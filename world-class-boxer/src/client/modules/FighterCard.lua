-- FighterCard: the professional fighter card / tale of the tape for the local boxer.
-- A studio portrait (a ViewportFrame holding a POSED clone of your character: gloves together at the
-- chest under the chin, chin level, framed from the measured head and chest - head top to mid chest
-- filling the frame, a slight low angle from the lead side - lit like a fight poster), the name (first
-- name over the LAST NAME, scaled to fit, never truncated), nickname, weight class, record, knockouts,
-- KO ratio, the four world titles as belt slots that light up when won, rankings per sanctioning body,
-- physique, style, nationality flag and recent form. Two sizes:
--   FighterCard.Full(parent, P)      the Career screen of the main menu (about 1240 x 640 design px)
--   FighterCard.Compact(parent, P)   the header of the Career Hub's Career tab
-- The posed clone is built once per look (LookSig, the anatomy meshes' builds) and cached; each photo
-- clones the cached copy (the Hub re-renders on every profile push). With AnatomyClient's organic meshes
-- the copy keeps them (the copied MeshParts share the live EditableMeshes) and hides what they replace;
-- a copy whose meshes did not come along shows the round-1 parts, and open photos re-shoot after every
-- mesh rebuild (the old EditableMeshes are destroyed then).
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UI = require(Shared:WaitForChild("UI"))
local Flags = require(script.Parent:WaitForChild("Flags"))
local T = UI.Theme

local FighterCard = {}
local player = Players.LocalPlayer
local A = CFrame.Angles

local PRO_AFTER = 4 -- amateur wins that turn you pro (Career: tier 1 -> 2 at 4 wins)

------------------------------------------------------------------------
-- Data helpers (pure)
------------------------------------------------------------------------
local function rec(r)
	r = type(r) == "table" and r or {}
	return tonumber(r.w) or 0, tonumber(r.l) or 0, tonumber(r.d) or 0, tonumber(r.ko) or 0
end

-- "12-1-0", KOs, KO percentage of wins (koPct nil before the first win: shown as a dash)
function FighterCard.RecordInfo(P)
	local pro = (P.tier or 1) >= 2
	local w, l, d, ko = rec(pro and P.record or P.amateurRecord)
	return { w = w, l = l, d = d, ko = ko, text = string.format("%d-%d-%d", w, l, d), koPct = w > 0 and math.floor(ko / w * 100 + 0.5) or nil, pro = pro }
end

-- "68%" or the dash
function FighterCard.KOText(ri)
	return ri.koPct and (ri.koPct .. "%") or "—"
end

-- first name and surname (old saves only have the full name: split at the first space)
function FighterCard.SplitName(identity)
	identity = type(identity) == "table" and identity or {}
	local first, last = identity.first, identity.last
	if type(first) == "string" and type(last) == "string" and (first ~= "" or last ~= "") then
		return first, last
	end
	local name = tostring(identity.name or "Boxer")
	local a, b = name:match("^(%S+)%s+(.+)$")
	if a then
		return a, b
	end
	return "", name
end

-- held titles: world belts by org, then regional / national
function FighterCard.Titles(P)
	local out = {}
	for _, org in ipairs(Config.Orgs) do
		if type(P.belts) == "table" and P.belts[org] then
			table.insert(out, { name = org, world = true })
		end
	end
	if type(P.regional) == "table" then
		if P.regional.national then
			table.insert(out, { name = "NATIONAL" })
		end
		if P.regional.regional then
			table.insert(out, { name = "REGIONAL" })
		end
	end
	return out
end

-- best ranking: text, is champion, caption ("WBC #4" / "WBA CHAMPION" / "UNRANKED" + why)
function FighterCard.BestRank(P)
	local best, bestOrg
	for _, org in ipairs(Config.Orgs) do
		local r = type(P.ranks) == "table" and P.ranks[org]
		if r == "C" then
			return org .. " CHAMPION", true, "WORLD CHAMPION"
		end
		r = tonumber(r)
		if r and (not best or r < best) then
			best, bestOrg = r, org
		end
	end
	if best then
		return string.format("%s #%d", bestOrg, best), false, "BEST RANKING"
	end
	if (P.tier or 1) < 2 then
		local w = rec(P.amateurRecord)
		local left = math.max(0, PRO_AFTER - w)
		return "UNRANKED", false, left > 0 and string.format("AMATEUR  ·  %d WIN%s TO TURN PRO", left, left == 1 and "" or "S") or "AMATEUR"
	end
	return "UNRANKED", false, "WIN TO ENTER THE TOP 15"
end

-- the last n results, newest first: { "W", "L", "D" }
function FighterCard.Form(P, n)
	local out = {}
	for i, h in ipairs(type(P.history) == "table" and P.history or {}) do
		if i > (n or 5) then
			break
		end
		table.insert(out, h.outcome == "win" and "W" or (h.outcome == "loss" and "L" or "D"))
	end
	return out
end

------------------------------------------------------------------------
-- The portrait: a posed clone of the character in a ViewportFrame
------------------------------------------------------------------------
local STRIP = { Script = true, LocalScript = true, ModuleScript = true, Sound = true, ParticleEmitter = true, Trail = true, Beam = true,
	BillboardGui = true, ProximityPrompt = true, ClickDetector = true, BodyMover = true, AlignPosition = true, AlignOrientation = true,
	Fire = true, Smoke = true, Sparkles = true, PointLight = true, SpotLight = true, SurfaceLight = true }

-- the portrait pose, per R15 joint (the Motor6D's Transform, in its own frame; the part it moves):
-- elbows tucked by the ribs, forearms up and in so the gloves meet in front of the upper chest about
-- a hand below the chin (solved offline against the R15 joint offsets: hands at x +-0.55, level with
-- the chest centre, 1.2 in front), chin level, chest out a touch
local PORTRAIT = {
	Waist = { "UpperTorso", A(0.03, 0, 0) },
	Neck = { "Head", A(0.03, 0, 0) },
	LeftShoulder = { "LeftUpperArm", A(0.16, -0.64, 0.3) },
	LeftElbow = { "LeftLowerArm", A(1.85, 0, 0) },
	LeftWrist = { "LeftHand", A(0.12, 0, 0) },
	RightShoulder = { "RightUpperArm", A(0.16, 0.64, -0.3) },
	RightElbow = { "RightLowerArm", A(1.85, 0, 0) },
	RightWrist = { "RightHand", A(0.12, 0, 0) },
}
FighterCard.Pose = PORTRAIT

-- pairs every clone instance with the live one it was copied from. Clone keeps every archivable child
-- in order, so the two trees are walked side by side (names repeat all over a rig: HairSeg, WrapFray,
-- Brow...): map[copy] = original
local function pairTrees(src, dst, map)
	map[dst] = src
	local a, b = src:GetChildren(), dst:GetChildren()
	local j = 1
	for _, ca in ipairs(a) do
		if ca.Archivable then
			local cb = b[j]
			if not cb then
				return
			end
			if cb.Name == ca.Name and cb.ClassName == ca.ClassName then
				pairTrees(ca, cb, map)
			end
			j += 1
		end
	end
end

-- AnatomyClient (the organic EditableMesh characters), required lazily: nil without the module
local anatomy
local anatomyLoaded = false
local function anatomyClient()
	if not anatomyLoaded then
		anatomyLoaded = true
		local m = script.Parent:FindFirstChild("AnatomyClient")
		local ok, ac = false, nil
		if m then
			ok, ac = pcall(require, m)
		end
		anatomy = (ok and type(ac) == "table") and ac or nil
	end
	return anatomy
end

-- does a copied anatomy MeshPart still show its mesh? Its geometry is an EditableMesh referenced
-- through MeshContent (Content.fromObject): a copy that lost the reference would draw nothing
local function meshCarried(mp)
	local ok, has = pcall(function()
		local c = mp.MeshContent
		return c ~= nil and c.Object ~= nil
	end)
	return ok and has == true
end

-- the copied anatomy meshes (model.Anatomy): kept when every piece still carries its mesh, else
-- removed so the photo falls back to the round-1 parts (true = the organic look is in the copy)
local function keepMeshes(clone)
	local folder = clone:FindFirstChild("Anatomy")
	if not folder then
		return false
	end
	local n = 0
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("MeshPart") then
			if not meshCarried(d) then
				folder:Destroy()
				return false
			end
			n += 1
		end
	end
	if n == 0 then
		folder:Destroy()
		return false
	end
	return true
end

-- what the anatomy meshes hide on the live character (LocalTransparencyModifier / Enabled, both
-- local) stays hidden in the photo when the meshes came along; without them the round-1 parts show.
-- The camera's own fading (first person) is not copied: only what AnatomyClient replaced, and the mesh
-- pieces it tucked under headgear / a hood
local function copyHidden(char, map, meshes)
	local ac = anatomyClient()
	local isReplaced = ac and ac.IsReplaced
	-- the hands are never replaced by meshes: hidden hands mean the camera is fading the character
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("LeftHand")
	local cameraFade = hand ~= nil and hand:IsA("BasePart") and hand.LocalTransparencyModifier > 0
	local pieces = char:FindFirstChild("Anatomy")
	for copy, src in pairs(map) do
		local replaced = false
		if isReplaced then
			local ok, r = pcall(isReplaced, src)
			replaced = ok and r == true
		end
		if copy:IsA("SurfaceGui") or copy:IsA("BillboardGui") then
			if copy:GetAttribute("AnatomyHid") == true then
				-- Enabled is copied: false while the live meshes hide it
				copy.Enabled = not meshes
				copy:SetAttribute("AnatomyHid", nil)
			end
		elseif meshes and (copy:IsA("BasePart") or copy:IsA("Decal")) then
			-- a round-1 part a mesh replaced, or a mesh piece tucked under headgear / a hood
			local covered = not cameraFade and pieces ~= nil and copy:IsA("MeshPart") and src.LocalTransparencyModifier >= 0.99 and src:IsDescendantOf(pieces)
			if replaced or covered then
				copy.Transparency = 1
			end
		end
	end
end

-- forward kinematics: every part placed from the root through the joints. The R15 joints of the
-- portrait take its transforms; every other joint keeps the offset it has on the live character right
-- now (hair segments hang the way HairFX left them, face parts sit where FaceFX put them). The joints
-- go afterwards (anchored parts in a ViewportFrame do not need them)
local function poseClone(clone, pose, map)
	local root = clone:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	-- where a part is now, read from the live character (its parts are solved every frame)
	local function cf(part)
		local src = map[part]
		return (src and src.Parent) and src.CFrame or part.CFrame
	end
	root.CFrame = cf(root)
	local links = {}
	local joints = {}
	local function link(a, b, rel)
		if not (a and b and a:IsA("BasePart") and b:IsA("BasePart")) then
			return
		end
		links[a] = links[a] or {}
		links[b] = links[b] or {}
		table.insert(links[a], { b, rel })
		table.insert(links[b], { a, rel:Inverse() })
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("JointInstance") then
			local p = d:IsA("Motor6D") and pose[d.Name]
			if p and d.Part1 and d.Part1.Name == p[1] then
				link(d.Part0, d.Part1, d.C0 * p[2] * d.C1:Inverse())
			elseif d.Part0 and d.Part1 then
				link(d.Part0, d.Part1, cf(d.Part0):ToObjectSpace(cf(d.Part1)))
			end
			table.insert(joints, d)
		elseif d:IsA("WeldConstraint") then
			if d.Part0 and d.Part1 then
				link(d.Part0, d.Part1, cf(d.Part0):ToObjectSpace(cf(d.Part1)))
			end
			table.insert(joints, d)
		elseif d:IsA("AnimationConstraint") then
			local a0, a1 = d.Attachment0, d.Attachment1
			if a0 and a1 and a0.Parent and a1.Parent then
				local p = pose[d.Name]
				if p and a1.Parent.Name == p[1] then
					link(a0.Parent, a1.Parent, a0.CFrame * p[2] * a1.CFrame:Inverse())
				else
					link(a0.Parent, a1.Parent, cf(a0.Parent):ToObjectSpace(cf(a1.Parent)))
				end
			end
			table.insert(joints, d)
		end
	end
	for _, j in ipairs(joints) do
		j:Destroy()
	end
	local seen = { [root] = true }
	local queue = { root }
	local i = 1
	while i <= #queue do
		local p = queue[i]
		i += 1
		for _, e in ipairs(links[p] or {}) do
			local q = e[1]
			if not seen[q] then
				seen[q] = true
				q.CFrame = p.CFrame * e[2]
				table.insert(queue, q)
			end
		end
	end
end

-- the rig's own parts (kept whatever they look like: the pose and the framing hang on them)
local R15 = { HumanoidRootPart = true, Head = true, UpperTorso = true, LowerTorso = true, LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
	RightUpperArm = true, RightLowerArm = true, RightHand = true, LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
	RightUpperLeg = true, RightLowerLeg = true, RightFoot = true }

-- the top of a part's box along world Y
local function topY(p)
	local cf, s = p.CFrame, p.Size
	local r, up, look = cf.RightVector, cf.UpVector, cf.LookVector
	return p.Position.Y + 0.5 * (math.abs(r.Y) * s.X + math.abs(up.Y) * s.Y + math.abs(look.Y) * s.Z)
end

-- builds the posed, pruned master clone (nil without a character)
local function buildMaster(char)
	if not (char and char:FindFirstChild("HumanoidRootPart") and char:FindFirstChild("Head")) then
		return nil
	end
	local was = char.Archivable
	local ok, clone = pcall(function()
		char.Archivable = true
		return char:Clone()
	end)
	pcall(function()
		char.Archivable = was
	end)
	if not (ok and clone) then
		return nil
	end
	local map = {}
	pcall(pairTrees, char, clone, map)
	copyHidden(char, map, keepMeshes(clone))
	for _, d in ipairs(clone:GetDescendants()) do
		for _, tag in ipairs(CollectionService:GetTags(d)) do
			CollectionService:RemoveTag(d, tag)
		end
		if STRIP[d.ClassName] or d:IsA("BodyMover") then
			d:Destroy()
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
	for _, tag in ipairs(CollectionService:GetTags(clone)) do
		CollectionService:RemoveTag(clone, tag)
	end
	poseClone(clone, PORTRAIT, map)
	-- prune what the photo never shows: the dressing below the waist and anything hidden (the rig's own
	-- body parts stay: the framing measures them); attachments and constraints
	local torso = clone:FindFirstChild("UpperTorso")
	local cut = torso and (torso.Position.Y - torso.Size.Y * 0.5 - 0.6) or -math.huge
	for _, d in ipairs(clone:GetDescendants()) do
		if d.Parent then
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
				local rigPart = d.Parent == clone and R15[d.Name]
				if not rigPart and (d.Transparency >= 0.99 or topY(d) < cut) then
					d:Destroy()
				end
			elseif d:IsA("Attachment") or d:IsA("Constraint") then
				d:Destroy()
			end
		end
	end
	clone.Name = "Portrait"
	return clone
end

-- cache: one master per look
local anatomyBuilds = 0
local anatomyHooked = false
local refreshPhotos, photos
local function hookAnatomy()
	if anatomyHooked then
		return
	end
	anatomyHooked = true
	task.spawn(function()
		local ac = anatomyClient()
		if not ac then
			return
		end
		for _, sig in ipairs({ ac.OnBuilt, ac.OnRestored }) do
			if type(sig) == "table" and type(sig.Connect) == "function" then
				pcall(function()
					sig:Connect(function(model)
						if model == player.Character then
							anatomyBuilds += 1
							-- every rebuild makes new meshes (the old ones are destroyed): open photos
							-- re-shoot so they never show a copy of a mesh that is gone
							refreshPhotos()
						end
					end)
				end)
			end
		end
	end)
end

local cache = { key = nil, master = nil }
local function masterFor(char)
	hookAnatomy()
	if not char then
		return nil
	end
	-- the look's digest (LookSig), the anatomy builds and the part count (a barber cut without LookSig)
	local key = string.format("%s|%s|%d|%d", tostring(char), tostring(char:GetAttribute("LookSig")), anatomyBuilds, #char:GetDescendants())
	if cache.key ~= key or not cache.master then
		if cache.master then
			cache.master:Destroy()
		end
		cache.master = buildMaster(char)
		cache.key = cache.master and key or nil
	end
	return cache.master
end

-- a fresh copy of the posed portrait clone (nil without a character)
function FighterCard.Snapshot(char)
	local m = masterFor(char or player.Character)
	return m and m:Clone() or nil
end

-- the camera for a portrait: head top to mid chest fill FILL of the frame height, the head (with its
-- hair) at most 70 % of the frame width, a three-quarter view from the lead side, a slight low angle
local FILL = 0.8
function FighterCard.Frame(model, aspect, fov)
	local head = model:FindFirstChild("Head")
	local torso = model:FindFirstChild("UpperTorso")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (head and torso and root) then
		return nil
	end
	local look = root.CFrame.LookVector
	local right = root.CFrame.RightVector
	look = Vector3.new(look.X, 0, look.Z).Unit
	right = Vector3.new(right.X, 0, right.Z).Unit
	local dir = (look + right * -0.3).Unit -- toward the lens: front, a little to the boxer's left
	local side = Vector3.yAxis:Cross(dir).Unit -- the frame's horizontal axis
	-- the head with everything on it (hair, ears, headgear): parts whose centre is above the chin
	local chin = head.Position.Y - head.Size.Y * 0.5
	local top, minS, maxS = topY(head), math.huge, -math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.99 and d.Position.Y > chin and (d.Position - head.Position).Magnitude < 4 then
			top = math.max(top, topY(d))
			local s = (d.Position - head.Position):Dot(side)
			local half = d.Size.Magnitude * 0.35
			minS, maxS = math.min(minS, s - half), math.max(maxS, s + half)
		end
	end
	local chest = torso.Position.Y
	local span = math.max(1.5, top - chest)
	local frameH = span / FILL
	local headW = math.max(1, maxS - minS)
	frameH = math.max(frameH, headW / (0.7 * math.max(0.3, aspect)))
	fov = fov or 24
	local dist = frameH * 0.5 / math.tan(math.rad(fov / 2))
	-- the head top sits (1 - FILL) / 2 below the frame top
	local centerY = top + frameH * (1 - FILL) * 0.5 - frameH * 0.5
	local target = Vector3.new(head.Position.X, centerY, head.Position.Z)
	local pos = target + dir * dist - Vector3.new(0, dist * 0.06, 0)
	return CFrame.lookAt(pos, target), fov
end

-- puts a fresh posed copy of the character in a ViewportFrame with its camera and key light (replacing
-- an earlier shot); false without a character to photograph
local function shoot(vf, aspect, fovOpt)
	local clone = FighterCard.Snapshot()
	local root = clone and clone:FindFirstChild("HumanoidRootPart")
	local camCF, fov
	if clone and root then
		camCF, fov = FighterCard.Frame(clone, aspect, fovOpt)
	end
	if not camCF then
		if clone then
			clone:Destroy()
		end
		return false
	end
	for _, c in ipairs(vf:GetChildren()) do
		if c.Name == "Portrait" or c:IsA("Camera") then
			c:Destroy()
		end
	end
	clone.Parent = vf
	local cam = Instance.new("Camera")
	cam.FieldOfView = fov
	cam.CFrame = camCF
	cam.Parent = vf
	vf.CurrentCamera = cam
	-- key light from the front-left, above (LightDirection = the way the light travels)
	local look, right = root.CFrame.LookVector, root.CFrame.RightVector
	vf.LightDirection = (-Vector3.new(look.X, 0, look.Z).Unit * 0.7 + Vector3.new(right.X, 0, right.Z).Unit * 0.45 + Vector3.new(0, -0.65, 0)).Unit
	return true
end

-- open photos (a closed screen's ViewportFrame drops out once it leaves the game); re-shot a moment after
-- the character's anatomy meshes are rebuilt or restored (one shot per burst: Body / Head / Hair build in turn)
photos = {}
local refreshToken = 0
refreshPhotos = function()
	refreshToken += 1
	local token = refreshToken
	task.delay(0.4, function()
		if token ~= refreshToken then
			return
		end
		for vf, o in pairs(photos) do
			if vf:IsDescendantOf(game) then
				pcall(shoot, vf, o.aspect, o.fov)
			else
				photos[vf] = nil
			end
		end
	end)
end

-- opts: Size, Position, ZIndex, aspect (width / height of the photo; read from the frame when it is
-- laid out)
function FighterCard.Photo(parent, opts)
	opts = opts or {}
	local holder = UI.Frame(parent, { Name = "Photo", Size = opts.Size or UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), ClipsDescendants = true, ZIndex = opts.ZIndex or 1 })
	if opts.Position then
		holder.Position = opts.Position
	end
	-- poster backdrop: deep red to black with a spotlight bloom behind the head
	UI.Gradient(holder, { Color3.fromRGB(120, 18, 26), Color3.fromRGB(28, 10, 14), Color3.fromRGB(8, 8, 10) }, 90)
	local glow = UI.Frame(holder, { Name = "Spot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromScale(1.3, 0.9), BackgroundColor3 = Color3.fromRGB(255, 196, 120), ZIndex = holder.ZIndex })
	UI.Gradient(glow, Color3.new(1, 1, 1), 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.55, 0.92), NumberSequenceKeypoint.new(1, 1) }), { type = "Elliptical" })
	-- broadcast scan lines
	local lines = UI.Frame(holder, { Name = "Lines", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.97, ZIndex = holder.ZIndex })
	local g = UI.Gradient(lines, Color3.new(1, 1, 1), 90, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0) }))
	pcall(function()
		g.TileMode = Enum.GradientTileMode.Repeat
		g.Scale = 0.02
	end)
	local vf = UI.New("ViewportFrame", {
		Name = "View", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = holder.ZIndex,
		Ambient = Color3.fromRGB(86, 82, 92), LightColor = Color3.fromRGB(255, 232, 206), Parent = holder,
	})
	local aspect = opts.aspect
	if not aspect then
		local abs = holder.AbsoluteSize
		aspect = (abs.X > 4 and abs.Y > 4) and abs.X / abs.Y or 0.68
	end
	for v in pairs(photos) do
		if not v:IsDescendantOf(game) then
			photos[v] = nil
		end
	end
	if shoot(vf, aspect, opts.fov) then
		photos[vf] = { aspect = aspect, fov = opts.fov }
	else
		-- no character to photograph: a silhouette
		local s = UI.Frame(holder, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(0.62, 0.78), BackgroundColor3 = Color3.fromRGB(14, 14, 18), ZIndex = holder.ZIndex })
		UI.Corner(s, 60)
		local h = UI.Frame(holder, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.26), Size = UDim2.fromScale(0.26, 0.2), BackgroundColor3 = Color3.fromRGB(14, 14, 18), ZIndex = holder.ZIndex })
		UI.Corner(h, 80)
	end
	-- fade the bottom into the card
	local fade = UI.Frame(holder, { Name = "Fade", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.4), BackgroundColor3 = T.ink, ZIndex = holder.ZIndex + 1 })
	UI.Gradient(fade, Color3.new(1, 1, 1), 90, NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.05) }))
	return holder, vf
