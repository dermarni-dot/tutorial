--!nocheck
-- host.luau: runs the game's pure Luau modules (src/shared, src/client/modules) under lune, unchanged.
--
--   local Host = require("./host")          -- from a script in tools/sim (or require("<path>/tools/sim/host"))
--   local H = Host.new()                    -- or Host.new({ root = "/path/to/world-class-boxer" })
--   local Hair = H.require("AnatomyHair")   -- by module name (src/shared first, then src/client/modules)
--   local look = H.Look({ g = 1, hair = { style = "Afro", type = "Kinky" } })
--   local res = Hair.Generate(look, "full", H.Ctx("Hair", "full"))
--
-- How the modules find each other: every file is a fake ModuleScript node in a fake DataModel laid out like
-- default.project.json (game.ReplicatedStorage.Shared = src/shared, game.StarterPlayer.StarterPlayerScripts.
-- BoxerClient = src/client/modules). Each file is loaded with luau.load in its own environment whose `script`
-- is its node, so script.Parent:WaitForChild("X"), script.Parent.X, Shared:FindFirstChild("X") and
-- game:GetService("ReplicatedStorage").Shared.X all work, and `require(node)` loads (once) and caches the file.
-- Globals the game expects and lune lacks are stubbed: game / workspace, task, tick, time, Enum / Vector3 /
-- CFrame / Color3 / ... (from @lune/roblox), typeof (Instance for nodes), Instance.new (inert stubs).
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local ltask = require("@lune/task")

local Host = {}

------------------------------------------------------------------------
-- paths
------------------------------------------------------------------------
local function dirname(p)
	return (p:gsub("/[^/]*$", ""))
end

local function isDir(p)
	local ok, r = pcall(fs.isDir, p)
	return ok and r
end

local function findRoot()
	-- this file lives in <root>/tools/sim
	local src = debug.info(1, "s")
	if type(src) == "string" then
		src = src:gsub("^@", "")
		local r = dirname(dirname(dirname(src)))
		if r ~= "" and isDir(r .. "/src/shared") then
			return r
		end
	end
	local d = process.cwd:gsub("/$", "")
	while d ~= "" do
		if isDir(d .. "/src/shared") then
			return d
		end
		d = dirname(d)
	end
	error("host: cannot find the repository root (src/shared); pass Host.new({ root = ... })")
end
Host.FindRoot = findRoot

------------------------------------------------------------------------
-- fake instances
------------------------------------------------------------------------
local Node = {}
local NodeMethods = {}
local nodeSet = setmetatable({}, { __mode = "k" })

local function newNode(name, className, parent)
	local n = setmetatable({ Name = name, ClassName = className, _kids = {}, _order = {}, _attr = {} }, Node)
	nodeSet[n] = true
	if parent then
		rawset(n, "Parent", parent)
		parent._kids[name] = n
		table.insert(parent._order, n)
	end
	return n
end
Host.NewNode = newNode

local IS_A = {
	ModuleScript = { ModuleScript = true, LuaSourceContainer = true, Instance = true },
	Script = { Script = true, LuaSourceContainer = true, Instance = true },
	LocalScript = { LocalScript = true, Script = true, LuaSourceContainer = true, Instance = true },
}

function NodeMethods:FindFirstChild(name)
	return self._kids[name]
end
function NodeMethods:WaitForChild(name, _timeout)
	local c = self._kids[name]
	if not c then
		warn(string.format("[host] WaitForChild(%q) on %s: no such child (returning nil)", tostring(name), self:GetFullName()))
	end
	return c
end
function NodeMethods:FindFirstChildOfClass(cls)
	for _, c in ipairs(self._order) do
		if c.ClassName == cls then
			return c
		end
	end
	return nil
end
function NodeMethods:FindFirstChildWhichIsA(cls)
	for _, c in ipairs(self._order) do
		if c:IsA(cls) then
			return c
		end
	end
	return nil
end
function NodeMethods:GetChildren()
	return table.clone(self._order)
