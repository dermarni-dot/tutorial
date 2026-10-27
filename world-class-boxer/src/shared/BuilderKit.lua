-- BuilderKit: part and colour helpers shared by the character builder modules.
-- Builder (facade: scales, HumanoidDescription, Cosmetics/Apply/CreateNPC), BuilderHead (face, hair,
-- beard, damage, sweat, headgear) and BuilderBody (colours, muscles, attire, hands, robe) all make their
-- extra parts with these, so every layer is welded, named and foldered the same way.
-- * V3 / CF / ANG / SMOOTH short aliases; lerpColor / darken / contrast / rgb colour maths
-- * weld, mk (part factory), textPatch (SurfaceGui text), getFolder (fresh BoxerLook sub-folder), part
-- * joint (animatable Motor6D, CONTRACTS section 5), font (safe Enum.Font lookup), setAttr (change-only)
-- * sig / cached / seal: per-folder rebuild caching (skip rebuilding a layer whose inputs did not change)
-- Requires none of the other builder modules, so they can all require it without a cycle.
local Kit = {}

-- the game's faces (the default text of a patch is the sign face; a Catalog brand names its own Enum.Font)
local Typography
do
	local ok, m = pcall(function()
		return require(script.Parent:WaitForChild("Typography", 5))
	end)
	Typography = ok and type(m) == "table" and m or nil
end

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local SMOOTH = Enum.Material.SmoothPlastic

-- false = always rebuild every layer (debug switch for the per-folder signature cache)
Kit.CACHE = true

local function lerpColor(a, b, t)
	return a:Lerp(b, math.clamp(t, 0, 1))
end

local function darken(c, k)
	return Color3.new(c.R * k, c.G * k, c.B * k)
end

local function contrast(c)
	local lum = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
	return lum > 0.55 and Color3.fromRGB(20, 20, 24) or Color3.fromRGB(245, 245, 245)
end

-- {r,g,b} (0..255, the save / Catalog format) -> Color3; anything else -> fallback
local function rgb(t, fallback)
	if type(t) == "table" and type(t[1]) == "number" then
		return Color3.fromRGB(t[1], t[2] or 0, t[3] or 0)
	end
	return fallback or Color3.new(1, 1, 1)
end

-- Enum.Font by NAME (Catalog brand fonts); unknown names fall back to GothamBlack instead of erroring
local fontCache = {}
local function font(name)
	if type(name) ~= "string" or name == "" then
		return Enum.Font.GothamBlack
	end
	local f = fontCache[name]
	if f == nil then
		local ok, res = pcall(function()
			return Enum.Font[name]
		end)
		f = ok and res or Enum.Font.GothamBlack
		fontCache[name] = f
	end
	return f
end

-- attributes replicate on every write, so only write real changes
local function setAttr(inst, key, value)
	if inst:GetAttribute(key) ~= value then
		inst:SetAttribute(key, value)
	end
end

------------------------------------------------------------------------
-- Part helpers
------------------------------------------------------------------------
local function weld(part, anchor)
	local w = Instance.new("WeldConstraint")
	w.Part0 = anchor
	w.Part1 = part
	w.Parent = part
end

-- shape: "Block" (default), "Ball", "Cylinder", "Ellipsoid", "Wedge"
local function mk(folder, anchor, name, size, cf, color, shape, material, transparency)
	local p = (shape == "Wedge") and Instance.new("WedgePart") or Instance.new("Part")
	p.Name = name
	p.Size = V3(math.max(size.X, 0.02), math.max(size.Y, 0.02), math.max(size.Z, 0.02))
	p.Color = color
	p.Material = material or SMOOTH
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	elseif shape == "Ellipsoid" then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	if transparency then
		p.Transparency = transparency
	end
	p.CFrame = cf
	if anchor then
		weld(p, anchor)
	end
	p.Parent = folder
	return p
end

-- fontName (optional) = an Enum.Font name; bg (optional Color3) = a filled label (sponsor patches)
-- the game's icon set (Shared.IconData, tools/ui): a glove logo prints its icon instead of a text glyph
local IconData
do
	local ok, m = pcall(function()
		return require(script.Parent:WaitForChild("IconData", 5))
	end)
	IconData = ok and type(m) == "table" and m or nil
