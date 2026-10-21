--!nocheck
-- fakeengine.luau: just enough of the Roblox engine to run AnatomyClient's scheduler and worker under lune:
-- Instances with a real hierarchy (Parent / children, FindFirstChild, IsA by class, attributes and their
-- changed signals, AncestryChanged / DescendantAdded / Destroying, Destroy), firing signals, a CollectionService
-- with tags, a RunService whose Heartbeat the test steps, and a camera. Properties are plain fields (anything
-- unknown reads nil). No physics, no rendering: a Weld is a record of Part0 / Part1 / C0 / C1.
--
--   local FE = require("./fakeengine")
--   local E = FE.new()
--   local H = Host.new({ globals = { Instance = E.Instance, workspace = E.workspace, Workspace = E.workspace } })
--   E.install(H)                                  -- RunService / CollectionService / Players / Workspace services
--   E.step(n)                                     -- n frames: Heartbeat fired, then task.wait()
local roblox = require("@lune/roblox")
local ltask = require("@lune/task")

local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local FE = {}

-- class -> its superclasses (IsA)
local SUPER = {
	Part = { "BasePart", "PVInstance" }, MeshPart = { "BasePart", "PVInstance" }, BasePart = { "PVInstance" },
	Model = { "PVInstance" }, Folder = {}, Weld = { "JointInstance" }, Motor6D = { "JointInstance" },
	Humanoid = {}, Decal = {}, SurfaceGui = { "LayerCollector" }, BillboardGui = { "LayerCollector" },
	Animator = {}, LocalScript = { "BaseScript", "LuaSourceContainer" }, Script = { "BaseScript", "LuaSourceContainer" },
	Workspace = { "Model", "PVInstance" }, Camera = {},
	-- 2D GUI (guisim lays these out)
	ScreenGui = { "LayerCollector", "GuiBase2d" }, LayerCollector = { "GuiBase2d" },
	GuiObject = { "GuiBase2d" }, GuiButton = { "GuiObject", "GuiBase2d" },
	Frame = { "GuiObject", "GuiBase2d" }, ScrollingFrame = { "GuiObject", "GuiBase2d" }, CanvasGroup = { "GuiObject", "GuiBase2d" },
	ViewportFrame = { "GuiObject", "GuiBase2d" }, VideoFrame = { "GuiObject", "GuiBase2d" },
	TextLabel = { "GuiObject", "GuiBase2d" }, ImageLabel = { "GuiObject", "GuiBase2d" }, TextBox = { "GuiObject", "GuiBase2d" },
	TextButton = { "GuiButton", "GuiObject", "GuiBase2d" }, ImageButton = { "GuiButton", "GuiObject", "GuiBase2d" },
	UIListLayout = { "UIGridStyleLayout", "UILayout", "UIComponent" }, UIGridLayout = { "UIGridStyleLayout", "UILayout", "UIComponent" },
	UIPadding = { "UIComponent" }, UIScale = { "UIComponent" }, UICorner = { "UIComponent" }, UIStroke = { "UIComponent" },
	UIGradient = { "UIComponent" }, UISizeConstraint = { "UIConstraint", "UIComponent" }, UITextSizeConstraint = { "UIConstraint", "UIComponent" },
	UIAspectRatioConstraint = { "UIConstraint", "UIComponent" }, PlayerGui = { "BasePlayerGui" },
}
FE.SUPER = SUPER

