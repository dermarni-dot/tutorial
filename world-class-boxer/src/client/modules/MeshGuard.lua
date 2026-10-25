-- MeshGuard (client): a boxer's mesh this client cannot draw never shows as the engine's plain box.
-- The server builds the gear (BuilderGear) and the muscle-tier body (BuilderTiers) from uploaded meshes and tags every
-- such MeshPart (WCBGearMesh / WCBBodyMesh). The server having loaded a mesh (CreateMeshPartAsync) does not mean this
-- client can fetch it: a mesh uploaded minutes ago answers "Asset content representation is being generated" for a
-- while, a moderation or permission hiccup fails it, and a MeshPart whose mesh did not arrive is drawn as its box (the
-- gym's gloves as red blocks several times the hand's size). For every tagged part:
-- * its MeshId's fetch status (ContentProvider:GetAssetFetchStatus, and its changed signal; a PreloadAsync asks for it)
-- * Failure / TimedOut (or an empty MeshId): the part is hidden on this client (Transparency 1, the old value kept)
--   and a stand-in drawn in its place: a rounded shape the size of the part (an ellipsoid: the Sphere mesh is built
--   in, it cannot fail), in the part's colour and material, welded to it so it follows every pose; thin detail pieces
--   (laces, stripes, hems, straps, buttons, badges...) are hidden without one
-- * retried on a backoff (BACKOFF, a few minutes: PreloadAsync again); when the status turns Success the stand-in goes
--   and the part shows again
-- Local only: nothing here replicates; the server's rebuild of a folder takes the stand-ins with it (they are children
-- of the parts). MeshGuard.Stats() for the diagnostic / tests.
-- Tests: MeshGuard.Services = { ContentProvider, CollectionService, schedule = function(delay, fn) }.
local MeshGuard = {}

MeshGuard.TAGS = { "WCBGearMesh", "WCBBodyMesh" }
MeshGuard.BACKOFF = { 5, 10, 20, 40, 60, 60, 60 }
MeshGuard.Services = {}

-- piece names drawn without a stand-in (too thin for a rounded shape to read as anything but a blob)
local HIDE_ONLY = { "Laces", "Stripe", "Hem", "Strap", "Band", "band", "Buttons", "Badge", "Placket", "Pocket", "BowTie", "Buckle",
	"Collar", "Belt", "Towel", "Polo", "Sole", "WrapWrist" }

local function svc(name)
	return MeshGuard.Services[name] or game:GetService(name)
end

local function schedule(delay, fn)
	local s = MeshGuard.Services.schedule
	if s then
		return s(delay, fn)
	end
	task.delay(delay, fn)
	return true
end

local function statusName(st)
	if st == nil then
		return "None"
	end
	local s = tostring(st)
	return s:match("([%w]+)$") or s
end

local pieces = {} -- part -> rec { part, id, fallback, origT, conns }
local ids = {} -- MeshId -> { parts = { [part] = true }, state = "ok" | "wait" | "failed", tries, conn }
local stats = { tracked = 0, fallbacks = 0, restored = 0, retries = 0 }
local conns = {}
local started = false

local function pieceName(p)
	local n = p:GetAttribute("GearPiece")
	return type(n) == "string" and n or p.Name
end

local function hideOnly(p)
	if p:GetAttribute("BodyTier") ~= nil then
		return false -- a body part always gets its stand-in
	end
	local n = pieceName(p)
	for _, k in ipairs(HIDE_ONLY) do
		if string.find(n, k, 1, true) then
			return true
		end
	end
	return false
end

local function applyFallback(rec)
	local p = rec.part
	if rec.fallback or rec.hidden or not p.Parent then
		return
	end
	rec.origT = p.Transparency
	rec.hidden = true
	p.Transparency = 1
	stats.fallbacks += 1
	if hideOnly(p) then
		return
	end
	local f = Instance.new("Part")
	f.Name = "MeshFallback"
	f.Size = p.Size
	f.CFrame = p.CFrame
	f.Color = p.Color
	f.Material = p.Material
	f.Reflectance = p.Reflectance
	f.Transparency = rec.origT or 0
	f.CanCollide = false
	f.CanQuery = false
	f.CanTouch = false
	f.Massless = true
	f.Anchored = false
	f.CastShadow = false
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = f
	local w = Instance.new("Weld")
	w.Name = "MeshFallbackWeld"
	w.Part0 = p
	w.Part1 = f
	w.C0 = CFrame.new()
	w.C1 = CFrame.new()
	w.Parent = f
	f.Parent = p
	rec.fallback = f
end

local function restore(rec)
	if not rec.hidden then
		return
	end
	rec.hidden = false
	if rec.fallback then
		rec.fallback:Destroy()
		rec.fallback = nil
	end
	if rec.part.Parent then
		rec.part.Transparency = rec.origT or 0
	end
	stats.restored += 1
end

local evaluate -- (id, status)

