-- BodyFX: muscles that move. Client-only, driven by the Animator every frame.
--  * contraction: the Animator writes how hard each muscle works this frame (rig.cxL / rig.cxR,
--    keyed by Config.MuscleParts id, 0..1); a contracting muscle shortens and bulges
--  * pump: the server's Pump / PumpParts / PumpAt attributes (Training.ApplyPump) fade over
--    Config.Pump.duration; the local LivePump attribute (Activities) pumps the exercise's muscles
--  * jiggle: damped springs per body region, kicked by impacts (punches landing, body shots,
--    rope hops, bar lockouts)
--  * veins (Beams tagged Vein, attribute BaseTransparency set by the Builder from VeinLevel) show
--    more with pump, contraction and Strain
-- Only SpecialMesh.Scale (from the BaseScale attribute) and Beam.Transparency are written, never
-- Size, so no physics is recomputed (CONTRACTS section 5). Nothing allocates per frame.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local K = require(script.Parent:WaitForChild("AnimKit"))
local okConfig, Config = pcall(function()
	return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
end)
if not okConfig then
	Config = {}
end

local BodyFX = {}

local PUMP = Config.Pump or {}
local PUMP_DURATION = PUMP.duration or 150
local PUMP_SCALE = PUMP.scale or 0.08
local FLEX_SCALE = PUMP.flexScale or 0.12
local VEIN_BOOST = PUMP.veinBoost or 0.4
local NEAR = 45 -- studs: closer than this the muscles are animated
local exp, abs, min, max = math.exp, math.abs, math.min, math.max
local V3 = Vector3.new

-- body regions that jiggle together: 1 chest, 2 core, 3 arms, 4 legs
local REGION = { chest = 1, back = 1, neck = 1, core = 2, shoulders = 3, arms = 3, legs = 4 }
local REGION_ID = { chest = 1, core = 2, arms = 3, legs = 4 }
local JIG_K, JIG_C = 210, 9 -- soft tissue: fast, lightly damped

-- per exercise: weight / max weight, so the main movers contract fully (Config.ExerciseTargets)
local TARGETS = {}
for actId, parts in pairs(Config.ExerciseTargets or {}) do
	local top = 0
	for _, w in pairs(parts) do
		top = max(top, w)
	end
	local norm = {}
	for id, w in pairs(parts) do
		norm[id] = top > 0 and w / top or 0
	end
	TARGETS[actId] = norm
end
BodyFX.Targets = TARGETS

local tracked = {} -- model -> rec

local function newRec(model)
	return {
		model = model, folder = false, list = {}, veins = {}, nextScan = 0, nextAttr = 0,
		pump = 0, pumpStr = nil, pumpSet = {}, live = 0, strain = 0,
		jx = { 0, 0, 0, 0 }, jv = { 0, 0, 0, 0 }, dirty = false, awake = false,
	}
end

function BodyFX.Track(model)
	if model and not tracked[model] then
		tracked[model] = newRec(model)
	end
end

function BodyFX.Untrack(model)
	local rec = tracked[model]
	if not rec then
		return
	end
	-- leave the muscles exactly as the Builder made them
	for _, m in ipairs(rec.list) do
		if m.mesh.Parent then
			m.mesh.Scale = m.base
		end
	end
	for _, v in ipairs(rec.veins) do
		if v.beam.Parent then
			v.beam.Transparency = NumberSequence.new(v.base)
		end
	end
	tracked[model] = nil
end

-- region: "chest" | "core" | "arms" | "legs" | "all"; amount ~0..1.5 (velocity kick)
function BodyFX.Jiggle(model, region, amount)
	local rec = tracked[model]
	if not rec then
		return
	end
	local a = (amount or 0.5) * 2.2
	if region == "all" then
		for i = 1, 4 do
			rec.jv[i] += a * (i == 2 and 1 or 0.7)
		end
	else
		local i = REGION_ID[region]
		if i then
			rec.jv[i] += a
		end
	end
	rec.awake = true
end

