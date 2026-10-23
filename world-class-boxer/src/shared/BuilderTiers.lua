-- BuilderTiers: the muscle-tier body parts on the server (tools/body/CONTRACT.md). The rig is the standard R15
-- body the HumanoidDescription builds (empty body-part ids: the engine's default parts); each of the 14
-- non-head parts is swapped for its tier's MeshPart with Humanoid:ReplaceBodyPartR15, and only when that
-- part's tier changes (a swap replicates one part).
-- * templates: one MeshPart per (frame, tier, part) (the frame's mesh family, BodyTiers.PartEntry; the tiers table's
--   .frame, else the model's Frame attribute), made once per server with AssetService:CreateMeshPartAsync
--   (pcall; concurrent callers wait for the same load; a failed id is retried after RETRY seconds) and given
--   the part-space RigAttachments / accessory attachments from BodyAssetData, an OriginalSize and every
--   attachment's OriginalPosition (the unscaled values the engine's body scaling multiplies) and an
--   AvatarPartScaleType "Classic" (the description runs at BodyTypeScale 0)
-- * the swap: the clone takes the replaced part's colour, material, collision and transparency; welds that held
--   on to the old part are moved to the new one; then the scale is checked once: ReplaceBodyPartR15 scales the
--   new part "as normal", i.e. from its OriginalSize by the humanoid's scales. Whatever the engine did, the part
--   ends at OriginalSize x the ratio the default part had (its Size / its OriginalSize, else the description's
--   Width / Height / Depth), the attachments at OriginalPosition x that ratio, and the joints that touch it are
--   re-aimed at its attachments (Builder.lua's headRecord / keepHeadScale guard the head swap the same way):
--   the part is scaled exactly once, never twice
-- * HipHeight follows the swapped legs (root -> hips -> knees -> ankles -> the soles, R15's rule
--   Height = HipHeight + RootPart.Size.Y / 2)
-- * an id 0 / a failed load keeps the part that is there (the default part, or the last tier that loaded)
-- * detail sets (Config.Detail.meshes): Apply(..., lite = true) swaps in each part's `lite` mesh (the v9 set the low
--   detail level wears) instead of the detailed one; a part showing the other set of its tier is swapped too
--   (attribute BodyMesh = the id it shows, BodyLite = true on a lite part)
-- Builder.Cosmetics runs Apply first (before the colours, so every layer is built on the final parts).
-- Tests: BuilderTiers.Services = { AssetService = fake, Content = fake } and BuilderTiers.Reset().
local BuilderTiers = {}

local Shared = script.Parent
local BodyTiers = require(Shared:WaitForChild("BodyTiers"))

local V3 = Vector3.new
BuilderTiers.RETRY = 120 -- seconds before a failed mesh id is tried again
BuilderTiers.Services = {} -- overrides (tests): AssetService, Content

local cache = {} -- "tier:part" -> { part = template } | { loading = true } | { failed = os.clock() }
local stats = { loads = 0, failed = 0, swaps = 0 }

function BuilderTiers.Reset()
	for _, e in pairs(cache) do
		if e.part then
			pcall(function()
				e.part:Destroy()
			end)
		end
	end
	table.clear(cache)
	stats.loads, stats.failed, stats.swaps = 0, 0, 0
end

function BuilderTiers.Stats()
	return table.clone(stats)
end

local function assetService()
	return BuilderTiers.Services.AssetService or game:GetService("AssetService")
end

local function contentOf(uri)
	local C = BuilderTiers.Services.Content or Content
	if C and C.fromUri then
		return C.fromUri(uri)
	end
	return uri
end

local function vec(t)
	return V3(t[1], t[2], t[3])
end

local function valueChild(parent, class, name, value)
	local v = parent:FindFirstChild(name)
	if not (v and v:IsA(class)) then
		v = Instance.new(class)
		v.Name = name
		v.Parent = parent
	end
	v.Value = value
	return v
end

-- one template from a loaded MeshPart (unscaled: the Blender export's size and attachments)
local function prepare(mp, e)
	mp.Name = e.name
	mp.Size = vec(e.size)
	mp.Anchored = false
	mp.CanCollide = false
	mp.CanTouch = false
	mp.Massless = false
	for name, p in pairs(e.attachments) do
		local a = Instance.new("Attachment")
		a.Name = name
		a.Position = vec(p)
		if string.find(name, "GripAttachment", 1, true) then
			-- the tool grip points down the fist (the engine's default hands' grip orientation)
			a.CFrame = CFrame.new(vec(p)) * CFrame.Angles(-math.pi / 2, 0, 0)
		end
		valueChild(a, "Vector3Value", "OriginalPosition", vec(p))
		a.Parent = mp
	end
	valueChild(mp, "Vector3Value", "OriginalSize", vec(e.size))
	valueChild(mp, "StringValue", "AvatarPartScaleType", "Classic")
	mp:SetAttribute("BodyTier", e.tier)
	mp:SetAttribute("BodyMesh", e.id)
	mp:SetAttribute("BodyLite", e.lite == true or nil)
	mp:SetAttribute("BodyFrame", e.frame)
	return mp
end

-- the template for (tier, part name) of a frame's family (frame nil = the default family), or nil + reason (not
-- uploaded / failed: the caller keeps its part). Yields on the first call for a key (CreateMeshPartAsync); later calls
-- are free
function BuilderTiers.Template(tier, name, lite, frame)
	local e = BodyTiers.PartEntry(tier, name, nil, lite, frame)
	if not e then
		return nil, "not uploaded"
	end
	local key = tier .. ":" .. name .. ":" .. e.id
	local c = cache[key]
	while c and c.loading do
		task.wait()
		c = cache[key]
	end
	if c and c.part then
		return c.part
	elseif c and c.failed and os.clock() - c.failed < BuilderTiers.RETRY then
		return nil, "failed"
	end
	cache[key] = { loading = true }
	stats.loads += 1
	local ok, mp = pcall(function()
		return assetService():CreateMeshPartAsync(contentOf("rbxassetid://" .. e.id), {
			CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Automatic,
		})
	end)
	if ok and mp then
		ok = pcall(prepare, mp, e)
	end
	if not (ok and mp) then
		stats.failed += 1
		cache[key] = { failed = os.clock() }
		warn(string.format("[BodyTiers] mesh %d (tier %d %s) did not load (%s); the default part stays", e.id, tier, name,
			tostring(mp)))
		return nil, "failed"
	end
	cache[key] = { part = mp }
	return mp
end

-- load every uploaded template in the background (server start), so the first boxers do not wait on them: the
-- default family first, then its lite set, then the other frames' families. Paced: PRELOAD_GAP seconds between
-- loads (a load the preloader has not reached yet is made on demand by the boxer that needs it, and one in
-- flight is shared), and the other families start PRELOAD_DEFER seconds in. The whole set is ~420
-- CreateMeshPartAsync calls (5 frames x 5 tiers x 14 parts + the lite set): fired back to back, in Studio (one
-- process for the server and the client) they saturated the asset pipeline for the first minute, while the
-- player's own parts, the menu's clone and the Creator's previews waited behind them.
-- opts (optional): { gap = seconds, defer = seconds, families = false (the default family only) }
BuilderTiers.PRELOAD_GAP = 0.1
BuilderTiers.PRELOAD_DEFER = 15
function BuilderTiers.Preload(opts)
	opts = type(opts) == "table" and opts or {}
	local gap = tonumber(opts.gap) or BuilderTiers.PRELOAD_GAP
	local defer = tonumber(opts.defer) or BuilderTiers.PRELOAD_DEFER
	local function pace()
		if gap > 0 then
			task.wait(gap)
		end
	end
	task.spawn(function()
		for _, lite in ipairs({ false, true }) do
			for tier = 1, BodyTiers.TIERS do
				for _, name in ipairs(BodyTiers.PARTS) do
					if BodyTiers.PartEntry(tier, name, nil, lite) then
						BuilderTiers.Template(tier, name, lite)
						pace()
					end
				end
			end
		end
		if opts.families == false then
			return
		end
		if defer > 0 then
			task.wait(defer)
		end
		for _, frame in ipairs(BodyTiers.Frames()) do
			if frame ~= BodyTiers.DEFAULT_FRAME then
				for tier = 1, BodyTiers.TIERS do
					for _, name in ipairs(BodyTiers.PARTS) do
						if BodyTiers.PartEntry(tier, name, nil, false, frame) then
							BuilderTiers.Template(tier, name, false, frame)
							pace()
						end
					end
				end
			end
		end
	end)
end

-- per-axis Size / OriginalSize of a body part (the engine's scale for it), nil when it has no record
local function ratioOf(p)
	local o = p and p:FindFirstChild("OriginalSize")
	if not (o and o:IsA("Vector3Value")) then
		return nil
	end
	local v = o.Value
	if v.X <= 1e-4 or v.Y <= 1e-4 or v.Z <= 1e-4 then
		return nil
	end
	local s = p.Size
	return V3(s.X / v.X, s.Y / v.Y, s.Z / v.Z)
end
BuilderTiers.RatioOf = ratioOf

-- the joints that touch a part, aimed at their rig attachments (Motor6D "X" uses the "XRigAttachment" pair)
local function reaim(model, p)
	for _, m in ipairs(model:GetDescendants()) do
		if m:IsA("Motor6D") and (m.Part0 == p or m.Part1 == p) then
			local an = m.Name .. "RigAttachment"
			local a0 = m.Part0 and m.Part0:FindFirstChild(an)
			local a1 = m.Part1 and m.Part1:FindFirstChild(an)
			if a0 and a0:IsA("Attachment") and (m.C0.Position - a0.CFrame.Position).Magnitude > 1e-4 then
				m.C0 = a0.CFrame
			end
			if a1 and a1:IsA("Attachment") and (m.C1.Position - a1.CFrame.Position).Magnitude > 1e-4 then
				m.C1 = a1.CFrame
			end
		end
	end
end
BuilderTiers.Reaim = reaim

-- the part at exactly OriginalSize x ratio, its attachments at OriginalPosition x ratio (true when fixed)
local function scaleOnce(p, ratio)
	local fixed = false
	local o = p:FindFirstChild("OriginalSize")
	if o and o:IsA("Vector3Value") then
		local want = o.Value * ratio
		if (p.Size - want).Magnitude > 1e-3 then
			p.Size = want
			fixed = true
		end
	end
	for _, a in ipairs(p:GetChildren()) do
		if a:IsA("Attachment") then
			local op = a:FindFirstChild("OriginalPosition")
			if op and op:IsA("Vector3Value") then
				local want = op.Value * ratio
				if (a.Position - want).Magnitude > 1e-4 then
					a.Position = want
					fixed = true
				end
			end
		end
	end
	return fixed
end

-- a body part swap that did not take (ReplaceBodyPartR15 refused it, or something else is in its place): warned once
-- per (part, reason) with where the model was (outside the DataModel the engine's rig operations misbehave), so a
-- silent failure is a visible Output line. SwapFailures: the count, for tests / the diagnostic
BuilderTiers.SwapFailures = 0
local swapWarned = {}
function BuilderTiers.SwapFailed(model, name, reason)
	BuilderTiers.SwapFailures += 1
	local inGame = false
	pcall(function()
		inGame = model:IsDescendantOf(game)
	end)
	local key = name .. "|" .. tostring(reason) .. "|" .. tostring(inGame)
	if swapWarned[key] then
		return
	end
	swapWarned[key] = true
	warn(string.format("[Boxer] body part swap did not take on %s: %s (%s); %s", tostring(model and model.Name), name, tostring(reason),
		inGame and "the model is in the DataModel" or "the model is OUTSIDE the DataModel: the engine cannot swap its parts there"))
end

local COPY = { "Color", "Material", "Transparency", "Reflectance", "CanCollide", "CanQuery", "CanTouch", "Massless", "CastShadow", "CFrame" }

-- swap one part (true when the model now carries the template's tier); scale = the description's
-- Width / Height / Depth (used when the old part has no OriginalSize)
local function swap(model, hum, name, template, scale)
	local old = model:FindFirstChild(name)
	if not (old and old:IsA("BasePart")) then
		return false
	end
	local ratio = ratioOf(old) or scale or V3(1, 1, 1)
	local new = template:Clone()
	for _, k in ipairs(COPY) do
		pcall(function()
			new[k] = old[k]
		end)
	end
	-- welds holding on to the old part (cosmetic layers, a robe, damage marks): moved over, so nothing drops
	local holders = {}
	for _, d in ipairs(model:GetDescendants()) do
		if (d:IsA("WeldConstraint") or d:IsA("Weld")) and (d.Part0 == old or d.Part1 == old) then
			table.insert(holders, d)
		end
	end
	local enum = Enum.BodyPartR15[name]
	local ok, err = pcall(function()
		hum:ReplaceBodyPartR15(enum, new)
	end)
	local got = model:FindFirstChild(name)
	if not ok or got ~= new then
		-- a swap that did not take is a silent default part under tier-fitted gear: one Output line per reason
		BuilderTiers.SwapFailed(model, name, ok and "the model still carries " .. (got and (got.ClassName .. " " .. got.Name) or "no part") or tostring(err))
		new:Destroy()
		return false
	end
	if not new:IsA("MeshPart") then
		BuilderTiers.SwapFailed(model, name, "the engine put a " .. new.ClassName .. " in place of the tier MeshPart")
	end
	scaleOnce(new, ratio)
	reaim(model, new)
	new:SetAttribute("BodyRatio", ratio)
	if scale then
		new:SetAttribute("BodyScale", scale)
	end
	for _, w in ipairs(holders) do
		if w.Parent then
			if w.Part0 == old then
				w.Part0 = new
			end
			if w.Part1 == old then
				w.Part1 = new
			end
		end
	end
	if old.Parent ~= nil then
		old:Destroy()
	end
	stats.swaps += 1
	return true
end

-- R15: Height = HipHeight + RootPart.Size.Y / 2, from the bind pose: root -> hip -> knee -> ankle -> sole
local function legBottom(model, side)
	local root = model:FindFirstChild("HumanoidRootPart")
	local lt = model:FindFirstChild("LowerTorso")
	local ul = model:FindFirstChild(side .. "UpperLeg")
	local ll = model:FindFirstChild(side .. "LowerLeg")
	local ft = model:FindFirstChild(side .. "Foot")
	if not (root and lt and ul and ll and ft) then
		return nil
	end
	local function att(p, n)
		local a = p:FindFirstChild(n)
		return a and a:IsA("Attachment") and a.Position or nil
	end
	local rA, rB = att(root, "RootRigAttachment"), att(lt, "RootRigAttachment")
	local hA, hB = att(lt, side .. "HipRigAttachment"), att(ul, side .. "HipRigAttachment")
	local kA, kB = att(ul, side .. "KneeRigAttachment"), att(ll, side .. "KneeRigAttachment")
	local aA, aB = att(ll, side .. "AnkleRigAttachment"), att(ft, side .. "AnkleRigAttachment")
	if not (rA and rB and hA and hB and kA and kB and aA and aB) then
		return nil
	end
	-- the centre of each part in root space (no rotation in the bind pose)
	local y = rA.Y - rB.Y + hA.Y - hB.Y + kA.Y - kB.Y + aA.Y - aB.Y
	return y - ft.Size.Y / 2
end

function BuilderTiers.HipHeight(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local l, r = legBottom(model, "Left"), legBottom(model, "Right")
	local b = (l and r) and math.min(l, r) or l or r
	if not b then
		return nil
	end
	return math.max(0.1, -b - root.Size.Y / 2)
end

local function fixHipHeight(model, hum)
	local h = BuilderTiers.HipHeight(model)
	if h and math.abs(hum.HipHeight - h) > 0.005 then
		hum.HipHeight = h
	end
end

-- the tier legs' HipHeight put back on a built body (change-only; a body of default parts keeps the engine's). Builder
-- runs it again a moment after a build: the engine's own scaling pass (AutomaticScalingEnabled, deferred to a later
-- frame after a part swap or a scale change) may have put the default body's value back, and the feet would float or
-- sink by the difference. Returns the value set (or nil)
function BuilderTiers.FixHipHeight(model)
	local hum = model and model.Parent and model:FindFirstChildOfClass("Humanoid")
	local key = model and model:GetAttribute("BodyTiers")
	if not (hum and type(key) == "string" and string.find(key, "[1-9]") ~= nil) then
		return nil
	end
	local h = BuilderTiers.HipHeight(model)
	if h and math.abs(hum.HipHeight - h) > 0.005 then
		hum.HipHeight = h
		return h
	end
	return nil
end

-- the frame a swap is for: the tiers table's frame (BodyTiers.Tiers), else the model's Frame attribute (Builder's
-- body attributes), else the default family
function BuilderTiers.FrameFor(model, tiers)
	local f = type(tiers) == "table" and tiers.frame or nil
	if type(f) ~= "string" or f == "" then
		f = model and model:GetAttribute("Frame") or nil
	end
	if type(f) ~= "string" or f == "" then
		f = BodyTiers.DEFAULT_FRAME
	end
	return f
end

-- swap every part whose tier (or frame family / detail set) changed. tiers = { [part] = 1..5, frame = id }
-- (BodyTiers.Tiers); scale = Vector3 (W, H, D) the description applied. Returns the number of parts swapped and the
-- model's tier key (attribute BodyTiers: the tiers the parts really show, 0 = a default part). lite = true: the detail
-- set of the low level (the v9 meshes). frame (optional) overrides the tiers table's frame
function BuilderTiers.Apply(model, tiers, scale, lite, frame)
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	if not (hum and type(tiers) == "table") then
		return 0, nil
	end
	frame = type(frame) == "string" and frame or BuilderTiers.FrameFor(model, tiers)
	local n = 0
	for _, name in ipairs(BodyTiers.PARTS) do
		local want = tiers[name]
		local cur = model:FindFirstChild(name)
		-- (the mesh this tier's part shows in the wanted detail set and frame family: a part of the same tier from
		-- another set or family is swapped too)
		local e = want and BodyTiers.PartEntry(want, name, nil, lite, frame)
		local otherSet = e ~= nil and cur ~= nil and cur:GetAttribute("BodyTier") == want and cur:GetAttribute("BodyMesh") ~= e.id
		if want and cur and (cur:GetAttribute("BodyTier") ~= want or otherSet) then
			local wasIn = model.Parent ~= nil
			local template = BuilderTiers.Template(want, name, lite, frame)
			-- (the load may have yielded: a model in the world may be gone; a new NPC is built before it is parented)
			if template and not (wasIn and model.Parent == nil) and swap(model, hum, name, template, scale) then
				n += 1
			end
		elseif cur and scale and cur:GetAttribute("BodyTier") ~= nil then
			-- an unchanged tier part after a rescale (ApplyDescription: a new height / frame): the engine rescales it
			-- from its OriginalSize; should it not have, the swap's ratio follows the description's change
			local r0, s0 = cur:GetAttribute("BodyRatio"), cur:GetAttribute("BodyScale")
			if typeof(r0) == "Vector3" and typeof(s0) == "Vector3" and (scale - s0).Magnitude > 1e-4 then
				local want = r0 * scale / s0
				local r = ratioOf(cur)
				if not (r and (r - want).Magnitude < 1e-3) and scaleOnce(cur, want) then
					reaim(model, cur)
				end
				cur:SetAttribute("BodyRatio", want)
				cur:SetAttribute("BodyScale", scale)
			end
		end
	end
	local shown = {}
	for _, name in ipairs(BodyTiers.PARTS) do
		local p = model:FindFirstChild(name)
		shown[name] = p and tonumber(p:GetAttribute("BodyTier")) or 0
	end
	local key = BodyTiers.Key(shown)
	-- the tier legs' own HipHeight, on every run (change-only inside): a body of default parts keeps the engine's; a
	-- rescale between runs (ApplyDescription: a new height, the avatar look on / off) puts the engine's value back on
	-- a body whose tiers did not change, and the soles would stand off the floor (or in it) until the next swap
	if string.find(key, "[1-9]") ~= nil then
		fixHipHeight(model, hum)
	end
	if model:GetAttribute("BodyTiers") ~= key then
		model:SetAttribute("BodyTiers", key)
	end
	-- the family the parts show (the frame id; the default family's name when the frame has no meshes of its own)
	local ut = model:FindFirstChild("UpperTorso")
	local shownFrame = ut and ut:GetAttribute("BodyFrame") or nil
	if model:GetAttribute("BodyFrame") ~= shownFrame then
		model:SetAttribute("BodyFrame", shownFrame)
	end
	return n, key
end

-- the tiers the model shows now ({ [part] = tier or nil }): the hysteresis' previous state
function BuilderTiers.Current(model)
	local out = {}
	for _, name in ipairs(BodyTiers.PARTS) do
		local p = model and model:FindFirstChild(name)
		out[name] = p and tonumber(p:GetAttribute("BodyTier")) or nil
	end
	return out
end

return BuilderTiers
