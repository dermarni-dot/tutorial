-- Activities: every training session and its minigame.
-- A session is a short structured workout: rounds or sets with rests in between, a live
-- heart-rate / calorie readout and the drill's own numbers on the panel (and on the smart
-- screens), coach technique tips during the rests, and a graded result with personal
-- bests (the server keeps the records).
--  combo     heavy bag: rhythm combinations (every punch on the beat of the last; the later ones called by number), power shots, speed burst
--  rhythm    speed bag: alternating rhythm that speeds up through the round, then doubles / triplets
--  reaction  double-end bag: react, slip & counter, then slip the bag's rebound off your own punch
--  mitts     mitt work: call & response - the coach calls the moves one at a time, feints must not be bitten on
--  shadow    mirror the coach: single moves on cue, then the called patterns copied in order
--  bench     keep the bar level as it drifts (one side is weaker), grind the sticking point, call the spotter
--  deadlift  set the back on the needle, drive through the knees, keep the grip squeezed
--  squat     sink (faster as you go) and stop in the depth zone, drive out of the hole in the bounce window
--  pullup    alternate arms through the bottom of the swing, go hollow to kill the swing
--  curls     tempo hold notes, one arm at a time (both at once is a swing)
--  medball   medicine ball: overhead slams on the pad, then a plank on the ball (shove it back in the green)
--  treadmill follow the program's speed and incline steps on the console
--  bike      a hill profile: pedal cadence in the band, gears for the gradient
--  rower     catch - drive - finish - recovery: the timing of every stroke at the piece's rate
--  ladder    stepped patterns: the drill's arrows reach the foot line on a quickening beat (reaction lights at the top level)
--  rope      basic bounce, boxer skip, double unders
--  icebath   full breaths from empty and long exhales against a cold-shock meter (cold waves)
--  stretch   four poses: hold the depth in a range that creeps deeper, never past it
--  massage   pick the sorest muscle groups off the body map, relax into the therapist's strokes
--  chamber   ride the pressure profile (pressurise / vent) and equalize the ears
--  sauna     the weight cut: stay in the heat for the water, step out before the red, sip
--  reps / pace / hold  the older shared lift / cardio / breathing drills (still playable)
--  course    roadwork loop      swim  pool lengths (both measured by the server)
-- Sparring opens the intensity picker and hands over to the fight client.
-- While you work the body shows it: Effort / LivePump (client-local attributes the Animator reads),
-- sweat drips onto the floor when your heart rate is high, the coaches react to great and sloppy
-- work, and the result screen lists every muscle part that grew, the pump and a FLEX button.
-- Gamepad: every drill plays on the controller with the fight layout (PAD_OF); VIEW / SHARE quits.
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local UI = require(Shared:WaitForChild("UI"))
-- the drills' judges: the same code scores the session on the server from this client's inputs
local DrillScore = require(Shared:WaitForChild("DrillScore"))
-- the pacing between a drill's segments: the server's replay holds the stream to the same numbers
local WAIT = DrillScore.WAIT
local State = require(script.Parent:WaitForChild("State"))
local GymVisuals = require(script.Parent:WaitForChild("GymVisuals"))
local BodyMap = require(script.Parent:WaitForChild("BodyMap"))
-- the Muscle Progression screen (registers State.open.Muscle: the report's MUSCLES button)
pcall(require, script.Parent:WaitForChild("MuscleScreen"))
-- coach reactions are a nice-to-have: the drills run without them
local okAmbience, Ambience = pcall(require, script.Parent:WaitForChild("Ambience"))
if not okAmbience then
	Ambience = nil
end
local T = UI.Theme
local K = Enum.KeyCode
-- the fight's control map (Settings.Keymap + Keymap.Keys / ActionText): a drill prompts and listens
-- for the keys the ring uses, a custom map included. Without the modules the drills keep their own lists.
local Keymap, Settings
do
	local km = Shared:FindFirstChild("Keymap")
	local ok, m = false, nil
	if km then
		ok, m = pcall(require, km)
	end
	Keymap = (ok and type(m) == "table" and type(m.Keys) == "function") and m or nil
	local sm = script.Parent:FindFirstChild("Settings")
	ok, m = false, nil
	if sm then
		ok, m = pcall(require, sm)
	end
	Settings = (ok and type(m) == "table" and type(m.Keymap) == "function") and m or nil
end
local Gamepad = UI.Gamepad -- input device and button names (optional)

local Activities = {}
local player = Players.LocalPlayer
local current = nil

local TIME_SCALE = Config.TrainingTimeScale or 6 -- training seconds per real second (kcal, distance, time-in)
local DOT = " · "
local PANEL_H = 314
local PANEL_W = 660
local SIDE_W = 212 -- the "muscles worked" card beside the panel
local STAGE_Y = 92
local STAGE_H = 120
local STUD_M = 0.28 -- metres per stud (roadwork distance)

-- names ({ text, rich }) as whole lines that fit `width` x `height` design px at obj's readability
-- floor: a name is never split or cut ("UPPER / CHEST +2.30"); what has no room ends as "+N MORE"
local NAME_SEP = "  ·  "
local function capsW(text, px)
	-- capitals run ~0.8 em in the bold face ("KNOCKOUT POWER" 10.5 em), wider than the kit's 0.6 em
	-- floor for body text: count them (digits ~0.64, spaces and marks ~0.34)
	local _, caps = string.gsub(text, "%u", "")
	local _, digits = string.gsub(text, "%d", "")
	local rest = (utf8.len(text) or #text) - caps - digits
	return math.max(UI.TextWidth(text, px, T.semi), math.ceil(px * (caps * 0.8 + digits * 0.64 + rest * 0.34)))
end
local function packNames(obj, names, size, width, height)
	local px = math.max(size, UI.TextFloor(UI.ScaleOf(obj)))
	local maxLines = math.max(1, math.floor(height / (px * 1.1)))
	local function fit(s)
		return capsW(s, px) <= width
	end
	for n = #names, 1, -1 do
		local lines, plain, rich = {}, nil, nil
		for i = 1, n do
			local it = names[i]
			if plain and fit(plain .. NAME_SEP .. it.text) then
				plain, rich = plain .. NAME_SEP .. it.text, rich .. NAME_SEP .. (it.rich or it.text)
			else
				if rich then
					table.insert(lines, rich)
				end
				plain, rich = it.text, it.rich or it.text
			end
		end
		if n < #names then
			local more = string.format("+%d MORE", #names - n)
			if fit(plain .. NAME_SEP .. more) then
				rich ..= NAME_SEP .. more
			else
				table.insert(lines, rich)
				rich = more
			end
		end
		table.insert(lines, rich)
		if #lines <= maxLines or n == 1 then
			return table.concat(lines, "\n")
		end
	end
	return ""
end
-- how hard each drill works you even between presses (heart-rate effort floor, 0..1)
local BASE_EFFORT = { combo = 0.45, rhythm = 0.3, reaction = 0.5, mitts = 0.55, shadow = 0.45, ladder = 0.45, rope = 0.45, medball = 0.5,
	pullup = 0.4, curls = 0.35, treadmill = 0.5, bike = 0.45, rower = 0.55 }
-- the pose to strike when you press FLEX after a session (Config.Pump.poses), by exercise
local FLEX_FOR = { Bench = "flex_chest", Dumbbells = "flex_biceps", PullUps = "flex_lat", Barbell = "flex_most", Squat = "flex_most", MedBall = "flex_abs",
	HeavyBag = "flex_most", MittWork = "flex_biceps" }

-- a decaying station-camera kick on heavy shots (set by ctx.impact, read by stationCamera)
local camKick = { t = 0, amp = 0 }
-- where the station camera puts the athlete across the screen (0..1; ctx.layout sets it: the middle of
-- the space the panels leave)
local camFrame = { fx = 0.5 }
local pumpFadeToken = 0 -- a new session stops the previous session's pump fade

-- every pose attribute a drill may write on the character (cleared when the session ends); AnimGym reads them
local POSE_ATTRS = { "PoseDrive", "PoseSpeed", "RepCount", "RopeSpin", "RopeFoot", "Effort", "TwistSide", "PoseTilt", "PoseSet", "PoseGrip",
	"PoseSwing", "CurlSide", "PoseIncline", "PoseClimb", "PoseLungs", "PoseShiver", "PoseStretch", "PoseHeat" }
-- the drills' arrows and symbols in one place (plain text today; icons can be swapped in here)
local GLYPH = { up = "^", down = "v", left = "<", right = ">", next = ">", prev = "<", line = "|", dot = "-" }
local DARK = Color3.fromRGB(28, 30, 38) -- the drills' empty tracks and gauges

local WINDUP = { jab = 0.16, cross = 0.22, leadhook = 0.24, rearhook = 0.26, uppercut = 0.26, overhand = 0.34 }
local HAND = { jab = "L", cross = "R", leadhook = "L", rearhook = "R", uppercut = "R", overhand = "R" }
local POWER = { jab = 0.55, cross = 0.9, leadhook = 0.95, rearhook = 1.05, uppercut = 1.0, overhand = 1.25 }

-- map = the fight action whose bindings the drill uses (resolveAction); keys / pad = the fallback
local PUNCH_ACTIONS = {
	{ id = "jab", label = "JAB", keys = { K.J, K.One }, map = "jab" },
	{ id = "cross", label = "CROSS", keys = { K.K, K.Two }, map = "cross" },
	{ id = "leadhook", label = "L.HOOK", keys = { K.L, K.Three }, map = "leadhook" },
	{ id = "rearhook", label = "R.HOOK", keys = { K.Four, K.Semicolon }, map = "rearhook" },
	{ id = "uppercut", label = "UPPER", keys = { K.U, K.Five }, map = "uppercut" },
	{ id = "overhand", label = "OVERHAND", keys = { K.O, K.Six }, map = "overhand" },
}
local DEFENSE_ACTIONS = {
	{ id = "slipL", label = "SLIP L", keys = { K.Q }, map = "slipL" },
	{ id = "slipR", label = "SLIP R", keys = { K.E }, map = "slipR" },
	{ id = "roll", label = "ROLL", keys = { K.C }, map = "dodge" },
	{ id = "pivotL", label = "PIVOT", keys = { K.Z }, map = "pivotL" },
	{ id = "parry", label = "PARRY", keys = { K.R }, map = "parry" },
}
local KEYNAME = { [K.J] = "J", [K.K] = "K", [K.L] = "L", [K.Four] = "4", [K.U] = "U", [K.O] = "O", [K.Q] = "Q", [K.E] = "E",
	[K.C] = "C", [K.Z] = "Z", [K.R] = "R", [K.Space] = "SPACE", [K.W] = "W", [K.A] = "A", [K.S] = "S", [K.D] = "D", [K.F] = "F", [K.G] = "G" }
-- gamepad: the buttons for every keyboard key a drill binds, laid out like the fight controls - X jab,
-- Y cross, B lead hook, A rear hook, RT uppercut, RB overhand; right-stick flicks slip (left / right) and
-- roll (down), RS click / D-pad left pivot, D-pad up parry; the D-pad steps (W/A/S/D) and taps the rope
-- feet. The speed bag's LEFT / RIGHT hands are X / Y like the jab and cross. The flicks ride on the
-- Thumbstick2Left / Right / Down / Up KeyCodes in ctx.padmap.
local PAD_OF = {
	[K.J] = { K.ButtonX }, [K.One] = { K.ButtonX }, [K.F] = { K.ButtonX },
	[K.K] = { K.ButtonY }, [K.Two] = { K.ButtonY }, [K.G] = { K.ButtonY },
	[K.L] = { K.ButtonB }, [K.Three] = { K.ButtonB },
	[K.Four] = { K.ButtonA }, [K.Semicolon] = { K.ButtonA },
	[K.U] = { K.ButtonR2 }, [K.Five] = { K.ButtonR2 },
	[K.O] = { K.ButtonR1 }, [K.Six] = { K.ButtonR1 },
	[K.Q] = { K.Thumbstick2Left }, [K.E] = { K.Thumbstick2Right }, [K.C] = { K.Thumbstick2Down },
	[K.Z] = { K.ButtonR3, K.DPadLeft }, [K.R] = { K.DPadUp, K.Thumbstick2Up },
	[K.W] = { K.DPadUp }, [K.Up] = { K.DPadUp }, [K.S] = { K.DPadDown }, [K.Down] = { K.DPadDown },
	[K.A] = { K.DPadLeft }, [K.Left] = { K.DPadLeft }, [K.D] = { K.DPadRight }, [K.Right] = { K.DPadRight },
}
-- SPACE (lift, slam, jump, pace, breathe, continue) takes A, or LT when the drill already gave A a punch
-- (the heavy bag's POWER shot next to the rear hook)
local PAD_SPACE = { K.ButtonA, K.ButtonL2 }
local FLICK_KEY = { L = K.Thumbstick2Left, R = K.Thumbstick2Right, D = K.Thumbstick2Down, U = K.Thumbstick2Up }

-- the drill's instructions name keyboard keys; on a gamepad they name the buttons PAD_OF gives them
local function padInfo(ctx, text)
	local L = Gamepad.Label
	local space = L(ctx.spacePad or K.ButtonA)
	text = text:gsub("W/A/S/D or arrows", "the D-pad")
	text = text:gsub("%(W/A/S/D%)", "(D-pad)")
	text = text:gsub("%(Q/E/C%)", "(right-stick flicks)")
	text = text:gsub("%(J/K/L%)", "(" .. L(K.ButtonX) .. "/" .. L(K.ButtonY) .. "/" .. L(K.ButtonB) .. ")")
	text = text:gsub("%(J%)", "(" .. L(K.ButtonX) .. ")")
	text = text:gsub("%(K%)", "(" .. L(K.ButtonY) .. ")")
	text = text:gsub("Hold W", "Push the left stick")
	text = text:gsub("SPACE", space)
	return text
end

-- on touch the instructions name the drill's own buttons (the bound action's label; `say` when the
-- label is not a word for a sentence) and the thumbstick, never a keyboard key
local function touchInfo(ctx, text)
	local space = ctx.spaceSay and ("the " .. ctx.spaceSay .. " button") or "the button"
	text = text:gsub(" %(SPACE%)", "")
	text = text:gsub("SPACE %(or [%w ]+%)", space)
	text = text:gsub("SPACE", space)
	text = text:gsub("W/A/S/D or arrows", "the direction buttons")
	text = text:gsub(" %(W/A/S/D%)", "")
	text = text:gsub("Hold W", "Push the thumbstick forward")
	text = text:gsub(" %(%u/%u/%u%)", "")
	text = text:gsub(" %(%u%)", "")
	text = text:gsub(" %(%)", "")
	-- "LEFT (LEFT)": a token that came out as the word before it
	text = text:gsub("([%u][%u%.]*) %(([%u][%u%. ]*)%)", function(a, b)
		if a == b then
			return a
		end
		return nil
	end)
	return text
end

-- the resolved control map, or nil when the modules are not there
local function controlMap()
	if not (Keymap and Settings) then
		return nil
	end
	local ok, map = pcall(Settings.Keymap)
	return (ok and type(map) == "table") and map or nil
end
-- the prompt name of a fight action on a device ("LMB / J", "X", "RS left"); a drill's instructions
-- carry {jab}-style tokens that infoFor expands for the device in use. The defaults when unmapped.
local FALLBACK_KEY = { jab = "J", cross = "K", leadhook = "L", rearhook = "4", uppercut = "U", overhand = "O", slipL = "Q", slipR = "E", dodge = "C", parry = "R", pivotL = "Z" }
local FALLBACK_PAD = { jab = K.ButtonX, cross = K.ButtonY, leadhook = K.ButtonB, rearhook = K.ButtonA, uppercut = K.ButtonR2, overhand = K.ButtonR1,
	slipL = K.Thumbstick2Left, slipR = K.Thumbstick2Right, dodge = K.Thumbstick2Down, parry = K.DPadUp, pivotL = K.DPadLeft }
-- the names of an action's plain keyboard bindings ("J / LMB"): the keys a drill really listens for
-- (Keymap.Keys skips chords and double taps, which a drill cannot take); first = the main one only
local function plainKeyText(map, ids, first)
	local names = {}
	for _, id in ipairs(type(ids) == "table" and ids or { ids }) do
		local ok, list = pcall(Keymap.Keys, map, id, "kbd")
		for _, k in ipairs(ok and list or {}) do
			local okN, n = pcall(Keymap.KeyName, k.Name)
			n = okN and n or k.Name
			if not table.find(names, n) then
				table.insert(names, n)
			end
		end
	end
	if first then
		return names[1]
	end
	return #names > 0 and table.concat(names, " / ") or nil
end
local function keyText(id, mode)
	local dev = mode == "gamepad" and "pad" or "kbd"
	local map = controlMap()
	if map then
		if dev == "kbd" then
			-- (an instruction names the main key: "({jab}/{cross})" reads "(LMB/RMB)"; the buttons list them all)
			local t = plainKeyText(map, id, true)
			if t then
				return t
			end
		end
		local ok, t = pcall(Keymap.ActionText, map, id, dev, Gamepad)
		if ok and type(t) == "string" and t ~= "-" then
			return t
		end
	end
	if dev == "pad" and FALLBACK_PAD[id] and Gamepad then
		return Gamepad.Label(FALLBACK_PAD[id])
	end
	return FALLBACK_KEY[id] or string.upper(id)
end
-- the drill's input stream: every input a drill takes (id, down, t on the drill clock) and "@" when a
-- segment starts. The server replays it through DrillScore on its own copy of the plan: that is the
-- session's quality (Main.server.lua ActivityInput / finishActivity).
local inputRemote
local function sendInput(ctx, id, down, t)
	if ctx.mode == "done" or not current then
		return
	end
	if inputRemote == nil then
		local r = State.Remotes and State.Remotes:FindFirstChild("ActivityInput")
		inputRemote = (r and r:IsA("RemoteEvent")) and r or false
	end
	if inputRemote then
		inputRemote:FireServer(current.token, id, down, t)
	end
end
-- an action with a map id (or a list of them) gets the control map's keys: the keyboard's plain
-- bindings, the pad's button or right-stick flick and the prompt text; its own lists stay as the
-- fallback for an action left unbound on purpose. The constant tables are never changed.
local function resolveAction(a)
	local map = a.map and controlMap()
	if not map then
		return a
	end
	local ids = type(a.map) == "table" and a.map or { a.map }
	local keys, pad = {}, {}
	for _, id in ipairs(ids) do
		local ok, list = pcall(Keymap.Keys, map, id, "kbd")
		for _, k in ipairs(ok and list or {}) do
			table.insert(keys, k)
		end
		ok, list = pcall(Keymap.Keys, map, id, "pad")
		for _, k in ipairs(ok and list or {}) do
			table.insert(pad, k)
		end
	end
	local r = table.clone(a)
	if #keys > 0 then
		r.keys = keys
		-- the button names only the keys bound here (a "2x A" double tap never reaches a drill)
		r.keyText = plainKeyText(map, ids)
	end
	if #pad > 0 then
		r.pad = pad
	end
	return r
end

-- the boxing numbers a coach calls combinations by
local PUNCH_NUMBER = { jab = "1", cross = "2", leadhook = "3", rearhook = "4", uppercut = "5", overhand = "6" }
local LABEL = { jab = "JAB", cross = "CROSS", leadhook = "L.HOOK", rearhook = "R.HOOK", uppercut = "UPPER", overhand = "OVERHAND",
	slipL = "SLIP L", slipR = "SLIP R", roll = "ROLL", pivotL = "PIVOT", parry = "PARRY",
	F = "STEP IN", B = "STEP BACK", L = "CIRCLE L", R = "CIRCLE R" }

local function actionList(...)
	local out = {}
	for _, list in ipairs({ ... }) do
		for _, a in ipairs(list) do
			table.insert(out, a)
		end
	end
	return out
end

-- 1240 -> "1,240"
local function fmtInt(n)
	local s = tostring(math.max(0, math.floor((tonumber(n) or 0) + 0.5)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

-- 5.30 -> "5.3", 12 -> "12", 1500 -> "1,500"
local function fmtNum(v)
	v = tonumber(v) or 0
	if v >= 100 or v % 1 == 0 then
		return fmtInt(v)
	end
	local s = string.format("%.2f", v)
	s = (s:gsub("0+$", ""))
	s = (s:gsub("%.$", ""))
	return s
end

-- 75 -> "1:15"
local function clock(sec)
	sec = math.max(0, math.floor((tonumber(sec) or 0) + 0.5))
	return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function gradeColor(id)
	local g = Config.GradeInfo(id)
	return Color3.fromRGB(g.rgb[1], g.rgb[2], g.rgb[3])
end

------------------------------------------------------------------------
-- Session context (UI + input + heart rate + local animation helpers)
------------------------------------------------------------------------
local function newContext(info)
	local P = State.P
	local ctx = {
		level = info.level or 1, params = info.params or {}, act = info.act, station = info.station, plan = info.plan or { segs = {} },
		segI = 0, judges = {}, results = {}, clock0 = os.clock(),
		handler = nil, keymap = {}, padmap = {}, conns = {}, buttons = {}, cleanups = {},
		out = {}, -- drill numbers sent with the result (display / personal bests only)
		lines = {}, -- the one-line session summary on the result screen
		tipIndex = math.random(0, 5), mode = "work", resting = false, baseEffort = info.baseEffort,
	}
	ctx.smart = ctx.params.smart == true
	-- the stats before the session: the result's popups show old -> new
	ctx.stats0 = {}
	for _, k in ipairs(Config.StatKeys) do
		ctx.stats0[k] = tonumber(P and P.stats and P.stats[k]) or 0
	end
	ctx.body0 = {}
	for _, part in ipairs(Config.MuscleParts) do
		ctx.body0[part.id] = tonumber(P and P.body and (Config.PartValue and Config.PartValue(P.body, part.id) or P.body[part.id])) or 0
	end
	do
		local frame = P and P.appearance and P.appearance.body and P.appearance.body.frame
		local def = Config.FindById(Config.BodyTypes, frame or "") or Config.BodyTypes[2]
		ctx.cap = 100 * (def.potential or 1)
	end
	-- the panel docks bottom-right (the athlete stays clear in the middle of the screen); ctx.layout
	local panel = UI.Frame(State.gui, { Name = "Activity", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.new(0.96, 0, 0, PANEL_H) })
	ctx.panelMax = UI.New("UISizeConstraint", { MaxSize = Vector2.new(PANEL_W, PANEL_H), Parent = panel })
	UI.Glass(panel, { transparency = 0.05, radius = UI.R.xl })
	ctx.fit = UI.New("UIScale", { Name = "Fit", Parent = panel })
	-- a gold rule along the top edge (the broadcast panel look)
	local rule = UI.Frame(panel, { Name = "Rule", Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -36, 0, 2), BackgroundColor3 = T.gold })
	UI.Gradient(rule, Color3.new(1, 1, 1), 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0), NumberSequenceKeypoint.new(0.8, 0), NumberSequenceKeypoint.new(1, 1) }))
	ctx.panel = panel
	ctx.title = UI.Text(panel, info.act.name:upper(), { Face = "display", TextSize = 24, TextColor3 = T.text, Position = UDim2.fromOffset(16, 6), Size = UDim2.new(0.42, -16, 0, 28), AutomaticSize = Enum.AutomaticSize.None, TextScaled = true, TextWrapped = false })
	UI.New("UITextSizeConstraint", { MaxTextSize = 24, MinTextSize = 12, Parent = ctx.title })
	-- the drill's own live numbers (heart rate, calories and the set live on the metrics strip)
	ctx.live = UI.Text(panel, "", { Font = T.semi, TextSize = 13, RichText = true, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -112, 0, 4), Size = UDim2.new(0.58, -116, 0, 32), TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Center, TextScaled = true, TextWrapped = false, AutomaticSize = Enum.AutomaticSize.None })
	UI.New("UITextSizeConstraint", { MaxTextSize = 13, MinTextSize = 8, Parent = ctx.live })
	-- touch: the panel's buttons are a fingertip high (UI.MinHit), the input cells and QUIT included
	ctx.cellH = math.max(40, UI.MinHit(panel))
	local quitH = math.max(28, UI.MinHit(panel))
	-- a finger-high QUIT takes the end of the instruction lines: they get a line more of height, and
	-- everything under them moves down with it
	local topExtra = quitH > 28 and 18 or 0
	ctx.stageY = STAGE_Y + topExtra
	ctx.panelBase = PANEL_H + topExtra
	ctx.panelH = ctx.panelBase
	panel.Size = UDim2.new(0.96, 0, 0, ctx.panelH)
	ctx.panelMax.MaxSize = Vector2.new(PANEL_W, ctx.panelH)
	-- (two lines; a longer instruction ends in "..." instead of running into the round header)
	ctx.info = UI.Text(panel, "", { TextSize = 13, TextColor3 = T.sub, Position = UDim2.fromOffset(16, 36), Size = UDim2.new(1, quitH > 28 and -136 or -32, 0, 30 + topExtra), AutomaticSize = Enum.AutomaticSize.None, TextTruncate = Enum.TextTruncate.AtEnd })
	-- ROUND / SET header and the session progress
	ctx.header = UI.Text(panel, "", { Face = "displayMed", TextSize = 15, TextColor3 = T.gold, Position = UDim2.fromOffset(16, 66 + topExtra), Size = UDim2.new(1, -32, 0, 16), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	local progBg, setBar = UI.Bar(panel, { Position = UDim2.new(0, 16, 0, 84 + topExtra), Size = UDim2.new(1, -32, 0, 4) }, T.gold)
	progBg.BackgroundColor3 = T.ink
	-- (the result report re-lays the header out on a phone: ctx.sizeResult)
	ctx.progBg, ctx.quitW, ctx.topExtra = progBg, quitH > 28 and -136 or -32, topExtra
	-- the session's progress: the bar under the header and the TIME tile's fill
	local function setProg(f)
		setBar(f)
		if ctx.fillTile then
			ctx.fillTile("time", f)
		end
	end
	ctx.setProgress = setProg
	setProg(0)
	ctx.stage = UI.Frame(panel, { Name = "Stage", Position = UDim2.new(0, 14, 0, ctx.stageY), Size = UDim2.new(1, -28, 0, STAGE_H), BackgroundColor3 = Color3.fromRGB(8, 9, 13), ClipsDescendants = true })
	UI.Corner(ctx.stage, 8)
	UI.Stroke(ctx.stage, Color3.new(1, 1, 1), 1, 0.9)
	ctx.flash = UI.Text(panel, "", { Face = "display", TextSize = 30, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, -28, 0, 34), Position = UDim2.new(0, 14, 0, ctx.stageY + 84), ZIndex = 5, AutomaticSize = Enum.AutomaticSize.None, TextStrokeTransparency = 0.4 })
	ctx.inputBar = UI.Frame(panel, { BackgroundTransparency = 1, Position = UDim2.new(0, 14, 0, ctx.stageY + STAGE_H + 6), Size = UDim2.new(1, -28, 0, 88) })
	UI.Grid(ctx.inputBar, UDim2.new(1 / 6, -5, 0, ctx.cellH), nil, 5)
	ctx.quit = UI.Button(panel, "QUIT", { Size = UDim2.fromOffset(88, quitH), Position = UDim2.new(1, -104, 0, 8), BackgroundColor3 = T.red, TextSize = 14 }, function()
		ctx.cancelled = true
	end)
	-- the panel plays on its key maps: none of its buttons take Roblox's UI selection (a selected button
	-- would also take the A press)
	ctx.quit.Selectable = false
	ctx.quitText = "QUIT"
	UI.BindHint(ctx.quit, function(mode)
		return mode == "gamepad" and Gamepad and (ctx.quitText .. " · " .. Gamepad.Label(K.ButtonSelect)) or ctx.quitText
	end)

	-- metrics strip: SET | REP (or CLEAN) | GOOD (rep drills) | QUALITY | TIME | BPM (heart) | KCAL - the
	-- one place the session's counters live (above the panel; a column beside it on short screens)
	ctx.t0 = os.clock()
	ctx.tiles = {}
	ctx.qSum, ctx.qN, ctx.clean = 0, 0, 0
	local metrics = UI.Frame(panel, { Name = "Metrics", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 0, -8), Size = UDim2.new(1, 0, 0, 56) })
	ctx.metrics = metrics
	ctx.metricsGrid = UI.New("UIGridLayout", { CellSize = UDim2.new(1 / 6, -5, 1, 0), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = metrics })
	-- every progress tile carries a thin fill bar: the set / round, the rep, the good reps, the quality
	-- and the time through the session (bpm and kcal are readouts)
	local function tile(key, caption, order, barColor)
		local f = UI.Frame(metrics, { Name = key, LayoutOrder = order })
		UI.Glass(f, { transparency = 0.12, radius = UI.R.md })
		local cap = UI.Text(f, caption, { Font = T.semi, TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(10, 5), Size = UDim2.new(1, -20, 0, 14), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
		local val = UI.Text(f, "-", { Face = "number", TextSize = 24, Position = UDim2.fromOffset(10, 19), Size = UDim2.new(1, -20, 0, 30), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
		ctx.tiles[key] = { frame = f, cap = cap, val = val }
		if barColor then
			local bg = UI.Frame(f, { Name = "Bar", Position = UDim2.new(0, 10, 1, -8), Size = UDim2.new(1, -20, 0, 3), BackgroundColor3 = T.ink })
			UI.Corner(bg, 2)
			ctx.tiles[key].fill = UI.Frame(bg, { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = barColor })
			UI.Corner(ctx.tiles[key].fill, 2)
		end
		return ctx.tiles[key]
	end
	function ctx.fillTile(key, f)
		local t = ctx.tiles[key]
		if t and t.fill then
			t.fill.Size = UDim2.fromScale(math.clamp(tonumber(f) or 0, 0, 1), 1)
		end
	end
	tile("set", "SESSION", 1, T.blue)
	tile("reps", "CLEAN", 2, T.green)
	tile("good", "GOOD", 3, T.green).frame.Visible = false
	tile("quality", "QUALITY", 4, T.gold)
	tile("time", "TIME", 5, T.sub)
	tile("hr", "BPM", 6)
	tile("kcal", "KCAL", 7)
	ctx.tileCount = 6
	function ctx.updateMetrics()
		local tl = ctx.tiles
		if ctx.repOf then
			tl.reps.cap.Text = "REP"
			tl.reps.val.Text = string.format("%d/%d", ctx.repOf[1], ctx.repOf[2])
			tl.good.val.Text = tostring(ctx.repOf[3] or 0)
			ctx.fillTile("reps", ctx.repOf[1] / math.max(1, ctx.repOf[2]))
			ctx.fillTile("good", (ctx.repOf[3] or 0) / math.max(1, ctx.repOf[2]))
		elseif ctx.reps then
			tl.reps.cap.Text = "REPS"
			tl.reps.val.Text = tostring(ctx.reps)
		else
			tl.reps.val.Text = tostring(ctx.clean)
			-- clean work against everything graded so far
			ctx.fillTile("reps", ctx.qN > 0 and ctx.clean / ctx.qN or 0)
		end
		-- a unit still in progress (a cardio interval, a breath) counts by the share of it done so far,
		-- so QUALITY moves from the first second instead of waiting for the first unit to end
		local n, sum, part = ctx.qN, ctx.qSum, ctx.partial
		if part and part.w > 0 then
			n += part.w
			sum += part.g * part.w
		end
		if n > 0 then
			local q = sum / n
			tl.quality.val.Text = string.format("%d%%", math.floor(q * 100 + 0.5))
			local col = q >= 0.85 and T.gold or (q >= 0.65 and T.green or (q >= 0.45 and T.orange or T.red))
			tl.quality.val.TextColor3 = col
			tl.quality.fill.BackgroundColor3 = col
			tl.quality.fill.Size = UDim2.fromScale(math.clamp(q, 0, 1), 1)
		end
	end

	-- rep drills: the strip shows REP r/n and GOOD (the stage and the header no longer repeat them)
	function ctx.setRep(r, n, good)
		ctx.repOf = { r, n, good }
		if not ctx.tiles.good.frame.Visible then
			ctx.tiles.good.frame.Visible = true
			ctx.tileCount = 7
			if ctx.layout then
				ctx.layout()
			end
		end
		ctx.updateMetrics()
	end
	-- back to a drill without reps (the GOOD tile goes, the second tile counts clean work)
	function ctx.clearRep()
		ctx.repOf, ctx.reps = nil, nil
		ctx.tiles.reps.cap.Text = "CLEAN"
		if ctx.tiles.good.frame.Visible then
			ctx.tiles.good.frame.Visible = false
			ctx.tileCount = 6
			if ctx.layout then
				ctx.layout()
			end
		end
		ctx.updateMetrics()
	end

	-- what this exercise works: the body map (Config.ExerciseTargets / act.parts), the top targets and
	-- the energy / fatigue it will cost; after the session the same card shows the growth
	local side = UI.Frame(panel, { Name = "Works", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(0, -12, 1, 0), Size = UDim2.fromOffset(SIDE_W, PANEL_H) })
	UI.Glass(side, { transparency = 0.06, radius = UI.R.xl })
	ctx.side = side
	local recovery = type(info.act.recovery) == "table" and info.act.recovery or nil
	local sideKicker = UI.Kicker(side, recovery and "Recovery" or "Muscles worked", recovery and T.cyan or T.red, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 16) })
	ctx.sideCaption = sideKicker:FindFirstChildOfClass("TextLabel")
	ctx.sideTick = sideKicker:FindFirstChildOfClass("Frame")
	-- the names under the figure: three lines, or five for a whole-body drill (the heavy bag lights nine
	-- regions); the figure gives up the difference
	local nLit = 0
	for _, w in pairs(type(info.act.parts) == "table" and info.act.parts or {}) do
		if (tonumber(w) or 0) > 0 then
			nLit += 1
		end
	end
	local listH = (not recovery and nLit > 5) and 78 or 50
	local okMap, map = pcall(BodyMap.new, side, { Size = UDim2.fromOffset(SIDE_W - 28, 176 - (listH - 50)), Position = UDim2.fromOffset(14, 30) })
	ctx.map = okMap and map or nil
	ctx.sideList = UI.Frame(side, { Name = "Targets", BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 260 - listH), Size = UDim2.new(1, -28, 0, listH), ClipsDescendants = true })
	-- every lit region by its short name, the strongest in white (wraps; the map and the list match)
	function ctx.sideNames(list, strongColor)
		UI.Clear(ctx.sideList)
		local names = {}
		for _, e in ipairs(list) do
			local name = string.upper(BodyMap.Short(e.id))
			table.insert(names, { text = name, rich = e.w >= 0.75 and string.format('<font color="#%s">%s</font>', (strongColor or T.text):ToHex(), name) or nil })
		end
		local box = ctx.sideList.Size
		UI.Text(ctx.sideList, packNames(ctx.sideList, names, 12, SIDE_W - 28, box.Y.Offset), { Font = T.semi, TextSize = 12, TextColor3 = T.sub, RichText = true, Size = UDim2.fromScale(1, 1),
			AutomaticSize = Enum.AutomaticSize.None, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	end
	-- rows: { name, value text, fraction, color } (recovery: what the session restores)
	function ctx.sideRows(rows)
		UI.Clear(ctx.sideList)
		UI.List(ctx.sideList, 2)
		for i, r in ipairs(rows) do
			local row = UI.Frame(ctx.sideList, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = i })
			UI.Text(row, string.upper(r[1]), { Font = T.semi, TextSize = 12, TextColor3 = T.text, Size = UDim2.new(0.6, 0, 0, 14), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
			UI.Text(row, r[2] or "", { Face = "number", TextSize = 13, TextColor3 = r[4] or T.sub, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.4, 0, 0, 14), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
		end
	end
	local targets = info.act.parts or {}
	if recovery then
		-- recovery works the whole body: everything glows a cool cyan
		local all = {}
		for _, p in ipairs(Config.MuscleParts) do
			all[p.id] = 0.5
		end
		if ctx.map then
			ctx.map:SetTargets(all, T.cyan, 1)
		end
		local rows = {}
		if recovery.fatigue then
			table.insert(rows, { "Fatigue", string.format("%+d", recovery.fatigue), math.min(1, math.abs(recovery.fatigue) / 50), recovery.fatigue < 0 and T.green or T.orange })
		end
		if recovery.energy then
			table.insert(rows, { "Energy", string.format("%+d", recovery.energy), math.min(1, math.abs(recovery.energy) / 30), recovery.energy > 0 and T.green or T.red })
		end
		if recovery.heal and recovery.heal > 0 then
			table.insert(rows, { "Injury healing", string.format("x%.1f", recovery.heal), math.min(1, recovery.heal / 2), T.cyan })
		end
		ctx.sideRows(rows)
	else
		if ctx.map then
			ctx.map:SetTargets(targets, T.red)
		end
		-- the list names exactly what the map lights (strongest first; primary targets in red)
		local list, max = {}, 0
		for id, w in pairs(targets) do
			w = tonumber(w) or 0
			if w > 0 then
				table.insert(list, { id = id, w = w })
				max = math.max(max, w)
			end
		end
		for _, e in ipairs(list) do
			e.w = max > 0 and e.w / max or 0
		end
		table.sort(list, function(a, b)
			if a.w ~= b.w then
				return a.w > b.w
			end
			return a.id < b.id
		end)
		ctx.workList = list
		ctx.sideNames(list, T.red)
	end
	-- a phone has no room for the card beside the panel: a strip over the panel names what the exercise
	-- works, with a small map (ctx.layout shows it when the card is hidden; the report hides it)
	do
		local works = UI.Frame(panel, { Name = "WorksStrip", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 0, -6), Size = UDim2.new(1, 0, 0, 44), Visible = false })
		UI.Glass(works, { transparency = 0.1, radius = UI.R.md })
		local okMini, mini = pcall(BodyMap.new, works, { Size = UDim2.fromOffset(28, 40), Position = UDim2.fromOffset(8, 2), views = "front", labels = false, glow = false })
		local bits = {}
		if recovery then
			if okMini and mini then
				local all = {}
				for _, p in ipairs(Config.MuscleParts) do
					all[p.id] = 0.5
				end
				mini:SetTargets(all, T.cyan, 1)
			end
			table.insert(bits, string.format('<font color="#%s">RECOVERY</font>', T.cyan:ToHex()))
			if recovery.fatigue then
				table.insert(bits, string.format("FATIGUE %+d", recovery.fatigue))
			end
			if recovery.energy then
				table.insert(bits, string.format("ENERGY %+d", recovery.energy))
			end
		else
			if okMini and mini then
				mini:SetTargets(targets, T.red)
			end
			table.insert(bits, string.format('<font color="#%s">WORKS</font>', T.red:ToHex()))
			for _, e in ipairs(ctx.workList or {}) do
				local name = string.upper(BodyMap.Short(e.id))
				table.insert(bits, e.w >= 0.75 and string.format('<font color="#%s">%s</font>', T.text:ToHex(), name) or name)
			end
		end
		UI.Text(works, table.concat(bits, "  ·  "), { Name = "Names", Font = T.semi, TextSize = 13, TextColor3 = T.sub, RichText = true, Position = UDim2.fromOffset(okMini and 44 or 12, 0), Size = UDim2.new(1, okMini and -52 or -24, 1, 0),
			AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextYAlignment = Enum.TextYAlignment.Center })
		ctx.works = works
	end
	-- energy and fatigue: now, with what the session will cost striped on top
	-- fromBottom: the caption's distance from the card's bottom edge (the card grows on the result screen)
	local function condBar(fromBottom, caption, color)
		UI.Text(side, caption, { Font = T.semi, TextSize = 11, TextColor3 = T.sub, Position = UDim2.new(0, 14, 1, -fromBottom), Size = UDim2.new(0.5, -14, 0, 14), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
		local val = UI.Text(side, "", { Face = "number", TextSize = 13, TextColor3 = T.text, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 1, -fromBottom - 1), Size = UDim2.new(0.5, -14, 0, 14), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false, RichText = true })
		local bg = UI.Frame(side, { Position = UDim2.new(0, 14, 1, -fromBottom + 15), Size = UDim2.new(1, -28, 0, 5), BackgroundColor3 = T.ink })
		UI.Corner(bg, 2)
		local fill = UI.Frame(bg, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = color })
		UI.Corner(fill, 2)
		local cost = UI.Frame(bg, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.35, Visible = false })
		return { val = val, fill = fill, cost = cost }
	end
	ctx.energyBar = condBar(52, "ENERGY", T.green)
	ctx.fatigueBar = condBar(28, "FATIGUE", T.orange)
	-- delta > 0 adds (fatigue), < 0 takes away (energy cost); the change shows as a white segment.
	-- showAfter: the label shows the value after the change (the result screen) instead of now
	local function round(v)
		return v >= 0 and math.floor(v + 0.5) or -math.floor(-v + 0.5)
	end
	function ctx.setCond(bar, now, delta, goodUp, showAfter)
		now = math.clamp(tonumber(now) or 0, 0, 100)
		delta = tonumber(delta) or 0
		local after = math.clamp(now + delta, 0, 100)
		bar.fill.Size = UDim2.fromScale(math.min(now, after) / 100, 1)
		bar.cost.Visible = math.abs(after - now) >= 0.5
		bar.cost.Position = UDim2.fromScale(math.min(now, after) / 100, 0)
		bar.cost.Size = UDim2.fromScale(math.abs(after - now) / 100, 1)
		local good = (delta > 0) == goodUp
		local d = round(after - now)
		local tag = d ~= 0 and string.format('  <font color="#%s">%+d</font>', (good and T.green or T.red):ToHex(), d) or ""
		bar.val.Text = string.format("%d%s", round(showAfter and after or now), tag)
	end
	local cond0 = P and P.condition or {}
	ctx.cond0 = { energy = tonumber(cond0.energy) or 0, fatigue = tonumber(cond0.fatigue) or 0 }
	if recovery then
		ctx.setCond(ctx.energyBar, cond0.energy, recovery.energy or 0, true)
		ctx.setCond(ctx.fatigueBar, cond0.fatigue, recovery.fatigue or 0, false)
	else
		ctx.setCond(ctx.energyBar, cond0.energy, -(tonumber(info.act.energy) or 0), true)
		ctx.setCond(ctx.fatigueBar, cond0.fatigue, tonumber(info.act.fatigue) or 0, false)
	end

	-- responsive: the panel docks bottom-right at its design size (nothing is scaled down, so no text
	-- drops under the readability floor). Wide screens: the metrics strip on top of the panel, the
	-- "muscles worked" card at the left edge, the camera puts the athlete in the clear middle. Short
	-- (phone) screens: the metrics as a column beside the panel, the card only where it fits.
	function ctx.layout()
		if not panel.Parent then
			return
		end
		local canvas = UI.CanvasSize(panel)
		local compact = canvas.Y < 640
		ctx.fit.Scale = 1
		local margin = compact and 8 or 16
		local panelW = math.min(PANEL_W, canvas.X * 0.96)
		panel.AnchorPoint = Vector2.new(1, 1)
		panel.Position = UDim2.new(1, -margin, 1, -margin)
		local panelLeft = canvas.X - margin - panelW
		local n = ctx.tileCount or 6
		local sideH = side.Size.Y.Offset
		if compact then
			local colW = 150
			metrics.AnchorPoint = Vector2.new(1, 1)
			metrics.Position = UDim2.new(0, -10, 1, 0)
			metrics.Size = UDim2.new(0, colW, 1, 0)
			ctx.metricsGrid.CellSize = UDim2.new(1, 0, 1 / n, -math.ceil(6 * (n - 1) / n))
			for _, t in pairs(ctx.tiles) do
				-- one line per tile: caption left, number right (a wide number like "100%" scales down
				-- into its slot instead of running over the caption)
				t.cap.Position, t.cap.Size = UDim2.new(0, 10, 0.5, -8), UDim2.new(0.55, -10, 0, 16)
				t.val.Position, t.val.Size = UDim2.new(0.55, 0, 0.5, -14), UDim2.new(0.45, -10, 0, 28)
				t.val.TextXAlignment = Enum.TextXAlignment.Right
				t.val.TextScaled = true
				if not t.valFit then
					t.valFit = UI.New("UITextSizeConstraint", { MaxTextSize = 24, MinTextSize = 12, Parent = t.val })
				end
			end
			local room = panelLeft - 10 - colW - 10 - margin
			side.Visible = room >= SIDE_W
			if ctx.works then
				-- (the strip over the panel only where the panel leaves room for it under the top of the screen:
				-- a drill with two rows of finger-sized buttons on a small phone has none)
				local panelTop = canvas.Y - margin - (ctx.compactRun and panel.Size.Y.Offset or ctx.panelH or PANEL_H)
				ctx.works.Visible = not side.Visible and not ctx.sizeResult and panelTop - 50 >= 0
			end
			side.AnchorPoint = Vector2.new(1, 1)
			side.Position = UDim2.new(0, -(10 + colW + 10), 1, 0)
			camFrame.fx = 0.5
		else
			metrics.AnchorPoint = Vector2.new(0, 1)
			metrics.Position = UDim2.new(0, 0, 0, -8)
			metrics.Size = UDim2.new(1, 0, 0, 56)
			-- n cells and n - 1 gaps of 6 fill the width exactly (a 7th tile must not wrap)
			ctx.metricsGrid.CellSize = UDim2.new(1 / n, -math.ceil(6 * (n - 1) / n), 1, 0)
			for _, t in pairs(ctx.tiles) do
				t.cap.Position, t.cap.Size = UDim2.fromOffset(10, 5), UDim2.new(1, -20, 0, 14)
				t.val.Position, t.val.Size = UDim2.fromOffset(10, 19), UDim2.new(1, -20, 0, 30)
				t.val.TextXAlignment = Enum.TextXAlignment.Left
				t.val.TextScaled = false
			end
			side.Visible = true
			if ctx.works then
				ctx.works.Visible = false
			end
			side.AnchorPoint = Vector2.new(0, 1)
			side.Position = UDim2.new(0, margin - panelLeft, 1, 0)
			-- the athlete in the middle of the space between the card and the panel
			local leftEdge = margin + SIDE_W + 16
			camFrame.fx = math.clamp(((leftEdge + panelLeft) / 2) / canvas.X, 0.3, 0.5)
		end
		side.Size = UDim2.fromOffset(SIDE_W, sideH)
		if ctx.sizeResult then
			-- the result report: the panel's height follows the screen; a growth card built taller
			-- than a short screen steps aside
			ctx.sizeResult()
			if compact and sideH > canvas.Y - 16 then
				side.Visible = false
			end
		end
	end
	ctx.layout()
	table.insert(ctx.conns, State.screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(ctx.layout))
	-- the HUD plate would sit behind the panel: hide it while the session runs
	State.HideHud("Activity", true)

	local function infoFor(mode)
		local text = (ctx.infoRaw or ""):gsub("{(%w+)}", function(id)
			-- a drill's own action (the rope's feet): its key, its pad button, nothing on touch
			if ctx.ownKey and ctx.ownKey[id] then
				return ctx.ownKeyText(id, mode) or ""
			end
			-- touch: the drill's own button for that fight action (its LEFT / SLIP LEFT / ROLL ...)
			if mode == "touch" then
				return ctx.labelOf and ctx.labelOf[id] or string.upper(LABEL[id] or id)
			end
			return keyText(id, mode)
		end)
		if mode == "gamepad" and Gamepad then
			return padInfo(ctx, text)
		elseif mode == "touch" then
			return touchInfo(ctx, text)
		end
		return text
	end
	function ctx.setInfo(text)
		ctx.infoRaw = text
		UI.BindHint(ctx.info, infoFor)
	end
	local lastReact = 0
	-- feedback colours grade the work: gold great, green good, orange sloppy, red a miss
	local GRADE_OF = { [T.gold] = 1, [T.green] = 0.8, [T.orange] = 0.45, [T.red] = 0 }
	-- one graded piece of work on the strip (0..1, on the colours' scale above): QUALITY averages them,
	-- CLEAN counts the good ones (0.8 and up). Drills measured as they go (a cardio interval's time in
	-- the zone, a breath in sync) grade each unit with its own number
	function ctx.grade(score)
		ctx.partial = nil
		if ctx.mode == "done" then
			return
		end
		ctx.qN += 1
		ctx.qSum += score
		if score >= 0.8 then
			ctx.clean += 1
		end
		ctx.updateMetrics()
	end
	-- the colour a 0..1 grade flashes in (the reverse of GRADE_OF)
	function ctx.gradeColor(g)
		return g >= 0.95 and T.gold or (g >= 0.8 and T.green or (g >= 0.45 and T.orange or T.red))
	end
	-- score: the grade when it is not the colour's own (a measured unit)
	function ctx.feedback(text, color, score)
		ctx.flash.Text = text
		ctx.flash.TextColor3 = color or T.text
		if score == nil then
			for c, v in pairs(GRADE_OF) do
				if color == c then
					score = v
				end
			end
		end
		if score then
			ctx.grade(score)
		end
		local id = os.clock()
		ctx.flashId = id
		task.delay(0.8, function()
			if ctx.flashId == id and ctx.flash.Parent then
				ctx.flash.Text = ""
			end
		end)
		-- a coach nearby shouts at gold (great) and red (sloppy) moments - not every single one
		if Ambience and Ambience.React and (color == T.gold or color == T.red) and id - lastReact > 4 and math.random() < 0.6 then
			lastReact = id
			pcall(Ambience.React, nil, color == T.gold and "good" or "bad")
		end
	end
	-- the session summary (result screen) and the numbers sent to the server
	function ctx.note(text)
		table.insert(ctx.lines, text)
	end
	function ctx.put(key, value)
		if type(value) == "number" and value == value and value > -math.huge and value < math.huge then
			ctx.out[key] = value
		end
	end
	function ctx.onDestroy(fn)
		table.insert(ctx.cleanups, fn)
	end

	-- heart rate & calories: resting HR from fatigue and fitness, rising toward the drill's working
	-- HR (faster with more input), dropping during rests; kcal integrated from the heart rate
	local cond = P and P.condition or {}
	local pstats = P and P.stats or {}
	local age = P and P.identity and P.identity.age or 22
	ctx.restHR = math.clamp(66 + (cond.fatigue or 20) * 0.14 - ((pstats.Stamina or 40) - 40) * 0.15, 48, 84)
	ctx.maxHR = math.floor(208 - 0.7 * age)
	ctx.hr = ctx.restHR + 10 + math.random() * 8
	ctx.hrPeak = ctx.hr
	ctx.kcal = 0
	local recHR = Config.RecoveryHR[info.act.id]
	ctx.recovery = recHR ~= nil
	ctx.workHR = recHR and (ctx.restHR + recHR) or (Config.TrainingHR[info.act.id] or 150)
	local activity, sinceLive, sinceEffort, sinceSweat = 0, 1, 1, 0
	pumpFadeToken += 1
	local startChar = player.Character
	ctx.livePump = startChar and tonumber(startChar:GetAttribute("LivePump")) or 0
	function ctx.pulse(n)
		activity = math.min(6, activity + 0.25 * (n or 1))
	end
	-- (each label is written only when its text changes: a Text write re-lays the label out)
	local shown = {}
	local function show(label, text)
		if shown[label] ~= text then
			shown[label] = text
			label.Text = text
		end
	end
	function ctx.refreshLive()
		local hr = math.floor(ctx.hr + 0.5)
		local f = hr / ctx.maxHR
		local tl = ctx.tiles
		if shown.hr ~= hr then
			shown.hr = hr
			tl.hr.val.Text = tostring(hr)
			tl.hr.val.TextColor3 = f >= 0.9 and T.red or (f >= 0.8 and T.orange or (f >= 0.65 and T.green or T.text))
		end
		local kcal = math.floor(ctx.kcal + 0.5)
		if shown.kcal ~= kcal then
			shown.kcal = kcal
			tl.kcal.val.Text = tostring(kcal)
		end
		if ctx.mode ~= "done" then
			local secs = math.floor(os.clock() - ctx.t0 + 0.5)
			if shown.secs ~= secs then
				shown.secs = secs
				tl.time.val.Text = clock(secs)
			end
		end
		show(ctx.live, ctx.statsText or "")
	end
	-- the drill's live numbers (second line of the live readout)
	function ctx.stats(text)
		if text ~= ctx.statsText then
			ctx.statsText = text
			ctx.refreshLive()
		end
	end
	table.insert(ctx.conns, RunService.Heartbeat:Connect(function(dt)
		if ctx.mode == "done" then
			return
		end
		dt = math.min(dt, 0.1)
		activity *= math.exp(-dt / 1.5)
		local effort = math.clamp(math.max(activity / 1.5, ctx.intensity or ctx.baseEffort or 0), 0, 1)
		local target, k
		if ctx.mode == "rest" then
			target, k = math.min(ctx.hr, ctx.restHR + 16), 0.11
		elseif ctx.recovery then
			target, k = ctx.workHR, 0.09
		else
			target = ctx.restHR + (ctx.workHR - ctx.restHR) * (0.4 + 0.6 * effort)
			k = target > ctx.hr and (0.04 + 0.22 * effort) or 0.07
		end
		ctx.hr = math.min(ctx.maxHR, ctx.hr + (target - ctx.hr) * (1 - math.exp(-k * dt)))
		ctx.hrPeak = math.max(ctx.hrPeak, ctx.hr)
		ctx.kcal += math.max(0, ctx.hr - 60) * 0.1 / 60 * dt * TIME_SCALE
		sinceLive += dt
		if sinceLive >= 0.15 then
			sinceLive = 0
			ctx.refreshLive()
		end
		-- Effort (client-local, 0..1 in 0.05 steps): the Animator's strain tremor and face
		sinceEffort += dt
		if sinceEffort >= 0.25 then
			sinceEffort = 0
			local e = math.clamp((ctx.hr - ctx.restHR) / math.max(1, ctx.maxHR - ctx.restHR), 0, 1)
			e = math.floor(math.clamp(e * 0.7 + (ctx.intensity or 0) * 0.3, 0, 1) * 20 + 0.5) / 20
			if e ~= ctx.effortSent then
				ctx.effortSent = e
				ctx.attr("Effort", e)
			end
		end
		-- sweat drips onto the floor while you work: driven by how wet the boxer already is (the server's
		-- Sweat attribute) or by working close to this drill's own working HR. An absolute 80% of max HR
		-- was out of reach at every weight station, so the floor never got wet. Recovery work stays dry.
		if ctx.mode == "work" and ctx.station and not ctx.recovery then
			local ch = player.Character
			local sw = (ch and tonumber(ch:GetAttribute("Sweat"))) or 0
			sw = sw == sw and math.clamp(sw, 0, 1) or 0
			if sw >= 0.35 or ctx.hr > 0.85 * ctx.workHR then
				sinceSweat += dt * (0.5 + sw)
				if sinceSweat >= 6 then
					sinceSweat = math.random() * 1.5
					pcall(GymVisuals.SweatDrop, ctx.station)
				end
			end
		end
	end))

	-- input: on-screen buttons and keys go through one dispatcher; rests ignore new presses
	-- (releases still pass so a held lift / breath can't get stuck)
	local function dispatch(id, down)
		local h = ctx.handler
		if not h then
			return
		end
		if down then
			if ctx.resting then
				return
			end
			ctx.pulse()
		end
		local t = ctx.now()
		sendInput(ctx, id, down, t)
		h(id, down, t)
	end
	function ctx.on(fn)
		ctx.handler = fn
	end
	-- the drill clock (what the inputs are stamped with)
	function ctx.now()
		return os.clock() - ctx.clock0
	end
	-- the next segment of the plan starts now: its judge (DrillScore) and the plan's numbers for it.
	-- The "@" marker tells the server's replay where the segment begins.
	function ctx.begin()
		ctx.segI += 1
		local seg = ctx.plan.segs[ctx.segI]
		local t = ctx.now()
		sendInput(ctx, "@", true, t)
		local j = seg and DrillScore.Judge(seg, t)
		ctx.judges[ctx.segI] = j
		ctx.segAt = t
		return j, seg, t
	end
	-- the plan's next segment (to show it before it starts: a cue's lead-in, a rep's zone)
	function ctx.peek()
		return ctx.plan.segs[ctx.segI + 1] or {}
	end
	-- a segment over: its result goes into the session score
	function ctx.close(j)
		for i, jj in pairs(ctx.judges) do
			if jj == j then
				j.finish(ctx.now())
				ctx.results[i] = j.result()
				ctx.judges[i] = nil
			end
		end
		return j and j.result()
	end
	-- the session's 0..1 score, exactly as the server will replay it
	function ctx.score()
		for i, j in pairs(ctx.judges) do
			j.finish(ctx.now())
			ctx.results[i] = j.result()
			ctx.judges[i] = nil
		end
		return DrillScore.Aggregate(ctx.plan, ctx.results)
	end
	-- actions: { id, label, keys = { KeyCode... }, pad = { KeyCode... } (optional: else PAD_OF of the keys),
	-- color }. ctx.keymap / ctx.padmap: KeyCode -> action id (the gamepad's flicks as Thumbstick2* keys)
	function ctx.bind(actions, cellsPerRow)
		local resolved = {}
		for i, a in ipairs(actions) do
			resolved[i] = resolveAction(a)
		end
		actions = resolved
		UI.Clear(ctx.inputBar)
		local grid = ctx.inputBar:FindFirstChildOfClass("UIGridLayout")
		local per = cellsPerRow or math.min(6, #actions)
		grid.CellSize = UDim2.new(1 / math.max(1, per), -5, 0, ctx.cellH)
		-- the bar holds every row at the cells' height; the drill panel grows to it (a phone's
		-- finger-high cells in two rows)
		local rows = math.max(1, math.ceil(#actions / math.max(1, per)))
		local barH = rows * ctx.cellH + (rows - 1) * 5
		ctx.inputBar.Size = UDim2.new(1, -28, 0, math.max(88, barH))
		ctx.panelH = math.max(ctx.panelBase, ctx.stageY + STAGE_H + 6 + barH + 10)
		if not ctx.sizeResult and not ctx.compactRun then
			panel.Size = UDim2.new(0.96, 0, 0, ctx.panelH)
			ctx.panelMax.MaxSize = Vector2.new(PANEL_W, ctx.panelH)
		end
		ctx.keymap = {}
		ctx.padmap = {}
		ctx.buttons = {}
		ctx.spacePad = nil
		-- touch instructions: the button that stands for each fight action, and the SPACE action's word
		ctx.labelOf = {}
		ctx.spaceSay = nil
		for _, a in ipairs(actions) do
			for _, m in ipairs(type(a.map) == "table" and a.map or { a.map or a.id }) do
				ctx.labelOf[m] = ctx.labelOf[m] or a.label
			end
			if table.find(a.keys or {}, K.Space) and not ctx.spaceSay then
				ctx.spaceSay = a.say or a.label
			end
		end
		local padOf = {}
		local function givePad(id, pk)
			if not ctx.padmap[pk] then
				ctx.padmap[pk] = id
				table.insert(padOf[id], pk)
				return true
			end
			return false
		end
		-- punches and moves first, SPACE takes what is left (A, else LT)
		for _, a in ipairs(actions) do
			padOf[a.id] = padOf[a.id] or {}
			for _, key in ipairs(a.keys or {}) do
				ctx.keymap[key] = a.id
			end
			for _, pk in ipairs(a.pad or {}) do
				givePad(a.id, pk)
			end
			if not a.pad then
				for _, key in ipairs(a.keys or {}) do
					for _, pk in ipairs(PAD_OF[key] or {}) do
						givePad(a.id, pk)
					end
				end
			end
		end
		for _, a in ipairs(actions) do
			if not a.pad and table.find(a.keys or {}, K.Space) then
				for _, pk in ipairs(PAD_SPACE) do
					if givePad(a.id, pk) then
						ctx.spacePad = ctx.spacePad or pk
						break
					end
				end
			end
		end
		ctx.ownKey = {}
		for i, a in ipairs(actions) do
			local keyText = a.keyText or (a.keys and a.keys[1] and (KEYNAME[a.keys[1]] or a.keys[1].Name)) or ""
			local padKey = padOf[a.id][1]
			if not a.map then
				ctx.ownKey[a.id] = { kbd = keyText, pad = padKey }
			end
			local b = UI.Button(ctx.inputBar, a.label, { LayoutOrder = i, TextSize = 13, BackgroundColor3 = a.color or T.panel2 })
			b.Selectable = false
			-- the key in brackets follows the device: the keyboard key, the gamepad button, nothing on touch
			UI.BindHint(b, function(mode)
				if mode == "gamepad" and Gamepad then
					return padKey and (a.label .. "  [" .. Gamepad.Label(padKey) .. "]") or a.label
				elseif mode == "touch" then
					return a.label
				end
				return a.label .. (keyText ~= "" and ("  [" .. keyText .. "]") or "")
			end)
			b.MouseButton1Down:Connect(function()
				dispatch(a.id, true)
			end)
			b.MouseButton1Up:Connect(function()
				dispatch(a.id, false)
			end)
			ctx.buttons[a.id] = b
		end
		-- the instructions may name SPACE: its button can have changed with this map
		if ctx.infoRaw then
			UI.BindHint(ctx.info, infoFor)
		end
		-- (the panel's height follows the rows of buttons: the strip over it may have to make way)
		if ctx.layout and not ctx.sizeResult then
			ctx.layout()
		end
	end
	-- the key a drill's own action is on for this device ("A", the pad button), nil on touch (the
	-- button is named instead); short = the pad's short form for a tight line ("D-LEFT")
	function ctx.ownKeyText(id, mode, short)
		local k = ctx.ownKey and ctx.ownKey[id]
		if not k or mode == "touch" then
			return nil
		elseif mode == "gamepad" then
			return (k.pad and Gamepad) and (short and Gamepad.Short or Gamepad.Label)(k.pad) or nil
		end
		return k.kbd ~= "" and k.kbd or nil
	end
	function ctx.wait(sec)
		local t0 = os.clock()
		while os.clock() - t0 < sec do
			if ctx.cancelled then
				return false
			end
			RunService.Heartbeat:Wait()
		end
		return not ctx.cancelled
	end

	-- rounds, rests and progress
	local function overlay(transparency)
		local o = UI.Frame(panel, { Name = "Overlay", Position = UDim2.new(0, 14, 0, ctx.stageY), Size = UDim2.new(1, -28, 0, STAGE_H), BackgroundColor3 = Color3.fromRGB(12, 14, 20), BackgroundTransparency = transparency or 0, ZIndex = 8 })
		UI.Corner(o, 8)
		UI.Stroke(o, T.gold, 1, 0.7)
		return o
	end
	function ctx.nextTip()
		local tips = Config.TrainingTips[ctx.act.id]
		if not tips or #tips == 0 then
			return nil
		end
		ctx.tipIndex += 1
		return tips[(ctx.tipIndex - 1) % #tips + 1]
	end
	-- sets the "ROUND 2/3 · POWER SHOTS" header and shows a short intro banner (sec = 0: header only)
	function ctx.round(i, n, name, kind, sec)
		kind = kind or "ROUND"
		ctx.roundI, ctx.roundN = i, n
		local tag = n > 1 and string.format("%s %d/%d", kind, i, n) or kind
		ctx.roundText = n > 1 and tag or nil
		-- the header names what you are doing; the count lives on the metrics strip only
		ctx.header.Text = name or ctx.act.name:upper()
		ctx.tiles.set.cap.Text = string.upper(kind)
		ctx.tiles.set.val.Text = n > 1 and string.format("%d/%d", i, n) or "1/1"
		ctx.fillTile("set", i / math.max(1, n))
		ctx.refreshLive()
		sec = sec or (i == 1 and WAIT.intro or WAIT.round)
		if sec <= 0 then
			return not ctx.cancelled
		end
		ctx.resting = true
		local o = overlay(0.08)
		UI.Text(o, n > 1 and string.format("%s %d", kind, i) or kind, { Face = "display", TextSize = 46, TextColor3 = T.gold, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 52), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
		if n > 1 then
			UI.Text(o, string.format("OF %d", n), { Font = T.semi, TextSize = 11, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 14), AutomaticSize = Enum.AutomaticSize.None })
		end
		if name then
			UI.Text(o, string.upper(name), { Face = "displayMed", TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 82), Size = UDim2.new(1, 0, 0, 24), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
		end
		local ok = ctx.wait(sec)
		o:Destroy()
		ctx.resting = false
		return ok
	end
	-- a breather between rounds / sets: countdown + coach tip; inputs are ignored and the heart rate drops
	function ctx.rest(sec, title, note, tip)
		ctx.resting = true
		ctx.mode = "rest"
		local o = overlay(0.03)
		UI.Text(o, string.upper(title or "REST"), { Face = "displayMed", TextSize = 20, TextColor3 = T.gold, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -110, 0, 24), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		if note then
			UI.Text(o, note, { Font = T.semi, TextSize = 13, TextColor3 = T.sub, Position = UDim2.fromOffset(12, 31), Size = UDim2.new(1, -110, 0, 18), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		end
		local count = UI.Text(o, "", { Face = "number", TextSize = 44, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.fromOffset(90, 46), TextXAlignment = Enum.TextXAlignment.Right, AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
		UI.Text(o, "REST", { Font = T.semi, TextSize = 11, TextColor3 = T.sub, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 44), Size = UDim2.fromOffset(90, 12), TextXAlignment = Enum.TextXAlignment.Right, AutomaticSize = Enum.AutomaticSize.None })
		tip = tip or ctx.nextTip()
		if tip then
			local tipBox = UI.Frame(o, { BackgroundColor3 = T.panel2, BackgroundTransparency = 0.5, Position = UDim2.fromOffset(12, 56), Size = UDim2.new(1, -24, 0, 44), ZIndex = 8 })
			UI.Corner(tipBox, 4)
			UI.Frame(tipBox, { Size = UDim2.new(0, 3, 1, -10), Position = UDim2.fromOffset(0, 5), BackgroundColor3 = T.gold, ZIndex = 8 })
			UI.Text(tipBox, "COACH:  \"" .. tip .. "\"", { Font = T.semi, TextSize = 14, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -20, 1, 0), TextYAlignment = Enum.TextYAlignment.Center, AutomaticSize = Enum.AutomaticSize.None, ZIndex = 8 })
		end
		local _, setBar = UI.Bar(o, { Position = UDim2.new(0, 12, 1, -12), Size = UDim2.new(1, -24, 0, 4) }, T.blue)
		local t0 = os.clock()
		local ok = true
		while true do
			if ctx.cancelled then
				ok = false
				break
			end
			local left = sec - (os.clock() - t0)
			if left <= 0 then
				break
			end
			count.Text = tostring(math.ceil(left))
			setBar(left / sec)
			RunService.Heartbeat:Wait()
		end
		o:Destroy()
		ctx.resting = false
		ctx.mode = "work"
		return ok
	end
	-- progress through the current round, shown as progress through the whole session
	function ctx.progress(f)
		local n = math.max(1, ctx.roundN or 1)
		local i = math.clamp(ctx.roundI or 1, 1, n)
		setProg((i - 1 + math.clamp(f, 0, 1)) / n)
	end

	-- local animation helpers
	local char = player.Character
	-- power (optional, ~0.3..1.5) goes out as the 5th Act field: the Animator scales hip rotation by it
	function ctx.punch(ptype, zone, power)
		local c = player.Character
		if not c then
			return 0.2, "R"
		end
		local hand = HAND[ptype] or "R"
		if ptype == "uppercut" then
			ctx.upHand = ctx.upHand == "R" and "L" or "R"
			hand = ctx.upHand
		end
		local act = string.format("%s|%s|%s|%.2f", ptype, hand, zone or "head", WINDUP[ptype] or 0.2)
		if power then
			act ..= string.format("|%.2f", math.clamp(power, 0, 2))
		end
		c:SetAttribute("Act", act)
		c:SetAttribute("ActId", (c:GetAttribute("ActId") or 0) + 1)
		return WINDUP[ptype] or 0.2, hand
	end
	function ctx.move(kind, dir)
		local c = player.Character
		if c then
			c:SetAttribute("Act", string.format("%s|%s|head|0.25", kind, dir or "L"))
			c:SetAttribute("ActId", (c:GetAttribute("ActId") or 0) + 1)
		end
	end
	-- (the pose attributes fire the Animator's listeners on every change: a value it already has is not
	-- written again, and the pace drills' speed moves in 0.02 steps instead of a new float every frame)
	function ctx.drive(d)
		if char and d ~= ctx.poseDrive then
			ctx.poseDrive = d
			char:SetAttribute("PoseDrive", d)
		end
	end
	function ctx.speed(w)
		w = math.floor(w * 50 + 0.5) / 50
		if char and w ~= ctx.poseSpeed then
			ctx.poseSpeed = w
			char:SetAttribute("PoseSpeed", w)
		end
	end
	-- a pose attribute written only when it changes by a step (the Animator reacts to every write)
	local attrShown = {}
	function ctx.attrQ(name, v, step)
		if type(v) == "number" then
			step = step or 0.02
			v = math.floor(v / step + 0.5) * step
		end
		if attrShown[name] ~= v then
			attrShown[name] = v
			ctx.attr(name, v)
		end
	end
	function ctx.attr(name, v)
		if char then
			char:SetAttribute(name, v)
		end
		if name == "RepCount" and type(v) == "number" then
			ctx.reps = v
			ctx.updateMetrics()
		end
	end
	-- the bag / ball reacts; ptype and zone (optional) shape the swing, twist, dent and sound
	function ctx.impact(power, side, ptype, zone)
		if ctx.station then
			GymVisuals.Impact(ctx.station, power, side, ptype, zone)
			local shake = math.clamp(tonumber(player:GetAttribute("CamShake")) or 1, 0, 1.5) -- Settings
			if (power or 0) > 1.0 and shake > 0 then
				camKick.t, camKick.amp = os.clock(), math.min(1.6, power) * shake
			end
		end
	end
	-- a good rep pumps the worked muscles a little more (client-local LivePump, BodyFX reads it)
	function ctx.pump(amount)
		ctx.livePump = math.clamp((ctx.livePump or 0) + (amount or 0.1), 0, 1)
		ctx.attr("LivePump", math.floor(ctx.livePump * 20 + 0.5) / 20)
	end
	-- keys work while the panel is alive
	table.insert(ctx.conns, UserInputService.InputBegan:Connect(function(input, gp)
		local k = input.KeyCode
		if Gamepad and Gamepad.IsPadKey(k) then
			-- VIEW / SHARE quits (closes the report); a default control binding can mark a pad button
			-- processed (A is the jump action), so only Roblox's UI selection stops the drill's buttons
			if k == K.ButtonSelect then
				ctx.cancelled = true
				return
			end
			if GuiService.SelectedObject ~= nil or UserInputService:GetFocusedTextBox() then
				return
			end
			local id = ctx.padmap and ctx.padmap[k]
			if id then
				dispatch(id, true)
			end
			return
		end
		if gp then
			return
		end
		-- a mouse button binding (the default jab / cross) is keyed by its UserInputType
		local id = ctx.keymap[k] or ctx.keymap[input.UserInputType]
		if id then
			dispatch(id, true)
		end
	end))
	table.insert(ctx.conns, UserInputService.InputEnded:Connect(function(input)
		local k = input.KeyCode
		local id = ctx.keymap[k] or ctx.keymap[input.UserInputType] or (ctx.padmap and ctx.padmap[k])
		if id then
			dispatch(id, false)
		end
	end))
	-- right-stick flicks: slips and rolls (a tap: press and release at once)
	local flick = Gamepad and Gamepad.Flick()
	if flick then
		table.insert(ctx.conns, UserInputService.InputChanged:Connect(function(input)
			if input.KeyCode ~= K.Thumbstick2 then
				return
			end
			local dir = flick:Update(input.Position.X, input.Position.Y, os.clock())
			local id = dir and ctx.padmap and ctx.padmap[FLICK_KEY[dir]]
			if id and GuiService.SelectedObject == nil then
				dispatch(id, true)
				dispatch(id, false)
			end
		end))
	end
	function ctx.destroy()
		ctx.mode = "done"
		ctx.handler = nil
		State.HideHud("Activity", false)
		for _, c in ipairs(ctx.conns) do
			c:Disconnect()
		end
		for _, fn in ipairs(ctx.cleanups) do
			pcall(fn)
		end
		if panel.Parent then
			panel:Destroy()
		end
		if char then
			for _, a in ipairs(POSE_ATTRS) do
				char:SetAttribute(a, nil)
			end
			-- the live pump fades over half a minute instead of vanishing with the panel
			local pumpLeft = ctx.livePump or 0
			if pumpLeft > 0 then
				local c = char
				local token = pumpFadeToken
				task.spawn(function()
					while pumpLeft > 0 and c.Parent and token == pumpFadeToken do
						task.wait(1)
						pumpLeft = math.max(0, pumpLeft - 0.035)
						c:SetAttribute("LivePump", pumpLeft > 0 and (math.floor(pumpLeft * 20 + 0.5) / 20) or nil)
					end
				end)
			else
				char:SetAttribute("LivePump", nil)
			end
		end
	end
	return ctx
end

-- the stage's width in design px (AbsoluteSize is in screen px under the root's UIScale)
local function stageWidth(ctx)
	local w = ctx.stage.AbsoluteSize.X / math.max(0.1, UI.ScaleOf(ctx.stage))
	return w > 100 and w or 620
end

local function chip(parent, text, x, w, color)
	local f = UI.Frame(parent, { Position = UDim2.new(0, x, 0.5, -20), Size = UDim2.fromOffset(w, 40), BackgroundColor3 = color or T.panel2 })
	UI.Corner(f, 8)
	UI.Pad(f, 2, 4)
	local t = UI.Text(f, text, { Font = T.bold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None, TextScaled = true })
	UI.New("UITextSizeConstraint", { MaxTextSize = 14, MinTextSize = 8, Parent = t })
	return f, t
end

-- a row of chips at a fixed height (with ">" between them for flow chains)
local function chipRow(ctx, labels, top, arrows, maxW)
	local n = #labels
	local gap = arrows and 20 or 8
	local w = math.max(36, math.min(maxW or 100, math.floor((stageWidth(ctx) - 20 - (n - 1) * gap) / math.max(1, n))))
	local chips = {}
	for i, text in ipairs(labels) do
		local x = 10 + (i - 1) * (w + gap)
		local f = chip(ctx.stage, text, x, w)
		f.Position = UDim2.new(0, x, 0, top)
		chips[i] = f
		if arrows and i < n then
			UI.Text(ctx.stage, ">", { Font = T.bold, TextSize = 16, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, x + w, 0, top), Size = UDim2.fromOffset(gap, 40), AutomaticSize = Enum.AutomaticSize.None })
		end
	end
	return chips
end

local function timeBar(ctx, top, color)
	local bar = UI.Frame(ctx.stage, { Position = UDim2.new(0, 10, 0, top), Size = UDim2.new(1, -20, 0, 6), BackgroundColor3 = color or T.green })
	UI.Corner(bar, 3)
	return function(frac)
		bar.Size = UDim2.new(math.clamp(frac, 0, 1), -20 * math.clamp(frac, 0, 1), 0, 6)
	end
end

-- the full-height panel (course / swim shrink it while running)
local function compactPanel(ctx)
	ctx.compactRun = true
	ctx.panel.Size = UDim2.new(0.96, 0, 0, math.max(196, ctx.stageY + 54 + ctx.cellH + 10))
	ctx.stage.Size = UDim2.new(1, -28, 0, 48)
	ctx.flash.Position = UDim2.new(0, 14, 0, ctx.stageY + 8)
	ctx.inputBar.Position = UDim2.new(0, 14, 0, ctx.stageY + 54)
end
local function fullPanel(ctx)
	ctx.compactRun = nil
	ctx.panel.Size = UDim2.new(0.96, 0, 0, ctx.panelH or PANEL_H)
	ctx.stage.Size = UDim2.new(1, -28, 0, STAGE_H)
	ctx.flash.Position = UDim2.new(0, 14, 0, ctx.stageY + 84)
	ctx.inputBar.Position = UDim2.new(0, 14, 0, ctx.stageY + STAGE_H + 6)
end

------------------------------------------------------------------------
-- Minigames: each returns a performance 0..1 (nil if cancelled)
------------------------------------------------------------------------
local GAMES = {}

-- HEAVY BAG -------------------------------------------------------------
-- (the drills play the server's plan, Training.DrillPlan; the judges are DrillScore's)

-- estimated punch force: grows with the Power stat and the bag level (roughly 350..1500 lbs)
local function punchLbs(ctx, ptype, quality)
	local P = State.P
	local power = math.clamp(P and P.stats and P.stats.Power or 40, 10, 99)
	local potential = 500 + power * 8 + (math.clamp(ctx.level, 1, 6) - 1) * 40
	local pf = 0.85 + 0.15 * ((POWER[ptype] or 0.9) - 0.55) / 0.7
	return math.floor(math.max(350, potential * (0.45 + 0.55 * math.clamp(quality, 0, 1)) * pf))
end

-- the smart bag's screen (after the impact readout the bag shows by itself)
local function bagScreen(ctx, text)
	if ctx.smart then
		task.delay(0.4, function()
			GymVisuals.SetDisplay("heavybag", text)
		end)
	end
end

-- a judge's segment plays until it closes (an answer, the end of its window); false when cancelled.
-- onFrame(now) draws the stage each frame.
local function playSegment(ctx, j, onFrame)
	while not j.closed do
		if ctx.cancelled then
			return false
		end
		local now = ctx.now()
		j.advance(now)
		if onFrame then
			onFrame(now)
		end
		if j.closed then
			break
		end
		RunService.Heartbeat:Wait()
	end
	return not ctx.cancelled
end

-- the chips of a sequence follow its judge: green when thrown, red for a moment on a wrong press
local function seqChips(j, chips, hit)
	local at = hit.idx
	if hit.ok then
		chips[at].BackgroundColor3 = T.green
		if chips[at + 1] then
			chips[at + 1].BackgroundColor3 = T.gold
		end
	else
		chips[at].BackgroundColor3 = T.red
		task.delay(0.15, function()
			if j.idx == at and chips[at] then
				chips[at].BackgroundColor3 = T.gold
			end
		end)
	end
end

-- 3 rounds: combinations, power shots on a power meter, a 6-second speed burst
GAMES.combo = function(ctx)
	local punches, maxLbs = 0, 0
	local combos, shots = 0, 0
	for _, seg in ipairs(ctx.plan.segs) do
		if seg.j == "seq" then
			combos += 1
		elseif seg.j == "needle" then
			shots += 1
		end
	end

	-- ROUND 1: COMBINATIONS (the later ones called by number: 1 jab, 2 cross, 3 lead hook, 4 rear hook,
	-- 5 uppercut, 6 overhand - the number keys throw them too)
	ctx.bind(PUNCH_ACTIONS)
	local INFO_NAMES = "Throw each combination in order, every punch on the beat of the one before (the gold ring closes on the beat). (body) = dig it to the body." .. (ctx.smart and "  SMART BAG: impact tracking on." or "")
	local INFO_NUMBERS = "CALLED BY NUMBER: 1 jab, 2 cross, 3 lead hook, 4 rear hook, 5 uppercut, 6 overhand. B = to the body. Keep the beat."
	ctx.setInfo(INFO_NAMES)
	if not ctx.round(1, 3, "COMBINATIONS") then
		return nil
	end
	local clean = 0
	for r = 1, combos do
		UI.Clear(ctx.stage)
		local seg = ctx.peek()
		local byNumber = seg.call == "numbers"
		ctx.setInfo(byNumber and INFO_NUMBERS or INFO_NAMES)
		local labels, call = {}, {}
		for i, name in ipairs(seg.ids or {}) do
			local body = seg.body and seg.body[i]
			if byNumber then
				labels[i] = (PUNCH_NUMBER[name] or "?") .. (body and "B" or "")
				call[i] = labels[i]
			else
				labels[i] = (LABEL[name] or name) .. (body and " (body)" or "")
			end
		end
		local chips = chipRow(ctx, labels, 34, false, byNumber and 56 or 100)
		if byNumber then
			UI.Text(ctx.stage, "COACH: \"" .. table.concat(call, "-") .. "!\"", { Font = T.bold, TextSize = 14, TextColor3 = T.gold, Position = UDim2.fromOffset(10, 80), Size = UDim2.new(1, -20, 0, 18),
				AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		end
		local setTime = timeBar(ctx, 14)
		local limit = seg.limit or 3
		chips[1].BackgroundColor3 = T.gold
		-- the beat: a gold ring that swells on each punch and closes over one beat (seg.beat) - the next
		-- punch lands as it closes
		local beat = seg.beat or 0.4
		local ring = UI.Frame(ctx.stage, { Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -34, 0, 96), BackgroundColor3 = T.gold, BackgroundTransparency = 0.2 })
		UI.Corner(ring, 20)
		local lastHit
		local TEMPO_TEXT = { perfect = { "ON THE BEAT", T.gold }, good = { "GOOD", T.green }, off = { "OFF BEAT", T.orange } }
		local j, _, start = ctx.begin()
		ctx.on(function(id, down, t)
			local hit = j.input(id, down, t)
			if not hit then
				return
			end
			seqChips(j, chips, hit)
			if hit.ok then
				lastHit = t
				if hit.tempo then
					-- (the combination is graded as a whole once it is thrown: the per-punch flash is not a grade)
					ctx.feedback(TEMPO_TEXT[hit.tempo][1], TEMPO_TEXT[hit.tempo][2], false)
				end
				local pw = POWER[id] * (0.85 + math.random() * 0.3)
				local zone = (seg.body and seg.body[hit.idx]) and "body" or "head"
				local windup, hand = ctx.punch(id, zone, pw)
				local lbs = punchLbs(ctx, id, 0.5 + math.random() * 0.35)
				maxLbs = math.max(maxLbs, lbs)
				task.delay(windup, function()
					ctx.impact(pw, hand == "L" and -1 or 1, id, zone)
				end)
				punches += 1
				if ctx.smart then
					ctx.feedback(fmtInt(lbs) .. " lbs", Color3.fromRGB(80, 200, 255))
				end
			end
		end)
		local okPlay = playSegment(ctx, j, function(now)
			local el = now - start
			setTime(1 - el / limit)
			ctx.progress((r - 1 + math.min(1, el / limit)) / combos)
			local ph = lastHit and math.clamp((now - lastHit) / beat, 0, 1) or 0
			local d = 16 + 22 * (1 - ph)
			ring.Size = UDim2.fromOffset(d, d)
			ring.BackgroundTransparency = 0.2 + 0.6 * ph
		end)
		ctx.on(nil)
		if not okPlay then
			return nil
		end
		local res = ctx.close(j)
		if res.complete and res.wrong == 0 then
			clean += 1
			ctx.feedback((res.beatQ or res.frac / 0.6) >= 0.8 and "PERFECT RHYTHM!" or "CLEAN!", T.gold)
		elseif res.complete then
			ctx.feedback("SLOPPY", T.orange)
		else
			ctx.feedback("TOO SLOW", T.red)
		end
		ctx.stats(string.format("Combo %d/%d%s%d clean%s%d punches", r, combos, DOT, clean, DOT, punches))
		ctx.progress(r / combos)
		bagScreen(ctx, string.format("COMBO %d/%d\n%d CLEAN", r, combos, clean))
		if not ctx.wait(WAIT.combo) then
			return nil
		end
	end
	if not ctx.rest(WAIT.rest, "ROUND 1 DONE", string.format("%d/%d clean combinations%s%d punches", clean, combos, DOT, punches)) then
		return nil
	end

	-- ROUND 2: POWER SHOTS - throw when the needle crosses the gold sweet spot
	ctx.bind(actionList({ { id = "power", label = "POWER", keys = { K.Space }, color = T.gold } }, PUNCH_ACTIONS), 4)
	if ctx.buttons.power then
		ctx.buttons.power.TextColor3 = T.bg
	end
	ctx.setInfo("Throw POWER (SPACE) or any punch while the needle is in the GOLD zone. Timing is power - hooks and overhands land heaviest.")
	if not ctx.round(2, 3, "POWER SHOTS") then
		return nil
	end
	for s = 1, shots do
		UI.Clear(ctx.stage)
		local seg = ctx.peek()
		UI.Text(ctx.stage, string.format("SHOT %d/%d", s, shots), { Font = T.bold, TextSize = 15, TextColor3 = T.sub, Position = UDim2.fromOffset(10, 8), Size = UDim2.new(0.5, -10, 0, 20), AutomaticSize = Enum.AutomaticSize.None })
		local bestText = UI.Text(ctx.stage, maxLbs > 0 and ("BEST " .. fmtInt(maxLbs) .. " lbs") or "", { Font = T.bold, TextSize = 15, TextColor3 = T.gold, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.new(0.5, -10, 0, 20), TextXAlignment = Enum.TextXAlignment.Right, AutomaticSize = Enum.AutomaticSize.None })
		local meter = UI.Frame(ctx.stage, { Position = UDim2.new(0, 10, 0, 38), Size = UDim2.new(1, -20, 0, 28), BackgroundColor3 = Color3.fromRGB(30, 30, 38) })
		UI.Corner(meter, 6)
		local w, c, dur = seg.w or 0.05, seg.c or 0.75, seg.dur or 4.5
		UI.Frame(meter, { Position = UDim2.fromScale(c - w * 2.5, 0), Size = UDim2.fromScale(w * 5, 1), BackgroundColor3 = T.green, BackgroundTransparency = 0.55 })
		UI.Frame(meter, { Position = UDim2.fromScale(c - w, 0), Size = UDim2.fromScale(w * 2, 1), BackgroundColor3 = T.gold })
		local needle = UI.Frame(meter, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0, 5, 1, 14), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3 })
		UI.Text(ctx.stage, "LIGHT", { Font = T.semi, TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(10, 70), Size = UDim2.fromOffset(80, 14), AutomaticSize = Enum.AutomaticSize.None })
		UI.Text(ctx.stage, "KNOCKOUT", { Font = T.semi, TextSize = 11, TextColor3 = T.sub, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 70), Size = UDim2.fromOffset(80, 14), TextXAlignment = Enum.TextXAlignment.Right, AutomaticSize = Enum.AutomaticSize.None })
		local j, _, t0 = ctx.begin()
		local thrown
		ctx.on(function(id, down, t)
			-- the needle is judged where it is at the press, not at the last frame
			local hit = j.input(id, down, t)
			if hit then
				thrown = hit
				needle.Position = UDim2.fromScale(hit.pos, 0.5)
			end
		end)
		local okPlay = playSegment(ctx, j, function(now)
			local el = now - t0
			if not thrown then
				needle.Position = UDim2.fromScale(DrillScore.NeedlePos(el, seg.sweep or 1), 0.5)
			end
			ctx.progress((s - 1 + math.min(1, el / dur)) / shots)
		end)
		ctx.on(nil)
		if not okPlay then
			return nil
		end
		ctx.close(j)
		if thrown then
			local ptype = thrown.id == "power" and "cross" or thrown.id
			local d, timing = thrown.d, thrown.timing
			local lbs = punchLbs(ctx, ptype, timing)
			maxLbs = math.max(maxLbs, lbs)
			punches += 1
			local imp = math.min(1.5, 0.5 + timing * (0.6 + 0.4 * POWER[ptype] / 1.25))
			local windup, hand = ctx.punch(ptype, "head", imp)
			task.delay(windup, function()
				ctx.impact(imp, hand == "L" and -1 or 1, ptype, "head")
			end)
			bagScreen(ctx, string.format("POWER\n%s lbs\nBEST %s", fmtInt(lbs), fmtInt(maxLbs)))
			local verdict, col
			if d <= w * 0.35 then
				verdict, col = "PERFECT!", T.gold
			elseif d <= w then
				verdict, col = "SWEET SPOT", T.green
			elseif d <= 2.5 * w then
				verdict, col = "GOOD", T.text
			else
				verdict, col = "MISTIMED", T.orange
			end
			needle.BackgroundColor3 = col
			bestText.Text = "BEST " .. fmtInt(maxLbs) .. " lbs"
			ctx.feedback(verdict .. "   " .. fmtInt(lbs) .. " lbs", col)
		else
			ctx.feedback("TOO LATE", T.red)
		end
		ctx.stats(string.format("Shot %d/%d%sMax %s lbs", s, shots, DOT, fmtInt(maxLbs)))
		ctx.progress(s / shots)
		if not ctx.wait(WAIT.shot) then
			return nil
		end
	end
	if not ctx.rest(WAIT.rest, "ROUND 2 DONE", string.format("Max power %s lbs", fmtInt(maxLbs))) then
		return nil
	end

	-- ROUND 3: SPEED BURST - alternate hands as fast as possible
	ctx.bind({ { id = "L", label = "LEFT", keys = { K.J, K.F, K.One }, map = "jab", color = T.blue }, { id = "R", label = "RIGHT", keys = { K.K, K.G, K.Two }, map = "cross", color = T.red } }, 2)
	ctx.setInfo("Alternate LEFT ({jab}) and RIGHT ({cross}) as fast as you can for 6 seconds. Only alternating punches count!")
	if not ctx.round(3, 3, "SPEED BURST") then
		return nil
	end
	UI.Clear(ctx.stage)
	local setTime = timeBar(ctx, 10, T.gold)
	local countText = UI.Text(ctx.stage, "0", { Font = T.bold, TextSize = 44, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 48), AutomaticSize = Enum.AutomaticSize.None })
	local rateText = UI.Text(ctx.stage, "punches", { Font = T.semi, TextSize = 14, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, 18), AutomaticSize = Enum.AutomaticSize.None })
	local j, seg, t0 = ctx.begin()
	local burst, target = seg and seg.dur or 6, seg and seg.target or 5
	local count = 0
	ctx.on(function(id, down, t)
		local hit = j and j.input(id, down, t)
		if not hit then
			return
		end
		if not hit.alt then
			ctx.feedback("ALTERNATE!", T.orange)
			return
		end
		count = hit.count
		punches += 1
		local ptype = id == "L" and "jab" or "cross"
		local windup, hand = ctx.punch(ptype, "head", 0.4)
		task.delay(windup * 0.6, function()
			ctx.impact(0.3 + math.random() * 0.15, hand == "L" and -1 or 1, ptype, "head")
		end)
	end)
	local okPlay = j and playSegment(ctx, j, function(now)
		local el = now - t0
		local rate = count / math.max(0.75, el)
		countText.Text = tostring(count)
		rateText.Text = string.format("%.1f punches / sec", rate)
		setTime(1 - el / burst)
		ctx.progress(el / burst)
		ctx.stats(string.format("%d punches%s%.1f / sec", count, DOT, rate))
	end)
	ctx.on(nil)
	if not okPlay then
		return nil
	end
	ctx.close(j)
	local pps = count / burst
	countText.Text = tostring(count)
	rateText.Text = string.format("%.1f punches / sec", pps)
	setTime(0)
	ctx.feedback(pps >= target and "BLAZING HANDS!" or string.format("%.1f / sec", pps), pps >= target and T.gold or T.text)
	bagScreen(ctx, string.format("SESSION\n%d PUNCHES\nMAX %s lbs", punches, fmtInt(maxLbs)))
	ctx.put("punches", punches)
	ctx.put("maxPower", maxLbs)
	ctx.put("handSpeed", math.floor(pps * 10 + 0.5) / 10)
	ctx.note(string.format("Max power %s lbs", fmtInt(maxLbs)))
	ctx.note(string.format("%.1f punches/sec", pps))
	ctx.note(string.format("%d punches", punches))
	if not ctx.wait(0.8) then
		return nil
	end
	return ctx.score()
end

-- SPEED BAG -------------------------------------------------------------
-- beats on two lanes slide to the gold line: the note frames of a notes judge (rhythm, twists)
local function noteFrames(ctx, j, lineX)
	UI.Frame(ctx.stage, { Position = UDim2.new(0, lineX - 2, 0, 6), Size = UDim2.new(0, 4, 1, -46), BackgroundColor3 = T.gold })
	local frames = {}
	for i, n in ipairs(j.notes) do
		local f = UI.Frame(ctx.stage, { Size = UDim2.fromOffset(26, 26), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, -100, 0, n.lane == "L" and 30 or 62), BackgroundColor3 = n.lane == "L" and T.blue or T.red })
		UI.Corner(f, 13)
		UI.Text(f, n.lane, { Font = T.bold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None })
		frames[i] = f
	end
	return frames
end
-- slide the open notes; true while any is still open. A note still beyond the stage's right edge (the
-- stage clips) is parked there once instead of moved every frame, and a judged one is hidden once
local NOTE_FAR = PANEL_W + 40
local function moveNotes(j, frames, lineX, now, pxPerSec)
	local alive = false
	local state = frames.state
	if not state then
		state = {}
		frames.state = state
	end
	for i, n in ipairs(j.notes) do
		if n.judged then
			if state[i] ~= "hidden" then
				state[i] = "hidden"
				frames[i].Visible = false
			end
		else
			alive = true
			local x = lineX + (n.t - now) * pxPerSec
			if x < NOTE_FAR then
				state[i] = nil
				frames[i].Position = UDim2.new(0, x, 0, n.lane == "L" and 30 or 62)
			elseif state[i] ~= "parked" then
				state[i] = "parked"
				frames[i].Position = UDim2.new(0, NOTE_FAR, 0, n.lane == "L" and 30 or 62)
			end
		end
	end
	return alive
end

-- 2 rounds: alternating rhythm, then faster doubles (and triplets on the better bags)
GAMES.rhythm = function(ctx)
	local lv = ctx.level
	ctx.bind({ { id = "L", label = "LEFT", keys = { K.J, K.F }, map = "jab", color = T.blue }, { id = "R", label = "RIGHT", keys = { K.K, K.G }, map = "cross", color = T.red } }, 2)
	local rounds = ctx.plan.segs
	local hitsAll, notesAll, bestStreak, bestHpm = 0, 0, 0, 0
	for ri, rd in ipairs(rounds) do
		local bpm = rd.bpm or 140
		ctx.setInfo(ri == 1 and string.format("Hit LEFT ({jab}) and RIGHT ({cross}) as each beat crosses the gold line. From %d BPM - the bag picks up speed through the round: keep up.", bpm)
			or string.format("Same hand two%s times in a row now, from %d BPM and speeding up. Stay loose and keep the rhythm.", lv >= 3 and " or three" or "", bpm))
		if not ctx.round(ri, #rounds, string.format("%s%s%d BPM", rd.name or "RHYTHM", DOT, bpm)) then
			return nil
		end
		UI.Clear(ctx.stage)
		local lineX = 70
		local j, seg, M = ctx.begin()
		local frames = noteFrames(ctx, j, lineX)
		local count = #seg.lanes
		local start = M + seg.lead
		local streak, hits = 0, 0
		ctx.on(function(id, down, t)
			if not down then
				return
			end
			ctx.impact(ri == 1 and 0.8 or 0.9, id == "L" and -1 or 1)
			local hit = j.input(id, down, t)
			if hit and hit.stray then
				-- a punch with no beat to hit (mashing costs points)
				streak = 0
				ctx.feedback("OFF BEAT", T.orange)
				return
			end
			if not (hit and hit.grade) then
				return
			end
			frames[hit.note].Visible = false
			if hit.grade == "perfect" then
				hits += 1
				streak += 1
				ctx.feedback("PERFECT x" .. streak, T.gold)
			elseif hit.grade == "good" then
				hits += 1
				streak += 1
				ctx.feedback("GOOD", T.green)
			else
				streak = 0
				ctx.feedback("OFF BEAT", T.orange)
			end
			bestStreak = math.max(bestStreak, streak)
			ctx.speed(1 + math.min(streak, 20) * 0.04)
		end)
		local pxPerSec = 260
		while true do
			if ctx.cancelled then
				ctx.on(nil)
				return nil
			end
			local now = ctx.now()
			for _ in ipairs(j.advance(now) or {}) do
				streak = 0
				ctx.feedback("MISS", T.red)
			end
			local alive = moveNotes(j, frames, lineX, now, pxPerSec)
			local el = now - start
			ctx.progress(el / math.max(1, j.notes[count].t - start))
			ctx.stats(string.format("%d hits/min%sstreak %d (best %d)", el > 1 and math.floor(hits / el * 60) or 0, DOT, streak, bestStreak))
			if not alive or j.closed then
				break
			end
			RunService.Heartbeat:Wait()
		end
		ctx.on(nil)
		ctx.speed(1)
		local res = ctx.close(j)
		bestHpm = math.max(bestHpm, hits / math.max(1, ctx.now() - start) * 60)
		hitsAll += res.hits
		notesAll += res.count
		if ri < #rounds then
			if not ctx.rest(WAIT.rest, "ROUND 1 DONE", string.format("%d/%d on the beat%sbest streak %d", res.hits, res.count, DOT, bestStreak)) then
				return nil
			end
		end
	end
	local acc = math.floor(hitsAll / math.max(1, notesAll) * 100 + 0.5)
	ctx.put("hitsPerMin", math.floor(bestHpm + 0.5))
	ctx.put("bestStreak", bestStreak)
	ctx.put("accuracy", acc)
	ctx.note(string.format("%d hits/min", math.floor(bestHpm + 0.5)))
	ctx.note(string.format("Best streak %d", bestStreak))
	ctx.note(string.format("%d%% on the beat", acc))
	return ctx.score()
end

-- DOUBLE-END BAG --------------------------------------------------------
local DEF_TEXT = { slipL = "<< SLIP LEFT", slipR = "SLIP RIGHT >>", roll = "ROLL UNDER!" }

local function defenseMove(ctx, id)
	if id == "roll" then
		ctx.move("roll", "L")
	elseif id == "slipL" or id == "slipR" then
		ctx.move("slip", id == "slipL" and "L" or "R")
	end
end

local function bagPunch(ctx)
	local windup, hand = ctx.punch(math.random() < 0.5 and "jab" or "cross")
	task.delay(windup, function()
		ctx.impact(0.8, hand == "L" and -1 or 1)
	end)
end

-- 2 rounds: react (punch / slip / roll on cue), then slip & counter (defend, then punch straight back)
GAMES.reaction = function(ctx)
	local lv = ctx.level
	local cues, cues2, cues3 = 0, 0, 0
	local window = 0.8
	for _, seg in ipairs(ctx.plan.segs) do
		if seg.j == "cue" then
			cues += 1
			window = seg.window or window
		elseif seg.j == "counter" then
			cues2 += 1
		elseif seg.j == "rebound" then
			cues3 += 1
		end
	end
	local rounds = cues3 > 0 and 3 or 2
	local actions = { { id = "punch", label = "PUNCH", keys = { K.J, K.K }, map = { "jab", "cross" } }, { id = "slipL", label = "SLIP L", keys = { K.Q }, map = "slipL" },
		{ id = "slipR", label = "SLIP R", keys = { K.E }, map = "slipR" } }
	if lv >= 2 then
		table.insert(actions, { id = "roll", label = "ROLL", keys = { K.C }, map = "dodge" })
	end
	ctx.bind(actions, #actions)
	local reactSum, reactN = 0, 0
	local function avgMs()
		return reactN > 0 and math.floor(reactSum / reactN * 1000 + 0.5) or 0
	end
	local function react(id)
		if id == "punch" then
			bagPunch(ctx)
		else
			defenseMove(ctx, id)
		end
	end

	-- ROUND 1: REACT
	ctx.setInfo(string.format("PUNCH when the bag comes into range, SLIP or ROLL when it swings back at you. Reaction window %.2fs.", window))
	if not ctx.round(1, rounds, "REACT") then
		return nil
	end
	local hits = 0
	for i = 1, cues do
		UI.Clear(ctx.stage)
		local seg = ctx.peek()
		if not ctx.wait(seg.delay or 0.8) then
			return nil
		end
		local cue = seg.want
		local text = cue == "punch" and "PUNCH!" or DEF_TEXT[cue]
		local f = chip(ctx.stage, text or "?", 0, 260, cue == "punch" and T.green or T.orange)
		f.Position = UDim2.new(0.5, -130, 0.5, -34)
		if cue ~= "punch" then
			ctx.impact(-0.7, 0) -- the bag springs back toward you
		end
		local j = ctx.begin()
		ctx.on(function(id, down, t)
			if j.input(id, down, t) then
				react(id)
			end
		end)
		local okPlay = playSegment(ctx, j)
		ctx.on(nil)
		if not okPlay then
			return nil
		end
		local r = ctx.close(j)
		if r.correct then
			hits += 1
			reactSum += r.rt
			reactN += 1
			f.BackgroundColor3 = T.green
			ctx.feedback(string.format("%d ms", math.floor(r.rt * 1000)), T.green)
		elseif r.early then
			f.BackgroundColor3 = T.red
			ctx.feedback("TOO EARLY", T.red)
		elseif not r.answered and cue ~= "punch" then
			f.BackgroundColor3 = T.red
			ctx.feedback("CLIPPED!", T.red)
		else
			f.BackgroundColor3 = T.red
			ctx.feedback(r.answered and "WRONG MOVE" or "TOO SLOW", T.red)
		end
		ctx.stats(string.format("%d/%d%savg %d ms", hits, i, DOT, avgMs()))
		ctx.progress(i / cues)
		if not ctx.wait(WAIT.react) then
			return nil
		end
	end
	if not ctx.rest(WAIT.rest, "ROUND 1 DONE", string.format("%d/%d reactions%savg %d ms", hits, cues, DOT, avgMs())) then
		return nil
	end

	-- ROUND 2: SLIP & COUNTER
	ctx.setInfo("The bag swings at you: make the defensive move first, then PUNCH straight back before it settles.")
	if not ctx.round(2, rounds, "SLIP & COUNTER") then
		return nil
	end
	local counters = 0
	for i = 1, cues2 do
		UI.Clear(ctx.stage)
		local seg = ctx.peek()
		if not ctx.wait(seg.delay or 0.8) then
			return nil
		end
		local want = seg.want
		local cw = math.min(190, math.floor((stageWidth(ctx) - 60) / 2))
		local c1 = chip(ctx.stage, DEF_TEXT[want] or "?", 0, cw, T.orange)
		c1.Position = UDim2.new(0.5, -cw - 24, 0.5, -34)
		UI.Text(ctx.stage, ">", { Font = T.bold, TextSize = 20, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0.5, -24, 0.5, -34), Size = UDim2.fromOffset(48, 40), AutomaticSize = Enum.AutomaticSize.None })
		local c2 = chip(ctx.stage, "COUNTER!", 0, cw, T.panel2)
		c2.Position = UDim2.new(0.5, 24, 0.5, -34)
		ctx.impact(-0.7, 0)
		local j = ctx.begin()
		ctx.on(function(id, down, t)
			local a = j.input(id, down, t)
			if not a then
				return
			end
			react(id)
			if a.step == 2 and a.ok then
				c1.BackgroundColor3 = T.green
				c2.BackgroundColor3 = T.gold
			elseif a.step == 3 then
				c2.BackgroundColor3 = T.green
			elseif a.step == 1 then
				c1.BackgroundColor3 = T.red
			else
				c2.BackgroundColor3 = T.red
			end
		end)
		local okPlay = playSegment(ctx, j)
		ctx.on(nil)
		if not okPlay then
			return nil
		end
		local r = ctx.close(j)
		if r.step == 3 and r.rt then
			counters += 1
			reactSum += r.rt
			reactN += 1
			ctx.feedback(string.format("COUNTER!  %d ms", math.floor(r.rt * 1000)), T.gold)
		elseif r.step == 2 then
			if not r.failed then
				c2.BackgroundColor3 = T.red
			end
			ctx.feedback(r.failed and "THROW THE COUNTER" or "NO COUNTER", T.orange)
		else
			if not r.failed then
				c1.BackgroundColor3 = T.red
			end
			ctx.feedback(r.failed and "WRONG MOVE" or "CLIPPED!", T.red)
		end
		ctx.stats(string.format("Counters %d/%d%savg %d ms", counters, i, DOT, avgMs()))
		ctx.progress(i / cues2)
		if not ctx.wait(WAIT.counter) then
			return nil
		end
	end
	-- ROUND 3: REBOUNDS - punch the bag, then slip it as it comes back off your own punch
	local slipped = 0
	if cues3 > 0 then
		if not ctx.rest(WAIT.rest, "ROUND 2 DONE", string.format("%d/%d counters%savg %d ms", counters, cues2, DOT, avgMs())) then
			return nil
		end
		ctx.setInfo("PUNCH the bag, then read it coming back: slip the side shown as it RETURNS - not before. Too soon and you slip straight back into it.")
		if not ctx.round(3, rounds, "REBOUNDS") then
			return nil
		end
		for i = 1, cues3 do
			UI.Clear(ctx.stage)
			local seg = ctx.peek()
			if not ctx.wait(seg.delay or 0.6) then
				return nil
			end
			local cw = math.min(190, math.floor((stageWidth(ctx) - 60) / 2))
			local c1 = chip(ctx.stage, "PUNCH!", 0, cw, T.green)
			c1.Position = UDim2.new(0.5, -cw - 24, 0.5, -34)
			UI.Text(ctx.stage, GLYPH.next, { Font = T.bold, TextSize = 20, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0.5, -24, 0.5, -34), Size = UDim2.fromOffset(48, 40), AutomaticSize = Enum.AutomaticSize.None })
			local c2 = chip(ctx.stage, DEF_TEXT[seg.want] or "?", 0, cw, T.panel2)
			c2.Position = UDim2.new(0.5, 24, 0.5, -34)
			-- the bag's return: a bar that fills up to the moment it comes back (the gold tick)
			local track = UI.Frame(ctx.stage, { Position = UDim2.new(0, 20, 1, -22), Size = UDim2.new(1, -40, 0, 8), BackgroundColor3 = DARK })
			UI.Corner(track, 3)
			local span = seg.ret + seg.w + 0.25
			UI.Frame(track, { Position = UDim2.fromScale((seg.ret - seg.w) / span, 0), Size = UDim2.fromScale(2 * seg.w / span, 1), BackgroundColor3 = T.gold })
			local fillBar = UI.Frame(track, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.4 })
			local j = ctx.begin()
			ctx.on(function(id, down, t)
				local a = j.input(id, down, t)
				if not a then
					return
				end
				react(id)
				if a.punch then
					c1.BackgroundColor3 = T.ink
					c2.BackgroundColor3 = T.orange
					-- the bag swings back at you from the punch
					task.delay(math.max(0, seg.ret - 0.2), function()
						ctx.impact(-0.8, seg.want == "slipL" and 1 or -1)
					end)
				end
			end)
			local okPlay = playSegment(ctx, j, function(now)
				local rt = j.returnAt()
				if rt then
					fillBar.Size = UDim2.fromScale(math.clamp((now - (rt - seg.ret)) / span, 0, 1), 1)
				end
			end)
			ctx.on(nil)
			if not okPlay then
				return nil
			end
			local r = ctx.close(j)
			if r.ok then
				slipped += 1
				c2.BackgroundColor3 = T.green
				local ms = math.floor(math.abs(r.dt or 0) * 1000 + 0.5)
				ctx.feedback(ms <= 40 and "SLIPPED IT CLEAN!" or string.format("SLIPPED  %d ms %s", ms, (r.dt or 0) < 0 and "early" or "late"), ms <= 40 and T.gold or T.green)
			elseif r.early then
				c2.BackgroundColor3 = T.red
				ctx.feedback("TOO SOON - IT CAUGHT YOU", T.red)
			elseif r.punched then
				c2.BackgroundColor3 = T.red
				ctx.feedback(r.hit and "CLIPPED ON THE RETURN" or "WRONG WAY", T.red)
			else
				c1.BackgroundColor3 = T.red
				ctx.feedback("THROW THE PUNCH FIRST", T.red)
			end
			ctx.stats(string.format("Rebounds %d/%d", slipped, i))
			ctx.progress(i / cues3)
			if not ctx.wait(WAIT.rebound) then
				return nil
			end
		end
	end
	local acc = math.floor((hits + counters + slipped) / math.max(1, cues + cues2 + cues3) * 100 + 0.5)
	ctx.put("accuracy", acc)
	ctx.put("counters", counters)
	if cues3 > 0 then
		ctx.put("rebounds", slipped)
	end
	ctx.note(string.format("Avg reaction %d ms", avgMs()))
	ctx.note(string.format("%d/%d reactions%s%d/%d counters", hits, cues, DOT, counters, cues2))
	if cues3 > 0 then
		ctx.note(string.format("%d/%d rebounds slipped", slipped, cues3))
	end
	return ctx.score()
end

-- MITT WORK -------------------------------------------------------------
-- 2 rounds of called combinations (round 2 is called faster) with a rest in between
GAMES.mitts = function(ctx)
	local lv = ctx.level
	local members = workspace:FindFirstChild("GymMembers")
	local coach = members and members:FindFirstChild("Coach Benny")
	local coachName = Catalog.Stations.mitts.levels[math.clamp(lv, 1, 5)].name
	local function say(text)
		local head = coach and coach:FindFirstChild("Head")
		if head then
			pcall(function()
				TextChatService:DisplayBubble(head, text)
			end)
		end
	end
	local function pick(t)
		return t[math.random(1, #t)]
	end
	ctx.bind(actionList(PUNCH_ACTIONS, DEFENSE_ACTIONS))
	local rounds = 2
	local perRound = math.max(1, math.ceil(#ctx.plan.segs / rounds))
	local clean, thrown = 0, 0
	for rd = 1, rounds do
		ctx.setInfo(rd == 1 and (coachName .. " calls the combo - throw it back exactly. Higher-level coaches call harder combos, faster.")
			or "Same drill, faster calls. Snap every combination back before the bar runs out.")
		if not ctx.round(rd, rounds, rd == 1 and "CALLED COMBOS" or "SHARPEN UP") then
			return nil
		end
		for r = 1, perRound do
			UI.Clear(ctx.stage)
			local seg = ctx.peek()
			local ids = seg.ids or {}
			UI.Text(ctx.stage, "COACH: \"" .. tostring(seg.name) .. "!\"", { Font = T.bold, TextSize = 18, TextColor3 = T.gold, Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 24), AutomaticSize = Enum.AutomaticSize.None })
			say(tostring(seg.name) .. "!")
			-- CALL & RESPONSE: one mitt per call, dim until the coach calls it (gold; a FEINT flashes orange
			-- and must be left alone), then coloured by the answer; the bar under them is the open call's window
			local labels = {}
			for i, k in ipairs(ids) do
				labels[i] = k == "feint" and "FEINT" or (LABEL[k] or k)
			end
			local chips = chipRow(ctx, labels, 40, false, 92)
			for i in ipairs(ids) do
				chips[i].BackgroundTransparency = 0.6
			end
			local setTime = timeBar(ctx, 30, T.gold)
			local CALL_COLOR = { perfect = T.gold, good = T.green, wrong = T.red, missed = T.red, held = T.green, bitten = T.red }
			local CALL_TEXT = { perfect = { "SNAP!", T.gold }, good = { "GOOD", T.green }, wrong = { "WRONG MITT", T.red }, missed = { "TOO SLOW", T.red }, held = { "HELD THE FEINT", T.green }, bitten = { "BIT ON THE FEINT!", T.orange } }
			local function paint(k, how)
				local c = chips[k]
				if c then
					c.BackgroundTransparency = 0
					c.BackgroundColor3 = CALL_COLOR[how] or T.panel2
				end
				local ft = CALL_TEXT[how]
				if ft then
					ctx.feedback(ft[1], ft[2], false)
				end
			end
			local j, _, start = ctx.begin()
			ctx.on(function(id, down, t)
				local hit = j.input(id, down, t)
				if not hit or hit.stray then
					return
				end
				paint(hit.k, hit.how)
				if hit.how ~= "perfect" and hit.how ~= "good" then
					return
				end
				local mittSide = "R"
				if WINDUP[id] then
					local _, hand = ctx.punch(id)
					mittSide = hand
				elseif id == "slipL" or id == "slipR" then
					ctx.move("slip", id == "slipL" and "L" or "R")
					mittSide = "D"
				elseif id == "roll" then
					ctx.move("roll", "L")
					mittSide = "D"
				elseif id == "pivotL" then
					ctx.move("pivot", "L")
					mittSide = "D"
				elseif id == "parry" then
					ctx.move("parry", "R")
					mittSide = "L"
				end
				if coach then
					coach:SetAttribute("MittCall", mittSide)
					coach:SetAttribute("MittCallT", os.clock())
					local h = coach:FindFirstChild("Head")
					if h and mittSide ~= "D" then
						task.delay(WINDUP[id] or 0.2, function()
							GymVisuals.Sound(h.Position, 1.6 + math.random() * 0.15, 0.4)
						end)
					end
				end
				thrown += 1
			end)
			local lit = {}
			local span = (seg.lead or 0.5) + #ids * (seg.call or 0.6)
			while true do
				if ctx.cancelled then
					ctx.on(nil)
					return nil
				end
				local now = ctx.now()
				for _, m in ipairs(j.advance(now) or {}) do
					paint(m.k, m.how)
				end
				local open
				for k, c in ipairs(j.calls) do
					if not c.judged and now >= c.t then
						if not lit[k] then
							lit[k] = true
							chips[k].BackgroundTransparency = 0
							chips[k].BackgroundColor3 = c.feint and T.orange or T.gold
						end
						open = open or c
					end
				end
				setTime(open and (1 - (now - open.t) / (seg.window or 1)) or 0)
				ctx.progress((r - 1 + math.min(1, (now - start) / span)) / perRound)
				if j.closed then
					break
				end
				RunService.Heartbeat:Wait()
			end
			ctx.on(nil)
			local res = ctx.close(j)
			local q = DrillScore.CallScore(res)
			if q >= 0.9 then
				clean += 1
				local line = pick(Config.MittPraise)
				ctx.feedback(line, T.gold)
				say(line)
			elseif q >= 0.6 then
				local line = pick(res.bitten > 0 and { "Don't bite on the feint!", "Eyes on the mitts, not the hands!" } or Config.MittCritique.sloppy)
				ctx.feedback(line, T.orange)
				say(line)
			else
				local line = pick(Config.MittCritique.slow)
				ctx.feedback(line, T.red)
				say(line)
			end
			ctx.stats(string.format("Combo %d/%d%s%d clean", (rd - 1) * perRound + r, perRound * rounds, DOT, clean))
			ctx.progress(r / perRound)
			if not ctx.wait(WAIT.mitt) then
				return nil
			end
		end
		if rd < rounds then
			local tip = ctx.nextTip()
			if tip then
				say(tip)
			end
			if not ctx.rest(WAIT.restLong, "ROUND 1 DONE", string.format("%d/%d clean combos", clean, perRound), tip) then
				return nil
			end
		end
	end
	ctx.put("cleanCombos", clean)
	ctx.put("punches", thrown)
	ctx.note(string.format("%d/%d clean combos", clean, perRound * rounds))
	ctx.note(string.format("%d shots & moves", thrown))
	return ctx.score()
end

-- SHADOW BOXING ---------------------------------------------------------
local SHADOW_PROMPTS = {
	{ id = "F", text = "STEP IN", keys = { K.W, K.Up } }, { id = "B", text = "STEP BACK", keys = { K.S, K.Down } },
	{ id = "L", text = "CIRCLE LEFT", keys = { K.A, K.Left } }, { id = "R", text = "CIRCLE RIGHT", keys = { K.D, K.Right } },
	{ id = "slipL", text = "SLIP LEFT", keys = { K.Q }, map = "slipL" }, { id = "slipR", text = "SLIP RIGHT", keys = { K.E }, map = "slipR" },
	{ id = "roll", text = "ROLL", keys = { K.C }, map = "dodge" }, { id = "jab", text = "JAB", keys = { K.J }, map = "jab" }, { id = "cross", text = "CROSS", keys = { K.K }, map = "cross" },
	{ id = "leadhook", text = "HOOK", keys = { K.L }, map = "leadhook" },
}
local SHADOW_TEXT = {}
for _, p in ipairs(SHADOW_PROMPTS) do
	SHADOW_TEXT[p.id] = p.text
end
local SHADOW_LABEL = { F = "STEP IN", B = "STEP BACK", L = "CIRCLE L", R = "CIRCLE R", slipL = "SLIP L", slipR = "SLIP R", roll = "ROLL", jab = "JAB", cross = "CROSS", leadhook = "HOOK" }

local function shadowMove(ctx, id)
	if id == "F" or id == "B" or id == "L" or id == "R" then
		ctx.move("step", id)
	elseif id == "slipL" or id == "slipR" then
		ctx.move("slip", id == "slipL" and "L" or "R")
	elseif id == "roll" then
		ctx.move("roll", "L")
	elseif WINDUP[id] then
		ctx.punch(id)
	end
end

-- 2 rounds: single moves on cue, then flow chains of mixed moves
GAMES.shadow = function(ctx)
	local lv = ctx.level
	local actions = {}
	for _, p in ipairs(SHADOW_PROMPTS) do
		table.insert(actions, { id = p.id, label = (p.text:gsub("CIRCLE ", ""):gsub("STEP ", "")), keys = p.keys, map = p.map })
	end
	ctx.bind(actions, 5)
	local function mirror(text)
		if lv >= 3 then
			GymVisuals.SetDisplay("mirror", text)
		end
	end
	local n, chains, steps = 0, 0, 0
	for _, seg in ipairs(ctx.plan.segs) do
		if seg.j == "cue" then
			n += 1
		elseif seg.j == "notes" then
			steps += 1
		else
			chains += 1
		end
	end
	local rounds = steps > 0 and 3 or 2

	-- ROUND 1: MOVES
	ctx.setInfo("Footwork (W/A/S/D), head movement ({slipL}/{slipR}/{dodge}) and punches ({jab}/{cross}/{leadhook}): follow the prompts in the mirror.")
	if not ctx.round(1, rounds, "MOVES") then
		return nil
	end
	local score, movesHit = 0, 0
	for i = 1, n do
		UI.Clear(ctx.stage)
		local seg = ctx.peek()
		if not ctx.wait(seg.delay or 0.3) then
			return nil
		end
		local f = chip(ctx.stage, SHADOW_TEXT[seg.want] or "?", 0, 240, T.panel2)
		f.Position = UDim2.new(0.5, -120, 0.5, -34)
		local j = ctx.begin()
		ctx.on(function(id, down, t)
			if j.input(id, down, t) then
				shadowMove(ctx, id)
			end
		end)
		local okPlay = playSegment(ctx, j)
		ctx.on(nil)
		if not okPlay then
			return nil
		end
		local r = ctx.close(j)
		if r.correct then
			score += 1 - 0.35 * r.rt / seg.window
			movesHit += 1
			f.BackgroundColor3 = T.green
		else
			f.BackgroundColor3 = T.red
			ctx.feedback(r.early and "TOO EARLY" or (r.answered and "WRONG MOVE" or "TOO SLOW"), T.red)
		end
		local form = math.floor(score / i * 100)
		mirror(string.format("FORM %d%%", form))
		ctx.stats(string.format("Move %d/%d%sform %d%%", i, n, DOT, form))
		ctx.progress(i / n)
		if not ctx.wait(WAIT.move) then
			return nil
		end
	end
	if not ctx.rest(WAIT.rest, "ROUND 1 DONE", string.format("%d/%d moves on cue", movesHit, n)) then
		return nil
	end

	-- ROUND 2: FOOTWORK PATTERNS - named step patterns on the beat, four lanes (in, back, left, right)
	local onBeat, stepCount = 0, 0
	if steps > 0 then
		local seg = ctx.peek()
		ctx.setInfo(string.format("Step the patterns on the beat (W/A/S/D or arrows): each arrow as it reaches the gold line. %d BPM - stay on the balls of your feet.", seg.bpm or 80))
		if not ctx.round(2, rounds, seg.name or "FOOTWORK", "ROUND") then
			return nil
		end
		UI.Clear(ctx.stage)
		local lineX = 70
		local LANE_Y = { F = 16, L = 40, R = 64, B = 88 }
		local LANE_TEXT = { F = GLYPH.up .. " IN", L = GLYPH.left .. " LEFT", R = GLYPH.right .. " RIGHT", B = GLYPH.down .. " BACK" }
		for id, y in pairs(LANE_Y) do
			UI.Text(ctx.stage, LANE_TEXT[id], { Font = T.semi, TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(4, y - 7), Size = UDim2.fromOffset(52, 14), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		end
		UI.Frame(ctx.stage, { Position = UDim2.new(0, lineX - 2, 0, 4), Size = UDim2.new(0, 4, 1, -8), BackgroundColor3 = T.gold })
		local j, sg, M = ctx.begin()
		local frames = {}
		for i, nt in ipairs(j.notes) do
			local f = UI.Frame(ctx.stage, { Size = UDim2.fromOffset(22, 20), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(NOTE_FAR, LANE_Y[nt.lane] or 50), BackgroundColor3 = T.blue })
			UI.Corner(f, 6)
			frames[i] = f
		end
		local streak = 0
		ctx.on(function(id, down, t)
			if not down then
				return
			end
			local hit = j.input(id, down, t)
			if hit and (hit.stray or hit.grade) then
				shadowMove(ctx, id)
			end
			if hit and hit.stray then
				streak = 0
				ctx.feedback("OFF THE BEAT", T.orange)
			elseif hit and hit.grade then
				frames[hit.note].Visible = false
				if hit.grade == "off" then
					streak = 0
					ctx.feedback("LATE FEET", T.orange)
				else
					streak += 1
					ctx.feedback(hit.grade == "perfect" and ("ON THE BEAT x" .. streak) or "GOOD STEP", hit.grade == "perfect" and T.gold or T.green)
				end
			end
		end)
		local pps = 200
		local start = M + sg.lead
		while true do
			if ctx.cancelled then
				ctx.on(nil)
				return nil
			end
			local now = ctx.now()
			for _ in ipairs(j.advance(now) or {}) do
				streak = 0
				ctx.feedback("MISSED STEP", T.red)
			end
			local alive = false
			for i, nt in ipairs(j.notes) do
				local f = frames[i]
				if nt.judged then
					if f.Visible then
						f.Visible = false
					end
				else
					alive = true
					local x = lineX + (nt.t - now) * pps
					if x < NOTE_FAR then
						f.Position = UDim2.fromOffset(x, LANE_Y[nt.lane] or 50)
					end
				end
			end
			ctx.progress((now - start) / math.max(1, #sg.lanes * sg.interval))
			if not alive or j.closed then
				break
			end
			RunService.Heartbeat:Wait()
		end
		ctx.on(nil)
		local r = ctx.close(j)
		onBeat, stepCount = r.hits, r.count
		if not ctx.wait(WAIT.steps) then
			return nil
		end
		if not ctx.rest(WAIT.rest, "ROUND 2 DONE", string.format("%d/%d steps on the beat", r.hits, r.count)) then
			return nil
		end
	end

	-- FLOW - chains of 3-4 mixed moves
	ctx.setInfo("Flow through each chain in order: punches, head movement and footwork blended together. Smooth beats fast.")
	if not ctx.round(rounds, rounds, "FLOW") then
		return nil
	end
	local score2, flowsClean = 0, 0
	for ci = 1, chains do
		UI.Clear(ctx.stage)
		local seg = ctx.peek()
		local seq = seg.ids or {}
		local labels = {}
		for k, id in ipairs(seq) do
			labels[k] = SHADOW_LABEL[id] or id
		end
		local chips = chipRow(ctx, labels, 36, true, 110)
		local setTime = timeBar(ctx, 14)
		local limit = seg.limit or 3
		chips[1].BackgroundColor3 = T.gold
		local j, _, start = ctx.begin()
		ctx.on(function(id, down, t)
			local hit = j.input(id, down, t)
			if hit then
				shadowMove(ctx, id)
				seqChips(j, chips, hit)
			end
		end)
		local okPlay = playSegment(ctx, j, function(now)
			local el = now - start
			setTime(1 - el / limit)
			ctx.progress((ci - 1 + math.min(1, el / limit)) / chains)
		end)
		ctx.on(nil)
		if not okPlay then
			return nil
		end
		local res = ctx.close(j)
		score2 += DrillScore.SeqScore(res, 0.8, 0.4, 1)
		if res.complete and res.wrong == 0 then
			flowsClean += 1
			ctx.feedback(res.frac > 0.4 and "FLOWING!" or "SMOOTH", T.gold)
		elseif res.complete then
			ctx.feedback("CHOPPY", T.orange)
		else
			ctx.feedback("LOST THE FLOW", T.red)
		end
		mirror(string.format("FLOW %d/%d\nFORM %d%%", ci, chains, math.floor(score2 / ci * 100)))
		ctx.stats(string.format("Flow %d/%d%s%d clean", ci, chains, DOT, flowsClean))
		ctx.progress(ci / chains)
		if not ctx.wait(WAIT.flow) then
			return nil
		end
	end
	local r2 = math.clamp(score2 / math.max(1, chains), 0, 1)
	local acc = math.floor((movesHit / math.max(1, n) * 0.5 + r2 * 0.5) * 100 + 0.5)
	ctx.put("accuracy", acc)
	ctx.put("cleanFlows", flowsClean)
	if stepCount > 0 then
		ctx.put("footwork", math.floor(onBeat / stepCount * 100 + 0.5))
		ctx.note(string.format("%d/%d steps on the beat", onBeat, stepCount))
	end
	ctx.note(string.format("%d/%d moves", movesHit, n))
	ctx.note(string.format("%d/%d clean flows", flowsClean, chains))
	return ctx.score()
end

-- STRENGTH --------------------------------------------------------------
-- a believable working load from the Power stat, the trained muscle group and the station level
local function liftLoad(ctx)
	local def = Config.LiftLoads[ctx.act.id]
	if not def then
		return nil, nil, nil
	end
	local P = State.P
	local power = P and P.stats and P.stats.Power or 40
	-- the exercise's own sub-muscle sets the load (falls back to its group for old summaries)
	local muscle = P and P.body and (def.part and Config.PartValue and Config.PartValue(P.body, def.part) or P.body[def.muscle]) or 10
	local st = Catalog.Stations[ctx.station]
	local maxLv = st and #st.levels or 4
	local s = math.clamp((power - 20) / 79, 0, 1) * 0.6 + math.clamp(muscle / 100, 0, 1) * 0.25
		+ (maxLv > 1 and math.clamp((ctx.level - 1) / (maxLv - 1), 0, 1) or 0) * 0.15
	if def.bodyweight then
		-- body weight first, then a weight belt
		local add = math.floor(math.max(0, (s - 0.35) / 0.65) * def.max / 5 + 0.5) * 5
		return add, add > 0 and ("BW +" .. add .. " lbs") or "BW", def.name, true
	end
	local load = math.floor((def.min + (def.max - def.min) * s) / 5 + 0.5) * 5
	return load, string.format(def.each and "%d lbs each" or "%d lbs", load), def.name, false
end

-- one lift / slam on the plan's zone (DrillScore lift judge: hold-type drills take TAPS too - a quick
-- tap starts the hold and the next tap ends it; a press held longer still works as a plain hold).
-- Waits for the press, raises the bar until the release (or the top), returns the result or nil.
local function liftRep(ctx, zone, fill, intensity)
	local seg = ctx.peek()
	zone.Position = UDim2.fromScale(seg.lo or 0.6, 0)
	zone.Size = UDim2.fromScale(seg.width or 0.2, 1)
	ctx.intensity = intensity[1]
	local j = ctx.begin()
	if not j then
		return nil
	end
	ctx.on(function(id, down, t)
		j.input(id, down, t)
	end)
	local working = false
	while not j.closed do
		if ctx.cancelled then
			ctx.on(nil)
			return nil
		end
		if j.holdStart and not working then
			working = true
			ctx.intensity = intensity[2]
		end
		local f = j.advance(ctx.now())
		fill.Size = UDim2.fromScale(f, 1)
		ctx.drive(f)
		if j.closed then
			break
		end
		RunService.Heartbeat:Wait()
	end
	ctx.on(nil)
	local res = ctx.close(j)
	fill.Size = UDim2.fromScale(res.f, 1)
	ctx.drive(res.f)
	return res
end

-- 2 sets x 5 reps: hold to lift, release in the green zone (set 2 is tighter); a spotter saves failed reps
GAMES.reps = function(ctx)
	local load, loadText, exName, bodyweight = liftLoad(ctx)
	exName = exName or ctx.act.name:upper()
	local sets, reps = 0, 0
	for _, seg in ipairs(ctx.plan.segs) do
		sets = math.max(sets, seg.set or 1)
		reps = math.max(reps, seg.rep or 1)
	end
	ctx.bind({ { id = "lift", label = "TAP / HOLD: LIFT", say = "LIFT", keys = { K.Space }, color = T.blue } }, 1)
	ctx.setInfo("Tap SPACE (or the button) to drive the weight up and tap again inside the green zone (holding and releasing works too). Overshoot and you fail the rep. Set 2 is tighter.")
	UI.Clear(ctx.stage)
	local barBg = UI.Frame(ctx.stage, { Position = UDim2.new(0, 20, 0, 18), Size = UDim2.new(1, -40, 0, 34), BackgroundColor3 = Color3.fromRGB(40, 20, 20) })
	UI.Corner(barBg, 6)
	local zone = UI.Frame(barBg, { BackgroundColor3 = T.green, Size = UDim2.fromScale(0.2, 1) })
	UI.Corner(zone, 6)
	local fill = UI.Frame(barBg, { BackgroundColor3 = T.gold, BackgroundTransparency = 0.25, Size = UDim2.fromScale(0, 1) })
	UI.Corner(fill, 6)
	UI.Text(ctx.stage, loadText or "", { Font = T.bold, TextColor3 = T.gold, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 56), Size = UDim2.new(0.4, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Right, AutomaticSize = Enum.AutomaticSize.None })
	local P = State.P
	local fatigue = P and P.condition and P.condition.fatigue or 0
	local goodReps, fails, lastRpe = 0, 0, 6
	local function rpeText(v)
		return "RPE " .. (v % 1 == 0 and tostring(math.floor(v)) or string.format("%.1f", v))
	end
	local LIFT_EFFORT = { 0.3, 0.85 }
	for set = 1, sets do
		if not ctx.round(set, sets, exName, "SET") then
			return nil
		end
		local setGood, setFails = 0, 0
		ctx.setRep(1, reps, 0)
		ctx.stats(nil)
		for r = 1, reps do
			ctx.setRep(r, reps, setGood)
			ctx.attr("RepCount", (set - 1) * reps + r)
			local res = liftRep(ctx, zone, fill, LIFT_EFFORT)
			if not res then
				return nil
			end
			local f = res.f
			if res.verdict == "none" then
				ctx.feedback("NO LIFT", T.red)
			elseif res.failed then
				fails += 1
				setFails += 1
				ctx.feedback("SPOTTER: I got you!", T.orange)
			elseif res.verdict == "perfect" or res.verdict == "good" then
				goodReps += 1
				setGood += 1
				-- the worked muscles fill up rep by rep (BodyFX reads LivePump; CONTRACTS s.7)
				ctx.pump(res.verdict == "perfect" and 0.1 or 0.07)
				ctx.feedback(res.verdict == "perfect" and "PERFECT REP" or "GOOD REP", res.verdict == "perfect" and T.gold or T.green)
			else
				if res.verdict == "short" then
					ctx.pump(0.03) -- a half rep still moves blood, just less
				end
				ctx.feedback(res.verdict == "short" and "HALF REP" or "LOST CONTROL", T.orange)
			end
			-- lower the weight
			ctx.intensity = 0.5
			local t0 = os.clock()
			while os.clock() - t0 < WAIT.lower do
				if ctx.cancelled then
					return nil
				end
				local k = (os.clock() - t0) / WAIT.lower
				ctx.drive(f * (1 - k))
				fill.Size = UDim2.fromScale(f * (1 - k), 1)
				RunService.Heartbeat:Wait()
			end
			ctx.drive(0)
			fill.Size = UDim2.fromScale(0, 1)
			ctx.setRep(r, reps, setGood)
			ctx.stats(setFails > 0 and string.format("%d spotted", setFails) or nil)
			ctx.progress(r / reps)
			if not ctx.wait(WAIT.rerack) then
				return nil
			end
		end
		-- how hard that set felt (rate of perceived exertion, 6-10)
		local rpe = math.clamp(6 + setFails * 1.2 + (reps - setGood) * 0.35 + (set - 1) * 0.6 + fatigue / 50, 6, 10)
		rpe = math.floor(rpe * 2 + 0.5) / 2
		lastRpe = rpe
		ctx.intensity = nil
		if set < sets then
			local left = math.max(0, math.floor(10 - rpe))
			if not ctx.rest(WAIT.rest, string.format("SET %d DONE%s%s", set, DOT, rpeText(rpe)), string.format("%d/%d good reps%s%s", setGood, reps, DOT, left > 0 and (left .. " more in the tank") or "nothing left in the tank")) then
				return nil
			end
		else
			ctx.feedback(rpeText(rpe), rpe >= 9 and T.red or (rpe >= 8 and T.orange or T.green))
		end
	end
	ctx.intensity = nil
	ctx.put(bodyweight and "addedLoad" or "load", load or 0)
	ctx.put("goodReps", goodReps)
	if load and not bodyweight then
		ctx.put("volume", load * goodReps)
	end
	ctx.note(exName .. (loadText and (" " .. loadText) or ""))
	ctx.note(string.format("%d/%d good reps", goodReps, sets * reps))
	if fails > 0 then
		ctx.note(string.format("%d spotted", fails))
	end
	ctx.note(rpeText(lastRpe))
	if not ctx.wait(0.3) then
		return nil
	end
	return ctx.score()
end

-- MEDICINE BALL ---------------------------------------------------------
-- Set 1 SLAMS: hold to drive the ball overhead, release in the green zone and the ball is slammed
-- into the pad (the station thumps, the dust flies). Set 2 PLANK ON THE BALL: the ball rolls under
-- your hands, LEFT / RIGHT shoves keep it in the green (TwistSide drives the Animator's rotation).
-- Abs and obliques get the live pump with every clean rep and every steady stretch.
GAMES.medball = function(ctx)
	local load, loadText = liftLoad(ctx)
	loadText = loadText or "MED BALL"
	local slams = 0
	for _, seg in ipairs(ctx.plan.segs) do
		if seg.j == "lift" then
			slams += 1
		end
	end
	-- SET 1: SLAMS
	ctx.bind({ { id = "lift", label = "TAP: RAISE  /  TAP: SLAM", say = "SLAM", keys = { K.Space }, color = T.gold } }, 1)
	if ctx.buttons.lift then
		ctx.buttons.lift.TextColor3 = T.bg
	end
	ctx.setInfo("Tap SPACE to drive the ball overhead, tap again inside the green zone to SLAM it (or hold and release). Brace your core - power comes from the trunk, not the arms.")
	if not ctx.round(1, 2, "SLAMS" .. DOT .. loadText, "SET") then
		return nil
	end
	ctx.stats(nil)
	UI.Clear(ctx.stage)
	local barBg = UI.Frame(ctx.stage, { Position = UDim2.new(0, 20, 0, 18), Size = UDim2.new(1, -40, 0, 34), BackgroundColor3 = Color3.fromRGB(40, 20, 20) })
	UI.Corner(barBg, 6)
	local zone = UI.Frame(barBg, { BackgroundColor3 = T.green, Size = UDim2.fromScale(0.2, 1) })
	UI.Corner(zone, 6)
	local fill = UI.Frame(barBg, { BackgroundColor3 = T.gold, BackgroundTransparency = 0.25, Size = UDim2.fromScale(0, 1) })
	UI.Corner(fill, 6)
	local cleanSlams = 0
	local SLAM_EFFORT = { 0.35, 0.9 }
	for r = 1, slams do
		ctx.setRep(r, slams, cleanSlams)
		ctx.attr("RepCount", r)
		local res = liftRep(ctx, zone, fill, SLAM_EFFORT)
		if not res then
			return nil
		end
		local f = res.f
		if res.verdict == "none" then
			ctx.feedback("NO SLAM", T.red)
		elseif res.failed then
			ctx.feedback("OVERREACHED - BRACE!", T.orange)
		elseif res.verdict == "perfect" or res.verdict == "good" then
			cleanSlams += 1
			ctx.feedback(res.verdict == "perfect" and "MONSTER SLAM!" or "GOOD SLAM", res.verdict == "perfect" and T.gold or T.green)
			ctx.pump(0.08)
		else
			ctx.feedback(res.verdict == "short" and "ALL ARMS - GET IT OVERHEAD" or "LOST THE BRACE", T.orange)
		end
		-- the slam: drive down fast, the ball hits the pad
		local t0 = os.clock()
		while os.clock() - t0 < WAIT.slam do
			if ctx.cancelled then
				return nil
			end
			ctx.drive(f * (1 - (os.clock() - t0) / WAIT.slam))
			RunService.Heartbeat:Wait()
		end
		ctx.drive(0)
		ctx.impact(0.6 + res.q * 0.7, 0, "slam", "body")
		fill.Size = UDim2.fromScale(0, 1)
		ctx.setRep(r, slams, cleanSlams)
		ctx.progress(r / slams)
		if not ctx.wait(WAIT.catch) then
			return nil
		end
		-- catch it off the bounce
		ctx.impact(-0.3, 0)
	end
	ctx.intensity = nil
	if not ctx.rest(WAIT.rest, "SLAMS DONE", string.format("%d/%d clean slams", cleanSlams, slams)) then
		return nil
	end

	-- SET 2: PLANK ON THE BALL - hands on the ball, it wants to roll out from under you: LEFT / RIGHT
	-- shoves keep the balance marker in the green (the obliques brace against every roll)
	ctx.bind({ { id = "L", label = "SHOVE LEFT", keys = { K.Q, K.A, K.J }, color = T.blue }, { id = "R", label = "SHOVE RIGHT", keys = { K.E, K.D, K.K }, color = T.red } }, 2)
	ctx.setInfo("Plank with your hands on the ball - it rolls under you. Tap LEFT / RIGHT to shove it back and keep the marker in the green. Brace, don't chase it.")
	if not ctx.round(2, 2, "PLANK ON THE BALL", "SET") then
		return nil
	end
	ctx.clearRep()
	UI.Clear(ctx.stage)
	local j, seg, M = ctx.begin()
	if not j then
		return nil
	end
	local W2 = DrillScore.Workouts
	local band = seg.band or 0.3
	local track = UI.Frame(ctx.stage, { Position = UDim2.new(0, 24, 0, 28), Size = UDim2.new(1, -48, 0, 32), BackgroundColor3 = Color3.fromRGB(30, 30, 38) })
	UI.Corner(track, 16)
	local green = UI.Frame(track, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(band, 1), BackgroundColor3 = T.green, BackgroundTransparency = 0.4 })
	UI.Corner(green, 16)
	UI.Frame(track, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = T.gold, BackgroundTransparency = 0.5 })
	local ball = UI.Frame(track, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = T.gold })
	UI.Corner(ball, 13)
	UI.Text(ctx.stage, GLYPH.left .. " SHOVE", { Font = T.semi, TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(24, 64), Size = UDim2.fromOffset(80, 14), AutomaticSize = Enum.AutomaticSize.None })
	UI.Text(ctx.stage, "SHOVE " .. GLYPH.right, { Font = T.semi, TextSize = 11, TextColor3 = T.sub, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 64), Size = UDim2.fromOffset(80, 14), TextXAlignment = Enum.TextXAlignment.Right, AutomaticSize = Enum.AutomaticSize.None })
	local setTime = timeBar(ctx, 84, T.blue)
	local lost, steadyAt, partialAt = 0, M, -math.huge
	ctx.intensity = 0.6
	ctx.on(function(id, down, t)
		if not down then
			return
		end
		if j.input(id, down, t) then
			ctx.attr("TwistSide", id == "L" and -1 or 1)
			ctx.impact(-0.15, id == "L" and -1 or 1)
		end
	end)
	while true do
		if ctx.cancelled then
			ctx.on(nil)
			return nil
		end
		local now = ctx.now()
		j.advance(now)
		local x = j.x
		local ax = math.abs(x)
		ball.Position = UDim2.fromScale(0.5 + 0.5 * x, 0.5)
		ball.BackgroundColor3 = ax <= band and T.green or (ax <= 2 * band and T.gold or T.red)
		if j.lost > lost then
			lost = j.lost
			steadyAt = now
			ctx.feedback("ROLLED OFF IT!", T.red)
		elseif ax <= band then
			if now - steadyAt >= 3 then
				steadyAt = now
				ctx.feedback("ROCK SOLID", T.gold)
				ctx.pump(0.05)
			end
		else
			steadyAt = now
		end
		setTime(1 - (now - M) / seg.duration)
		ctx.progress((now - M) / seg.duration)
		if now - partialAt >= 0.25 then
			partialAt = now
			ctx.partial = { w = 1, g = math.clamp(j.acc * W2.TICK / math.max(0.01, now - M) / W2.TIMED_FULL, 0, 1) }
			ctx.updateMetrics()
		end
		ctx.stats(string.format("%.1f s in the green%s%d slips", j.inBand * W2.TICK, DOT, j.lost))
		if j.closed then
			break
		end
		RunService.Heartbeat:Wait()
	end
	ctx.on(nil)
	local res = ctx.close(j)
	ctx.partial = nil
	ctx.intensity = nil
	ctx.attr("TwistSide", 0)
	local coreQ = math.clamp(res.acc / math.max(0.1, res.duration) / W2.TIMED_FULL - 0.1 * res.lost, 0, 1)
	ctx.feedback(coreQ >= 0.9 and "IRON CORE" or (coreQ >= 0.65 and "SOLID PLANK" or "SHAKY"), ctx.gradeColor(coreQ), coreQ)
	ctx.put("load", load or 0)
	ctx.put("cleanSlams", cleanSlams)
	ctx.put("plankSec", math.floor(res.inBand * 10 + 0.5) / 10)
	ctx.put("slips", res.lost)
	ctx.note(string.format("%s%s%d/%d clean slams", loadText, DOT, cleanSlams, slams))
	ctx.note(string.format("%.1f s steady on the ball%s%d slips", res.inBand, DOT, res.lost))
	if not ctx.wait(0.3) then
		return nil
	end
	return ctx.score()
end

-- CARDIO MACHINES -------------------------------------------------------
local INCLINE = { 1.0, 2.0, 0.5, 4.0 } -- treadmill incline per interval

-- tap to hold the pace inside each interval zone; the machine shows its own readouts
GAMES.pace = function(ctx)
	local lv = ctx.level
	local id = ctx.act.id
	local seg = ctx.peek()
	local phases = seg.phases or { { 0.3, 0.5, "WARM-UP" } }
	ctx.bind({ { id = "push", label = "PUSH PACE", keys = { K.Space }, color = T.blue } }, 1)
	ctx.setInfo("Tap SPACE to speed up. Keep the marker inside the green zone through every interval: warm-up, sprint, recover, all out.")
	if not ctx.round(1, #phases, phases[1][3], "INTERVAL") then
		return nil
	end
	UI.Clear(ctx.stage)
	local barBg = UI.Frame(ctx.stage, { Position = UDim2.new(0, 20, 0, 12), Size = UDim2.new(1, -40, 0, 30), BackgroundColor3 = Color3.fromRGB(25, 25, 32) })
	UI.Corner(barBg, 6)
	local zone = UI.Frame(barBg, { BackgroundColor3 = T.green, BackgroundTransparency = 0.3, Size = UDim2.fromScale(0.2, 1) })
	UI.Corner(zone, 6)
	local marker = UI.Frame(barBg, { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(0, 6, 1, 10), Position = UDim2.new(0, 0, 0, -5) })
	local metrics = UI.Text(ctx.stage, "", { Font = T.semi, TextSize = 15, TextColor3 = Color3.fromRGB(120, 220, 255), Position = UDim2.fromOffset(20, 50), Size = UDim2.new(1, -40, 0, 22), AutomaticSize = Enum.AutomaticSize.None })
	local status = UI.Text(ctx.stage, "", { Font = T.bold, Position = UDim2.fromOffset(20, 76), Size = UDim2.new(1, -40, 0, 24), AutomaticSize = Enum.AutomaticSize.None })
	-- the last interval's verdict (its time in the zone) at the readout line's right end for a moment
	local verdict = UI.Text(ctx.stage, "", { Font = T.bold, TextSize = 15, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 50), Size = UDim2.new(0.45, 0, 0, 22),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
	-- the pace judge: each press speeds up, the pace drains; the time in the zone is the score
	local j, _, start = ctx.begin()
	if not j then
		return nil
	end
	local duration = seg.duration or 28
	ctx.on(function(i, down, t)
		j.input(i, down, t)
	end)
	local last = ctx.now()
	local miles, meters, topSpeed, maxWatts, maxSpm, rpmSum, rpmTime = 0, 0, 0, 0, 0, 0, 0
	local phaseIdx, sinceScreen = 1, 1
	local screen = ""
	-- the strip grades each interval by its time in the zone (on the session's scale: DrillScore.PACE_FULL
	-- of it in the zone is full marks): CLEAN counts the intervals held, QUALITY averages them with the
	-- interval in progress counting by the share run so far
	local len = duration / #phases
	local zoneAt, partial, verdictAt = 0, { g = 0, w = 0 }, -math.huge
	local function gradeInterval(pi)
		local share = math.clamp((j.inZone - zoneAt) / len, 0, 1)
		local g = math.clamp(share / DrillScore.PACE_FULL, 0, 1)
		zoneAt = j.inZone
		ctx.grade(g)
		verdict.Text = string.format("%s %d%% IN ZONE", (string.gsub(phases[pi][3], "!", "")), math.floor(share * 100 + 0.5))
		verdict.TextColor3 = ctx.gradeColor(g)
		verdictAt = ctx.now()
	end
	-- the readouts are text: they are rewritten about 15 times a second (and at once when the marker
	-- crosses into or out of the zone); the marker itself moves every frame
	local textAt, lastOk = -math.huge, nil
	local zoneOf = nil
	while true do
		if ctx.cancelled then
			ctx.on(nil)
			return nil
		end
		local now = ctx.now()
		local dt = now - last
		last = now
		local el = now - start
		local v = j.advance(now)
		if el >= duration then
			break
		end
		local pi = j.phaseOf(now)
		if pi ~= phaseIdx then
			gradeInterval(phaseIdx)
			phaseIdx = pi
			ctx.round(pi, #phases, phases[pi][3], "INTERVAL", 0)
		end
		local ph = phases[pi]
		local lo, hi = ph[1], ph[2]
		if zoneOf ~= pi then
			zoneOf = pi
			zone.Position = UDim2.fromScale(lo, 0)
			zone.Size = UDim2.fromScale(hi - lo, 1)
		end
		marker.Position = UDim2.new(v, -3, 0, -5)
		local ok = v >= lo and v <= hi
		ctx.intensity = 0.25 + v * 0.75
		ctx.speed(0.5 + v * 1.6)
		-- machine readouts (the totals add up every frame, the text is written at the readout rate)
		local rpm, split, spm, mph
		if id == "Bike" then
			rpm = 50 + v * 70
			local watts = 0.022 * rpm * rpm * (0.9 + 0.12 * lv)
			maxWatts = math.max(maxWatts, watts)
			rpmSum += rpm * dt
			rpmTime += dt
		elseif id == "Rower" then
			split = 165 - v * 70 -- seconds per 500 m
			spm = 18 + v * 18
			meters += 500 / split * dt * TIME_SCALE
			maxSpm = math.max(maxSpm, spm)
		else
			mph = 3 + v * 10
			miles += mph / 3600 * dt * TIME_SCALE
			topSpeed = math.max(topSpeed, mph)
		end
		sinceScreen += dt
		if now - textAt >= 0.066 or ok ~= lastOk or sinceScreen >= 0.25 then
			textAt, lastOk = now, ok
			local readout
			if id == "Bike" then
				local watts = 0.022 * rpm * rpm * (0.9 + 0.12 * lv)
				readout = string.format("%d RPM%s%d W", math.floor(rpm), DOT, math.floor(watts))
				screen = string.format("RPM %d\n%d WATTS", math.floor(rpm), math.floor(watts))
			elseif id == "Rower" then
				readout = string.format("%s /500m%s%d spm%s%d m", clock(split), DOT, math.floor(spm), DOT, math.floor(meters))
				screen = string.format("%s /500\n%d SPM\n%d m", clock(split), math.floor(spm), math.floor(meters))
			else
				local incline = INCLINE[pi] + (lv >= 3 and 2 or 0)
				readout = string.format("%.1f mph%s%.1f%% incline%s%.2f mi", mph, DOT, incline, DOT, miles)
				screen = string.format("%.1f MPH\nINCLINE %.1f%%\n%.2f mi", mph, incline, miles)
			end
			metrics.Text = readout
			status.Text = string.format("%s   %s   %.1fs left", ph[3], ok and "IN ZONE" or (v < lo and "FASTER!" or "EASE OFF"), duration - el)
			status.TextColor3 = ok and T.green or T.orange
			ctx.stats(readout)
		end
		if sinceScreen >= 0.25 then
			sinceScreen = 0
			GymVisuals.SetDisplay(ctx.station, screen)
			if verdictAt > -math.huge and now - verdictAt > 3 then
				verdictAt = -math.huge
				verdict.Text = ""
			end
			-- the interval so far on the strip (a few times a second is plenty for a percentage)
			local into = el - (phaseIdx - 1) * len
			partial.w = math.clamp(into / len, 0, 1)
			partial.g = into > 0 and math.clamp((j.inZone - zoneAt) / into / DrillScore.PACE_FULL, 0, 1) or 0
			ctx.partial = partial
			ctx.updateMetrics()
		end
		ctx.setProgress(el / duration)
		RunService.Heartbeat:Wait()
	end
	ctx.on(nil)
	local res = ctx.close(j)
	gradeInterval(phaseIdx)
	ctx.intensity = nil
	ctx.speed(1)
	local zonePct = math.floor(res.inZone / duration * 100 + 0.5)
	if id == "Bike" then
		local avgRpm = rpmTime > 0 and rpmSum / rpmTime or 0
		ctx.put("maxWatts", math.floor(maxWatts))
		ctx.put("avgRpm", math.floor(avgRpm))
		ctx.note(string.format("Max %d W", math.floor(maxWatts)))
		ctx.note(string.format("avg %d RPM", math.floor(avgRpm)))
		GymVisuals.SetDisplay(ctx.station, string.format("DONE\nMAX %d W", math.floor(maxWatts)))
	elseif id == "Rower" then
		ctx.put("meters", math.floor(meters))
		ctx.put("maxSpm", math.floor(maxSpm))
		ctx.note(string.format("%d m rowed", math.floor(meters)))
		ctx.note(string.format("max %d spm", math.floor(maxSpm)))
		GymVisuals.SetDisplay(ctx.station, string.format("DONE\n%d m", math.floor(meters)))
	else
		ctx.put("distance", math.floor(miles * 100 + 0.5) / 100)
		ctx.put("topSpeed", math.floor(topSpeed * 10 + 0.5) / 10)
		ctx.note(string.format("%.2f mi", miles))
		ctx.note(string.format("top %.1f mph", topSpeed))
		GymVisuals.SetDisplay(ctx.station, string.format("DONE\n%.2f mi", miles))
	end
	ctx.put("inZone", zonePct)
	ctx.note(string.format("%d%% in zone", zonePct))
	return ctx.score()
end

-- AGILITY LADDER --------------------------------------------------------
local LADDER_DIRS = {
	{ id = "F", label = "UP", keys = { K.W, K.Up }, arrow = GLYPH.up }, { id = "L", label = "LEFT", keys = { K.A, K.Left }, arrow = GLYPH.left },
	{ id = "B", label = "DOWN", keys = { K.S, K.Down }, arrow = GLYPH.down }, { id = "R", label = "RIGHT", keys = { K.D, K.Right }, arrow = GLYPH.right },
}
local LADDER_PAD = { F = 1, L = 3, B = 4, R = 2 } -- reaction pods: forward, right, left, back
local LADDER_COLOR = { F = T.blue, B = T.red, L = T.green, R = T.gold }

-- STEPPED PATTERNS: a named drill's steps (arrows) slide along the ladder to the foot line on a beat
-- that quickens through the drill; the smart ladder at the top level ends with random reaction lights
GAMES.ladder = function(ctx)
	local dirById = {}
	for _, d in ipairs(LADDER_DIRS) do
		dirById[d.id] = d
	end
	ctx.bind(LADDER_DIRS, 4)
	local drills = ctx.plan.segs
	ctx.onDestroy(function()
		GymVisuals.Light("ladder", 0)
	end)
	local completed, correct, stepTime, stepsAll = 0, 0, 0, 0
	for p, drill in ipairs(drills) do
		local lights = drill.j == "lights"
		ctx.setInfo(lights and "SMART LIGHTS: step toward each pad as it lights up (W/A/S/D or arrows), as fast as you can."
			or string.format("%s: step each arrow (W/A/S/D or arrows) as it reaches the foot line. The beat quickens through the drill - light feet.", drill.name or "LADDER"))
		if not ctx.round(p, #drills, drill.name, "DRILL") then
			return nil
		end
		UI.Clear(ctx.stage)
		if drill.j == "notes" then
			local lineX = 70
			UI.Text(ctx.stage, "FEET", { Font = T.semi, TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(8, 44), Size = UDim2.fromOffset(52, 14), AutomaticSize = Enum.AutomaticSize.None })
			UI.Frame(ctx.stage, { Position = UDim2.new(0, lineX - 2, 0, 18), Size = UDim2.new(0, 4, 0, 66), BackgroundColor3 = T.gold })
			-- the ladder's rungs
			for x = lineX + 40, 600, 40 do
				UI.Frame(ctx.stage, { Position = UDim2.new(0, x, 0, 30), Size = UDim2.new(0, 2, 0, 42), BackgroundColor3 = T.line })
			end
			local j, sg, M = ctx.begin()
			if not j then
				return nil
			end
			local frames = {}
			for i, nt in ipairs(j.notes) do
				local d = dirById[nt.lane] or LADDER_DIRS[1]
				local f = UI.Frame(ctx.stage, { Size = UDim2.fromOffset(30, 30), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(NOTE_FAR, 51), BackgroundColor3 = LADDER_COLOR[nt.lane] or T.blue })
				UI.Corner(f, 8)
				UI.Text(f, d.arrow, { Font = T.bold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None })
				frames[i] = f
			end
			local streak, onBeat = 0, 0
			ctx.on(function(id, down, t)
				if not down then
					return
				end
				local hit = j.input(id, down, t)
				if not hit then
					return
				end
				ctx.move("step", id)
				if hit.stray then
					streak = 0
					ctx.feedback("OFF THE BEAT", T.orange)
				elseif hit.grade then
					frames[hit.note].Visible = false
					if hit.grade == "off" then
						streak = 0
						ctx.feedback("LATE FEET", T.orange)
					else
						streak += 1
						onBeat += 1
						correct += 1
						ctx.feedback(hit.grade == "perfect" and ("QUICK FEET x" .. streak) or "GOOD STEP", hit.grade == "perfect" and T.gold or T.green)
					end
				end
			end)
			local pps = 200
			local start = M + (sg.lead or 1)
			local lastT = j.notes[#j.notes].t
			while true do
				if ctx.cancelled then
					ctx.on(nil)
					return nil
				end
				local now = ctx.now()
				for _ in ipairs(j.advance(now) or {}) do
					streak = 0
					ctx.feedback("MISSED STEP", T.red)
				end
				local alive = false
				for i, nt in ipairs(j.notes) do
					local f = frames[i]
					if nt.judged then
						if f.Visible then
							f.Visible = false
						end
					else
						alive = true
						local x = lineX + (nt.t - now) * pps
						if x < NOTE_FAR then
							f.Position = UDim2.fromOffset(x, 51)
						end
					end
				end
				ctx.speed(1 + math.min(streak, 10) * 0.05)
				ctx.progress((now - start) / math.max(1, lastT - start))
				ctx.stats(string.format("%d/%d steps on the beat%sstreak %d", onBeat, #sg.lanes, DOT, streak))
				if not alive or j.closed then
					break
				end
				RunService.Heartbeat:Wait()
			end
			ctx.on(nil)
			ctx.speed(1)
			local res = ctx.close(j)
			stepTime += math.max(0.5, lastT - start)
			stepsAll += res.count
			if res.hits >= 0.6 * res.count then
				completed += 1
				ctx.feedback(string.format("%d/%d ON THE BEAT", res.hits, res.count), res.hits == res.count and T.gold or T.green)
			else
				ctx.feedback("LOST THE PATTERN", T.red)
			end
		else
			local seq = {}
			for i, s in ipairs(drill.ids or {}) do
				seq[i] = dirById[s] or LADDER_DIRS[1]
			end
			local len = #seq
			local chips = {}
			if not lights then
				local w = math.max(24, math.min(44, math.floor((stageWidth(ctx) - 20) / math.max(1, len)) - 4))
				for i, d in ipairs(seq) do
					chips[i] = chip(ctx.stage, d.arrow, 10 + (i - 1) * (w + 4), w)
				end
				if chips[1] then
					chips[1].BackgroundColor3 = T.gold
				end
			end
			local j, _, start = ctx.begin()
			if not j then
				return nil
			end
			local lightChip
			local function lightUp()
				local d = seq[j.idx]
				if not d then
					return
				end
				if lightChip then
					lightChip:Destroy()
				end
				lightChip = chip(ctx.stage, d.arrow .. "  " .. d.label, 0, 160, T.blue)
				lightChip.Position = UDim2.new(0.5, -80, 0.5, -34)
				GymVisuals.Light("ladder", LADDER_PAD[d.id], Color3.fromRGB(60, 200, 255))
			end
			ctx.on(function(id, down, t)
				if not down then
					return
				end
				-- a pad due to light lights first (the judge does the same at this moment)
				if lights and j.advance(t) then
					lightUp()
				end
				local at = j.idx
				local hit = j.input(id, down, t)
				if not hit then
					return
				end
				ctx.move("step", id)
				ctx.speed(1.3)
				if hit.ok then
					correct += 1
					if chips[at] then
						chips[at].BackgroundColor3 = T.green
					end
					if chips[at + 1] then
						chips[at + 1].BackgroundColor3 = T.gold
					end
					if lights then
						GymVisuals.Light("ladder", 0)
						if lightChip then
							lightChip:Destroy()
							lightChip = nil
						end
						ctx.feedback(hit.rt and hit.rt < 0.4 and "QUICK!" or "STEP", hit.rt and hit.rt < 0.4 and T.gold or T.green, false)
					end
				else
					if chips[at] then
						chips[at].BackgroundColor3 = T.red
					end
					ctx.feedback(hit.early and "TOO EARLY" or "WRONG FOOT", T.red)
				end
			end)
			local okPlay = true
			while not j.closed do
				if ctx.cancelled then
					okPlay = false
					break
				end
				local now = ctx.now()
				if j.advance(now) and lights then
					lightUp()
				end
				if j.closed then
					break
				end
				local el = now - start
				ctx.progress((j.idx - 1) / math.max(1, len))
				ctx.stats(string.format("Step %d/%d%s%.1f steps/s", math.min(j.idx, len), len, DOT, (j.idx - 1) / math.max(0.5, el)))
				RunService.Heartbeat:Wait()
			end
			ctx.on(nil)
			ctx.speed(1)
			GymVisuals.Light("ladder", 0)
			if not okPlay then
				return nil
			end
			local res = ctx.close(j)
			local el = res.time or drill.limit or 0
			stepTime += el
			stepsAll += len
			if res.complete then
				completed += 1
				ctx.feedback(string.format("%.1fs", el), T.gold)
			else
				ctx.feedback("OUT OF TIME", T.red)
			end
		end
		ctx.progress(1)
		if not ctx.wait(WAIT.ladder) then
			return nil
		end
		-- the breathers the plan paces: before the reaction lights, and after the first pattern
		local nextDrill = drills[p + 1]
		if nextDrill and nextDrill.j == "lights" then
			if not ctx.rest(WAIT.rest, string.format("DRILL %d DONE", p), string.format("%d/%d drills completed", completed, p)) then
				return nil
			end
		elseif nextDrill and p == 1 then
			if not ctx.rest(WAIT.restShort, "DRILL 1 DONE", string.format("%d/%d drills completed", completed, p)) then
				return nil
			end
		end
	end
	local sps = correct / math.max(1, stepTime)
	ctx.put("stepsPerSec", math.floor(sps * 10 + 0.5) / 10)
	ctx.put("drills", completed)
	ctx.put("steps", correct)
	ctx.note(string.format("%d/%d drills completed", completed, #drills))
	ctx.note(string.format("%d/%d steps%s%.1f steps/s", correct, stepsAll, DOT, sps))
	return ctx.score()
end

-- JUMP ROPE -------------------------------------------------------------
local ROPE_INFO = {
	jump = "Press SPACE (or JUMP) as the rope reaches your feet - the bottom of the circle.",
	feet = "BOXER SKIP: land on the called foot - LEFT ({footL}) or RIGHT ({footR}) - as the rope passes your feet.",
	doubles = "DOUBLE UNDER = two quick presses while the rope spins twice. Plain jumps in between.",
	speed = "The rope spins faster now. Same timing - quick, light feet.",
}

-- phases with banners: basic bounce, boxer skip (footwork rope), double unders (weighted rope)
GAMES.rope = function(ctx)
	local doubles = ctx.params.doubleUnders
	local feet = ctx.params.footwork
	local actions = { { id = "jump", label = "JUMP", keys = { K.Space }, color = T.blue } }
	if feet then
		table.insert(actions, { id = "footL", label = "LEFT FOOT", keys = { K.A } })
		table.insert(actions, { id = "footR", label = "RIGHT FOOT", keys = { K.D } })
	end
	ctx.bind(actions, #actions)
	local phases = ctx.plan.segs
	UI.Clear(ctx.stage)
	local R = 44
	local ring = UI.Frame(ctx.stage, { Size = UDim2.fromOffset(R * 2, R * 2), Position = UDim2.new(0, 30, 0.5, -R - 12), BackgroundTransparency = 1 })
	UI.Stroke(UI.Corner(UI.Frame(ring, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }), R), T.line, 3)
	local zoneDot = UI.Frame(ring, { Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(R, R * 2), BackgroundColor3 = T.green })
	UI.Corner(zoneDot, 11)
	local dot = UI.Frame(ring, { Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(R, 0), BackgroundColor3 = Color3.new(1, 1, 1) })
	UI.Corner(dot, 7)
	local cueText = UI.Text(ctx.stage, "", { Font = T.bold, TextSize = 22, Position = UDim2.new(0, R * 2 + 60, 0, 20), Size = UDim2.new(1, -(R * 2 + 70), 0, 30), AutomaticSize = Enum.AutomaticSize.None })
	local countText = UI.Text(ctx.stage, "", { TextSize = 15, Position = UDim2.new(0, R * 2 + 60, 0, 52), Size = UDim2.new(1, -(R * 2 + 70), 0, 22), AutomaticSize = Enum.AutomaticSize.None, TextColor3 = T.sub })
	local totalJumps = 0
	for _, ph in ipairs(phases) do
		totalJumps += ph.jumps or 10
	end
	local clean, attempts, streak, bestStreak, doublesDone = 0, 0, 0, 0, 0
	-- the called foot names its key on this device (A / D, the D-pad on a gamepad, the button on touch)
	local cueNow
	local function cueLine(mode)
		if cueNow == "footL" or cueNow == "footR" then
			local key = ctx.ownKeyText(cueNow, mode, true)
			return (cueNow == "footL" and "LEFT FOOT" or "RIGHT FOOT") .. (key and (" (" .. key .. ")") or "")
		end
		return cueNow == "double" and "DOUBLE UNDER!" or (cueNow and "JUMP" or "")
	end
	local function showCue(cue)
		cueNow = cue
		UI.BindHint(cueText, cueLine)
		cueText.TextColor3 = cue == "jump" and T.text or T.gold
	end
	-- the rope judge (DrillScore) times every pass; this shows what it judged
	local j, jumps, done = nil, 0, 0
	local function judged(list)
		for _, jd in ipairs(list or {}) do
			done += 1
			attempts += 1
			if jd.clean then
				clean += 1
				streak += 1
				bestStreak = math.max(bestStreak, streak)
				if jd.cue == "double" then
					doublesDone += 1
				end
				ctx.move("jump", "L")
				local _, _, root = State.char()
				if root then
					GymVisuals.Sound(root.Position - Vector3.new(0, 3, 0), 2 + math.random() * 0.3, 0.2, "rbxasset://sounds/action_footsteps_plastic.mp3")
				end
				ctx.attr("RopeFoot", jd.cue == "footL" and "L" or (jd.cue == "footR" and "R" or nil))
				ctx.feedback(jd.cue == "double" and "DOUBLE!" or (streak >= 5 and ("CLEAN x" .. streak) or "CLEAN"), T.green)
			else
				streak = 0
				ctx.feedback((jd.count == 0 and not jd.early) and "TRIPPED!" or "MISTIMED!", T.red)
			end
			countText.Text = string.format("Clean %d / %d%sstreak %d", clean, attempts, DOT, streak)
			ctx.stats(string.format("Clean %d/%d%sstreak %d (best %d)", clean, attempts, DOT, streak, bestStreak))
			ctx.progress(done / math.max(1, jumps))
			if j then
				showCue(j.cue)
			end
		end
	end
	ctx.on(function(id, down, t)
		if j and down then
			judged(j.input(id, down, t))
		end
	end)
	for phI, ph in ipairs(phases) do
		ctx.setInfo(ROPE_INFO[ph.mode] or ROPE_INFO.jump)
		ctx.attr("RopeSpin", 0)
		showCue(nil)
		if not ctx.round(phI, #phases, ph.name, "PHASE") then
			return nil
		end
		jumps, done = ph.jumps or 10, 0
		j = ctx.begin()
		if not j then
			return nil
		end
		showCue(j.cue)
		while not j.closed do
			if ctx.cancelled then
				return nil
			end
			local now = ctx.now()
			judged(j.advance(now))
			local a = j.angle(now)
			if now >= j.tripped then
				ctx.attr("RopeSpin", a)
			end
			ctx.intensity = math.clamp(0.45 + (j.omega - 6) * 0.07 + (j.cue == "double" and 0.1 or 0), 0, 1)
			a %= 2 * math.pi
			dot.Position = UDim2.fromOffset(R + math.sin(a) * R, R + math.cos(a) * R)
			if j.closed then
				break
			end
			RunService.Heartbeat:Wait()
		end
		ctx.close(j)
		j = nil
		ctx.intensity = nil
		if phI < #phases then
			ctx.attr("RopeSpin", 0)
			ctx.attr("RopeFoot", nil)
			if not ctx.rest(WAIT.restShort, ph.name .. " DONE", string.format("%d/%d clean%sbest streak %d", clean, attempts, DOT, bestStreak)) then
				return nil
			end
		end
	end
	ctx.on(nil)
	ctx.put("cleanJumps", clean)
	ctx.put("bestStreak", bestStreak)
	if doubles then
		ctx.put("doubleUnders", doublesDone)
	end
	ctx.note(string.format("%d/%d clean jumps", clean, totalJumps))
	ctx.note(string.format("best streak %d", bestStreak))
	if doubles then
		ctx.note(string.format("%d double unders", doublesDone))
	end
	return ctx.score()
end

-- RECOVERY --------------------------------------------------------------
local HOLD_INFO = {
	IceBath = "Cold water constricts the blood vessels and flushes soreness. Tap to inhale, tap again to exhale (or hold and release) - slow and calm.",
	Stretch = "Long exhales let the muscles release. Tap to inhale, tap again to exhale (or hold and release) and sink into each stretch.",
	Massage = "Relax into the table. Tap to inhale, tap again to exhale (or hold and release) while the tension melts away.",
	Chamber = "Elite recovery tech - oxygen, compression and cold. Breathe with the circle.",
	Sauna = "Sweat out water weight before a weigh-in - rehydrate afterwards! Breathe with the circle.",
}
local MASSAGE_FOCUS = { "BACK & SHOULDERS", "LEGS", "FOREARMS", "NECK", "LOWER BACK" }

-- guided breathing - hold while the circle grows, release while it shrinks - plus what the session does for you
GAMES.hold = function(ctx)
	ctx.bind({ { id = "breathe", label = "TAP: INHALE / EXHALE", keys = { K.Space }, color = T.blue } }, 1)
	local act = ctx.act
	local lv = ctx.level
	local P = State.P
	ctx.setInfo(HOLD_INFO[act.id] or "Breathe with the circle: tap to inhale, tap again to exhale (or hold and release).")
	local seg = ctx.peek()
	local breaths, inhale, exhale = seg.breaths or 5, seg.inhale or 2.6, seg.exhale or 2.6
	local cycle = inhale + exhale
	local duration = breaths * cycle
	local fatigue = P and P.condition and P.condition.fatigue or 30
	local tempC = Config.IceBathTempC[math.clamp(lv, 1, #Config.IceBathTempC)]
	local saunaC = Config.SaunaTempC[math.clamp(lv, 1, #Config.SaunaTempC)]
	local st = Catalog.Stations[ctx.station]
	local lvMult = st and st.levels[math.clamp(lv, 1, #st.levels)].mult or 1
	local tensionStart = math.clamp(35 + fatigue * 0.55, 35, 92)
	local function toF(c)
		return math.floor(c * 9 / 5 + 32 + 0.5)
	end
	local stretchStart = math.random(1, #Config.StretchNames)
	local focusStart = math.random(1, #MASSAGE_FOCUS)
	-- what each breath is about (shown in the BREATH header)
	local function breathName(b)
		if act.id == "Stretch" then
			return Config.StretchNames[(stretchStart + b - 2) % #Config.StretchNames + 1]
		elseif act.id == "Massage" then
			return MASSAGE_FOCUS[(focusStart + b - 2) % #MASSAGE_FOCUS + 1]
		elseif act.id == "IceBath" then
			return string.format("WATER %d°F", toF(tempC))
		elseif act.id == "Sauna" then
			return saunaC > 0 and string.format("%d°F", toF(saunaC)) or "SAUNA SUIT"
		elseif act.id == "Chamber" then
			return "1.3 ATA"
		end
		return nil
	end
	if not ctx.round(1, breaths, breathName(1), "BREATH") then
		return nil
	end
	UI.Clear(ctx.stage)
	local circle = UI.Frame(ctx.stage, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 70, 0.5, 0), Size = UDim2.fromOffset(30, 30), BackgroundColor3 = Color3.fromRGB(80, 170, 255), BackgroundTransparency = 0.3 })
	UI.Corner(circle, 60)
	local label = UI.Text(ctx.stage, "", { Font = T.bold, TextSize = 16, Position = UDim2.new(0, 140, 0, 8), Size = UDim2.new(1, -150, 0, 22), AutomaticSize = Enum.AutomaticSize.None })
	local line1 = UI.Text(ctx.stage, "", { Font = T.semi, TextSize = 14, TextColor3 = Color3.fromRGB(150, 210, 255), Position = UDim2.new(0, 140, 0, 34), Size = UDim2.new(1, -150, 0, 20), AutomaticSize = Enum.AutomaticSize.None })
	local line2 = UI.Text(ctx.stage, "", { Font = T.semi, TextSize = 14, TextColor3 = T.sub, Position = UDim2.new(0, 140, 0, 56), Size = UDim2.new(1, -150, 0, 20), AutomaticSize = Enum.AutomaticSize.None })
	local setMeter
	if act.id == "Massage" or act.id == "Chamber" then
		local _, set = UI.Bar(ctx.stage, { Position = UDim2.new(0, 140, 0, 80), Size = UDim2.new(1, -160, 0, 8) }, act.id == "Massage" and T.orange or T.green)
		setMeter = set
	end
	-- the breath judge (DrillScore): tap or hold on through the inhale, off through the exhale
	local j, _, start = ctx.begin()
	if not j then
		return nil
	end
	ctx.on(function(id, down, t)
		j.input(id, down, t)
	end)
	local breathIdx = 1
	local syncF, prog, waterLost, tension, recovered = 0, 0, 0, tensionStart, 0
	-- the strip grades each breath by its time in sync with the circle: CLEAN counts the breaths
	-- followed, QUALITY averages them (the breath in progress by its share so far)
	local syncAt, partial, partialAt = 0, { g = 0, w = 0 }, -math.huge
	local function gradeBreath()
		local g = math.clamp((j.sync - syncAt) / cycle, 0, 1)
		syncAt = j.sync
		ctx.grade(g)
	end
	while true do
		if ctx.cancelled then
			ctx.on(nil)
			return nil
		end
		local now = ctx.now()
		local el = now - start
		j.advance(now)
		if el >= duration then
			break
		end
		local b = math.min(breaths, math.floor(el / cycle) + 1)
		if b ~= breathIdx then
			gradeBreath()
			breathIdx = b
			ctx.round(b, breaths, breathName(b), "BREATH", 0)
		end
		if now - partialAt >= 0.25 then
			partialAt = now
			local into = el - (breathIdx - 1) * cycle
			partial.w = math.clamp(into / cycle, 0, 1)
			partial.g = into > 0 and math.clamp((j.sync - syncAt) / into, 0, 1) or 0
			ctx.partial = partial
			ctx.updateMetrics()
		end
		local c = el % cycle
		local inPhase = c < inhale
		local k = inPhase and (c / inhale) or (1 - (c - inhale) / exhale)
		local size = 30 + 70 * k
		circle.Size = UDim2.fromOffset(size, size)
		label.Text = inPhase and "INHALE... (tap / hold)" or "EXHALE... (tap / release)"
		syncF = j.sync / math.max(0.01, el)
		prog = el / duration
		-- what this recovery is doing for you
		if act.id == "IceBath" then
			line1.Text = string.format("WATER %d°F (%d°C)", toF(tempC), tempC)
			line2.Text = "TIME IN " .. clock(el * TIME_SCALE)
		elseif act.id == "Sauna" then
			line1.Text = saunaC > 0 and string.format("%s %d°F (%d°C)", lv >= 3 and "INFRARED" or "SAUNA", toF(saunaC), saunaC)
				or string.format("SAUNA SUIT%sCORE %.1f°F", DOT, 98.6 + 2.2 * prog)
			waterLost = 2.5 * lvMult * (0.8 + 0.2 * (0.5 + syncF * 0.95)) * prog
			line2.Text = string.format("WATER WEIGHT LOST %.1f lbs", waterLost)
		elseif act.id == "Massage" then
			local finish = tensionStart * (0.6 - 0.3 * syncF)
			tension = tensionStart + (finish - tensionStart) * prog
			line1.Text = string.format("MUSCLE TENSION %d%%", math.floor(tension + 0.5))
			line2.Text = "WORKING: " .. (breathName(b) or "")
			if setMeter then
				setMeter(tension / 100)
			end
		elseif act.id == "Stretch" then
			line1.Text = "STRETCH: " .. (breathName(b) or "")
			line2.Text = string.format("RANGE OF MOTION +%d%%", math.floor(3 + 9 * syncF * prog + 0.5))
		elseif act.id == "Chamber" then
			line1.Text = string.format("PRESSURE 1.3 ATA%sO2 %d%%", DOT, 94 + math.floor(prog * 4))
			recovered = (60 + 40 * syncF) * prog
			line2.Text = string.format("CELL RECOVERY %d%%", math.floor(recovered))
			if setMeter then
				setMeter(recovered / 100)
			end
		end
		ctx.stats(string.format("Breath %d/%d%ssync %d%%", b, breaths, DOT, math.floor(syncF * 100)))
		ctx.setProgress(prog)
		RunService.Heartbeat:Wait()
	end
	ctx.on(nil)
	local res = ctx.close(j)
	gradeBreath()
	syncF = math.clamp(res.sync / math.max(0.01, duration), 0, 1)
	local syncPct = math.floor(syncF * 100 + 0.5)
	ctx.put("sync", syncPct)
	ctx.note(string.format("Breathing sync %d%%", syncPct))
	if act.id == "Sauna" then
		waterLost = 2.5 * lvMult * (0.8 + 0.2 * (0.5 + syncF * 0.95))
		ctx.put("waterLost", math.floor(waterLost * 10 + 0.5) / 10)
		ctx.note(string.format("~%.1f lbs water", waterLost))
	elseif act.id == "Massage" then
		ctx.note(string.format("Tension %d%% -> %d%%", math.floor(tensionStart + 0.5), math.floor(tension + 0.5)))
	elseif act.id == "IceBath" then
		ctx.note(string.format("%s at %d°F", clock(duration * TIME_SCALE), toF(tempC)))
	elseif act.id == "Chamber" then
		ctx.note(string.format("Cell recovery %d%%", math.floor(60 + 40 * syncF)))
	end
	return ctx.score()
end

-- WORKOUT KIT ----------------------------------------------------------
-- (the exercise-specific workouts: their judges and plans are DrillWorkouts', DrillScore runs them)
local Workouts = DrillScore.Workouts

-- a one-line label that never runs out of its box (cut with "..." instead)
local function label(parent, text, props)
	local p = { Font = T.semi, TextSize = 13, TextColor3 = T.text, AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd }
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	return UI.Text(parent, text, p)
end

-- a horizontal track with zones, a fill and a marker (values 0..1 along it); every setter skips a write
-- that would not move anything
local function meter(parent, pos, size)
	local f = UI.Frame(parent, { Position = pos, Size = size, BackgroundColor3 = DARK })
	UI.Corner(f, 4)
	local m = { frame = f }
	function m.zone(lo, hi, color, transparency)
		local z = UI.Frame(f, { Position = UDim2.fromScale(lo, 0), Size = UDim2.fromScale(math.max(0, hi - lo), 1), BackgroundColor3 = color, BackgroundTransparency = transparency or 0.45 })
		local last = { lo, hi }
		return function(a, b)
			if math.abs(a - last[1]) > 0.002 or math.abs(b - last[2]) > 0.002 then
				last = { a, b }
				z.Position = UDim2.fromScale(math.clamp(a, 0, 1), 0)
				z.Size = UDim2.fromScale(math.clamp(b, 0, 1) - math.clamp(a, 0, 1), 1)
			end
		end, z
	end
	local fill = UI.Frame(f, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.gold, BackgroundTransparency = 0.3, Visible = false })
	UI.Corner(fill, 4)
	local mk = UI.Frame(f, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0, 4, 1, 8), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3, Visible = false })
	m.marker, m.fillFrame = mk, fill
	local lastMark, lastFill = -1, -1
	function m.mark(v, color)
		mk.Visible = true
		v = math.clamp(v, 0, 1)
		if math.abs(v - lastMark) > 0.002 then
			lastMark = v
			mk.Position = UDim2.fromScale(v, 0.5)
		end
		if color and mk.BackgroundColor3 ~= color then
			mk.BackgroundColor3 = color
		end
	end
	function m.fill(v, color)
		fill.Visible = true
		v = math.clamp(v, 0, 1)
		if math.abs(v - lastFill) > 0.002 then
			lastFill = v
			fill.Size = UDim2.fromScale(v, 1)
		end
		if color and fill.BackgroundColor3 ~= color then
			fill.BackgroundColor3 = color
		end
	end
	return m
end

-- a label whose text is written only when it changes
local function setText(lbl, text, color)
	if lbl.Text ~= text then
		lbl.Text = text
	end
	if color and lbl.TextColor3 ~= color then
		lbl.TextColor3 = color
	end
end

local function pct(v)
	return string.format("%d%%", math.floor(math.clamp(v, 0, 1) * 100 + 0.5))
end

-- a timed one-segment drill (cardio machines, recovery): the banner, then the judge until its end with
-- draw(j, seg, now) every frame; react(j, seg, hit) on each answered input. Returns the result or nil.
local function timedDrill(ctx, name, kind, draw, react)
	if not ctx.round(1, 1, name, kind or "SESSION") then
		return nil
	end
	local j, seg, start = ctx.begin()
	if not j then
		return nil
	end
	ctx.on(function(id, down, t)
		local hit = j.input(id, down, t)
		if hit and react then
			react(j, seg, hit)
		end
	end)
	local dur = seg.duration or 30
	local partialAt = -math.huge
	local okPlay = playSegment(ctx, j, function(now)
		draw(j, seg, now)
		ctx.setProgress((now - start) / dur)
		-- QUALITY moves from the first second: the time on target so far, on the session's scale
		if now - partialAt >= 0.25 and j.acc then
			partialAt = now
			local el = math.max(0.01, now - start)
			ctx.partial = { w = 1, g = math.clamp(j.acc * Workouts.TICK / el / Workouts.TIMED_FULL, 0, 1) }
			ctx.updateMetrics()
		end
	end)
	ctx.on(nil)
	if not okPlay then
		return nil
	end
	local res = ctx.close(j)
	ctx.partial = nil
	return res, seg
end

-- 2 sets of reps of one judge (bench, deadlift, squat, pull-ups): the station's real load on the stage,
-- REP / GOOD on the strip, the weight lowered between reps, an RPE after each set. o = {
--   actions, perRow, info, build(loadText) -> draw(j, seg, now), react(j, seg, hit), verdict(res) -> text,
--   color, top(res) (the drive the weight is lowered from), onRep(res) }
local function repSets(ctx, o)
	local load, loadText, exName, bodyweight = liftLoad(ctx)
	exName = exName or ctx.act.name:upper()
	local sets, reps = 0, 0
	for _, seg in ipairs(ctx.plan.segs) do
		sets = math.max(sets, seg.set or 1)
		reps = math.max(reps, seg.rep or 1)
	end
	ctx.bind(o.actions, o.perRow)
	ctx.setInfo(o.info)
	UI.Clear(ctx.stage)
	local draw = o.build(loadText)
	local P = State.P
	local fatigue = P and P.condition and P.condition.fatigue or 0
	local goodReps, fails, lastRpe, qSum = 0, 0, 6, 0
	local function rpeText(v)
		return "RPE " .. (v % 1 == 0 and tostring(math.floor(v)) or string.format("%.1f", v))
	end
	for set = 1, sets do
		if not ctx.round(set, sets, exName, "SET") then
			return nil
		end
		local setGood, setFails = 0, 0
		ctx.stats(nil)
		for r = 1, reps do
			ctx.setRep(r, reps, setGood)
			ctx.attr("RepCount", (set - 1) * reps + r)
			ctx.intensity = 0.35
			local j, seg = ctx.begin()
			if not j then
				return nil
			end
			ctx.on(function(id, down, t)
				local hit = j.input(id, down, t)
				if hit and o.react then
					o.react(j, seg, hit)
				end
			end)
			local okPlay = playSegment(ctx, j, function(now)
				draw(j, seg, now)
			end)
			ctx.on(nil)
			if not okPlay then
				return nil
			end
			local res = ctx.close(j)
			qSum += res.q
			local text, col = o.verdict(res)
			ctx.feedback(text, col, res.q)
			if res.q >= 0.7 then
				goodReps += 1
				setGood += 1
				ctx.pump(res.q >= 0.9 and 0.1 or 0.07)
			elseif res.verdict ~= "none" then
				if res.q < 0.3 then
					fails += 1
					setFails += 1
				end
				ctx.pump(0.03)
			end
			if o.onRep then
				o.onRep(res)
			end
			draw(j, seg, ctx.now())
			-- lower the weight
			ctx.intensity = 0.5
			local top = o.top and o.top(res) or (res.p or 0)
			local t0 = os.clock()
			while os.clock() - t0 < WAIT.lower do
				if ctx.cancelled then
					return nil
				end
				ctx.drive(top * (1 - (os.clock() - t0) / WAIT.lower))
				RunService.Heartbeat:Wait()
			end
			ctx.drive(0)
			ctx.setRep(r, reps, setGood)
			ctx.stats(setFails > 0 and string.format("%d spotted", setFails) or nil)
			ctx.progress(r / reps)
			if not ctx.wait(WAIT.rerack) then
				return nil
			end
		end
		local rpe = math.clamp(6 + setFails * 1.2 + (reps - setGood) * 0.35 + (set - 1) * 0.6 + fatigue / 50, 6, 10)
		rpe = math.floor(rpe * 2 + 0.5) / 2
		lastRpe = rpe
		ctx.intensity = nil
		if set < sets then
			local left = math.max(0, math.floor(10 - rpe))
			if not ctx.rest(WAIT.rest, string.format("SET %d DONE%s%s", set, DOT, rpeText(rpe)), string.format("%d/%d good reps%s%s", setGood, reps, DOT, left > 0 and (left .. " more in the tank") or "nothing left in the tank")) then
				return nil
			end
		else
			ctx.feedback(rpeText(rpe), rpe >= 9 and T.red or (rpe >= 8 and T.orange or T.green))
		end
	end
	ctx.intensity = nil
	ctx.put(bodyweight and "addedLoad" or "load", load or 0)
	ctx.put("goodReps", goodReps)
	if load and not bodyweight then
		ctx.put("volume", load * goodReps)
	end
	ctx.put("form", math.floor(qSum / math.max(1, sets * reps) * 100 + 0.5))
	ctx.note(exName .. (loadText and (" " .. loadText) or ""))
	ctx.note(string.format("%d/%d good reps", goodReps, sets * reps))
	if fails > 0 then
		ctx.note(string.format("%d failed or spotted", fails))
	end
	ctx.note(rpeText(lastRpe))
	if not ctx.wait(0.3) then
		return nil
	end
	return ctx.score()
end

-- BENCH PRESS -----------------------------------------------------------
-- Press the bar while it drifts out of level (one side is weaker): push the low end back up, get through
-- the sticking point and lock it out; the spotter is there when it goes wrong (or when you call him).
GAMES.bench = function(ctx)
	return repSets(ctx, {
		actions = {
			{ id = "press", label = "PRESS", say = "PRESS", keys = { K.Space }, color = T.blue },
			{ id = "L", label = "LEFT UP", keys = { K.A, K.Left } },
			{ id = "R", label = "RIGHT UP", keys = { K.D, K.Right } },
			{ id = "spot", label = "SPOTTER!", keys = { K.F }, color = T.orange },
		},
		perRow = 4,
		info = "Tap or hold PRESS (SPACE) to drive the bar. Keep it level: lift the low end with LEFT UP ({L}) or RIGHT UP ({R}). Stalled? Call the SPOTTER ({spot}).",
		build = function(loadText)
			local sw = stageWidth(ctx)
			local cx, half = math.floor(sw * 0.24), math.floor(math.min(120, sw * 0.18))
			local dots = {}
			for i = 1, 11 do
				local d = UI.Frame(ctx.stage, { Size = UDim2.fromOffset(8, 6), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(200, 200, 210) })
				dots[i] = d
			end
			local plateL = UI.Frame(ctx.stage, { Size = UDim2.fromOffset(10, 34), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = T.red })
			local plateR = UI.Frame(ctx.stage, { Size = UDim2.fromOffset(10, 34), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = T.red })
			UI.Corner(plateL, 3)
			UI.Corner(plateR, 3)
			local x0 = math.floor(sw * 0.5)
			local mw = sw - x0 - 12
			label(ctx.stage, "BAR LEVEL", { TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(x0, 6), Size = UDim2.fromOffset(mw, 14) })
			local tilt = meter(ctx.stage, UDim2.fromOffset(x0, 22), UDim2.fromOffset(mw, 16))
			tilt.zone(0.4, 0.6, T.green, 0.3)
			tilt.zone(0, 0.1, T.red, 0.3)
			tilt.zone(0.9, 1, T.red, 0.3)
			label(ctx.stage, "LOCKOUT", { TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(x0, 46), Size = UDim2.fromOffset(mw * 0.5, 14) })
			local lockText = label(ctx.stage, "", { Face = "number", TextSize = 13, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(x0 + mw, 44), Size = UDim2.fromOffset(mw * 0.5, 16), TextXAlignment = Enum.TextXAlignment.Right })
			local lock = meter(ctx.stage, UDim2.fromOffset(x0, 62), UDim2.fromOffset(mw, 14))
			local setStick = lock.zone(0.42, 0.6, T.orange, 0.55)
			label(ctx.stage, loadText or "", { Font = T.bold, TextColor3 = T.gold, Position = UDim2.fromOffset(x0, 84), Size = UDim2.fromOffset(mw, 18) })
			return function(j, seg, now)
				local y = 96 - j.p * 62
				local dy = j.x * 22
				for i, d in ipairs(dots) do
					local k = (i - 1) / (#dots - 1)
					d.Position = UDim2.fromOffset(cx - half + 2 * half * k, y + dy * (1 - 2 * k))
				end
				local danger = math.abs(j.x) > 0.6
				plateL.Position = UDim2.fromOffset(cx - half - 6, y + dy)
				plateR.Position = UDim2.fromOffset(cx + half + 6, y - dy)
				local lowL, lowR = j.x > 0.25, j.x < -0.25
				plateL.BackgroundColor3 = (danger and j.x > 0) and T.gold or (lowL and T.orange or T.red)
				plateR.BackgroundColor3 = (danger and j.x < 0) and T.gold or (lowR and T.orange or T.red)
				tilt.mark(0.5 - j.x / 2, danger and T.red or (math.abs(j.x) > 0.2 and T.orange or T.green))
				setStick(seg.stickLo, seg.stickHi)
				lock.fill(j.p, T.gold)
				setText(lockText, j.started and pct(j.p) or "PRESS!", j.started and T.text or T.gold)
				ctx.drive(j.p)
				ctx.attrQ("PoseTilt", j.x, 0.05)
				ctx.intensity = j.press.on and 0.9 or 0.45
			end
		end,
		react = function(_, _, hit)
			if hit.spot then
				ctx.feedback("SPOTTER: I GOT IT", T.orange)
			end
		end,
		verdict = function(res)
			local v = res.verdict
			if v == "lockout" then
				return res.q >= 0.9 and "LEVEL LOCKOUT!" or (res.q >= 0.7 and "GOOD REP" or "SHAKY REP"), res.q >= 0.9 and T.gold or (res.q >= 0.7 and T.green or T.orange)
			elseif v == "assisted" then
				return "ASSISTED REP", T.orange
			elseif v == "tilted" then
				return "BAR TIPPED - SPOTTER!", T.red
			elseif v == "stalled" then
				return "STALLED - SPOTTER!", T.red
			end
			return "NO PRESS", T.red
		end,
		onRep = function()
			ctx.attrQ("PoseTilt", 0)
		end,
	})
end

-- DEADLIFT --------------------------------------------------------------
-- SET YOUR BACK (press as the back-angle needle passes neutral), then drive the bar through the knees
-- with the grip squeezed (the grip drains while the bar is off the floor).
GAMES.deadlift = function(ctx)
	return repSets(ctx, {
		actions = {
			{ id = "lift", label = "SET & LIFT", say = "LIFT", keys = { K.Space }, color = T.blue },
			{ id = "grip", label = "SQUEEZE GRIP", keys = { K.J, K.F }, color = T.panel2 },
		},
		perRow = 2,
		info = "Press LIFT (SPACE) as the needle crosses NEUTRAL to set your back, then keep driving. SQUEEZE GRIP ({grip}) before your grip runs out.",
		build = function(loadText)
			local sw = stageWidth(ctx)
			local mw = sw - 24
			local status = label(ctx.stage, "", { Font = T.bold, TextSize = 15, Position = UDim2.fromOffset(12, 4), Size = UDim2.fromOffset(mw * 0.6, 20) })
			label(ctx.stage, loadText or "", { Font = T.bold, TextColor3 = T.gold, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(12 + mw, 4), Size = UDim2.fromOffset(mw * 0.4, 20), TextXAlignment = Enum.TextXAlignment.Right })
			local back = meter(ctx.stage, UDim2.fromOffset(12, 28), UDim2.fromOffset(mw, 16))
			local setNeutral = back.zone(0.4, 0.6, T.gold, 0.2)
			label(ctx.stage, "ROUNDED", { TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(12, 46), Size = UDim2.fromOffset(90, 14) })
			label(ctx.stage, "OVER-ARCHED", { TextSize = 11, TextColor3 = T.sub, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(12 + mw, 46), Size = UDim2.fromOffset(110, 14), TextXAlignment = Enum.TextXAlignment.Right })
			local bar = meter(ctx.stage, UDim2.fromOffset(12, 66), UDim2.fromOffset(math.floor(mw * 0.62), 14))
			local setStick = bar.zone(0.32, 0.58, T.orange, 0.55)
			label(ctx.stage, "BAR", { TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(12, 82), Size = UDim2.fromOffset(60, 14) })
			local gx = 24 + math.floor(mw * 0.62)
			local grip = meter(ctx.stage, UDim2.fromOffset(gx, 66), UDim2.fromOffset(12 + mw - gx, 14))
			local gripText = label(ctx.stage, "GRIP", { TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(gx, 82), Size = UDim2.fromOffset(12 + mw - gx, 14) })
			return function(j, seg, now)
				setNeutral(seg.c - seg.w, seg.c + seg.w)
				setStick(seg.stickLo, seg.stickHi)
				if j.phase == "set" then
					local pos = j.needleAt(now)
					local d = math.abs(pos - seg.c)
					back.mark(pos, d <= seg.w and T.gold or Color3.new(1, 1, 1))
					setText(status, "SET YOUR BACK", T.gold)
					ctx.attrQ("PoseSet", 1 - math.min(1, d * 2), 0.05)
				else
					back.mark(j.setPos or seg.c, (j.setQ or 0) >= 0.8 and T.green or T.orange)
					local stick = j.p >= seg.stickLo and j.p <= seg.stickHi
					setText(status, j.closed and "" or (stick and "THROUGH THE KNEES!" or (j.lift.on and "DRIVE!" or "KEEP PULLING")), stick and T.orange or T.text)
				end
				bar.fill(j.p, T.gold)
				local g = j.g or 1
				grip.fill(g, g < 0.25 and T.red or (g < 0.5 and T.orange or T.green))
				setText(gripText, g < 0.3 and "GRIP SLIPPING!" or "GRIP", g < 0.3 and T.red or T.sub)
				ctx.drive(j.p)
				ctx.attrQ("PoseGrip", g, 0.05)
				ctx.intensity = j.lift.on and 0.95 or 0.4
			end
		end,
		react = function(_, _, hit)
			if hit.set then
				local q = hit.setQ
				ctx.feedback(q >= 0.85 and "NEUTRAL BACK" or (q >= 0.6 and "BACK SET" or "ROUNDED BACK!"), q >= 0.85 and T.green or (q >= 0.6 and T.text or T.orange), false)
				ctx.attrQ("PoseSet", q, 0.05)
			end
		end,
		verdict = function(res)
			local v = res.verdict
			if v == "lockout" then
				return res.q >= 0.9 and "PERFECT PULL!" or (res.q >= 0.7 and "GOOD LOCKOUT" or "UGLY PULL"), res.q >= 0.9 and T.gold or (res.q >= 0.7 and T.green or T.orange)
			elseif v == "grip" then
				return "GRIP GAVE OUT", T.red
			elseif v == "stalled" then
				return "STUCK AT THE KNEES", T.red
			end
			return "NEVER SET UP", T.red
		end,
		onRep = function()
			ctx.attrQ("PoseGrip", 1)
		end,
	})
end

-- SQUAT -----------------------------------------------------------------
-- Sink (it speeds up the deeper you go), stop in the depth zone, then drive out of the hole inside the
-- bounce window and keep driving to the top.
GAMES.squat = function(ctx)
	return repSets(ctx, {
		actions = { { id = "sit", label = "SINK / DRIVE", say = "SQUAT", keys = { K.Space }, color = T.blue } },
		perRow = 1,
		info = "Tap or hold SPACE to sink and let go in the DEPTH zone. Then press again inside the bounce window and drive all the way up.",
		build = function(loadText)
			local sw = stageWidth(ctx)
			local x0 = 120
			local mw = sw - x0 - 14
			-- the depth gauge: standing at the top, the hole at the bottom
			local gauge = UI.Frame(ctx.stage, { Position = UDim2.fromOffset(20, 6), Size = UDim2.fromOffset(40, 100), BackgroundColor3 = DARK })
			UI.Corner(gauge, 4)
			local zone = UI.Frame(gauge, { BackgroundColor3 = T.green, BackgroundTransparency = 0.35, Size = UDim2.fromScale(1, 0.15) })
			UI.Frame(gauge, { BackgroundColor3 = T.red, BackgroundTransparency = 0.35, Position = UDim2.fromScale(0, 0.94), Size = UDim2.fromScale(1, 0.06) })
			local hip = UI.Frame(gauge, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, 10, 0, 5), Position = UDim2.fromScale(0.5, 0), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3 })
			label(ctx.stage, "DEPTH", { TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(66, 6), Size = UDim2.fromOffset(50, 14) })
			local status = label(ctx.stage, "", { Font = T.bold, TextSize = 16, Position = UDim2.fromOffset(x0, 6), Size = UDim2.fromOffset(mw, 22) })
			label(ctx.stage, "BOUNCE WINDOW", { TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(x0, 34), Size = UDim2.fromOffset(mw, 14) })
			local win = meter(ctx.stage, UDim2.fromOffset(x0, 50), UDim2.fromOffset(mw, 14))
			local setWin = win.zone(0.1, 0.5, T.green, 0.3)
			label(ctx.stage, "DRIVE UP", { TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(x0, 70), Size = UDim2.fromOffset(mw * 0.5, 14) })
			local up = meter(ctx.stage, UDim2.fromOffset(x0, 86), UDim2.fromOffset(math.floor(mw * 0.55), 12))
			label(ctx.stage, loadText or "", { Font = T.bold, TextColor3 = T.gold, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(x0 + mw, 82), Size = UDim2.fromOffset(mw * 0.42, 18), TextXAlignment = Enum.TextXAlignment.Right })
			local WIN_SPAN = 1.2
			return function(j, seg, now)
				zone.Position = UDim2.fromScale(0, seg.lo)
				zone.Size = UDim2.fromScale(1, seg.hi - seg.lo)
				local z = j.depth()
				hip.Position = UDim2.fromScale(0.5, z)
				local inZone = z >= seg.lo and z <= seg.hi
				hip.BackgroundColor3 = inZone and T.green or (z > seg.hi and T.orange or Color3.new(1, 1, 1))
				setWin(seg.bounce / WIN_SPAN, seg.pause / WIN_SPAN)
				local ph = j.phase
				if ph == "ready" then
					setText(status, "SINK", T.text)
				elseif ph == "descend" then
					setText(status, inZone and "DEPTH! LET GO" or "SINKING...", inZone and T.green or T.text)
				elseif ph == "bottom" then
					local since = now - j.bottomT
					win.mark(since / WIN_SPAN, (since >= seg.bounce and since <= seg.pause) and T.green or T.orange)
					setText(status, since < seg.bounce and "HOLD THE HOLE..." or "DRIVE NOW!", since < seg.bounce and T.text or T.gold)
				elseif ph == "drive" then
					win.mark((j.pressDt or 0) / WIN_SPAN)
					setText(status, j.sit.on and "DRIVE!" or "KEEP DRIVING!", j.sit.on and T.green or T.orange)
				end
				up.fill(j.u, T.gold)
				ctx.drive(1 - z)
				ctx.intensity = (ph == "drive" or ph == "bottom") and 0.95 or 0.5
			end
		end,
		verdict = function(res)
			local v = res.verdict
			if v == "stand" then
				local depth = ({ zone = "PARALLEL", high = "HIGH", deep = "DEEP", dive = "DIVE-BOMBED" })[res.depth] or ""
				local drive = ({ good = "", bounce = " · BOUNCED", pause = " · SLOW OUT" })[res.drive] or ""
				return (res.q >= 0.9 and "PERFECT! " or "") .. depth .. drive, res.q >= 0.9 and T.gold or (res.q >= 0.7 and T.green or T.orange)
			elseif v == "stalled" then
				return "STUCK - RACKED IT", T.red
			elseif v == "stuck" then
				return "LOST IT IN THE HOLE", T.red
			end
			return "NO REP", T.red
		end,
		top = function(res)
			return res.verdict == "stand" and 1 or 0.4
		end,
	})
end

-- PULL-UPS --------------------------------------------------------------
-- Pull LEFT and RIGHT in turn through the bottom of the swing; HOLLOW kills the swing (and slows you).
GAMES.pullup = function(ctx)
	local nextHand = "L"
	return repSets(ctx, {
		actions = {
			{ id = "L", label = "PULL LEFT", keys = { K.J, K.A, K.Left }, color = T.blue },
			{ id = "R", label = "PULL RIGHT", keys = { K.K, K.D, K.Right }, color = T.red },
			{ id = "hollow", label = "HOLLOW BODY", say = "HOLLOW", keys = { K.Space } },
		},
		perRow = 3,
		info = "Pull LEFT ({L}) and RIGHT ({R}) in turn as the swing passes the middle. Swinging too much? Tap HOLLOW (SPACE) to brace and kill it.",
		build = function(loadText)
			local sw = stageWidth(ctx)
			local mw = sw - 110
			label(ctx.stage, "SWING", { TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(12, 6), Size = UDim2.fromOffset(80, 14) })
			local swing = meter(ctx.stage, UDim2.fromOffset(12, 22), UDim2.fromOffset(mw, 18))
			swing.zone(0.42, 0.58, T.green, 0.3)
			swing.zone(0, 0.06, T.red, 0.3)
			swing.zone(0.94, 1, T.red, 0.3)
			local status = label(ctx.stage, "", { Font = T.bold, TextSize = 15, Position = UDim2.fromOffset(12, 48), Size = UDim2.fromOffset(mw, 20) })
			label(ctx.stage, loadText or "", { Font = T.bold, TextColor3 = T.gold, Position = UDim2.fromOffset(12, 76), Size = UDim2.fromOffset(mw, 18) })
			-- the height: the chin climbs to the bar line
			local col = UI.Frame(ctx.stage, { Position = UDim2.fromOffset(sw - 80, 16), Size = UDim2.fromOffset(28, 88), BackgroundColor3 = DARK })
			UI.Corner(col, 4)
			UI.Frame(ctx.stage, { Position = UDim2.fromOffset(sw - 92, 12), Size = UDim2.fromOffset(52, 4), BackgroundColor3 = Color3.fromRGB(190, 190, 200) })
			local chin = UI.Frame(col, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BackgroundColor3 = T.gold })
			UI.Corner(chin, 4)
			label(ctx.stage, "CHIN", { TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(sw - 44, 10), Size = UDim2.fromOffset(40, 14) })
			return function(j, seg, now)
				local s = j.swing(now)
				local off = math.abs(math.sin(j.phaseAt(now)))
				swing.mark(0.5 + s / 2, off < 0.3 and T.green or Color3.new(1, 1, 1))
				chin.Size = UDim2.fromScale(1, math.clamp(j.h, 0, 1))
				local want = j.last == "L" and "RIGHT" or (j.last == "R" and "LEFT" or (nextHand == "L" and "LEFT" or "RIGHT"))
				if j.hollow.on then
					setText(status, "HOLLOW - BRACED", T.cyan)
				elseif j.A > 0.6 then
					setText(status, "SWINGING! GO HOLLOW", T.orange)
				else
					setText(status, "NEXT: PULL " .. want, T.text)
				end
				ctx.drive(0.15 + 0.85 * j.h)
				ctx.attrQ("PoseSwing", s, 0.04)
				ctx.intensity = 0.4 + 0.5 * j.h
			end
		end,
		react = function(_, _, hit)
			if hit.alt == false then
				ctx.feedback("OTHER ARM!", T.orange, false)
			elseif hit.off and hit.off > 0.6 then
				ctx.feedback("KIPPING", T.orange, false)
			end
		end,
		verdict = function(res)
			local v = res.verdict
			if v == "chin" then
				return res.q >= 0.9 and "STRICT REP!" or (res.q >= 0.7 and "CHIN OVER" or "SWINGY REP"), res.q >= 0.9 and T.gold or (res.q >= 0.7 and T.green or T.orange)
			elseif v == "swung" then
				return "SWUNG OFF THE BAR", T.red
			elseif v == "stalled" then
				return "RAN OUT OF PULL", T.red
			end
			return "DEAD HANG", T.red
		end,
		top = function(res)
			return 0.15 + 0.85 * (res.h or 0)
		end,
		onRep = function(res)
			nextHand = res.pulls and res.pulls % 2 == 1 and "R" or "L"
			ctx.attrQ("PoseSwing", 0)
		end,
	})
end

-- DUMBBELL CURLS ----------------------------------------------------------
-- Hold notes on a tempo: press the arm's button as its bar reaches the line (curl up), hold through the
-- squeeze, let go as the tail passes (lower). Two sets: alternating curls, then slower tempo curls.
GAMES.curls = function(ctx)
	local load, loadText, exName = liftLoad(ctx)
	exName = exName or "DUMBBELL CURLS"
	ctx.bind({ { id = "L", label = "LEFT ARM", keys = { K.J, K.A, K.F }, color = T.blue }, { id = "R", label = "RIGHT ARM", keys = { K.K, K.D, K.G }, color = T.red } }, 2)
	ctx.setInfo("Hold LEFT ARM ({L}) or RIGHT ARM ({R}) as its bar reaches the line, keep holding through the squeeze, let go at its end. One arm at a time - no swinging.")
	local segs = ctx.plan.segs
	local sumAll, countAll, swingsAll, perfectAll = 0, 0, 0, 0
	local lineX, LANE_Y = 64, { L = 30, R = 70 }
	for si, seg0 in ipairs(segs) do
		if not ctx.round(si, #segs, (seg0.name or exName) .. DOT .. (seg0.bpm or 60) .. " BPM", "SET") then
			return nil
		end
		UI.Clear(ctx.stage)
		UI.Frame(ctx.stage, { Position = UDim2.new(0, lineX - 2, 0, 6), Size = UDim2.new(0, 4, 1, -12), BackgroundColor3 = T.gold })
		label(ctx.stage, "L", { Font = T.bold, Position = UDim2.fromOffset(10, LANE_Y.L - 9), Size = UDim2.fromOffset(40, 18), TextColor3 = T.blue })
		label(ctx.stage, "R", { Font = T.bold, Position = UDim2.fromOffset(10, LANE_Y.R - 9), Size = UDim2.fromOffset(40, 18), TextColor3 = T.red })
		label(ctx.stage, loadText or "", { Font = T.bold, TextSize = 12, TextColor3 = T.gold, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 2), Size = UDim2.fromOffset(160, 16), TextXAlignment = Enum.TextXAlignment.Right })
		local j, seg = ctx.begin()
		if not j then
			return nil
		end
		local pps = 120 / (seg.beat or 1)
		local frames = {}
		for i, n in ipairs(j.notes) do
			local f = UI.Frame(ctx.stage, { AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(math.max(16, (n.te - n.ts) * pps), 22), Position = UDim2.fromOffset(NOTE_FAR, LANE_Y[n.lane]),
				BackgroundColor3 = n.lane == "L" and T.blue or T.red, BackgroundTransparency = 0.25 })
			UI.Corner(f, 8)
			frames[i] = f
		end
		local held = {}
		local hand = {}
		ctx.intensity = 0.45
		ctx.on(function(id, down, t)
			local hit = j.input(id, down, t)
			held[id] = down
			if down then
				hand[id] = t
			end
			if not hit then
				return
			end
			if hit.swing then
				ctx.feedback("NO SWINGING!", T.orange, false)
			end
			if hit.stray then
				ctx.feedback("OFF TEMPO", T.orange, false)
			end
		end)
		local VERDICT = { early = { "DROPPED IT EARLY", T.orange }, late = { "TOO LONG AT THE TOP", T.orange }, miss = { "MISSED THE CURL", T.red } }
		local okPlay = playSegment(ctx, j, function(now)
			for i, n in ipairs(j.notes) do
				local f = frames[i]
				if n.judged then
					if f.Visible then
						-- judged since the last frame (let go, held too long or never started): its grade once
						f.Visible = false
						local v = VERDICT[n.endText]
						if v then
							ctx.feedback(v[1], v[2], n.q)
						else
							ctx.feedback(n.q >= 0.9 and "PERFECT TEMPO" or "GOOD CURL", n.q >= 0.9 and T.gold or T.green, n.q)
						end
						if n.q >= 0.8 then
							ctx.pump(0.05)
						end
					end
				else
					local x = lineX + (n.ts - now) * pps
					if n.startT then
						-- curled: the bar's head stays on the line while the tail runs in
						local w = math.max(6, (n.te - now) * pps)
						f.Position = UDim2.fromOffset(lineX, LANE_Y[n.lane])
						f.Size = UDim2.fromOffset(w, 22)
						f.BackgroundTransparency = 0
					elseif x < NOTE_FAR then
						f.Position = UDim2.fromOffset(x, LANE_Y[n.lane])
					end
				end
			end
			-- the animation: the arm being held curls up over half a second and lowers when let go
			local side = held.L and "L" or (held.R and "R" or nil)
			if side then
				ctx.attrQ("CurlSide", side)
				ctx.drive(math.min(1, (now - (hand[side] or now)) / 0.45))
			else
				ctx.drive(math.max(0, (ctx.poseDrive or 0) - 0.04))
			end
			ctx.progress((now - (j.notes[1] and j.notes[1].ts or now)) / math.max(1, j.endT - (j.notes[1] and j.notes[1].ts or now)))
			ctx.stats(string.format("%d/%d curls%s%d perfect", j.perfect, #j.notes, DOT, j.perfect))
		end)
		ctx.on(nil)
		if not okPlay then
			return nil
		end
		local res = ctx.close(j)
		sumAll += res.sum
		countAll += res.count
		swingsAll += res.swings
		perfectAll += res.perfect
		ctx.drive(0)
		if si < #segs then
			if not ctx.rest(WAIT.rest, string.format("SET %d DONE", si), string.format("%d/%d perfect curls%s%d swings", res.perfect, res.count, DOT, res.swings)) then
				return nil
			end
		end
	end
	ctx.intensity = nil
	ctx.put("load", load or 0)
	ctx.put("tempo", math.floor(sumAll / math.max(1, countAll) * 100 + 0.5))
	ctx.put("perfectCurls", perfectAll)
	ctx.note(exName .. (loadText and (" " .. loadText) or ""))
	ctx.note(string.format("%d/%d perfect curls", perfectAll, countAll))
	if swingsAll > 0 then
		ctx.note(string.format("%d swings", swingsAll))
	end
	if not ctx.wait(0.6) then
		return nil
	end
	return ctx.score()
end

-- TREADMILL -------------------------------------------------------------
-- The program calls speed and incline; step the console to follow it.
GAMES.treadmill = function(ctx)
	ctx.bind({
		{ id = "spdDn", label = "SPEED -", keys = { K.S, K.Down } },
		{ id = "spdUp", label = "SPEED +", keys = { K.W, K.Up }, color = T.blue },
		{ id = "incDn", label = "INCLINE -", keys = { K.A, K.Left } },
		{ id = "incUp", label = "INCLINE +", keys = { K.D, K.Right }, color = T.green },
	}, 4)
	ctx.setInfo("Follow the program: SPEED +/- ({spdUp}/{spdDn}) and INCLINE +/- ({incUp}/{incDn}). The closer you track both targets, the better.")
	UI.Clear(ctx.stage)
	local sw = stageWidth(ctx)
	local x0, mw = 96, sw - 96 - 14
	local stepText = label(ctx.stage, "", { Font = T.bold, TextSize = 15, Position = UDim2.fromOffset(12, 2), Size = UDim2.fromOffset(sw * 0.55, 20) })
	local nextText = label(ctx.stage, "", { TextSize = 12, TextColor3 = T.sub, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(sw - 12, 4), Size = UDim2.fromOffset(sw * 0.42, 16), TextXAlignment = Enum.TextXAlignment.Right })
	local spdText = label(ctx.stage, "", { Face = "number", TextSize = 14, Position = UDim2.fromOffset(12, 28), Size = UDim2.fromOffset(x0 - 16, 18) })
	local spd = meter(ctx.stage, UDim2.fromOffset(x0, 30), UDim2.fromOffset(mw, 16))
	local setSpd = spd.zone(0, 0.1, T.green, 0.3)
	local incText = label(ctx.stage, "", { Face = "number", TextSize = 14, Position = UDim2.fromOffset(12, 58), Size = UDim2.fromOffset(x0 - 16, 18) })
	local inc = meter(ctx.stage, UDim2.fromOffset(x0, 60), UDim2.fromOffset(mw, 16))
	local setInc = inc.zone(0, 0.1, T.green, 0.3)
	local readout = label(ctx.stage, "", { TextSize = 13, TextColor3 = Color3.fromRGB(120, 220, 255), Position = UDim2.fromOffset(12, 88), Size = UDim2.fromOffset(sw - 24, 18) })
	local miles, topSpeed, lastNow, screenAt, lastStep = 0, 0, nil, -math.huge, nil
	local res, seg = timedDrill(ctx, "TREADMILL PROGRAM", "PROGRAM", function(j, sg, now)
		local tg = j.target(now)
		local nx = nil
		for _, p in ipairs(sg.program) do
			if p.t > now - ctx.segAt + 1e-6 then
				nx = p
				break
			end
		end
		if tg ~= lastStep then
			lastStep = tg
			setText(stepText, tg.name or "INTERVAL", T.gold)
		end
		setText(nextText, nx and string.format("NEXT %s in %ds", nx.name, math.ceil(nx.t - (now - ctx.segAt))) or "LAST INTERVAL")
		setSpd((tg.mph - sg.tolMph) / sg.mphMax, (tg.mph + sg.tolMph) / sg.mphMax)
		setInc((tg.incl - sg.tolIncl) / sg.inclMax, (tg.incl + sg.tolIncl) / sg.inclMax)
		local okS, okI = math.abs(j.mph - tg.mph) <= sg.tolMph + 1e-6, math.abs(j.incl - tg.incl) <= sg.tolIncl + 1e-6
		spd.mark(j.mph / sg.mphMax, okS and T.green or T.orange)
		inc.mark(j.incl / sg.inclMax, okI and T.green or T.orange)
		setText(spdText, string.format("%.1f mph", j.mph), okS and T.text or T.orange)
		setText(incText, string.format("%d%% grade", j.incl), okI and T.text or T.orange)
		local dt = lastNow and (now - lastNow) or 0
		lastNow = now
		miles += j.mph / 3600 * dt * TIME_SCALE
		topSpeed = math.max(topSpeed, j.mph)
		setText(readout, string.format("TARGET %.1f mph%s%d%%%s%.2f mi", tg.mph, DOT, tg.incl, DOT, miles))
		ctx.intensity = math.clamp(0.2 + j.mph / 14 * 0.6 + j.incl / 12 * 0.3, 0, 1)
		ctx.speed(0.4 + j.mph / 14 * 1.6)
		ctx.attrQ("PoseIncline", j.incl / 12, 0.05)
		if now - screenAt >= 0.25 then
			screenAt = now
			GymVisuals.SetDisplay(ctx.station, string.format("%.1f MPH\nINCLINE %d%%\n%.2f mi", j.mph, j.incl, miles))
			ctx.stats(string.format("%.1f mph%s%d%% incline%s%.2f mi", j.mph, DOT, j.incl, DOT, miles))
		end
	end, function(_, _, hit)
		ctx.pulse(0.5)
	end)
	if not res then
		return nil
	end
	ctx.intensity = nil
	ctx.speed(1)
	local onTarget = math.floor(res.acc / seg.duration * 100 + 0.5)
	ctx.grade(math.clamp(res.acc / seg.duration / Workouts.TIMED_FULL, 0, 1))
	ctx.put("distance", math.floor(miles * 100 + 0.5) / 100)
	ctx.put("topSpeed", math.floor(topSpeed * 10 + 0.5) / 10)
	ctx.put("inZone", onTarget)
	ctx.note(string.format("%.2f mi%stop %.1f mph", miles, DOT, topSpeed))
	ctx.note(string.format("%d%% on the program", onTarget))
	GymVisuals.SetDisplay(ctx.station, string.format("DONE\n%.2f mi", miles))
	if not ctx.wait(0.5) then
		return nil
	end
	return ctx.score()
end

-- BIKE ------------------------------------------------------------------
-- A hill profile: pedal LEFT / RIGHT for cadence, shift gears so the strokes you can keep up turn into a
-- cadence inside the band.
GAMES.bike = function(ctx)
	local lv = ctx.level
	ctx.bind({
		{ id = "L", label = "PEDAL L", keys = { K.J, K.A, K.Left }, color = T.blue },
		{ id = "R", label = "PEDAL R", keys = { K.K, K.D, K.Right }, color = T.red },
		{ id = "gearDn", label = "GEAR -", keys = { K.S, K.Down } },
		{ id = "gearUp", label = "GEAR +", keys = { K.W, K.Up } },
	}, 4)
	ctx.setInfo("Pedal LEFT and RIGHT in turn ({L} / {R}) and keep the cadence in the green band. Hills bog you down: shift GEAR - ({gearDn}); flats and descents want GEAR + ({gearUp}).")
	UI.Clear(ctx.stage)
	local sw = stageWidth(ctx)
	local seg0 = ctx.peek()
	local hill = seg0.hill or {}
	local total = seg0.duration or 30
	-- the hill profile: a column per section, as tall as it is steep
	local px0, pw = 12, sw - 24
	for i, h in ipairs(hill) do
		local t1 = hill[i + 1] and hill[i + 1].t or total
		local hgt = math.clamp(10 + h.grade * 3, 4, 40)
		local c = UI.Frame(ctx.stage, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromOffset(px0 + pw * h.t / total, 46), Size = UDim2.fromOffset(math.max(2, pw * (t1 - h.t) / total - 2), hgt),
			BackgroundColor3 = h.grade >= 6 and T.red or (h.grade >= 3 and T.orange or (h.grade < 0 and T.cyan or T.green)), BackgroundTransparency = 0.45 })
		UI.Corner(c, 2)
	end
	local rider = UI.Frame(ctx.stage, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(px0, 4), Size = UDim2.fromOffset(4, 44), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3 })
	local gearText = label(ctx.stage, "", { Face = "number", TextSize = 14, Position = UDim2.fromOffset(12, 54), Size = UDim2.fromOffset(110, 18) })
	local rpmBar = meter(ctx.stage, UDim2.fromOffset(126, 56), UDim2.fromOffset(sw - 126 - 12, 14))
	local RPM_MAX = 140
	rpmBar.zone(seg0.lo / RPM_MAX, seg0.hi / RPM_MAX, T.green, 0.35)
	local status = label(ctx.stage, "", { Font = T.bold, TextSize = 14, Position = UDim2.fromOffset(12, 80), Size = UDim2.fromOffset(sw * 0.5, 18) })
	local readout = label(ctx.stage, "", { TextSize = 13, TextColor3 = Color3.fromRGB(120, 220, 255), AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(sw - 12, 80), Size = UDim2.fromOffset(sw * 0.48, 18), TextXAlignment = Enum.TextXAlignment.Right })
	local km, maxWatts, rpmSum, rpmT, lastNow, screenAt = 0, 0, 0, 0, nil, -math.huge
	local res, seg = timedDrill(ctx, "HILL PROFILE", "RIDE", function(j, sg, now)
		local el = now - ctx.segAt
		rider.Position = UDim2.fromOffset(px0 + pw * math.clamp(el / total, 0, 1), 4)
		local h = j.hill(now)
		local rpm = j.rpm(now)
		local ideal = Workouts.IdealGear(h.grade, sg.gears)
		local band = rpm >= sg.lo and rpm <= sg.hi
		rpmBar.mark(rpm / RPM_MAX, band and T.green or T.orange)
		setText(gearText, string.format("GEAR %d%s%d RPM", j.gear, DOT, math.floor(rpm + 0.5)))
		local hint
		if not j.lastTap or now - j.lastTap > 1.5 then
			hint = "PEDAL!"
		elseif j.gear > ideal + 1 then
			hint = "TOO HEAVY - SHIFT DOWN"
		elseif j.gear < ideal - 1 then
			hint = "SPINNING OUT - SHIFT UP"
		elseif rpm < sg.lo then
			hint = "FASTER LEGS"
		elseif rpm > sg.hi then
			hint = "EASE THE CADENCE"
		else
			hint = (h.name or "RIDE") .. string.format(" %+d%%", h.grade)
		end
		setText(status, hint, (band and math.abs(j.gear - ideal) <= 1) and T.green or T.orange)
		local dt = lastNow and (now - lastNow) or 0
		lastNow = now
		local watts = 0.02 * rpm * rpm * (0.7 + 0.12 * j.gear) * (1 + math.max(0, h.grade) * 0.06) * (0.9 + 0.12 * lv)
		maxWatts = math.max(maxWatts, watts)
		local kmh = rpm * j.gear * 0.055 / (1 + math.max(0, h.grade) * 0.08)
		km += kmh / 3600 * dt * TIME_SCALE
		if rpm > 0 then
			rpmSum += rpm * dt
			rpmT += dt
		end
		setText(readout, string.format("%d W%s%.1f km/h%s%.2f km", math.floor(watts), DOT, kmh, DOT, km))
		ctx.intensity = math.clamp(0.25 + watts / 450, 0, 1)
		ctx.speed(math.clamp(rpm / 80, 0, 2))
		ctx.attrQ("PoseClimb", h.grade >= 6 and 1 or 0)
		if now - screenAt >= 0.25 then
			screenAt = now
			GymVisuals.SetDisplay(ctx.station, string.format("RPM %d\n%d WATTS\nGEAR %d", math.floor(rpm), math.floor(watts), j.gear))
			ctx.stats(string.format("%d RPM%s%d W", math.floor(rpm), DOT, math.floor(watts)))
		end
	end, function(_, _, hit)
		if hit.alt == false then
			ctx.feedback("OTHER PEDAL", T.orange, false)
		end
	end)
	if not res then
		return nil
	end
	ctx.intensity = nil
	ctx.speed(1)
	ctx.grade(math.clamp(res.acc / seg.duration / Workouts.TIMED_FULL, 0, 1))
	local avgRpm = rpmT > 0 and rpmSum / rpmT or 0
	ctx.put("maxWatts", math.floor(maxWatts))
	ctx.put("avgRpm", math.floor(avgRpm))
	ctx.put("inZone", math.floor(res.inBand / seg.duration * 100 + 0.5))
	ctx.note(string.format("Max %d W%savg %d RPM", math.floor(maxWatts), DOT, math.floor(avgRpm)))
	ctx.note(string.format("%d%% in the cadence band", math.floor(res.inBand / seg.duration * 100 + 0.5)))
	GymVisuals.SetDisplay(ctx.station, string.format("DONE\nMAX %d W", math.floor(maxWatts)))
	return ctx.score()
end

-- ROWER -----------------------------------------------------------------
-- Catch, drive, finish, recover: ROW at the catch, let go at the finish, let the slide come back.
GAMES.rower = function(ctx)
	ctx.bind({ { id = "row", label = "ROW: DRIVE", say = "ROW", keys = { K.Space }, color = T.blue } }, 1)
	ctx.setInfo("Press ROW (SPACE) at the CATCH and hold the drive, let go at the FINISH. The slide comes back by itself - catch it as it arrives, don't rush it.")
	UI.Clear(ctx.stage)
	local sw = stageWidth(ctx)
	local mw = sw - 24
	local pieceText = label(ctx.stage, "", { Font = T.bold, TextSize = 15, Position = UDim2.fromOffset(12, 2), Size = UDim2.fromOffset(mw * 0.6, 20) })
	local spmText = label(ctx.stage, "", { Face = "number", TextSize = 14, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(12 + mw, 4), Size = UDim2.fromOffset(mw * 0.4, 18), TextXAlignment = Enum.TextXAlignment.Right })
	label(ctx.stage, "CATCH", { TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(12, 28), Size = UDim2.fromOffset(80, 14) })
	label(ctx.stage, "FINISH", { TextSize = 11, TextColor3 = T.sub, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(12 + mw, 28), Size = UDim2.fromOffset(80, 14), TextXAlignment = Enum.TextXAlignment.Right })
	local slide = meter(ctx.stage, UDim2.fromOffset(12, 44), UDim2.fromOffset(mw, 20))
	local seg0 = ctx.peek()
	slide.zone(0, seg0.catchW or 0.1, T.green, 0.3)
	slide.zone(seg0.finishLo or 0.86, 1, T.green, 0.3)
	local phaseText = label(ctx.stage, "", { Font = T.bold, TextSize = 14, Position = UDim2.fromOffset(12, 72), Size = UDim2.fromOffset(mw * 0.5, 18) })
	local lastText = label(ctx.stage, "", { TextSize = 13, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(12 + mw, 72), Size = UDim2.fromOffset(mw * 0.5, 18), TextXAlignment = Enum.TextXAlignment.Right })
	local readout = label(ctx.stage, "", { TextSize = 13, TextColor3 = Color3.fromRGB(120, 220, 255), Position = UDim2.fromOffset(12, 94), Size = UDim2.fromOffset(mw, 18) })
	local meters, maxSpm, lastStrokeT, spm, screenAt, lastPiece = 0, 0, nil, 0, -math.huge, nil
	local res = timedDrill(ctx, "ROWING PIECES", "PIECE", function(j, sg, now)
		local pc = j.piece(now)
		if pc ~= lastPiece then
			lastPiece = pc
			setText(pieceText, string.format("%s%s%d SPM", pc.name, DOT, pc.spm), T.gold)
		end
		slide.mark(j.x, j.phase == "drive" and T.gold or Color3.new(1, 1, 1))
		local ph = j.phase
		setText(phaseText, ph == "drive" and (j.x >= 1 and "LET GO - FINISH!" or "DRIVE!") or (ph == "catch" and "CATCH - ROW!" or "RECOVER..."), ph == "catch" and T.gold or (ph == "drive" and T.green or T.sub))
		local split = spm > 0 and math.clamp(150 - (spm - 18) * 2.2 - (j.last and j.last.q or 0.5) * 18, 85, 175) or 0
		setText(spmText, string.format("%d SPM", math.floor(spm + 0.5)), (math.abs(spm - pc.spm) <= 2) and T.green or T.text)
		setText(readout, split > 0 and string.format("%s /500m%s%d m%s%d strokes", clock(split), DOT, math.floor(meters), DOT, #j.strokes) or "")
		ctx.drive(j.x)
		ctx.intensity = ph == "drive" and 0.9 or 0.55
		if now - screenAt >= 0.25 then
			screenAt = now
			GymVisuals.SetDisplay(ctx.station, split > 0 and string.format("%s /500\n%d SPM\n%d m", clock(split), math.floor(spm + 0.5), math.floor(meters)) or "ROW")
			ctx.stats(string.format("%d spm%s%d m", math.floor(spm + 0.5), DOT, math.floor(meters)))
		end
	end, function(_, _, hit)
		if hit.catch == "rushed" then
			ctx.feedback("RUSHED THE SLIDE", T.orange, false)
		elseif hit.stroke then
			local st = hit.stroke
			if lastStrokeT then
				spm = 60 / math.max(0.5, st.t - lastStrokeT)
				maxSpm = math.max(maxSpm, spm)
			end
			lastStrokeT = st.t
			meters += 7 + 4 * st.q
			setText(lastText, string.format("%s CATCH%s%s", string.upper(st.catch or "clean"), DOT, string.upper(st.finish)), st.q >= 0.9 and T.green or T.orange)
			ctx.feedback(st.q >= 0.95 and "PERFECT STROKE" or (st.finish == "short" and "SHORT STROKE" or (st.catch == "pause" and "PAUSED AT THE CATCH" or "GOOD STROKE")), ctx.gradeColor(st.q), st.q)
		end
	end)
	if not res then
		return nil
	end
	ctx.intensity = nil
	ctx.put("meters", math.floor(meters))
	ctx.put("maxSpm", math.floor(maxSpm))
	ctx.put("strokes", res.strokes)
	ctx.note(string.format("%d m rowed%s%d strokes", math.floor(meters), DOT, res.strokes))
	ctx.note(string.format("max %d spm", math.floor(maxSpm)))
	GymVisuals.SetDisplay(ctx.station, string.format("DONE\n%d m", math.floor(meters)))
	return ctx.score()
end

-- RECOVERY STATIONS -------------------------------------------------------
local function toF(c)
	return math.floor(c * 9 / 5 + 32 + 0.5)
end

-- ICE BATH: full breaths from empty, long exhales, ride out the cold waves
GAMES.icebath = function(ctx)
	local lv = ctx.level
	local tempC = Config.IceBathTempC[math.clamp(lv, 1, #Config.IceBathTempC)]
	ctx.bind({ { id = "breathe", label = "BREATHE IN", say = "BREATHE", keys = { K.Space }, color = T.blue } }, 1)
	ctx.setInfo("Hold (or tap) BREATHE IN (SPACE) for a full breath, let go for a long slow exhale until you're empty. Calm breathing beats the cold shock.")
	UI.Clear(ctx.stage)
	local sw = stageWidth(ctx)
	local lungs = UI.Frame(ctx.stage, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(62, 58), Size = UDim2.fromOffset(30, 30), BackgroundColor3 = Color3.fromRGB(80, 170, 255), BackgroundTransparency = 0.3 })
	UI.Corner(lungs, 60)
	local x0 = 130
	local mw = sw - x0 - 12
	local breathText = label(ctx.stage, "", { Font = T.bold, TextSize = 15, Position = UDim2.fromOffset(x0, 4), Size = UDim2.fromOffset(mw, 20) })
	label(ctx.stage, "COLD SHOCK", { TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(x0, 30), Size = UDim2.fromOffset(mw * 0.5, 14) })
	local waveText = label(ctx.stage, "", { Font = T.bold, TextSize = 12, TextColor3 = T.cyan, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(x0 + mw, 29), Size = UDim2.fromOffset(mw * 0.5, 15), TextXAlignment = Enum.TextXAlignment.Right })
	local cold = meter(ctx.stage, UDim2.fromOffset(x0, 46), UDim2.fromOffset(mw, 16))
	cold.zone(0, 0.5, T.green, 0.55)
	cold.zone(0.5, 0.8, T.orange, 0.55)
	cold.zone(0.8, 1, T.red, 0.45)
	local line1 = label(ctx.stage, "", { TextSize = 13, TextColor3 = Color3.fromRGB(150, 210, 255), Position = UDim2.fromOffset(x0, 70), Size = UDim2.fromOffset(mw, 18) })
	local line2 = label(ctx.stage, "", { TextSize = 13, TextColor3 = T.sub, Position = UDim2.fromOffset(x0, 90), Size = UDim2.fromOffset(mw, 18) })
	local res, seg = timedDrill(ctx, string.format("WATER %d°F", toF(tempC)), "SESSION", function(j, sg, now)
		local size = 30 + 66 * j.l
		lungs.Size = UDim2.fromOffset(size, size)
		local on = j.br.on
		if on then
			setText(breathText, j.l >= 1 and "FULL - LET IT GO" or "BREATHE IN...", j.l >= 1 and T.gold or T.text)
		else
			setText(breathText, j.l > 0.02 and "LONG EXHALE..." or "EMPTY - BREATHE IN", j.l > 0.02 and T.cyan or T.gold)
		end
		cold.mark(j.S, j.S < 0.5 and T.green or (j.S < 0.8 and T.orange or T.red))
		setText(waveText, j.wave(now) and "COLD WAVE!" or "")
		setText(line1, string.format("WATER %d°F (%d°C)%sTIME IN %s", toF(tempC), tempC, DOT, clock((now - ctx.segAt) * TIME_SCALE)))
		setText(line2, string.format("Calm breaths %d / %d", math.floor(j.good + 0.5), j.breaths), j.S >= 0.8 and T.red or T.sub)
		ctx.drive(j.l)
		ctx.attrQ("PoseLungs", j.l, 0.05)
		ctx.attrQ("PoseShiver", j.S, 0.05)
		ctx.stats(string.format("Cold %s%sbreaths %d", pct(j.S), DOT, math.floor(j.good + 0.5)))
	end, function(_, _, hit)
		if hit.exhale then
			if hit.good then
				ctx.feedback("CALM BREATH", T.green, false)
			elseif not hit.full then
				ctx.feedback("GASPING - FILL UP", T.orange, false)
			else
				ctx.feedback("EMPTY OUT FIRST", T.orange, false)
			end
		end
	end)
	if not res then
		return nil
	end
	local calmPct = math.floor(res.calm / seg.duration * 100 + 0.5)
	ctx.grade(math.clamp(res.calm / seg.duration / Workouts.TIMED_FULL, 0, 1))
	ctx.put("sync", calmPct)
	ctx.put("calmBreaths", math.floor(res.good + 0.5))
	ctx.note(string.format("%s at %d°F", clock(seg.duration * TIME_SCALE), toF(tempC)))
	ctx.note(string.format("Calm %d%% of the time%s%d calm breaths", calmPct, DOT, math.floor(res.good + 0.5)))
	return ctx.score()
end

-- STRETCHING: ease into each pose and keep it in the range as the muscle lets go - never past it
GAMES.stretch = function(ctx)
	ctx.bind({ { id = "sink", label = "SINK DEEPER", say = "SINK", keys = { K.Space }, color = T.blue } }, 1)
	ctx.setInfo("Hold (or tap) SINK DEEPER (SPACE) to ease in, let go to back off. Stay in the green range as it creeps deeper. Past it is an overstretch.")
	local segs = ctx.plan.segs
	local inSum, overs, tweaks = 0, 0, 0
	for i, seg0 in ipairs(segs) do
		local name = seg0.name or "STRETCH"
		if not ctx.round(i, #segs, name, "POSE") then
			return nil
		end
		UI.Clear(ctx.stage)
		local sw = stageWidth(ctx)
		local mw = sw - 24
		local status = label(ctx.stage, "", { Font = T.bold, TextSize = 16, Position = UDim2.fromOffset(12, 4), Size = UDim2.fromOffset(mw * 0.6, 22) })
		local timeText = label(ctx.stage, "", { Face = "number", TextSize = 14, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(12 + mw, 6), Size = UDim2.fromOffset(mw * 0.35, 18), TextXAlignment = Enum.TextXAlignment.Right })
		label(ctx.stage, "EASY", { TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(12, 32), Size = UDim2.fromOffset(60, 14) })
		label(ctx.stage, "TOO FAR", { TextSize = 11, TextColor3 = T.sub, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(12 + mw, 32), Size = UDim2.fromOffset(80, 14), TextXAlignment = Enum.TextXAlignment.Right })
		local range = meter(ctx.stage, UDim2.fromOffset(12, 48), UDim2.fromOffset(mw, 22))
		local setBand = range.zone(0, 0.1, T.green, 0.3)
		local setOver = range.zone(0.9, 1, T.red, 0.45)
		local romText = label(ctx.stage, "", { TextSize = 13, TextColor3 = T.sub, Position = UDim2.fromOffset(12, 80), Size = UDim2.fromOffset(mw, 18) })
		ctx.attrQ("PoseStretch", seg0.pose or 0)
		local j, seg, start = ctx.begin()
		if not j then
			return nil
		end
		ctx.on(function(id, down, t)
			j.input(id, down, t)
		end)
		local wasOver = false
		local okPlay = playSegment(ctx, j, function(now)
			local lo, hi = j.band(now)
			setBand(lo, hi)
			setOver(hi + seg.overMargin, 1)
			local over = j.z > hi + seg.overMargin
			local inR = j.z >= lo and j.z <= hi
			range.mark(j.z, over and T.red or (inR and T.green or Color3.new(1, 1, 1)))
			setText(status, over and "OVERSTRETCH - BACK OFF!" or (inR and "HOLD IT... BREATHE" or (j.z < lo and "EASE DEEPER" or "EASY NOW")), over and T.red or (inR and T.green or T.text))
			setText(timeText, string.format("%.1fs", math.max(0, seg.dur - (now - start))))
			setText(romText, string.format("%s%sin range %.1fs", name, DOT, j.inT * Workouts.TICK))
			if over and not wasOver then
				ctx.feedback("OUCH - TOO FAR", T.red, false)
			end
			wasOver = over
			ctx.drive(j.z)
			ctx.progress((now - start) / seg.dur)
		end)
		ctx.on(nil)
		if not okPlay then
			return nil
		end
		local res = ctx.close(j)
		inSum += res.inRange
		overs += res.overs
		if res.tweaked then
			tweaks += 1
		end
		ctx.feedback(res.tweaked and "TWEAKED IT" or (res.q >= 0.9 and "PERFECT HOLD" or (res.q >= 0.65 and "GOOD STRETCH" or "NOT IN IT")), res.tweaked and T.red or ctx.gradeColor(res.q), res.q)
	end
	ctx.drive(0)
	ctx.put("sync", math.floor(ctx.score() * 100 + 0.5))
	ctx.put("timeInRange", math.floor(inSum * 10 + 0.5) / 10)
	ctx.note(string.format("%.1fs in range over %d stretches", inSum, #segs))
	if overs > 0 then
		ctx.note(string.format("%d overstretch%s%s", overs, overs > 1 and "es" or "", tweaks > 0 and " (tweaked one)" or ""))
	end
	return ctx.score()
end

-- MASSAGE: pick the sore groups (the body map shows them), then relax into each stroke
local GROUP_LABEL = { back = "BACK", shoulders = "DELTS", legs = "LEGS", arms = "ARMS", chest = "CHEST", core = "CORE", neck = "NECK" }
GAMES.massage = function(ctx)
	local seg0 = ctx.peek()
	local groups = seg0.groups or Workouts.MassageGroups
	local function bindChoose()
		ctx.bind({
			{ id = "prev", label = GLYPH.prev .. " PREV", keys = { K.A, K.Left } },
			{ id = "ok", label = "WORK THIS", say = "WORK THIS", keys = { K.Space }, color = T.gold },
			{ id = "next", label = "NEXT " .. GLYPH.next, keys = { K.D, K.Right } },
		}, 3)
		if ctx.buttons.ok then
			ctx.buttons.ok.TextColor3 = T.bg
		end
		ctx.setInfo("Where does it hurt? Move ({prev} / {next}) to the sorest group on the map and WORK THIS (SPACE). The sorest group left scores best.")
	end
	local function bindWork()
		ctx.bind({ { id = "ok", label = "RELAX", say = "RELAX", keys = { K.Space }, color = T.blue } }, 1)
		ctx.setInfo("Breathe out and RELAX (SPACE) as each stroke lands on the line.")
	end
	-- the body map: each group's parts glow by its soreness
	local function paintMap(j)
		if not ctx.map then
			return
		end
		local w = {}
		for _, p in ipairs(Config.MuscleParts) do
			local v = j.sore[p.group] or 0
			if j.worked[p.group] then
				v *= 0.25
			end
			w[p.id] = v
		end
		pcall(function()
			ctx.map:SetTargets(w, T.orange, 1)
		end)
	end
	bindChoose()
	if not ctx.round(1, 1, "WHERE'S IT SORE?", "SESSION") then
		return nil
	end
	UI.Clear(ctx.stage)
	local sw = stageWidth(ctx)
	local n = #groups
	local cw = math.floor((sw - 20 - (n - 1) * 4) / n)
	local chips = {}
	for i, g in ipairs(groups) do
		local f = UI.Frame(ctx.stage, { Position = UDim2.fromOffset(10 + (i - 1) * (cw + 4), 6), Size = UDim2.fromOffset(cw, 50), BackgroundColor3 = T.panel2 })
		UI.Corner(f, 6)
		local nm = label(f, GROUP_LABEL[g] or string.upper(g), { Font = T.bold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(2, 4), Size = UDim2.new(1, -4, 0, 16) })
		local bg = UI.Frame(f, { Position = UDim2.new(0, 6, 1, -16), Size = UDim2.new(1, -12, 0, 8), BackgroundColor3 = DARK })
		UI.Corner(bg, 3)
		local fill = UI.Frame(bg, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.orange })
		UI.Corner(fill, 3)
		chips[i] = { frame = f, name = nm, fill = fill }
	end
	local status = label(ctx.stage, "", { Font = T.bold, TextSize = 15, Position = UDim2.fromOffset(12, 62), Size = UDim2.fromOffset(sw * 0.6, 20) })
	local timeText = label(ctx.stage, "", { TextSize = 12, TextColor3 = T.sub, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(sw - 12, 64), Size = UDim2.fromOffset(sw * 0.35, 16), TextXAlignment = Enum.TextXAlignment.Right })
	-- the work phase's strokes slide in along one lane to the line
	local lineX = 70
	local lane = UI.Frame(ctx.stage, { Position = UDim2.fromOffset(10, 86), Size = UDim2.new(1, -20, 0, 26), BackgroundColor3 = DARK, BackgroundTransparency = 0.3 })
	UI.Corner(lane, 6)
	UI.Frame(ctx.stage, { Position = UDim2.fromOffset(lineX - 2, 84), Size = UDim2.fromOffset(4, 30), BackgroundColor3 = T.gold, ZIndex = 2 })
	local dots = {}
	for k = 1, seg0.strokes or 5 do
		local d = UI.Frame(ctx.stage, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(20, 20), Position = UDim2.fromOffset(NOTE_FAR, 99), BackgroundColor3 = T.cyan, ZIndex = 3 })
		UI.Corner(d, 10)
		dots[k] = d
	end
	local j, seg = ctx.begin()
	if not j then
		return nil
	end
	paintMap(j)
	local phase = "choose"
	local pickTexts = {}
	ctx.on(function(id, down, t)
		local hit = j.input(id, down, t)
		if not hit then
			return
		end
		if hit.stroke then
			ctx.feedback(hit.stroke.grade == "perfect" and "AHHH..." or "RELAX", hit.stroke.grade == "perfect" and T.green or T.text, false)
		elseif hit.stray then
			ctx.feedback("TENSING UP", T.orange, false)
		elseif hit.already then
			ctx.feedback("ALREADY DONE", T.orange, false)
		end
	end)
	local pps = 150 / (seg.beat or 1)
	local okPlay = playSegment(ctx, j, function(now)
		-- a pick made since the last frame (yours, or the therapist's when the time ran out)
		while #pickTexts < #j.picks do
			local p = j.picks[#pickTexts + 1]
			if p.timedOut then
				ctx.feedback("TOO SLOW - THERAPIST'S CHOICE", T.orange, 0)
			else
				ctx.feedback(p.q >= 0.95 and "RIGHT ON THE KNOT" or (p.q >= 0.6 and "TIGHT THERE" or "NOT MUCH THERE"), ctx.gradeColor(p.q), p.q)
			end
			table.insert(pickTexts, GROUP_LABEL[p.group] or p.group)
		end
		if j.phase ~= phase then
			phase = j.phase
			if phase == "work" then
				bindWork()
			else
				bindChoose()
			end
			paintMap(j)
		end
		for i, g in ipairs(groups) do
			local c = chips[i]
			local v = (j.sore[g] or 0) * (j.worked[g] and 0.25 or 1)
			c.fill.Size = UDim2.fromScale(math.clamp(v, 0, 1), 1)
			local sel = phase == "choose" and i == j.cursor
			local col = sel and T.gold or (j.worked[g] and T.ink or T.panel2)
			if c.frame.BackgroundColor3 ~= col then
				c.frame.BackgroundColor3 = col
				c.name.TextColor3 = sel and T.bg or (j.worked[g] and T.sub or T.text)
			end
		end
		if phase == "choose" then
			setText(status, string.format("ROUND %d/%d: PICK A SORE SPOT", j.round, seg.rounds), T.gold)
			setText(timeText, string.format("%ds", math.max(0, math.ceil(seg.chooseT - (now - j.chooseAt)))))
			for _, d in ipairs(dots) do
				d.Visible = false
			end
		else
			local p = j.picks[#j.picks]
			setText(status, "WORKING: " .. ((p and GROUP_LABEL[p.group]) or ""), T.text)
			setText(timeText, "")
			for k, st in ipairs(j.strokes or {}) do
				local d = dots[k]
				if d then
					d.Visible = not st.judged
					if not st.judged then
						d.Position = UDim2.fromOffset(math.min(NOTE_FAR, lineX + (st.t - now) * pps), 99)
					end
				end
			end
		end
		ctx.progress(((j.round - 1) + (phase == "work" and 0.5 or 0)) / math.max(1, seg.rounds))
	end)
	ctx.on(nil)
	if not okPlay then
		return nil
	end
	local res = ctx.close(j)
	ctx.put("sync", math.floor(res.relax / math.max(1, res.strokes) * 100 + 0.5))
	ctx.put("soreSpots", math.floor(res.pickSum / math.max(1, res.rounds) * 100 + 0.5))
	ctx.note("Worked: " .. table.concat(pickTexts, ", "))
	ctx.note(string.format("Found the knots %d%%", math.floor(res.pickSum / math.max(1, res.rounds) * 100 + 0.5)))
	return ctx.score()
end

-- RECOVERY CHAMBER: ride the pressure profile, clear your ears
GAMES.chamber = function(ctx)
	ctx.bind({
		{ id = "down", label = "VENT", keys = { K.S, K.Down } },
		{ id = "eq", label = "EQUALIZE", say = "EQUALIZE", keys = { K.Space }, color = T.cyan },
		{ id = "up", label = "PRESSURISE", keys = { K.W, K.Up }, color = T.blue },
	}, 3)
	if ctx.buttons.eq then
		ctx.buttons.eq.TextColor3 = T.bg
	end
	ctx.setInfo("Follow the pressure line: hold PRESSURISE ({up}) or VENT ({down}). Every change fills your ears - EQUALIZE (SPACE) before they hurt.")
	UI.Clear(ctx.stage)
	local sw = stageWidth(ctx)
	local seg0 = ctx.peek()
	local gx, gw, gy, gh = 12, sw - 24, 6, 62
	local graph = UI.Frame(ctx.stage, { Position = UDim2.fromOffset(gx, gy), Size = UDim2.fromOffset(gw, gh), BackgroundColor3 = DARK, BackgroundTransparency = 0.2 })
	UI.Corner(graph, 4)
	local maxP = seg0.maxP or 1.6
	local function yOf(p)
		return gh - 4 - (p - 1) / (maxP - 1) * (gh - 8)
	end
	-- the target line as dots (a straight run of pressure readings, no rotated frames)
	local pts = seg0.profile or { { 0, 1 }, { 1, 1 } }
	local dur = seg0.duration or 30
	for k = 0, 40 do
		local el = dur * k / 40
		local p = 1
		for i = 2, #pts do
			if el <= pts[i][1] then
				local a, b = pts[i - 1], pts[i]
				p = a[2] + (b[2] - a[2]) * math.clamp((el - a[1]) / math.max(1e-6, b[1] - a[1]), 0, 1)
				break
			end
		end
		UI.Frame(graph, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(gw * k / 40, yOf(p)), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = T.green, BackgroundTransparency = 0.2 })
	end
	local you = UI.Frame(graph, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3 })
	UI.Corner(you, 6)
	local pText = label(ctx.stage, "", { Face = "number", TextSize = 14, Position = UDim2.fromOffset(12, 74), Size = UDim2.fromOffset(sw * 0.5, 18) })
	label(ctx.stage, "EARS", { TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(sw * 0.52, 76), Size = UDim2.fromOffset(40, 14) })
	local ear = meter(ctx.stage, UDim2.fromOffset(sw * 0.52 + 42, 76), UDim2.fromOffset(sw * 0.48 - 54, 14))
	ear.zone(0.75, 1, T.red, 0.45)
	local recText = label(ctx.stage, "", { TextSize = 13, TextColor3 = T.sub, Position = UDim2.fromOffset(12, 96), Size = UDim2.fromOffset(sw - 24, 18) })
	local res, seg = timedDrill(ctx, string.format("%.1f ATA DIVE", pts[2] and pts[2][2] or 1.3), "SESSION", function(j, sg, now)
		local el = now - ctx.segAt
		you.Position = UDim2.fromOffset(gw * math.clamp(el / dur, 0, 1), yOf(j.P))
		local tg = j.target(now)
		local d = math.abs(j.P - tg)
		you.BackgroundColor3 = d <= sg.tol and T.green or (d <= 2.5 * sg.tol and T.orange or T.red)
		local pain = now < j.painUntil
		setText(pText, string.format("%.2f ATA%sTARGET %.2f", j.P, DOT, tg), d <= sg.tol and T.text or T.orange)
		ear.fill(j.ear, j.ear >= 0.75 and T.red or (j.ear >= 0.45 and T.orange or T.green))
		setText(recText, pain and "EAR PAIN - EQUALIZE!" or string.format("O2 %d%%%scell recovery %d%%", 94 + math.floor(el / dur * 4), DOT, math.floor(j.acc * Workouts.TICK / dur * 100 / Workouts.TIMED_FULL)), pain and T.red or T.sub)
		ctx.stats(string.format("%.2f ATA%sears %s", j.P, DOT, pct(j.ear)))
	end, function(_, _, hit)
		if hit.eq then
			ctx.feedback(hit.cleared > 0.2 and "POP - CLEAR" or "NOTHING TO CLEAR", hit.cleared > 0.2 and T.green or T.sub, false)
		end
	end)
	if not res then
		return nil
	end
	local onLine = math.floor(res.acc / seg.duration * 100 + 0.5)
	ctx.grade(math.clamp(res.acc / seg.duration / Workouts.TIMED_FULL, 0, 1))
	ctx.put("sync", onLine)
	ctx.note(string.format("On the pressure line %d%%", onLine))
	ctx.note(res.pains > 0 and string.format("%d ear squeeze%s", res.pains, res.pains > 1 and "s" or "") or "Clean dive, no ear pain")
	return ctx.score()
end

-- SAUNA (weight cut): push the heat for the cut, step out before you go light-headed, sip to stay sharp
GAMES.sauna = function(ctx)
	local lv = ctx.level
	local saunaC = Config.SaunaTempC[math.clamp(lv, 1, #Config.SaunaTempC)]
	local P = State.P
	local hyd0 = P and P.condition and tonumber(P.condition.hydration) or 80
	local st = Catalog.Stations[ctx.station]
	local lvMult = st and st.levels[math.clamp(lv, 1, #st.levels)] and st.levels[math.clamp(lv, 1, #st.levels)].mult or 1
	local hydCost = math.abs(ctx.act.recovery and ctx.act.recovery.hydration or 25)
	ctx.bind({
		{ id = "door", label = "STEP OUT / IN", say = "STEP OUT", keys = { K.Space }, color = T.orange },
		{ id = "sip", label = "SIP WATER", keys = { K.J, K.F }, color = T.cyan },
	}, 2)
	ctx.setInfo("Stay in the heat to cut water, STEP OUT (SPACE) before your core temperature hits the red, step back in once cooled. SIP ({sip}) to take the edge off.")
	UI.Clear(ctx.stage)
	local sw = stageWidth(ctx)
	local x0 = 108
	local mw = sw - x0 - 12
	local where = label(ctx.stage, "", { Font = T.bold, TextSize = 15, Position = UDim2.fromOffset(12, 4), Size = UDim2.fromOffset(sw - 24, 20) })
	label(ctx.stage, "CORE TEMP", { TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(12, 32), Size = UDim2.fromOffset(x0 - 16, 14) })
	local temp = meter(ctx.stage, UDim2.fromOffset(x0, 30), UDim2.fromOffset(mw, 16))
	temp.zone(0.7, 0.85, T.orange, 0.5)
	temp.zone(0.85, 1, T.red, 0.4)
	label(ctx.stage, "WATER CUT", { TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(12, 56), Size = UDim2.fromOffset(x0 - 16, 14) })
	local cut = meter(ctx.stage, UDim2.fromOffset(x0, 54), UDim2.fromOffset(mw, 16))
	label(ctx.stage, "HYDRATION", { TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(12, 80), Size = UDim2.fromOffset(x0 - 16, 14) })
	local hyd = meter(ctx.stage, UDim2.fromOffset(x0, 78), UDim2.fromOffset(mw * 0.6, 14))
	local cutText = label(ctx.stage, "", { Face = "number", TextSize = 13, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(x0 + mw, 78), Size = UDim2.fromOffset(mw * 0.38, 16), TextXAlignment = Enum.TextXAlignment.Right })
	local wasInside = true
	local res, seg = timedDrill(ctx, saunaC > 0 and string.format("WEIGHT CUT %d°F", toF(saunaC)) or "WEIGHT CUT: SAUNA SUIT", "SESSION", function(j, sg, now)
		local forced = now < j.forcedUntil
		if j.inside then
			setText(where, saunaC > 0 and string.format("IN THE HEAT - %d°F", toF(saunaC)) or "SAUNA SUIT - SWEATING", j.T > 0.85 and T.red or T.text)
		else
			setText(where, forced and "LIGHT-HEADED - COACH PULLED YOU OUT" or "COOLING OFF OUTSIDE", forced and T.red or T.cyan)
		end
		if j.inside ~= wasInside then
			wasInside = j.inside
			if ctx.buttons.door then
				ctx.buttons.door.Text = j.inside and "STEP OUT" or "STEP IN"
			end
		end
		temp.mark(j.T, j.T > 0.85 and T.red or (j.T > 0.7 and T.orange or T.green))
		local share = math.clamp(j.w / sg.goal, 0, 1)
		cut.fill(share, share >= 1 and T.gold or T.green)
		local lost = j.w * lvMult * 2.5 / sg.goal
		setText(cutText, string.format("-%.1f lbs", lost))
		local h = math.clamp(hyd0 - hydCost * math.min(1, j.w / sg.goal), 0, 100)
		hyd.fill(h / 100, h < 40 and T.red or T.cyan)
		ctx.attrQ("PoseHeat", j.inside and j.T or 0, 0.05)
		ctx.stats(string.format("Core %s%scut %s", pct(j.T), DOT, pct(share)))
	end, function(_, _, hit)
		if hit.sip then
			ctx.feedback("SIP", T.cyan, false)
		elseif hit.wait then
			ctx.feedback("SMALL SIPS", T.sub, false)
		elseif hit.forced then
			ctx.feedback("SIT DOWN A MOMENT", T.orange, false)
		end
	end)
	if not res then
		return nil
	end
	local q = Workouts.SaunaScore(res)
	ctx.grade(q)
	local lost = 2.5 * lvMult * (0.8 + 0.2 * (0.5 + q * 0.95))
	ctx.put("waterLost", math.floor(lost * 10 + 0.5) / 10)
	ctx.note(string.format("~%.1f lbs water", lost))
	if res.faints > 0 then
		ctx.note("Went light-headed - pulled out")
	end
	ctx.note("Rehydrate after the weigh-in")
	return ctx.score()
end

-- ROADWORK & SWIM -------------------------------------------------------
-- running speed from the character's movement, smoothed (drives the heart rate)
local function trackMovement(ctx, state, dt)
	local _, _, root = State.char()
	if not root then
		return
	end
	local p = Vector3.new(root.Position.X, 0, root.Position.Z)
	if state.lastPos then
		local step = (p - state.lastPos).Magnitude
		if step < 12 then -- ignore teleports
			state.dist += step
		end
		local inst = math.clamp(step / math.max(dt, 1e-3) / 24, 0, 1)
		ctx.intensity = (ctx.intensity or 0) * 0.93 + inst * 0.07
	end
	state.lastPos = p
end

-- ROADWORK: run the loop through every checkpoint (measured by the server)
GAMES.course = function(ctx, info)
	ctx.bind({ { id = "finish", label = "FINISH EARLY", keys = {}, pad = { K.ButtonY }, color = T.red } }, 1)
	ctx.setInfo("Run the loop around the gym through all 8 checkpoints and back to the start arch. Hold W - your stamina sets your pace.")
	compactPanel(ctx)
	ctx.header.Text = "ROADWORK" .. DOT .. "8 CHECKPOINTS"
	UI.Clear(ctx.stage)
	local status = UI.Text(ctx.stage, "", { Font = T.bold, TextSize = 16, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), AutomaticSize = Enum.AutomaticSize.None })
	local gym = workspace:FindFirstChild("Gym")
	local cpFolder = gym and gym:FindFirstChild("TrackCheckpoints")
	local order = { 2, 3, 4, 5, 6, 7, 8, 1 }
	local reached = 0
	local done = false
	local beacon = Instance.new("Part")
	beacon.Anchored, beacon.CanCollide, beacon.CanQuery, beacon.CanTouch = true, false, false, false
	beacon.Size = Vector3.new(1.5, 40, 1.5)
	beacon.Material = Enum.Material.Neon
	beacon.Color = T.gold
	beacon.Transparency = 0.35
	beacon.Parent = workspace
	ctx.onDestroy(function()
		beacon:Destroy()
	end)
	local function place()
		local cp = cpFolder and cpFolder:FindFirstChild("CP" .. order[math.min(#order, reached + 1)])
		if cp then
			beacon.CFrame = CFrame.new(cp.Position.X, 20, cp.Position.Z)
		end
	end
	place()
	table.insert(ctx.conns, State.Notify.OnClientEvent:Connect(function(msg)
		if type(msg) == "table" and msg.t == "checkpoint" and (msg.token == nil or msg.token == info.token) then
			reached = msg.n
			ctx.feedback("CHECKPOINT " .. msg.n .. "/" .. msg.total, T.gold)
			ctx.setProgress(msg.n / msg.total)
			if msg.n >= msg.total then
				done = true
			else
				place()
			end
		end
	end))
	local quit = false
	ctx.on(function(id, down)
		if down and id == "finish" then
			quit = true
		end
	end)
	local move = { dist = 0, lastPos = nil }
	local start, last = os.clock(), os.clock()
	local miles = 0
	while not done and not quit do
		if ctx.cancelled then
			return nil
		end
		local now = os.clock()
		trackMovement(ctx, move, now - last)
		last = now
		local _, _, root = State.char()
		local cp = cpFolder and cpFolder:FindFirstChild("CP" .. order[math.min(#order, reached + 1)])
		local dist = (root and cp) and math.floor((Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(cp.Position.X, 0, cp.Position.Z)).Magnitude) or 0
		local el = now - start
		miles = move.dist * STUD_M / 1609.34
		local pace = miles > 0.01 and clock(el / miles) or "--:--"
		status.Text = string.format("CP %d/8%sNext %d studs%s%s%s%.2f mi%s%s /mi", reached, DOT, dist, DOT, clock(el), DOT, miles, DOT, pace)
		ctx.stats(string.format("%.2f mi%s%s /mi", miles, DOT, pace))
		RunService.Heartbeat:Wait()
	end
	ctx.intensity = nil
	beacon:Destroy()
	local el = os.clock() - start
	ctx.put("distance", math.floor(miles * 100 + 0.5) / 100)
	if miles > 0.01 then
		ctx.put("speed", math.floor(miles / (el / 3600) * 10 + 0.5) / 10)
		ctx.note(string.format("%.2f mi in %s (%s /mi)", miles, clock(el), clock(el / miles)))
	end
	ctx.note(string.format("%d/8 checkpoints", reached))
	return 1
end

-- SWIMMING: swim lengths of the pool (measured by the server)
GAMES.swim = function(ctx, info)
	ctx.bind({ { id = "finish", label = "FINISH EARLY", keys = {}, pad = { K.ButtonY }, color = T.red } }, 1)
	local target = info.lengths or 4
	ctx.setInfo(string.format("Jump in and swim %d lengths: touch the far wall, then come back. Swimming builds stamina and speeds recovery.", target))
	compactPanel(ctx)
	ctx.header.Text = string.format("SWIM%s%d LENGTHS", DOT, target)
	UI.Clear(ctx.stage)
	local status = UI.Text(ctx.stage, "", { Font = T.bold, TextSize = 16, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), AutomaticSize = Enum.AutomaticSize.None })
	local lengths, done, quit = 0, false, false
	local lastLengthAt
	local bestLength
	local start, last = os.clock(), os.clock()
	table.insert(ctx.conns, State.Notify.OnClientEvent:Connect(function(msg)
		if type(msg) == "table" and msg.t == "length" and (msg.token == nil or msg.token == info.token) then
			local now = os.clock()
			local split = now - (lastLengthAt or start)
			lastLengthAt = now
			bestLength = bestLength and math.min(bestLength, split) or split
			lengths = msg.n
			ctx.feedback(string.format("LENGTH %d/%d  %s", msg.n, msg.total, clock(split)), T.gold)
			ctx.setProgress(msg.n / msg.total)
			done = msg.n >= msg.total
		end
	end))
	ctx.on(function(id, down)
		if down and id == "finish" then
			quit = true
		end
	end)
	local move = { dist = 0, lastPos = nil }
	while not done and not quit do
		if ctx.cancelled then
			return nil
		end
		local now = os.clock()
		trackMovement(ctx, move, now - last)
		last = now
		local el = now - start
		local pace = lengths > 0 and (clock(el / lengths) .. " /length") or "--:-- /length"
		status.Text = string.format("Lengths %d/%d%s%s%s%s", lengths, target, DOT, clock(el), DOT, pace)
		ctx.stats(string.format("%d/%d lengths%s%s", lengths, target, DOT, pace))
		RunService.Heartbeat:Wait()
	end
	ctx.intensity = nil
	local el = os.clock() - start
	ctx.put("lengths", lengths)
	if lengths > 0 then
		ctx.put("speed", math.floor(lengths / (el / 60) * 10 + 0.5) / 10)
		ctx.note(string.format("%d lengths in %s (%s each)", lengths, clock(el), clock(el / lengths)))
	end
	if bestLength then
		ctx.note("fastest length " .. clock(bestLength))
	end
	return 1
end

------------------------------------------------------------------------
-- Camera during station work
------------------------------------------------------------------------
local LOW = { bench = true, lie = true, lieup = true, longsit = true, sit = true, row = true, bike = true }
-- lifts and cardio read best from the side; bag work over the shoulder
local SIDE = { curl = true, deadlift = true, squat = true, pullup = true, run = true, rope = true, ladder = true, stretch = true }
-- does the segment a -> a + d pass through the box (cf, size)? (slab test in the box's space)
local function slab(pa, va, ha, t0, t1)
	if math.abs(va) < 1e-6 then
		if pa < -ha or pa > ha then
			return nil
		end
		return t0, t1
	end
	local ta, tb = (-ha - pa) / va, (ha - pa) / va
	if ta > tb then
		ta, tb = tb, ta
	end
	t0, t1 = math.max(t0, ta), math.min(t1, tb)
	if t0 > t1 then
		return nil
	end
	return t0, t1
end
local function segmentHitsBox(a, d, cf, size)
	local p = cf:PointToObjectSpace(a)
	local v = cf:VectorToObjectSpace(d)
	local t0, t1 = slab(p.X, v.X, size.X / 2, 0, 1)
	if t0 then
		t0, t1 = slab(p.Y, v.Y, size.Y / 2, t0, t1)
	end
	if t0 then
		t0, t1 = slab(p.Z, v.Z, size.Z / 2, t0, t1)
	end
	return t0 ~= nil
end

-- shifts a camera goal sideways so the subject (dist studs ahead) sits at camFrame.fx across the screen
local function frameShift(cam, goal, dist)
	local shift = 0.5 - camFrame.fx
	if math.abs(shift) < 0.01 then
		return goal
	end
	local vp = cam.ViewportSize
	local aspect = (vp.Y > 0) and (vp.X / vp.Y) or (16 / 9)
	local halfW = math.tan(math.rad(cam.FieldOfView) / 2) * aspect * dist
	return goal * CFrame.new(shift * 2 * halfW, 0, 0)
end

local function stationCamera(pose)
	local cam = workspace.CurrentCamera
	local _, _, root = State.char()
	if not root then
		return nil
	end
	cam.CameraType = Enum.CameraType.Scriptable
	local base = root.CFrame
	local baseFov = cam.FieldOfView
	camKick.baseFov = baseFov
	-- the station view only depends on the spot, the screen and the lens: it is worked out again only
	-- when one of those changes, and once the camera has settled on it nothing is written
	local goal, goalVp, goalFov, goalFx = nil, nil, nil, nil
	return RunService.RenderStepped:Connect(function(dt)
		cam = workspace.CurrentCamera
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Scriptable
		end
		local _, _, r = State.char()
		if not r then
			return
		end
		local vp, fov = cam.ViewportSize, cam.FieldOfView
		if not goal or vp ~= goalVp or fov ~= goalFov or camFrame.fx ~= goalFx then
			goalVp, goalFov, goalFx = vp, fov, camFrame.fx
			local p = base.Position
			local look, right = base.LookVector, base.RightVector
			-- the activity panel covers the bottom of the screen, so the camera aims a little low:
			-- that lifts the athlete into the clear upper part of the view (feet included)
			if LOW[pose] then
				goal = CFrame.lookAt(p + right * 7.5 + look * 1.5 + Vector3.new(0, 5, 0), p + look * 0.5 - Vector3.new(0, 1.4, 0))
			elseif SIDE[pose] then
				local lift = pose == "pullup" and 1.2 or 0
				goal = CFrame.lookAt(p + right * 10 + look * 2.5 + Vector3.new(0, 2.2 + lift, 0), p + look * 0.6 + Vector3.new(0, lift - 1.7, 0))
			else
				-- over the right shoulder, looking at the equipment
				goal = CFrame.lookAt(p + right * 3.8 - look * 6 + Vector3.new(0, 3.2, 0), p + look * 2.6 + Vector3.new(0, 0.1, 0))
			end
			goal = frameShift(cam, goal, (goal.Position - p).Magnitude)
		end
		local cur = cam.CFrame
		if cur ~= goal then
			local nxt = cur:Lerp(goal, math.clamp(dt * 6, 0, 1))
			-- (within a ten-thousandth of a stud: on it)
			if (nxt.Position - goal.Position).Magnitude < 1e-4 and nxt.LookVector:Dot(goal.LookVector) > 0.99999999 and nxt.UpVector:Dot(goal.UpVector) > 0.99999999 then
				nxt = goal
			end
			cam.CFrame = nxt
		end
		-- heavy shots kick the camera: a quick decaying shake plus a small FOV punch
		local el = os.clock() - camKick.t
		if el < 0.45 and camKick.amp > 0 then
			local k = camKick.amp * math.exp(-el * 9)
			cam.CFrame = cam.CFrame * CFrame.new(math.sin(el * 70) * 0.06 * k, math.sin(el * 55 + 1) * 0.05 * k, 0)
			cam.FieldOfView = baseFov - 1.5 * k * math.max(0, 1 - el * 4)
		elseif cam.FieldOfView ~= baseFov then
			cam.FieldOfView = baseFov
		end
	end)
end

-- the result: a front view of the athlete (the pump and the growth are what the screen is about), in the
-- clear part of the screen beside the docked panel, drifting slowly
local function revealCamera()
	local cam = workspace.CurrentCamera
	local _, _, root = State.char()
	if not root then
		return nil
	end
	cam.CameraType = Enum.CameraType.Scriptable
	local t0 = os.clock()
	-- the station's equipment can stand between the lens and the athlete (the heavy bag hangs right in
	-- front of him): on the first frame the camera swings round him to the first clear line of sight
	-- and keeps that angle. The gym's equipment visuals are client-built and CanQuery = false, so a ray
	-- does not see them: their models' bounding boxes are tested as well
	local swing
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local SWINGS = { 0, 0.9, -0.9, 1.6, -1.6, 2.4, -2.4 }
	local function blocked(a, d, boxes)
		if workspace:Raycast(a, d, rayParams) then
			return true
		end
		for _, b in ipairs(boxes) do
			if segmentHitsBox(a, d, b[1], b[2]) then
				return true
			end
		end
		return false
	end
	return RunService.RenderStepped:Connect(function(dt)
		cam = workspace.CurrentCamera
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Scriptable
		end
		local _, _, r = State.char()
		if not r then
			return
		end
		-- framed on the upper torso's own axes: standing, a front view; lying on a bench, from above
		local char = r.Parent
		local torso = char and char:FindFirstChild("UpperTorso")
		local cf = torso and torso.CFrame or (r.CFrame * CFrame.new(0, 1.1, 0))
		local look, right, up = cf.LookVector, cf.RightVector, cf.UpVector
		local chest = cf.Position - up * 0.2
		local drift = math.sin((os.clock() - t0) * 0.35) * 0.6
		local dist = 7.5
		if not swing then
			swing = 0
			rayParams.FilterDescendantsInstances = { char }
			local boxes = {}
			local localGym = workspace:FindFirstChild("LocalGym")
			for _, m in ipairs(localGym and localGym:GetChildren() or {}) do
				if m:IsA("Model") then
					local bcf, bsize = m:GetBoundingBox()
					-- near, and not a box he stands in (a platform under him would block every angle)
					local q = bcf:PointToObjectSpace(chest)
					local inside = math.abs(q.X) <= bsize.X / 2 and math.abs(q.Y) <= bsize.Y / 2 and math.abs(q.Z) <= bsize.Z / 2
					if not inside and (bcf.Position - chest).Magnitude < 16 + bsize.Magnitude / 2 then
						table.insert(boxes, { bcf, bsize })
					end
				end
			end
			for _, a in ipairs(SWINGS) do
				local off = CFrame.fromAxisAngle(Vector3.yAxis, a):VectorToWorldSpace(look * dist + right * 1.3 + up * 0.7)
				if not blocked(chest, off, boxes) then
					swing = a
					break
				end
			end
		end
		local off = CFrame.fromAxisAngle(Vector3.yAxis, swing):VectorToWorldSpace(look * dist + right * (1.3 + drift) + up * 0.7)
		local eye = chest + off
		local goal = frameShift(cam, CFrame.lookAt(eye, chest, up), dist)
		cam.CFrame = cam.CFrame:Lerp(goal, math.clamp(dt * 3, 0, 1))
	end)
end

------------------------------------------------------------------------
-- Results
------------------------------------------------------------------------
local STAT_NAMES = {
	punches = "Punches", maxPower = "Max power", handSpeed = "Hand speed", hitsPerMin = "Hits per minute",
	bestStreak = "Best streak", accuracy = "Accuracy", counters = "Counters", cleanCombos = "Clean combos",
	cleanFlows = "Clean flows", load = "Load", addedLoad = "Added load", goodReps = "Good reps", volume = "Volume",
	distance = "Distance", topSpeed = "Top speed", maxWatts = "Max watts", avgRpm = "Avg cadence", meters = "Distance",
	maxSpm = "Stroke rate", inZone = "Time in zone", stepsPerSec = "Foot speed", drills = "Drills completed",
	cleanJumps = "Clean jumps", doubleUnders = "Double unders", sync = "Breathing sync", waterLost = "Water cut",
	lengths = "Lengths", speed = "Average speed", cleanSlams = "Clean slams", twists = "Twists on the beat", plankSec = "Steady on the ball (s)", slips = "Slips", steps = "Steps",
	form = "Form", tempo = "Tempo", perfectCurls = "Perfect curls", strokes = "Strokes", calmBreaths = "Calm breaths",
	timeInRange = "Time in range", soreSpots = "Sore spots found", rebounds = "Rebounds slipped", footwork = "Footwork on the beat",
}
local STAT_UNITS = {
	maxPower = " lbs", handSpeed = " punches/s", accuracy = "%", load = " lbs", addedLoad = " lbs", volume = " lbs",
	distance = " mi", topSpeed = " mph", maxWatts = " W", avgRpm = " rpm", meters = " m", maxSpm = " spm", inZone = "%",
	stepsPerSec = " steps/s", sync = "%", waterLost = " lbs", form = "%", tempo = "%", timeInRange = " s", soreSpots = "%", footwork = "%",
}
local function statText(actId, key, v)
	local unit = STAT_UNITS[key] or ""
	if key == "speed" then
		unit = actId == "Swimming" and " lengths/min" or " mph"
	end
	return (STAT_NAMES[key] or key) .. " " .. fmtNum(v) .. unit
end

local function coachRemark(actId, grade)
	local special = Config.ActivityRemarks[actId]
	if special then
		if (grade == "S" or grade == "A") and special.hi and math.random() < 0.6 then
			return special.hi
		elseif (grade == "C" or grade == "D") and special.lo and math.random() < 0.6 then
			return special.lo
		end
	end
	local list = Config.GradeRemarks[grade] or Config.GradeRemarks.B
	return list[math.random(1, #list)]
end

-- the result's status chips: { text, color } (one colour per meaning: red = worked / pumped, orange =
-- sore or a warning, cyan = sweat, blue = veins, green = fat coming off)
local function statusChips(res)
	local r = res.result or {}
	local chips = {}
	if type(r.pump) == "table" and type(r.pump.parts) == "table" and #r.pump.parts > 0 then
		local names = {}
		for i, id in ipairs(r.pump.parts) do
			if i > 3 then
				break
			end
			table.insert(names, string.upper(BodyMap.Short(id)))
		end
		table.insert(chips, { string.format("PUMP %d%%  ·  %s", math.floor((tonumber(r.pump.level) or 0) * 100 + 0.5), table.concat(names, ", ")), T.red })
	end
	if type(r.sore) == "table" then
		for _, k in ipairs(Config.MuscleKeys) do
			local v = tonumber(r.sore[k])
			if v and v >= 0.3 then
				table.insert(chips, { string.format("SORE %s %d%%", string.upper(Config.MuscleNames[k] or k), math.floor(v * 100 + 0.5)), T.orange })
			end
		end
	end
	if type(r.sweat) == "number" and r.sweat > 0 then
		table.insert(chips, { string.format("SWEAT %d%%", math.floor(r.sweat * 100 + 0.5)), T.cyan })
	end
	if type(r.vasc) == "number" and r.vasc > 0.005 then
		table.insert(chips, { string.format("VEINS +%.2f", r.vasc), T.blue })
	end
	if r.fat and math.abs(r.fat) > 0.001 then
		table.insert(chips, { string.format("BODY FAT %+.2f%%", r.fat), r.fat < 0 and T.green or T.orange })
	end
	if r.fatigue then
		table.insert(chips, { string.format("FATIGUE %d%%", math.floor(r.fatigue)), r.fatigue > 70 and T.red or (r.fatigue > 40 and T.orange or T.sub) })
	end
	return chips
end

-- a wrapping row of chips (auto-sized pills, new line when the width runs out)
local function chipFlow(parent, list, order, width)
	local rows = UI.Frame(parent, { Name = "Chips", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order })
	UI.List(rows, 6)
	local row, used, n = nil, 0, 0
	for _, c in ipairs(list) do
		local est = #c[1] * 8.5 + 26
		if not row or used + est > width then
			n += 1
			row = UI.Frame(rows, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = n })
			UI.List(row, 6, true)
			used = 0
		end
		used += est + 6
		UI.Chip(row, c[1], c[2], { h = 28, TextSize = 14, solid = c[3] == true, textColor = c[3] and T.ink or nil })
	end
	return rows
end

-- the +XP toast (top centre, above every window): the number counts up over a second with an
-- ease-out so the last digits settle slowly, the level bar fills behind it, a level-up flashes gold
-- the report's gains go in the band above it (a row of chips, the +XP card top-right) on a phone and
-- wherever a popup column beside the growth card would run into the panel (a 1024 tablet at 0.9)
local function gainsInBand(canvas)
	return canvas.Y < 640 or (canvas.X - 16 - PANEL_W) < (24 + SIDE_W + 16 + 280 + 8)
end

local function xpToast(r0)
	local xp = tonumber(r0.xp)
	if not xp or xp <= 0 then
		return nil
	end
	local lv = type(r0.level) == "table" and r0.level or nil
	-- in the band: a smaller card tucked into the top-right corner, where the gains strip (top-left)
	-- and the panel are not
	local small = gainsInBand(UI.CanvasSize(State.gui))
	local numSize = small and 26 or 34
	local shown = small and UDim2.new(1, -24, 0, 8) or UDim2.new(0.5, 0, 0, 18)
	local hidden = small and UDim2.new(1, -24, 0, -96) or UDim2.new(0.5, 0, 0, -96)
	local card = UI.Frame(State.toastRoot, { Name = "XPToast", AnchorPoint = small and Vector2.new(1, 0) or Vector2.new(0.5, 0), Position = hidden, Size = small and UDim2.fromOffset(220, 56) or UDim2.fromOffset(300, 84), BackgroundColor3 = T.bg, ZIndex = 60 })
	card:SetAttribute("XP", xp)
	UI.Glass(card, { transparency = 0.04, radius = UI.R.lg })
	UI.Stroke(card, T.gold, 1.5, 0.3)
	local num = UI.Text(card, "+0 XP", { Name = "Number", Face = "number", TextSize = numSize, TextColor3 = T.gold, Position = UDim2.fromOffset(16, small and 3 or 6), Size = UDim2.new(1, -32, 0, small and 30 or 40), AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, ZIndex = 61 })
	-- (the band's small card says it shorter, and grows to its caption at the readability floor)
	local caption = lv and string.format(small and "LEVEL %d  ·  %d / %d XP" or "TRAINING XP  ·  LEVEL %d  ·  %d / %d", lv.level or 1, lv.into or 0, lv.need or 1) or "TRAINING XP"
	local upText = lv and string.format(small and "LEVEL UP!  ·  LEVEL %d" or "LEVEL UP!  ·  TRAINING LEVEL %d", lv.level or 1) or caption
	local capSize = small and 10 or 12
	local px = math.max(capSize, UI.TextFloor(UI.ScaleOf(card)))
	local capH = math.max(14, math.ceil(px * 1.2))
	if small then
		card.Size = UDim2.fromOffset(math.max(220, math.max(capsW(caption, px), capsW(upText, px)) + 36), 42 + capH)
	end
	local sub = UI.Text(card, caption, { Name = "Caption", Font = T.semi, TextSize = capSize, TextColor3 = T.sub, Position = UDim2.fromOffset(16, small and 32 or 48), Size = UDim2.new(1, -32, 0, capH), AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, ZIndex = 61 })
	local barBg = UI.Frame(card, { Position = UDim2.new(0, 16, 1, small and -8 or -12), Size = UDim2.new(1, -32, 0, small and 3 or 4), BackgroundColor3 = T.ink, ZIndex = 61 })
	UI.Corner(barBg, 2)
	local fill = UI.Frame(barBg, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.gold, ZIndex = 62 })
	UI.Corner(fill, 2)
	UI.Tween(card, { Position = shown }, UI.Motion.base)
	-- the count-up: 1.1 s, cubic ease-out
	local from = lv and math.max(0, (lv.into or 0) - xp) or 0
	local need = lv and math.max(1, lv.need or 1) or 1
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not card.Parent then
			conn:Disconnect()
			return
		end
		local k = math.clamp((os.clock() - t0) / 1.1, 0, 1)
		local e = 1 - (1 - k) ^ 3
		num.Text = string.format("+%d XP", math.floor(xp * e + 0.5))
		if lv then
			-- a level-up wraps the bar: it runs to full, then fills again from zero
			local into = from + xp * e
			if r0.levelUp and into >= need then
				into = lv.into or 0
				fill.Size = UDim2.fromScale(math.clamp(into / need, 0, 1), 1)
			else
				fill.Size = UDim2.fromScale(math.clamp(into / need, 0, 1), 1)
			end
		end
		if k >= 1 then
			conn:Disconnect()
			if r0.levelUp and lv then
				sub.Text = upText
				sub.TextColor3 = T.gold
				num.TextSize = numSize + 6
				TweenService:Create(num, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = numSize }):Play()
			else
				TweenService:Create(num, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = numSize + 4 }):Play()
				task.delay(0.25, function()
					if num.Parent then
						UI.Tween(num, { TextSize = numSize }, UI.Motion.base)
					end
				end)
			end
			pcall(function()
				local snd = Instance.new("Sound")
				snd.SoundId = Config.BuiltinSounds and Config.BuiltinSounds.ping or "rbxasset://sounds/electronicpingshort.wav"
				snd.Volume = 0.35
				snd.Parent = card
				snd:Play()
			end)
		end
	end)
	task.delay(4.6, function()
		if card.Parent then
			UI.Tween(card, { Position = hidden }, UI.Motion.base)
			task.wait(0.35)
			card:Destroy()
		end
	end)
	return card
end

-- the gain popups (top left, where nothing else sits during a session): one card per stat that rose
-- (old -> new) and per muscle part that grew (+gain, level), sliding in one after another and
-- fading after a while; the result panel keeps the full lists
local POPUP_MAX = 12
local function gainPopups(ctx, r0, grown)
	local items = {}
	for _, k in ipairs(Config.StatKeys) do
		local g = tonumber(type(r0.gains) == "table" and r0.gains[k])
		if g and g > 0.001 then
			local old = ctx.stats0 and ctx.stats0[k] or 0
			table.insert(items, { kind = "stat", key = k, label = string.upper(Config.StatNames[k] or k), old = old, new = old + g, g = g, color = T.green })
		end
	end
	-- a muscle: the level now and the gain now (the report adds tonight's share; BodyMap.GrowthSplit)
	for _, e in ipairs(grown) do
		local before = ctx.body0 and ctx.body0[e.id] or 0
		local now, tonight = BodyMap.GrowthSplit(e.g)
		table.insert(items, { kind = "muscle", key = e.id, label = string.upper(BodyMap.Short(e.id)), old = before, new = before + now, g = now, tonight = tonight, color = T.orange,
			group = string.upper(Config.MuscleNames[Config.MusclePartGroup[e.id] or ""] or "") })
	end
	if #items == 0 then
		return nil
	end
	-- wide screens: a column beside the body map card (which grows tall on the report), else in the
	-- top-left corner. Phones (the compact test of ctx.layout) have no room for a column: the report
	-- fills the screen below a thin band, so the gains become one row of chips in that band, left of
	-- the +XP toast, as many as fit in the width (stats first; the report keeps every one)
	local canvas = UI.CanvasSize(State.gui)
	local compact = gainsInBand(canvas)
	-- narrower chips on the smallest phones (667 wide: three fit beside the toast instead of two)
	local CHIP_W, GAP = (compact and canvas.X < 760) and 118 or 136, 6
	local NUMS_W = 72 + 84 + 6 -- a column row: the gain (72 from the right), the numbers (84), a gap
	local col, host, rowSize, shown, labelPx, labelW
	if compact then
		-- a strip this short shows the biggest stat and the biggest muscle first, then the rest in turns
		local stats, muscles, mixed = {}, {}, {}
		for _, it in ipairs(items) do
			table.insert(it.kind == "stat" and stats or muscles, it)
		end
		for i = 1, math.max(#stats, #muscles) do
			if stats[i] then
				table.insert(mixed, stats[i])
			end
			if muscles[i] then
				table.insert(mixed, muscles[i])
			end
		end
		items = mixed
		local stripW = math.max(CHIP_W, math.floor(canvas.X - 24 - 16 - 220 - 24))
		-- a chip is as wide as its name at the text floor ("KNOCKOUT POWER" whole), as many as fit; the
		-- last slot goes to the "+N more" note when not everything fits
		local px = math.max(11, UI.TextFloor(UI.ScaleOf(State.gui)))
		local moreW = capsW("+99 more in", px) + 6
		local used = 0
		shown = 0
		for i, it in ipairs(items) do
			it.chipW = math.min(stripW, math.max(CHIP_W, capsW(it.label, px) + 16))
			if i > 1 and used + it.chipW + (i < #items and moreW + GAP or 0) > stripW then
				break
			end
			used += it.chipW + GAP
			shown = i
		end
		col = UI.Frame(State.gui, { Name = "Gains", Position = UDim2.fromOffset(24, 8), Size = UDim2.fromOffset(stripW, 52), BackgroundTransparency = 1, ZIndex = 20 })
		UI.Kicker(col, "SESSION GAINS", T.green, { Size = UDim2.new(1, 0, 0, 16) })
		host = UI.Frame(col, { Name = "Row", Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, ZIndex = 20 })
		UI.List(host, GAP, true)
		rowSize = UDim2.fromOffset(moreW, 32)
	else
		local x = (ctx.side and ctx.side.Visible) and (24 + SIDE_W + 16) or 24
		-- the column is wide enough for the longest name at the text floor beside its numbers
		labelPx = math.max(13, UI.TextFloor(UI.ScaleOf(State.gui)))
		local colW = 300
		for i = 1, math.min(#items, POPUP_MAX) do
			colW = math.max(colW, capsW(items[i].label, labelPx) + 12 + NUMS_W)
		end
		labelW = colW - 12 - NUMS_W
		col = UI.Frame(State.gui, { Name = "Gains", Position = UDim2.fromOffset(x, 24), Size = UDim2.fromOffset(colW, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 20 })
		UI.List(col, 6)
		UI.Kicker(col, "SESSION GAINS", T.green, { order = 0 })
		host = col
		rowSize = UDim2.new(1, 0, 0, 36)
		shown = math.min(#items, POPUP_MAX)
	end
	ctx.onDestroy(function()
		col:Destroy()
	end)
	for i = 1, shown do
		local it = items[i]
		task.delay(0.14 * i, function()
			if not host.Parent then
				return
			end
			local row = UI.Frame(host, { Name = it.kind == "stat" and "StatGain" or "MuscleGain", BackgroundTransparency = 1, Size = compact and UDim2.fromOffset(it.chipW, 32) or rowSize, LayoutOrder = i, ZIndex = 20 })
			row:SetAttribute("Key", it.key)
			row:SetAttribute("Old", math.floor(it.old * 100 + 0.5) / 100)
			row:SetAttribute("New", math.floor(it.new * 100 + 0.5) / 100)
			row:SetAttribute("Gain", math.floor(it.g * 100 + 0.5) / 100)
			if it.tonight then
				row:SetAttribute("Tonight", math.floor(it.tonight * 100 + 0.5) / 100)
			end
			local card = UI.Frame(row, { Name = "Card", Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(-40, 0), BackgroundColor3 = T.bg, BackgroundTransparency = 1, ZIndex = 20 })
			UI.Glass(card, { transparency = 0.08, radius = compact and UI.R.sm or UI.R.md })
			card.BackgroundTransparency = 1
			UI.Frame(card, { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(0, 3, 1, -16), BackgroundColor3 = it.color, ZIndex = 21 })
			local label = it.label
			-- the muscle's group beside it where both fit whole ("PECS chest")
			if it.group and it.group ~= "" and not compact and capsW(it.label .. " " .. it.group, labelPx) <= labelW then
				label = string.format('%s <font color="#%s" size="11">%s</font>', it.label, T.sub:ToHex(), it.group)
			end
			local numbers = string.format("%.1f > %.1f", it.old, it.new)
			local gain = string.format("+%.2f", it.g)
			if compact then
				-- a chip: the name over the numbers, the gain in the corner
				UI.Text(card, label, { Font = T.semi, TextSize = 11, Position = UDim2.fromOffset(9, 2), Size = UDim2.new(1, -14, 0, 13), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false,
					TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 21 })
				UI.Text(card, numbers, { Face = "number", TextSize = 12, Position = UDim2.fromOffset(9, 16), Size = UDim2.new(1, -64, 0, 14), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, ZIndex = 21 })
				UI.Text(card, gain, { Face = "number", TextSize = 12, TextColor3 = it.color, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 16), Size = UDim2.fromOffset(52, 14), AutomaticSize = Enum.AutomaticSize.None,
					TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false, ZIndex = 21 })
			else
				UI.Text(card, label, { Font = T.semi, TextSize = 13, RichText = true, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -(12 + NUMS_W), 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false,
					TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 21 })
				UI.Text(card, numbers, { Face = "number", TextSize = 15, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -72, 0, 0), Size = UDim2.new(0, 84, 1, 0), AutomaticSize = Enum.AutomaticSize.None,
					TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false, ZIndex = 21 })
				UI.Text(card, gain, { Face = "number", TextSize = 15, TextColor3 = it.color, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.fromOffset(60, 36), AutomaticSize = Enum.AutomaticSize.None,
					TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false, ZIndex = 21 })
			end
			UI.Tween(card, { Position = UDim2.fromOffset(0, 0), BackgroundTransparency = 0.08 }, UI.Motion.base)
		end)
	end
	if #items > shown then
		task.delay(0.14 * (shown + 1), function()
			if host.Parent then
				UI.Text(host, string.format(compact and "+%d more in\nthe report" or "+ %d more in the report", #items - shown), { Font = T.semi, TextSize = compact and 11 or 12, TextColor3 = T.sub,
					Size = compact and rowSize or UDim2.new(1, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = compact, LayoutOrder = shown + 1, ZIndex = 20 })
			end
		end)
	end
	task.delay(10, function()
		if col.Parent then
			for _, r in ipairs(host:GetChildren()) do
				local c = r:FindFirstChild("Card")
				if c then
					UI.Tween(c, { Position = UDim2.fromOffset(-40, 0), BackgroundTransparency = 1 }, UI.Motion.base)
				end
			end
			task.wait(0.4)
			col:Destroy()
		end
	end)
	return col
end

-- a bout (or sparring) has the player: the report and the reveal camera give way to the ring
-- the coach's report card (server Training's result.report, plus the goals Record completed): the
-- multipliers as chips, what went well / what to fix, mastery and overload, goals done, the camp, a tip
local function reportSection(list, nextOrder, res, listW, compact)
	local r0 = type(res.result) == "table" and res.result or {}
	local rep = type(r0.report) == "table" and r0.report or nil
	if not rep then
		return
	end
	UI.Kicker(list, "COACH'S REPORT", T.gold, { order = nextOrder(), TextSize = 13, icon = "whistle", Name = "ReportKicker" })
	local chips = {}
	for _, c in ipairs(type(rep.chips) == "table" and rep.chips or {}) do
		table.insert(chips, { tostring(c.text), c.good and T.green or T.orange })
	end
	if #chips > 0 then
		local f = chipFlow(list, chips, nextOrder(), listW)
		f.Name = "ReportChips"
	end
	local function line(icon, color, text, name)
		local row = UI.Frame(list, { Name = name, BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder() })
		UI.Icon(row, icon, 15, color, { Position = UDim2.fromOffset(0, 2) })
		UI.Text(row, text, { Font = T.semi, TextSize = 14, TextColor3 = T.text, Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -22, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	end
	for _, t in ipairs(type(rep.well) == "table" and rep.well or {}) do
		line("check", T.green, tostring(t), "Well")
	end
	for _, t in ipairs(type(rep.fix) == "table" and rep.fix or {}) do
		line("warning", T.orange, tostring(t), "Fix")
	end
	-- mastery: the level, the bar to the next one, the overload the drill is at
	local m = rep.mastery
	if type(m) == "table" then
		local row = UI.Frame(list, { Name = "Mastery", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 22), LayoutOrder = nextOrder() })
		local ov = type(rep.overload) == "table" and rep.overload or nil
		local label = string.format("MASTERY %s%s", string.upper(tostring(m.name or "")), ov and ov.to > 0 and string.format("  ·  OVERLOAD %d", ov.to) or "")
		UI.Text(row, label, { Font = T.semi, TextSize = 13, TextColor3 = m.up and T.gold or T.text, Size = UDim2.new(0.5, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		local need = tonumber(m.need) or 0
		local _, set = UI.Bar(row, { Position = UDim2.new(0.5, 6, 0.5, -4), Size = UDim2.new(0.5, -76, 0, 8) }, T.gold)
		set(need > 0 and math.clamp((tonumber(m.into) or 0) / need, 0, 1) or 1)
		UI.Text(row, string.format("+%d", tonumber(m.gained) or 0), { Face = "number", TextSize = 15, TextColor3 = T.gold, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(62, 22),
			AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
		if m.up and m.perk then
			line("medal", T.gold, "NEW PERK  " .. tostring(m.perk), "Perk")
		end
	end
	-- goals done this session (the session's own, and the personal best's from Record)
	local goals = {}
	for _, src in ipairs({ rep.goals, type(res.record) == "table" and res.record.goals or nil }) do
		for _, g in ipairs(type(src) == "table" and src or {}) do
			table.insert(goals, { string.format("%s %s  +$%s", g.sweep and "SWEEP" or (g.weekly and "WEEKLY" or "GOAL"), tostring(g.text or ""), tostring(g.money or 0)), T.gold, true })
		end
	end
	if #goals > 0 then
		local f = chipFlow(list, goals, nextOrder(), listW)
		f.Name = "GoalChips"
	end
	if type(rep.camp) == "table" then
		local c = rep.camp
		local l = UI.Text(list, string.format("FIGHT CAMP  ·  DAY %d/%d  ·  %s  ·  READINESS %d (%s)", tonumber(c.day) or 1, tonumber(c.total) or 1, string.upper(tostring(c.phase or "")), tonumber(c.readiness) or 0, tostring(c.label or "")),
			{ Font = T.semi, TextSize = 13, TextColor3 = T.red, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder() })
		l.Name = "CampLine"
	end
	if type(rep.tip) == "table" and rep.tip.text and not compact then
		local l = UI.Text(list, string.format('<font color="#%s">%s:</font> %s', T.gold:ToHex(), string.upper(tostring(rep.tip.coach or "COACH")), tostring(rep.tip.text)),
			{ RichText = true, TextSize = 13, TextColor3 = T.sub, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder() })
		l.Name = "ReportTip"
	end
end

-- the soreness after the session on a small figure (orange = sore), beside its numbers
local function sorenessMap(list, nextOrder, sore)
	local any = false
	for _, v in pairs(type(sore) == "table" and sore or {}) do
		if (tonumber(v) or 0) >= 0.1 then
			any = true
		end
	end
	if not any or not BodyMap.new then
		return
	end
	local row = UI.Frame(list, { Name = "SoreMap", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 120), LayoutOrder = nextOrder() })
	local okMap, map = pcall(BodyMap.new, row, { Size = UDim2.fromOffset(150, 118), labels = false, glow = false })
	if okMap and map and map.SetSoreness then
		map:SetSoreness(sore)
	end
	local lines = {}
	for _, k in ipairs(Config.MuscleKeys) do
		local v = tonumber(sore[k])
		if v and v >= 0.1 then
			table.insert(lines, string.format("%s %d%%", string.upper(Config.MuscleNames[k] or k), math.floor(v * 100 + 0.5)))
		end
	end
	UI.Text(row, "SORENESS\n" .. table.concat(lines, "\n"), { Font = T.semi, TextSize = 13, TextColor3 = T.orange, Position = UDim2.fromOffset(160, 0), Size = UDim2.new(1, -160, 1, 0),
		AutomaticSize = Enum.AutomaticSize.None, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd })
end

local function inRing()
	local b = State.busy()
	return State.inFight() or b == "fight" or b == "spar" or b == "pvp"
end

local function showResult(ctx, res, quality)
	ctx.mode = "done" -- freeze the heart-rate readout
	ctx.resting = false
	ctx.handler = nil
	ctx.roundText, ctx.statsText = nil, nil
	ctx.refreshLive()
	fullPanel(ctx)
	for _, c in ipairs(ctx.panel:GetChildren()) do
		if c.Name == "Overlay" then
			c:Destroy()
		end
	end
	UI.Clear(ctx.inputBar)
	UI.Clear(ctx.stage)
	ctx.flash.Text = ""
	local rec = type(res.record) == "table" and res.record or {}
	local grade = type(rec.grade) == "string" and rec.grade or Config.GradeFor(quality)
	local gcol = gradeColor(grade)
	local r0 = res.result or {}
	ctx.title.Text = ctx.act.name:upper()
	ctx.header.Text = "SESSION COMPLETE" .. DOT .. "GRADE " .. grade
	ctx.header.TextColor3 = gcol
	ctx.setProgress(1)
	-- the strip shows the graded session (the server's quality)
	ctx.tiles.quality.val.Text = string.format("%d%%", Config.QualityPct(quality))
	ctx.tiles.quality.val.TextColor3 = gcol
	ctx.tiles.quality.fill.BackgroundColor3 = gcol
	ctx.tiles.quality.fill.Size = UDim2.fromScale(math.clamp(Config.QualityPct(quality) / 100, 0, 1), 1)
	ctx.tiles.time.val.Text = clock(os.clock() - ctx.t0)
	local parts = { string.format("Session quality %d%%", Config.QualityPct(quality)) }
	if type(rec.best) == "number" and rec.best > 0 then
		table.insert(parts, string.format("Personal best %d%%", Config.QualityPct(rec.best)))
	end
	if type(rec.sessions) == "number" and rec.sessions > 0 then
		table.insert(parts, string.format("%d session%s", rec.sessions, rec.sessions == 1 and "" or "s"))
	end
	-- the record line takes the drill instructions' place (and keeps it when the device changes: the
	-- drill's hint would be bound again by ctx.bind below)
	ctx.infoRaw = nil
	local recText = table.concat(parts, DOT)
	UI.BindHint(ctx.info, function()
		return recText
	end)
	-- the report gets room: on a wide screen the panel grows upward (the metrics strip rides on top).
	-- ctx.layout calls this again when the screen changes (a window resized, a phone turned), so the
	-- panel never runs off the top of a smaller screen
	function ctx.sizeResult()
		local cv = UI.CanvasSize(ctx.panel)
		local small = cv.Y < 640
		-- (a phone: up to the thin band the SESSION GAINS strip and the +XP card use)
		local h = small and math.floor(math.clamp(cv.Y - 88, math.min(PANEL_H, cv.Y - 16), 560)) or math.floor(math.clamp(cv.Y - 230, PANEL_H, 560))
		if ctx.panelMax then
			ctx.panelMax.MaxSize = Vector2.new(PANEL_W, h)
		end
		ctx.panel.Size = UDim2.new(0.96, 0, 0, h)
		-- a phone: the record line keeps to one line, the SESSION COMPLETE header moves up under it and
		-- the (full) progress bar goes, so the list shows a growth row without scrolling
		local top = small and math.min(ctx.stageY, 80) or ctx.stageY
		ctx.info.Size = UDim2.new(1, ctx.quitW or -32, 0, small and 22 or 30 + (ctx.topExtra or 0))
		ctx.header.Position = UDim2.fromOffset(16, small and 60 or 66 + (ctx.topExtra or 0))
		ctx.header.Size = UDim2.new(1, small and (ctx.quitW or -32) or -32, 0, 16)
		if ctx.progBg then
			ctx.progBg.Visible = not small
		end
		ctx.stage.Position = UDim2.new(0, 14, 0, top)
		ctx.stage.Size = UDim2.new(1, -28, 0, h - top - ctx.cellH - 18)
		ctx.inputBar.Position = UDim2.new(0, 14, 0, h - ctx.cellH - 10)
		return h, small, cv
	end
	local H, compact, canvas = ctx.sizeResult()
	ctx.stage.BackgroundTransparency = 1
	local list = UI.Scroll(ctx.stage, { Position = UDim2.fromOffset(0, 0), Size = UDim2.fromScale(1, 1) })
	UI.List(list, compact and 4 or 8)
	local listW = math.min(PANEL_W, canvas.X * 0.96) - 28 - 16
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end
	local grown = {}
	if type(r0.parts) == "table" then
		for id, g in pairs(r0.parts) do
			g = tonumber(g)
			if g and g > 0.005 then
				table.insert(grown, { id = id, g = g })
			end
		end
		table.sort(grown, function(a, b)
			return a.g > b.g
		end)
	end
	-- 1. the grade, the record and the coach (a phone without the growth card beside the panel: the
	-- growth body map sits between the grade and the coach)
	-- (a phone: a shorter block, so the first growth rows show under it)
	local topH = compact and 80 or 96
	local top = UI.Frame(list, { Name = "Top", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, topH), LayoutOrder = nextOrder() })
	local topMapW = (#grown > 0 and not (ctx.side and ctx.side.Visible)) and 104 or 0
	if topMapW > 0 then
		local okMap, gmap = pcall(BodyMap.new, top, { Size = UDim2.fromOffset(topMapW - 8, topH), Position = UDim2.fromOffset(104, 0), labels = false, glow = false })
		if okMap and gmap then
			gmap.frame.Name = "GrowthMap"
			gmap:SetGrowth(r0.parts, T.green)
			gmap:Pulse(2)
		else
			topMapW = 0
		end
	end
	local badge = UI.Frame(top, { Name = "Grade", Size = UDim2.fromOffset(92, topH), BackgroundColor3 = UI.Shade(gcol, -0.72) })
	UI.Corner(badge, 10)
	UI.Stroke(badge, gcol, 2, 0.1)
	UI.Gradient(badge, { Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150) }, 90)
	local letter = UI.Text(badge, grade, { Face = "display", TextSize = 30, TextColor3 = gcol, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, topH - 26), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	TweenService:Create(letter, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = compact and 54 or 64 }):Play()
	UI.Text(badge, string.format("%d%%", Config.QualityPct(quality)), { Face = "number", TextSize = 16, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 1, -24), Size = UDim2.new(1, 0, 0, 20), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	local right = UI.Frame(top, { BackgroundTransparency = 1, Position = UDim2.fromOffset(104 + topMapW, 0), Size = UDim2.new(1, -(104 + topMapW), 1, 0) })
	UI.List(right, 6)
	local headline, hcol
	if rec.newBest then
		headline, hcol = string.format("NEW PERSONAL BEST!   (was %d%%)", Config.QualityPct(rec.prevBest or 0)), T.gold
	elseif rec.first then
		headline, hcol = "FIRST SESSION LOGGED - the score to beat", T.gold
	elseif rec.uncounted then
		headline, hcol = "Too quick to count for your records", T.orange
	end
	if headline then
		UI.Text(right, headline, { Face = "displayMed", TextSize = 18, TextColor3 = hcol, Size = UDim2.new(1, 0, 0, 22), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 1 })
	end
	local quote = UI.Frame(right, { Name = "Coach", BackgroundColor3 = T.panel2, BackgroundTransparency = 0.35, Size = UDim2.new(1, 0, 0, headline and topH - 34 or topH - 4), LayoutOrder = 2 })
	UI.Corner(quote, UI.R.md)
	UI.Frame(quote, { Size = UDim2.new(0, 3, 1, -12), Position = UDim2.fromOffset(0, 6), BackgroundColor3 = gcol })
	UI.Text(quote, string.format('"%s"  <font color="#%s">- COACH</font>', coachRemark(ctx.act.id, grade), T.sub:ToHex()), { RichText = true, Font = T.semi, TextSize = 14, Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -24, 1, -12),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd })
	-- 1b. the coach's report card
	local okRep, errRep = pcall(reportSection, list, nextOrder, res, listW, compact)
	if not okRep then
		warn("[Activities] report:", errRep)
	end
	-- 2. muscle growth: every part that grew - the level before (its colour), the growth now (green),
	-- tonight's share once you sleep (pale green), your frame's potential (gold tick); in numbers the
	-- gain now, tonight's and the level now (the one the Muscle screen and the Body tab show)
	if #grown > 0 then
		UI.Kicker(list, "MUSCLE GROWTH", T.green, { order = nextOrder(), TextSize = 13 })
		local cap = ctx.cap or 100
		BodyMap.GrowthColumns(list, nextOrder(), UDim2.new(1, -8, 0, 16))
		-- every part that grew (the list scrolls): the name, its group, the bar and the numbers
		for _, e in ipairs(grown) do
			local before = ctx.body0 and ctx.body0[e.id] or 0
			local now, tonight = BodyMap.GrowthSplit(e.g)
			local row = UI.Frame(list, { Name = "Grow", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 24), LayoutOrder = nextOrder() })
			row:SetAttribute("Part", e.id)
			row:SetAttribute("Gain", math.floor(e.g * 100 + 0.5) / 100)
			row:SetAttribute("Now", math.floor(now * 100 + 0.5) / 100)
			row:SetAttribute("Tonight", math.floor(tonight * 100 + 0.5) / 100)
			row:SetAttribute("Level", math.floor((before + now) * 100 + 0.5) / 100)
			local grp = Config.MuscleNames[Config.MusclePartGroup[e.id] or ""] or ""
			UI.Text(row, string.upper(BodyMap.Short(e.id)) .. (grp ~= "" and string.format('  <font color="#%s" size="11">%s</font>', T.sub:ToHex(), string.upper(grp)) or ""),
				{ Font = T.semi, TextSize = 14, RichText = true, Size = UDim2.new(0.3, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
			UI.LevelBar(row, { Position = UDim2.new(0.3, 6, 0.5, -5), Size = UDim2.new(0.7, -6 - BodyMap.GROW_COLS_W, 0, 10) },
				{ gain = { before, before + now }, pending = before + e.g, cap = cap, color = BodyMap.DevColor(before / cap) })
			BodyMap.GrowthNumbers(row, now, tonight, before + now)
		end
		UI.Text(list, string.format("Green grew now (LEVEL is where the muscle stands now); the pale part grows tonight if you sleep and eat well. Gold tick: your frame's potential (%d).", math.floor(cap + 0.5)),
			{ TextSize = 13, TextColor3 = T.sub, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder() })
	end
	-- 3. stat increases: every stat that rose, old -> new (the popups say the same; this stays)
	local statRows = {}
	if type(r0.gains) == "table" then
		for _, k in ipairs(Config.StatKeys) do
			local g = tonumber(r0.gains[k])
			if g and g > 0.001 then
				table.insert(statRows, { key = k, g = g, old = ctx.stats0 and ctx.stats0[k] or 0 })
			end
		end
	end
	if #statRows > 0 then
		UI.Kicker(list, "STAT INCREASES", T.green, { order = nextOrder(), TextSize = 13 })
		for _, e in ipairs(statRows) do
			local row = UI.Frame(list, { Name = "StatRow", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 22), LayoutOrder = nextOrder() })
			row:SetAttribute("Stat", e.key)
			UI.Text(row, string.upper(Config.StatNames[e.key] or e.key), { Font = T.semi, TextSize = 14, Size = UDim2.new(0, 150, 1, 0), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
			UI.LevelBar(row, { Position = UDim2.new(0, 156, 0.5, -4), Size = UDim2.new(1, -156 - 214, 0, 8) }, { gain = { e.old, e.old + e.g }, color = T.line })
			UI.Text(row, string.format("%.1f > %.1f", e.old, e.old + e.g), { Face = "number", TextSize = 16, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -66, 0, 0), Size = UDim2.fromOffset(140, 22),
				AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
			UI.Text(row, string.format("+%.2f", e.g), { Face = "number", TextSize = 16, TextColor3 = T.green, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(60, 22),
				AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
		end
	end
	local statChips = {}
	if type(rec.newStats) == "table" and type(rec.bests) == "table" then
		for _, key in ipairs(rec.newStats) do
			local v = rec.bests[key]
			if type(v) == "number" then
				table.insert(statChips, { "NEW BEST: " .. string.upper(statText(ctx.act.id, key, v)), T.gold })
			end
		end
	end
	if #statChips > 0 then
		UI.Kicker(list, "RECORDS", T.gold, { order = nextOrder(), TextSize = 13 })
		chipFlow(list, statChips, nextOrder(), listW)
	end
	-- the toasts and popups: +XP counting up, every stat and muscle that rose
	pcall(xpToast, r0)
	pcall(gainPopups, ctx, r0, grown)
	-- 4. the body: pump, soreness, sweat, veins, fat, fatigue
	local sc = statusChips(res)
	if #sc > 0 then
		UI.Kicker(list, "YOUR BODY", T.red, { order = nextOrder(), TextSize = 13 })
		chipFlow(list, sc, nextOrder(), listW)
	end
	pcall(sorenessMap, list, nextOrder, r0.sore)
	-- 5. the session in numbers, then notes (injuries in red)
	local summary = table.clone(ctx.lines)
	table.insert(summary, ctx.recovery and string.format("HR settled at %d BPM", math.floor(ctx.hr + 0.5)) or string.format("HR peak %d BPM", math.floor(ctx.hrPeak + 0.5)))
	table.insert(summary, string.format("%d kcal", math.floor(ctx.kcal + 0.5)))
	UI.Text(list, table.concat(summary, DOT), { Font = T.semi, TextSize = 14, TextColor3 = Color3.fromRGB(150, 210, 255), Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder() })
	for _, n in ipairs(r0.notes or {}) do
		UI.Text(list, n, { Font = T.semi, TextSize = 14, TextColor3 = n:find("INJURY") and T.red or T.sub, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder() })
	end
	-- the side card turns into the growth map: bigger, every part that grew lit and named
	if ctx.side and ctx.sideCaption then
		if #grown > 0 then
			ctx.sideCaption.Text = "GROWTH THIS SESSION"
			ctx.sideCaption.TextColor3 = T.green
			if ctx.sideTick then
				ctx.sideTick.BackgroundColor3 = T.green
			end
			-- a bigger figure for the report (the card grows with the panel on a wide screen)
			if not compact then
				ctx.side.Size = UDim2.fromOffset(SIDE_W, H)
				if ctx.map then
					ctx.map.frame:Destroy()
				end
				-- the names list: three lines, five when more than two parts grew (whole names with
				-- their gains take a line or two each)
				local listH = #grown > 2 and 78 or 50
				local okMap, map = pcall(BodyMap.new, ctx.side, { Size = UDim2.fromOffset(SIDE_W - 28, math.max(176, H - 120 - listH)), Position = UDim2.fromOffset(14, 30) })
				ctx.map = okMap and map or nil
				ctx.sideList.Position = UDim2.new(0, 14, 1, -(78 + listH))
				ctx.sideList.Size = UDim2.new(1, -28, 0, listH)
			end
			if ctx.map then
				ctx.map:SetGrowth(r0.parts, T.green)
				ctx.map:Pulse(2)
			end
			-- the names under the figure carry their gains (exactly which muscles grew, and by how much:
			-- the gain now, as everywhere else; tonight's share is in the report)
			local names = {}
			for _, e in ipairs(grown) do
				table.insert(names, { text = string.format("%s +%.2f", string.upper(BodyMap.Short(e.id)), (BodyMap.GrowthSplit(e.g))) })
			end
			UI.Clear(ctx.sideList)
			UI.Text(ctx.sideList, packNames(ctx.sideList, names, 12, SIDE_W - 28, ctx.sideList.Size.Y.Offset), { Name = "GrowthNames", Font = T.semi, TextSize = 12, TextColor3 = T.green, Size = UDim2.fromScale(1, 1),
				AutomaticSize = Enum.AutomaticSize.None, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
		end
		-- energy / fatigue after the session (the server's numbers once the profile arrives)
		local c0 = ctx.cond0 or {}
		local function settle()
			local P1 = State.P and State.P.condition or {}
			local e1 = tonumber(P1.energy) or c0.energy or 0
			local f1 = tonumber(r0.fatigue) or tonumber(P1.fatigue) or c0.fatigue or 0
			ctx.setCond(ctx.energyBar, c0.energy or e1, e1 - (c0.energy or e1), true, true)
			ctx.setCond(ctx.fatigueBar, c0.fatigue or f1, f1 - (c0.fatigue or f1), false, true)
		end
		settle()
		local conn = State.Changed:Connect(settle)
		ctx.onDestroy(function()
			conn:Disconnect()
		end)
	end
	ctx.layout()
	ctx.quitText = "CLOSE"
	UI.BindHint(ctx.quit, function(mode)
		return mode == "gamepad" and Gamepad and ("CLOSE · " .. Gamepad.Label(K.ButtonB)) or "CLOSE"
	end)
	ctx.quit.BackgroundColor3 = T.panel2
	-- FLEX: strike the pose that shows the muscles you just pumped (server: handlers.Flex)
	local flexKind = FLEX_FOR[ctx.act.id] or "flex_most"
	local canFlex = (type(r0.pump) == "table" or type(r0.parts) == "table") and not ctx.recovery
	local actions = { { id = "close", label = "CONTINUE", keys = { K.Space }, color = T.gold } }
	if canFlex then
		table.insert(actions, { id = "flex", label = "FLEX", keys = { K.F }, color = Color3.fromRGB(255, 140, 60) })
	end
	-- MUSCLES: the Muscle Progression screen (3D figure, the groups, growth over time) opens on the
	-- parts this session grew
	local wantMuscle = false
	if #grown > 0 and State.open.Muscle then
		table.insert(actions, { id = "muscles", label = "MUSCLES", keys = { K.M }, pad = { K.ButtonY }, color = T.panel2 })
	end
	ctx.bind(actions, #actions)
	if ctx.buttons.close then
		ctx.buttons.close.TextColor3 = T.bg
	end
	-- gamepad: B closes the report too (A continues)
	if not ctx.padmap[K.ButtonB] then
		ctx.padmap[K.ButtonB] = "close"
	end
	local closed = false
	local t0 = os.clock()
	local lastFlex = 0
	ctx.on(function(id, down)
		-- a key still being mashed from the drill (SPACE) mustn't skip the results instantly
		if not down or os.clock() - t0 <= 0.8 then
			return
		end
		if id == "muscles" then
			wantMuscle = true
			closed = true
			return
		end
		if id == "flex" then
			if os.clock() - lastFlex > 3.5 then
				-- (the report stays up by itself now: CONTINUE right after a flex closes it)
				lastFlex = os.clock()
				ctx.feedback("FLEX!", Color3.fromRGB(255, 160, 70))
				task.spawn(function()
					local ok, out = pcall(State.req, "Flex", flexKind)
					if ok and type(out) == "table" and out.ok == false and out.err then
						State.toast(out.err, T.red)
					end
				end)
			end
			return
		end
		closed = true
	end)
	ctx.cancelled = false
	-- the report stays until CONTINUE / CLOSE (B): a phone player scrolls it at their own pace. It is
	-- not in the player's way, though: a window opening over it (State.closeAll - a PvP match found,
	-- the bout starting) closes it, and so does the ring itself (a queued player is free once the
	-- session is handed in)
	local function closer()
		closed = true
	end
	State.windows.ActivityReport = closer
	while not closed and not ctx.cancelled and ctx.panel.Parent and not inRing() do
		RunService.Heartbeat:Wait()
	end
	if State.windows.ActivityReport == closer then
		State.windows.ActivityReport = nil
	end
	return wantMuscle and not inRing()
end

------------------------------------------------------------------------
-- Entry points
------------------------------------------------------------------------
local SPAR_INFO = {
	Light = "1 round, 30% power, coach steps in before any knockdown. Low energy, safe.",
	Medium = "2 rounds, 55% power, the coach stops it if someone gets dropped.",
	Hard = "3 rounds, 85% power, knockdowns allowed. Big Ring IQ & chin gains, risk of cuts and bruised ribs.",
}

function Activities.SparPicker()
	if current or State.busy() then
		State.toast("Finish what you're doing first.", T.red)
		return
	end
	local shade, win, body
	local function close()
		State.windows.Spar = nil
		if shade then
			shade:Destroy()
		end
	end
	State.closeAll("Spar")
	shade, win, body = UI.Window(State.gui, "Spar", 520, 420, "SPARRING", { onClose = close })
	State.windows.Spar = close
	local P = State.P
	UI.Line(body, "Live rounds in the sparring ring with headgear on, against a gym partner matched to your level.", { TextColor3 = T.sub, TextSize = 14 })
	for _, name in ipairs({ "Light", "Medium", "Hard" }) do
		local c = UI.Card(body)
		local cost = ({ Light = 25, Medium = 35, Hard = 45 })[name]
		UI.Line(c, name:upper() .. string.format("   (energy %d)", cost), { Font = T.bold, TextColor3 = name == "Hard" and T.red or (name == "Medium" and T.gold or T.green) })
		UI.Line(c, SPAR_INFO[name], { TextSize = 13, TextColor3 = T.sub })
		UI.Button(c, "SPAR " .. name:upper(), { Size = UDim2.new(0, 180, 0, 34), BackgroundColor3 = T.gold, TextColor3 = T.bg }, function()
			if P and P.condition and P.condition.energy < cost then
				State.toast(string.format("Not enough energy (%d needed). Eat, recover or sleep.", cost), T.red)
				return
			end
			close()
			local r = State.req("StartSparring", name)
			if not r.ok then
				State.toast(r.err or "Can't spar right now", T.red)
			end
		end)
	end
end

function Activities.Start(actId)
	if current then
		State.toast("Finish your current exercise first.", T.red)
		return
	end
	if State.inFight() or State.busy() == "fight" or State.busy() == "spar" then
		return
	end
	local P = State.P
	if not (P and P.created) or P.retired then
		return
	end
	local act = Config.FindById(Config.Activities, actId)
	if not act then
		return
	end
	if act.id == "Sparring" then
		Activities.SparPicker()
		return
	end
	State.closeAll()
	-- the drill plays on its own key maps: no window selection while it runs
	UI.PadHold("Activity", true)
	local res = State.req("StartActivity", actId)
	if not res.ok then
		UI.PadHold("Activity", false)
		State.toast(res.err or "Can't do that right now", T.red)
		return
	end
	local drill = GAMES[res.minigame]
	if not drill then
		UI.PadHold("Activity", false)
		State.req("CancelActivity")
		return
	end
	current = { token = res.token, act = act }
	State.activity = current
	local ctx = newContext({ act = act, level = res.level, params = res.params, plan = res.plan, station = act.station, baseEffort = BASE_EFFORT[res.minigame] })
	current.ctx = ctx
	-- progressive overload (the drill's mastery): the server drew a tighter plan
	local ovl = type(res.plan) == "table" and tonumber(res.plan.overload) or 0
	if ovl and ovl > 0 then
		State.toast(string.format("OVERLOAD %d: tighter timing, bigger gains if you nail it.", ovl), T.gold, 3)
	end
	local camConn
	if res.pose then
		task.wait(0.15) -- let the server place the character
		camConn = stationCamera(res.pose)
	end
	local muscleAfter -- the MUSCLES button on the report: open the muscle screen on these parts once the panel is gone
	ctx.clock0 = os.clock() -- the drill clock starts with the drill
	local ok, perf = pcall(drill, ctx, res)
	ctx.on(nil)
	ctx.intensity = nil
	ctx.resting = false
	if not ok then
		warn("[Activities]", perf)
		perf = nil
	end
	if type(perf) == "number" and perf ~= perf then
		perf = 0
	end
	if type(perf) ~= "number" or ctx.cancelled then
		ctx.mode = "done"
		State.req("CancelActivity")
		State.toast(act.name .. " cancelled - no energy used.", T.sub)
	else
		-- (the server measures the quality itself from the inputs; this number is only the client's view)
		local quality = 0.5 + math.clamp(perf, 0, 1) * 0.95
		ctx.mode = "done"
		local fin = State.req("FinishActivity", res.token, quality, ctx.out)
		if fin.ok then
			if camConn then
				camConn:Disconnect()
				camConn = nil
				workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
				if camKick.baseFov then
					workspace.CurrentCamera.FieldOfView = camKick.baseFov
				end
			end
			if fin.result and fin.result.injury then
				State.toast("INJURY: " .. fin.result.injury, T.red, 6)
			end
			-- the reveal: the camera turns to face the athlete for the report
			task.wait(0.2) -- the server lets go of the station pose
			camConn = revealCamera()
			if showResult(ctx, fin, fin.quality or quality) then
				muscleAfter = type(fin.result) == "table" and fin.result.parts or {}
			end
		else
			State.toast(fin.err or "Session didn't count.", T.red)
		end
	end
	if camConn then
		camConn:Disconnect()
		if camKick.baseFov and not inRing() then
			workspace.CurrentCamera.FieldOfView = camKick.baseFov
		end
	end
	-- (the fight camera owns the view once a bout has the player)
	if not inRing() then
		workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	end
	ctx.destroy()
	current = nil
	State.activity = nil
	UI.PadHold("Activity", false)
	if muscleAfter and State.open.Muscle then
		task.defer(State.open.Muscle, { growth = muscleAfter })
	end
end

function Activities.Busy()
	return current ~= nil
end

function Activities.Cancel()
	if current and current.ctx then
		current.ctx.cancelled = true
	end
end

State.open.Activity = function(actId)
	task.spawn(Activities.Start, actId)
end
State.open.Spar = Activities.SparPicker
return Activities
