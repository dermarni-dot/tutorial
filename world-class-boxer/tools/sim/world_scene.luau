--!nocheck
-- tools/sim/world_scene.luau: builds the game's WORLD offline (fakeengine) and dumps every part for rendering
-- and counting: the server gym + city (MapBuilder.BuildGym -> GymDecor, CityMap), the venue templates
-- (Venues.BuildTemplates / Venues.New per tier), the client gym dressing (GymVisuals / GymFacility), the
-- client detail layer (WorldDetail, when present) and the title-screen set (MenuStage).
--
--   lune run tools/sim/world_scene.luau [--out DIR] [--level 1|2|3] [--src DIR] [--only gym,city,venues,menu]
--                                       [--counts]   (instance counts only, no dump)
--
-- DIR/scene.json = { roots = { [name] = { parts = [...], lights = [...], guis = [...] } }, counts = {...},
--                    lighting = { props, children (post effects / Atmosphere / Sky by name), night }, venueLighting = { [kind] = VenueFX profile } }
-- part = { c = class, s = {x,y,z}, cf = {12}, col = {r,g,b} (0..1), m = material, t = transparency,
--          sh = shape, mesh = {k = MeshType, s = scale, o = offset} | nil, refl }
-- light = { k = class, p = {x,y,z}, d = {dir} | nil, col, b = brightness, r = range, a = angle, face, on }
-- gui = { part = index into parts, face = NormalId, items = [{ x, y, w, h (0..1 of the face), bg = {rgb}, bt,
--          text, tc = {rgb}, tt }] }
-- counts per root: instances, parts, lights, guis, decals (the totals the performance budget is measured on).
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Host = require("./host")
local FE = require("./fakeengine")

local Vector3, CFrame, Color3 = roblox.Vector3, roblox.CFrame, roblox.Color3

local args = {}
do
	local i = 1
	while i <= #process.args do
		local a = process.args[i]
		if a:sub(1, 2) == "--" then
			local nx = process.args[i + 1]
			if nx and nx:sub(1, 2) ~= "--" then
				args[a:sub(3)] = nx
				i += 1
			else
				args[a:sub(3)] = true
			end
		end
		i += 1
	end
end
local OUT = args.out or "tools/sim/out/world"
local LEVEL = tonumber(args.level) or 3
local ONLY = {}
for w in tostring(args.only or "gym,city,venues,menu"):gmatch("[^,]+") do
	ONLY[w] = true
end

local E = FE.new()
local Signal = FE.Signal

-- engine members the world code touches that fakeengine leaves out
local SIGNALS = {
	Touched = true, TouchEnded = true, Triggered = true, TriggerEnded = true, PromptShown = true, PromptHidden = true,
	MouseClick = true, Completed = true, Ended = true, Played = true, Loaded = true, Activated = true, Event = true,
	OnClientEvent = true, OnServerEvent = true, OnInvoke = true, MouseButton1Click = true, CharacterAdded = true,
	Died = true, Running = true, StateChanged = true, Focused = true, FocusLost = true, InputBegan = true,
	MouseEnter = true, MouseLeave = true, DidLoop = true,
}
local function moveTree(o, delta)
	for _, d in ipairs(o:GetDescendants()) do
		local p = rawget(d, "_props")
		if p.CFrame and (d:IsA("BasePart")) then
			p.CFrame = delta * p.CFrame
		end
	end
	local p = rawget(o, "_props")
	if p.WorldPivot then
		p.WorldPivot = delta * p.WorldPivot
	end
end
local function bbox(o)
	local mn, mx
	for _, d in ipairs(o:GetDescendants()) do
		if d:IsA("BasePart") then
			local cf, s = d.CFrame, d.Size
			for _, sx in ipairs({ -0.5, 0.5 }) do
				for _, sy in ipairs({ -0.5, 0.5 }) do
					for _, sz in ipairs({ -0.5, 0.5 }) do
						local w = cf * Vector3.new(s.X * sx, s.Y * sy, s.Z * sz)
						mn = mn and Vector3.new(math.min(mn.X, w.X), math.min(mn.Y, w.Y), math.min(mn.Z, w.Z)) or w
						mx = mx and Vector3.new(math.max(mx.X, w.X), math.max(mx.Y, w.Y), math.max(mx.Z, w.Z)) or w
					end
				end
			end
		end
	end
	if not mn then
		return CFrame.new(), Vector3.zero
	end
	return CFrame.new((mn + mx) / 2), mx - mn
end
local function modelPivot(o)
	local p = rawget(o, "_props")
	if p.CFrame then
		return p.CFrame
	end
	if p.WorldPivot then
		return p.WorldPivot
	end
	if p.PrimaryPart then
		return p.PrimaryPart.CFrame
	end
	return (bbox(o))
