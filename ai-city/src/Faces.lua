-- Faces (ModuleScript) — ReplicatedStorage.Shared.Faces
-- Drawn cartoon faces for citizens: eyes with irises, pupils and a shine,
-- eyebrows, a mouth that changes shape, blush and freckles.
--
-- The server builds each face once (Faces.Build) and sets the citizen's
-- "Expression" attribute. Every player's client then draws the expression,
-- blinks, glances around and moves the mouth while the citizen talks
-- (Faces.Set), so faces feel alive without costing the server anything.
--
-- Expressions: neutral, happy, grin, laugh, sad, angry, scared, surprised,
-- sleepy, asleep, hurt, focused, love, talk

local Faces = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local INK = rgb(40, 30, 32)
local MOUTH = rgb(90, 30, 40)
local TONGUE = rgb(230, 110, 120)
local EYE_COLORS = { rgb(90, 60, 40), rgb(60, 40, 28), rgb(70, 120, 180), rgb(80, 140, 90), rgb(120, 90, 60), rgb(40, 40, 50), rgb(140, 110, 70), rgb(100, 130, 150) }

Faces.Expressions = { "neutral", "happy", "grin", "laugh", "sad", "angry", "scared", "surprised", "sleepy", "asleep", "hurt", "focused", "love", "talk" }