local function preload(id)
	task.spawn(function()
		local cp = svc("ContentProvider")
		local got
		pcall(function()
			cp:PreloadAsync({ id }, function(_, status)
				got = status
			end)
		end)
		if got ~= nil then
			evaluate(id, got)
		else
			local ok, st = pcall(function()
				return cp:GetAssetFetchStatus(id)
			end)
			evaluate(id, ok and st or nil)
		end
	end)
end

local function retryLater(id, rec)
	local delay = MeshGuard.BACKOFF[rec.tries]
	if not delay then
		return -- past the schedule: the stand-in stays until a rebuild brings a new part
	end
	schedule(delay, function()
		local cur = ids[id]
		if cur ~= rec or rec.state ~= "failed" or next(rec.parts) == nil then
			return
		end
		stats.retries += 1
		rec.retryPending = true
		preload(id)
	end)
end

function evaluate(id, status)
	local rec = ids[id]
	if not rec then
		return
	end
	local s = statusName(status)
	if s == "Success" then
		rec.retryPending = nil
		rec.state = "ok"
		for p in pairs(rec.parts) do
			local r = pieces[p]
			if r then
				restore(r)
			end
		end
	elseif s == "Failure" or s == "TimedOut" or id == "" then
		local was = rec.state
		rec.state = "failed"
		for p in pairs(rec.parts) do
			local r = pieces[p]
			if r then
				applyFallback(r)
			end
		end
		if was ~= "failed" or rec.retryPending then
			rec.retryPending = nil
			rec.tries = (rec.tries or 0) + 1
			retryLater(id, rec)
		end
	else
		-- None / Loading: a part still loading draws nothing (no box); the changed signal or the preload answers
		if rec.state ~= "failed" then
			rec.state = "wait"
		end
	end
end

local function untrack(p)
	local rec = pieces[p]
	if not rec then
		return
	end
	pieces[p] = nil
	for _, c in ipairs(rec.conns) do
		c:Disconnect()
	end
	if rec.fallback and rec.fallback.Parent then
		rec.fallback:Destroy()
	end
	local ir = ids[rec.id]
	if ir then
		ir.parts[p] = nil
		if next(ir.parts) == nil then
			if ir.conn then
				ir.conn:Disconnect()
			end
			ids[rec.id] = nil
		end
	end
end

local function track(p)
	if pieces[p] or not p:IsA("MeshPart") then
		return
	end
	local okId, id = pcall(function()
		return p.MeshId
	end)
	id = (okId and type(id) == "string") and id or ""
	local rec = { part = p, id = id, conns = {} }
	pieces[p] = rec
	stats.tracked += 1
	table.insert(rec.conns, p.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			untrack(p)
		end
	end))
	local ir = ids[id]
	if not ir then
		ir = { parts = {}, state = "wait", tries = 0 }
		ids[id] = ir
		if id ~= "" then
			pcall(function()
				ir.conn = svc("ContentProvider"):GetAssetFetchStatusChangedSignal(id):Connect(function(st)
					evaluate(id, st)
				end)
			end)
		end
	end
	ir.parts[p] = true
	if id == "" then
		evaluate(id, nil)
		return
	end
	if ir.state == "failed" then
		applyFallback(rec)
		return
	end
	local ok, st = pcall(function()
		return svc("ContentProvider"):GetAssetFetchStatus(id)
	end)
	local s = ok and statusName(st) or "None"
	if s == "Success" or s == "Failure" or s == "TimedOut" then
		evaluate(id, st)
	elseif not ir.asked then
		ir.asked = true
		preload(id)
	end
end
MeshGuard.Track = track

function MeshGuard.Start()
	if started then
		return
	end
	started = true
	local CS = svc("CollectionService")
	for _, tag in ipairs(MeshGuard.TAGS) do
		table.insert(conns, CS:GetInstanceAddedSignal(tag):Connect(function(p)
			track(p)
		end))
		table.insert(conns, CS:GetInstanceRemovedSignal(tag):Connect(function(p)
			untrack(p)
		end))
		for _, p in ipairs(CS:GetTagged(tag)) do
			track(p)
		end
	end
end

function MeshGuard.Stop()
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	table.clear(conns)
	local list = {}
	for p in pairs(pieces) do
		table.insert(list, p)
	end
	for _, p in ipairs(list) do
		local rec = pieces[p]
		if rec then
			restore(rec)
		end
		untrack(p)
	end
	started = false
end

function MeshGuard.Stats()
	local out = table.clone(stats)
	local failing, showing = {}, 0
	for id, ir in pairs(ids) do
		if ir.state == "failed" then
			table.insert(failing, id)
		end
	end
	for _, rec in pairs(pieces) do
		if rec.fallback then
			showing += 1
		end
	end
	table.sort(failing)
	out.failing = failing
	out.standIns = showing
	return out
end

-- (tests) forget everything without touching the parts
function MeshGuard.Reset()
	MeshGuard.Stop()
	table.clear(pieces)
	table.clear(ids)
	stats.tracked, stats.fallbacks, stats.restored, stats.retries = 0, 0, 0, 0
end

return MeshGuard
