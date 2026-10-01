-- SchoolService (ModuleScript) — ServerScriptService.Modules.SchoolService
-- 🏫 Schoolyard fights. At a school (in the building or out in the yard) you
-- can get into a scuffle with a student: fists only (weapons aren't allowed
-- at school, and the little ones under 9 are off limits). They swing back,
-- the other kids crowd round chanting "FIGHT! FIGHT!", and a few punches in
-- they give up. Soon a teacher (or any grown-up nearby, or the principal
-- over the loudspeaker) steps in: no police, but you're marched to
-- the principal's office for detention. The kid remembers it, too.

local Players = game:GetService("Players")

local SchoolService = {}
local S

SchoolService.SCHOOLS = { "School", "MiddleSchool", "HighSchool" }
SchoolService.KID_HP = 60
SchoolService.DETENTION = 20
SchoolService.MIN_AGE = 9

local fights = {} -- [player] = { School, Kid, Since, Teacher, Hits }
local detention = {} -- [player] = until (os.clock)
SchoolService.Fights = fights
SchoolService.InDetention = detention

local CHANTS = { "FIGHT! FIGHT! FIGHT!", "Ooooh!", "Get 'em!", "Somebody get a teacher!", "Oh snap!" }
local KID_HITS = { "You wanna go?!", "Leave me alone!", "I'm not scared of you!", "Back off!" }
local TEACHER_LINES = { "HEY! Break it up!", "Stop that this instant!", "Hands to yourself!" }

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function rootOf(player)
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

-- the school this spot is at (the building or its yard), or nil
function SchoolService.SchoolAt(pos)
	for _, id in ipairs(SchoolService.SCHOOLS) do
		local place = S.Map.Places[id]
		if place then
			for _, p in ipairs({ place.Inside, place.Door, place.Yard }) do
				if p and Vector3.new(pos.X - p.X, 0, pos.Z - p.Z).Magnitude < 34 then
					return place
				end
			end
		end
	end
	return nil
end

-- can this player start a scuffle with this kid, here?
function SchoolService.CanScuffle(player, brain)
	local root = rootOf(player)
	if not root or brain.C.Temp then
		return false
	end
	return S.Life:Age(brain.C) >= SchoolService.MIN_AGE and SchoolService.SchoolAt(root.Position) ~= nil and SchoolService.SchoolAt(brain.Root.Position) ~= nil
end