end
local METHODS = {
	PivotTo = function(o, cf)
		local p = rawget(o, "_props")
		if p.CFrame and o:IsA("BasePart") then
			local delta = cf * p.CFrame:Inverse()
			p.CFrame = cf
			moveTree(o, delta)
			return
		end
		local cur = modelPivot(o)
		moveTree(o, cf * cur:Inverse())
		p.WorldPivot = cf
	end,
	GetPivot = function(o)
		return modelPivot(o)
	end,
	MoveTo = function(o, pos)
		local cur = modelPivot(o)
		local delta = CFrame.new(pos - cur.Position)
		moveTree(o, delta)
	end,
	TranslateBy = function(o, v)
		moveTree(o, CFrame.new(v))
	end,
	SetPrimaryPartCFrame = function(o, cf)
		local cur = modelPivot(o)
		moveTree(o, cf * cur:Inverse())
	end,
	GetBoundingBox = function(o)
		return bbox(o)
	end,
	GetExtentsSize = function(o)
		local _, s = bbox(o)
		return s
	end,
	ScaleTo = function() end, GetScale = function()
		return 1
	end,
	SetNetworkOwner = function() end, BreakJoints = function() end, Play = function() end, Stop = function() end,
	Pause = function() end, Resume = function() end, Emit = function() end, Clear = function() end,
	Fire = function() end, FireClient = function() end, FireAllClients = function() end, FireServer = function() end,
	InvokeServer = function() end, LoadAnimation = function()
		return { Play = function() end, Stop = function() end, AdjustSpeed = function() end, Stopped = Signal() }
	end,
	GetMass = function()
		return 1
	end,
	GetTouchingParts = function()
		return {}
	end,
	ApplyImpulse = function() end, ApplyAngularImpulse = function() end,
	AddTag = function(o, t)
		E.CollectionService:AddTag(o, t)
	end,
	RemoveTag = function(o, t)
		E.CollectionService:RemoveTag(o, t)
	end,
	HasTag = function(o, t)
		return E.CollectionService:HasTag(o, t)
	end,
	GetTags = function(o)
		return E.CollectionService:GetTags(o)
	end,
	GetFullName = nil,
	Resize = function() end, SetTextureId = function() end,
	GetChildrenOfClass = nil,
	CaptureFocus = function() end,
	TweenPosition = function() end, TweenSize = function() end,
	GetTextSize = function()
		return roblox.Vector2.new(10, 10)
	end,
}
local DEFAULTS = {
	AbsoluteSize = function()
		return roblox.Vector2.new(1280, 720)
	end,
	AbsolutePosition = function()
		return roblox.Vector2.new(0, 0)
	end,
	TextBounds = function()
		return roblox.Vector2.new(40, 14)
	end,
	Size = function(o)
		if o:IsA("BasePart") then
			return Vector3.new(4, 1, 2)
		end
		return nil
	end,
}
E.lazyGet = function(o, k)
	if SIGNALS[k] or (type(k) == "string" and k:match("Changed$")) then
		local sigs = rawget(o, "_sigs")
		if not sigs then
			sigs = {}
			rawset(o, "_sigs", sigs)
		end
		sigs[k] = sigs[k] or Signal()
		return sigs[k]
	end
	local m = METHODS[k]
	if m then
		return m
	end
	local d = DEFAULTS[k]
	if d then
		return d(o)
	end
	return nil
end
E.workspace.Terrain = E.new("Terrain")
rawget(E.workspace, "_props").Gravity = 196.2
rawget(E.workspace, "_props").DistributedGameTime = 0
rawget(E.workspace, "_props").Raycast = function()
	return nil
end
rawget(E.workspace, "_props").GetPartBoundsInBox = function()
	return {}
end
rawget(E.workspace, "_props").GetServerTimeNow = function()
	return os.clock()
end
E.camera.FieldOfView = 70
E.camera.ViewportSize = roblox.Vector2.new(1280, 720)

