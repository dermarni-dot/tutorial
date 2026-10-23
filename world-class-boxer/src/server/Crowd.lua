-- Crowd: the fight venues' spectators and stands. Venues.buildTemplate calls Crowd.Build on every venue template
-- (sold out), Venues.New calls Crowd.Apply on each fight's clone (the house Venues.CrowdFill draws, the supporters,
-- the signs). Everything that moves (sitting / standing / jumping, arms, phones, signs, the printed rows and the
-- upper bowl, the reaction waves) is the client's src/client/modules/CrowdFX.lua.
--
-- Three kinds of fan, by how close the fight cameras get (CONTRACTS 11: no per-fan scripts, no Builder NPCs):
--   full   ringside row 0, the VIP boxes, the press box, the standers: Fan (torso, the root) + Head (a classic head
--          mesh wearing one of the drawn Boxer faces as its front Decal) + ArmL / ArmR + Lap (seated; CrowdFX turns it
--          into legs when he stands) or Legs + an optional Hat (cap, beanie, bucket) + an optional Phone. 5-7 parts.
--   lite   the next physical row(s): Fan + Head + ArmL + ArmR (+ Hat). 4-5 parts.
--   print  every row behind, the standing room and the upper bowl: one slab per seating block (attributes
--          CrowdCols / Seed / RowFrac / Standing / CrowdRows); CrowdFX draws its fans on the slab's ring-facing
--          surface (a flat body, a round face wearing a drawn face, arms, hats) and animates them. Zero parts a fan.
-- No two fans the same: build (shoulders, height, women), skin tone, face, headwear (BaldMode: caps, beanies and
-- bucket hats or bald), clothing style (jersey with a number, hoodie, jacket, tee, suit at ringside / in the boxes)
-- and colour, what they hold.
--
-- Stands: tiered rows with the venue's rake (tread tops at row * rowRise + 0.5, the geometry VenueDetail's aisle
-- nosings and rails expect), seat rows per block, a mid aisle on the walkway-free sides and the walkway aisles on
-- the others, stair lights on every aisle step, glass-railed VIP boxes with leather seats and a drinks table, a
-- MEDIA box with monitors, sponsor boards on the fascias, LED ribbons, broadcast camera platforms (a camera and its
-- operator on a railed riser), a photographers' pit at the apron and a standing-room rail at the top.
--
-- Attributes CrowdFX reads: on the arena CrowdShare (0..1) and CrowdReact ("event|who|seq", Crowd.React); on a Fan
-- Row, Side, Rig (full / lite), VIP, Standing, Supporter, Fav (1 the player's fan, -1 the opponent's, 0 neutral),
-- Style, Energy, Phone; on a print slab CrowdCols, Seed, RowFrac, Standing, CrowdRows (bowl tiers), Side.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Looks = require(Shared:WaitForChild("Looks"))
local Typography = require(Shared:WaitForChild("Typography"))
local BodyTiers
do
	local ok, m = pcall(function()
		return require(Shared:WaitForChild("BodyTiers"))
	end)
	BodyTiers = ok and m or nil
end

local Crowd = {}

