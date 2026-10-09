-- Creator: the character creator, as seven steps with Back / Next and a step bar (jump to any step).
-- Each step starts from presets (face presets, skin and eye swatches, a hairstyle grid with little
-- head drawings, body types, gear kits, boxing styles), then shows its few main controls with plain-word
-- readouts and one-line hints; an Advanced expander holds every other slider. The title row has UNDO
-- (also Ctrl+Z / Y on a gamepad; the last 20 changes), RESET (this step back to the defaults) and RANDOM
-- (this step randomised). Steps: Name (names, age, gender, nationality; voice and walkout song under
-- Advanced), Face, Skin & Eyes, Hair (style, colour, beard), Body (type, height, division, weight,
-- reach, build), Gear and Fight Style. Every change previews live on your character (server-built,
-- sent at most four times a second while a slider moves and once when it is let go); the camera frames
-- the face on the head steps and the whole body on the others, and turns (drag the 3D view, the dock's
-- arrows or the right stick) and zooms (mouse wheel over the 3D view, the dock, LT / RT).
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Looks = require(Shared:WaitForChild("Looks"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local UI = require(Shared:WaitForChild("UI"))
local State = require(script.Parent:WaitForChild("State"))
local LookKit = require(script.Parent:WaitForChild("LookKit"))
local okFlags, Flags = pcall(function()
	return require(script.Parent:WaitForChild("Flags", 5))
end)
if not okFlags then
	Flags = nil
end
local T = UI.Theme
-- the face module draws the client-side fight-damage preview (same visuals as a real fight)
local okHead, Head = pcall(function()
	return require(Shared:WaitForChild("BuilderHead"))
end)
if not okHead then
	Head = nil
end

local Creator = {}

local function newState()
	return {
		first = "", last = "", nickname = "", age = 20, nationality = "USA", music = "", voice = "Calm",
		weightClass = 5, weight = 145, reachDelta = 2, style = "BoxerPuncher", specialty = "Speed",
		look = Looks.Defaults(1),
	}
end
local C = newState()
local page = "Identity"
local PAGES = { "Identity", "Face", "Skin & Eyes", "Hair", "Body", "Gear", "Fight Style" }
local SHORT = { Identity = "NAME", Face = "FACE", ["Skin & Eyes"] = "SKIN", Hair = "HAIR", Body = "BODY", Gear = "GEAR", ["Fight Style"] = "STYLE" }
local TITLES = { Identity = "Your boxer" }
local PAGE_HINTS = {
	Identity = "Name your boxer - the rest can stay as it is. RANDOM on this step rolls a whole new look.",
	Face = "Start from a face, then tune the main features. Advanced holds every detail.",
	["Skin & Eyes"] = "Pick a skin tone and eye colour, then adjust the eyes and skin.",
	Hair = "Tap a style, then a colour. Length, volume and the beard are below.",
	Body = "Pick a body type and your size. Training shapes the rest of your body.",
	Gear = "Pick a kit, or set the main colours yourself.",
	["Fight Style"] = "How you box decides your starting stats.",
}
local HEAD_PAGES = { Face = true, ["Skin & Eyes"] = true, Hair = true }

local shade, win, body
local camConn, previewConn
local inputConns = {}
local camYaw = 0
local camZoom = 0 -- -1 closer .. 1 wider (back to 0 when the framing changes between face and body)
local camHead = false
local stickX = 0 -- right stick: turns the camera while held
local turning -- the mouse button / touch turning the camera by dragging the 3D view
local turnX = 0
local dirty = false
local dirtyFull = false -- a change that needs the whole body rebuilt (not just face / hair / beard)
local lastSent = 0
local inflight = false
local SEND_EVERY = 0.25 -- at most four previews a second while a slider moves
-- preview-only state (never saved)
local view = { growth = 0, peak = false, expr = "neutral", damage = "None" }
local advanced = {} -- [page] = the Advanced section is open
local chosen = { face = "Classic" } -- the face preset / kit last picked (outlined in the grid)
local hairGroup -- the hairstyle group shown (nil: the current style's own)
local short = false -- a short screen (phone in landscape): no page hint line
local narrow = false -- a narrow window (the smallest phones): no step prefix in the title
local keyLight

-- head = the change only touches the face, hair or beard (the server can rebuild just those)
local function preview(head)
	dirty = true
	if not head then
		dirtyFull = true
	end
end
local function previewHead()
	preview(true)
end
local lastUndoKey -- (Undo below) the control whose gesture is still open
-- a slider gesture ended (let go, a step, a reset, a wheel notch): the next change is a new undo step
local function gestureEnd()
	lastUndoKey = nil
end

local function deepcopy(t)
	if type(t) ~= "table" then
		return t
	end
	local o = {}
	for k, v in pairs(t) do
		o[k] = deepcopy(v)
	end
	return o
end

------------------------------------------------------------------------
-- Undo: snapshots of everything but the typed names, taken before each change
------------------------------------------------------------------------
local UNDO_MAX = 20
local undoStack = {}
local lastUndoAt = 0
local undoBtn
local render
local updatePlate

local function updateUndo()
	if undoBtn and undoBtn.Parent then
		local has = #undoStack > 0
		undoBtn.TextTransparency = has and 0 or 0.55
		undoBtn:SetAttribute("Steps", #undoStack)
	end
end

local SNAP_KEYS = { "age", "nationality", "voice", "music", "weightClass", "weight", "reachDelta", "style", "specialty" }
-- key: the control being changed; one slider gesture (a drag until it is let go; changes under the same
-- key in quick succession for controls without a release) is one step back
local function pushUndo(key)
	local now = os.clock()
	if key ~= nil and key == lastUndoKey and now - lastUndoAt < 0.8 then
		lastUndoAt = now
		return
	end
	lastUndoKey, lastUndoAt = key, now
	local snap = { look = deepcopy(C.look), face = chosen.face }
	for _, k in ipairs(SNAP_KEYS) do
		snap[k] = C[k]
	end
	table.insert(undoStack, snap)
	if #undoStack > UNDO_MAX then
		table.remove(undoStack, 1)
	end
	updateUndo()
end

local function undo()
	local snap = table.remove(undoStack)
	if not snap then
		return false
	end
	C.look = snap.look
	chosen.face, chosen.kit = snap.face, snap.kit
	for _, k in ipairs(SNAP_KEYS) do
		C[k] = snap[k]
	end
	lastUndoKey = nil
	preview()
	render()
	return true
end

-- wraps a control's callback: snapshot first (key: see pushUndo), then the change
local function edit(key, fn)
	return function(...)
		pushUndo(key)
		fn(...)
	end
end

------------------------------------------------------------------------
-- Previews on the character: expression, fight damage, the Preview tag
------------------------------------------------------------------------
-- fight damage previews (CONTRACTS section 8 dmg tables), one per Config.FaceDamage stage
local DAMAGE_PREVIEW = {
	None = {},
	Light = { leftEye = 0.2, bruise = 0.25, redness = 0.6 },
	Moderate = { leftEye = 0.45, cheekL = 0.5, bruise = 0.35, noseBleed = 0.4, forehead = 0.3 },
	Heavy = { leftEye = 0.7, cut = 0.6, cutSide = -1, bruise = 0.5, lip = 0.5, noseBleed = 0.5, cheekL = 0.5 },
	Severe = { leftEye = 1, rightEye = 0.85, cut = 1.1, cutSide = -1, cut2 = 0.6, bruise = 0.9, lip = 1, noseBleed = 1, nose = true, cheekL = 1, cheekR = 0.7, forehead = 0.8, earL = 0.6 },
}
local DAMAGE_ORDER = { "None", "Light", "Moderate", "Heavy", "Severe" }
local damageFace -- the Face folder the preview was last drawn against

local function applyDamagePreview()
	local char = State.char()
	if not (char and Head) then
		return
	end
	local look = char:FindFirstChild("BoxerLook")
	damageFace = look and look:FindFirstChild("Face")
	pcall(Head.SetDamage, char, C.look, DAMAGE_PREVIEW[view.damage] or {}, "PreviewDamage")
	if view.damage == "None" then
		local f = look and look:FindFirstChild("PreviewDamage")
		if f then
			f:Destroy()
		end
	end
end

local function setExpression(expr)
	view.expr = expr
	local char = State.char()
	if char then
		-- client-local: the Animator lets ExprPreview win over Expr on the local character
		char:SetAttribute("ExprPreview", expr ~= "neutral" and expr or nil)
	end
end

local function previewTag(on)
	local char = State.char()
	if char then
		if on then
			CollectionService:AddTag(char, "Preview")
		else
			CollectionService:RemoveTag(char, "Preview")
			char:SetAttribute("ExprPreview", nil)
		end
	end
end

local function hands()
	return page == "Gear" and "gloves" or "wraps"
end

local function freeze(on)
	local _, hum = State.char()
	if hum then
		hum.WalkSpeed = on and 0 or 16
		hum.JumpHeight = on and 0 or 7.2
	end
	State.SetAnimate(not on)
end

local function idsOf(list)
	local out = {}
	for _, v in ipairs(list) do
		table.insert(out, v.id or v)
	end
	return out
end

local function sameColor(a, b)
	return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

local function paletteIndex(palette, c)
	for i, p in ipairs(palette) do
		if sameColor(p, c) then
			return i
		end
	end
	return nil
end

local function skinRGB()
	return Looks.SkinTones[C.look.skin] or Looks.SkinTones[6]
end

local function defaults()
	return Looks.Defaults(C.look.gender)
end

------------------------------------------------------------------------
-- Building blocks
------------------------------------------------------------------------
local function hintLine(text)
	if short then
		return nil -- the title and the step bar say enough where every line counts
	end
	return UI.Line(body, text, { Name = "PageHint", TextColor3 = T.sub, TextSize = 13 })
end

-- colour swatches (+ a colour wheel behind "Custom colour" when wheel = true)
-- head = true: the colour only shows on the head (hair / beard), a partial rebuild is enough
local function colorField(parent, label, get, set, palette, names, head, wheelToo, key)
	local holder = UI.Frame(parent, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	UI.List(holder, 4)
	local _, refresh = UI.Swatches(holder, label, palette, paletteIndex(palette, get()), function(rgb)
		pushUndo(nil)
		set(rgb)
		preview(head)
	end, { names = names })
	if wheelToo then
		local wheel
		UI.Button(holder, "Custom colour", { Name = "CustomColour", Size = UDim2.new(0, 160, 0, math.max(30, UI.MinHit(holder))), TextSize = 13, BackgroundColor3 = T.panel2 }, function()
			if wheel then
				wheel:Destroy()
				wheel = nil
				return
			end
			wheel = UI.ColorWheel(holder, label .. " - colour wheel", get(), function(rgb)
				pushUndo(key or label)
				set(rgb)
				refresh(nil)
				preview(head)
			end)
		end)
	end
	return holder
end

-- face keys the body builder reads too (BuilderBody: skin smoothness picks the limb / torso skin
-- material, the seed varies the muscles); a change to them needs the whole character rebuilt
local BODY_FACE_KEYS = { smooth = true, seed = true }

-- one look slider (a Looks slider entry): plain words, reset to the gender default, live preview
local function lookSlider(tbl, key, def, head, withHint)
	local e = LookKit.Entry(key)
	if not e then
		return nil
	end
	local opts, num = LookKit.Opts(e, def and def[key], withHint)
	opts.onEnd = gestureEnd
	return UI.Slider(body, LookKit.Label(e), e.min, e.max, tbl[key] or (def and def[key]) or 0, e.step, function(v)
		pushUndo(key)
		tbl[key] = v
		preview(head)
	end, num, opts)
end

-- sliders for keys of a Looks list, skipping the ones in `skip`
local function sliderList(list, tbl, def, skip, head)
	local n = 0
	for _, s in ipairs(list) do
		if not (skip and skip[s.key]) then
			lookSlider(tbl, s.key, def, head == nil and not BODY_FACE_KEYS[s.key] or head)
			n += 1
		end
	end
	return n
end

local function setOf(keys)
	local t = {}
	for _, k in ipairs(keys) do
		t[k] = true
	end
	return t
end

-- the Advanced expander; returns true when it is open (the caller then builds the section)
local function advancedToggle(count)
	local open = advanced[page] == true
	local b = UI.Button(body, (open and "HIDE ADVANCED" or "ADVANCED") .. string.format("   (%d more)", count), { Name = "AdvancedToggle", Size = UDim2.new(1, 0, 0, 40), TextSize = 15,
		BackgroundColor3 = T.panel2, TextColor3 = open and T.gold or T.text }, function()
		advanced[page] = not open
		render()
	end)
	UI.Icon(b, open and "up" or "down", 12, open and T.gold or T.text, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0) })
	return open
end

-- chips: a grid of text buttons, the picked one in gold
local function chips(list, picked, cols, onPick, display)
	local grid = UI.Frame(body, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	UI.Grid(grid, UDim2.new(1 / cols, -6, 0, 36), nil, 6)
	for i, v in ipairs(list) do
		local on = v == picked
		UI.Button(grid, display and display(v) or tostring(v), { Name = "Chip_" .. tostring(v), LayoutOrder = i, TextSize = 14, BackgroundColor3 = on and T.gold or T.panel2, TextColor3 = on and T.bg or T.text }, function()
			onPick(v)
		end)
	end
	return grid
end

local function startingStats()
	local style = Config.FindById(Config.Styles, C.style) or Config.Styles[4]
	local spec = Config.FindById(Config.Specialties, C.specialty) or Config.Specialties[1]
	local frame = Config.FindById(Config.BodyTypes, C.look.body.frame) or Config.BodyTypes[2]
	local base = 26 + (C.age - 16) * 0.75
	local out = {}
	for _, k in ipairs(Config.StatKeys) do
		out[k] = math.clamp(math.floor(base + (style.mods[k] or 0) + (frame.mods[k] or 0) + (spec.stats[k] or 0)), 10, 60)
	end
	return out
end

local function modsText(mods)
	local parts = {}
	for _, k in ipairs(Config.StatKeys) do
		local v = mods[k]
		if v and v ~= 0 then
			table.insert(parts, string.format("%s%d %s", v > 0 and "+" or "", v, Config.StatNames[k]))
		end
	end
	return table.concat(parts, ", ")
end

------------------------------------------------------------------------
-- Camera: frames the face on the head steps, the whole body on the others; turns and zooms
------------------------------------------------------------------------
local function camera(on)
	if camConn then
		camConn:Disconnect()
		camConn = nil
	end
	local cam = workspace.CurrentCamera
	if not on then
		cam.CameraType = Enum.CameraType.Custom
		return
	end
	cam.CameraType = Enum.CameraType.Scriptable
	camConn = RunService.RenderStepped:Connect(function(dt)
		cam = workspace.CurrentCamera
		-- the engine resets the camera to Custom whenever the character (re)spawns
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Scriptable
		end
		if stickX ~= 0 then
			camYaw -= stickX * dt * 2.6
		end
		local char, _, root = State.char()
		local head = char and char:FindFirstChild("Head")
		if not (root and head) then
			return
		end
		local isHead = HEAD_PAGES[page] == true
		if isHead ~= camHead then
			-- the framing changed (face <-> body): start from its own default distance
			camHead = isHead
			camZoom = 0
		end
		local rot = CFrame.Angles(0, camYaw, 0) * root.CFrame.Rotation
		local look, right = rot.LookVector, rot.RightVector
		local goal
		if isHead then
			local target = head.Position + Vector3.new(0, 0.05, 0)
			local d = 1 + 0.45 * camZoom
			goal = CFrame.lookAt(target + (look * 4 + right * 1.5) * d + Vector3.new(0, 0.25, 0), target + right * 1.15 * d)
		else
			local target = root.Position + Vector3.new(0, 0.7, 0)
			local d = 1 + 0.35 * camZoom
			goal = CFrame.lookAt(target + (look * 10.5 + right * 3.8) * d + Vector3.new(0, 0.8, 0), target + right * 3.0 * d)
		end
		cam.CFrame = cam.CFrame:Lerp(goal, math.clamp(dt * 7, 0, 1))
		-- a soft key light on the face for the head pages (client-only, follows the turntable)
		if keyLight then
			keyLight.Key.Enabled = isHead
			keyLight.Fill.Enabled = isHead
			local from = head.Position + look * 2.2 + right * 1.4 + Vector3.new(0, 1.1, 0)
			keyLight.CFrame = CFrame.lookAt(from, head.Position)
		end
	end)
end

local function zoomBy(d)
	camZoom = math.clamp(camZoom + d, -1, 1)
end

local function setKeyLight(on)
	if keyLight then
		keyLight:Destroy()
		keyLight = nil
	end
	if not on then
		return
	end
	local p = Instance.new("Part")
	p.Name = "CreatorKeyLight"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	local key = Instance.new("SpotLight")
	key.Name = "Key"
	key.Brightness = 1.4
	key.Range = 9
	key.Angle = 50
	key.Color = Color3.fromRGB(255, 240, 225)
	key.Face = Enum.NormalId.Front
	key.Shadows = true
	key.Parent = p
	local fill = Instance.new("PointLight")
	fill.Name = "Fill"
	fill.Brightness = 0.35
	fill.Range = 6
	fill.Color = Color3.fromRGB(200, 215, 255)
	fill.Parent = p
	p.Parent = workspace.CurrentCamera
	keyLight = p
end

------------------------------------------------------------------------
-- Pages
------------------------------------------------------------------------
local function pageIdentity()
	hintLine(PAGE_HINTS.Identity)
	UI.TextInput(body, "First name", C.first, "e.g. Marcus", 14, function(v)
		C.first = v
	end)
	UI.TextInput(body, "Last name", C.last, "e.g. Rivera", 16, function(v)
		C.last = v
	end)
	UI.TextInput(body, "Boxing nickname", C.nickname, "e.g. The Hurricane", 20, function(v)
		C.nickname = v
	end)
	UI.Cycler(body, "Gender", { 1, 2 }, C.look.gender, edit(nil, function(g)
		local keep = { skin = C.look.skin, eye = C.look.face.eyeColor, shape = C.look.face.shape, seed = C.look.face.seed, undertone = C.look.face.undertone }
		C.look = Looks.Defaults(g)
		C.look.skin, C.look.face.eyeColor, C.look.face.shape, C.look.face.seed = keep.skin, keep.eye, keep.shape, keep.seed
		C.look.face.undertone = keep.undertone
		chosen.face = nil
		preview()
	end), function(g)
		return Config.Genders[g]
	end)
	UI.Slider(body, "Age", 16, 35, C.age, 1, function(v)
		pushUndo("age")
		C.age = v
	end, function(v)
		return v .. " yrs"
	end, {
		default = 20, hint = LookKit.Hints.age, onEnd = gestureEnd,
		words = function(v)
			return v <= 19 and "Prospect" or (v <= 27 and "Prime" or "Veteran")
		end,
	})
	UI.Cycler(body, "Nationality", Config.Nationalities, C.nationality, edit(nil, function(v)
		C.nationality = v
	end))
	if advancedToggle(3) then
		local sample
		UI.Cycler(body, "Voice type", Config.VoiceTypes, C.voice, edit(nil, function(v)
			C.voice = v
			sample.Text = "\"" .. string.format(Config.VoiceLines[v][1], "my opponent") .. "\""
		end))
		sample = UI.Line(body, "\"" .. string.format(Config.VoiceLines[C.voice][1], "my opponent") .. "\"", { TextColor3 = Color3.fromRGB(255, 170, 170), TextSize = 14 })
		UI.TextInput(body, "Walkout song (audio ID)", C.music, "Optional Roblox audio ID", 20, function(v)
			C.music = v:gsub("%D", "")
		end)
		UI.Line(body, "Your voice type shapes your press-conference lines and the ring announcer's introduction. The walkout song plays during your ring walk.", { TextColor3 = T.sub, TextSize = 13 })
	end
end

local FACE_MAIN = { "jawWidth", "chin", "cheek", "noseWidth", "noseLength", "lips" }

local function applyFacePreset(p)
	local f = C.look.face
	local def = defaults().face
	for _, list in ipairs({ Looks.FaceSliders, Looks.SculptSliders or {}, Looks.WearSliders }) do
		for _, s in ipairs(list) do
			f[s.key] = def[s.key]
		end
	end
	f.shape = p.shape
	f.noseType = p.nose or def.noseType
	for k, v in pairs(p.set) do
		f[k] = v
	end
	chosen.face = p.id
end

-- preset grids: up to n columns, fewer on a narrow window (phones, tablets) so every card's second
-- line ("80% muscle", "High cheekbones" at the readability floor) keeps its room (UI.CardColumns);
-- the body list is the window (0.46 of the canvas, at most 600) less its 16 px margins and 4 px padding
local function gridCols(n, items)
	return UI.CardColumns(State.gui, items, math.min(600, 0.46 * UI.CanvasSize(State.gui).X) - 40, n)
end

local function pageFace()
	local f = C.look.face
	local def = defaults().face
	hintLine(PAGE_HINTS.Face)
	UI.Header(body, "START FROM A FACE")
	local items = {}
	for _, p in ipairs(LookKit.FacePresets) do
		table.insert(items, { id = p.id, label = p.id, sub = p.desc, preset = p, glyph = function(art)
			LookKit.FaceGlyph(art, p.shape, skinRGB())
		end })
	end
	LookKit.PresetGrid(body, items, { name = "FacePresets", cols = gridCols(4, items), cellH = 100, picked = chosen.face }, function(it)
		pushUndo(nil)
		applyFacePreset(it.preset)
		previewHead()
		render()
	end)
	UI.Header(body, "MAIN FEATURES")
	for _, k in ipairs(FACE_MAIN) do
		lookSlider(f, k, def, true, true)
	end
	UI.Cycler(body, "Nose shape", Looks.NoseTypes or { "Straight" }, f.noseType or "Straight", edit(nil, function(v)
		f.noseType = v
		previewHead()
	end))
	local skip = setOf(FACE_MAIN)
	local more = #Looks.FaceSliders - #FACE_MAIN + #(Looks.SculptSliders or {}) + #Looks.WearSliders + 3
	if advancedToggle(more) then
		UI.Header(body, "FACE SHAPE")
		chips(Looks.FaceShapes, f.shape, 3, function(sh)
			pushUndo(nil)
			f.shape = sh
			previewHead()
			render()
		end)
		UI.Header(body, "MORE FEATURES")
		sliderList(Looks.FaceSliders, f, def, skip)
		-- v3 sculpt (organic head meshes): skull, cheekbones, jaw, chin, eyes, nose, lips
		UI.Header(body, "SCULPT")
		sliderList(Looks.SculptSliders or {}, f, def)
		UI.Header(body, "BOXER WEAR")
		sliderList(Looks.WearSliders, f, def)
		UI.Line(body, "Fights add their own wear: deep cuts scar, broken noses bend and swollen ears can turn into cauliflower ears.", { TextColor3 = T.sub, TextSize = 13 })
		UI.Header(body, "PREVIEW")
		UI.Cycler(body, "Expression", Config.Expressions, view.expr, function(v)
			setExpression(v)
		end, function(v)
			return v:sub(1, 1):upper() .. v:sub(2)
		end)
		if Head then
			UI.Cycler(body, "Fight damage", DAMAGE_ORDER, view.damage, function(v)
				view.damage = v
				applyDamagePreview()
			end)
		end
		UI.Line(body, "Previews only: see how your boxer looks mid-fight. Swelling, cuts and bruises heal over the days after a real fight.", { TextColor3 = T.sub, TextSize = 13 })
	end
end

local EYE_MAIN = { "eyeSize", "eyeShape", "eyeDist" }
local SKIN_MAIN = { "freckles" }

local function pageEyesSkin()
	local f = C.look.face
	local def = defaults().face
	hintLine(PAGE_HINTS["Skin & Eyes"])
	UI.Swatches(body, "Skin tone", Looks.SkinTones, C.look.skin, function(_, i)
		pushUndo(nil)
		C.look.skin = i
		preview()
	end, { names = LookKit.SkinNames, size = 40 })
	UI.Cycler(body, "Skin undertone", Looks.Undertones, f.undertone or "Neutral", edit(nil, function(v)
		f.undertone = v
		previewHead()
	end))
	UI.Swatches(body, "Eye colour", Looks.EyeColors, f.eyeColor, function(_, i)
		pushUndo(nil)
		f.eyeColor = i
		previewHead()
	end, { names = Looks.EyeColorNames, size = 40 })
	UI.Cycler(body, "Eyebrow style", Looks.BrowStyles, f.browStyle or "Natural", edit(nil, function(v)
		f.browStyle = v
		previewHead()
	end))
	UI.Header(body, "MAIN FEATURES")
	for _, k in ipairs(EYE_MAIN) do
		lookSlider(f, k, def, true, true)
	end
	for _, k in ipairs(SKIN_MAIN) do
		lookSlider(f, k, def, true, true)
	end
	local more = #Looks.EyeSliders - #EYE_MAIN + #Looks.SkinSliders - #SKIN_MAIN + 2
	if advancedToggle(more) then
		local second = { 0 }
		for i = 1, #Looks.EyeColors do
			table.insert(second, i)
		end
		UI.Cycler(body, "Right eye (heterochromia)", second, f.eyeColor2 or 0, edit(nil, function(v)
			f.eyeColor2 = v
			previewHead()
		end), function(v)
			return v == 0 and "Same as left" or (Looks.EyeColorNames[v] or tostring(v))
		end)
		sliderList(Looks.EyeSliders, f, def, setOf(EYE_MAIN))
		UI.Header(body, "SKIN DETAILS")
		sliderList(Looks.SkinSliders, f, def, setOf(SKIN_MAIN))
		UI.Line(body, "Skin texture is suggested with a fine-grain finish and scattered pores up close; wrinkles also deepen with age.", { TextColor3 = T.sub, TextSize = 13 })
		UI.Button(body, "New skin detail pattern", { Name = "NewPattern", Size = UDim2.new(0, 230, 0, 34), TextSize = 14 }, function()
			pushUndo(nil)
			f.seed = math.random(1, 1000000)
			preview() -- the seed also varies the body
		end)
	end
end

local HAIR_MAIN = { "length", "volume" }

local function pageHair()
	local h = C.look.hair
	local beard = C.look.beard
	local def = defaults()
	hintLine(PAGE_HINTS.Hair)
	if not Config.BaldMode then
		UI.Cycler(body, "Hair type", Looks.HairTypeOrder, h.type, edit(nil, function(v)
			h.type = v
			previewHead()
		end), Looks.HairTypeName)
		-- the styles as cards with a little head wearing each, one group at a time
		UI.Header(body, "STYLE")
		LookKit.HairPicker(body, h, skinRGB(), hairGroup, function(st)
			pushUndo(nil)
			h.style = st
			previewHead()
			render()
		end, function(g)
			hairGroup = g
			render()
		end)
		UI.Header(body, "COLOUR")
		colorField(body, "Hair colour", function()
			return h.color
		end, function(rgb)
			h.color = rgb
		end, Looks.HairColors, LookKit.HairColorNames, true)
		UI.Header(body, "LENGTH & VOLUME")
		for _, k in ipairs(HAIR_MAIN) do
			lookSlider(h, k, def.hair, true, true)
		end
	else
		UI.Line(body, "Hair is switched off on this server - beards only.", { TextColor3 = T.sub, TextSize = 13 })
	end
	if C.look.gender == 1 then
		UI.Header(body, "BEARD")
		chips(Looks.BeardStyles, beard.style, 3, function(v)
			pushUndo(nil)
			beard.style = v
			previewHead()
			render()
		end)
	end
	local more = Config.BaldMode and 0 or (#Looks.HairSliders + #(Looks.HairDetailSliders or {}) - #HAIR_MAIN + 7)
	if C.look.gender == 1 then
		more += 1
	end
	if advancedToggle(more) then
		if not Config.BaldMode then
			UI.Header(body, "CUT")
			UI.Cycler(body, "Hairline", Looks.Hairlines, h.hairline or "Natural", edit(nil, function(v)
				h.hairline = v
				previewHead()
			end))
			UI.Cycler(body, "Part", Looks.HairParts, h.part or "None", edit(nil, function(v)
				h.part = v
				previewHead()
			end))
			sliderList(Looks.HairSliders, h, def.hair, setOf(HAIR_MAIN), true)
			-- v3 strand detail for the hair meshes: clumping, frizz, volume, curl size
			sliderList(Looks.HairDetailSliders or {}, h, def.hair, setOf(HAIR_MAIN), true)
			UI.Slider(body, "Preview growth", 0, 1.5, view.growth, nil, function(v)
				view.growth = v
				previewHead()
			end, function(v)
				return v < 0.05 and "Fresh cut" or string.format("%d days", math.floor(v / (Config.HairGrowthPerDay or 0.02) + 0.5))
			end, { default = 0, onEnd = gestureEnd })
			UI.Header(body, "COLOUR EXTRAS")
			colorField(body, "Hair colour (any colour)", function()
				return h.color
			end, function(rgb)
				h.color = rgb
			end, Looks.HairColors, LookKit.HairColorNames, true, true, "hairWheel")
			UI.Toggle(body, "Highlights", h.hl, edit(nil, function(v)
				h.hl = v
				previewHead()
			end))
			UI.Cycler(body, "Dye pattern", Looks.DyePatterns, h.dye, edit(nil, function(v)
				h.dye = v
				previewHead()
			end))
			colorField(body, "Highlight / dye colour", function()
				return h.hcolor
			end, function(rgb)
				h.hcolor = rgb
			end, Looks.HairColors, LookKit.HairColorNames, true, true, "dyeWheel")
		end
		if C.look.gender == 1 then
			UI.Header(body, "BEARD COLOUR")
			UI.Toggle(body, "Beard matches hair colour", beard.color == nil, edit(nil, function(v)
				beard.color = (not v) and table.clone(h.color) or nil
				previewHead()
				render()
			end))
			if beard.color then
				colorField(body, "Beard colour", function()
					return beard.color
				end, function(rgb)
					beard.color = rgb
				end, Looks.HairColors, LookKit.HairColorNames, true, true, "beardWheel")
			end
		end
		UI.Line(body, "Hair and beards grow over time - visit the Barber Shop in the gym to restyle, recolour, line up or trim.", { TextColor3 = T.sub, TextSize = 13 })
	end
end

local BODY_MAIN = { "shoulders", "arms" }

local function pageBody()
	local b = C.look.body
	local def = defaults()
	hintLine(PAGE_HINTS.Body)
	UI.Header(body, "BODY TYPE")
	local items = {}
	for _, bt in ipairs(Config.BodyTypes) do
		table.insert(items, { id = bt.id, label = (bt.id:gsub(" Build$", "")), sub = string.format("%d%% muscle", math.floor(bt.potential * 100 + 0.5)), glyph = function(art)
			LookKit.BuildGlyph(art, bt.width, skinRGB())
		end })
	end
	LookKit.PresetGrid(body, items, { name = "BodyTypes", cols = gridCols(5, items), cellH = 104, picked = b.frame }, function(it)
		pushUndo(nil)
		b.frame = it.id
		preview()
		render()
	end)
	local ft = Config.FindById(Config.BodyTypes, b.frame) or Config.BodyTypes[2]
	UI.Line(body, string.format("%s: %s", ft.id, modsText(ft.mods)), { TextColor3 = T.sub, TextSize = 13 })
	UI.Header(body, "SIZE")
	UI.Slider(body, "Height", 60, 84, C.look.height, 1, function(v)
		pushUndo("height")
		C.look.height = v
		preview()
	end, function(v)
		return Config.HeightText(v)
	end, {
		default = def.height, hint = LookKit.Hints.height, onEnd = gestureEnd,
		words = function(v)
			return v < 66 and "Short" or (v <= 71 and "Average" or (v <= 76 and "Tall" or "Very tall"))
		end,
	})
	local idx = {}
	for i = 1, #Config.WeightClasses do
		idx[i] = i
	end
	UI.Cycler(body, "Weight class", idx, C.weightClass, edit(nil, function(v)
		C.weightClass = v
		local wc = Config.WeightClasses[v]
		C.weight = math.clamp(C.weight, wc.min, wc.limit)
		render()
	end), function(v)
		-- a division is known by its limit (the walk-around slider below covers its range); on a narrow
		-- row the limit takes the second line
		local wc = Config.WeightClasses[v]
		return string.format("%s (%d lbs)", wc.name, wc.limit)
	end)
	local wc = Config.WeightClasses[C.weightClass]
	C.weight = math.clamp(C.weight, wc.min, wc.limit)
	UI.Slider(body, "Walk-around weight", wc.min, wc.limit, C.weight, 1, function(v)
		pushUndo("weight")
		C.weight = v
	end, function(v)
		return v .. " lbs"
	end, {
		default = math.floor((wc.min + wc.limit) / 2 + 0.5), hint = LookKit.Hints.weight, onEnd = gestureEnd,
		words = function(v)
			local a = (v - wc.min) / math.max(1, wc.limit - wc.min)
			return a < 0.34 and "Light" or (a < 0.67 and "Middle" or "Heavy")
		end,
	})
	UI.Slider(body, "Reach", -3, 6, C.reachDelta, 1, function(v)
		pushUndo("reach")
		C.reachDelta = v
	end, function(v)
		return (C.look.height + v) .. " in"
	end, {
		default = 2, hint = LookKit.Hints.reach, onEnd = gestureEnd,
		words = function(v)
			return v < 0 and "Short" or (v <= 2 and "Average" or (v <= 4 and "Long" or "Very long"))
		end,
	})
	UI.Header(body, "BUILD")
	for _, k in ipairs(BODY_MAIN) do
		lookSlider(b, k, def.body, false, true)
	end
	if advancedToggle(#Looks.BodySliders - #BODY_MAIN + 2) then
		sliderList(Looks.BodySliders, b, def.body, setOf(BODY_MAIN), false)
		UI.Header(body, "PHYSIQUE")
		local phDesc
		local function physiqueText(id)
			local ph = Config.FindById(Config.Physiques, id)
			return ph and ph.desc or "Your body follows your training: the gym decides what you become."
		end
		UI.Cycler(body, "Physique target", Looks.Physiques, b.physique or "Auto", edit(nil, function(v)
			b.physique = v
			phDesc.Text = physiqueText(v)
			preview()
		end), function(v)
			local ph = Config.FindById(Config.Physiques, v)
			return ph and ph.name or "Auto (from training)"
		end)
		phDesc = UI.Line(body, physiqueText(b.physique or "Auto"), { TextColor3 = T.sub, TextSize = 13 })
		UI.Cycler(body, "Preview body", { false, true }, view.peak, function(v)
			view.peak = v
			preview()
		end, function(v)
			return v and "Peak (fully trained)" or "Starting (lean amateur)"
		end)
		UI.Line(body, "Everyone starts lean. Training transforms your body: power work builds chest, shoulders, arms and back; cardio burns fat; balanced training builds an athletic physique.", { TextColor3 = T.sub, TextSize = 13 })
	end
end

local function pageGear()
	local a = C.look.attire
	local g = C.look.gloves
	local pal, names = Looks.Palette, LookKit.PaletteNames
	hintLine(PAGE_HINTS.Gear)
	UI.Header(body, "KITS")
	local items = {}
	for _, kit in ipairs(LookKit.KitPresets) do
		table.insert(items, { id = kit.id, label = kit.id, sub = kit.desc, kit = kit, glyph = function(art)
			LookKit.KitGlyph(art, kit)
		end })
	end
	LookKit.PresetGrid(body, items, { name = "Kits", cols = gridCols(3, items), cellH = 100, picked = chosen.kit }, function(it)
		pushUndo(nil)
		LookKit.ApplyKit(it.kit, a, g)
		chosen.kit = it.id
		preview()
		render()
	end)
	UI.Header(body, "MAIN COLOURS")
	colorField(body, "Trunks", function()
		return a.trunks
	end, function(c)
		a.trunks = c
		a.robe = c
	end, pal, names)
	colorField(body, "Gloves", function()
		return g.color
	end, function(c)
		g.color = c
	end, pal, names)
	UI.Cycler(body, "Trunk style", Catalog.TrunkStyles, a.trunkStyle, edit(nil, function(v)
		a.trunkStyle = v
		preview()
	end))
	UI.Cycler(body, "Shoe style", { "Low-Top", "High-Top" }, a.shoeStyle, edit(nil, function(v)
		a.shoeStyle = v
		preview()
	end))
	if advancedToggle(8) then
		local function field(label, key)
			colorField(body, label, function()
				return a[key]
			end, function(c)
				a[key] = c
			end, pal, names, false, true, key)
		end
		UI.Header(body, "TRUNKS & FOOTWEAR")
		field("Trim / waistband", "trim")
		field("Socks", "socks")
		field("Boxing shoes", "shoes")
		field("Laces", "laces")
		UI.Header(body, "HANDS & MOUTH")
		field("Hand wraps", "wraps")
		UI.Cycler(body, "Wrap pattern", Looks.WrapPatterns, a.wrapPattern or "Solid", edit(nil, function(v)
			a.wrapPattern = v
			preview()
		end))
		field("Mouthguard", "mouthguard")
		UI.Header(body, "ROBE (walkouts)")
		field("Robe trim", "robeTrim")
		UI.Line(body, "You start with worn, beaten-up gloves. Better gloves (Gear tab) unlock trim, stitching, finishes, logos and name embroidery at the Locker Room.", { TextColor3 = T.sub, TextSize = 13 })
	end
end

local function pageStyle()
	hintLine(PAGE_HINTS["Fight Style"])
	UI.Header(body, "BOXING STYLE")
	for _, s in ipairs(Config.Styles) do
		local selected = C.style == s.id
		-- the card grows with its description (three lines on a phone-width window)
		local b = UI.Button(body, "", { Name = "Style_" .. s.id, Size = UDim2.new(1, 0, 0, 66), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = selected and T.panel:Lerp(T.gold, 0.16) or T.panel }, function()
			pushUndo(nil)
			C.style = s.id
			render()
		end)
		UI.New("UIPadding", { PaddingBottom = UDim.new(0, 8), Parent = b })
		if selected then
			UI.Stroke(b, T.gold, 2)
			UI.Frame(b, { Size = UDim2.new(0, 4, 1, -16), Position = UDim2.fromOffset(0, 8), BackgroundColor3 = T.gold })
		end
		UI.Text(b, string.upper(s.name), { Face = "display", TextSize = 22, TextColor3 = selected and T.gold or T.text, Position = UDim2.fromOffset(14, 4), Size = UDim2.new(1, -28, 0, 28), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
		UI.Text(b, s.desc .. "  (" .. modsText(s.mods) .. ")", { TextColor3 = T.sub, TextSize = 13, Position = UDim2.fromOffset(14, 32), Size = UDim2.new(1, -28, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			TextYAlignment = Enum.TextYAlignment.Top })
	end
	local specs = idsOf(Config.Specialties)
	UI.Cycler(body, "Specialty", specs, C.specialty, edit(nil, function(v)
		C.specialty = v
		render()
	end))
	local spec = Config.FindById(Config.Specialties, C.specialty)
	UI.Line(body, "Specialty bonus: " .. modsText(spec.stats) .. " and +25% training gains on those stats.", { TextColor3 = T.sub, TextSize = 13 })
	UI.Header(body, "STARTING STATS")
	local grid = UI.Frame(body, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	UI.Grid(grid, UDim2.new(0.5, -6, 0, 24), nil, 4)
	grid:FindFirstChildOfClass("UIGridLayout").CellPadding = UDim2.fromOffset(12, 4)
	local stats = startingStats()
	for i, k in ipairs(Config.StatKeys) do
		local v = stats[k]
		local row = UI.StatRow(grid, string.upper(Config.StatNames[k]), v, 100, v >= 40 and T.green or T.gold)
		row.LayoutOrder = i
	end
	UI.Line(body, string.format("Overall %d  -  You'll start as an amateur at the local gym with %s.", Config.Overall(stats), Config.Money(500)), { Font = T.semi, TextSize = 14 })
end

local PAGE_FN = {
	Identity = pageIdentity, Face = pageFace, ["Skin & Eyes"] = pageEyesSkin, Hair = pageHair,
	Body = pageBody, Gear = pageGear, ["Fight Style"] = pageStyle,
}

------------------------------------------------------------------------
-- Per-step RANDOM and RESET
------------------------------------------------------------------------
local function rng()
	return Random.new(math.random(1, 1000000))
end

local RANDOMIZE = {
	Identity = function()
		-- the whole look (a player's body follows training, and fight wear is earned: server-only)
		C.look = Looks.Random(math.random(1, 1000000), C.look.gender)
		C.look.body.frame = "Athletic"
		C.look.body.physique = "Auto"
		C.look.battle = nil
		chosen.face, chosen.kit = nil, nil
		return false
	end,
	Face = function()
		local f = C.look.face
		local r = Looks.Random(math.random(1, 1000000), C.look.gender)
		for _, list in ipairs({ Looks.FaceSliders, Looks.SculptSliders or {} }) do
			for _, s in ipairs(list) do
				f[s.key] = r.face[s.key]
			end
		end
		local R = rng()
		-- the random look keeps the sculpt neutral: give it some variety of its own
		for _, s in ipairs(Looks.SculptSliders or {}) do
			f[s.key] = s.min < 0 and R:NextNumber(-0.5, 0.5) or R:NextNumber(0.1, 0.8)
		end
		f.shape = r.face.shape
		f.noseType = Looks.NoseTypes[R:NextInteger(1, #Looks.NoseTypes)]
		chosen.face = nil
		return true
	end,
	["Skin & Eyes"] = function()
		local f = C.look.face
		local r = Looks.Random(math.random(1, 1000000), C.look.gender)
		C.look.skin = r.skin
		for _, list in ipairs({ Looks.EyeSliders, Looks.SkinSliders }) do
			for _, s in ipairs(list) do
				f[s.key] = r.face[s.key]
			end
		end
		f.undertone, f.browStyle, f.eyeColor, f.eyeColor2, f.seed = r.face.undertone, r.face.browStyle, r.face.eyeColor, r.face.eyeColor2 or 0, r.face.seed
		return false
	end,
	Hair = function()
		local r = Looks.Random(math.random(1, 1000000), C.look.gender)
		r.hair.growth = 0
		C.look.hair = r.hair
		if C.look.gender == 1 then
			r.beard.growth = 0
			C.look.beard = r.beard
		end
		return true
	end,
	Body = function()
		local R = rng()
		local b = C.look.body
		b.frame = Config.BodyTypes[R:NextInteger(1, #Config.BodyTypes)].id
		for _, s in ipairs(Looks.BodySliders) do
			b[s.key] = math.floor(R:NextNumber(-0.5, 0.5) * 100 + 0.5) / 100
		end
		C.look.height = C.look.gender == 2 and R:NextInteger(61, 71) or R:NextInteger(65, 77)
		local wc = Config.WeightClasses[C.weightClass]
		C.weight = R:NextInteger(wc.min, wc.limit)
		C.reachDelta = R:NextInteger(-1, 4)
		return false
	end,
	Gear = function()
		local R = rng()
		local pal = Looks.Palette
		local function pick(not1)
			local i
			repeat
				i = R:NextInteger(1, #pal)
			until i ~= not1
			return i, table.clone(pal[i])
		end
		local a, g = C.look.attire, C.look.gloves
		local ti, trunks = pick()
		local _, trim = pick(ti)
		a.trunks, a.trim, a.robe, a.robeTrim = trunks, trim, table.clone(trunks), table.clone(trim)
		a.shoes = R:NextNumber() < 0.5 and table.clone(trunks) or { 20, 20, 20 }
		a.socks = R:NextNumber() < 0.6 and { 240, 240, 240 } or { 20, 20, 20 }
		a.laces = table.clone(trim)
		local _, glove = pick()
		g.color, g.trim = glove, table.clone(trim)
		a.trunkStyle = Catalog.TrunkStyles[R:NextInteger(1, #Catalog.TrunkStyles)]
		a.shoeStyle = R:NextNumber() < 0.5 and "Low-Top" or "High-Top"
		chosen.kit = nil
		return false
	end,
	["Fight Style"] = function()
		C.style = Config.Styles[math.random(1, #Config.Styles)].id
		C.specialty = Config.Specialties[math.random(1, #Config.Specialties)].id
		return false
	end,
}

local RESET = {
	Identity = function()
		C.age, C.nationality, C.voice, C.music = 20, "USA", "Calm", ""
		return false
	end,
	Face = function()
		applyFacePreset(LookKit.FacePresets[1])
		return true
	end,
	["Skin & Eyes"] = function()
		local f, def = C.look.face, defaults()
		C.look.skin = def.skin
		for _, list in ipairs({ Looks.EyeSliders, Looks.SkinSliders }) do
			for _, s in ipairs(list) do
				f[s.key] = def.face[s.key]
			end
		end
		f.undertone, f.browStyle, f.eyeColor, f.eyeColor2 = def.face.undertone, def.face.browStyle, def.face.eyeColor, def.face.eyeColor2
		return false
	end,
	Hair = function()
		local def = defaults()
		C.look.hair = def.hair
		C.look.beard = def.beard
		view.growth = 0
		return true
	end,
	Body = function()
		local def = defaults()
		C.look.body = def.body
		C.look.height = def.height
		C.weightClass, C.weight, C.reachDelta = 5, 145, 2
		return false
	end,
	Gear = function()
		local def = defaults()
		C.look.attire = def.attire
		C.look.gloves = def.gloves
		chosen.kit = nil
		return false
	end,
	["Fight Style"] = function()
		C.style, C.specialty = "BoxerPuncher", "Speed"
		return false
	end,
}

local function stepAction(tbl)
	local fn = tbl[page]
	if not fn then
		return
	end
	pushUndo(nil)
	local headOnly = fn()
	preview(headOnly)
	render()
end

------------------------------------------------------------------------
-- The window
------------------------------------------------------------------------
local tabsFrame, nextBtn, backBtn, progressFill
local stepsFrame, titleLabel, stepKicker
local stepMenu = false -- short screens: the step bar is a menu that drops from the step's name
local lastPage

local function goTo(name)
	local wasHands = hands()
	page = name
	if hands() ~= wasHands then
		preview()
	end
	render()
end

-- short screens: opens / closes the step menu (the step bar itself on taller screens: always shown)
local function showSteps(on)
	if not (stepMenu and tabsFrame) then
		return
	end
	tabsFrame.Visible = on
	local chevron = win and win:FindFirstChild("StepPick")
	chevron = chevron and chevron:FindFirstChild("Chevron")
	if chevron then
		chevron.Rotation = on and 180 or 0
	end
	if on and UI.InputMode() == "gamepad" then
		UI.PadSelect(stepsFrame)
	end
end

function render()
	if not (shade and shade.Parent) then
		return
	end
	local cur = table.find(PAGES, page) or 1
	-- title: the step's name (a window with neither kicker line counts the step in the title too)
	local kicker = win:FindFirstChild("Kicker")
	if titleLabel then
		local name = string.upper(TITLES[page] or page)
		titleLabel.Text = (kicker or narrow or stepKicker) and name or string.format("%d/%d  %s", cur, #PAGES, name)
	end
	if kicker then
		kicker.Text = string.format("CREATE YOUR BOXER  ·  STEP %d OF %d", cur, #PAGES)
	end
	if stepKicker then
		stepKicker.Text = string.format("STEP %d OF %d", cur, #PAGES)
	end
	UI.Clear(stepsFrame)
	for i, name in ipairs(PAGES) do
		local done = i < cur
		local b = UI.Button(stepsFrame, string.format("%d %s", i, SHORT[name]), { Name = "Step" .. i, LayoutOrder = i, TextSize = stepMenu and 15 or 13, BackgroundColor3 = name == page and T.gold or T.panel2,
			TextColor3 = name == page and T.bg or (done and T.gold or T.text) }, function()
			showSteps(false)
			goTo(name)
		end)
		b:SetAttribute("CreatorStep", i)
		if name == page then
			UI.PadStart(b)
		end
	end
	if progressFill then
		progressFill.Size = UDim2.fromScale(cur / #PAGES, 1)
	end
	local y = lastPage == page and body.CanvasPosition or Vector2.zero
	lastPage = page
	UI.Clear(body)
	local ok, err = pcall(PAGE_FN[page])
	if not ok then
		warn("[Creator]", err)
	end
	task.defer(function()
		if body and body.Parent then
			body.CanvasPosition = y
		end
	end)
	if nextBtn then
		nextBtn.Text = page == PAGES[#PAGES] and "BEGIN CAREER" or ("NEXT:  " .. SHORT[PAGES[cur + 1]])
	end
	if backBtn then
		backBtn.TextTransparency = cur == 1 and 0.55 or 0
	end
	updateUndo()
end

-- the live fighter plate (built in Creator.Open)
local plate, plateFlag, plateNick, plateName, plateInfo, plateConn
-- the fields the plate shows and what it last showed (compared field by field every frame: no
-- table or string is built unless something changed)
local PLATE_FIELDS = { "first", "last", "nickname", "nationality", "weightClass", "style", "age" }
local plateSeen = {}
function updatePlate()
	if not (plate and plate.Parent) then
		return
	end
	local same = true
	for _, k in ipairs(PLATE_FIELDS) do
		if plateSeen[k] ~= C[k] then
			plateSeen[k] = C[k]
			same = false
		end
	end
	if same then
		return
	end
	local wc = Config.WeightClasses[C.weightClass]
	local style = Config.FindById(Config.Styles, C.style)
	local first = C.first:gsub("^%s+", ""):gsub("%s+$", "")
	local last = C.last:gsub("^%s+", ""):gsub("%s+$", "")
	local name = (first .. " " .. last):gsub("^%s+", "")
	plateName.Text = name ~= "" and string.upper(name) or "YOUR NAME"
	plateName.TextColor3 = name ~= "" and T.text or T.dim
	plateNick.Text = C.nickname ~= "" and ('"' .. string.upper(C.nickname) .. '"') or "AMATEUR  ·  DEBUT"
	plateInfo.Text = string.format("%s  ·  %s  ·  %s  ·  AGE %d", string.upper(C.nationality), string.upper(wc and wc.name or "-"), string.upper(style and style.name or "-"), C.age)
	UI.Clear(plateFlag)
	if Flags then
		pcall(Flags.Draw, plateFlag, C.nationality, { Size = UDim2.fromOffset(36, 24) })
	end
end

local function begin()
	if C.first:gsub("%s", "") == "" or C.last:gsub("%s", "") == "" then
		State.toast("Give your boxer a first and last name.", T.red)
		page = "Identity"
		render()
		return
	end
	nextBtn.Text = "CREATING..."
	local res = State.req("CreateBoxer", {
		first = C.first, last = C.last, nickname = C.nickname, age = C.age, nationality = C.nationality,
		music = C.music, voice = C.voice, weightClass = C.weightClass, weight = C.weight, reachDelta = C.reachDelta,
		style = C.style, specialty = C.specialty, look = C.look,
	})
	if res.ok then
		Creator.Close()
		State.toast("Welcome to the fight game! Your amateur career starts now.", T.gold, 5)
		State.toast("Train at the gym stations, eat and sleep - then book a fight at the FIGHT BOARD (or press H).", T.gold, 7)
	else
		nextBtn.Text = "BEGIN CAREER"
		State.toast(res.err or "Couldn't create your boxer", T.red)
	end
end

local function step(d)
	local i = table.find(PAGES, page) or 1
	local j = math.clamp(i + d, 1, #PAGES)
	if j ~= i then
		goTo(PAGES[j])
	end
end

-- keyboard, mouse, touch and gamepad shortcuts while the creator is open
local function bindInputs()
	for _, c in ipairs(inputConns) do
		c:Disconnect()
	end
	table.clear(inputConns)
	local function onTop()
		-- the creator is open and no other window sits over it
		local top = UI.PadTop()
		return shade and shade.Parent and (top == nil or top == win)
	end
	table.insert(inputConns, UserInputService.InputBegan:Connect(function(input, gp)
		if not onTop() then
			return
		end
		local t, k = input.UserInputType, input.KeyCode
		if not gp and (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch) and turning == nil then
			-- a press on the 3D view (not on any GUI): drag to turn the boxer
			turning, turnX = input, input.Position.X
		elseif k == Enum.KeyCode.ButtonY or (k == Enum.KeyCode.Z and not gp and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl))) then
			-- Ctrl+Z / Y: one change back
			undo()
		elseif k == Enum.KeyCode.ButtonL1 or k == Enum.KeyCode.ButtonR1 then
			step(k == Enum.KeyCode.ButtonL1 and -1 or 1)
		elseif k == Enum.KeyCode.ButtonL2 or k == Enum.KeyCode.ButtonR2 then
			zoomBy(k == Enum.KeyCode.ButtonL2 and 0.4 or -0.4)
		end
	end))
	table.insert(inputConns, UserInputService.InputChanged:Connect(function(input, gp)
		local t = input.UserInputType
		if turning and ((t == Enum.UserInputType.MouseMovement and turning.UserInputType == Enum.UserInputType.MouseButton1) or (t == Enum.UserInputType.Touch and input == turning)) then
			local x = input.Position.X
			camYaw -= (x - turnX) * 0.012
			turnX = x
		elseif t == Enum.UserInputType.MouseWheel and not gp and onTop() then
			zoomBy(input.Position.Z > 0 and -0.2 or 0.2)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local x = input.Position.X
			stickX = math.abs(x) > 0.25 and x or 0
		end
	end))
	table.insert(inputConns, UserInputService.InputEnded:Connect(function(input)
		if turning and (input == turning or (input.UserInputType == Enum.UserInputType.MouseButton1 and turning.UserInputType == Enum.UserInputType.MouseButton1)) then
			turning = nil
		end
	end))
end

function Creator.Open()
	if shade and shade.Parent then
		return
	end
	State.closeAll("Creator")
	C = newState()
	page = "Identity"
	camYaw, camZoom, stickX, turning = 0, 0, 0, nil
	table.clear(undoStack)
	table.clear(advanced)
	chosen.face, chosen.kit = "Classic", nil
	hairGroup = nil
	lastUndoKey = nil
	-- BACK (and B on a gamepad: the creator cannot be closed, B steps back a page)
	local function back()
		if stepMenu and tabsFrame and tabsFrame.Visible then
			showSteps(false) -- B / Backspace first closes the step menu
			return
		end
		step(-1)
	end
	shade, win, body = UI.Window(State.gui, "Creator", 600, 720, "CREATE YOUR BOXER", { side = "left", noShade = true, footer = 50, onBack = back, kicker = "CREATE YOUR BOXER" })
	local canvas = UI.CanvasSize(State.gui)
	short = canvas.Y < 560
	-- a narrow window (the smallest phones: 0.46 of the canvas is under 420 design px) keeps the step's
	-- name readable with slimmer tool buttons and no "1/7" prefix (the step bar counts the steps)
	narrow = canvas.X * 0.46 < 420
	local top = body.Position.Y.Offset
	-- touch: the tool buttons, the step bar and BACK / NEXT grow to a fingertip and the rows around them
	local minHit = UI.MinHit(win)
	-- title row: UNDO / RESET / RANDOM on the right of the step's name
	local title = win:FindFirstChild("Title")
	local bw = narrow and 56 or (short and 66 or 78)
	local bh = math.max(32, minHit)
	local toolsY = title and (title.Position.Y.Offset + math.floor((title.Size.Y.Offset - bh) / 2)) or 12
	if bh > 32 then
		-- taller buttons start under the kicker line (a tablet) or near the top edge (a phone)
		local kicker = win:FindFirstChild("Kicker")
		toolsY = math.max(kicker and (kicker.Position.Y.Offset + kicker.Size.Y.Offset + 4) or 4, toolsY)
		top = math.max(top, toolsY + bh + 8)
	end
	local tools = UI.Frame(win, { Name = "Tools", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(bw * 3 + 12, bh), Position = UDim2.new(1, -16, 0, toolsY) })
	UI.List(tools, 6, true, Enum.HorizontalAlignment.Right)
	local tts = narrow and 12 or 13
	undoBtn = UI.Button(tools, "UNDO", { Name = "Undo", Size = UDim2.fromOffset(bw, bh), TextSize = tts, LayoutOrder = 1 }, function()
		undo()
	end)
	UI.Button(tools, "RESET", { Name = "ResetStep", Size = UDim2.fromOffset(bw, bh), TextSize = tts, LayoutOrder = 2 }, function()
		stepAction(RESET)
	end)
	local rb = UI.Button(tools, "RANDOM", { Name = "RandomStep", Size = UDim2.fromOffset(bw, bh), TextSize = tts, LayoutOrder = 3, TextColor3 = T.gold }, function()
		stepAction(RANDOMIZE)
	end)
	UI.Stroke(rb, T.gold, 1, 0.55)
	titleLabel = title
	stepKicker = nil
	if title then
		title.Size = UDim2.new(1, -(40 + bw * 3 + 12 + 24), 0, title.Size.Y.Offset)
	end
	local sh = math.max(34, minHit)
	local line
	stepMenu = short
	if stepMenu then
		-- short screens (phones): the step bar folds into a menu that drops from the step's name, so
		-- the body keeps the 77 px a finger-high bar would take; the step's name becomes the menu
		-- button ("STEP 2 OF 7" over it, a chevron) and a thin progress line runs under the header
		local rowH = math.max(bh, 44)
		local pick = UI.Button(win, "", { Name = "StepPick", Position = UDim2.fromOffset(12, toolsY), Size = UDim2.new(1, -(12 + bw * 3 + 12 + 16 + 8), 0, rowH),
			BackgroundColor3 = T.panel2, BackgroundTransparency = 0.6 }, function()
			showSteps(not tabsFrame.Visible)
		end)
		local tick = win:FindFirstChild("TitleTick")
		if tick then
			tick.Parent = pick
			tick.Position = UDim2.new(0, 10, 0.5, -10)
			tick.Size = UDim2.fromOffset(4, 20)
		end
		stepKicker = UI.Text(pick, "", { Name = "StepKicker", Font = T.semi, TextSize = 11, TextColor3 = T.gold, Position = UDim2.new(0, 22, 0.5, -19), Size = UDim2.new(1, -52, 0, 15),
			AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
		if title then
			title.Parent = pick
			title.Position = UDim2.new(0, 22, 0.5, -5)
			title.Size = UDim2.new(1, -52, 0, 24)
			UI.SetTextSize(title, 22)
		end
		UI.Icon(pick, "down", 14, T.text, { Name = "Chevron", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0) })
		top = math.max(top, toolsY + rowH + 10)
		local divider = win:FindFirstChild("Divider")
		if divider then
			divider.Visible = false -- (the window's header line: the progress line takes its place)
		end
		line = UI.Frame(win, { Name = "Progress", Position = UDim2.fromOffset(16, top - 5), Size = UDim2.new(1, -32, 0, 3), BackgroundColor3 = T.panel2 })
		-- the menu: two columns of finger-high steps over a dimmed body (a tap beside them closes it)
		local rows = math.ceil(#PAGES / 2)
		tabsFrame = UI.New("TextButton", { Name = "StepBar", Parent = win, Text = "", AutoButtonColor = false, Visible = false, ZIndex = 5, BorderSizePixel = 0, Selectable = false,
			BackgroundColor3 = T.ink, BackgroundTransparency = 0.35, Position = UDim2.fromOffset(0, top), Size = UDim2.new(1, 0, 1, -top) })
		UI.Corner(tabsFrame, UI.R.xl)
		tabsFrame.MouseButton1Click:Connect(function()
			showSteps(false)
		end)
		local card = UI.Frame(tabsFrame, { Name = "Card", Position = UDim2.fromOffset(12, 2), Size = UDim2.new(1, -24, 0, rows * (sh + 6) + 18), ZIndex = 5 })
		UI.Glass(card, { transparency = 0.04, radius = UI.R.lg })
		stepsFrame = UI.Frame(card, { Name = "Steps", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -24, 1, -18), ZIndex = 5 })
		UI.Grid(stepsFrame, UDim2.new(0.5, -6, 0, sh), nil, 6)
	else
		local divider = win:FindFirstChild("Divider")
		if divider and bh > 32 then
			divider.Position = UDim2.fromOffset(16, top - 5) -- (under the finger-sized tools, not through them)
		end
		-- the step bar: every step (tap to jump) over a thin progress line
		tabsFrame = UI.Frame(win, { Name = "StepBar", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, top), Size = UDim2.new(1, -32, 0, sh + 6) })
		stepsFrame = UI.Frame(tabsFrame, { Name = "Steps", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, sh) })
		UI.Grid(stepsFrame, UDim2.new(1 / #PAGES, -4, 0, sh), nil, 4)
		line = UI.Frame(tabsFrame, { Name = "Progress", Position = UDim2.new(0, 0, 1, -3), Size = UDim2.new(1, -4, 0, 3), BackgroundColor3 = T.panel2 })
		top += sh + 14
	end
	UI.Corner(line, 2)
	progressFill = UI.Frame(line, { Name = "Fill", Size = UDim2.fromScale(1 / #PAGES, 1), BackgroundColor3 = T.gold })
	UI.Corner(progressFill, 2)
	local nh = math.max(42, minHit)
	body.Position = UDim2.fromOffset(16, top)
	body.Size = UDim2.new(1, -32, 1, -(top + nh + 20))
	local nav = UI.Frame(win, { Name = "Nav", BackgroundTransparency = 1, Position = UDim2.new(0, 16, 1, -(nh + 12)), Size = UDim2.new(1, -32, 0, nh) })
	backBtn = UI.Button(nav, "BACK", { Name = "BackStep", Size = UDim2.new(0.3, 0, 1, 0) }, back)
	nextBtn = UI.Button(nav, "NEXT", { Name = "NextStep", Size = UDim2.new(0.66, 0, 1, 0), Position = UDim2.new(0.34, 0, 0, 0), BackgroundColor3 = T.gold, TextColor3 = T.bg })
	nextBtn.MouseButton1Click:Connect(function()
		if page ~= PAGES[#PAGES] then
			step(1)
		else
			begin()
		end
	end)
	-- the live fighter plate over the 3D view: flag, name, nickname, division, style (updates as you type)
	plate = UI.Frame(shade, { Name = "FighterPlate", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -28, 1, -84), Size = UDim2.fromOffset(440, 120) })
	UI.Glass(plate, { transparency = 0.12, radius = UI.R.lg })
	UI.Frame(plate, { Name = "Accent", Size = UDim2.new(0, 4, 1, -20), Position = UDim2.fromOffset(0, 10), BackgroundColor3 = T.gold })
	plateFlag = UI.Frame(plate, { Name = "Flag", BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 16), Size = UDim2.fromOffset(36, 24) })
	plateNick = UI.Text(plate, "", { Font = T.semi, TextSize = 12, TextColor3 = T.gold, Position = UDim2.fromOffset(64, 12), Size = UDim2.new(1, -80, 0, 14), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	plateName = UI.Text(plate, "", { Face = "display", TextSize = 34, Position = UDim2.fromOffset(64, 24), Size = UDim2.new(1, -80, 0, 42), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	-- the info line fits its box: it takes a second line on a narrow plate rather than being cut (the
	-- box holds two lines of the readability floor)
	plateInfo = UI.Text(plate, "", { Font = T.semi, TextSize = 12, TextColor3 = T.sub, Position = UDim2.fromOffset(18, 72), Size = UDim2.new(1, -36, 0, 36), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = true, TextScaled = true,
		TextYAlignment = Enum.TextYAlignment.Top })
	UI.New("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 10, Parent = plateInfo })
	table.clear(plateSeen)
	-- turntable dock (right side of the screen): rotate and zoom, with the device's own shortcuts above it
	-- touch: its buttons are finger-sized (the plate and the camera hint stack above the taller dock);
	-- where the room right of the window is short of the full dock (the smallest phones) the ROTATE /
	-- ZOOM words go and the arrows speak for themselves
	local db = math.max(36, minHit)
	local dockH = db + 12
	local dockWords = 4 * db + 74 + 50 + 40 + 1 + 7 * 6 + 16 <= canvas.X * 0.54 - 24 - 28 - 12
	local dock = UI.Frame(shade, { Name = "Turntable", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -28, 1, -24), Size = UDim2.fromOffset(0, dockH), AutomaticSize = Enum.AutomaticSize.X })
	local camHint = UI.Text(shade, "", { Name = "CameraHint", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -34, 1, -(30 + dockH)), Size = UDim2.fromOffset(440, 16), TextSize = 12, TextColor3 = T.sub,
		TextXAlignment = Enum.TextXAlignment.Right, AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	UI.BindHint(camHint, function(mode)
		if mode == "gamepad" then
			local G = UI.Gamepad
			local function l(k)
				return G and G.Label(k) or k.Name
			end
			return string.format("RIGHT STICK turn  ·  %s / %s zoom  ·  %s / %s step  ·  %s undo  ·  %s reset slider", l(Enum.KeyCode.ButtonL2), l(Enum.KeyCode.ButtonR2), l(Enum.KeyCode.ButtonL1),
				l(Enum.KeyCode.ButtonR1), l(Enum.KeyCode.ButtonY), l(Enum.KeyCode.ButtonX))
		elseif mode == "touch" then
			return "Drag your boxer to turn him"
		end
		return "Drag your boxer to turn  ·  wheel to zoom  ·  Ctrl+Z undo"
	end)
	-- phones: the plate moves to the top-right corner so it never covers the boxer, and takes no more
	-- than the room right of the window (the window is 0.46 of the canvas plus its 24 px margin)
	local function placePlate()
		if not (plate and plate.Parent) then
			return
		end
		local cv = UI.CanvasSize(plate)
		local small = cv.Y < 640
		plate.AnchorPoint = small and Vector2.new(1, 0) or Vector2.new(1, 1)
		plate.Position = small and UDim2.new(1, -20, 0, 12) or UDim2.new(1, -28, 1, -(36 + dockH))
		local free = cv.X - (0.46 * cv.X + 24) - 40
		plate.Size = UDim2.fromOffset(small and math.clamp(math.floor(free), 240, 480) or 440, 120)
		camHint.Position = small and UDim2.new(1, -34, 1, -(30 + dockH)) or UDim2.new(1, -34, 1, -(162 + dockH))
	end
	placePlate()
	if plateConn then
		plateConn:Disconnect()
	end
	plateConn = State.screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(placePlate)
	UI.Glass(dock, { transparency = 0.15, radius = math.floor(dockH / 2) })
	UI.New("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = dock })
	UI.List(dock, 6, true, Enum.HorizontalAlignment.Center)
	if dockWords then
		UI.Text(dock, "ROTATE", { Font = T.semi, TextSize = 10, TextColor3 = T.sub, Size = UDim2.fromOffset(50, dockH), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, LayoutOrder = 0 })
	end
	local held = 0
	UI.Frame(dock, { Size = UDim2.fromOffset(1, math.floor(dockH * 0.55)), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.8, LayoutOrder = 5 })
	if dockWords then
		UI.Text(dock, "ZOOM", { Font = T.semi, TextSize = 10, TextColor3 = T.sub, Size = UDim2.fromOffset(40, dockH), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, LayoutOrder = 6 })
	end
	local iconSize = math.floor(14 + (db - 36) * 0.2)
	for i, z in ipairs({ { "minus", 0.4 }, { "plus", -0.4 } }) do
		local zb = UI.Button(dock, "", { Name = z[1] == "minus" and "ZoomOut" or "ZoomIn", Size = UDim2.fromOffset(db, db), LayoutOrder = 6 + i }, function()
			zoomBy(z[2])
		end)
		zb:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, math.floor(db / 2))
		UI.Icon(zb, z[1], iconSize, T.text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	end
	for i, def in ipairs({ { "<", 0.35 }, { "FRONT", 0 }, { ">", -0.35 } }) do
		local icon = def[1] == "<" and "left" or (def[1] == ">" and "right" or nil)
		local b = UI.Button(dock, icon and "" or def[1], { Name = icon and ("Turn" .. icon) or "Front", Size = UDim2.fromOffset(icon and db or 74, db), TextSize = 14, LayoutOrder = i }, function()
			if def[2] == 0 then
				camYaw = 0
			else
				camYaw += def[2]
			end
		end)
		b.MouseButton1Down:Connect(function()
			if def[2] ~= 0 then
				held = def[2]
			end
		end)
		b.MouseButton1Up:Connect(function()
			held = 0
		end)
		b.MouseLeave:Connect(function()
			held = 0
		end)
		b:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, math.floor(db / 2))
		if icon then
			UI.Icon(b, icon, iconSize, T.text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		end
	end
	freeze(true)
	camera(true)
	setKeyLight(true)
	previewTag(true)
	bindInputs()
	view.growth, view.peak, view.expr, view.damage = 0, false, "neutral", "None"
	State.HidePrompts("Creator", true)
	render()
	if previewConn then
		previewConn:Disconnect()
	end
	inflight = false
	previewConn = RunService.Heartbeat:Connect(function(dt)
		if held ~= 0 then
			camYaw += held * dt * 4
		end
		updatePlate()
		local now = os.clock()
		if inflight and now - lastSent > 2 then
			inflight = false -- a lost reply never blocks the preview for good
		end
		if dirty and not inflight then
			if now - lastSent >= SEND_EVERY then
				local full = dirtyFull
				dirty, dirtyFull = false, false
				lastSent = now
				inflight = true
				-- preview-only options: growth stage, starting / peak body, partial head rebuild
				local popts = { peak = view.peak, growth = view.growth > 0.02 and view.growth or nil }
				if not full then
					popts.only = { Face = true, Hair = true, Beard = true }
				end
				task.spawn(function()
					local r = State.req("PreviewLook", C.look, hands(), popts)
					inflight = false
					if r and r.throttled then
						dirty = true
						dirtyFull = dirtyFull or full
					end
				end)
			end
		end
		-- a server rebuild replaces the face: draw the damage preview over the new one
		if view.damage ~= "None" then
			local char = State.char()
			local look = char and char:FindFirstChild("BoxerLook")
			local face = look and look:FindFirstChild("Face")
			if face and face ~= damageFace then
				applyDamagePreview()
			end
		end
	end)
	State.windows.Creator = Creator.Close
	preview()
end

function Creator.Close()
	State.windows.Creator = nil
	if previewConn then
		previewConn:Disconnect()
		previewConn = nil
	end
	if plateConn then
		plateConn:Disconnect()
		plateConn = nil
	end
	for _, c in ipairs(inputConns) do
		c:Disconnect()
	end
	table.clear(inputConns)
	turning, stickX = nil, 0
	camera(false)
	setKeyLight(false)
	-- drop the preview-only expression, damage and tag
	if view.damage ~= "None" then
		view.damage = "None"
		applyDamagePreview()
	end
	previewTag(false)
	freeze(false)
	State.HidePrompts("Creator", false)
	if shade then
		shade:Destroy()
		shade = nil
	end
end

function Creator.IsOpen()
	return shade ~= nil and shade.Parent ~= nil
end

-- the character respawned while creating: keep the player's choices, re-apply the preview
function Creator.Refresh()
	if not Creator.IsOpen() then
		return
	end
	freeze(true)
	camera(true)
	previewTag(true)
	setExpression(view.expr)
	preview()
end

State.open.Creator = Creator.Open
return Creator