-- index the Muscles folder (rebuilt by every Builder.Cosmetics, so re-scan when it changes)
local function scan(rec)
	local look = rec.model:FindFirstChild("BoxerLook")
	local folder = look and look:FindFirstChild("Muscles")
	if folder == rec.folder then
		return
	end
	rec.folder = folder or false
	table.clear(rec.list)
	table.clear(rec.veins)
	if not folder then
		return
	end
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			local id = d:GetAttribute("Part")
			local mesh = id and d:FindFirstChildOfClass("SpecialMesh")
			if mesh and not d:GetAttribute("Groove") and not d:GetAttribute("Fat") then
				local base = d:GetAttribute("BaseScale")
				if typeof(base) ~= "Vector3" then
					base = mesh.Scale
				end
				-- the longest axis is the fibre direction: contraction shortens it and thickens the others
				local s = d.Size
				local long = (s.X >= s.Y and s.X >= s.Z) and 1 or ((s.Y >= s.Z) and 2 or 3)
				local group = d:GetAttribute("Group") or (Config.MusclePartGroup and Config.MusclePartGroup[id]) or ""
				table.insert(rec.list, {
					part = d, mesh = mesh, base = base, id = id, side = d:GetAttribute("Side") or 0,
					long = long, region = REGION[group] or 2, c = 0, wk = -1, wl = -1,
					peak = (d:GetAttribute("Layer") or 1) >= 2,
				})
			end
		elseif d:IsA("Beam") and d.Name == "Vein" then
			local base = d:GetAttribute("BaseTransparency")
			if type(base) ~= "number" then
				base = 0.6
			end
			table.insert(rec.veins, { beam = d, id = d:GetAttribute("Part") or "", base = base, last = base })
		end
	end
end

local function readAttrs(rec, now)
	local m = rec.model
	local pump = m:GetAttribute("Pump")
	local at = m:GetAttribute("PumpAt")
	local level = 0
	if type(pump) == "number" and pump > 0 then
		if type(at) == "number" then
			level = pump * K.clamp01(1 - (now - at) / PUMP_DURATION)
		else
			level = pump
		end
	end
	rec.pump = level
	local parts = m:GetAttribute("PumpParts")
	if parts ~= rec.pumpStr then
		rec.pumpStr = parts
		table.clear(rec.pumpSet)
		if type(parts) == "string" then
			for id in string.gmatch(parts, "[^,%s]+") do
				rec.pumpSet[id] = true
			end
		end
	end
	local live = m:GetAttribute("LivePump")
	rec.live = type(live) == "number" and K.clamp01(live) or 0
	local strain = m:GetAttribute("Strain")
	local effort = m:GetAttribute("Effort")
	rec.strain = max(type(strain) == "number" and strain or 0, type(effort) == "number" and effort * 0.6 or 0)
end

local function restore(rec)
	for _, m in ipairs(rec.list) do
		if m.wk ~= -1 and m.mesh.Parent then
			m.mesh.Scale = m.base
		end
		m.wk, m.wl, m.c = -1, -1, 0
	end
	for _, v in ipairs(rec.veins) do
		if v.last ~= v.base and v.beam.Parent then
			v.beam.Transparency = NumberSequence.new(v.base)
		end
		v.last = v.base
	end
end