end
function NodeMethods:GetDescendants()
	local out = {}
	local function walk(n)
		for _, c in ipairs(n._order) do
			out[#out + 1] = c
			walk(c)
		end
	end
	walk(self)
	return out
end
function NodeMethods:IsA(cls)
	if cls == self.ClassName or cls == "Instance" then
		return true
	end
	local t = IS_A[self.ClassName]
	return t ~= nil and t[cls] == true
end
function NodeMethods:IsDescendantOf(other)
	local p = rawget(self, "Parent")
	while p do
		if p == other then
			return true
		end
		p = rawget(p, "Parent")
	end
	return false
end
function NodeMethods:GetFullName()
	local names = {}
	local n = self
	while n and n.ClassName ~= "DataModel" do
		table.insert(names, 1, n.Name)
		n = rawget(n, "Parent")
	end
	return table.concat(names, ".")
end
function NodeMethods:GetAttribute(k)
	return self._attr[k]
end
function NodeMethods:SetAttribute(k, v)
	self._attr[k] = v
end
function NodeMethods:GetAttributes()
	return table.clone(self._attr)
end
function NodeMethods:GetAttributeChangedSignal()
	return Host.Signal()
end
function NodeMethods:Destroy() end

Node.__index = function(self, k)
	local m = NodeMethods[k]
	if m ~= nil then
		return m
	end
	if k == "Parent" then
		return nil
	end
	local c = rawget(self, "_kids")[k]
	if c ~= nil then
		return c
	end
	local svc = rawget(self, "_props")
	if svc and svc[k] ~= nil then
		return svc[k]
	end
	error(string.format("%s is not a valid member of %s %q", tostring(k), rawget(self, "ClassName"), rawget(self, "Name")), 2)
end
Node.__tostring = function(self)
	return rawget(self, "Name")
end

-- an inert signal (Connect returns a connection; nothing ever fires)
function Host.Signal()
	local conn = { Connected = true }
	function conn:Disconnect()
		self.Connected = false
	end
	return {
		Connect = function()
			return conn
		end,
		Once = function()
			return conn
		end,
		Wait = function()
			return nil
		end,
	}
end

------------------------------------------------------------------------
-- host
------------------------------------------------------------------------
-- opts: root (repo root, default: found from this file), client (default true: mount src/client/modules),
-- src (the folder holding shared/ and client/, default <root>/src: e.g. a `git archive` of an older commit),
-- globals (extra globals for every module)
function Host.new(opts)
	opts = opts or {}
	local root = opts.root or findRoot()
	local src = opts.src or (root .. "/src")
	local H = { root = root, src = src, cache = {}, loading = {}, files = {} }

	local game = newNode("Game", "DataModel")
	H.game = game
	local services = {}
	local function service(name)
		local s = services[name]
		if not s then
			s = game._kids[name] or newNode(name, name, game)
			services[name] = s
		end
		return s
	end
	H.Service = service
	function NodeMethods:GetService(name)
		return service(name)
	end
	-- (methods are shared by all nodes; GetService is only meaningful on game)
	game._props = { PlaceId = 0, GameId = 0, JobId = "lune" }

	-- services the modules may touch (behaviour-free stubs)
	local rs = service("RunService")
	rs._props = {
		IsClient = function()
			return opts.server ~= true
		end,
		IsServer = function()
			return opts.server == true
		end,
		IsStudio = function()
			return true
		end,
		IsRunning = function()
			return false
		end,
		Heartbeat = Host.Signal(), RenderStepped = Host.Signal(), Stepped = Host.Signal(), PreSimulation = Host.Signal(),
		PostSimulation = Host.Signal(),
		BindToRenderStep = function() end, UnbindFromRenderStep = function() end,
	}
	service("HttpService")._props = {
		JSONEncode = function(_, v)
			return serde.encode("json", v)
		end,
		JSONDecode = function(_, s)
			return serde.decode("json", s)
		end,
		GenerateGUID = function()
			return "00000000-0000-0000-0000-000000000000"
		end,
	}
	service("CollectionService")._props = {
		GetTagged = function()
			return {}
		end,
		HasTag = function()
			return false
		end,
		AddTag = function() end, RemoveTag = function() end,
		GetInstanceAddedSignal = function()
			return Host.Signal()
		end,
		GetInstanceRemovedSignal = function()
			return Host.Signal()
		end,
	}
	service("Players")._props = { LocalPlayer = nil, PlayerAdded = Host.Signal(), PlayerRemoving = Host.Signal(),
		GetPlayers = function()
			return {}
		end }
	-- AssetService: no CreateEditableMesh / CreateEditableImage (MeshKit.ToEditableMesh returns its error)
	service("AssetService")._props = {}
	local ws = service("Workspace")
	ws._props = { CurrentCamera = nil }
	H.workspace = ws

	-- the project tree (default.project.json)
	local RS = service("ReplicatedStorage")
	local Shared = newNode("Shared", "Folder", RS)
	H.shared = Shared
	local SP = service("StarterPlayer")
	local SPS = newNode("StarterPlayerScripts", "StarterPlayerScripts", SP)
	local BoxerClient = newNode("BoxerClient", "Folder", SPS)
	H.client = BoxerClient

	local function mount(folder, dir)
		local ok, list = pcall(fs.readDir, dir)
		if not ok then
			return
		end
		table.sort(list)
		for _, f in ipairs(list) do
			local path = dir .. "/" .. f
			local base, cls
			if f:match("%.server%.luau?$") then
				base, cls = f:gsub("%.server%.luau?$", ""), "Script"
			elseif f:match("%.client%.luau?$") then
				base, cls = f:gsub("%.client%.luau?$", ""), "LocalScript"
			elseif f:match("%.luau?$") then
				base, cls = f:gsub("%.luau?$", ""), "ModuleScript"
			end
			if base and fs.isFile(path) then
				local n = newNode(base, cls, folder)
				rawset(n, "_file", path)
				if not H.files[base] then
					H.files[base] = n
				end
			elseif isDir(path) then
				mount(newNode(f, "Folder", folder), path)
			end
		end
	end
	mount(Shared, src .. "/shared")
	if opts.client ~= false then
		mount(BoxerClient, src .. "/client/modules")
	end

	-- globals every module sees
	local taskLib = {
		wait = function(t)
			return ltask.wait(t or 0)
		end,
		spawn = ltask.spawn, defer = ltask.defer, delay = ltask.delay, cancel = ltask.cancel,
		desynchronize = function() end, synchronize = function() end,
	}
	local clock0 = os.clock()
	local function hostTypeof(v)
		if type(v) == "table" and nodeSet[v] then
			return "Instance"
		end
		return typeof(v)
	end
	local InstanceStub = {
		new = function(cls, parent)
			local n = newNode(cls, cls, nil)
			n._props = {}
			if parent then
				rawset(n, "Parent", parent)
			end
			return n
		end,
	}
	-- Roblox's Random (deterministic per seed; not the engine's sequence, only its interface)
	local RandomStub = {
		new = function(seed)
			local st = math.floor(math.abs(tonumber(seed) or os.clock() * 1e6)) % 2147483647
			if st == 0 then
				st = 1
			end
			local r = {}
			local function nxt()
				st = (st * 48271) % 2147483647
				return st / 2147483647
			end
			function r:NextNumber(a, b)
				if a == nil then
					return nxt()
				end
				return a + (b - a) * nxt()
			end
			function r:NextInteger(a, b)
				return math.min(b, a + math.floor(nxt() * (b - a + 1)))
			end
			return r
		end,
	}
	local G = {
		Random = RandomStub,
		game = game, workspace = ws, Workspace = ws, task = taskLib,
		tick = function()
			return os.time() + (os.clock() % 1)
		end,
		time = function()
			return os.clock() - clock0
		end,
		elapsedTime = function()
			return os.clock() - clock0
		end,
		typeof = hostTypeof, Instance = InstanceStub, warn = warn, print = print,
		settings = function()
			return {}
		end,
		UserSettings = function()
			return {}
		end,
	}
	for _, k in ipairs({ "Vector3", "Vector2", "CFrame", "Color3", "ColorSequence", "ColorSequenceKeypoint", "NumberSequence",
		"NumberSequenceKeypoint", "NumberRange", "UDim", "UDim2", "Rect", "Ray", "BrickColor", "Enum", "Region3", "Font",
		"PhysicalProperties", "Faces", "Axes", "Content" }) do
		if roblox[k] ~= nil then
			G[k] = roblox[k]
		end
	end
	for k, v in pairs(opts.globals or {}) do
		G[k] = v
	end
	H.globals = G

	local requireNode
	local function shimRequire(target)
		if type(target) == "table" and nodeSet[target] then
			return requireNode(target)
		elseif type(target) == "string" then
			if target:sub(1, 1) == "@" then
				return require(target)
			end
			local n = H.files[target]
			if n then
				return requireNode(n)
			end
		end
		error("host require: cannot resolve " .. tostring(target), 2)
	end
	G.require = shimRequire

	function requireNode(n)
		local c = H.cache[n]
		if c ~= nil then
			return c.value
		end
		local file = rawget(n, "_file")
		if not file then
			error("host require: " .. n:GetFullName() .. " is not a module file", 3)
		end
		if H.loading[n] then
			error("host require: cyclic require of " .. n:GetFullName(), 3)
		end
		H.loading[n] = true
		local env = table.clone(G)
		env.script = n
		local rel = file:sub(1, #root) == root and file:sub(#root + 2) or file
		local chunk = luau.load(fs.readFile(file), { debugName = rel, environment = env, codegenEnabled = true })
		local ok, res = pcall(chunk)
		H.loading[n] = nil
		if not ok then
			error(string.format("host: %s failed to load: %s", rel, tostring(res)), 0)
		end
		H.cache[n] = { value = res }
		return res
	end
	H.requireNode = requireNode

	-- by module name or path-like "Shared/X" / "Client/X"
	function H.require(name)
		local folder, base = name:match("^(%a+)/(.+)$")
		if folder == "Shared" then
			return requireNode(assert(Shared._kids[base], name))
		elseif folder == "Client" then
			return requireNode(assert(BoxerClient._kids[base], name))
		end
		local n = H.files[name]
		if not n then
			error("host: no module named " .. tostring(name), 2)
		end
		return requireNode(n)
	end

	-- the ctx AnatomyClient passes a generator (section budget from Config.Anatomy.tris)
	function H.Ctx(section, lod)
		local Config = H.require("Config")
		local tris = Config.Anatomy and Config.Anatomy.tris and Config.Anatomy.tris[section]
		return { section = section, lod = lod, budget = tris and tris[lod] or nil, settings = {} }
	end

	H.Rig = function(g)
		return Host.Rig(g)
	end
	H.Look = function(spec)
		return Host.Look(H, spec)
	end
	return H
end

------------------------------------------------------------------------
-- rig and look tables
------------------------------------------------------------------------
-- Realistic R15 rig numbers for Builder's default boxer (Looks.Defaults: Athletic frame, no training), in the
-- shape LookData.ReadRig records. Derivation (src/shared/Builder.lua):
--   head  = 1.2 (the plain head Part BuilderHead swaps in) x HeadScale (FRAME_PROPORTIONS.Athletic.head 0.82,
--           x 0.97 for women) x 0.942 (the engine's Rthro head factor at BodyTypeScale 1)
--           -> men 0.927, women 0.899 (uniform): AnatomySkull's nominal 1.2 head scaled by k = 0.7725 / 0.749
--   torso = R15 Classic 2 x 1.6 x 1 x the Rthro blend (x 1.03 wide, x 1.3 tall, x 1.15 deep) x Builder.Scales
--           (height = inches / 70; width 0.77 (SLIM_W) x 0.92 for women; depth 0.84 (SLIM_D) x 0.94 for women)
--           -> men 1.59 x 2.08 x 0.97, women 1.42 x 1.96 x 0.91. Checked against Builder's comment (hip pivot
--           45 %, shoulders 81 % of a ~6.5-stud 70-inch man: waist..shoulder pivot = 0.875 x UT.y = 1.82)
--   Neck  = C0 (0, UT.y / 2, 0) in UpperTorso space; C1 (0, -(0.5 + NECK_LIFT) x head.y, 0) in Head space
--           (Builder liftHead: NECK_LIFT 0.26 men, 0.22 women) -> men c1.y -0.705, women -0.647
--   Waist = C0 (0, LT.y / 2, 0), C1 (0, -UT.y / 2, 0)
-- The limbs are left out: the Body generator falls back to the Classic boxes x look.scale.
Host.RIG = {
	[1] = { head = 0.927, ut = { 1.59, 2.08, 0.97 }, lt = { 1.59, 0.52, 0.97 }, lift = 0.26, scale = { h = 1, w = 0.77, d = 0.84 } },
	[2] = { head = 0.899, ut = { 1.42, 1.96, 0.91 }, lt = { 1.45, 0.49, 0.91 }, lift = 0.22, scale = { h = 0.943, w = 0.708, d = 0.79 } },
}

local function r3(x)
	return math.floor(x * 1000 + 0.5) / 1000
end

function Host.Rig(g)
	local R = Host.RIG[g == 2 and 2 or 1]
	local hd = R.head
	return {
		parts = {
			Head = { hd, hd, hd },
			UpperTorso = table.clone(R.ut),
			LowerTorso = table.clone(R.lt),
		},
		joints = {
			Neck = { p0 = "UpperTorso", p1 = "Head", c0 = { 0, r3(R.ut[2] / 2), 0 }, c1 = { 0, r3(-(0.5 + R.lift) * hd), 0 } },
			Waist = { p0 = "LowerTorso", p1 = "UpperTorso", c0 = { 0, r3(R.lt[2] / 2), 0 }, c1 = { 0, r3(-R.ut[2] / 2), 0 } },
		},
	}
end

local function merge(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" and type(dst[k]) == "table" and #v == 0 then
			merge(dst[k], v)
		else
			dst[k] = v
		end
	end
	return dst
end

-- A look table exactly as the server publishes it (LookData.FromBuilder on Looks.Defaults(g), quantised), with
-- the realistic rig above. spec (all optional):
--   g (1 / 2), age (26), skin (Looks.SkinTones index, default 6), height (inches),
--   hair = { style, type, color = {r,g,b} | HairColors index, length, density, thickness, clump, frizz, volume,
--            curlSize, growth, dye, hairline, part, hl, hcolor }  (merged over the defaults)
--   face = { ... } (merged over the defaults), beard = { style, growth }, build = { fat, ... }, opts = { ... }
--   rig = a rig table (replaces Host.Rig(g)), app = fn(app) to edit the app table before conversion,
--   headShape = "classic" (the game's head; default nil: the organic skull the hair was modelled on)
function Host.Look(H, spec)
	spec = spec or {}
	local Looks = H.require("Looks")
	local LookData = H.require("LookData")
	local g = spec.g == 2 and 2 or 1
	local app = Looks.Defaults(g)
	app.skin = spec.skin or 6
	if spec.height then
		app.height = spec.height
	end
	if spec.face then
		merge(app.face, spec.face)
	end
	if spec.hair then
		local h = table.clone(spec.hair)
		if type(h.color) == "number" then
			h.color = table.clone(Looks.HairColors[h.color])
		end
		if type(h.hcolor) == "number" then
			h.hcolor = table.clone(Looks.HairColors[h.hcolor])
		end
		merge(app.hair, h)
	end
	if spec.beard then
		merge(app.beard, spec.beard)
	end
	if spec.app then
		spec.app(app)
	end
	local opts = table.clone(spec.opts or {})
	opts.age = opts.age or spec.age or 26
	local look = LookData.FromBuilder(nil, app, spec.build or {}, opts, {}, nil)
	look.rig = LookData.Quantize(spec.rig or Host.Rig(g))
	local R = Host.RIG[g]
	look.scale = table.clone(R.scale)
	if spec.height then
		look.scale.h = math.clamp(spec.height / 70, 0.86, 1.2)
	end
	look.body.frame = look.body.frame or "Athletic"
	-- the head: the game publishes headShape "classic" (the standard R15 classic head); the hair tests written for
	-- the organic skull it replaced keep that skull unless spec.headShape = "classic"
	look.headShape = spec.headShape
	return look, app
end

------------------------------------------------------------------------
-- output helpers
------------------------------------------------------------------------
function Host.MkDir(p)
	if not isDir(p) then
		fs.writeDir(p)
	end
end

function Host.WriteJSON(path, v, pretty)
	fs.writeFile(path, serde.encode("json", v, pretty == true))
end

-- raw RGBA8 (w * h * 4 bytes, rows top to bottom) as written by MeshKit.RasterizeUV / Paint.Texture
function Host.WriteRGBA(path, buf)
	fs.writeFile(path, buffer.tostring(buf))
end

-- a texture of a generated piece as AnatomyClient makes it (make() > .buffer > RasterizeUV(shade)); nil when
-- the piece has none. Returns buf, w, h
function Host.TextureOf(H, piece)
	local tex = piece.texture
	if type(tex) ~= "table" then
		return nil
	end
	local MeshKit = H.require("MeshKit")
	local w, h = tex.w or (tex.size and tex.size[1]) or 256, tex.h or (tex.size and tex.size[2]) or 256
	local make = rawget(tex, "make")
	local buf
	if type(make) == "function" then
		buf = make()
	else
		local ok, b = pcall(function()
			return tex.buffer
		end)
		buf = ok and b or nil
	end
	if type(buf) ~= "buffer" and tex.shade then
		buf = MeshKit.RasterizeUV(piece.mesh, w, h, tex.shade, { pad = tex.pad })
	end
	if type(buf) == "buffer" and buffer.len(buf) == w * h * 4 then
		return buf, w, h
	end
	return nil
end

return Host