local function cheer(pos, kid)
	if not (S.Social and S.Social.Audience) then
		return
	end
	local n = 0
	for _, b in ipairs(S.Social.Audience(pos, 30, 6)) do
		if b ~= kid and S.Life:Age(b.C) < 18 then
			n += 1
			S.Citizens.React(b, if n % 2 == 0 then "point" else "cheer", if n <= 2 then CHANTS[math.random(1, #CHANTS)] else nil, "surprised", 4, pos)
		end
	end
end

-- the nearest teacher at that school (or any grown-up working there, or
-- failing that any grown-up close by)
local function findTeacher(place, pos)
	local best, bestD
	for _, b in ipairs(S.Citizens.List) do
		if b.Model.Parent and not b.C.Temp and b.State ~= "ko" and b.State ~= "hospital" and b.Plan and b.Plan.Kind == "Work" and b.Plan.Place == place.Id and S.Life:Age(b.C) >= 18 then
			local d = (b.Root.Position - pos).Magnitude
			if d < 200 and (not bestD or d < bestD) then
				best, bestD = b, d
			end
		end
	end
	if best then
		return best
	end
	for _, b in ipairs(S.Citizens.Nearby(pos, 70)) do
		if not b.C.Temp and S.Life:Age(b.C) >= 25 and b.State ~= "ko" and b.State ~= "hospital" and b.State ~= "police" and not b.Model:GetAttribute("Fighting") then
			return b
		end
	end
	return nil
end

-- you: off to the principal's office
local function sendToDetention(player, f)
	local root = rootOf(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if S.Crime and S.Crime.StopFight then
		S.Crime.StopFight(f.Kid)
	end
	fights[player] = nil
	if not root or not humanoid then
		return
	end
	local place = f.School
	local office = (place.Inside or place.Door) + Vector3.new(0, 3, 0)
	root.CFrame = CFrame.new(office)
	root.AssemblyLinearVelocity = Vector3.zero
	detention[player] = os.clock() + SchoolService.DETENTION
	player:SetAttribute("Detention", workspace:GetServerTimeNow() + SchoolService.DETENTION)
	humanoid.WalkSpeed = 0
	S.City.Toast(player, "📋", "DETENTION", "Fighting at school! You're in the principal's office for " .. SchoolService.DETENTION .. " seconds. Think about what you did.", rgb(230, 160, 60))
	S.City.News("🏫 " .. player.DisplayName .. " got into a fight with " .. f.Kid.C.First .. " at the " .. (place.Label or place.Id) .. " and got detention.", "School", true)
	if f.Kid.Model.Parent then
		pcall(S.City.Remember, f.Kid.C, player, "picked a fight with me at school", -25, "picked a fight with " .. f.Kid.C.First .. " at school")
	end
end
SchoolService.SendToDetention = sendToDetention

-- a punch landed on a kid at school (from CrimeService.Attack)
function SchoolService.Hit(player, brain, w, id, fromPos)
	if id ~= "Fists" then
		S.City.Toast(player, "🏫", "No weapons at school", "Put that away. Fists only, and a teacher will be here any second.", rgb(220, 120, 80))
		return { Ok = true, Hit = false, Weapon = id }
	end
	local root = rootOf(player)
	local f = fights[player]
	if not f or f.Kid ~= brain then
		f = { School = SchoolService.SchoolAt(root.Position), Kid = brain, Since = os.clock(), Hits = 0 }
		fights[player] = f
		cheer(brain.Root.Position, brain)
	end
	f.Hits += 1
	brain.SchoolFight = true
	brain.HP = (brain.HP or SchoolService.KID_HP) - w.Damage
	brain.LastHit = os.clock()
	brain.Model:SetAttribute("MaxHP", SchoolService.KID_HP)
	brain.Model:SetAttribute("HP", math.max(0, brain.HP))
	S.City.SendNear(brain.Root.Position, 120, { Type = "Hit", Position = brain.Root.Position + Vector3.new(0, 2, 0), Damage = w.Damage, Weapon = id })
	if brain.HP <= 0 then
		-- down on the ground, but just winded (kids don't go to hospital)
		brain.HP = nil
		brain.Model:SetAttribute("HP", nil)
		if S.Crime and S.Crime.StopFight then
			S.Crime.StopFight(brain)
		end
		S.Citizens.Hurt(brain, fromPos, "OW! Okay, okay, you win!", (w.Knock or 14) * 1.5)
		return { Ok = true, Hit = true, Name = brain.C.First, Weapon = id, Won = true }
	end
	S.Citizens.Hurt(brain, fromPos, KID_HITS[math.random(1, #KID_HITS)], w.Knock)
	-- most kids swing back; the shy ones run off crying for a teacher
	local p = brain.C.Personality
	if p == "shy" or p == "anxious" then
		task.delay(0.4, function()
			S.Citizens.Flee(brain, fromPos, 8, "TEACHER!!")
		end)
	elseif S.Crime and S.Crime.StartFight then
		task.delay(0.3, function()
			S.Crime.StartFight(brain, player)
		end)
	end
	return { Ok = true, Hit = true, Name = brain.C.First, HP = brain.HP, Weapon = id }
end

-- every half second: the teacher on the way, detention running out
local function step()
	local now = os.clock()
	for player, f in pairs(fights) do
		local root = rootOf(player)
		if not player.Parent or not root then
			fights[player] = nil
		elseif not f.Teacher and now - f.Since > 3 then
			local t = findTeacher(f.School, root.Position)
			if t then
				S.Citizens.Control(t, true)
				f.Teacher = t
				S.Citizens.Say(t, TEACHER_LINES[math.random(1, #TEACHER_LINES)], "angry", 2.5)
			elseif now - f.Since > 8 then
				-- no teacher around: the principal saw it all on the cameras
				S.City.Toast(player, "📢", "PRINCIPAL", player.DisplayName .. ", to my office. NOW.", rgb(230, 160, 60))
				sendToDetention(player, f)
			end
		elseif f.Teacher then
			local t = f.Teacher
			local d = (t.Root.Position - root.Position).Magnitude
			if not t.Model.Parent or t.State == "ko" or d > 220 or not SchoolService.SchoolAt(root.Position) then
				-- you ran off (or the teacher got hurt): they give up
				if t.Model.Parent and t.State == "police" then
					S.Citizens.Say(t, "I KNOW who you are!", "angry", 2.5)
					S.Citizens.Control(t, false)
				end
				fights[player] = nil
			elseif d < 6 then
				S.Citizens.Say(t, "Principal's office. NOW.", "angry", 3)
				S.Citizens.Control(t, false)
				sendToDetention(player, f)
			else
				S.Citizens.SetGait(t, 15, "run")
				t.Humanoid:MoveTo(root.Position)
			end
		end
	end
	for player, untilT in pairs(detention) do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not player.Parent then
			detention[player] = nil
		elseif now >= untilT then
			detention[player] = nil
			player:SetAttribute("Detention", nil)
			if humanoid then
				humanoid.WalkSpeed = S.Config.PLAYER_WALK_SPEED or 16
			end
			S.City.Toast(player, "🏫", "Detention's over", "You can go. And no more fighting!", rgb(120, 190, 120))
		elseif humanoid then
			humanoid.WalkSpeed = 0
		end
	end
end
SchoolService.Step = step

function SchoolService.Start(services)
	S = services
	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, err = pcall(step)
			if not ok then
				warn("[SchoolService] " .. tostring(err))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		fights[player] = nil
		detention[player] = nil
	end)
end

return SchoolService
