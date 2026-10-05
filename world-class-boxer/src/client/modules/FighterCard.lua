-- FighterCard: the professional fighter card / tale of the tape for the local boxer.
-- A studio "photo" (ViewportFrame holding a snapshot clone of your character, lit like a fight
-- poster), name and nickname, weight class, record W-L-D, knockouts, belts, world rankings per
-- sanctioning body, physique, style, nationality flag and recent form. Two sizes:
--   FighterCard.Full(parent, P)      the Career screen of the main menu (about 1240 x 640 design px)
--   FighterCard.Compact(parent, P)   the header of the Career Hub's Career tab
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

------------------------------------------------------------------------
-- Data helpers (pure)
------------------------------------------------------------------------
local function rec(r)
	r = type(r) == "table" and r or {}
	return tonumber(r.w) or 0, tonumber(r.l) or 0, tonumber(r.d) or 0, tonumber(r.ko) or 0
end

-- "12-1-0", KOs, KO percentage of wins
function FighterCard.RecordInfo(P)
	local pro = (P.tier or 1) >= 2
	local w, l, d, ko = rec(pro and P.record or P.amateurRecord)
	return { w = w, l = l, d = d, ko = ko, text = string.format("%d-%d-%d", w, l, d), koPct = w > 0 and math.floor(ko / w * 100 + 0.5) or 0, pro = pro }
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

-- best ranking text: "WBC #4", "WBA CHAMPION", or "UNRANKED"
function FighterCard.BestRank(P)
	local best, bestOrg
	for _, org in ipairs(Config.Orgs) do
		local r = type(P.ranks) == "table" and P.ranks[org]
		if r == "C" then
			return org .. " CHAMPION", true
		end
		r = tonumber(r)
		if r and (not best or r < best) then
			best, bestOrg = r, org
		end
	end
	if best then
		return string.format("%s #%d", bestOrg, best), false
	end
	return (P.tier or 1) < 2 and "AMATEUR" or "UNRANKED", false
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
-- The photo: a snapshot clone of the character in a ViewportFrame
------------------------------------------------------------------------
local function pathOf(inst, root)
	local parts = {}
	while inst and inst ~= root do
		table.insert(parts, 1, inst.Name)
		inst = inst.Parent
	end
	return table.concat(parts, "/")
end

local STRIP = { Script = true, LocalScript = true, ModuleScript = true, Sound = true, ParticleEmitter = true, Trail = true, Beam = true,
	BillboardGui = true, ProximityPrompt = true, ClickDetector = true, BodyMover = true, AlignPosition = true, AlignOrientation = true }

function FighterCard.Snapshot()
	local char = player.Character
	if not (char and char:FindFirstChild("HumanoidRootPart")) then
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
	-- parts hidden locally (a mesh replacement drawn over the base body) must stay hidden in the photo
	local hidden = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d.LocalTransparencyModifier > 0 then
			hidden[pathOf(d, char)] = 1 - (1 - d.Transparency) * (1 - d.LocalTransparencyModifier)
		end
	end
	for _, d in ipairs(clone:GetDescendants()) do
		for _, tag in ipairs(CollectionService:GetTags(d)) do
			CollectionService:RemoveTag(d, tag)
		end
		if STRIP[d.ClassName] or d:IsA("BodyMover") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			local t = hidden[pathOf(d, clone)]
			if t then
				d.Transparency = t
			end
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
	for _, tag in ipairs(CollectionService:GetTags(clone)) do
		CollectionService:RemoveTag(clone, tag)
	end
	return clone
end