end
local function iconEntry(name)
	local e = name and IconData and IconData.icons and IconData.icons[name]
	return (e and (tonumber(e.id) or 0) > 0) and e or nil
end
-- "icon:<name>" for textPatch when that icon is uploaded (nil otherwise: the caller keeps its text)
function Kit.IconText(name)
	return iconEntry(name) and ("icon:" .. name) or nil
end

local function textPatch(folder, anchor, name, size, cf, text, textColor, face, fontName, bg)
	local p = mk(folder, anchor, name, size, cf, Color3.new(0, 0, 0), "Block", SMOOTH, 1)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face or Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 120
	sg.LightInfluence = 0.6
	local e = iconEntry(type(text) == "string" and text:match("^icon:(%w+)$"))
	if e then
		-- an icon: the white glyph tinted the text colour, fitted to the patch
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.fromScale(1, 1)
		img.BackgroundTransparency = 1
		img.Image = "rbxassetid://" .. tostring(e.id)
		img.ImageRectOffset = Vector2.new(e.x, e.y)
		img.ImageRectSize = Vector2.new(IconData.cell or 256, IconData.cell or 256)
		img.ImageColor3 = textColor
		img.ScaleType = Enum.ScaleType.Fit
		img.Parent = sg
		sg.Parent = p
		return p
	end
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = bg and 0 or 1
	if bg then
		t.BackgroundColor3 = bg
		t.BorderSizePixel = 0
	end
	t.Text = text
	t.TextScaled = true
	if fontName then
		t.Font = font(fontName)
	elseif Typography then
		Typography.Apply(t, "sign")
	else
		t.Font = Enum.Font.GothamBlack
	end
	t.TextColor3 = textColor
	t.Parent = sg
	sg.Parent = p
	return p
end

local function getFolder(model, name)
	local look = model:FindFirstChild("BoxerLook")
	if not look then
		look = Instance.new("Folder")
		look.Name = "BoxerLook"
		look.Parent = model
	end
	local f = look:FindFirstChild(name)
	if f then
		f:Destroy()
	end
	f = Instance.new("Folder")
	f.Name = name
	f.Parent = look
	return f
end

local function part(model, name)
	return model:FindFirstChild(name)
end

-- animatable cosmetic joint (CONTRACTS section 5): the moving part has no WeldConstraint, the
-- client animates Motor6D.Transform. C0 = where part1 sits in part0's space, C1 = identity.
local function joint(part0, part1, name)
	local m = Instance.new("Motor6D")
	m.Name = name or "Joint"
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = part0.CFrame:Inverse() * part1.CFrame
	m.C1 = CF()
	m.Parent = part1
	return m
end

