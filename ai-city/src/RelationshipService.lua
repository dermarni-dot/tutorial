-- RelationshipService (ModuleScript) — ServerScriptService.Modules.RelationshipService
-- Couples and the drama that comes with them (the plans are in Life:Plan):
--   • Date nights: partners go out together (dinner, the lake, the park, the
--     cinema, a coffee). On the way they walk hand in hand; once there they sit
--     together, lean in and chat, and little hearts float up.
--   • Cheating: now and then someone sneaks off to meet a friend behind their
--     partner's back. They flirt, laugh and whisper...
--   • Caught: if their partner shows up (some follow a hunch), there's a
--     scene: "WHAT is going on here?!", "It's not what it looks like!", a slap,
--     and "We're DONE!". The couple breaks up, the whole city hears about it,
--     and players nearby get a heads-up to come and watch.

local Players = game:GetService("Players")

local RelationshipService = {}
local S

local DATE_LINES = { "I love this place.", "You look amazing tonight.", "We should do this more often.", "Remember our first date?", "I'm so lucky.", "Happy? 😊" }
local FLIRT_LINES = { "Nobody knows we're here, right?", "You're so funny.", "Shh, not so loud...", "I've missed you.", "We have to be careful." }
local caughtToday = {} -- [pair key] = day

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function free(brain)
	return brain and brain.Model.Parent and brain.State ~= "ko" and brain.State ~= "hospital" and brain.State ~= "police" and brain.State ~= "talk" and not brain.Model:GetAttribute("Fighting") and not brain.Model:GetAttribute("Brawling")
end

local function setHand(brain, side)
	if brain.Model:GetAttribute("HoldHand") ~= side then
		brain.Model:SetAttribute("HoldHand", side)
	end
end

local function hearts(brain)
	brain.Model:SetAttribute("Hearts", os.clock())
end

local function toastNear(pos, radius, emoji, title, text, color)
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - pos).Magnitude < radius then
			S.City.Toast(p, emoji, title, text, color)
		end
	end
end

function RelationshipService.BreakUp(a, b)
	local life = S.Life
	local h = life.Households[a.Household]
	if h and h.Partners and table.find(h.Partners, a.Id) and table.find(h.Partners, b.Id) then
		h.Partners = {}
	end
	a.Ex, b.Ex = b.Id, a.Id
	a.Heartbroken, b.Heartbroken = life.Day, life.Day
end