-- opts: Size, Position, framing = "upper" | "full"
function FighterCard.Photo(parent, opts)
	opts = opts or {}
	local holder = UI.Frame(parent, { Name = "Photo", Size = opts.Size or UDim2.fromScale(1, 1), BackgroundColor3 = T.ink, ClipsDescendants = true, ZIndex = opts.ZIndex or 1 })
	if opts.Position then
		holder.Position = opts.Position
	end
	-- poster backdrop: deep red to black with a spotlight bloom behind the head
	UI.Gradient(holder, { Color3.fromRGB(120, 18, 26), Color3.fromRGB(28, 10, 14), Color3.fromRGB(8, 8, 10) }, 90)
	local glow = UI.Frame(holder, { Name = "Spot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.32), Size = UDim2.fromScale(1.3, 0.9), BackgroundColor3 = Color3.fromRGB(255, 196, 120), ZIndex = holder.ZIndex })
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
	local clone = FighterCard.Snapshot()
	local root = clone and clone:FindFirstChild("HumanoidRootPart")
	local head = clone and clone:FindFirstChild("Head")
	if clone and root and head then
		clone.Parent = vf
		local cam = Instance.new("Camera")
		cam.FieldOfView = opts.fov or 24
		local look, right = root.CFrame.LookVector, root.CFrame.RightVector
		look = Vector3.new(look.X, 0, look.Z).Unit
		right = Vector3.new(right.X, 0, right.Z).Unit
		local full = opts.framing == "full"
		local target = full and (root.Position + Vector3.new(0, 0.6, 0)) or (head.Position - Vector3.new(0, 1.15, 0))
		local half = full and 3.8 or 2.3
		local dist = half / math.tan(math.rad(cam.FieldOfView / 2))
		cam.CFrame = CFrame.lookAt(target + look * dist + right * dist * 0.22 + Vector3.new(0, dist * 0.06, 0), target)
		cam.Parent = vf
		vf.CurrentCamera = cam
		-- key light from the front-left, above (LightDirection = the way the light travels)
		local dir = (-look * 0.7 + right * 0.45 + Vector3.new(0, -0.65, 0)).Unit
		vf.LightDirection = dir
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
local function belt(parent, title, order)
	local b = UI.Frame(parent, { Name = "Belt", Size = UDim2.fromOffset(112, 46), BackgroundColor3 = Color3.fromRGB(26, 22, 14), LayoutOrder = order or 0 })
	UI.Corner(b, 10)
	UI.Stroke(b, T.gold, 1.5, 0.2)
	UI.Gradient(b, { Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150) }, 90)
	local plate = UI.Frame(b, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(46, 34), BackgroundColor3 = T.gold })
	UI.Corner(plate, 12)
	UI.Gradient(plate, { Color3.fromRGB(255, 240, 190), T.goldDeep }, 110)
	UI.Text(plate, title.world and title.name or title.name:sub(1, 3), { Face = "number", TextSize = 15, TextColor3 = Color3.fromRGB(60, 40, 6), Size = UDim2.fromScale(1, 1),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
	for _, x in ipairs({ 0.12, 0.88 }) do
		local stud = UI.Frame(b, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = T.goldDeep })
		UI.Corner(stud, 5)
	end
	return b
end

local function formBubbles(parent, form, order)
	local row = UI.Frame(parent, { Name = "Form", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = order or 0 })
	UI.List(row, 6, true)
	if #form == 0 then
		UI.Text(row, "No fights yet - your story starts on fight night.", { TextSize = 13, TextColor3 = T.sub, Size = UDim2.new(1, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.None })
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

-- a tale-of-the-tape row: CAPTION (small) / value (display)
local function tapeCell(parent, caption, value, order, accent)
	local f = UI.Frame(parent, { Name = "Tape", BackgroundColor3 = T.panel2, BackgroundTransparency = 0.5, LayoutOrder = order })
	UI.Corner(f, UI.R.md)
	UI.Text(f, string.upper(caption), { Font = T.semi, TextSize = 11, TextColor3 = T.sub, Position = UDim2.fromOffset(12, 7), Size = UDim2.new(1, -24, 0, 13),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	UI.Text(f, tostring(value), { Face = "displayMed", TextSize = 21, TextColor3 = accent or T.text, Position = UDim2.fromOffset(12, 21), Size = UDim2.new(1, -24, 0, 26),
		AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	return f
end

local function nameBlock(parent, P, size)
	local id = P.identity or {}
	local name = UI.Title(parent, string.upper(id.name or "BOXER"), { Name = "Name", TextSize = size or 64, Size = UDim2.new(1, 0, 0, (size or 64) + 4), AutomaticSize = Enum.AutomaticSize.None,
		TextTruncate = Enum.TextTruncate.AtEnd })
	local nick = (id.nickname and id.nickname ~= "") and ('"' .. string.upper(id.nickname) .. '"') or ""
	local n = UI.Title(parent, nick, { Name = "Nick", TextSize = math.floor((size or 64) * 0.42), TextColor3 = T.gold, Face = "displayMed",
		Size = UDim2.new(1, 0, 0, math.floor((size or 64) * 0.42) + 6), AutomaticSize = Enum.AutomaticSize.None, TextTruncate = Enum.TextTruncate.AtEnd })
	return name, n
end

------------------------------------------------------------------------
-- Full card (the Career screen)
------------------------------------------------------------------------
function FighterCard.Full(parent, P, opts)
	opts = opts or {}
	local id = P.identity or {}
	local card = UI.Frame(parent, { Name = "FighterCard", Size = opts.Size or UDim2.fromOffset(1240, 640), BackgroundTransparency = 1 })
	if opts.Position then
		card.Position = opts.Position
	end
	if opts.AnchorPoint then
		card.AnchorPoint = opts.AnchorPoint
	end
	-- photo column
	local photoW = 430
	local frame = UI.Frame(card, { Name = "PhotoFrame", Size = UDim2.new(0, photoW, 1, 0), BackgroundColor3 = T.ink })
	UI.Corner(frame, UI.R.xl)
	UI.Stroke(frame, Color3.new(1, 1, 1), 1, 0.86)
	local photo = FighterCard.Photo(frame, { Size = UDim2.fromScale(1, 1), framing = "upper" })
	UI.Corner(photo, UI.R.xl)
	local ri = FighterCard.RecordInfo(P)
	-- OVR badge + flag on the photo
	local ovr = UI.Frame(frame, { Name = "OVR", Position = UDim2.fromOffset(18, 18), Size = UDim2.fromOffset(84, 84), BackgroundColor3 = T.ink, BackgroundTransparency = 0.25, ZIndex = 5 })
	UI.Corner(ovr, UI.R.lg)
	UI.Stroke(ovr, T.gold, 1.5, 0.15)
	UI.Text(ovr, tostring(P.overall or 0), { Face = "number", TextSize = 44, TextColor3 = T.gold, Size = UDim2.new(1, 0, 0, 52), Position = UDim2.fromOffset(0, 6),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
	UI.Text(ovr, "OVERALL", { Font = T.semi, TextSize = 10, TextColor3 = T.sub, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -22),
		AutomaticSize = Enum.AutomaticSize.None, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
	Flags.Draw(frame, id.nationality, { Size = UDim2.fromOffset(54, 36), Position = UDim2.new(1, -72, 0, 22), ZIndex = 5, radius = 3 })
	-- nameplate on the photo
	local plate = UI.Frame(frame, { Name = "Plate", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 22, 1, -20), Size = UDim2.new(1, -44, 0, 70), BackgroundTransparency = 1, ZIndex = 5 })
	UI.Text(plate, string.upper(P.className or ""), { Face = "displayMed", TextSize = 22, TextColor3 = T.text, Size = UDim2.new(1, 0, 0, 26), AutomaticSize = Enum.AutomaticSize.None, ZIndex = 6, TextWrapped = false })
	UI.Text(plate, string.format("%s  ·  %s", string.upper(P.tierName or ""), string.upper(id.nationality or "")), { Font = T.semi, TextSize = 13, TextColor3 = T.sub, Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.None, ZIndex = 6, TextWrapped = false })
	local bar = UI.Frame(plate, { Position = UDim2.fromOffset(0, 56), Size = UDim2.fromOffset(120, 4), BackgroundColor3 = T.red, ZIndex = 6 })
	UI.Gradient(bar, Color3.new(1, 1, 1), 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }))

	-- info column
	local info = UI.Frame(card, { Name = "Info", Position = UDim2.new(0, photoW + 36, 0, 0), Size = UDim2.new(1, -(photoW + 36), 1, 0), BackgroundTransparency = 1 })
	UI.List(info, 10)
	UI.Kicker(info, ri.pro and ("PROFESSIONAL BOXER  ·  " .. string.upper(P.className or "") .. " DIVISION") or ("AMATEUR BOXER  ·  " .. string.upper(P.className or "")), T.gold, { order = 1 })
	local nameHolder = UI.Frame(info, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	UI.List(nameHolder, -6)
	nameBlock(nameHolder, P, 66)
	-- the headline numbers
	local strip = UI.Frame(info, { Name = "Numbers", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 84), LayoutOrder = 3 })
	UI.List(strip, 10, true)
	local rankText, champ = FighterCard.BestRank(P)
	local titles = FighterCard.Titles(P)
	local numbers = {
		{ ri.text, ri.pro and "PRO RECORD" or "AMATEUR RECORD", T.text },
		{ tostring(ri.ko), "KNOCKOUTS", T.red },
		{ ri.koPct .. "%", "KO RATIO", T.text },
		{ tostring(#titles), "TITLES", #titles > 0 and T.gold or T.text },
		{ rankText, "BEST RANKING", champ and T.gold or T.text },
	}
	for i, n in ipairs(numbers) do
		UI.Stat(strip, n[1], n[2], { Size = UDim2.new(i == 5 and 0.26 or 0.172, -8, 1, 0), valueColor = n[3], valueSize = 38, order = i, scaled = true })
	end
	-- tale of the tape
	UI.Kicker(info, "TALE OF THE TAPE", T.sub, { order = 4 })
	local grid = UI.Frame(info, { Name = "Tape", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 116), LayoutOrder = 5 })
	UI.Grid(grid, UDim2.new(0.25, -8, 0, 54), nil, 8)
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
	-- rankings by organisation + belts
	UI.Kicker(info, "WORLD RANKINGS", T.sub, { order = 6 })
	local ranks = UI.Frame(info, { Name = "Ranks", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 7 })
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
	if #titles > 0 then
		UI.Kicker(info, "CHAMPIONSHIPS", T.gold, { order = 8 })
		local belts = UI.Frame(info, { Name = "Belts", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), LayoutOrder = 9 })
		UI.List(belts, 10, true)
		for i, t in ipairs(titles) do
			belt(belts, t, i)
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
	local card = UI.Frame(parent, { Name = "FighterCardCompact", Size = UDim2.new(1, -8, 0, 186), BackgroundColor3 = T.panel, BackgroundTransparency = 0.05, LayoutOrder = opts.order or 0 })
	UI.Corner(card, UI.R.lg)
	UI.Stroke(card, Color3.new(1, 1, 1), 1, 0.9)
	UI.Gradient(card, { Color3.fromRGB(255, 225, 225), Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190) }, 0)
	local photo = FighterCard.Photo(card, { Size = UDim2.new(0, 150, 1, 0), framing = "upper" })
	UI.Corner(photo, UI.R.lg)
	local x = 168
	Flags.Draw(card, id.nationality, { Size = UDim2.fromOffset(30, 20), Position = UDim2.fromOffset(x, 16) })
	UI.Text(card, string.upper((P.className or "") .. "  ·  " .. (P.tierName or "")), { Font = T.semi, TextSize = 12, TextColor3 = T.gold, Position = UDim2.fromOffset(x + 40, 18),
		Size = UDim2.new(1, -(x + 60), 0, 16), AutomaticSize = Enum.AutomaticSize.None, TextWrapped = false })
	local nb = UI.Frame(card, { BackgroundTransparency = 1, Position = UDim2.fromOffset(x, 40), Size = UDim2.new(1, -(x + 20), 0, 70) })
	UI.List(nb, -4)
	nameBlock(nb, P, 40)
	local ri = FighterCard.RecordInfo(P)
	local strip = UI.Frame(card, { BackgroundTransparency = 1, Position = UDim2.new(0, x, 1, -64), Size = UDim2.new(1, -(x + 16), 0, 52) })
	UI.List(strip, 8, true)
	local rankText, champ = FighterCard.BestRank(P)
	for i, n in ipairs({ { ri.text, ri.pro and "RECORD" or "AMATEUR" }, { tostring(ri.ko), "KOS" }, { tostring(P.overall or 0), "OVR" }, { rankText, "RANKING" } }) do
		UI.Stat(strip, n[1], n[2], { Size = UDim2.new(i == 4 and 0.34 or 0.2, -8, 1, 0), valueSize = 26, order = i, scaled = true,
			valueColor = (i == 4 and champ) and T.gold or (i == 2 and T.red or T.text) })
	end
	return card
end

return FighterCard