FE.Connections = 0 -- live connections on every signal (diagnostics: tools/ui/ui_profile.luau)
-- owner: the instance the signal belongs to; Destroy drops its connections (as the engine does), so a count of
-- live connections after a Destroy is what really leaks (connections on services and module-level signals)
function FE.Signal(owner)
	local handlers = {}
	local sig = {}
	if owner then
		local list = rawget(owner, "_sigs")
		if list then
			table.insert(list, sig)
		end
	end
	function sig:DisconnectAll()
		for c in pairs(handlers) do
			c:Disconnect()
		end
	end
	function sig:Connect(fn)
		local c = { Connected = true }
		handlers[c] = fn
		FE.Connections += 1
		function c:Disconnect()
			if self.Connected then
				FE.Connections -= 1
			end
			self.Connected = false
			handlers[self] = nil
		end
		return c
	end
	function sig:Once(fn)
		local c
		c = sig:Connect(function(...)
			c:Disconnect()
			fn(...)
		end)
		return c
	end
	function sig:Wait()
		local th = coroutine.running()
		sig:Once(function(...)
			ltask.spawn(th, ...)
		end)
		return coroutine.yield()
	end
	function sig:Fire(...)
		local list = {}
		for c, fn in pairs(handlers) do
			list[#list + 1] = { c, fn }
		end
		for _, it in ipairs(list) do
			if it[1].Connected then
				it[2](...)
			end
		end
	end
	function sig:Count()
		local n = 0
		for _ in pairs(handlers) do
			n += 1
		end
		return n
	end
	return sig
end

function FE.new()
	local E = { all = setmetatable({}, { __mode = "k" }) }
	local Signal = FE.Signal
	local Inst = {}
	local methods = {}
	local instSet = E.all

	local function isA(cls, want)
		if cls == want or want == "Instance" then
			return true
		end
		for _, s in ipairs(SUPER[cls] or {}) do
			if s == want or isA(s, want) then
				return true
			end
		end
		return false
	end

	local function new(className, parent)
		local raw = {
			_class = className, _name = className, _kids = {}, _attr = {}, _attrSig = {}, _props = {},
			_parent = nil, _destroyed = false, _sigs = {},
		}
		for _, k in ipairs({ "AncestryChanged", "DescendantAdded", "Destroying", "ChildAdded", "ChildRemoved", "Changed", "AttributeChanged" }) do
			raw[k] = Signal(raw)
		end
		local o = setmetatable(raw, Inst)
		instSet[o] = true
		if className == "Part" or className == "MeshPart" then
			raw._props.CFrame = CFrame.new()
			raw._props.Size = Vector3.new(1, 1, 1)
			raw._props.Transparency = 0
			raw._props.LocalTransparencyModifier = 0
			raw._props.Reflectance = 0
		end
		if parent then
			o.Parent = parent
		end
		return o
	end
	E.new = new

	local function fireDescendantAdded(p, inst)
		local cur = p
		while cur do
			cur.DescendantAdded:Fire(inst)
			cur = rawget(cur, "_parent")
		end
	end
	local function ancestry(inst, parent)
		inst.AncestryChanged:Fire(inst, parent)
		for _, k in ipairs(rawget(inst, "_kids")) do
			ancestry(k, parent)
		end
	end
	local function setParent(o, p)
		local old = rawget(o, "_parent")
		if old == p then
			return
		end
		if rawget(o, "_destroyed") and p ~= nil then
			error("The Parent property of " .. rawget(o, "_name") .. " is locked", 3)
		end
		if old then
			local kids = rawget(old, "_kids")
			local i = table.find(kids, o)
			if i then
				table.remove(kids, i)
			end
			old.ChildRemoved:Fire(o)
		end
		rawset(o, "_parent", p)
		if p then
			table.insert(rawget(p, "_kids"), o)
			p.ChildAdded:Fire(o)
			fireDescendantAdded(p, o)
			for _, d in ipairs(o:GetDescendants()) do
				fireDescendantAdded(p, d)
			end
		end
		ancestry(o, p)
	end

	Inst.__index = function(o, k)
		local m = methods[k]
		if m then
			return m
		end
		if k == "Parent" then
			return rawget(o, "_parent")
		elseif k == "Name" then
			return rawget(o, "_name")
		elseif k == "ClassName" then
			return rawget(o, "_class")
		elseif k == "Position" then
			local cf = rawget(o, "_props").CFrame
			-- (a GUI object's Position is its own UDim2)
			return cf and cf.Position or rawget(o, "_props").Position
		end
		local v = rawget(o, "_props")[k]
		if v ~= nil then
			return v
		end
		-- a child by name (as the engine: instance.Child)
		for _, c in ipairs(rawget(o, "_kids")) do
			if rawget(c, "_name") == k then
				return c
			end
		end
		-- (optional) computed members: E.lazyGet(o, k) (guisim: events, AbsoluteSize, TextBounds)
		local lazy = E.lazyGet
		if lazy then
			return lazy(o, k)
		end
		return nil
	end
	Inst.__newindex = function(o, k, v)
		if k == "Parent" then
			setParent(o, v)
		elseif k == "Name" then
			rawset(o, "_name", v)
		elseif k == "Position" and typeof(v) == "Vector3" then
			-- (as the engine: Position moves the CFrame, its rotation kept)
			local cf = rawget(o, "_props").CFrame
			rawget(o, "_props").CFrame = cf and (CFrame.new(v) * cf.Rotation) or CFrame.new(v)
		else
			rawget(o, "_props")[k] = v
		end
		-- (optional) E.onSet(o, k, v): a property was written (guisim: the layout goes stale)
		local hook = E.onSet
		if hook then
			hook(o, k, v)
		end
	end
	Inst.__tostring = function(o)
		return rawget(o, "_name")
	end

	function methods.IsA(o, cls)
		return isA(rawget(o, "_class"), cls)
	end
	function methods.FindFirstChild(o, name, recursive)
		for _, c in ipairs(rawget(o, "_kids")) do
			if rawget(c, "_name") == name then
				return c
			end
		end
		if recursive then
			for _, c in ipairs(rawget(o, "_kids")) do
				local f = c:FindFirstChild(name, true)
				if f then
					return f
				end
			end
		end
		return nil
	end
	methods.WaitForChild = methods.FindFirstChild
	function methods.FindFirstChildOfClass(o, cls)
		for _, c in ipairs(rawget(o, "_kids")) do
			if rawget(c, "_class") == cls then
				return c
			end
		end
		return nil
	end
	function methods.FindFirstChildWhichIsA(o, cls)
		for _, c in ipairs(rawget(o, "_kids")) do
			if c:IsA(cls) then
				return c
			end
		end
		return nil
	end
	function methods.GetChildren(o)
		return table.clone(rawget(o, "_kids"))
	end
	function methods.GetDescendants(o)
		local out = {}
		local function walk(n)
			for _, c in ipairs(rawget(n, "_kids")) do
				out[#out + 1] = c
				walk(c)
			end
		end
		walk(o)
		return out
	end
	function methods.FindFirstAncestorOfClass(o, cls)
		local p = rawget(o, "_parent")
		while p do
			if rawget(p, "_class") == cls then
				return p
			end
			p = rawget(p, "_parent")
		end
		return nil
	end
	function methods.FindFirstAncestorWhichIsA(o, cls)
		local p = rawget(o, "_parent")
		while p do
			if p:IsA(cls) then
				return p
			end
			p = rawget(p, "_parent")
		end
		return nil
	end
	function methods.FindFirstAncestor(o, name)
		local p = rawget(o, "_parent")
		while p do
			if rawget(p, "_name") == name then
				return p
			end
			p = rawget(p, "_parent")
		end
		return nil
	end
	function methods.IsDescendantOf(o, other)
		local p = rawget(o, "_parent")
		while p do
			if p == other then
				return true
			end
			p = rawget(p, "_parent")
		end
		return false
	end
	function methods.GetFullName(o)
		local names = {}
		local n = o
		while n do
			table.insert(names, 1, rawget(n, "_name"))
			n = rawget(n, "_parent")
		end
		return table.concat(names, ".")
	end
	function methods.GetAttribute(o, k)
		return rawget(o, "_attr")[k]
	end
	function methods.GetAttributes(o)
		return table.clone(rawget(o, "_attr"))
	end
	function methods.SetAttribute(o, k, v)
		local a = rawget(o, "_attr")
		if a[k] == v then
			return
		end
		a[k] = v
		local s = rawget(o, "_attrSig")[k]
		if s then
			s:Fire()
		end
		o.AttributeChanged:Fire(k)
	end
	function methods.GetAttributeChangedSignal(o, k)
		local t = rawget(o, "_attrSig")
		t[k] = t[k] or Signal(o)
		return t[k]
	end
	function methods.GetPropertyChangedSignal(o, _k)
		return Signal(o)
	end
	function methods.GetPivot(o)
		local cf = rawget(o, "_props").CFrame
		if cf then
			return cf
		end
		local pp = rawget(o, "_props").PrimaryPart or o:FindFirstChild("HumanoidRootPart")
		return pp and pp.CFrame or CFrame.new()
	end
	function methods.Destroy(o)
		if rawget(o, "_destroyed") then
			return
		end
		o.Destroying:Fire()
		for _, c in ipairs(table.clone(rawget(o, "_kids"))) do
			c:Destroy()
		end
		setParent(o, nil)
		rawset(o, "_destroyed", true)
		for _, sig in ipairs(rawget(o, "_sigs")) do
			sig:DisconnectAll()
		end
	end
	function methods.ClearAllChildren(o)
		for _, c in ipairs(table.clone(rawget(o, "_kids"))) do
			c:Destroy()
		end
	end
	-- as the engine's Clone: nil for a non-Archivable instance (Archivable = false; unset counts as on), its
	-- non-Archivable descendants left out, and instance references inside the copied tree (a joint's Part0 /
	-- Part1, an ObjectValue) pointed at the copies
	local function copyTree(o, map)
		if rawget(o, "_props").Archivable == false then
			return nil
		end
		local c = new(rawget(o, "_class"))
		c.Name = rawget(o, "_name")
		map[o] = c
		for k, v in pairs(rawget(o, "_props")) do
			rawget(c, "_props")[k] = v
		end
		for k, v in pairs(rawget(o, "_attr")) do
			rawget(c, "_attr")[k] = v
		end
		for _, k in ipairs(rawget(o, "_kids")) do
			local kc = copyTree(k, map)
			if kc then
				kc.Parent = c
			end
		end
		return c
	end
	function methods.Clone(o)
		local map = {}
		local c = copyTree(o, map)
		for _, copy in pairs(map) do
			local props = rawget(copy, "_props")
			for k, v in pairs(props) do
				if type(v) == "table" and map[v] then
					props[k] = map[v]
				end
			end
		end
		return c
	end

	E.Instance = {
		new = function(cls, parent)
			return new(cls, parent)
		end,
	}
	function E.IsInstance(v)
		return type(v) == "table" and instSet[v] == true
	end

	-- the world
	E.workspace = new("Workspace")
	E.workspace.Name = "Workspace"
	E.camera = new("Camera", E.workspace)
	E.camera.CFrame = CFrame.new(0, 5, 0)
	E.workspace.CurrentCamera = E.camera

	-- services
	E.Heartbeat = Signal()
	E.RenderStepped = Signal()
	local tags = {} -- tag -> { [inst] = true }
	local added, removed = {}, {}
	local CS = {}
	function CS.GetTagged(_, tag)
		local out = {}
		for inst in pairs(tags[tag] or {}) do
			out[#out + 1] = inst
		end
		return out
	end
	function CS.HasTag(_, inst, tag)
		return tags[tag] ~= nil and tags[tag][inst] == true
	end
	function CS.AddTag(_, inst, tag)
		tags[tag] = tags[tag] or {}
		if not tags[tag][inst] then
			tags[tag][inst] = true
			if added[tag] then
				added[tag]:Fire(inst)
			end
		end
	end
	function CS.RemoveTag(_, inst, tag)
		if tags[tag] and tags[tag][inst] then
			tags[tag][inst] = nil
			if removed[tag] then
				removed[tag]:Fire(inst)
			end
		end
	end
	function CS.GetTags(_, inst)
		local out = {}
		for tag, set in pairs(tags) do
			if set[inst] then
				out[#out + 1] = tag
			end
		end
		return out
	end
	function CS.GetInstanceAddedSignal(_, tag)
		added[tag] = added[tag] or Signal()
		return added[tag]
	end
	function CS.GetInstanceRemovedSignal(_, tag)
		removed[tag] = removed[tag] or Signal()
		return removed[tag]
	end
	E.CollectionService = CS

	-- the host's service nodes get these behaviours (H = Host.new(...))
	function E.install(H)
		local rs = H.Service("RunService")._props
		rs.Heartbeat, rs.RenderStepped = E.Heartbeat, E.RenderStepped
		rs.IsClient = function()
			return true
		end
		rs.IsServer = function()
			return false
		end
		H.Service("CollectionService")._props = CS
		-- a local player without a character (every tracked model is an NPC or a Preview)
		E.localPlayer = E.localPlayer or new("Player")
		E.localPlayer.Name = "LocalPlayer"
		E.localPlayer.CharacterAdded = Signal()
		H.Service("Players")._props = {
			LocalPlayer = E.localPlayer, PlayerAdded = Signal(), PlayerRemoving = Signal(),
			GetPlayers = function()
				return {}
			end,
		}
		H.Service("Workspace")._props = { CurrentCamera = E.camera }
		H.game._props.IsLoaded = function()
			return true
		end
	end

	-- one frame: Heartbeat (dt), then a scheduler turn (the worker's task.wait() resumes)
	function E.step(n, dt)
		for _ = 1, n or 1 do
			E.Heartbeat:Fire(dt or 1 / 60)
			ltask.wait()
		end
	end
	-- frames until pred() is true (at most maxFrames; returns true when it held)
	function E.stepUntil(pred, maxFrames)
		for _ = 1, maxFrames or 2000 do
			if pred() then
				return true
			end
			E.step(1)
		end
		return pred()
	end
	-- frames until pred() is true or `seconds` of wall time passed (the scheduler's holds are os.clock based)
	function E.waitFor(pred, seconds)
		local t0 = os.clock()
		while os.clock() - t0 < (seconds or 30) do
			if pred() then
				return true
			end
			E.step(1)
		end
		return pred()
	end
	return E
end

return FE
