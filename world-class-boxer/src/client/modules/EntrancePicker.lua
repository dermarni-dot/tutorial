-- EntrancePicker: the Locker Room's ENTRANCE window (State.open.Entrance): the ring walk's celebrations (one at the
-- tunnel, one down the aisle or none, one in the ring), whether the crowd may carry him in on its shoulders, and the
-- walkout song / announcer style the creator set. Saved with the server's SetEntrance (Shared.Entrance.Sanitize on
-- both sides); the current choice comes with the profile summary (P.entrance = Entrance.View).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Entrance = require(Shared:WaitForChild("Entrance"))
local UI = require(Shared:WaitForChild("UI"))
local State = require(script.Parent:WaitForChild("State"))
local T = UI.Theme

local EntrancePicker = {}

local shade
local function close()
	State.windows.Entrance = nil
	if shade then
		shade:Destroy()
		shade = nil
	end
end

local function nameOf(id)
	if id == Entrance.NONE then
		return "None"
	end
	local c = Entrance.ById[id]
	return c and c.name or tostring(id)
end

-- the editable copy: the celebrations, carry, and the identity's walkout song and announcer voice
local function current(P)
	local view = type(P.entrance) == "table" and P.entrance or {}
	local c = Entrance.Sanitize(view.choice)
	local id = type(P.identity) == "table" and P.identity or {}
	c.music = tostring(id.music or "")
	c.voice = table.find(Config.VoiceTypes, id.voice) and id.voice or "Calm"
	return c, tonumber(view.belts) or 0
end

-- overLocker = opened from the Locker Room (its fitting session stays open under this window)
function EntrancePicker.Open(overLocker)
	local P = State.P
	if not (P and P.created) then
		return
	end
	if overLocker ~= true then
		State.closeAll("Entrance")
	end
	local C, belts = current(P)
	local fh = math.max(44, UI.MinHit(State.gui))
	local win, body
	shade, win, body = UI.Window(State.gui, "Entrance", 600, 720, "ENTRANCE", { onClose = close, footer = fh + 12, kicker = "Locker room  ·  ring walk" })
	State.windows.Entrance = close
	local footer = UI.Frame(win, { Name = "Footer", BackgroundTransparency = 1, Position = UDim2.new(0, 16, 1, -(fh + 12)), Size = UDim2.new(1, -32, 0, fh) })

	local descs = {}
	local function describe(slot, id)
		local l = descs[slot]
		if not l then
			return
		end
		local c = Entrance.ById[id]
		local txt = id == Entrance.NONE and "Just the walk: no second celebration." or (c and c.desc or "")
		if c and c.belt and belts <= 0 then
			txt ..= "  (Needs a belt: until you win one he pumps a fist instead.)"
		end
		l.Text = txt
	end

	UI.Header(body, "CELEBRATIONS")
	UI.Line(body, "Your boxer does one in the tunnel, one down the aisle and one in his corner. The ring walk is skippable (Space, A or tap SKIP).", { TextColor3 = T.sub, TextSize = 13 })
	UI.Cycler(body, "In the tunnel", Entrance.WALK, C.walk1, function(v)
		C.walk1 = v
		if C.walk2 == v then
			C.walk2 = Entrance.NONE
		end
		describe("walk1", v)
	end, nameOf)
	descs.walk1 = UI.Line(body, "", { Name = "TunnelDesc", TextColor3 = T.sub, TextSize = 13 })
	local aisle = { Entrance.NONE }
	for _, id in ipairs(Entrance.WALK) do
		table.insert(aisle, id)
	end
	UI.Cycler(body, "Down the aisle", aisle, C.walk2, function(v)
		C.walk2 = v
		describe("walk2", v)
	end, nameOf)
	descs.walk2 = UI.Line(body, "", { Name = "AisleDesc", TextColor3 = T.sub, TextSize = 13 })
	UI.Cycler(body, "In the ring", Entrance.RING, C.ring, function(v)
		C.ring = v
		describe("ring", v)
	end, nameOf)
	descs.ring = UI.Line(body, "", { Name = "RingDesc", TextColor3 = T.sub, TextSize = 13 })
	describe("walk1", C.walk1)
	describe("walk2", C.walk2)
	describe("ring", C.ring)

	UI.Header(body, "CARRIED BY THE CROWD")
	UI.Cycler(body, "Carried in", { "yes", "no" }, C.carry and "yes" or "no", function(v)
		C.carry = v == "yes"
	end, function(v)
		return v == "yes" and "When the fans want to" or "Never: I walk"
	end)
	UI.Line(body, string.format("Fans lift a fan favourite (popularity %d+) onto their shoulders, and a well-known boxer (%d+) on a title night. Your popularity: %d.",
		Entrance.CARRY_POP, Entrance.CARRY_POP_BIG, math.floor(tonumber(P.popularity) or 0)), { TextColor3 = T.sub, TextSize = 13 })

	UI.Header(body, "WALKOUT MUSIC & ANNOUNCER")
	local sample
	UI.Cycler(body, "Announcer style", Config.VoiceTypes, C.voice, function(v)
		C.voice = v
		if sample then
			sample.Text = "\"" .. tostring(Config.AnnouncerIntro[v] or "") .. "\""
		end
	end)
	sample = UI.Line(body, "\"" .. tostring(Config.AnnouncerIntro[C.voice] or "") .. "\"", { Name = "IntroSample", TextColor3 = Color3.fromRGB(255, 170, 170), TextSize = 14 })
	UI.TextInput(body, "Walkout song (audio ID)", C.music, "Optional Roblox audio ID", 20, function(v)
		C.music = tostring(v or ""):gsub("%D", "")
	end)

	UI.Button(footer, "SAVE", { Name = "Save", Size = UDim2.new(0.62, 0, 1, 0), BackgroundColor3 = T.gold, TextColor3 = T.bg }, function()
		local r = State.req("SetEntrance", { walk1 = C.walk1, walk2 = C.walk2, ring = C.ring, carry = C.carry, music = C.music, voice = C.voice })
		if r and r.ok then
			State.toast("Entrance saved.", T.green)
			close()
		else
			State.toast((r and r.err) or "Couldn't save", T.red)
		end
	end)
	UI.Button(footer, "CANCEL", { Name = "Cancel", Size = UDim2.new(0.34, 0, 1, 0), Position = UDim2.new(0.66, 0, 0, 0) }, close)
	return shade
end

State.open.Entrance = EntrancePicker.Open

return EntrancePicker