-- the partner walks up to the two of them: a scene, a slap, a breakup
local function caught(cheater, lover, partner)
	local key = math.min(cheater.C.Id, lover.C.Id) .. ":" .. math.max(cheater.C.Id, lover.C.Id)
	if caughtToday[key] == S.Life.Day then
		return
	end
	caughtToday[key] = S.Life.Day
	S.Citizens.Control(partner, true)
	S.Citizens.SetGait(partner, 14, "run")
	partner.Humanoid:MoveTo(cheater.Root.Position)
	partner.Model:SetAttribute("Expression", "angry")
	S.Citizens.Say(partner, "WHAT is going on here?!", "angry", 3)
	local pos = cheater.Root.Position
	toastNear(pos, 180, "💔", "Busted!", partner.C.First .. " just caught " .. cheater.C.First .. " with " .. lover.C.First .. " at the " .. (cheater.Target and cheater.Target.Place and (cheater.Target.Place.Label or cheater.Target.Place.Id) or "park") .. "!", rgb(230, 80, 120))
	local token = partner.Token
	task.delay(2.2, function()
		if not partner.Model.Parent then
			return
		end
		S.Citizens.Say(cheater, ({ "It's not what it looks like!", "I can explain!", "Wait, babe, listen!" })[math.random(1, 3)], "scared", 2.6)
		cheater.Model:SetAttribute("Expression", "scared")
		lover.Model:SetAttribute("Expression", "surprised")
	end)
	task.delay(4.4, function()
		if not partner.Model.Parent or not cheater.Model.Parent then
			return
		end
		-- the slap
		local now = os.clock()
		partner.Model:SetAttribute("SwingSide", (partner.Model:GetAttribute("SwingSide") or 0) + 1)
		partner.Model:SetAttribute("Swing", now)
		cheater.Model:SetAttribute("HitFrom", partner.Root.Position)
		cheater.Model:SetAttribute("HitPower", 8)
		cheater.Model:SetAttribute("Hit", now)
		S.City.SendNear(cheater.Root.Position, 120, { Type = "Hit", Position = cheater.Root.Position + Vector3.new(0, 2, 0), Damage = 0, Weapon = "Fists" })
		S.Citizens.Say(partner, ({ "How COULD you?!", "With " .. lover.C.First .. "?! Really?!", "After everything?!" })[math.random(1, 3)], "angry", 2.6)
	end)
	task.delay(7, function()
		if not partner.Model.Parent then
			return
		end
		S.Citizens.Say(partner, "We're DONE!", "angry", 2.6)
		RelationshipService.BreakUp(cheater.C, partner.C)
		S.City.News("💔 " .. partner.C.Name .. " caught " .. cheater.C.Name .. " cheating with " .. lover.C.Name .. ". They broke up on the spot!", "Gossip")
		S.City.Boost(partner.C, -40)
		S.City.Boost(cheater.C, -25)
		if partner.Token == token then
			S.Citizens.Control(partner, false)
		end
		S.Citizens.Flee(partner, cheater.Root.Position, 10, "😭")
		partner.Model:SetAttribute("Expression", "sad")
		cheater.Model:SetAttribute("Expression", "sad")
	end)
end

local function step()
	local now = os.clock()
	for _, brain in ipairs(S.Citizens.List) do
		local plan = brain.Plan
		local partnerId = plan and (plan.Date or plan.Affair)
		local other = partnerId and S.Citizens.GetBrain(partnerId)
		if other and free(brain) and free(other) and other.Plan and (other.Plan.Date == brain.C.Id or other.Plan.Affair == brain.C.Id) then
			local d = (other.Root.Position - brain.Root.Position).Magnitude
			-- walking together: hand in hand (a date only; an affair keeps it hidden)
			if plan.Date and brain.State == "walk" and other.State == "walk" and d < 5 then
				setHand(brain, if brain.C.Id < other.C.Id then "R" else "L")
			else
				setHand(brain, nil)
			end
			if brain.State == "act" and other.State == "act" and d < 14 and brain.C.Id < other.C.Id then
				-- together at the spot
				local lines = if plan.Date then DATE_LINES else FLIRT_LINES
				if now >= (brain.NextLove or 0) then
					brain.NextLove = now + math.random(8, 16)
					local who = if math.random() < 0.5 then brain else other
					S.Citizens.Say(who, lines[math.random(1, #lines)], "happy", 2.6)
					hearts(who)
				end
				brain.Model:SetAttribute("Expression", "happy")
				other.Model:SetAttribute("Expression", "happy")
				-- an affair: is anyone's partner here?
				if plan.Affair then
					for _, cheater in ipairs({ brain, other }) do
						local partner = S.Life:PartnerOf(cheater.C)
						local pb = partner and S.Citizens.GetBrain(partner.Id)
						if pb and pb ~= brain and pb ~= other and free(pb) and (pb.Root.Position - cheater.Root.Position).Magnitude < 40 then
							caught(cheater, if cheater == brain then other else brain, pb)
							break
						end
					end
				end
			end
		elseif brain.Model:GetAttribute("HoldHand") then
			setHand(brain, nil)
		end
	end
end

function RelationshipService.Start(services)
	S = services
	task.spawn(function()
		while true do
			task.wait(0.5)
			if S.Citizens and S.Citizens.List then
				local ok, err = pcall(step)
				if not ok then
					warn("[RelationshipService] " .. tostring(err))
					task.wait(3)
				end
			end
		end
	end)
end

RelationshipService.Caught = caught

return RelationshipService