-- The face someone has (from their own random numbers, so it never changes)
-- rng: a Random; age in years; feminine: true/false (only nudges lashes)
function Faces.Describe(rng, age, feminine)
	local kid = age < 13
	return {
		EyeColor = EYE_COLORS[rng:NextInteger(1, #EYE_COLORS)],
		EyeSize = (if kid then 1.18 else 1) * rng:NextNumber(0.9, 1.1), -- kids have big eyes
		EyeGap = rng:NextNumber(0.36, 0.42),
		EyeHeight = rng:NextNumber(0.4, 0.45),
		BrowThick = rng:NextNumber(0.035, 0.06) * (if age >= 60 then 1.3 else 1),
		BrowTilt = rng:NextNumber(-6, 6),
		Lashes = feminine and rng:NextNumber() < 0.7,
		Freckles = rng:NextNumber() < (if kid then 0.35 else 0.15),
		Blush = kid or rng:NextNumber() < 0.25,
		MouthWidth = rng:NextNumber(0.24, 0.32),
		Wrinkles = age >= 60,
	}
end

local function frame(parent, name, pos, size, color, round)
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = pos
	f.Size = size
	f.BorderSizePixel = 0
	if color then
		f.BackgroundColor3 = color
	else
		f.BackgroundTransparency = 1
	end
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(round, 0)
		c.Parent = f
	end
	f.Parent = parent
	return f
end

-- an arc: part of a circle outline, cut by a clipping frame. The clip's
-- height sets how curved it looks (up = the top of the circle, like ^)
local function arc(parent, name, pos, size, thickness, color, up)
	local clip = frame(parent, name, pos, size, nil)
	clip.ClipsDescendants = true
	local ring = frame(clip, "Ring", UDim2.fromScale(0.5, if up then 0 else 1), UDim2.fromScale(1, 1), nil, 1)
	ring.AnchorPoint = Vector2.new(0.5, if up then 0 else 1)
	local square = Instance.new("UIAspectRatioConstraint")
	square.AspectRatio = 1
	square.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Color = color
	stroke.Parent = ring
	return clip
end

-- Builds the face on a head (removes the default face decal). Returns the SurfaceGui.
function Faces.Build(head, face, skin)
	local old = head:FindFirstChild("face")
	if old and old:IsA("Decal") then
		old:Destroy()
	end
	local existing = head:FindFirstChild("CityFace")
	if existing then
		existing:Destroy()
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "CityFace"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 80
	gui.LightInfluence = 1
	gui.MaxDistance = 170
	gui.ResetOnSpawn = false
	gui.ClipsDescendants = true
	gui.Adornee = head
	local line = 3 -- ink thickness in pixels (80 px per stud)

	for _, side in ipairs({ -1, 1 }) do
		local name = if side < 0 then "L" else "R"
		local x = 0.5 + side * face.EyeGap / 2
		local eye = frame(gui, "Eye" .. name, UDim2.fromScale(x, face.EyeHeight), UDim2.fromScale(0.17 * face.EyeSize, 0.21 * face.EyeSize), nil)
		local ball = frame(eye, "Ball", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1), rgb(252, 252, 250), 1)
		ball.ClipsDescendants = true
		local iris = frame(ball, "Iris", UDim2.fromScale(0.5, 0.52), UDim2.fromScale(0.7, 0.66), face.EyeColor, 1)
		frame(iris, "Pupil", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.52, 0.52), rgb(15, 12, 14), 1)
		frame(iris, "Shine", UDim2.fromScale(0.68, 0.3), UDim2.fromScale(0.3, 0.3), rgb(255, 255, 255), 1)
		local outline = Instance.new("UIStroke")
		outline.Thickness = 1.5
		outline.Color = INK
		outline.Transparency = 0.35
		outline.Parent = ball
		-- the upper lid (grows down for sleepy and blinking eyes)
		local lid = frame(ball, "Lid", UDim2.fromScale(0.5, 0), UDim2.fromScale(1.1, 0), skin)
		lid.AnchorPoint = Vector2.new(0.5, 0)
		lid.ZIndex = 3
		-- closed happy eyes (^ ^), closed sleeping eyes (- -), and hurt eyes (x x)
		arc(eye, "Closed", UDim2.fromScale(0.5, 0.55), UDim2.fromScale(1, 0.4), line, INK, true).Visible = false
		local sleep = frame(eye, "Shut", UDim2.fromScale(0.5, 0.6), UDim2.new(1, 0, 0, line), INK, 1)
		sleep.Visible = false
		local x1 = frame(eye, "X1", UDim2.fromScale(0.5, 0.5), UDim2.new(1, 0, 0, line), INK, 1)
		x1.Rotation = 45
		x1.Visible = false
		local x2 = frame(eye, "X2", UDim2.fromScale(0.5, 0.5), UDim2.new(1, 0, 0, line), INK, 1)
		x2.Rotation = -45
		x2.Visible = false
		local heart = Instance.new("TextLabel")
		heart.Name = "Heart"
		heart.BackgroundTransparency = 1
		heart.AnchorPoint = Vector2.new(0.5, 0.5)
		heart.Position = UDim2.fromScale(0.5, 0.5)
		heart.Size = UDim2.fromScale(1.3, 1.3)
		heart.Text = "♥"
		heart.TextScaled = true
		heart.TextColor3 = rgb(235, 60, 90)
		heart.Visible = false
		heart.Parent = eye
		if face.Lashes then
			for k = 0, 1 do
				local lash = frame(eye, "Lash", UDim2.fromScale(0.5 + side * (0.42 + k * 0.1), 0.12 + k * 0.12), UDim2.new(0.22, 0, 0, 2), INK, 1)
				lash.Rotation = side * (-30 - k * 15)
			end
		end
		-- eyebrows
		local brow = frame(gui, "Brow" .. name, UDim2.fromScale(x, face.EyeHeight - 0.16 * face.EyeSize), UDim2.fromScale(0.2, face.BrowThick), INK, 1)
		brow:SetAttribute("X", x)
		brow:SetAttribute("BaseY", face.EyeHeight - 0.16 * face.EyeSize)
		brow:SetAttribute("Tilt", face.BrowTilt * side)
		brow:SetAttribute("Side", side)
		brow.Rotation = face.BrowTilt * side
		-- cheeks
		local blush = frame(gui, "Blush" .. name, UDim2.fromScale(0.5 + side * 0.33, face.EyeHeight + 0.2), UDim2.fromScale(0.16, 0.08), rgb(255, 130, 140), 1)
		blush.BackgroundTransparency = if face.Blush then 0.6 else 1
		blush:SetAttribute("Base", if face.Blush then 0.6 else 1)
		if face.Freckles then
			for k = 0, 2 do
				frame(gui, "Freckle", UDim2.fromScale(0.5 + side * (0.26 + k * 0.045), face.EyeHeight + 0.15 + (k % 2) * 0.035), UDim2.fromOffset(3, 3), rgb(160, 100, 70), 1).BackgroundTransparency = 0.3
			end
		end
		if face.Wrinkles then
			local w = frame(gui, "Wrinkle", UDim2.fromScale(0.5 + side * 0.44, face.EyeHeight), UDim2.new(0.06, 0, 0, 1), INK, 1)
			w.BackgroundTransparency = 0.6
			w.Rotation = side * 20
		end
	end

	-- the mouth: every shape is there, and Faces.Set shows the right one
	local w = face.MouthWidth
	local mouth = frame(gui, "Mouth", UDim2.fromScale(0.5, 0.74), UDim2.fromScale(w, 0.16), nil)
	mouth:SetAttribute("Width", w)
	arc(mouth, "Smile", UDim2.fromScale(0.5, 0.3), UDim2.fromScale(1, 0.55), line, INK, false)
	arc(mouth, "Frown", UDim2.fromScale(0.5, 0.65), UDim2.fromScale(0.8, 0.4), line, INK, true).Visible = false
	frame(mouth, "Line", UDim2.fromScale(0.5, 0.45), UDim2.new(0.7, 0, 0, line), INK, 1).Visible = false
	local open = frame(mouth, "Open", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.55, 0.8), MOUTH, 1)
	open.ClipsDescendants = true
	frame(open, "Tongue", UDim2.fromScale(0.5, 0.95), UDim2.fromScale(0.7, 0.55), TONGUE, 1)
	open.Visible = false
	-- a big grin: the lower half of a filled circle with teeth on top
	local grin = frame(mouth, "Grin", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1), nil)
	grin.ClipsDescendants = true
	local fill = frame(grin, "Fill", UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 2), MOUTH, 1)
	fill.ClipsDescendants = true
	frame(fill, "Teeth", UDim2.fromScale(0.5, 0.56), UDim2.fromScale(0.8, 0.16), rgb(250, 250, 248), 0.3)
	frame(fill, "Tongue", UDim2.fromScale(0.5, 0.9), UDim2.fromScale(0.5, 0.3), TONGUE, 1)
	grin.Visible = false
	-- a small wobbly line for scared / worried
	local wobble = frame(mouth, "Wobble", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.7, 0.3), nil)
	for k = 0, 2 do
		arc(wobble, "W" .. k, UDim2.fromScale(0.17 + k * 0.33, if k % 2 == 0 then 0.3 else 0.7), UDim2.fromScale(0.36, 0.4), 2, INK, k % 2 == 0)
	end
	wobble.Visible = false
	gui:SetAttribute("Expression", "neutral")
	gui.Parent = head
	return gui