------------------------------------------------------------------------
-- Rebuild caching. Builder.Cosmetics runs after every session, sleep, purchase and fight; a layer
-- whose inputs did not change keeps its parts instead of destroying and re-replicating ~50 of them.
------------------------------------------------------------------------
-- stable text signature of any mix of numbers (rounded), strings, booleans and nested tables
local function sigInto(out, v)
	local t = typeof(v)
	if t == "number" then
		out[#out + 1] = string.format("%.3f", v)
	elseif t == "table" then
		local keys = {}
		for k in pairs(v) do
			keys[#keys + 1] = k
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		out[#out + 1] = "{"
		for _, k in ipairs(keys) do
			out[#out + 1] = tostring(k) .. "="
			sigInto(out, v[k])
		end
		out[#out + 1] = "}"
	elseif t == "Vector3" then
		out[#out + 1] = string.format("%.3f,%.3f,%.3f", v.X, v.Y, v.Z)
	elseif t == "Color3" then
		out[#out + 1] = string.format("%.3f,%.3f,%.3f", v.R, v.G, v.B)
	else
		out[#out + 1] = tostring(v)
	end
	out[#out + 1] = ";"
end

local function sig(...)
	local out = {}
	for i = 1, select("#", ...) do
		sigInto(out, (select(i, ...)))
	end
	return table.concat(out)
end

-- fixed-length digest of a signature: the folder stores 16 hex chars instead of the 400-1100 char key
-- (attributes replicate to every client, and only the server's cached() ever reads them).
-- Two 32-bit rolling hashes, exact in doubles (h1 * 33 < 2^38, h2 * 65599 < 2^49).
local function digest(s)
	local h1, h2 = 5381, 0
	for i = 1, #s do
		local c = string.byte(s, i)
		h1 = (h1 * 33 + c) % 4294967296
		h2 = (h2 * 65599 + c) % 4294967296
	end
	return string.format("%08x%08x", h1, h2)
end

-- every weld / motor in the folder still holds on to a part of this model (a respawn, a head swap or
-- a rescale through ApplyDescription replaces or moves the anchors, so the old parts are stale)
local function intact(model, folder)
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("WeldConstraint") or d:IsA("Motor6D") or d:IsA("Weld") then
			local p0 = d.Part0
			if not (p0 and p0:IsDescendantOf(model)) or not d.Part1 then
				return false
			end
		end
	end
	return true
end

-- true when BoxerLook/<name> was built from exactly this signature and is still attached
local function cached(model, name, key)
	if not Kit.CACHE then
		return false
	end
	local look = model:FindFirstChild("BoxerLook")
	local f = look and look:FindFirstChild(name)
	return f ~= nil and f:GetAttribute("Sig") == digest(key) and intact(model, f)
end

-- stamp a finished folder with the signature it was built from (set last: a build that errors
-- half way never gets a signature, so the next call rebuilds it)
local function seal(model, name, key)
	local look = model:FindFirstChild("BoxerLook")
	local f = look and look:FindFirstChild(name)
	if f then
		f:SetAttribute("Sig", digest(key))
	end
end

Kit.V3 = V3
Kit.CF = CF
Kit.ANG = ANG
Kit.SMOOTH = SMOOTH
Kit.lerpColor = lerpColor
Kit.darken = darken
Kit.contrast = contrast
Kit.rgb = rgb
Kit.font = font
Kit.setAttr = setAttr
Kit.weld = weld
Kit.mk = mk
Kit.textPatch = textPatch
Kit.getFolder = getFolder
Kit.part = part
Kit.joint = joint
Kit.sig = sig
Kit.digest = digest
Kit.intact = intact
Kit.cached = cached
Kit.seal = seal

------------------------------------------------------------------------
-- Mesh templates (BuilderTiers' body parts, BuilderGear's gear): what a load must show before it is used, the
-- retry schedule of a failed load, the "a mesh that failed is ready now" notice, and the player's own loads first
------------------------------------------------------------------------
-- A MeshPart whose mesh never arrived is drawn by the engine as its plain box (a CreateMeshPartAsync that returned a
-- part without geometry, an id whose "content representation is being generated" for minutes after the upload): it
-- must never be cloned onto a boxer. A real load names its content (MeshId, or a MeshContent with a source) and has a
-- finite MeshSize above zero. A property the part does not have (a simulator stub) is no evidence either way.
-- Returns ok, why
function Kit.MeshLoaded(mp)
	if mp == nil then
		return false, "no part"
	end
	local okId, id = pcall(function()
		return mp.MeshId
	end)
	local named = nil
	if okId and type(id) == "string" then
		named = id ~= ""
	end
	if named == false then
		local okC, c = pcall(function()
			return mp.MeshContent
		end)
		if okC and c ~= nil then
			local okU, uri = pcall(function()
				return c.Uri
			end)
			local okO, obj = pcall(function()
				return c.Object
			end)
			named = (okU and type(uri) == "string" and uri ~= "") or (okO and obj ~= nil)
		end
	end
	if named == false then
		return false, "no mesh content (MeshId is empty)"
	end
	local okS, ms = pcall(function()
		return mp.MeshSize
	end)
	if okS and typeof(ms) == "Vector3" then
		for _, v in ipairs({ ms.X, ms.Y, ms.Z }) do
			if v ~= v or v == math.huge or v <= 1e-4 then
				return false, "no geometry (MeshSize " .. tostring(ms) .. ")"
			end
		end
	end
	return true
end

-- seconds before the n-th retry of a failed load (n = 1 after the first failure); nil past the schedule (the caller's
-- own RETRY then applies, on demand). The schedule spans ~4.5 minutes: a freshly uploaded mesh answers "Asset content
-- representation is being generated" for a while and then loads
Kit.ASSET_BACKOFF = { 5, 10, 20, 40, 60, 60, 60 }
function Kit.RetryDelay(n)
	return Kit.ASSET_BACKOFF[n]
end
-- an error worth retrying soon (the asset exists but is not ready / the request did not go through)
function Kit.Transient(err)
	local s = string.lower(tostring(err or ""))
	for _, k in ipairs({ "being generated", "representation", "timeout", "timed out", "throttl", "http", "503", "502", "429", "try again" }) do
		if string.find(s, k, 1, true) then
			return true
		end
	end
	return false
end

-- the background retry: fn() after `delay` seconds on a running server only (a simulator or an edit-mode require has
-- no one to retry for, and a pending timer would keep it alive). Kit.Services.schedule(delay, fn) replaces it (tests)
Kit.Services = Kit.Services or {}
local function running()
	local ok, r = pcall(function()
		return game:GetService("RunService"):IsRunning()
	end)
	return ok and r == true
end
function Kit.Schedule(delay, fn)
	local s = Kit.Services.schedule
	if s then
		return s(delay, fn)
	end
	if not running() then
		return false
	end
	task.delay(delay, fn)
	return true
end

-- "a template that had failed has loaded": Builder rebuilds the boxers that were built without it (their cached
-- layers keep everything else; the layer that fell back now resolves to the mesh and rebuilds)
local readyListeners = {}
function Kit.OnAssetReady(fn)
	table.insert(readyListeners, fn)
	return fn
end
function Kit.AssetReady(kind, id)
	for _, fn in ipairs(readyListeners) do
		task.spawn(function()
			local ok, err = pcall(fn, kind, id)
			if not ok then
				warn("[Boxer] asset-ready listener failed:", err)
			end
		end)
	end
end

-- The player's own loads first: a build that runs Kit.Priority(fn) (Builder.Apply on a player's character) marks its
-- thread; while such a load is in flight, every other template load (the background preloaders, the gym's NPC
-- builds) waits for it, at most PRIORITY_WAIT seconds, so the boxer the menu shows is never queued behind a few
-- hundred background meshes (in Studio the server and the client share one asset pipeline)
Kit.PRIORITY_WAIT = 3
local priorityThreads = setmetatable({}, { __mode = "k" })
local priorityLoads = 0
function Kit.Priority(fn, ...)
	local co = coroutine.running()
	local was = priorityThreads[co]
	priorityThreads[co] = true
	local res = table.pack(pcall(fn, ...))
	priorityThreads[co] = was
	if not res[1] then
		error(res[2], 0)
	end
	return table.unpack(res, 2, res.n)
end
function Kit.IsPriority()
	return priorityThreads[coroutine.running()] == true
end
-- wrap one template load: a priority thread's load is counted; any other thread first waits out the priority loads
function Kit.Load(fn)
	if Kit.IsPriority() then
		priorityLoads += 1
		local res = table.pack(pcall(fn))
		priorityLoads -= 1
		if not res[1] then
			error(res[2], 0)
		end
		return table.unpack(res, 2, res.n)
	end
	local t0 = os.clock()
	while priorityLoads > 0 and os.clock() - t0 < Kit.PRIORITY_WAIT do
		task.wait()
	end
	return fn()
end
function Kit.PriorityLoads()
	return priorityLoads
end

------------------------------------------------------------------------
-- Fit audit: every built piece on a model is welded to a live part of it and sits on that part
------------------------------------------------------------------------
-- For every BasePart under BoxerLook (and every accessory handle): its joint (Weld / WeldConstraint / Motor6D) must
-- hold a part of the model that is still in it; a Weld / Motor6D must put the piece where it is (Part0.CFrame * C0 =
-- Part1.CFrame * C1: a C0 computed for another size or another part shows here); and the piece must touch its anchor:
-- the distance from the piece's centre to the anchor's box (in the anchor's space) at most the piece's half extent +
-- slack (0.15 studs: a buckle on a belt over the trousers, a logo patch on the glove's face anchored to the hand). A
-- piece welded to another built piece is followed to the body part at the end of the chain. The head-worn folders
-- (Headgear, Hat) must also be fitted to the live head: their HeadSize record equal to the head's Size (gear sized for
-- another head sits off it although welded).
-- Returns { problems = { "Folder/Piece: why" ... }, pieces = n }
local function jointOf(p)
	for _, c in ipairs(p:GetChildren()) do
		if c:IsA("Weld") or c:IsA("WeldConstraint") or c:IsA("Motor6D") then
			return c
		end
	end
	return nil
end
local function boxDistance(rel, half)
	local dx = math.max(math.abs(rel.X) - half.X, 0)
	local dy = math.max(math.abs(rel.Y) - half.Y, 0)
	local dz = math.max(math.abs(rel.Z) - half.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end
function Kit.FitAudit(model, opts)
	opts = opts or {}
	local slack = opts.slack or 0.15
	local out = { problems = {}, pieces = 0 }
	local look = model:FindFirstChild("BoxerLook")
	local list = {}
	if look then
		for _, d in ipairs(look:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
	end
	for _, acc in ipairs(model:GetChildren()) do
		local h = acc:IsA("Accessory") and acc:FindFirstChild("Handle")
		if h and h:IsA("BasePart") then
			table.insert(list, h)
		end
	end
	local function note(p, why)
		local f = p.Parent and p.Parent.Name or "?"
		table.insert(out.problems, f .. "/" .. p.Name .. ": " .. why)
	end
	local head = model:FindFirstChild("Head")
	for _, fname in ipairs({ "Headgear", "Hat" }) do
		local f = look and look:FindFirstChild(fname)
		local fit = f and f:GetAttribute("HeadSize")
		if f and #f:GetChildren() > 0 and head and head:IsA("BasePart") and typeof(fit) == "Vector3" and (fit - head.Size).Magnitude > 1e-3 then
			table.insert(out.problems, string.format("%s: fitted to a %s head, the head is %s", fname, tostring(fit), tostring(head.Size)))
		end
	end
	for _, p in ipairs(list) do
		out.pieces += 1
		local j = jointOf(p)
		local other = j and ((j.Part0 == p and j.Part1) or j.Part0)
		if not j then
			note(p, "not welded")
		elseif not (other and other:IsA("BasePart") and other:IsDescendantOf(model)) then
			note(p, "welded to " .. (other and other:GetFullName() or "nothing") .. " (not a part of this model)")
		else
			if j:IsA("Weld") or j:IsA("Motor6D") then
				local p0, p1 = j.Part0, j.Part1
				if p0 and p1 then
					local want = p0.CFrame * j.C0
					local have = p1.CFrame * j.C1
					local d = (want.Position - have.Position).Magnitude
					if d > 1e-3 + 0.01 * math.max(p.Size.X, p.Size.Y, p.Size.Z) then
						note(p, string.format("the weld puts it %.3f studs from where it is (C0 for another size or part)", d))
					end
				end
			end
			-- the body part at the end of the chain (a piece welded to a built piece: that piece's anchor)
			local anchor, hops = other, 0
			while anchor and hops < 4 and look and anchor:IsDescendantOf(look) do
				local j2 = jointOf(anchor)
				local o2 = j2 and ((j2.Part0 == anchor and j2.Part1) or j2.Part0)
				anchor, hops = o2, hops + 1
			end
			local target = (anchor and anchor:IsA("BasePart") and not (look and anchor:IsDescendantOf(look))) and anchor or other
			local rel = target.CFrame:PointToObjectSpace(p.Position)
			local reach = 0.5 * math.max(p.Size.X, p.Size.Y, p.Size.Z) + slack
			local gap = boxDistance(rel, target.Size * 0.5)
			if gap > reach then
				note(p, string.format("%.2f studs off %s (its own half extent %.2f)", gap - reach + slack, target.Name, reach - slack))
			end
		end
	end
	return out
end

return Kit