end

------------------------------------------------------------------------
-- Pieces
------------------------------------------------------------------------
-- a championship belt: lit gold when held, a dim outline when it is still a goal
local function belt(parent, name, held, order, w)
	w = w or 112
	local b = UI.Frame(parent, { Name = "Belt", Size = UDim2.fromOffset(w, 46), BackgroundColor3 = held and Color3.fromRGB(26, 22, 14) or T.panel, BackgroundTransparency = held and 0 or 0.4, LayoutOrder = order or 0 })
	UI.Corner(b, 10)
	UI.Stroke(b, held and T.gold or T.line, held and 1.5 or 1, held and 0.2 or 0.3)
	if held then
		UI.Gradient(b, { Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150) }, 90)
	end
	local plate = UI.Frame(b, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(52, 34), BackgroundColor3 = held and Color3.new(1, 1, 1) or T.panel2 })
	UI.Corner(plate, 12)
	if held then
		UI.Gradient(plate, { Color3.fromRGB(255, 240, 190), T.goldDeep }, 110)
	end
	UI.Text(plate, name, { Face = "number", TextSize = 15, TextColor3 = held and Color3.fromRGB(60, 40, 6) or T.dim, Size = UDim2.fromScale(1, 1),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
	for _, x in ipairs({ 0.1, 0.9 }) do
		local stud = UI.Frame(b, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.5), Size = UDim2.fromOffset(9, 9), BackgroundColor3 = held and T.goldDeep or T.line })
		UI.Corner(stud, 5)
	end
	return b
