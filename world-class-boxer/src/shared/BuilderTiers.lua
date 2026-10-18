-- BuilderTiers: the muscle-tier body parts on the server (tools/body/CONTRACT.md). The rig is the standard R15
-- body the HumanoidDescription builds (empty body-part ids: the engine's default parts); each of the 14
-- non-head parts is swapped for its tier's MeshPart with Humanoid:ReplaceBodyPartR15, and only when that
-- part's tier changes (a swap replicates one part).
-- * templates: one MeshPart per (tier, part), made once per server with AssetService:CreateMeshPartAsync
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
		valueChild(a, "Vector3Value", "OriginalPosition", vec(p))
		a.Parent = mp
	end
	valueChild(mp, "Vector3Value", "OriginalSize", vec(e.size))
	valueChild(mp, "StringValue", "AvatarPartScaleType", "Classic")
	mp:SetAttribute("BodyTier", e.tier)
	mp:SetAttribute("BodyMesh", e.id)
	return mp
end

-- the template for (tier, part name), or nil + reason (not uploaded / failed: the caller keeps its part). Yields
-- on the first call for a key (CreateMeshPartAsync); later calls are free
function BuilderTiers.Template(tier, name)
	local e = BodyTiers.PartEntry(tier, name)
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

-- load every uploaded template in the background (server start), so the first boxers do not wait on them
function BuilderTiers.Preload()
	task.spawn(function()
		for tier = 1, BodyTiers.TIERS do
			for _, name in ipairs(BodyTiers.PARTS) do
				BuilderTiers.Template(tier, name)
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
	local ok = pcall(function()
		hum:ReplaceBodyPartR15(enum, new)
	end)
	if not ok or model:FindFirstChild(name) ~= new then
		new:Destroy()
		return false
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

-- swap every part whose tier changed. tiers = { [part] = 1..5 } (BodyTiers.Tiers); scale = Vector3 (W, H, D)
-- the description applied. Returns the number of parts swapped and the model's tier key (attribute BodyTiers:
-- the tiers the parts really show, 0 = a default part)
function BuilderTiers.Apply(model, tiers, scale)
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	if not (hum and type(tiers) == "table") then
		return 0, nil
	end
	local n = 0
	for _, name in ipairs(BodyTiers.PARTS) do
		local want = tiers[name]
		local cur = model:FindFirstChild(name)
		if want and cur and cur:GetAttribute("BodyTier") ~= want then
			local template = BuilderTiers.Template(want, name)
			-- (the load may have yielded: the model may be gone)
			if template and model.Parent ~= nil and swap(model, hum, name, template, scale) then
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
	if n > 0 or model:GetAttribute("BodyTiers") ~= key then
		fixHipHeight(model, hum)
	end
	if model:GetAttribute("BodyTiers") ~= key then
		model:SetAttribute("BodyTiers", key)
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