-- (the engine truncates UDim offsets to integers; lune's UDim2 refuses fractions)
local RU = roblox.UDim2
local function io(x)
	return math.floor((tonumber(x) or 0) + 0.5)
end
local UDim2 = setmetatable({
	new = function(a, b, c, d)
		if typeof(a) == "UDim" then
			return RU.new(a, b)
		end
		return RU.new(a or 0, io(b), c or 0, io(d))
	end,
	fromOffset = function(x, y)
		return RU.fromOffset(io(x), io(y))
	end,
	fromScale = function(x, y)
		return RU.fromScale(x or 0, y or 0)
	end,
}, { __index = RU })
local RUD = roblox.UDim
local UDim = setmetatable({ new = function(s, o)
	return RUD.new(s or 0, io(o))
end }, { __index = RUD })

local TweenInfo = { new = function(time, style, dir, rep, rev, delay)
	return { Time = time or 1, EasingStyle = style, EasingDirection = dir, RepeatCount = rep or 0, Reverses = rev or false, DelayTime = delay or 0 }
end }
-- typeof: fakeengine instances (and the host's module nodes) are Instances, as the game code expects
local luneTypeof = typeof
local function worldTypeof(v)
	if type(v) == "table" and (E.IsInstance(v) or rawget(v, "_class") ~= nil or rawget(v, "ClassName") ~= nil) then
		return "Instance"
	end
	return luneTypeof(v)
end
-- (RaycastParams: VenueFX's follow spots build one for their floor-pool rays)
local RaycastParams = { new = function()
	return { FilterDescendantsInstances = {}, FilterType = nil, IgnoreWater = true }
end }
local H = Host.new({ globals = { Instance = E.Instance, workspace = E.workspace, Workspace = E.workspace, UDim2 = UDim2, UDim = UDim, TweenInfo = TweenInfo, typeof = worldTypeof, RaycastParams = RaycastParams }, src = args.src })

-- services as fakeengine instances (they hold real children); the host's GetService finds game._kids first
local function svc(name, props)
	local s = E.new(name)
	s.Name = name
	for k, v in pairs(props or {}) do
		rawget(s, "_props")[k] = v
	end
	H.game._kids[name] = s
	return s
end
local CS = E.CollectionService
local methodsFind = E.workspace.FindFirstChild
H.game._kids.Workspace = E.workspace
svc("Lighting", { ClockTime = 14 })
svc("ServerStorage")
svc("SoundService")
svc("Debris", { AddItem = function() end })
svc("TweenService", {
	Create = function(_, inst, _info, goal)
		local tw = { Completed = Signal() }
		function tw.Play()
			for k, v in pairs(goal or {}) do
				pcall(function()
					inst[k] = v
				end)
			end
			tw.Completed:Fire(Enum and nil)
		end
		function tw.Cancel() end
		function tw.Pause() end
		function tw.Destroy() end
		return tw
	end,
})
svc("ContentProvider", { PreloadAsync = function() end })
svc("TextService", { GetTextSize = function()
	return roblox.Vector2.new(10, 10)
end })
svc("UserInputService", { TouchEnabled = false, KeyboardEnabled = true, GamepadEnabled = false, InputBegan = Signal(), InputEnded = Signal(), InputChanged = Signal(), LastInputTypeChanged = Signal(), GetLastInputType = function()
	return roblox.Enum.UserInputType.Keyboard
end, GetConnectedGamepads = function()
	return {}
end })
svc("GuiService", {})
svc("MaterialService", {})
svc("PhysicsService", { RegisterCollisionGroup = function() end, CollisionGroupSetCollidable = function() end, IsCollisionGroupRegistered = function()
	return true
end })
svc("StarterGui", { SetCoreGuiEnabled = function() end, SetCore = function() end })
svc("AssetService", {})
svc("ContextActionService", { BindAction = function() end, UnbindAction = function() end })
svc("HapticService", {})
svc("Teams", {})
svc("Chat", {})
svc("TextChatService", {})
svc("ProximityPromptService", { PromptTriggered = Signal(), PromptShown = Signal() })
svc("BadgeService", {})
svc("MarketplaceService", {})
H.Service("CollectionService")._props = CS
local localPlayer = E.new("Player")
localPlayer.Name = "LocalPlayer"
localPlayer.UserId = 1
local pg = E.new("PlayerGui", localPlayer)
pg.Name = "PlayerGui"
H.Service("Players")._props = {
	LocalPlayer = localPlayer, PlayerAdded = Signal(), PlayerRemoving = Signal(),
	GetPlayers = function()
		return {}
	end,
	GetPlayerFromCharacter = function()
		return nil
	end,
}
local rs = H.Service("RunService")._props
rs.Heartbeat, rs.RenderStepped, rs.Stepped = E.Heartbeat, E.RenderStepped, Signal()
rs.PreSimulation, rs.PostSimulation, rs.PreRender = Signal(), Signal(), Signal()
rs.IsServer = function()
	return true
end
rs.IsClient = function()
	return true
end
H.game._props.IsLoaded = function()
	return true
end
H.game._props.Loaded = Signal()
H.game._props.BindToClose = function() end
-- host nodes (ReplicatedStorage and the module folders) take fakeengine children
for _, n in ipairs({ H.Service("ReplicatedStorage"), H.shared, H.client }) do
	rawset(n, "ChildAdded", Signal())
	rawset(n, "ChildRemoved", Signal())
	rawset(n, "DescendantAdded", Signal())
end

-- ReplicatedStorage.Remotes: any remote asked for exists (a RemoteEvent / RemoteFunction that does nothing)
do
	local remotes = E.new("Folder")
	remotes.Name = "Remotes"
	local function get(o, name)
		local c = methodsFind(o, name)
		if c then
			return c
		end
		c = E.new(name:match("Fn$") and "RemoteFunction" or "RemoteEvent")
		c.Name = name
		c.Parent = o
		return c
	end
	rawset(remotes, "WaitForChild", get)
	rawset(remotes, "FindFirstChild", get)
	local RS = H.Service("ReplicatedStorage")
	RS._kids.Remotes = remotes
	table.insert(RS._order, remotes)
end

-- the graphics level for the client modules (Perf reads the player attribute / its own detection)
localPlayer:SetAttribute("GfxLevel", LEVEL)

-- src/server as ServerScriptService.BoxerModules
local srcDir = H.src
local SSS = H.Service("ServerScriptService")
local BM = Host.NewNode("BoxerModules", "Folder", SSS)
for _, f in ipairs(fs.readDir(srcDir .. "/server")) do
	local base = f:match("^(.-)%.lua$")
	if base and not f:match("%.server%.lua$") then
		local n = Host.NewNode(base, "ModuleScript", BM)
		rawset(n, "_file", srcDir .. "/server/" .. f)
		if not H.files[base] then
			H.files[base] = n
		end
	end
end
local function requireServer(name)
	return H.requireNode(BM._kids[name])
end

-- Perf pinned to LEVEL (the real module measures fps)
local function pinPerf()
	local ok, Perf = pcall(H.require, "Client/Perf")
	if ok and type(Perf) == "table" then
		Perf.Level = function()
			return LEVEL
		end
		Perf.AtLeast = function(n)
			return LEVEL >= n
		end
		Perf.Pick = function(lo, me, hi)
			return LEVEL == 1 and lo or (LEVEL == 2 and me or hi)
		end
		Perf.Name = function(l)
			return ({ "Low", "Medium", "High" })[l or LEVEL]
		end
		Perf.OnChanged = Perf.OnChanged or function() end
	end
end
pinPerf()

------------------------------------------------------------------------
-- dump
------------------------------------------------------------------------
local function rgb(c)
	return c and { math.floor(c.R * 1000 + 0.5) / 1000, math.floor(c.G * 1000 + 0.5) / 1000, math.floor(c.B * 1000 + 0.5) / 1000 } or nil
end
local function r3(x)
	return math.floor(x * 1000 + 0.5) / 1000
end
local function cfArr(cf)
	local c = { cf:GetComponents() }
	for i = 1, 12 do
		c[i] = r3(c[i])
	end
	return c
end
local function enumName(v)
	if v == nil then
		return nil
	end
	local s = tostring(v)
	return s:match("([^%.]+)$")
end
local function visible(o, stop)
	local p = o
	while p and p ~= stop do
		if rawget(p, "_parent") == nil and p ~= stop then
			return false
		end
		p = rawget(p, "_parent")
	end
	return true
end

local function gui2d(sg, part)
	-- the face's size in studs, CanvasSize from PixelsPerStud
	local face = enumName(sg.Face) or "Front"
	local s = part.Size
	local fw, fh
	if face == "Front" or face == "Back" then
		fw, fh = s.X, s.Y
	elseif face == "Left" or face == "Right" then
		fw, fh = s.Z, s.Y
	else
		fw, fh = s.X, s.Z
	end
	local pps = sg.PixelsPerStud or 50
	local canvas
	if sg.SizingMode and enumName(sg.SizingMode) == "FixedSize" and sg.CanvasSize then
		canvas = { sg.CanvasSize.X, sg.CanvasSize.Y }
	else
		canvas = { fw * pps, fh * pps }
	end
	local items = {}
	local function walk(o, ax, ay, aw, ah, depth)
		for _, c in ipairs(o:GetChildren()) do
			if c:IsA("GuiObject") and c.Visible ~= false then
				local sz, pos = c.Size, c.Position
				local w = sz and (sz.X.Scale * aw + sz.X.Offset) or aw
				local h = sz and (sz.Y.Scale * ah + sz.Y.Offset) or ah
				local ap = c.AnchorPoint
				local x = ax + (pos and (pos.X.Scale * aw + pos.X.Offset) or 0) - (ap and ap.X * w or 0)
				local y = ay + (pos and (pos.Y.Scale * ah + pos.Y.Offset) or 0) - (ap and ap.Y * h or 0)
				local bt = c.BackgroundTransparency or 0
				local it = {
					x = r3(x / canvas[1]), y = r3(y / canvas[2]), w = r3(w / canvas[1]), h = r3(h / canvas[2]),
					bg = rgb(c.BackgroundColor3 or Color3.new(1, 1, 1)), bt = r3(bt), z = depth,
				}
				if c.Text ~= nil and (c:IsA("TextLabel") or c:IsA("TextButton")) then
					it.text = tostring(c.Text)
					it.tc = rgb(c.TextColor3 or Color3.new(0, 0, 0))
					it.tt = r3(c.TextTransparency or 0)
					it.ts = c.TextScaled and 0 or (c.TextSize or 14) / canvas[2]
					it.font = enumName(c.Font)
					-- a FontFace (Shared.Typography) names its family: "Bangers", "Montserrat", "Oswald"...
					local ff = c.FontFace
					if ff ~= nil and tostring(ff.Family or ""):find("families/") then
						it.font = tostring(ff.Family):match("families/([%w_]+)%.json") or it.font
						it.wt = tostring(ff.Weight or ""):match("(%a+)$")
					end
				end
				if c:IsA("ImageLabel") then
					it.img = tostring(c.Image or "")
					it.ic = rgb(c.ImageColor3 or Color3.new(1, 1, 1))
					it.it = r3(c.ImageTransparency or 0)
					if c.ImageRectSize and c.ImageRectSize.X > 0 then
						it.rect = { c.ImageRectOffset.X, c.ImageRectOffset.Y, c.ImageRectSize.X, c.ImageRectSize.Y }
					end
				end
				local grad = c:FindFirstChildOfClass("UIGradient")
				if grad and grad.Color then
					local ok, kps = pcall(function()
						return grad.Color.Keypoints
					end)
					if ok and kps then
						it.grad = {}
						for _, kp in ipairs(kps) do
							table.insert(it.grad, { r3(kp.Time), rgb(kp.Value) })
						end
						it.grot = grad.Rotation or 0
					end
				end
				table.insert(items, it)
				walk(c, x, y, w, h, depth + 1)
			end
		end
	end
	walk(sg, 0, 0, canvas[1], canvas[2], 0)
	return face, items
end

local function dumpRoot(root)
	local out = { parts = {}, lights = {}, guis = {}, decals = {}, beams = {} }
	local counts = { instances = 0, parts = 0, meshparts = 0, lights = 0, guis = 0, decals = 0, beams = 0, particles = 0, models = 0 }
	-- the performance flags (unset = the engine default: unanchored, collides, queries, touches, casts a shadow)
	local perf = { shadowLights = 0, onLights = 0, casters = 0, smallCasters = 0, unanchored = 0, collide = 0, query = 0, touch = 0 }
	counts.perf = perf
	local index = {}
	local list = root:GetDescendants()
	for _, o in ipairs(list) do
		counts.instances += 1
		if o:IsA("BasePart") then
			counts.parts += 1
			if o.Anchored ~= true then
				perf.unanchored += 1
			end
			if o.CanCollide ~= false then
				perf.collide += 1
			end
			if o.CanQuery ~= false then
				perf.query += 1
			end
			if o.CanTouch ~= false then
				perf.touch += 1
			end
			if o.CastShadow ~= false and (o.Transparency or 0) < 1 then
				perf.casters += 1
				local sz = o.Size
				if sz and math.max(sz.X, sz.Y, sz.Z) < 2 then
					perf.smallCasters += 1
				end
			end
			if o.ClassName == "MeshPart" then
				counts.meshparts += 1
			end
			local mesh = o:FindFirstChildOfClass("SpecialMesh")
			local it = {
				c = o.ClassName, s = { r3(o.Size.X), r3(o.Size.Y), r3(o.Size.Z) }, cf = cfArr(o.CFrame), col = rgb(o.Color or Color3.new(0.64, 0.64, 0.64)),
				m = enumName(o.Material) or "Plastic", t = r3(math.max(o.Transparency or 0, 0)), sh = enumName(o.Shape) or "Block",
				refl = r3(o.Reflectance or 0), n = o.Name,
			}
			if o.CanCollide ~= nil then
				it.cc = o.CanCollide
			end
			if o.CanQuery ~= nil then
				it.cq = o.CanQuery
			end
			if o.CanTouch ~= nil then
				it.ct = o.CanTouch
			end
			if o.CastShadow == false then
				it.ns = true
			end
			local tg = CS:GetTags(o)
			if #tg > 0 then
				it.tg = tg
			end
			if o.ClassName == "WedgePart" then
				it.sh = "Wedge"
			elseif o.ClassName == "CornerWedgePart" then
				it.sh = "CornerWedge"
			elseif o.ClassName == "TrussPart" then
				it.sh = "Block"
			end
			if mesh then
				it.mesh = {
					k = enumName(mesh.MeshType) or "Brick", s = mesh.Scale and { r3(mesh.Scale.X), r3(mesh.Scale.Y), r3(mesh.Scale.Z) } or { 1, 1, 1 },
					o = mesh.Offset and { r3(mesh.Offset.X), r3(mesh.Offset.Y), r3(mesh.Offset.Z) } or { 0, 0, 0 },
				}
			end
			table.insert(out.parts, it)
			index[o] = #out.parts
		elseif o:IsA("Model") then
			counts.models += 1
		end
	end
	for _, o in ipairs(list) do
		local cls = o.ClassName
		if cls == "PointLight" or cls == "SpotLight" or cls == "SurfaceLight" then
			counts.lights += 1
			if o.Enabled ~= false then
				perf.onLights += 1
				if o.Shadows == true then
					perf.shadowLights += 1
				end
			end
			local p = rawget(o, "_parent")
			if p and index[p] then
				local pp = p
				table.insert(out.lights, {
					k = cls, part = index[pp], col = rgb(o.Color or Color3.new(1, 1, 1)), b = r3(o.Brightness or 1), r = r3(o.Range or 8),
					a = r3(o.Angle or 90), face = enumName(o.Face) or "Front", on = o.Enabled ~= false, sh = o.Shadows == true,
					tg = CS:GetTags(o),
				})
			end
		elseif cls == "SurfaceGui" then
			counts.guis += 1
			local p = o.Adornee or rawget(o, "_parent")
			if p and index[p] and o.Enabled ~= false then
				local face, items = gui2d(o, p)
				table.insert(out.guis, { part = index[p], face = face, items = items, light = r3(o.LightInfluence or 1), bright = r3(o.Brightness or 1) })
			end
		elseif cls == "Decal" or cls == "Texture" then
			counts.decals += 1
			local p = rawget(o, "_parent")
			if p and index[p] then
				table.insert(out.decals, { part = index[p], face = enumName(o.Face) or "Front", tex = tostring(o.Texture or ""), col = rgb(o.Color3 or Color3.new(1, 1, 1)), t = r3(o.Transparency or 0), k = cls, su = o.StudsPerTileU, sv = o.StudsPerTileV })
			end
		elseif cls == "Beam" then
			counts.beams += 1
			local a0, a1 = o.Attachment0, o.Attachment1
			local function wpos(a)
				if not a then
					return nil
				end
				local pp = rawget(a, "_parent")
				local lcf = a.CFrame or (a.Position and CFrame.new(a.Position)) or CFrame.new()
				if pp and pp:IsA("BasePart") then
					return (pp.CFrame * lcf).Position
				end
				return a.WorldPosition
			end
			local p0, p1 = wpos(a0), wpos(a1)
			if p0 and p1 and o.Enabled ~= false then
				local col = Color3.new(1, 1, 1)
				pcall(function()
					col = o.Color.Keypoints[1].Value
				end)
				local tr = 0
				pcall(function()
					tr = o.Transparency.Keypoints[1].Value
				end)
				table.insert(out.beams, { a = { r3(p0.X), r3(p0.Y), r3(p0.Z) }, b = { r3(p1.X), r3(p1.Y), r3(p1.Z) }, w = r3(o.Width0 or 1), col = rgb(col), t = r3(tr), glow = r3(o.LightEmission or 0), seg = o.Segments, c0 = o.CurveSize0, c1 = o.CurveSize1 })
			end
		elseif cls == "ParticleEmitter" then
			counts.particles += 1
		end
	end
	return out, counts
end

------------------------------------------------------------------------
-- build
------------------------------------------------------------------------
local scene = { roots = {}, counts = {}, level = LEVEL, cameras = {} }
local function record(name, root)
	if not root then
		return
	end
	local d, c = dumpRoot(root)
	scene.roots[name] = d
	scene.counts[name] = c
	print(string.format("%-18s instances %6d  parts %6d  lights %4d  guis %4d  decals %4d  beams %4d  particles %3d", name, c.instances, c.parts, c.lights, c.guis, c.decals, c.beams, c.particles))
	local pf = c.perf
	print(string.format("%-18s perf: lights on %d (shadowed %d)  shadow casters %d (small %d)  unanchored %d  collide %d  query %d  touch %d", "", pf.onLights, pf.shadowLights, pf.casters, pf.smallCasters, pf.unanchored, pf.collide, pf.query, pf.touch))
end

local function try(label, fn, ...)
	local ok, res = pcall(fn, ...)
	if not ok then
		print("[world_scene] " .. label .. " failed: " .. tostring(res))
	end
	return ok, res
end

-- a profile good enough for the client dressing (State.P shape)
local function profile(lv)
	local Config = H.require("Config")
	local levels, cond = {}, {}
	for _, st in ipairs(Config.Stations or {}) do
		levels[st.id] = lv
		cond[st.id] = 80
	end
	for _, k in ipairs({ "pool", "ring", "bag", "speedbag", "doubleend", "bench", "squat", "treadmill", "bike", "rower", "ropes", "medball", "icebath", "sauna", "massage", "chamber", "mirror", "dumbbells", "pullup" }) do
		levels[k] = levels[k] or lv
		cond[k] = cond[k] or 80
	end
	return {
		created = true, name = "Preview", nick = "Preview", gym = { levels = levels, cond = cond }, owned = {}, tier = 1,
		record = { w = 12, l = 1, d = 0, ko = 8 }, money = 50000, popularity = 40, fame = 40, belts = {}, cars = {}, homes = {},
		sponsors = {}, history = {}, stats = {}, legacy = {}, titles = {},
	}
end

-- the Lighting service as the server left it (Config.Lighting through MapBuilder): the properties, the
-- post effects / Atmosphere / Sky by name, plus Config.Lighting.Night for the night views. The renderer
-- (world_render.py) derives its sun, sky, fills, exposure and compositor grade from these.
local function dumpLighting()
	local L = H.game._kids.Lighting
	local out = { props = {}, children = {}, night = {} }
	for _, k in ipairs({ "ClockTime", "Brightness", "ExposureCompensation", "GeographicLatitude", "ShadowSoftness", "EnvironmentDiffuseScale", "EnvironmentSpecularScale" }) do
		local v = L[k]
		if type(v) == "number" then
			out.props[k] = r3(v)
		end
	end
	for _, k in ipairs({ "Ambient", "OutdoorAmbient", "ColorShift_Top", "ColorShift_Bottom" }) do
		local v = L[k]
		if typeof(v) == "Color3" then
			out.props[k] = rgb(v)
		end
	end
	for _, c in ipairs(L:GetChildren()) do
		local e = { class = c.ClassName }
		for k, v in pairs(rawget(c, "_props") or {}) do
			if type(v) == "number" or type(v) == "boolean" then
				e[k] = v
			elseif typeof(v) == "Color3" then
				e[k] = rgb(v)
			end
		end
		out.children[c.Name] = e
	end
	local okC, Config = pcall(H.require, "Config")
	if okC and type(Config) == "table" and Config.Lighting then
		for k, v in pairs(Config.Lighting.Night or {}) do
			out.night[k] = type(v) == "table" and { v[1] / 255, v[2] / 255, v[3] / 255 } or v
		end
	end
	return out
end

local gymRoot
if ONLY.gym or ONLY.city then
	local MapBuilder = requireServer("MapBuilder")
	local ok = try("MapBuilder.BuildGym", MapBuilder.BuildGym)
	gymRoot = E.workspace:FindFirstChild("Gym")
	local okL, lighting = pcall(dumpLighting)
	if okL then
		scene.lighting = lighting
	else
		print("[world_scene] lighting dump failed: " .. tostring(lighting))
	end
	if ok and gymRoot then
		-- client gym dressing
		if ONLY.gym then
			local okG, GV = pcall(H.require, "Client/GymVisuals")
			if okG then
				try("GymVisuals.Refresh", GV.Refresh, profile(tonumber(args.gymlevel) or 3))
			else
				print("[world_scene] GymVisuals failed to load: " .. tostring(GV))
			end
		end
		if ONLY.city then
			local okC, CV = pcall(H.require, "Client/CityVisuals")
			if okC then
				try("CityVisuals.Refresh", CV.Refresh, profile(3))
			else
				print("[world_scene] CityVisuals failed to load: " .. tostring(CV))
			end
		end
		local okD, WD = pcall(H.require, "Client/WorldDetail")
		if okD and type(WD) == "table" and WD.BuildAll then
			try("WorldDetail.BuildAll", WD.BuildAll, { level = LEVEL, everywhere = true })
		elseif not okD and not tostring(WD):find("no module") and not tostring(WD):find("assertion") then
			print("[world_scene] WorldDetail failed to load: " .. tostring(WD))
		end
		-- split the server folder into the gym and the city for counting
		local gymF, cityF = E.new("Folder"), E.new("Folder")
		local city = gymRoot:FindFirstChild("City")
		record("server_gym_and_city", gymRoot)
		if city then
			record("server_city", city)
		end
		for _, n in ipairs({ "LocalGym", "LocalCity" }) do
			local f = E.workspace:FindFirstChild(n)
			if f then
				record(n, f)
			end
		end
		local wd = E.workspace:FindFirstChild("WorldDetail")
		if wd then
			for _, pair in ipairs({ { "Gym", "WorldDetail_gym" }, { "City", "WorldDetail_city" } }) do
				local f = wd:FindFirstChild(pair[1])
				if f then
					record(pair[2], f)
					-- parts per cell tier (the streamer builds one tier at a time: the biggest is the worst hitch)
					scene.cells = scene.cells or {}
					for _, tier in ipairs(f:GetChildren()) do
						local n = 0
						for _, d in ipairs(tier:GetDescendants()) do
							if d:IsA("BasePart") then
								n += 1
							end
						end
						scene.cells[tier.Name] = n
					end
				end
			end
		end
		local _ = gymF and cityF
	end
end

if ONLY.venues then
	local Venues = requireServer("Venues")
	try("Venues.BuildTemplates", Venues.BuildTemplates)
	-- the venue geometry both sides use (test_worlddetail checks VenueDetail's mirror of it)
	scene.venueSpecs = {}
	local FIELDS = { "tier", "size", "height", "roof", "half", "ringH", "rows", "rowStart", "rowGap", "rowRise", "rigY" }
	local okVD0, VD0 = pcall(H.require, "Client/VenueDetail")
	for kind, sp in pairs(Venues.Specs or {}) do
		local row = { server = {}, client = {} }
		local csp = okVD0 and type(VD0) == "table" and VD0.Specs and VD0.Specs[kind] or nil
		for _, f in ipairs(FIELDS) do
			row.server[f] = sp[f]
			row.client[f] = csp and csp[f]
		end
		row.hasClient = csp ~= nil
		scene.venueSpecs[kind] = row
	end
	local kinds = { "CommunityCenter", "ClubArena", "Arena", "Stadium", "Gym" }
	local okFX, VenueFX = pcall(H.require, "Client/VenueFX")
	local okVD, VD = pcall(H.require, "Client/VenueDetail")
	for i, kind in ipairs(kinds) do
		local ok, arena = pcall(Venues.New, kind, { stakes = i >= 3 and "title" or "regular", importance = i / 4, popularity = 20 * i, kind = "fight", playerNick = "PREVIEW" })
		if ok and arena then
			arena.Parent = E.workspace
			local detail
			if okVD and type(VD) == "table" and VD.Build then
				local okB, res = try("VenueDetail.Build " .. kind, VD.Build, arena, { venue = kind, level = LEVEL })
				detail = okB and res or nil
			elseif not okVD and not tostring(VD):find("assertion") then
				print("[world_scene] VenueDetail failed to load: " .. tostring(VD))
			end
			if detail then
				detail.Parent = nil
			end
			record("venue_" .. kind, arena)
			if detail then
				detail.Parent = arena
				record("VenueDetail_" .. kind, detail)
			end
			local center = arena:FindFirstChild("Anchors") and arena.Anchors:FindFirstChild("RingCenter")
			scene.cameras["venue_" .. kind] = center and cfArr(center.CFrame) or nil
			-- the Arena on a world title night with VenueFX's show rig running (its client-local lights,
			-- apron LEDs, corner glows, fascia trims; the spots in their entrance gels): root VenueFX_Arena
			if kind == "Arena" and okFX and type(VenueFX) == "table" and VenueFX.Start then
				local okS, errS = pcall(VenueFX.Start, arena, {
					venue = kind, venueName = "WCB GRAND ARENA", stakes = { "WBC", "WBA" }, kind = "fight", rounds = 12,
					tape = { you = { name = "PREVIEW", nick = "THE PREVIEW", record = { w = 20, l = 0, d = 0, ko = 15 } }, opp = { name = "RIVAL", record = { w = 18, l = 2, d = 0, ko = 10 } } },
				})
				if okS then
					pcall(VenueFX.Phase, "entrance", { who = "you", corner = "Red" })
					for _ = 1, 12 do
						pcall(E.Heartbeat.Fire, E.Heartbeat, 0.1)
					end
					local fx = E.workspace:FindFirstChild("VenueFX_Local")
					if fx then
						record("VenueFX_Arena", fx)
					end
					-- the arena again as VenueFX left it (the keys, the spots' gels, the house tints)
					record("venue_Arena_show", arena)
					pcall(VenueFX.Stop)
					-- and a regular card's walkout (no belts: red / blue promotion colours, the spots sweeping
					-- the house in their coloured gels): roots venue_Arena_card + VenueFX_ArenaCard
					local okC, errC = pcall(VenueFX.Start, arena, {
						venue = kind, venueName = "WCB GRAND ARENA", stakes = {}, kind = "fight", rounds = 10,
						tape = { you = { name = "PREVIEW", nick = "THE PREVIEW", record = { w = 12, l = 1, d = 0, ko = 8 } }, opp = { name = "RIVAL", record = { w = 11, l = 3, d = 0, ko = 6 } } },
					})
					if okC then
						pcall(VenueFX.Phase, "entrance", { who = "you", corner = "Red" })
						for _ = 1, 12 do
							pcall(E.Heartbeat.Fire, E.Heartbeat, 0.1)
						end
						local fx2 = E.workspace:FindFirstChild("VenueFX_Local")
						if fx2 then
							record("VenueFX_ArenaCard", fx2)
						end
						record("venue_Arena_card", arena)
						pcall(VenueFX.Stop)
					else
						print("[world_scene] VenueFX.Start (regular card preview) failed: " .. tostring(errC))
					end
				else
					print("[world_scene] VenueFX.Start (preview) failed: " .. tostring(errS))
				end
			end
		else
			print("[world_scene] Venues.New " .. kind .. " failed: " .. tostring(arena))
		end
	end
	-- the fight-night lighting per venue (VenueFX.Profiles: what VenueFX.Start sets on Lighting)
	if okFX and type(VenueFX) == "table" and type(VenueFX.Profiles) == "table" then
		scene.venueLighting = {}
		for kind, prof in pairs(VenueFX.Profiles) do
			local row = {}
			for k, v in pairs(prof) do
				if type(v) == "number" or type(v) == "boolean" then
					row[k] = v
				elseif typeof(v) == "Color3" then
					row[k] = rgb(v)
				end
			end
			scene.venueLighting[kind] = row
		end
	end
end

if ONLY.menu then
	local okM, MenuStage = pcall(H.require, "Client/MenuStage")
	if okM then
		local name = ({ "Low", "Medium", "High" })[LEVEL]
		local ok, st = pcall(MenuStage.Build, name)
		if ok and st and st.folder then
			-- (previews only) a grey stand-in where the menu clones your boxer, for the framing
			if args.standin ~= "0" then
				local mk = st.mark
				local function sp(name, size, cf)
					local p = E.new("Part", st.folder)
					p.Name = name
					p.Size = size
					p.CFrame = mk * cf
					p.Color = Color3.fromRGB(150, 140, 132)
					p.Material = roblox.Enum.Material.SmoothPlastic
				end
				sp("StandInLegs", Vector3.new(1.6, 3.0, 0.9), CFrame.new(0, 1.5, 0))
				sp("StandInTorso", Vector3.new(2.0, 2.4, 1.0), CFrame.new(0, 4.2, 0))
				sp("StandInHead", Vector3.new(1.1, 1.2, 1.1), CFrame.new(0, 6.1, 0))
				sp("StandInArmL", Vector3.new(0.6, 2.2, 0.6), CFrame.new(-1.4, 4.4, -0.6) * CFrame.Angles(math.rad(-60), 0, 0))
				sp("StandInArmR", Vector3.new(0.6, 2.2, 0.6), CFrame.new(1.4, 4.4, -0.6) * CFrame.Angles(math.rad(-60), 0, 0))
			end
			record("menu", st.folder)
			local okS, cf, fov = pcall(MenuStage.Shot, st, "main", 0)
			if okS and cf then
				scene.cameras.menu = { cf = cfArr(cf), fov = fov }
			end
			scene.cameras.menu_origin = cfArr(CFrame.new(MenuStage.Origin))
		else
			print("[world_scene] MenuStage.Build failed: " .. tostring(st))
		end
	else
		print("[world_scene] MenuStage failed to load: " .. tostring(MenuStage))
	end
end

-- named sites (camera targets)
do
	local okC, CityMap = pcall(requireServer, "CityMap")
	if okC and CityMap.Sites then
		scene.sites = {}
		for k, cf in pairs(CityMap.Sites) do
			scene.sites[k] = cfArr(cf)
		end
	end
end

if not args.counts then
	fs.writeDir(OUT)
	fs.writeFile(OUT .. "/scene.json", serde.encode("json", scene))
	print("wrote " .. OUT .. "/scene.json")
end
fs.writeFile(OUT .. "_counts_L" .. LEVEL .. ".json", serde.encode("json", scene.counts, true))