end

-- What each expression does: eye state, lid (0 open .. 1 shut), brow lift
-- and angle, mouth shape, blush
local LOOK = {
	neutral = { Eyes = "open", Lid = 0.08, Brow = 0, Angle = 0, Mouth = "Smile", Small = true },
	happy = { Eyes = "open", Lid = 0.05, Brow = 0.02, Angle = 0, Mouth = "Smile" },
	grin = { Eyes = "open", Lid = 0.1, Brow = 0.03, Angle = 0, Mouth = "Grin", Blush = true },
	laugh = { Eyes = "closed", Lid = 0, Brow = 0.04, Angle = 0, Mouth = "Grin", Blush = true },
	sad = { Eyes = "open", Lid = 0.3, Brow = 0.02, Angle = -16, Mouth = "Frown" },
	angry = { Eyes = "open", Lid = 0.28, Brow = -0.035, Angle = 20, Mouth = "Frown" },
	scared = { Eyes = "open", Lid = 0, Brow = 0.05, Angle = -18, Mouth = "Wobble", Pupil = 0.35 },
	surprised = { Eyes = "open", Lid = 0, Brow = 0.06, Angle = 0, Mouth = "Open", Pupil = 0.4 },
	sleepy = { Eyes = "open", Lid = 0.55, Brow = -0.01, Angle = -6, Mouth = "Line" },
	asleep = { Eyes = "shut", Lid = 0, Brow = -0.01, Angle = -4, Mouth = "Line" },
	hurt = { Eyes = "x", Lid = 0, Brow = 0.02, Angle = -14, Mouth = "Wobble" },
	focused = { Eyes = "open", Lid = 0.22, Brow = -0.015, Angle = 8, Mouth = "Line" },
	love = { Eyes = "heart", Lid = 0, Brow = 0.04, Angle = 0, Mouth = "Grin", Blush = true },
	talk = { Eyes = "open", Lid = 0.05, Brow = 0.02, Angle = 0, Mouth = "Open" },
}
Faces.Look = LOOK