local V3 = Vector3.new
local CF = CFrame.new
local M = Enum.Material
local FACE = Enum.NormalId

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local function c3(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local BLACK = rgb(14, 14, 18)
local WHITE = rgb(238, 238, 238)
local GOLD = rgb(255, 200, 40)
local RED = rgb(200, 25, 30)

-- the seat pitch (studs between neighbours) and the rows of real rigs per venue tier (row 0 is always full rigs)
Crowd.SEAT = 3.0
Crowd.PHYSICAL_ROWS = { [1] = 2, [2] = 3, [3] = 2, [4] = 2 }
-- fans per box, boxes per block side
Crowd.VIP_SEATS = 4

------------------------------------------------------------------------
-- part helpers (the same conventions as Venues': anchored, no touches; dressing never collides or queries)
------------------------------------------------------------------------
local function part(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function deco(parent, name, size, cf, color, material, extra)
	local props = { Name = name, Size = size, CFrame = cf, Color = color, Material = material or M.SmoothPlastic }
	for k, v in pairs(extra or {}) do
		props[k] = v
	end
	return part(parent, props)
end

local function prop(parent, name, size, cf, color, material, extra)
	local p = deco(parent, name, size, cf, color, material, extra)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- a fan's part: never collides, queries, touches or casts (hundreds of them)
local FANP = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
local function fanPart(parent, name, size, cf, color, material)
	return prop(parent, name, size, cf, color, material or M.Fabric, FANP)
end

local function blob(parent, name, size, cf, color, material, extra)
	local p = prop(parent, name, size, cf, color, material, extra)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

local function gui(p, face, pps, light, bright)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = pps or 14
	sg.LightInfluence = light or 0
	sg.Brightness = bright or 1
	sg.MaxDistance = 420
	sg.ClipsDescendants = true
	sg.Parent = p
	return sg
end

local function frame(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in pairs(props) do
		f[k] = v
	end
	f.Parent = parent
	return f
end

local function label(parent, props)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	Typography.Apply(t, "sign")
	t.TextScaled = true
	t.TextColor3 = WHITE
	t.Text = ""
	for k, v in pairs(props) do
		if k == "Face" then
			Typography.Apply(t, v)
		else
			t[k] = v
		end
	end
	t.Parent = parent
	return t
end

local function round(f, scale)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale or 0.5, 0)
	c.Parent = f
	return c
end

local function sign(p, face, text, bg, fg, pps, font, light)
	local sg = gui(p, face, pps or 14, light or 0, 1)
	label(sg, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = bg or BLACK, BackgroundTransparency = bg and 0 or 1, TextColor3 = fg or GOLD, Face = font or "sign", Text = text })
	return sg
end

local function rod(parent, name, p0, p1, thick, color, material)
	local len = (p1 - p0).Magnitude
	local d = p1 - p0
	local cf
	if len < 1e-4 then
		cf = CF(p0)
	elseif math.abs(d.Unit.Y) > 0.98 then
		cf = CFrame.lookAt((p0 + p1) / 2, p1, Vector3.xAxis)
	else
		cf = CFrame.lookAt((p0 + p1) / 2, p1)
	end
	return prop(parent, name, V3(thick, thick, len), cf, color, material or M.Metal, { CastShadow = false })
end

------------------------------------------------------------------------
-- Looks: who the fans are
------------------------------------------------------------------------
-- clothing by style: the colours a style comes in (a fan's shirt = one of them, his sleeves the same or the jacket's)
local JERSEY = { { 200, 30, 30 }, { 30, 60, 200 }, { 240, 240, 240 }, { 20, 20, 24 }, { 240, 190, 40 }, { 40, 150, 70 }, { 130, 40, 170 }, { 240, 120, 30 }, { 0, 170, 190 }, { 240, 120, 170 } }
local HOODIE = { { 60, 60, 66 }, { 30, 36, 60 }, { 24, 24, 28 }, { 110, 30, 40 }, { 90, 90, 96 }, { 40, 80, 60 }, { 150, 150, 158 }, { 70, 40, 90 } }
local JACKET = { { 26, 26, 30 }, { 70, 50, 36 }, { 60, 70, 50 }, { 40, 60, 110 }, { 120, 40, 40 }, { 150, 150, 158 } }
local TEE = { { 240, 240, 240 }, { 200, 200, 205 }, { 20, 20, 24 }, { 230, 90, 60 }, { 90, 160, 220 }, { 240, 220, 120 }, { 130, 200, 150 }, { 240, 170, 200 }, { 170, 120, 70 }, { 60, 60, 66 } }
local SUIT = { { 26, 30, 44 }, { 30, 30, 34 }, { 50, 50, 56 }, { 40, 30, 30 }, { 20, 22, 30 } }
local HATS = { { 200, 30, 30 }, { 30, 60, 200 }, { 20, 20, 24 }, { 240, 240, 240 }, { 60, 60, 66 }, { 40, 110, 60 }, { 240, 190, 40 }, { 120, 80, 50 } }
local STYLES = { "jersey", "hoodie", "jacket", "tee", "tee", "jersey" }
-- the resting drawn faces fans wear, weighted (Looks.NPC_FACES when the Looks module exports it)
local FACES = Looks.NPC_FACES or {
	{ "wcb_neutral", 0.3 }, { "wcb_grin", 0.14 }, { "wcb_smirk", 0.1 }, { "wcb_focused", 0.1 }, { "wcb_confident", 0.08 },
	{ "wcb_cool", 0.08 }, { "wcb_toothy", 0.06 }, { "wcb_determined", 0.05 }, { "wcb_stern", 0.04 }, { "wcb_wink", 0.03 }, { "wcb_grit", 0.02 },
}
-- fans smile more than boxers: the friendly faces weigh in again
local FAN_FACES = {}
do
	local boost = { wcb_grin = 4, wcb_toothy = 4, wcb_smirk = 2, wcb_cool = 2, wcb_wink = 2, wcb_confident = 1.5 }
	for _, f in ipairs(FACES) do
		table.insert(FAN_FACES, { f[1], f[2] * (boost[f[1]] or 1) })
	end
end

local faceIds = nil
local function faceId(key)
	if not faceIds then
		faceIds = {}
		if BodyTiers and BodyTiers.Face then
			for _, f in ipairs(FAN_FACES) do
				local ok, e = pcall(BodyTiers.Face, f[1])
				if ok and type(e) == "table" and e.id then
					faceIds[f[1]] = e.id
				end
			end
		end
	end
	return faceIds[key]
end

local function pick(rng, list)
	return list[rng:NextInteger(1, #list)]
end

local function faceKey(rng)
	local total = 0
	for _, f in ipairs(FAN_FACES) do
		total += f[2]
	end
	local r = rng:NextNumber() * total
	for _, f in ipairs(FAN_FACES) do
		if r < f[2] then
			return f[1]
		end
		r -= f[2]
	end
	return FAN_FACES[1][1]
end

-- one fan's look. o.dress: "ringside" (suits and jackets likely), "vip" (suits), "press", or nil (anyone)
function Crowd.Look(rng, o)
	o = o or {}
	local L = {}
	local skin = Looks.SkinTones[rng:NextInteger(1, #Looks.SkinTones)]
	L.skin = c3(skin)
	L.female = rng:NextNumber() < 0.38
	-- build: shoulders and height; women narrower
	L.w = (L.female and 1.35 or 1.6) * (0.88 + rng:NextNumber() * 0.26)
	L.h = (L.female and 1.85 or 2.0) * (0.9 + rng:NextNumber() * 0.2)
	L.face = faceKey(rng)
	-- headwear (BaldMode: no hair): caps and beanies, or bald
	local hr = rng:NextNumber()
	if o.dress == "vip" or o.dress == "press" then
		L.hat = hr < 0.12 and "cap" or nil
	else
		L.hat = hr < 0.38 and "cap" or (hr < 0.52 and "beanie" or (hr < 0.58 and "bucket" or nil))
	end
	L.hatColor = c3(pick(rng, HATS))
	-- clothing
	local style
	if o.dress == "vip" then
		style = rng:NextNumber() < 0.75 and "suit" or "jacket"
	elseif o.dress == "press" then
		style = rng:NextNumber() < 0.5 and "jacket" or "tee"
	elseif o.dress == "ringside" then
		local r = rng:NextNumber()
		style = r < 0.35 and "suit" or (r < 0.6 and "jacket" or pick(rng, STYLES))
	else
		style = pick(rng, STYLES)
	end
	L.style = style
	if style == "jersey" then
		L.shirt = c3(pick(rng, JERSEY))
		L.number = rng:NextInteger(1, 99)
	elseif style == "hoodie" then
		L.shirt = c3(pick(rng, HOODIE))
	elseif style == "jacket" then
		L.shirt = c3(pick(rng, JACKET))
		L.inner = c3(pick(rng, TEE))
	elseif style == "suit" then
		L.shirt = c3(pick(rng, SUIT))
		L.tie = rng:NextNumber() < 0.7 and c3(pick(rng, { { 140, 20, 30 }, { 20, 36, 110 }, { 20, 20, 24 }, { 200, 160, 40 }, { 60, 60, 66 } })) or nil
	else
		L.shirt = c3(pick(rng, TEE))
	end
	L.pants = rng:NextNumber() < 0.55 and rgb(28, 28, 34) or (rng:NextNumber() < 0.5 and rgb(40, 50, 90) or rgb(70, 60, 50))
	if style == "suit" then
		L.pants = L.shirt
	end
	-- what he holds: a phone up (recording), nothing
	L.phone = rng:NextNumber() < (o.dress == "vip" and 0.25 or 0.3)
	-- how lively: the jumpers, the clappers, the calm ones
	local er = rng:NextNumber()
	L.energy = er < 0.25 and 0.6 or (er < 0.8 and 1 or 1.4)
	return L
end

------------------------------------------------------------------------
-- rigs
------------------------------------------------------------------------
local function shirtPrint(torso, L)
	if L.style == "tee" or (L.style == "hoodie" and not L.printHood) then
		return
	end
	local sg = gui(torso, FACE.Front, 24, 1, 1)
	sg.Name = "Print"
	if L.style == "jersey" then
		label(sg, { Size = UDim2.fromScale(0.6, 0.5), Position = UDim2.fromScale(0.2, 0.2), Text = tostring(L.number), TextColor3 = L.shirt:Lerp(L.shirt.R + L.shirt.G + L.shirt.B > 1.5 and BLACK or WHITE, 0.85), Face = "number" })
	elseif L.style == "jacket" then
		-- the open jacket shows the shirt under it
		frame(sg, { Size = UDim2.fromScale(0.26, 0.62), Position = UDim2.fromScale(0.37, 0), BackgroundColor3 = L.inner })
	elseif L.style == "suit" then
		frame(sg, { Size = UDim2.fromScale(0.24, 0.46), Position = UDim2.fromScale(0.38, 0), BackgroundColor3 = rgb(236, 236, 240) })
		if L.tie then
			frame(sg, { Size = UDim2.fromScale(0.1, 0.56), Position = UDim2.fromScale(0.45, 0.04), BackgroundColor3 = L.tie, ZIndex = 2 })
		end
	elseif L.style == "hoodie" then
		frame(sg, { Size = UDim2.fromScale(0.5, 0.2), Position = UDim2.fromScale(0.25, 0.62), BackgroundColor3 = L.shirt:Lerp(BLACK, 0.3) })
	end
end

local function headOf(m, L, cf, size)
	local head = fanPart(m, "Head", V3(size, size * 1.06, size), cf, L.skin, M.SmoothPlastic)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = V3(1.2, 1.2, 1.2)
	mesh.Parent = head
	local id = faceId(L.face)
	if id then
		local d = Instance.new("Decal")
		d.Name = "face"
		d.Face = FACE.Front
		d.Texture = "rbxassetid://" .. tostring(id)
		d.Color3 = Color3.new(1, 1, 1)
		d.Parent = head
	end
	return head
end

local function hatOf(m, L, headCF, size)
	if not L.hat then
		return
	end
	if L.hat == "cap" then
		local cap = blob(m, "Hat", V3(size * 1.12, size * 0.5, size * 1.12), headCF * CF(0, size * 0.36, 0.02), L.hatColor, M.Fabric, FANP)
		cap:SetAttribute("Kind", "cap")
		fanPart(m, "HatBrim", V3(size * 0.9, 0.06, size * 0.55), headCF * CF(0, size * 0.3, -size * 0.6), L.hatColor, M.Fabric)
	elseif L.hat == "beanie" then
		local b = blob(m, "Hat", V3(size * 1.1, size * 0.72, size * 1.1), headCF * CF(0, size * 0.3, 0), L.hatColor, M.Fabric, FANP)
		b:SetAttribute("Kind", "beanie")
	else
		local b = blob(m, "Hat", V3(size * 1.35, size * 0.42, size * 1.35), headCF * CF(0, size * 0.4, 0), L.hatColor:Lerp(BLACK, 0.2), M.Fabric, FANP)
		b:SetAttribute("Kind", "bucket")
	end
end

-- arm about the shoulder: CrowdFX recomputes this with its own pitch / roll
local function armCF(torsoCF, side, w, h, pitch, roll)
	return torsoCF * CF(side * (w / 2 + 0.22), h / 2 - 0.25, 0) * CFrame.Angles(pitch or 0, 0, (roll or 0) * side) * CF(0, -0.8, 0)
end

-- a fan: cf = the seat (or the floor under a stander), LookVector toward the ring. o.rig = "full" | "lite",
-- o.pose = "sit" | "stand", o.dress
local function fan(parent, cf, rng, o)
	local L = Crowd.Look(rng, o)
	local full = o.rig == "full"
	local seated = o.pose ~= "stand"
	local w, h = L.w, L.h
	local hip = seated and 0.0 or 2.55
	local torsoY = hip + h / 2 + (seated and 0.05 or 0)
	local torsoCF = cf * CF(0, torsoY, 0)
	local torso = fanPart(parent, "Fan", V3(w, h, 0.85), torsoCF, L.shirt, M.Fabric)
	torso:SetAttribute("Rig", o.rig)
	torso:SetAttribute("Style", L.style)
	torso:SetAttribute("Energy", L.energy)
	torso:SetAttribute("Pose", seated and "sit" or "stand")
	local headSize = 1.0 + (w - 1.4) * 0.25
	local headCF = cf * CF(0, torsoY + h / 2 + headSize * 0.52, 0)
	headOf(torso, L, headCF, headSize)
	local armPitch = seated and (full and 0.55 or 0.4) or 0.12
	for _, side in ipairs({ -1, 1 }) do
		local arm = fanPart(torso, side < 0 and "ArmL" or "ArmR", V3(0.42, 1.65, 0.45), armCF(torsoCF, side, w, h, armPitch, 0.1), L.style == "tee" and L.skin:Lerp(L.shirt, 0.5) or L.shirt, M.Fabric)
		arm:SetAttribute("Side", side)
	end
	if full then
		if seated then
			fanPart(torso, "Lap", V3(w * 0.92, 0.55, 1.35), cf * CF(0, 0.28, -0.6), L.pants, M.Fabric)
		else
			fanPart(torso, "Legs", V3(w * 0.8, 2.55, 0.7), cf * CF(0, 1.28, 0), L.pants, M.Fabric)
		end
		hatOf(torso, L, headCF, headSize)
		shirtPrint(torso, L)
		if L.phone then
			-- held up in the right hand (CrowdFX keeps it at the hand); the screen glows toward the ring
			local ph = fanPart(torso, "Phone", V3(0.34, 0.6, 0.07), armCF(torsoCF, 1, w, h, armPitch, 0.1) * CF(0, -0.95, -0.2), rgb(20, 20, 24), M.SmoothPlastic)
			local sg = gui(ph, FACE.Front, 60, 0, 1.6)
			frame(sg, { Size = UDim2.fromScale(0.86, 0.9), Position = UDim2.fromScale(0.07, 0.05), BackgroundColor3 = rgb(190, 215, 255) })
			torso:SetAttribute("Phone", true)
		end
	elseif L.hat and rng:NextNumber() < 0.7 then
		-- lite rigs: the cap alone (no brim)
		local kind = L.hat
		local b = blob(torso, "Hat", V3(headSize * 1.1, headSize * (kind == "beanie" and 0.7 or 0.5), headSize * 1.1), headCF * CF(0, headSize * 0.33, 0), L.hatColor, M.Fabric, FANP)
		b:SetAttribute("Kind", kind)
	end
	return torso, L
end

------------------------------------------------------------------------
-- stands
------------------------------------------------------------------------
-- the seating blocks of one row on one side: sides 0 / 2 (the walkway sides) leave the 10-stud walkway aisle in the
-- middle and own the corners; sides 1 / 3 have a 3-stud mid aisle. {x0, x1} in the side's frame (+X to the left as
-- seen from the ring)
local function blocksOf(side, d0, d1)
	if side == 0 or side == 2 then
		return { { 5, d1 }, { -d1, -5 } }
	end
	return { { 1.5, d0 }, { -d0, -1.5 } }
end

local function rowTop(spec, row)
	local h = row * spec.rowRise
	return h > 0 and h + 0.5 or 0
end

-- the chairs / seat rows of a block. kind: "ringside" (individual luxury chairs), "seats" (a cushion slab and a seat
-- back with printed dividers), "folding" (the hall's chairs, one part each)
local function seating(st, spec, rot, b, row, kind, seatsX)
	local d0 = spec.rowStart + row * spec.rowGap
	local y = rowTop(spec, row)
	local zc = d0 + spec.rowGap / 2
	local w = b[2] - b[1]
	local xc = (b[1] + b[2]) / 2
	local col = spec.seats or rgb(40, 40, 48)
	if kind == "ringside" then
		local leather = spec.tier >= 3
		local scol = leather and rgb(22, 22, 26) or (spec.tier == 2 and rgb(110, 20, 26) or rgb(70, 70, 80))
		for _, x in ipairs(seatsX) do
			local base = rot * CF(x, y, zc)
			prop(st, "ChairSeat", V3(2.2, 0.5, 2.0), base * CF(0, 0.7, 0.1), scol, leather and M.Leather or M.Fabric, { CastShadow = false })
			local back = prop(st, "ChairBack", V3(2.2, 2.3, 0.35), base * CF(0, 1.95, 1.0), scol, leather and M.Leather or M.Fabric, { CastShadow = false })
			if leather then
				-- gold piping on the big shows' ringside chairs
				local sg = gui(back, FACE.Front, 16, 1, 1)
				local f = frame(sg, { Size = UDim2.fromScale(0.86, 0.84), Position = UDim2.fromScale(0.07, 0.08), BackgroundTransparency = 1 })
				local s = Instance.new("UIStroke")
				s.Thickness = 2
				s.Color = rgb(200, 160, 40)
				s.Parent = f
			end
		end
		return
	elseif kind == "folding" then
		for _, x in ipairs(seatsX) do
			deco(st, "Chair", V3(1.8, 1.6, 1.8), rot * CF(x, y + 0.8, zc + 0.3), rgb(70, 70, 80), M.Metal, { CanCollide = false, CastShadow = false })
		end
		return
	end
	-- a block's row of fixed seats: the cushions and the backs, one slab each, the dividers printed on the back
	prop(st, "SeatRow", V3(w, 0.5, 1.5), rot * CF(xc, y + 0.7, zc + 0.2), col, M.Fabric, { CastShadow = false })
	local back = prop(st, "SeatBack", V3(w, 1.6, 0.3), rot * CF(xc, y + 1.6, zc + 1.05), col, M.Fabric, { CastShadow = false })
	local sg = gui(back, FACE.Front, 8, 1, 1)
	local n = math.max(1, math.floor(w / Crowd.SEAT))
	local text = {}
	for _ = 1, n do
		table.insert(text, "▏")
	end
	local l = label(sg, { Size = UDim2.fromScale(1, 1), Text = table.concat(text, "      "), TextColor3 = col:Lerp(BLACK, 0.55), Face = "glyph", TextScaled = true })
	l.TextTransparency = 0.2
end

-- a print slab the client fills with fans: at the seats of a block
local function printRow(bowl, spec, rot, b, row, side, seed, standing)
	local d0 = spec.rowStart + row * spec.rowGap
	local y = rowTop(spec, row)
	local zc = d0 + spec.rowGap / 2 + (standing and 0.8 or 0.55)
	local w = b[2] - b[1]
	local xc = (b[1] + b[2]) / 2
	local col = (spec.seats or rgb(30, 30, 36)):Lerp(BLACK, 0.5)
	local hgt = standing and 5.2 or 3.6
	local slab = prop(bowl, "RowPrint", V3(w, hgt, 0.5), rot * CF(xc, y + (standing and 0 or 0.4) + hgt / 2, zc), col, M.Fabric, { CastShadow = false, Transparency = 1 })
	local sg = gui(slab, FACE.Front, 6, 1, 1)
	sg.Name = "CrowdPrint"
	slab:SetAttribute("CrowdCols", math.max(2, math.floor(w / Crowd.SEAT)))
	slab:SetAttribute("Seed", seed)
	slab:SetAttribute("Side", side)
	slab:SetAttribute("Row", row)
	slab:SetAttribute("RowFrac", math.clamp(row / math.max(1, spec.rows - 1), 0, 1))
	slab:SetAttribute("Standing", standing == true)
	slab:SetAttribute("Fill", 1)
	return slab
end

-- stair lights down an aisle edge: one per row step
local function stairLights(st, spec, rot, x, row)
	if spec.rowRise <= 0 or row == 0 then
		return
	end
	local d0 = spec.rowStart + row * spec.rowGap
	local y = rowTop(spec, row)
	prop(st, "StairLight", V3(0.5, 0.1, 0.12), rot * CF(x, y - 0.22, d0 - 0.06), rgb(90, 170, 255), M.Neon, { CastShadow = false })
end

-- a VIP box: a railed glass front, leather chairs, a drinks table, carpet and a VIP sign; fans in suits
local function vipBox(st, crowd, spec, rot, xc, row, side, rng, idx)
	local d0 = spec.rowStart + row * spec.rowGap
	local y = rowTop(spec, row)
	local zc = d0 + spec.rowGap / 2
	local bw = Crowd.VIP_SEATS * 2.4 + 1.2
	local m = Instance.new("Model")
	m.Name = "VIPBox"
	m:SetAttribute("Side", side)
	m:SetAttribute("Idx", idx)
	-- carpet and the low wall with its glass rail toward the ring
	prop(m, "VIPCarpet", V3(bw, 0.08, spec.rowGap - 0.4), rot * CF(xc, y + 0.04, zc), rgb(70, 16, 24), M.Fabric, { CastShadow = false })
	prop(m, "VIPWall", V3(bw, 1.0, 0.3), rot * CF(xc, y + 0.5, d0 + 0.3), rgb(24, 24, 28), M.Metal)
	prop(m, "VIPGlass", V3(bw, 1.6, 0.12), rot * CF(xc, y + 1.8, d0 + 0.3), rgb(160, 200, 230), M.Glass, { Transparency = 0.55, CastShadow = false })
	prop(m, "VIPRail", V3(bw + 0.2, 0.12, 0.12), rot * CF(xc, y + 2.62, d0 + 0.3), rgb(200, 160, 40), M.Metal, { CastShadow = false })
	for _, sx in ipairs({ -1, 1 }) do
		prop(m, "VIPPost", V3(0.14, 2.6, 0.14), rot * CF(xc + sx * (bw / 2 - 0.1), y + 1.3, d0 + 0.3), rgb(200, 160, 40), M.Metal, { CastShadow = false })
		-- side partitions
		prop(m, "VIPSide", V3(0.12, 2.4, spec.rowGap - 0.6), rot * CF(xc + sx * bw / 2, y + 1.2, zc), rgb(160, 200, 230), M.Glass, { Transparency = 0.6, CastShadow = false })
	end
	local wall = m:FindFirstChild("VIPWall")
	if wall then
		local sg = gui(wall, FACE.Front, 20, 0, 1.4)
		label(sg, { Size = UDim2.fromScale(0.6, 0.8), Position = UDim2.fromScale(0.2, 0.1), Text = "VIP", TextColor3 = GOLD })
	end
	-- the drinks table at the rail
	prop(m, "VIPTable", V3(1.6, 0.08, 0.8), rot * CF(xc, y + 1.1, d0 + 1.1), rgb(30, 26, 24), M.Wood, { CastShadow = false })
	prop(m, "VIPTableLeg", V3(0.12, 1.0, 0.12), rot * CF(xc, y + 0.55, d0 + 1.1), rgb(60, 60, 66), M.Metal, { CastShadow = false })
	for k = 1, 2 do
		local g = prop(m, "VIPGlassware", V3(0.22, 0.4, 0.22), rot * CF(xc + (k - 1.5) * 0.5, y + 1.34, d0 + 1.1), rgb(230, 200, 120), M.Glass, { Transparency = 0.3, CastShadow = false })
		g.Shape = Enum.PartType.Cylinder
		g.CFrame = g.CFrame * CFrame.Angles(0, 0, math.pi / 2)
	end
	-- leather chairs and their fans
	for i = 1, Crowd.VIP_SEATS do
		local x = xc + (i - (Crowd.VIP_SEATS + 1) / 2) * 2.4
		local base = rot * CF(x, y, zc + 0.6)
		prop(m, "VIPSeat", V3(2.0, 0.55, 2.0), base * CF(0, 0.75, 0), rgb(22, 22, 26), M.Leather, { CastShadow = false })
		prop(m, "VIPSeatBack", V3(2.0, 2.2, 0.4), base * CF(0, 1.9, 1.0), rgb(22, 22, 26), M.Leather, { CastShadow = false })
		prop(m, "VIPArm", V3(0.25, 0.5, 1.6), base * CF(i == 1 and -1.1 or 1.1, 1.25, 0.2), rgb(30, 30, 34), M.Leather, { CastShadow = false })
		local f = fan(crowd, base * CF(0, 1.0, 0), rng, { rig = "full", pose = "sit", dress = "vip" })
		f:SetAttribute("Row", row)
		f:SetAttribute("Side", side)
		f:SetAttribute("VIP", true)
	end
	m.Parent = st
	return bw
end

-- the MEDIA box: a glass-fronted desk row with monitors and laptops, press in it
local function mediaBox(st, crowd, spec, rot, xc, row, side, rng)
	local d0 = spec.rowStart + row * spec.rowGap
	local y = rowTop(spec, row)
	local zc = d0 + spec.rowGap / 2
	local n = spec.tier >= 4 and 5 or 4
	local bw = n * 2.4 + 1.0
	local m = Instance.new("Model")
	m.Name = "MediaBox"
	m:SetAttribute("Side", side)
	prop(m, "MediaDesk", V3(bw, 0.18, 1.6), rot * CF(xc, y + 2.2, d0 + 1.2), rgb(36, 36, 40), M.Metal)
	prop(m, "MediaDeskFront", V3(bw, 2.2, 0.15), rot * CF(xc, y + 1.1, d0 + 0.45), rgb(16, 16, 20), M.SmoothPlastic)
	local front = m:FindFirstChild("MediaDeskFront")
	if front then
		local sg = gui(front, FACE.Front, 14, 0, 1.4)
		frame(sg, { Size = UDim2.fromScale(1, 0.26), Position = UDim2.fromScale(0, 0.37), BackgroundColor3 = rgb(150, 16, 24) })
		label(sg, { Size = UDim2.fromScale(0.9, 0.24), Position = UDim2.fromScale(0.05, 0.38), Text = "MEDIA  -  WCB SPORTS  -  MEDIA", TextColor3 = WHITE })
	end
	prop(m, "MediaGlass", V3(bw, 1.2, 0.1), rot * CF(xc, y + 2.9, d0 + 0.45), rgb(160, 200, 230), M.Glass, { Transparency = 0.55, CastShadow = false })
	for i = 1, n do
		local x = xc + (i - (n + 1) / 2) * 2.4
		local base = rot * CF(x, y, zc + 0.9)
		prop(m, "MediaChair", V3(1.7, 0.4, 1.6), base * CF(0, 0.7, 0), rgb(30, 30, 34), M.Fabric, { CastShadow = false })
		prop(m, "MediaChairBack", V3(1.7, 1.8, 0.25), base * CF(0, 1.7, 0.75), rgb(30, 30, 34), M.Fabric, { CastShadow = false })
		-- a laptop (lid glow) at every seat, a monitor on a stand every other
		prop(m, "LaptopBase", V3(1.2, 0.06, 0.85), rot * CF(x, y + 2.32, d0 + 1.3), rgb(40, 40, 44), M.Metal, { CastShadow = false })
		local lid = prop(m, "Laptop", V3(1.2, 0.8, 0.05), rot * CF(x, y + 2.7, d0 + 0.9) * CFrame.Angles(math.rad(15), 0, 0), rgb(40, 40, 44), M.Metal, { CastShadow = false })
		local sg = gui(lid, FACE.Back, 40, 0, 1.2)
		frame(sg, { Size = UDim2.fromScale(0.92, 0.88), Position = UDim2.fromScale(0.04, 0.06), BackgroundColor3 = rgb(150, 190, 255) })
		if i % 2 == 1 then
			local mon = prop(m, "Monitor", V3(1.5, 0.95, 0.1), rot * CF(x + 1.2, y + 3.4, d0 + 0.75), rgb(20, 20, 22), M.Metal, { CastShadow = false })
			local ms = gui(mon, FACE.Back, 30, 0, 1.2)
			frame(ms, { Size = UDim2.fromScale(0.94, 0.9), Position = UDim2.fromScale(0.03, 0.05), BackgroundColor3 = rgb(40, 90, 60) })
			prop(m, "MonitorStand", V3(0.2, 0.5, 0.2), rot * CF(x + 1.2, y + 2.55, d0 + 0.8), rgb(40, 40, 44), M.Metal, { CastShadow = false })
		end
		local f = fan(crowd, base * CF(0, 0.9, 0), rng, { rig = "lite", pose = "sit", dress = "press" })
		f:SetAttribute("Row", row)
		f:SetAttribute("Side", side)
		f:SetAttribute("Press", true)
	end
	m.Parent = st
	return bw
end

-- a broadcast camera on a railed riser at the stands (a kit camera when Venues passes one)
local function cameraPlatform(st, spec, rot, x, row, kit, rng, idx)
	local d0 = spec.rowStart + row * spec.rowGap
	local y = rowTop(spec, row)
	local zc = d0 + spec.rowGap / 2
	local m = Instance.new("Model")
	m.Name = "CamPlatform"
	local ph = 1.6
	prop(m, "CamRiser", V3(4.2, ph, 4.2), rot * CF(x, y + ph / 2, zc), rgb(30, 30, 34), M.DiamondPlate)
	for _, sx in ipairs({ -1, 1 }) do
		prop(m, "CamRailPost", V3(0.12, 2.6, 0.12), rot * CF(x + sx * 2.0, y + ph + 1.3, zc - 2.0), rgb(150, 150, 156), M.Metal, { CastShadow = false })
		prop(m, "CamRailPost", V3(0.12, 2.6, 0.12), rot * CF(x + sx * 2.0, y + ph + 1.3, zc + 2.0), rgb(150, 150, 156), M.Metal, { CastShadow = false })
		prop(m, "CamRail", V3(0.12, 0.12, 4.1), rot * CF(x + sx * 2.0, y + ph + 2.55, zc), rgb(150, 150, 156), M.Metal, { CastShadow = false })
	end
	prop(m, "CamRail", V3(4.1, 0.12, 0.12), rot * CF(x, y + ph + 2.55, zc + 2.0), rgb(150, 150, 156), M.Metal, { CastShadow = false })
	prop(m, "CamRail", V3(4.1, 0.12, 0.12), rot * CF(x, y + ph + 1.3, zc - 2.0), rgb(150, 150, 156), M.Metal, { CastShadow = false })
	local sgp = m:FindFirstChild("CamRiser")
	if sgp then
		local sg = gui(sgp, FACE.Front, 12, 1, 1)
		label(sg, { Size = UDim2.fromScale(0.9, 0.6), Position = UDim2.fromScale(0.05, 0.2), Text = "CAM " .. tostring(idx), TextColor3 = WHITE, Face = "signSub" })
	end
	local pos = (rot * CF(x, y + ph, zc)).Position
	if kit and kit.tvCamera then
		kit.tvCamera(m, pos, V3(0, spec.ringH + 3, 0), rng, 10 + idx)
	else
		prop(m, "TVCamera", V3(1.4, 1.4, 3), CFrame.lookAt(pos + V3(0, 5.6, 0), V3(0, spec.ringH + 3, 0)), rgb(25, 25, 28), M.Metal)
	end
	m.Parent = st
end

-- the photographers' pit at the apron: kneeling figures with cameras, flashes come from VenueFX
local function photographers(st, crowd, spec, rng, kit)
	local half = spec.half
	local E = half + 3.2
	local n = spec.tier >= 3 and 4 or (spec.tier == 2 and 3 or 1)
	for _, z in ipairs({ -1, 1 }) do
		for i = 1, n do
			-- beside the walkway rail (x < -4.5), short of the stool corner (x > -(half + 2.8))
			local x = -(5.0 + (i - 1) * 2.5)
			if x > -(half + 2.6) then
				local pos = V3(x, 0, z * (E + 1.4))
				local cf = CFrame.lookAt(pos, V3(x, 0, 0))
				-- a kneeling photographer: a low full rig (seated pose on the floor), a camera at the eye
				local f = fan(crowd, cf * CF(0, 0.5, 0), rng, { rig = "full", pose = "sit", dress = "press" })
				f:SetAttribute("Row", -1)
				f:SetAttribute("Side", z < 0 and 0 or 2)
				f:SetAttribute("Press", true)
				f:SetAttribute("Photographer", true)
				local head = f:FindFirstChild("Head")
				if head then
					local cam = fanPart(f, "Camera", V3(0.5, 0.35, 0.45), head.CFrame * CF(0.1, -0.1, -0.55), rgb(20, 20, 22), M.Metal)
					local lens = fanPart(f, "CameraLens", V3(0.7, 0.3, 0.3), cam.CFrame * CF(0, 0, -0.5) * CFrame.Angles(0, math.pi / 2, 0), rgb(15, 15, 18), M.Metal)
					lens.Shape = Enum.PartType.Cylinder
				end
			end
		end
		-- the PRESS tape along the pit
		if n > 1 then
			local len = (n - 1) * 2.5 + 3
			local tape = prop(st, "PressTape", V3(len, 0.25, 0.04), CF(-(5.0 + (n - 1) * 1.25), 2.0, z * (E + 3.0)), rgb(240, 200, 40), M.Fabric, { CastShadow = false })
			local sg = gui(tape, z < 0 and FACE.Back or FACE.Front, 24, 1, 1)
			label(sg, { Size = UDim2.fromScale(1, 1), Text = "PRESS  -  PRESS  -  PRESS", TextColor3 = BLACK, Face = "signSub" })
			for _, sx in ipairs({ -1, 1 }) do
				prop(st, "PressTapePost", V3(0.12, 2.1, 0.12), CF(-(5.0 + (n - 1) * 1.25) + sx * len / 2, 1.05, z * (E + 3.0)), rgb(60, 60, 66), M.Metal, { CastShadow = false })
			end
		end
	end
	local _ = kit
end

-- sponsor boards on a fascia: the venue's ads, alternating colours
local function sponsorBoard(st, spec, rot, b, row, k)
	local d0 = spec.rowStart + row * spec.rowGap
	local y = rowTop(spec, row)
	local w = b[2] - b[1]
	local xc = (b[1] + b[2]) / 2
	local ads = spec.ads or { "WCB SPORTS" }
	local text = ads[(k - 1) % #ads + 1]
	local dark = k % 2 == 0
	local board = prop(st, "SponsorBoard", V3(w, 0.9, 0.12), rot * CF(xc, y - 0.7, d0 - 0.1), dark and BLACK or rgb(150, 16, 24), M.SmoothPlastic, { CastShadow = false })
	local sg = gui(board, FACE.Front, 12, spec.tier >= 3 and 0.2 or 1, 1.2)
	label(sg, { Size = UDim2.fromScale(0.96, 0.8), Position = UDim2.fromScale(0.02, 0.1), Text = text .. "   -   " .. text .. "   -   " .. text, TextColor3 = dark and GOLD or WHITE })
end

------------------------------------------------------------------------
-- the upper bowl (Arena / Stadium): one slab per side, rows of RichText fans drawn by CrowdFX
------------------------------------------------------------------------
local function buildBowl(arena, spec, bowl)
	local S = spec.size
	local R0 = spec.rowStart + spec.rows * spec.rowGap + 1
	local y0 = (spec.rows - 1) * spec.rowRise + 3.5
	local R1 = S / 2 - 3
	local y1 = math.min(spec.height - 10, y0 + (R1 - R0) * 0.72)
	spec.bowlTop = y1
	local dR, dy = R1 - R0, y1 - y0
	local slopeLen = math.sqrt(dR * dR + dy * dy)
	local width = R0 + R1
	local nRows = math.clamp(math.floor(slopeLen / 2.6), 10, 26)
	for side = 0, 3 do
		local a = side * math.pi / 2
		local o = V3(math.sin(a), 0, math.cos(a))
		local mid = o * ((R0 + R1) / 2) + V3(0, (y0 + y1) / 2, 0)
		local s = (o * dR + V3(0, dy, 0)).Unit
		local n = (-o * dy + V3(0, dR, 0)).Unit
		local zAxis = -n
		local xAxis = s:Cross(zAxis)
		local slab = prop(bowl, "BowlTier", V3(width, slopeLen, 1.2), CFrame.fromMatrix(mid, xAxis, s, zAxis), spec.seats or rgb(30, 30, 36), M.Fabric, { CastShadow = false })
		local sg = gui(slab, FACE.Front, 4, 1, 1)
		sg.Name = "CrowdPrint"
		frame(sg, { Name = "Seats", Size = UDim2.fromScale(1, 1), BackgroundColor3 = (spec.seats or rgb(30, 30, 36)):Lerp(Color3.new(), 0.35) })
		slab:SetAttribute("CrowdRows", nRows)
		slab:SetAttribute("Fill", 1)
		slab:SetAttribute("Side", side)
		slab:SetAttribute("Seed", 100 + side)
		for i = 1, nRows - 1, 2 do
			frame(sg, { Name = "SeatLine", Size = UDim2.fromScale(1, 0.18 / nRows), Position = UDim2.fromScale(0, i / nRows), BackgroundColor3 = rgb(10, 10, 12), BackgroundTransparency = 0.5 })
		end
		for _, ax in ipairs({ 0.2, 0.4, 0.6, 0.8 }) do
			frame(sg, { Name = "Aisle", Size = UDim2.fromScale(0.012, 1), Position = UDim2.fromScale(ax, 0), BackgroundColor3 = rgb(70, 70, 76) })
		end
		-- the bowl's front fascia carries a ring of LED (VenueFX drives it) over a sponsor line
		local fascia = prop(bowl, "LEDRibbon", V3(width * (R0 / ((R0 + R1) / 2)) * 0.98, 1.6, 0.3), CFrame.lookAt(o * (R0 - 0.4) + V3(0, y0 - 0.3, 0), V3(0, y0 - 0.3, 0)), BLACK, M.SmoothPlastic, { CastShadow = false })
		fascia:SetAttribute("Upper", true)
	end
	local _ = arena
end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
-- kit (optional): { tvCamera = fn(parent, pos, target, rng, idx) } from Venues
function Crowd.Build(arena, spec, kit)
	if (spec.rows or 0) <= 0 then
		return nil
	end
	local rng = Random.new(spec.size * 7 + spec.tier * 131)
	local crowd = Instance.new("Folder")
	crowd.Name = "Crowd"
	crowd.Parent = arena
	local stands = Instance.new("Folder")
	stands.Name = "Stands"
	stands.Parent = arena
	local bowl = Instance.new("Folder")
	bowl.Name = "Bowl"
	bowl.Parent = arena
	local physRows = Crowd.PHYSICAL_ROWS[spec.tier] or 2
	local vipRow = spec.tier >= 2 and math.min(spec.rows - 1, 2) or nil
	local stepColor = spec.chairs and rgb(60, 60, 70) or rgb(35, 35, 42)
	local seed = 0
	local camIdx = 0
	for side = 0, 3 do
		local rot = CFrame.Angles(0, side * math.pi / 2, 0)
		for row = 0, spec.rows - 1 do
			local d0 = spec.rowStart + row * spec.rowGap
			local d1 = d0 + spec.rowGap
			local h = row * spec.rowRise
			local y = rowTop(spec, row)
			local blocks = blocksOf(side, d0, d1)
			for bi, b in ipairs(blocks) do
				local w = b[2] - b[1]
				local xc = (b[1] + b[2]) / 2
				-- the stand: a block whose top is the tread (a riser face toward the ring)
				if h > 0 then
					deco(stands, "Stand", V3(w, h + 0.5, spec.rowGap), rot * CF(xc, (h + 0.5) / 2, d0 + spec.rowGap / 2), stepColor, M.Concrete)
				elseif spec.tier >= 2 then
					-- the ringside row stands on a low riser so its chairs read over the barrier
					deco(stands, "Stand", V3(w, 0.5, spec.rowGap), rot * CF(xc, 0.25, d0 + spec.rowGap / 2), stepColor, M.Concrete)
				end
				-- stair lights on the block's aisle edges
				local aisleX = (side == 0 or side == 2) and (bi == 1 and b[1] + 0.35 or b[2] - 0.35) or (bi == 1 and b[1] + 0.35 or b[2] - 0.35)
				stairLights(stands, spec, rot, aisleX, row)
				-- seats
				local seatsX = {}
				local n = math.floor(w / Crowd.SEAT)
				for i = 1, n do
					table.insert(seatsX, b[1] + (i - 0.5) * (w / n))
				end
				local reserved = {} -- x ranges of this block's row taken by a box / platform
				if row == vipRow and (side == 1 or side == 3) then
					local nBoxes = spec.tier >= 4 and 2 or 1
					for k = 1, nBoxes do
						local bx = nBoxes == 1 and xc or (b[1] + w * (k - 0.5) / nBoxes)
						local bw = vipBox(stands, crowd, spec, rot, bx, row, side, rng, (side * 10 + bi * 2 + k))
						table.insert(reserved, { bx - bw / 2, bx + bw / 2 })
					end
				end
				if spec.tier >= 2 and row == vipRow and (side == 0 or side == 2) and bi == 1 and spec.tier >= 3 then
					local bw = mediaBox(stands, crowd, spec, rot, b[1] + 8, row, side, rng)
					table.insert(reserved, { b[1] + 8 - bw / 2, b[1] + 8 + bw / 2 })
				end
				if spec.tier >= 2 and row == vipRow and (side == 1 or side == 3) and bi == 2 and (spec.tier >= 3 or side == 1) then
					camIdx += 1
					cameraPlatform(stands, spec, rot, b[1] + 2.6, row, kit, rng, camIdx)
					table.insert(reserved, { b[1], b[1] + 5 })
				end
				if spec.tier >= 2 and row == vipRow and (side == 0 or side == 2) and bi == 2 and spec.tier >= 3 then
					camIdx += 1
					cameraPlatform(stands, spec, rot, b[2] - 2.6, row, kit, rng, camIdx)
					table.insert(reserved, { b[2] - 5, b[2] })
				end
				local free = {}
				for _, x in ipairs(seatsX) do
					local taken = false
					for _, r in ipairs(reserved) do
						if x > r[1] - 0.8 and x < r[2] + 0.8 then
							taken = true
						end
					end
					if not taken then
						table.insert(free, x)
					end
				end
				if row < physRows then
					-- real rigs
					local kind = row == 0 and (spec.chairs and "folding" or "ringside") or (spec.chairs and "folding" or "seats")
					seating(stands, spec, rot, b, row, kind, free)
					local seatTop = y + (kind == "ringside" and 0.95 or (kind == "folding" and 1.6 or 0.95))
					for _, x in ipairs(free) do
						local base = rot * CF(x, seatTop, d0 + spec.rowGap / 2 + 0.3)
						local f = fan(crowd, base, rng, { rig = row == 0 and "full" or "lite", pose = "sit", dress = row == 0 and spec.tier >= 2 and "ringside" or nil })
						f:SetAttribute("Row", row)
						f:SetAttribute("Side", side)
						f:SetAttribute("Seat", x)
					end
				else
					-- a printed row at the seats (the slab is the row; its fans are drawn client-side)
					if #free >= 2 then
						seed += 1
						if #reserved == 0 then
							printRow(bowl, spec, rot, b, row, side, seed, false)
							seating(stands, spec, rot, b, row, spec.chairs and "folding" or "seats", spec.chairs and free or {})
						else
							-- around the boxes: a print slab per free span
							local spans = {}
							local x0 = b[1]
							table.sort(reserved, function(p, q)
								return p[1] < q[1]
							end)
							for _, r in ipairs(reserved) do
								if r[1] - x0 >= Crowd.SEAT * 2 then
									table.insert(spans, { x0, r[1] })
								end
								x0 = math.max(x0, r[2])
							end
							if b[2] - x0 >= Crowd.SEAT * 2 then
								table.insert(spans, { x0, b[2] })
							end
							for _, sp in ipairs(spans) do
								seed += 1
								printRow(bowl, spec, rot, sp, row, side, seed, false)
								seating(stands, spec, rot, sp, row, "seats", {})
							end
						end
					end
					if row == physRows and spec.tier >= 2 then
						sponsorBoard(stands, spec, rot, b, row, side * 2 + bi)
					end
				end
			end
		end
		-- the standing-room rail at the top of the stands (packed houses only: Crowd.Apply / CrowdFX)
		if spec.tier >= 2 then
			local row = spec.rows
			local d0 = spec.rowStart + row * spec.rowGap
			local y = rowTop(spec, row - 1) + (spec.rowRise > 0 and spec.rowRise or 0)
			local blocks = blocksOf(side, d0, d0 + 2.5)
			for bi, b in ipairs(blocks) do
				local w = b[2] - b[1]
				local xc = (b[1] + b[2]) / 2
				deco(stands, "StandTop", V3(w, y + 0.5, 3.0), rot * CF(xc, (y + 0.5) / 2, d0 + 1.5), stepColor, M.Concrete)
				prop(stands, "StandRail", V3(w, 0.12, 0.12), rot * CF(xc, y + 3.3, d0 + 0.2), rgb(150, 150, 156), M.Metal, { CastShadow = false })
				seed += 1
				local slab = printRow(bowl, spec, rot, { b[1], b[2] }, row, side, seed, true)
				slab:SetAttribute("Standing", true)
				local _ = bi
			end
		end
		-- the aisle standers (packed houses): on the mid aisle steps of the walkway-free sides
		if spec.tier >= 2 and (side == 1 or side == 3) then
			for k = 1, math.min(3, spec.rows - physRows) do
				local row = physRows + k - 1
				local d0 = spec.rowStart + row * spec.rowGap
				local y = rowTop(spec, row)
				local base = rot * CF((k % 2 == 0 and 0.7 or -0.7), y, d0 + spec.rowGap * 0.5)
				local f = fan(crowd, base, rng, { rig = "full", pose = "stand" })
				f:SetAttribute("Row", row)
				f:SetAttribute("Side", side)
				f:SetAttribute("Standing", true)
			end
		end
	end
	-- the hall: standers along the back wall by the door, a bleacher print at the back of each side
	if spec.tier == 1 then
		local S = spec.size
		for k = 1, 6 do
			local x = -S / 2 + 10 + k * 5
			local f = fan(crowd, CFrame.lookAt(V3(x, 0, S / 2 - 6), V3(x, 0, 0)), rng, { rig = "full", pose = "stand" })
			f:SetAttribute("Row", spec.rows)
			f:SetAttribute("Side", 0)
			f:SetAttribute("Standing", true)
		end
	end
	if spec.bowl then
		buildBowl(arena, spec, bowl)
	end
	photographers(stands, crowd, spec, rng, kit)
	-- the fascia LED ribbon at the back of the physical rows (big shows)
	if spec.tier >= 3 then
		for side = 0, 3 do
			local rot = CFrame.Angles(0, side * math.pi / 2, 0)
			local row = physRows
			local d0 = spec.rowStart + row * spec.rowGap
			local y = rowTop(spec, row)
			for _, b in ipairs(blocksOf(side, d0, d0 + spec.rowGap)) do
				local w = b[2] - b[1]
				local xc = (b[1] + b[2]) / 2
				local led = prop(stands, "LEDRibbon", V3(w - 0.4, 0.5, 0.14), rot * CF(xc, y - 0.1, d0 - 0.2), BLACK, M.SmoothPlastic, { CastShadow = false })
				led:SetAttribute("Upper", false)
			end
		end
	end
	return crowd
end

------------------------------------------------------------------------
-- Apply: the night's house
------------------------------------------------------------------------
-- how much of a row fills at a given share of the house: the best seats sell first (the front rows fill before the
-- back ones; a 0.5 house seats 0.7 of row 0 and 0.3 of the back row). The standing room only opens when it is packed
function Crowd.RowFill(share, rowFrac, standing)
	share = math.clamp(tonumber(share) or 1, 0, 1)
	if standing then
		return math.clamp((share - 0.88) / 0.12, 0, 1)
	end
	if share >= 1 then
		return 1
	end
	return math.clamp(share ^ (0.5 + math.clamp(rowFrac or 0, 0, 1) * 1.3), 0, 1)
end

local SIGN_TEXTS = { "GO %s!", "%s #1", "%s TIME", "WE LOVE %s", "%s!!!", "TEAM %s", "%s KO" }
local SIGN_COLORS = { { 250, 250, 245 }, { 255, 220, 60 }, { 250, 250, 245 }, { 240, 110, 110 } }

local function fanSign(f, text, k)
	local s = prop(f, "FanSign", V3(2.4, 1.4, 0.08), f.CFrame * CF(0, 2.2, -0.35), c3(SIGN_COLORS[(k - 1) % #SIGN_COLORS + 1]), M.SmoothPlastic, { CastShadow = false, CanCollide = false, CanQuery = false, CanTouch = false })
	for _, face in ipairs({ FACE.Front, FACE.Back }) do
		local sg = gui(s, face, 30, 1, 1)
		label(sg, { Size = UDim2.fromScale(0.92, 0.8), Position = UDim2.fromScale(0.04, 0.1), Text = text, TextColor3 = rgb(190, 20, 26), Face = "marker" })
	end
	return s
end

function Crowd.Apply(arena, spec, share, supporters, nick, seed)
	local crowd = arena:FindFirstChild("Crowd")
	if not crowd then
		return
	end
	local rng = Random.new(seed or 1)
	local keep = math.clamp(tonumber(share) or 1, 0, 1)
	local rows = math.max(1, (spec.rows or 1) - 1)
	local fans = {}
	for _, f in ipairs(crowd:GetChildren()) do
		if f.Name == "Fan" and f:IsA("BasePart") then
			local row = tonumber(f:GetAttribute("Row")) or 0
			local p
			if f:GetAttribute("Press") or f:GetAttribute("Photographer") then
				p = 1
			elseif f:GetAttribute("VIP") then
				p = keep >= 0.9 and 1 or 0.55 + keep * 0.4
			elseif f:GetAttribute("Standing") then
				p = Crowd.RowFill(keep, 0, true)
			else
				p = Crowd.RowFill(keep, row / rows, false)
			end
			if rng:NextNumber() < p then
				table.insert(fans, f)
			else
				f:Destroy()
			end
		end
	end
	arena:SetAttribute("CrowdShare", math.floor(keep * 100) / 100)
	local sup = math.clamp(tonumber(supporters) or 0, 0, 1)
	-- who they are for: the player's supporters bunch up on the red side (z < 0, the red tunnel's side); among the
	-- rest a few are the opponent's (they boo when he is hurt) and most cheer whoever lands
	local reds = { rgb(200, 25, 30), rgb(170, 20, 26), rgb(230, 50, 50), rgb(240, 240, 240) }
	local supporterList = {}
	for _, f in ipairs(fans) do
		if f:GetAttribute("Press") or f:GetAttribute("Photographer") then
			f:SetAttribute("Fav", 0)
		else
			local z = f.Position.Z
			local p = sup * (z < 0 and 0.85 or 0.25)
			if rng:NextNumber() < p then
				f.Color = reds[rng:NextInteger(1, #reds)]
				for _, arm in ipairs(f:GetChildren()) do
					if (arm.Name == "ArmL" or arm.Name == "ArmR") and f:GetAttribute("Style") ~= "tee" then
						arm.Color = f.Color
					end
				end
				local pr = f:FindFirstChild("Print")
				if pr then
					pr:Destroy()
				end
				f:SetAttribute("Supporter", true)
				f:SetAttribute("Fav", 1)
				table.insert(supporterList, f)
			else
				f:SetAttribute("Fav", rng:NextNumber() < 0.22 and -1 or 0)
			end
		end
	end
	if #supporterList == 0 then
		return
	end
	-- signs in the camera rows: the front rows first
	table.sort(supporterList, function(a, b)
		return (tonumber(a:GetAttribute("Row")) or 0) < (tonumber(b:GetAttribute("Row")) or 0)
	end)
	local who = (type(nick) == "string" and nick ~= "") and string.upper(nick) or "RED CORNER"
	local signs = math.min(#supporterList, math.floor(2 + sup * 12))
	for i = 1, signs do
		local idx = math.min(#supporterList, 1 + rng:NextInteger(0, math.min(#supporterList - 1, 6)))
		local f = table.remove(supporterList, idx)
		fanSign(f, string.format(SIGN_TEXTS[(i - 1) % #SIGN_TEXTS + 1], who), i)
		f:SetAttribute("Sign", true)
	end
	-- a banner on the barrier (or the first row's riser) on the red side when the fans came in numbers
	if sup >= 0.3 and spec.rows > 0 then
		local rb = spec.rowStart - 0.6
		local len = math.min(18, rb - 8)
		for k, sx in ipairs({ -1, 1 }) do
			if k == 1 or sup >= 0.6 then
				local x = sx * (6 + len / 2)
				local pos = V3(x, 2.2 + (spec.tier >= 3 and 0.6 or 0), -(rb + 0.45))
				local b = prop(arena, "FanBanner", V3(len, 2.0, 0.08), CFrame.lookAt(pos, V3(x, pos.Y, 0)), k == 1 and rgb(250, 250, 245) or rgb(200, 25, 30), M.Fabric, { CastShadow = false })
				local sg = gui(b, FACE.Front, 16, 1, 1)
				label(sg, { Size = UDim2.fromScale(0.94, 0.8), Position = UDim2.fromScale(0.03, 0.1), Text = (k == 1 and "%s ARMY" or "GO %s GO"):format(who), TextColor3 = k == 1 and rgb(190, 20, 26) or WHITE, Face = "marker" })
			end
		end
	end
end

------------------------------------------------------------------------
-- React: the server's hook for crowd reactions (FightEngine may call it; the fighting client's VenueFX already
-- forwards its own phases to CrowdFX, so this reaches every other client watching the venue)
------------------------------------------------------------------------
-- event: "bigpunch" | "knockdown" | "count" | "getup" | "roundstart" | "roundend" | "bell" | "ko" | "winner" |
--        "entrance" | "boo" | "cheer";  data = { who = "you" | "opp", n = count, result = "win" | "loss" | "draw" }
local seq = 0
function Crowd.React(arena, event, data)
	if typeof(arena) ~= "Instance" or type(event) ~= "string" then
		return
	end
	data = type(data) == "table" and data or {}
	seq += 1
	arena:SetAttribute("CrowdReact", string.format("%s|%s|%s|%d", event, tostring(data.who or ""), tostring(data.result or data.n or ""), seq))
end

-- counts for tests and the report: fans by rig, print slabs, parts in Crowd + Stands + Bowl
function Crowd.Counts(arena)
	local out = { full = 0, lite = 0, fans = 0, vip = 0, standing = 0, press = 0, signs = 0, prints = 0, bowlTiers = 0, parts = 0, instances = 0 }
	for _, fn in ipairs({ "Crowd", "Stands", "Bowl" }) do
		local f = arena:FindFirstChild(fn)
		if f then
			for _, d in ipairs(f:GetDescendants()) do
				out.instances += 1
				if d:IsA("BasePart") then
					out.parts += 1
					if d.Name == "Fan" then
						out.fans += 1
						out[d:GetAttribute("Rig") == "full" and "full" or "lite"] += 1
						if d:GetAttribute("VIP") then
							out.vip += 1
						end
						if d:GetAttribute("Standing") then
							out.standing += 1
						end
						if d:GetAttribute("Press") then
							out.press += 1
						end
					elseif d.Name == "FanSign" then
						out.signs += 1
					elseif d.Name == "RowPrint" then
						out.prints += 1
					elseif d.Name == "BowlTier" then
						out.bowlTiers += 1
					end
				end
			end
		end
	end
	return out
end

return Crowd
