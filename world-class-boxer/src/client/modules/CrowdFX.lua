-- CrowdFX: the crowd, alive, on the fighting client (VenueFX owns the session and calls in; nothing replicates).
-- The server's Crowd.lua builds the fans and the stands (sold out, then emptied to the night's house); this module
--   * animates the real rigs (Crowd/Fan parts: ringside, VIP boxes, press, standers): sitting fans bob and sway with
--     the excitement, clap, hold phones up, throw their arms up, stand, jump, boo (arms crossed, head shaking) -
--     per fan a temperament (Energy), a style (phone / sign / clapper / jumper) and a favourite (Fav: the player's
--     supporters, the opponent's fans, the neutrals who cheer whoever lands). Parts are bulk-moved, time-sliced
--     (half the rigs a tick, a part budget per Graphics level, the view cone first) - no per-fan scripts.
--   * draws the printed rows (Bowl/RowPrint slabs): every seat a flat fan (a drawn face on a round head, a hat, a
--     body in its own colours, two arms) on the slab's ring-facing SurfaceGui, the empty seats showing their backs,
--     and animates them a few slabs a tick (bob, arms up, standing).
--   * draws the upper bowl (Bowl/BowlTier slabs): rows of RichText fans (heads over bodies) that lift in the waves.
--   * runs the reaction waves: CrowdFX.React(event, data) from VenueFX's phases and hits (and from the arena's
--     CrowdReact attribute, Crowd.React on the server) spreads from the ring outward at ~70 studs a second: a big
--     punch, a knockdown, the count, the get-up, the bell, the round's end, the KO and the winner's announcement.
--     Each fan answers by his favourite: cheer (stand, arms up, jump) or boo.
--   CrowdFX.Start(arena, { center, share, venue })  CrowdFX.Update(dt, now, excite, supportBoost)
--   CrowdFX.React(event, data)  CrowdFX.Fans()  CrowdFX.Guis()  CrowdFX.Stop()
--   CrowdFX.Print(arena, share, folder) (the printed rows alone: the previews use it offline)
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
local WorldLOD
do
	local m = script.Parent:FindFirstChild("WorldLOD")
	local ok, mod = false, nil
	if m then
		ok, mod = pcall(require, m)
	end
	WorldLOD = (ok and type(mod) == "table") and mod or nil
end
local function lodPick(low, medium, high)
	return WorldLOD and WorldLOD.Pick(low, medium, high) or high
end

local CrowdFX = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local WHITE = rgb(240, 240, 240)
local BLACK = rgb(14, 14, 18)

local CROWD_BUDGET = 420 -- full-rate parts per tick (High; Medium 280, Low 160)
local CROWD_SLOW_BUDGET = 300
local CROWD_EDGE = 3
local WAVE_SPEED = 70 -- studs / s a reaction travels outward from the ring
local PRINT_SLABS_PER_TICK = { 2, 4, 7 } -- printed rows redrawn a tick by level
local BOWL_ROWS_PER_TICK = { 6, 12, 24 }

local S = nil