end

-- the four world titles (goals until won) and any regional / national belt
local function beltRow(parent, P, order, w)
	local row = UI.Frame(parent, { Name = "Belts", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), LayoutOrder = order })
	UI.List(row, 10, true)
	local held = type(P.belts) == "table" and P.belts or {}
	for i, org in ipairs(Config.Orgs) do
		belt(row, org, held[org] and true or false, i, w)
	end
	for i, t in ipairs(FighterCard.Titles(P)) do
		if not t.world then
			belt(row, t.name:sub(1, 3), true, 10 + i, w)
		end
	end
	return row
end

local function formBubbles(parent, form, order)
	local row = UI.Frame(parent, { Name = "Form", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = order or 0 })
	UI.List(row, 6, true)
	if #form == 0 then
		UI.Text(row, "No fights yet - your story starts on fight night.", { TextSize = 14, TextColor3 = T.sub, Size = UDim2.new(1, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.None })
		return row
	end
	for i, r in ipairs(form) do
		local c = r == "W" and T.green or (r == "L" and T.red or T.sub)
		local b = UI.Frame(row, { Size = UDim2.fromOffset(28, 28), BackgroundColor3 = c, BackgroundTransparency = 0.15, LayoutOrder = i })
		UI.Corner(b, 6)
		UI.Text(b, r, { Face = "number", TextSize = 16, TextColor3 = T.ink, Size = UDim2.fromScale(1, 1), AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center })
	end
	return row
end

-- a tale-of-the-tape cell: CAPTION (small) / value (display)
local function tapeCell(parent, caption, value, order, accent)
	local f = UI.Frame(parent, { Name = "Tape", BackgroundColor3 = T.panel2, BackgroundTransparency = 0.5, LayoutOrder = order })
	UI.Corner(f, UI.R.md)
	UI.Text(f, string.upper(caption), { Font = T.semi, TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 14),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	UI.Text(f, tostring(value), { Face = "displayMed", TextSize = 21, TextColor3 = accent or T.text, Position = UDim2.fromOffset(12, 21), Size = UDim2.new(1, -24, 0, 26),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	return f
end

-- the name, UFC style: the first name on a small display line, the SURNAME big and scaled to its
-- box (down to minSize: a 16-letter surname still fits), the nickname in gold under it
local function nameBlock(parent, P, size, order)
	local id = P.identity or {}
	local first, last = FighterCard.SplitName(id)
	local holder = UI.Frame(parent, { Name = "NameBlock", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order or 0 })
	UI.List(holder, 0)
	local small = math.max(14, math.floor(size * 0.36))
	if first ~= "" then
		UI.Title(holder, string.upper(first), { Name = "First", Face = "displayMed", TextSize = small, TextColor3 = T.sub, Size = UDim2.new(1, 0, 0, small + 2), AutomaticSize = Enum.AutomaticSize.None,
			LayoutOrder = 1, TextTruncate = Enum.TextTruncate.AtEnd })
	end
	local lastLabel = UI.Title(holder, string.upper(last ~= "" and last or first), { Name = "Last", TextSize = size, TextScaled = true, Size = UDim2.new(1, 0, 0, size + 4),
		AutomaticSize = Enum.AutomaticSize.None, LayoutOrder = 2 })
	UI.New("UITextSizeConstraint", { MaxTextSize = size, MinTextSize = math.min(size, math.max(20, math.floor(size * 0.44))), Parent = lastLabel })
	local nick = (id.nickname and id.nickname ~= "") and ('"' .. string.upper(id.nickname) .. '"') or ""
	if nick ~= "" then
		local ns = math.max(15, math.floor(size * 0.34))
		local n = UI.Title(holder, nick, { Name = "Nick", TextSize = ns, TextColor3 = T.gold, Face = "displayMed", TextScaled = true, Size = UDim2.new(1, 0, 0, ns + 6),
			AutomaticSize = Enum.AutomaticSize.None, LayoutOrder = 3 })
		UI.New("UITextSizeConstraint", { MaxTextSize = ns, MinTextSize = math.min(ns, 14), Parent = n })
	end
	return holder
end
FighterCard.NameBlock = nameBlock

------------------------------------------------------------------------
-- Full card (the Career screen)
------------------------------------------------------------------------
function FighterCard.Full(parent, P, opts)
	opts = opts or {}
	local small = opts.compact == true
	local id = P.identity or {}
	local card = UI.Frame(parent, { Name = "FighterCard", Size = opts.Size or UDim2.fromOffset(1240, 640), BackgroundTransparency = 1 })
	if opts.Position then
		card.Position = opts.Position
	end
	if opts.AnchorPoint then
		card.AnchorPoint = opts.AnchorPoint
	end
	-- photo column
	local photoW = small and 300 or 430
	local frame = UI.Frame(card, { Name = "PhotoFrame", Size = UDim2.new(0, photoW, 1, 0), BackgroundColor3 = T.ink })
	UI.Corner(frame, UI.R.xl)
	UI.Stroke(frame, Color3.new(1, 1, 1), 1, 0.86)
	local cardH = (opts.Size and opts.Size.Y.Offset > 0) and opts.Size.Y.Offset or 640
	local photo = FighterCard.Photo(frame, { Size = UDim2.fromScale(1, 1), aspect = photoW / cardH })
	UI.Corner(photo, UI.R.xl)
	local ri = FighterCard.RecordInfo(P)
	-- OVR badge + flag on the photo
	local ovr = UI.Frame(frame, { Name = "OVR", Position = UDim2.fromOffset(18, 18), Size = UDim2.fromOffset(84, 84), BackgroundColor3 = T.ink, BackgroundTransparency = 0.25, ZIndex = 5 })
	UI.Corner(ovr, UI.R.lg)
	UI.Stroke(ovr, T.gold, 1.5, 0.15)
	UI.Text(ovr, tostring(P.overall or 0), { Face = "number", TextSize = 44, TextColor3 = T.gold, Size = UDim2.new(1, 0, 0, 52), Position = UDim2.fromOffset(0, 6),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
	UI.Text(ovr, "OVERALL", { Font = T.semi, TextSize = 11, TextColor3 = T.sub, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -22),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
	Flags.Draw(frame, id.nationality, { Size = UDim2.fromOffset(54, 36), Position = UDim2.new(1, -72, 0, 22), ZIndex = 5, radius = 3 })
	-- nameplate on the photo
	local plate = UI.Frame(frame, { Name = "Plate", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 22, 1, -20), Size = UDim2.new(1, -44, 0, 70), BackgroundTransparency = 1, ZIndex = 5 })
	UI.Text(plate, string.upper(P.className or ""), { Face = "displayMed", TextSize = 22, TextColor3 = T.text, Size = UDim2.new(1, 0, 0, 26), AutomaticSize = Enum.AutomaticSize.None, ZIndex = 6, TextWrapped = false })
	UI.Text(plate, string.format("%s  ·  %s", string.upper(P.tierName or ""), string.upper(id.nationality or "")), { Font = T.semi, TextSize = 13, TextColor3 = T.sub, Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.None, ZIndex = 6, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	local bar = UI.Frame(plate, { Position = UDim2.fromOffset(0, 56), Size = UDim2.fromOffset(120, 4), BackgroundColor3 = T.red, ZIndex = 6 })
	UI.Gradient(bar, Color3.new(1, 1, 1), 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }))

	-- info column (scrolls on short screens)
	local info = UI.Scroll(card, { Name = "Info", Position = UDim2.new(0, photoW + (small and 20 or 36), 0, 0), Size = UDim2.new(1, -(photoW + (small and 20 or 36)), 1, 0) })
	UI.List(info, small and 8 or 10)
	UI.Pad(info, 0, 2)
	UI.Kicker(info, ri.pro and ("PROFESSIONAL BOXER  ·  " .. string.upper(P.className or "") .. " DIVISION") or ("AMATEUR BOXER  ·  " .. string.upper(P.className or "")), T.gold, { order = 1 })
	nameBlock(info, P, small and 48 or 68, 2)
	-- the headline numbers: record, knockouts, KO ratio, ranking (a dash / UNRANKED until they mean something)
	local cardW = (opts.Size and opts.Size.X.Offset > 0) and opts.Size.X.Offset or 1240
	local infoW = cardW - photoW - (small and 20 or 36)
	-- a scaled-down screen draws its captions at the readability floor (15 design px on a phone): the
	-- tiles were sized for 11, so they take the short captions (the kicker above already says amateur /
	-- pro), and a narrow info column (a small phone) puts the ranking on a row of its own
	local terse = small or UI.ScaleOf(parent) < 1
	local tight = infoW < 520
	local rowH = small and 60 or 84
	local strip = UI.Frame(info, { Name = "Numbers", BackgroundTransparency = 1, Size = UDim2.new(1, -6, 0, tight and (rowH * 2 + 8) or rowH), LayoutOrder = 3 })
	local rankText, champ, rankCaption = FighterCard.BestRank(P)
	if terse then
		rankCaption = rankCaption:gsub("^AMATEUR  ·  ", ""):gsub("TO TURN PRO", "TO GO PRO")
	end
	local numbers = {
		{ ri.text, terse and "RECORD" or (ri.pro and "PRO RECORD" or "AMATEUR RECORD"), T.text, tight and 0.38 or 0.22 },
		{ tostring(ri.ko), terse and "KOS" or "KNOCKOUTS", ri.ko > 0 and T.red or nil, tight and 0.31 or 0.17 },
		{ FighterCard.KOText(ri), terse and "KO %" or "KO RATIO", ri.koPct and T.text or T.dim, tight and 0.31 or 0.17 },
		{ rankText, rankCaption, champ and T.gold or (rankText == "UNRANKED" and T.sub or T.text), tight and 1 or 0.44 },
	}
	local rows = { strip }
	if tight then
		UI.List(strip, 8)
		for r = 1, 2 do
			rows[r] = UI.Frame(strip, { Name = "Row" .. r, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, rowH), LayoutOrder = r })
			UI.List(rows[r], 10, true)
		end
	else
		UI.List(strip, 10, true)
	end
	for i, n in ipairs(numbers) do
		local row = rows[(tight and i == 4) and 2 or 1]
		UI.Stat(row, n[1], n[2], { Size = UDim2.new(n[4], n[4] < 1 and -8 or -2, 1, 0), valueColor = n[3], valueSize = small and 28 or 38, order = i, scaled = true })
	end
	-- tale of the tape
	UI.Kicker(info, "TALE OF THE TAPE", T.sub, { order = 4 })
	-- four cells a row; two when the info column is narrow (a small phone: "Boxer-Puncher" and
	-- "POPULARITY" need the room)
	local tapeCols = tight and 2 or 4
	local tapeRows = math.ceil(8 / tapeCols)
	local grid = UI.Frame(info, { Name = "Tape", BackgroundTransparency = 1, Size = UDim2.new(1, -6, 0, tapeRows * 54 + (tapeRows - 1) * 8), LayoutOrder = 5 })
	UI.Grid(grid, UDim2.new(1 / tapeCols, -8, 0, 54), nil, 8)
	local phys = P.physical or {}
	local cells = {
		{ "Age", tostring(id.age or "?") },
		{ "Height", Config.HeightText and phys.height and Config.HeightText(phys.height) or "?" },
		{ "Reach", phys.reach and (phys.reach .. " in") or "?" },
		{ "Weight", P.weight and string.format("%.1f lbs", P.weight) or "?" },
		{ "Style", P.style or "?" },
		{ "Physique", P.physique or "?", T.gold },
		{ "Specialty", P.specialty or "?" },
		{ "Popularity", tostring(P.popularity or 0) },
	}
	for i, c in ipairs(cells) do
		tapeCell(grid, c[1], c[2], i, c[3])
	end
	-- the championships: the four world belts as goals, lit when held
	UI.Kicker(info, "CHAMPIONSHIPS", T.gold, { order = 6 })
	beltRow(info, P, 7, small and 96 or 112)
	-- rankings by organisation
	UI.Kicker(info, "WORLD RANKINGS", T.sub, { order = 8 })
	local ranks = UI.Frame(info, { Name = "Ranks", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 9 })
	UI.List(ranks, 8, true)
	for i, org in ipairs(Config.Orgs) do
		local r = type(P.ranks) == "table" and P.ranks[org]
		local text = r == "C" and (org .. "  CHAMPION") or (r and (org .. "  #" .. tostring(r)) or (org .. "  —"))
		if r == "C" then
			UI.Badge(ranks, text, T.gold, { order = i, h = 28, TextSize = 13 })
		else
			UI.Chip(ranks, text, r and T.text or T.dim, { order = i, h = 28, TextSize = 13 })
		end
	end
	UI.Kicker(info, "RECENT FORM", T.sub, { order = 10 })
	formBubbles(info, FighterCard.Form(P, 6), 11)
	return card
end

------------------------------------------------------------------------
-- Compact card (Career Hub header)
------------------------------------------------------------------------
function FighterCard.Compact(parent, P, opts)
	opts = opts or {}
	local id = P.identity or {}
	local card = UI.Frame(parent, { Name = "FighterCardCompact", Size = UDim2.new(1, -8, 0, 196), BackgroundColor3 = T.panel, BackgroundTransparency = 0.05, LayoutOrder = opts.order or 0 })
	UI.Corner(card, UI.R.lg)
	UI.Stroke(card, Color3.new(1, 1, 1), 1, 0.9)
	UI.Gradient(card, { Color3.fromRGB(255, 225, 225), Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190) }, 0)
	local photo = FighterCard.Photo(card, { Size = UDim2.new(0, 156, 1, 0), aspect = 156 / 196 })
	UI.Corner(photo, UI.R.lg)
	local x = 174
	Flags.Draw(card, id.nationality, { Size = UDim2.fromOffset(30, 20), Position = UDim2.fromOffset(x, 14) })
	UI.Text(card, string.upper((P.className or "") .. "  ·  " .. (P.tierName or "")), { Font = T.semi, TextSize = 12, TextColor3 = T.gold, Position = UDim2.fromOffset(x + 40, 16),
		Size = UDim2.new(1, -(x + 60), 0, 16), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	local nb = UI.Frame(card, { BackgroundTransparency = 1, Position = UDim2.fromOffset(x, 38), Size = UDim2.new(1, -(x + 20), 0, 80) })
	UI.List(nb, 0)
	nameBlock(nb, P, 36, 1)
	local ri = FighterCard.RecordInfo(P)
	local strip = UI.Frame(card, { BackgroundTransparency = 1, Position = UDim2.new(0, x, 1, -66), Size = UDim2.new(1, -(x + 16), 0, 54) })
	UI.List(strip, 8, true)
	local rankText, champ = FighterCard.BestRank(P)
	-- (the line above the name already says amateur / pro: "RECORD" fits the narrow tile on a phone)
	local widths = { 0.27, 0.16, 0.17, 0.34 } -- the record tile holds its caption at the phone's text floor
	for i, n in ipairs({ { ri.text, "RECORD" }, { tostring(ri.ko), "KOS" }, { tostring(P.overall or 0), "OVR" }, { rankText, "RANKING" } }) do
		UI.Stat(strip, n[1], n[2], { Size = UDim2.new(widths[i], -8, 1, 0), valueSize = 26, order = i, scaled = true,
			valueColor = (i == 4 and champ) and T.gold or ((i == 2 and ri.ko > 0) and T.red or ((i == 4 and rankText == "UNRANKED") and T.sub or T.text)) })
	end
	return card
end

return FighterCard