-- Draws an expression. blink: 0..1 (1 = eyes closed), talk: 0..1 mouth
-- opening while speaking, glance: -1..1 where the pupils look.
function Faces.Set(gui, expression, blink, talk, glance)
	local look = LOOK[expression] or LOOK.neutral
	blink = blink or 0
	talk = talk or 0
	glance = glance or 0
	for _, name in ipairs({ "L", "R" }) do
		local eye = gui:FindFirstChild("Eye" .. name)
		if eye then
			local state = look.Eyes
			if blink > 0.85 and state == "open" then
				state = "shut"
			end
			local ball = eye:FindFirstChild("Ball")
			ball.Visible = state == "open"
			eye.Closed.Visible = state == "closed"
			eye.Shut.Visible = state == "shut"
			eye.X1.Visible = state == "x"
			eye.X2.Visible = state == "x"
			eye.Heart.Visible = state == "heart"
			if state == "open" then
				local lid = math.clamp(math.max(look.Lid, blink), 0, 1)
				ball.Lid.Size = UDim2.fromScale(1.1, lid)
				local pupil = look.Pupil or 0.52
				ball.Iris.Pupil.Size = UDim2.fromScale(pupil, pupil)
				ball.Iris.Position = UDim2.fromScale(0.5 + glance * 0.16, 0.52 + lid * 0.12)
			end
		end
		local brow = gui:FindFirstChild("Brow" .. name)
		if brow then
			local side = brow:GetAttribute("Side") or 1
			brow.Position = UDim2.fromScale(brow:GetAttribute("X") or 0.5, (brow:GetAttribute("BaseY") or 0.26) - look.Brow)
			brow.Rotation = (brow:GetAttribute("Tilt") or 0) + look.Angle * side
		end
		local blush = gui:FindFirstChild("Blush" .. name)
		if blush then
			blush.BackgroundTransparency = if look.Blush then 0.35 else (blush:GetAttribute("Base") or 1)
		end
	end
	local mouth = gui:FindFirstChild("Mouth")
	if mouth then
		local shape = look.Mouth
		if talk > 0.05 then
			shape = "Open"
		end
		for _, child in ipairs(mouth:GetChildren()) do
			if child:IsA("Frame") then
				child.Visible = child.Name == shape
			end
		end
		local width = mouth:GetAttribute("Width") or 0.28
		if shape == "Smile" then
			mouth.Smile.Size = UDim2.fromScale(if look.Small then 0.62 else 1, if look.Small then 0.3 else 0.55)
		elseif shape == "Open" then
			local open = if talk > 0.05 then 0.25 + talk * 0.65 else 0.8
			mouth.Open.Size = UDim2.fromScale(if expression == "surprised" then 0.45 else 0.6, open)
		end
		mouth.Size = UDim2.fromScale(width, 0.16)
	end
	gui:SetAttribute("Expression", expression)
end

return Faces