------------------------------------------------------------------------
-- looks for the printed fans (the same palettes as Crowd.lua's rigs, so the rows read as one crowd)
------------------------------------------------------------------------
local SHIRTS = {
	{ 200, 30, 30 }, { 30, 60, 200 }, { 240, 240, 240 }, { 20, 20, 24 }, { 240, 190, 40 }, { 40, 150, 70 }, { 130, 40, 170 }, { 240, 120, 30 },
	{ 0, 170, 190 }, { 240, 120, 170 }, { 60, 60, 66 }, { 30, 36, 60 }, { 110, 30, 40 }, { 90, 90, 96 }, { 70, 50, 36 }, { 60, 70, 50 },
	{ 200, 200, 205 }, { 230, 90, 60 }, { 90, 160, 220 }, { 240, 220, 120 }, { 130, 200, 150 }, { 170, 120, 70 }, { 26, 30, 44 }, { 50, 50, 56 },
}
local HATS = { { 200, 30, 30 }, { 30, 60, 200 }, { 20, 20, 24 }, { 240, 240, 240 }, { 60, 60, 66 }, { 40, 110, 60 }, { 240, 190, 40 }, { 120, 80, 50 } }
local FACES = Looks.NPC_FACES or { { "wcb_neutral", 1 } }
local faceIds = nil
local function faceList()
	if faceIds then
		return faceIds
	end
	faceIds = {}
	if BodyTiers and BodyTiers.Face then
		local boost = { wcb_grin = 4, wcb_toothy = 4, wcb_smirk = 2, wcb_cool = 2, wcb_wink = 2, wcb_confident = 1.5 }
		for _, f in ipairs(FACES) do
			local ok, e = pcall(BodyTiers.Face, f[1])
			if ok and type(e) == "table" and e.id then
				table.insert(faceIds, { id = e.id, w = f[2] * (boost[f[1]] or 1) })
			end
		end
	end
	return faceIds
end
local function pickFace(rng)
	local list = faceList()
	if #list == 0 then
		return nil
	end
	local total = 0
	for _, f in ipairs(list) do
		total += f.w
	end
	local r = rng:NextNumber() * total
	for _, f in ipairs(list) do
		if r < f.w then
			return f.id
		end
		r -= f.w
	end
	return list[1].id
end

local function c3(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- the row's fill at the house share (Crowd.RowFill on the server; the same curve here for the printed rows)
local function rowFill(share, rowFrac, standing)
	share = math.clamp(tonumber(share) or 1, 0, 1)
	if standing then
		return math.clamp((share - 0.88) / 0.12, 0, 1)
	end
	if share >= 1 then
		return 1
	end
	return math.clamp(share ^ (0.5 + math.clamp(rowFrac or 0, 0, 1) * 1.3), 0, 1)
end
CrowdFX.RowFill = rowFill

------------------------------------------------------------------------
-- reactions
------------------------------------------------------------------------
-- event -> { attitude for a fan of the player (fav 1), of the opponent (fav -1), neutral; intensity; hold; decay }
-- who = the boxer the event is about (bigpunch: who landed it; knockdown / count / getup: who is down; winner: the
-- result from the player's side)
local EVENTS = {
	bigpunch = { k = 0.55, hold = 0.6, decay = 1.2, loud = 0.5 },
	knockdown = { k = 1, hold = 2.2, decay = 2.5, loud = 1 },
	count = { k = 0.7, hold = 0.5, decay = 0.8, loud = 0.5 },
	getup = { k = 0.8, hold = 1.2, decay = 1.6, loud = 0.6, all = "cheer" },
	roundstart = { k = 0.6, hold = 1.2, decay = 1.5, loud = 0.4, all = "cheer" },
	roundend = { k = 0.75, hold = 2.5, decay = 2.5, loud = 0.6, all = "cheer" },
	bell = { k = 0.5, hold = 0.8, decay = 1.0, loud = 0.4, all = "cheer" },
	entrance = { k = 0.85, hold = 5, decay = 3, loud = 0.7, all = "cheer" },
	ko = { k = 1, hold = 4, decay = 4, loud = 1 },
	winner = { k = 1, hold = 6, decay = 5, loud = 1 },
	cheer = { k = 0.8, hold = 1.5, decay = 2, loud = 0.6, all = "cheer" },
	boo = { k = 0.8, hold = 2, decay = 2, loud = 0.6, all = "boo" },
}

-- the attitude of a fan with favourite fav (1 / -1 / 0) to a reaction about `who` ("you" / "opp")
local function attitude(ev, fav, who, result)
	if ev.all then
		return ev.all
	end
	-- who benefits: the puncher, the one still standing, the winner
	local good
	if result then
		good = result == "win" and "you" or (result == "loss" and "opp" or nil)
	elseif ev == EVENTS.knockdown or ev == EVENTS.count then
		good = who == "you" and "opp" or "you"
	else
		good = who
	end
	if not good or fav == 0 then
		return ev == EVENTS.knockdown and "ooh" or "cheer"
	end
	if (fav == 1 and good == "you") or (fav == -1 and good == "opp") then
		return "cheer"
	end
	return "boo"
end

-- a fan's reaction value now: 0 before the wave reaches him, 1 at its peak, back to 0 after hold + decay
local function reactValue(r, ringD, now)
	if not r then
		return 0
	end
	local d = now - r.t0 - ringD / WAVE_SPEED
	if d < 0 then
		return 0
	end
	local rise = math.min(1, d / 0.25)
	local fall = d > r.hold and math.clamp(1 - (d - r.hold) / r.decay, 0, 1) or 1
	return rise * fall * r.k
end

------------------------------------------------------------------------
-- rigs
------------------------------------------------------------------------
local function setupRigs()
	S.fans = {}
	S.bulkParts, S.bulkCFs = {}, {}
	local crowd = S.arena:FindFirstChild("Crowd")
	if not crowd then
		return
	end
	for _, fan in ipairs(crowd:GetChildren()) do
		if fan:IsA("BasePart") and fan.Name == "Fan" then
			local e = {
				fan = fan, base = fan.CFrame, pos = fan.Position, kids = {}, phase = math.random() * 6.28, speed = 4.5 + math.random() * 4,
				sup = fan:GetAttribute("Supporter") == true, fav = tonumber(fan:GetAttribute("Fav")) or 0, energy = tonumber(fan:GetAttribute("Energy")) or 1,
				vip = fan:GetAttribute("VIP") == true, press = fan:GetAttribute("Press") == true or fan:GetAttribute("Photographer") == true,
				standing = fan:GetAttribute("Pose") == "stand", w = fan.Size.X, h = fan.Size.Y, live = false, att = "cheer",
			}
			for _, c in ipairs(fan:GetChildren()) do
				if c:IsA("BasePart") then
					local k = { p = c, rel = fan.CFrame:ToObjectSpace(c.CFrame), name = c.Name, side = tonumber(c:GetAttribute("Side")) }
					if c.Name == "ArmL" or c.Name == "ArmR" then
						k.kind = "arm"
						e.pitch0 = e.pitch0 or (e.standing and 0.12 or 0.5)
					elseif c.Name == "Lap" then
						k.kind = "lap"
						e.lap = k
					elseif c.Name == "Head" then
						k.kind = "head"
						e.head = k
					elseif c.Name == "Hat" then
						k.kind = "hat"
					elseif c.Name == "Phone" then
						k.kind = "phone"
						e.phone = k
					elseif c.Name == "FanSign" then
						k.kind = "sign"
						e.sign = k
					elseif c.Name == "Camera" or c.Name == "CameraLens" then
						k.kind = "camera"
					end
					table.insert(e.kids, k)
				end
			end
			e.n = 1 + #e.kids
			-- the style he cheers in
			local r = math.random()
			e.style = e.sign and "sign" or (e.phone and "phone" or (e.press and "press" or (e.energy >= 1.3 and "jumper" or (r < 0.5 and "clapper" or "waver"))))
			local flat = V3(fan.Position.X - S.center.X, 0, fan.Position.Z - S.center.Z)
			e.ringD = flat.Magnitude
			table.insert(S.fans, e)
		end
	end
	table.sort(S.fans, function(a, b)
		return a.ringD < b.ringD
	end)
	S.fanIdx = 0
end

local function homeFan(e, parts, cfs, k)
	k += 1
	parts[k], cfs[k] = e.fan, e.base
	for _, c in ipairs(e.kids) do
		k += 1
		parts[k], cfs[k] = c.p, e.base * c.rel
	end
	return k
end

local function armCF(torsoCF, side, w, h, pitch, roll)
	return torsoCF * CF(side * (w / 2 + 0.22), h / 2 - 0.25, 0) * ANG(pitch, 0, roll * side) * CF(0, -0.8, 0)
end

-- one rig's pose now: fills parts / cfs from index k, returns the new k
local function poseFan(e, now, ex, boost, parts, cfs, k)
	local r = reactValue(S.react, e.ringD, now)
	local att = r > 0 and e.att or "cheer"
	local energy = e.energy
	local sup = e.sup and boost or 0
	-- how much he is up out of his seat, and bobbing
	local standK, hop, bob, raise, sway = 0, 0, 0, 0, 0
	if e.press then
		bob = math.sin(now * 1.3 + e.phase) * 0.03
		raise = 0
	elseif att == "boo" then
		standK = r * 0.5 * (energy >= 1 and 1 or 0.3)
		bob = math.sin(now * e.speed * 0.6 + e.phase) * 0.06
		sway = math.sin(now * 5 + e.phase) * 0.12 * r
	elseif att == "ooh" then
		-- the knockdown gasp: up on the feet, hands to the head, then the cheer
		standK = math.min(1, r * 1.4) * (e.vip and 0.6 or 1)
		bob = math.sin(now * e.speed + e.phase) * 0.05
		raise = r * 0.8
	else
		standK = math.clamp(r * 1.25 + (ex - 0.82) * 4 + sup * 0.6, 0, 1) * (e.vip and 0.5 or (energy >= 1 and 1 or 0.45))
		local amp = 0.05 + ex * 0.32 * energy + r * 0.25
		bob = math.max(0, math.sin(now * e.speed + e.phase)) * amp
		if e.style == "jumper" and (r > 0.45 or ex > 0.9) then
			hop = math.abs(math.sin(now * 7 + e.phase)) * 0.55 * math.max(r, ex - 0.6)
		end
		raise = math.clamp(r * 1.3 + (ex - 0.45) * 1.6 + sup, 0, 1)
		sway = math.sin(now * 1.1 + e.phase) * 0.05 * (0.3 + ex)
	end
	if e.standing then
		standK = 0
	end
	local cf = e.base * CF(0, standK * 1.15 + bob + hop, -standK * 0.12) * ANG(0, 0, sway)
	k += 1
	parts[k], cfs[k] = e.fan, cf
	local w, h = e.w, e.h
	local armPose = {}
	for _, c in ipairs(e.kids) do
		k += 1
		parts[k] = c.p
		if c.kind == "arm" then
			local s = c.side or 1
			local pitch, roll = e.pitch0, 0.1
			if att == "boo" then
				-- arms folded, a thumbs-down shake from the lively ones
				pitch, roll = 1.1 + r * 0.2, 0.55 + r * 0.2
				if energy >= 1 and s > 0 then
					pitch = 1.6 + math.sin(now * 6 + e.phase) * 0.2 * r
				end
			elseif att == "ooh" and r > 0.3 then
				pitch, roll = 2.3 + math.sin(now * 3 + e.phase) * 0.1, 0.5
			elseif e.style == "phone" and s > 0 and (ex > 0.25 or r > 0) then
				pitch, roll = 2.35 + math.sin(now * 0.8 + e.phase) * 0.06, 0.08
			elseif e.style == "sign" and raise > 0.05 then
				pitch, roll = 2.7, 0.35 + math.sin(now * 2.2 + e.phase) * 0.1
			elseif e.style == "clapper" and raise > 0.05 and raise < 0.75 then
				local clap = math.sin(now * 13 + e.phase)
				pitch, roll = 1.25 + raise * 0.3, 0.45 + clap * 0.22
			else
				local wave = math.sin(now * e.speed * 0.5 + e.phase + (s > 0 and 0 or 1.3)) * 0.18 * raise
				pitch = e.pitch0 + (2.75 - e.pitch0) * raise + wave
				roll = 0.1 + raise * 0.28
			end
			local acf = armCF(cf, s, w, h, pitch, roll)
			cfs[k] = acf
			armPose[s] = acf
		elseif c.kind == "lap" then
			-- the lap turns into legs as he stands
			local seated = cf * c.rel
			local stood = cf * CF(0, -h / 2 - 0.68, 0.05) * ANG(math.pi / 2, 0, 0)
			cfs[k] = standK > 0.01 and seated:Lerp(stood, standK) or seated
		elseif c.kind == "phone" then
			local arm = armPose[1]
			cfs[k] = arm and (arm * CF(0, -0.95, -0.2)) or cf * c.rel
		elseif c.kind == "sign" then
			cfs[k] = cf * CF(0, h / 2 + 0.35 + raise * 1.0, -0.35 - raise * 0.15) * ANG(0, 0, math.sin(now * 2.2 + e.phase) * 0.08 * (0.3 + raise))
		elseif c.kind == "head" or c.kind == "hat" then
			local yaw = math.sin(now * 0.7 + e.phase) * 0.1
			local pitch = 0
			if att == "boo" then
				yaw = math.sin(now * 9 + e.phase) * 0.3 * r
			elseif att == "ooh" then
				pitch = 0.22 * r
			elseif e.style == "phone" then
				pitch = -0.1
			end
			cfs[k] = cf * CF(0, h / 2, 0) * ANG(pitch, yaw, 0) * CF(0, -h / 2, 0) * c.rel
		else
			cfs[k] = cf * c.rel
		end
	end
	return k
end

local function updateRigs(dt, now, ex, boost)
	local fans = S.fans
	local count = #fans
	if count == 0 then
		return
	end
	local cam = workspace.CurrentCamera
	local camCF = cam and cam.CFrame or CF(S.center)
	local camPos, look = camCF.Position, camCF.LookVector
	local vp = cam and cam.ViewportSize
	local aspect = (vp and vp.Y > 0) and vp.X / vp.Y or 16 / 9
	local tanD = math.tan(math.rad((cam and cam.FieldOfView or 70) * 0.5)) * math.sqrt(1 + aspect * aspect)
	local parts, cfs = S.bulkParts, S.bulkCFs
	local k, moved, slow = 0, 0, 0
	local budget, slowBudget = lodPick(160, 280, CROWD_BUDGET), lodPick(0, 150, CROWD_SLOW_BUDGET)
	S.fanTick = ((S.fanTick or 0) + 1) % 4
	S.fanIdx = S.fanTick % 2
	local slowTurn = S.fanTick < 2 and 0 or 1
	for i = 1 + S.fanIdx, count, 2 do
		local e = fans[i]
		local d = e.pos - camPos
		local along = d:Dot(look)
		local show, hold = false, false
		if along > -CROWD_EDGE or S.everyone then
			local reach = math.max(along, 0) * tanD + CROWD_EDGE
			if S.everyone or d:Dot(d) - along * along <= reach * reach then
				if moved + e.n <= budget or S.everyone then
					show = true
					moved += e.n
				elseif math.floor((i - 1) / 2) % 2 ~= slowTurn then
					hold = e.live
				elseif slow + e.n <= slowBudget then
					show = true
					slow += e.n
				end
			end
		end
		if show then
			e.live = true
			k = poseFan(e, now, ex, boost, parts, cfs, k)
		elseif e.live and not hold then
			e.live = false
			k = homeFan(e, parts, cfs, k)
		end
	end
	for j = k + 1, #parts do
		parts[j], cfs[j] = nil, nil
	end
	if k > 0 then
		local ok = pcall(function()
			workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end)
		if not ok then
			for j = 1, k do
				parts[j].CFrame = cfs[j]
			end
		end
	end
	local _ = dt
end

------------------------------------------------------------------------
-- printed rows
------------------------------------------------------------------------
local function mk(class, props, parent)
	local o = Instance.new(class)
	if class ~= "UICorner" then
		o.BorderSizePixel = 0
	end
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

-- draws one slab's fans; returns the slab record for the animation
local function printSlab(slab, share, seedK)
	local sg = slab:FindFirstChild("CrowdPrint")
	local cols = tonumber(slab:GetAttribute("CrowdCols"))
	if not sg or not cols then
		return nil
	end
	for _, c in ipairs(sg:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local standing = slab:GetAttribute("Standing") == true
	local fill = rowFill(share, tonumber(slab:GetAttribute("RowFrac")) or 0, standing)
	local rng = Random.new((tonumber(slab:GetAttribute("Seed")) or 1) * 7919 + (seedK or 0))
	local slabW, slabH = slab.Size.X, slab.Size.Y
	local colW = 1 / cols -- a seat in x scale
	local asp = slabH / slabW -- x scale per y scale of the same length
	local seatCol = slab.Color:Lerp(BLACK, 0.2)
	local rec = { slab = slab, sg = sg, fans = {}, standing = standing, ringD = (slab.Position - S.center).Magnitude, phase = rng:NextNumber() * 6.28 }
	-- the seat backs (one strip; the fans sit in front of it) unless standing room
	if not standing then
		mk("Frame", { Size = UDim2.fromScale(1, 0.46), Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = seatCol, ZIndex = 1 }, sg)
		local divs = {}
		for _ = 1, cols do
			table.insert(divs, "▏")
		end
		local l = mk("TextLabel", { Size = UDim2.fromScale(1, 0.46), Position = UDim2.fromScale(0, 0.5), BackgroundTransparency = 1, TextScaled = true, RichText = false, Text = table.concat(divs, "      "), TextColor3 = seatCol:Lerp(BLACK, 0.5), ZIndex = 2 }, sg)
		Typography.Apply(l, "glyph")
	end
	local bodyH = standing and 0.42 or 0.5
	local headH = standing and 0.2 or 0.3
	local headW = headH * asp * 0.98
	local bodyW = colW * 0.56
	local faces = #faceList() > 0
	for c = 0, cols - 1 do
		if rng:NextNumber() < fill then
			local female = rng:NextNumber() < 0.38
			local skin = c3(Looks.SkinTones[rng:NextInteger(1, #Looks.SkinTones)])
			local shirt = c3(SHIRTS[rng:NextInteger(1, #SHIRTS)]):Lerp(rgb(90, 90, 96), 0.18)
			local x = (c + 0.5) * colW + (rng:NextNumber() - 0.5) * colW * 0.12
			local wk = female and 0.86 or (0.9 + rng:NextNumber() * 0.25)
			local hk = 0.92 + rng:NextNumber() * 0.16
			local baseY = standing and 1 or 0.98
			local f = { x = x, bw = bodyW * wk, bh = bodyH * hk, hw = headW * (female and 0.95 or 1), hh = headH, phase = rng:NextNumber() * 6.28, speed = 4 + rng:NextNumber() * 4,
				energy = rng:NextNumber() < 0.3 and 0.6 or (rng:NextNumber() < 0.7 and 1 or 1.4), baseY = baseY, fav = rng:NextNumber() < 0.2 and -1 or 0, standing = standing, asp = asp }
			f.body = mk("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(x, baseY), Size = UDim2.fromScale(f.bw, f.bh), BackgroundColor3 = shirt, ZIndex = 4 }, sg)
			if standing then
				-- legs under a stander
				f.legs = mk("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(x, 1), Size = UDim2.fromScale(f.bw * 0.7, 0.34), BackgroundColor3 = rgb(32, 32, 38), ZIndex = 3 }, sg)
				f.body.Position = UDim2.fromScale(x, 1 - 0.3)
				f.baseY = 1 - 0.3
			end
			local headY = f.baseY - f.bh + 0.01
			if faces and rng:NextNumber() < 0.9 then
				f.head = mk("ImageLabel", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(x, headY), Size = UDim2.fromScale(f.hw, f.hh), BackgroundColor3 = skin, BackgroundTransparency = 0,
					Image = "rbxassetid://" .. tostring(pickFace(rng)), ScaleType = Enum.ScaleType.Fit, ZIndex = 5 }, sg)
			else
				f.head = mk("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(x, headY), Size = UDim2.fromScale(f.hw, f.hh), BackgroundColor3 = skin, ZIndex = 5 }, sg)
			end
			mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f.head)
			local hr = rng:NextNumber()
			if hr < 0.45 then
				-- a cap or a beanie over the top of the head
				f.hat = mk("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(x, headY - f.hh * 0.62), Size = UDim2.fromScale(f.hw * (hr < 0.3 and 1.08 or 0.98), f.hh * (hr < 0.3 and 0.3 or 0.42)), BackgroundColor3 = c3(HATS[rng:NextInteger(1, #HATS)]), ZIndex = 6 }, sg)
				mk("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f.hat)
				f.hatDy = f.hh * 0.62
			end
			-- arms: thin bars from the shoulders, rotated about their top (positioned so the top stays at the shoulder)
			f.armL = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromScale(colW * 0.12, f.bh * 0.78), BackgroundColor3 = shirt:Lerp(skin, rng:NextNumber() < 0.4 and 0.6 or 0), ZIndex = 3 }, sg)
			f.armR = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromScale(colW * 0.12, f.bh * 0.78), BackgroundColor3 = f.armL.BackgroundColor3, ZIndex = 3 }, sg)
			f.armLen = f.bh * 0.78
			f.phone = rng:NextNumber() < 0.14
			if f.phone then
				f.phoneF = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromScale(colW * 0.1, f.bh * 0.16), BackgroundColor3 = rgb(200, 225, 255), ZIndex = 7 }, sg)
			end
			table.insert(rec.fans, f)
		end
	end
	rec.asp = asp
	return rec
end

-- lays one printed fan out for a lift (0..1 standing), a bob and an arm angle (0 = down, 1 = straight up)
local function layoutFan(f, lift, bob, armK, armSwing, booK)
	local x = f.x
	local y = f.baseY - lift * (f.standing and 0 or 0.16) - bob
	f.body.Position = UDim2.fromScale(x, y)
	local headY = y - f.bh + 0.01
	f.head.Position = UDim2.fromScale(x, headY)
	if f.hat then
		f.hat.Position = UDim2.fromScale(x, headY - f.hatDy)
	end
	-- the shoulders
	local sy = y - f.bh * 0.92
	for i, arm in ipairs({ f.armL, f.armR }) do
		local s = i == 1 and -1 or 1
		local sx = x + s * f.bw * 0.56
		local a
		if booK > 0 then
			a = s * (0.9 + booK * 0.3) -- folded across
		else
			a = s * (0.12 + armK * (math.pi - 0.35) + armSwing * (i == 1 and 1 or -1))
		end
		-- the arm hangs from the shoulder: its centre is half a length along its direction (+y down)
		local cx = sx + math.sin(a) * f.armLen / 2 * f.asp
		local cy = sy + math.cos(a) * f.armLen / 2
		arm.Position = UDim2.fromScale(cx, cy)
		arm.Rotation = -math.deg(a)
		if i == 2 and f.phoneF then
			local hx = sx + math.sin(a) * f.armLen * f.asp
			local hy = sy + math.cos(a) * f.armLen
			f.phoneF.Position = UDim2.fromScale(hx, hy)
		end
	end
end

local function updatePrints(now, ex, boost)
	local list = S.prints
	if #list == 0 then
		return
	end
	local per = lodPick(PRINT_SLABS_PER_TICK[1], PRINT_SLABS_PER_TICK[2], PRINT_SLABS_PER_TICK[3])
	for _ = 1, per do
		S.printIdx = (S.printIdx or 0) % #list + 1
		local rec = list[S.printIdx]
		local r = reactValue(S.react, rec.ringD, now)
		local att = (r > 0 and S.react) and S.react.att or "cheer"
		for _, f in ipairs(rec.fans) do
			local fav = f.fav
			local a = att
			if att == "split" then
				a = (fav == -1) == (S.react.good == "opp") and "cheer" or (fav == 0 and "cheer" or "boo")
			end
			local lift, bob, armK, swing, booK = 0, 0, 0, 0, 0
			if a == "boo" then
				booK = r
				bob = math.sin(now * 5 + f.phase) * 0.012 * r
			else
				lift = math.clamp(r * 1.2 + (ex - 0.82) * 4, 0, 1) * (f.energy >= 1 and 1 or 0.4)
				bob = math.max(0, math.sin(now * f.speed + f.phase)) * (0.006 + ex * 0.03 * f.energy + r * 0.03)
				armK = f.phone and 0.7 or math.clamp(r * 1.3 + (ex - 0.45) * 1.6 + (fav == 1 and boost or 0), 0, 1) * (f.energy >= 1 and 1 or 0.6)
				swing = math.sin(now * f.speed * 0.5 + f.phase) * 0.15 * armK
			end
			layoutFan(f, lift, bob, armK, swing, booK)
		end
	end
end

------------------------------------------------------------------------
-- the upper bowl: RichText rows
------------------------------------------------------------------------
local function bowlRows(slab, share)
	local sg = slab:FindFirstChild("CrowdPrint")
	local rows = tonumber(slab:GetAttribute("CrowdRows"))
	if not sg or not rows then
		return nil
	end
	for _, c in ipairs(sg:GetChildren()) do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	local rng = Random.new((tonumber(slab:GetAttribute("Seed")) or 1) * 331)
	local cols = 110
	local rec = { slab = slab, sg = sg, rows = {}, ringD = (slab.Position - S.center).Magnitude }
	for i = 0, rows - 1 do
		-- the far rows of the bowl fill last
		local fill = rowFill(share, 0.6 + 0.4 * i / math.max(1, rows - 1), false)
		local heads, bodies = table.create(cols), table.create(cols)
		for j = 1, cols do
			if rng:NextNumber() < fill then
				-- far and under the house lights: dim, a little grey, so the bowl reads as a crowd and not confetti
				local sh = SHIRTS[rng:NextInteger(1, #SHIRTS)]
				local sk = Looks.SkinTones[rng:NextInteger(1, #Looks.SkinTones)]
				local kk = 0.35 + rng:NextNumber() * 0.3
				local hat = rng:NextNumber() < 0.4 and HATS[rng:NextInteger(1, #HATS)] or nil
				local hc = hat or sk
				local function dim(c)
					local g = (c[1] + c[2] + c[3]) / 3
					return math.floor((c[1] * 0.7 + g * 0.3) * kk), math.floor((c[2] * 0.7 + g * 0.3) * kk), math.floor((c[3] * 0.7 + g * 0.3) * kk)
				end
				heads[j] = string.format('<font color="#%02x%02x%02x">●</font>', dim(hc))
				bodies[j] = string.format('<font color="#%02x%02x%02x">▮</font>', dim(sh))
			else
				heads[j] = '<font transparency="1">●</font>'
				bodies[j] = '<font transparency="1">▮</font>'
			end
		end
		local rowH = 1 / rows
		local hl = mk("TextLabel", { Name = "CrowdRow", BackgroundTransparency = 1, RichText = true, TextScaled = true, TextColor3 = WHITE, Text = table.concat(heads), Size = UDim2.fromScale(1, rowH * 0.42), Position = UDim2.fromScale(0, i * rowH + rowH * 0.04), ZIndex = 3 }, sg)
		local bl = mk("TextLabel", { Name = "CrowdRow", BackgroundTransparency = 1, RichText = true, TextScaled = true, TextColor3 = WHITE, Text = table.concat(bodies), Size = UDim2.fromScale(1, rowH * 0.5), Position = UDim2.fromScale(0, i * rowH + rowH * 0.42), ZIndex = 2 }, sg)
		Typography.Apply(hl, "glyph")
		Typography.Apply(bl, "glyph")
		table.insert(rec.rows, { h = hl, b = bl, y = i * rowH, rowH = rowH, phase = rng:NextNumber() * 6.28, d = rec.ringD + i * 2.6 })
	end
	sg.LightInfluence = 0
	return rec
end

local function updateBowl(now, ex)
	local list = S.bowlRecs
	if #list == 0 then
		return
	end
	local per = lodPick(BOWL_ROWS_PER_TICK[1], BOWL_ROWS_PER_TICK[2], BOWL_ROWS_PER_TICK[3])
	for _ = 1, per do
		S.bowlIdx = (S.bowlIdx or 0) + 1
		local total = S.bowlTotal
		if S.bowlIdx > total then
			S.bowlIdx = 1
		end
		local idx = S.bowlIdx
		for _, rec in ipairs(list) do
			if idx <= #rec.rows then
				local row = rec.rows[idx]
				local r = reactValue(S.react, row.d, now)
				local lift = (math.max(0, math.sin(now * 2.2 + row.phase)) * (0.02 + ex * 0.12) + r * 0.35) * row.rowH
				row.h.Position = UDim2.fromScale(0, row.y - lift)
				row.b.Position = UDim2.fromScale(0, row.y + row.rowH * 0.45 - lift * 0.5)
				break
			end
			idx -= #rec.rows
		end
	end
end

------------------------------------------------------------------------
-- public
------------------------------------------------------------------------
-- draws the printed rows and the bowl for the arena (share = the house); the previews call it offline
function CrowdFX.Print(arena, share, center)
	local own = S == nil
	if own then
		S = { arena = arena, center = center or V3(0, 0, 0), prints = {}, bowlRecs = {}, bowlTotal = 0 }
	end
	local bowl = arena:FindFirstChild("Bowl")
	local prints, recs, total = {}, {}, 0
	if bowl then
		local k = 0
		for _, slab in ipairs(bowl:GetChildren()) do
			if slab:IsA("BasePart") and slab.Name == "RowPrint" then
				k += 1
				local rec = printSlab(slab, share, k)
				if rec then
					table.insert(prints, rec)
				end
			elseif slab:IsA("BasePart") and slab.Name == "BowlTier" then
				local rec = bowlRows(slab, share)
				if rec then
					table.insert(recs, rec)
					total += #rec.rows
				end
			end
		end
	end
	table.sort(prints, function(a, b)
		return a.ringD < b.ringD
	end)
	if own then
		local out = { prints = prints, bowl = recs }
		S = nil
		return out
	end
	S.prints, S.bowlRecs, S.bowlTotal = prints, recs, total
	return { prints = prints, bowl = recs }
end

function CrowdFX.Start(arena, opts)
	CrowdFX.Stop()
	opts = type(opts) == "table" and opts or {}
	local anchors = arena:FindFirstChild("Anchors")
	local c = anchors and anchors:FindFirstChild("RingCenter")
	S = {
		arena = arena, center = opts.center or (c and c.Position) or arena:GetPivot().Position, fans = {}, prints = {}, bowlRecs = {}, bowlTotal = 0,
		share = tonumber(opts.share) or tonumber(arena:GetAttribute("CrowdShare")) or 1, react = nil, lastLocal = {}, everyone = opts.everyone == true,
	}
	setupRigs()
	CrowdFX.Print(arena, S.share, S.center)
	-- lay the printed fans out once at rest
	for _, rec in ipairs(S.prints) do
		for _, f in ipairs(rec.fans) do
			layoutFan(f, 0, 0, f.phone and 0.7 or 0, 0, 0)
		end
	end
	-- reactions the server (Crowd.React) broadcasts
	pcall(function()
		S.conn = arena:GetAttributeChangedSignal("CrowdReact"):Connect(function()
			local v = arena:GetAttribute("CrowdReact")
			if type(v) ~= "string" then
				return
			end
			local event, who, extra = v:match("^([^|]*)|([^|]*)|([^|]*)|")
			if event and EVENTS[event] then
				local data = { who = who ~= "" and who or nil, remote = true }
				if event == "winner" then
					data.result = extra
				elseif event == "count" then
					data.n = tonumber(extra)
				end
				CrowdFX.React(event, data)
			end
		end)
	end)
	return S
end

-- a reaction: event (EVENTS), data = { who = "you" | "opp", result = "win" | "loss" | "draw", n = count }
function CrowdFX.React(event, data)
	if not S then
		return false
	end
	local ev = EVENTS[event]
	if not ev then
		return false
	end
	data = type(data) == "table" and data or {}
	local now = os.clock()
	-- the server's broadcast of a reaction the fighting client already played locally
	if data.remote and S.lastLocal[event] and now - S.lastLocal[event] < 1.0 then
		return false
	end
	if not data.remote then
		S.lastLocal[event] = now
	end
	local who = data.who == "opp" and "opp" or (data.who == "you" and "you" or nil)
	local result = data.result
	S.react = { event = event, t0 = now, k = ev.k, hold = ev.hold, decay = ev.decay, who = who, loud = ev.loud, result = result }
	-- every rig's attitude to it, once
	for _, e in ipairs(S.fans) do
		e.att = attitude(ev, e.fav, who, result)
	end
	-- the printed rows and the bowl answer as one crowd (their neutrals and the opponent's fans split on a KO)
	local good = result and (result == "win" and "you" or (result == "loss" and "opp" or nil)) or ((ev == EVENTS.knockdown or ev == EVENTS.count) and (who == "you" and "opp" or "you") or who)
	S.react.good = good
	S.react.att = ev.all or ((ev == EVENTS.ko or ev == EVENTS.winner or ev == EVENTS.knockdown) and good and "split" or "cheer")
	return true
end

function CrowdFX.Update(dt, now, excite, supportBoost)
	if not S then
		return
	end
	local ex = math.clamp(tonumber(excite) or 0.3, 0, 1)
	local boost = math.clamp(tonumber(supportBoost) or 0, 0, 1)
	if S.react and now - S.react.t0 > S.react.hold + S.react.decay + 3 then
		S.react = nil
	end
	updateRigs(dt, now, ex, boost)
	updatePrints(now, ex, boost)
	updateBowl(now, ex)
end

-- the rigs (for VenueFX's phone-light / flash volumes): { fan = part, pos = Vector3 }
function CrowdFX.Fans()
	return S and S.fans or {}
end

-- the printed rows' and the bowl's SurfaceGuis (VenueFX dims them with the house lights)
function CrowdFX.Guis()
	local out = {}
	if S then
		for _, rec in ipairs(S.bowlRecs) do
			table.insert(out, rec.sg)
		end
	end
	return out
end

-- a reaction's value at a distance from the ring now (tests, the previews)
function CrowdFX.ReactValue(ringD, now)
	return S and reactValue(S.react, ringD, now or os.clock()) or 0
end

function CrowdFX.Stop()
	if not S then
		return
	end
	pcall(function()
		if S.conn then
			S.conn:Disconnect()
		end
	end)
	-- everyone back in his seat (the arena is usually gone already)
	pcall(function()
		local parts, cfs = {}, {}
		local k = 0
		for _, e in ipairs(S.fans) do
			if e.fan.Parent then
				k = homeFan(e, parts, cfs, k)
			end
		end
		if k > 0 then
			workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
	S = nil
end

return CrowdFX