-- rigs = the Animator's rig table (rig.cxL / rig.cxR / rig.poseAct / rig.near), may be nil
function BodyFX.Update(dt, t, camPos, rigs)
	local now = workspace:GetServerTimeNow()
	for model, rec in pairs(tracked) do
		if not model.Parent then
			tracked[model] = nil
			continue
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		if not root then
			continue
		end
		local far = (root.Position - camPos).Magnitude > NEAR
		if far then
			if rec.awake then
				restore(rec)
				rec.awake = false
			end
			continue
		end
		if t >= rec.nextScan then
			rec.nextScan = t + 0.5
			scan(rec)
		end
		if t >= rec.nextAttr then
			rec.nextAttr = t + 0.2
			readAttrs(rec, now)
		end
		local list = rec.list
		if #list == 0 then
			continue
		end
		local rig = rigs and rigs[model]
		local cxL = rig and rig.cxL
		local cxR = rig and rig.cxR
		local live = rec.live
		local liveSet = live > 0 and rig and rig.poseAct and TARGETS[rig.poseAct] or nil
		-- jiggle springs
		local jig = false
		for i = 1, 4 do
			local x, v = K.spring(rec.jx[i], rec.jv[i], 0, JIG_K, JIG_C, dt)
			if abs(x) < 1e-4 and abs(v) < 1e-3 then
				x, v = 0, 0
			else
				jig = true
			end
			rec.jx[i], rec.jv[i] = x, v
		end
		local anyC = false
		if cxL then
			for _, v in pairs(cxL) do
				if v > 0 then
					anyC = true
					break
				end
			end
		end
		if not anyC and cxR then
			for _, v in pairs(cxR) do
				if v > 0 then
					anyC = true
					break
				end
			end
		end
		local active = anyC or jig or rec.pump > 0.005 or live > 0.005
		if not active and not rec.awake then
			continue
		end
		local settled = true
		local upRate, downRate = 1 - exp(-dt * 14), 1 - exp(-dt * 5)
		for _, m in ipairs(list) do
			local id = m.id
			local want = 0
			if cxL or cxR then
				local l = cxL and cxL[id] or 0
				local r = cxR and cxR[id] or 0
				if m.side < 0 then
					want = l
				elseif m.side > 0 then
					want = r
				else
					want = max(l, r)
				end
			end
			-- muscles tense fast and relax slowly
			m.c += (want - m.c) * (want > m.c and upRate or downRate)
			if m.c < 1e-3 then
				m.c = 0
			end
			local pump = rec.pumpSet[id] and rec.pump or 0
			if liveSet and liveSet[id] then
				pump = max(pump, live * liveSet[id])
			end
			local c = m.c * (m.peak and 1.25 or 1)
			local j = rec.jx[m.region]
			local thick = 1 + FLEX_SCALE * c + PUMP_SCALE * pump + j * 0.5
			local long = 1 - FLEX_SCALE * 0.35 * c + PUMP_SCALE * 0.4 * pump - j * 0.25
			if c > 0 or pump > 0 or j ~= 0 then
				settled = false
			end
			-- skip the write when nothing visible changed (Scale writes replicate to the renderer)
			if abs(thick - m.wk) > 0.002 or abs(long - m.wl) > 0.002 then
				m.wk, m.wl = thick, long
				local b = m.base
				if m.long == 1 then
					m.mesh.Scale = V3(b.X * long, b.Y * thick, b.Z * thick)
				elseif m.long == 2 then
					m.mesh.Scale = V3(b.X * thick, b.Y * long, b.Z * thick)
				else
					m.mesh.Scale = V3(b.X * thick, b.Y * thick, b.Z * long)
				end
			end
		end
		-- veins: pump, contraction of the host muscle and strain bring them out
		for _, v in ipairs(rec.veins) do
			local id = v.id
			local c = 0
			if cxL or cxR then
				c = max(cxL and cxL[id] or 0, cxR and cxR[id] or 0)
			end
			local pump = rec.pumpSet[id] and rec.pump or rec.pump * 0.3
			local level = K.clamp01(pump * (1 + VEIN_BOOST) * 0.8 + c * 0.45 + rec.strain * 0.35)
			-- conditioning sets how far they come out: the Builder's base (VeinLevel) drops by at most
			-- Config.Pump.veinBoost, so a beginner's pump shows faint veins, an athlete's clear ones,
			-- and nothing goes past the elite floor (0.15) or ever fades below its own base
			local target = min(v.base, max(0.15, v.base - VEIN_BOOST * level))
			target = math.floor(target * 20 + 0.5) / 20
			if target ~= v.last then
				v.last = target
				v.beam.Transparency = NumberSequence.new(target)
			end
			if target ~= v.base then
				settled = false
			end
		end
		rec.awake = not settled
	end
end

-- Track every player's character as well (pump shows on players walking around after training)
local function hookPlayer(plr)
	plr.CharacterAdded:Connect(function(char)
		BodyFX.Track(char)
	end)
	if plr.Character then
		BodyFX.Track(plr.Character)
	end
end
for _, plr in ipairs(Players:GetPlayers()) do
	hookPlayer(plr)
end
Players.PlayerAdded:Connect(hookPlayer)

return BodyFX
