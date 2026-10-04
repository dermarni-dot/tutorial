-- BuilderBody: everything built on the body below the head (server side), split out of Builder.
-- * body evolution: muscle overlays that grow with training, body fat, frame type
-- * colours: skin, satin trunks, worn shoes on the R15 parts
-- * attire: trunks, waistband, socks, boxing boots / shoes, robe
-- * gloves with finishes, logos, stitching, embroidery and visible wear; hand wraps
-- Builder.Cosmetics runs Colors first, then (after the head) Muscles, Attire and Hands; Builder
-- forwards SetRobe here and uses frameOf / avgDev for Builder.Scales.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Looks = require(Shared:WaitForChild("Looks"))
local Kit = require(script.Parent:WaitForChild("BuilderKit"))

local Body = {}

local V3, CF, ANG, SMOOTH = Kit.V3, Kit.CF, Kit.ANG, Kit.SMOOTH
local lerpColor, darken, contrast = Kit.lerpColor, Kit.darken, Kit.contrast
local mk, textPatch, getFolder, part = Kit.mk, Kit.textPatch, Kit.getFolder, Kit.part

------------------------------------------------------------------------
-- Frame / training helpers (also used by Builder.Scales)
------------------------------------------------------------------------
local function frameOf(app)
	return Config.FindById(Config.BodyTypes, app.body and app.body.frame or "Athletic") or Config.BodyTypes[2]
end

local function avgDev(build, keys)
	local t = 0
	for _, k in ipairs(keys) do
		t += (build and build[k] or 10)
	end
	return t / #keys / 100
end

------------------------------------------------------------------------
-- Body: colors, muscles, attire
------------------------------------------------------------------------
local function musclesBuild(model, app, build)
	local folder = getFolder(model, "Muscles")
	build = build or {}
	local frame = frameOf(app)
	local sl = app.body or {}
	local female = app.gender == 2
	local skin = Looks.Color(Looks.SkinTones[app.skin or 5])
	local trunks = Looks.Color(app.attire and app.attire.trunks, Color3.fromRGB(200, 25, 30))
	local top = Looks.Color(app.attire and app.attire.trim, Color3.new(1, 1, 1))
	local fat = build.fat or 14
	local def = math.clamp((16 - fat) / 8, 0, 1) -- muscle definition from low body fat
	local function lvl(k, slider)
		return math.clamp(((build[k] or 8) / 100) * frame.potential * (1 + 0.3 * (slider or 0)), 0, 1.2)
	end
	local chestL, shoulderL, armL, backL = lvl("chest", sl.chest), lvl("shoulders", sl.shoulders), lvl("arms", sl.arms), lvl("back")
	local legL, coreL, neckL = lvl("legs", sl.legs), lvl("core"), lvl("neck", sl.neck)

	local ut, lt = part(model, "UpperTorso"), part(model, "LowerTorso")
	if ut then
		local s = ut.Size
		local chestColor = female and top or skin
		-- pecs
		if chestL > 0.12 or female then
			for side = -1, 1, 2 do
				local k = female and 0.5 or chestL
				mk(folder, ut, "Pec", V3(0.44 * s.X * (0.85 + 0.3 * k), 0.34 * s.Y * (0.85 + 0.25 * k), 0.12 + 0.28 * k * s.Z),
					ut.CFrame * CF(side * 0.23 * s.X, 0.2 * s.Y, -s.Z * 0.42), chestColor, "Ellipsoid")
			end
		end
		-- abs: visible with low fat and a trained core
		if coreL > 0.12 and def > 0.15 then
			local absColor = female and skin or lerpColor(skin, Color3.new(1, 1, 1), 0.04)
			for row = 0, 2 do
				for side = -1, 1, 2 do
					mk(folder, ut, "Ab", V3(0.17 * s.X, 0.13 * s.Y, 0.06 + 0.06 * coreL), ut.CFrame * CF(side * 0.105 * s.X, (-0.06 - row * 0.15) * s.Y, -s.Z * 0.47), absColor, "Ellipsoid", SMOOTH, 1 - def * 0.9)
				end
			end
		end
		if female then
			-- sports top with a bare midriff
			mk(folder, ut, "Midriff", V3(s.X * 1.01, s.Y * 0.32, s.Z * 1.02), ut.CFrame * CF(0, -0.34 * s.Y, 0), skin, "Block")
		end
		-- traps
		if backL > 0.3 or neckL > 0.35 then
			local k = math.max(backL, neckL)
			mk(folder, ut, "Traps", V3(0.85 * s.X * (0.6 + 0.3 * k), 0.12 + 0.22 * k * s.Y, 0.6 * s.Z), ut.CFrame * CF(0, 0.47 * s.Y, 0.08 * s.Z), female and top or skin, "Ellipsoid")
		end
		-- lats (V-taper)
		if backL > 0.25 then
			for side = -1, 1, 2 do
				mk(folder, ut, "Lat", V3(0.22 * s.X * (0.8 + 0.5 * backL), 0.62 * s.Y, 0.7 * s.Z), ut.CFrame * CF(side * 0.44 * s.X, 0.02 * s.Y, 0.08 * s.Z), female and top or skin, "Ellipsoid")
			end
			mk(folder, ut, "BackMuscle", V3(0.8 * s.X, 0.7 * s.Y, 0.08 + 0.2 * backL), ut.CFrame * CF(0, 0.12 * s.Y, s.Z * 0.45), female and top or skin, "Ellipsoid")
		end
		-- belly when body fat is high
		if fat > 19 then
			local k = math.clamp((fat - 19) / 8, 0, 1)
			mk(folder, ut, "Belly", V3(0.75 * s.X, 0.5 * s.Y, 0.15 + 0.35 * k), ut.CFrame * CF(0, -0.3 * s.Y, -s.Z * 0.42), skin, "Ellipsoid")
		end
		-- neck
		local head = part(model, "Head")
		if head then
			local d = (0.5 + 0.22 * neckL + 0.08 * (sl.neck or 0)) * head.Size.X
			mk(folder, ut, "Neck", V3(0.4, d, d), ut.CFrame * CF(0, s.Y * 0.5 + 0.08, 0.02) * ANG(0, 0, math.rad(90)), skin, "Cylinder")
		end
	end
	if lt and (sl.waist or 0) > 0.2 then
		local s = lt.Size
		for side = -1, 1, 2 do
			mk(folder, lt, "Oblique", V3(0.3 * s.X * (sl.waist or 0), s.Y * 1.4, 0.8 * s.Z), lt.CFrame * CF(side * 0.48 * s.X, 0.25 * s.Y, 0), trunks, "Ellipsoid")
		end
	end
	for _, side in ipairs({ "Left", "Right" }) do
		local sign = side == "Left" and -1 or 1
		local ua, la = part(model, side .. "UpperArm"), part(model, side .. "LowerArm")
		if ua then
			local s = ua.Size
			if shoulderL > 0.1 then
				mk(folder, ua, "Delt", V3(s.X * (1.02 + 0.28 * shoulderL), s.Y * 0.5, s.Z * (1.02 + 0.22 * shoulderL)), ua.CFrame * CF(sign * 0.04 * shoulderL, 0.28 * s.Y, 0), skin, "Ellipsoid")
			end
			if armL > 0.12 then
				mk(folder, ua, "Bicep", V3(s.X * (0.62 + 0.3 * armL), s.Y * 0.55, 0.1 + 0.4 * armL * s.Z), ua.CFrame * CF(0, -0.05 * s.Y, -s.Z * 0.42), skin, "Ellipsoid")
				mk(folder, ua, "Tricep", V3(s.X * (0.6 + 0.25 * armL), s.Y * 0.6, 0.08 + 0.3 * armL * s.Z), ua.CFrame * CF(0, 0.02 * s.Y, s.Z * 0.42), skin, "Ellipsoid")
			end
		end
		if la and armL > 0.3 then
			local s = la.Size
			mk(folder, la, "Forearm", V3(s.X * (1.02 + 0.15 * armL), s.Y * 0.55, s.Z * (1.02 + 0.15 * armL)), la.CFrame * CF(0, 0.18 * s.Y, 0), skin, "Ellipsoid")
			if armL > 0.6 and def > 0.5 then
				mk(folder, la, "Vein", V3(0.04, s.Y * 0.6, 0.04), la.CFrame * CF(0.1, 0.05 * s.Y, -s.Z * 0.53) * ANG(0, 0, math.rad(8)), darken(lerpColor(skin, Color3.fromRGB(80, 90, 150), 0.25), 0.85))
			end
		end
		local ul, ll = part(model, side .. "UpperLeg"), part(model, side .. "LowerLeg")
		if ul and legL > 0.12 then
			local s = ul.Size
			mk(folder, ul, "Quad", V3(s.X * (0.82 + 0.3 * legL), s.Y * 0.72, 0.1 + 0.3 * legL * s.Z), ul.CFrame * CF(0, 0.04 * s.Y, -s.Z * 0.42), skin, "Ellipsoid")
		end
		if ll and legL > 0.15 then
			local s = ll.Size
			-- with tall boxing boots the calf bulges out above the boot shaft
			local tall = not (app.attire and app.attire.shoeStyle == "Low-Top")
			local cy, ch = tall and 0.25 or 0.15, tall and 0.38 or 0.45
			mk(folder, ll, "Calf", V3(s.X * (0.75 + 0.25 * legL), s.Y * ch, 0.1 + 0.35 * legL * s.Z), ll.CFrame * CF(0, cy * s.Y, s.Z * 0.4), skin, "Ellipsoid")
		end
	end
end

local function colorBody(model, app, gear)
	local skin = Looks.Color(Looks.SkinTones[app.skin or 5])
	local a = app.attire or {}
	local shoeCond = gear and gear.shoesCond or 100
	local shoeColor = Looks.Color(a.shoes, Color3.fromRGB(25, 25, 25))
	if shoeCond < 60 then
		-- worn-out shoes fade and get grubby
		shoeColor = lerpColor(shoeColor, Color3.fromRGB(95, 85, 70), (60 - shoeCond) / 60 * 0.45)
	end
	local trunks = Looks.Color(a.trunks, Color3.fromRGB(200, 25, 30))
	local bc = model:FindFirstChildOfClass("BodyColors")
	if bc then
		bc:Destroy()
	end
	local smooth = (app.face and app.face.smooth or 0.5) >= 0.5
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			local n = p.Name
			if n == "LowerTorso" then
				p.Color = trunks
				p.Material = SMOOTH -- satin trunks (the Fabric texture reads as noise at play distance)
			elseif n:find("Foot") then
				p.Color = shoeColor
				p.Material = Enum.Material.Leather
			else
				p.Color = skin
				p.Material = smooth and SMOOTH or Enum.Material.Plastic
			end
		end
	end
	if app.gender == 2 then
		local ut = model:FindFirstChild("UpperTorso")
		if ut then
			ut.Color = Looks.Color(a.trim, Color3.new(1, 1, 1))
			ut.Material = SMOOTH
		end
	end
	for _, c in ipairs(model:GetChildren()) do
		if c:IsA("Shirt") or c:IsA("Pants") or c:IsA("ShirtGraphic") or c:IsA("Accessory") then
			c:Destroy()
		end
	end
end

local function attireBuild(model, app, opts, gear)
	local folder = getFolder(model, "Attire")
	local a = app.attire or {}
	local shoeCond = gear and gear.shoesCond or 100
	local shoeColor = Looks.Color(a.shoes, Color3.fromRGB(25, 25, 25))
	if shoeCond < 60 then
		shoeColor = lerpColor(shoeColor, Color3.fromRGB(95, 85, 70), (60 - shoeCond) / 60 * 0.45)
	end
	local trunks = Looks.Color(a.trunks, Color3.fromRGB(200, 25, 30))
	local trim = Looks.Color(a.trim, Color3.new(1, 1, 1))
	local lt = part(model, "LowerTorso")
	if lt then
		local s = lt.Size
		local band = mk(folder, lt, "Waistband", V3(s.X * 1.1, s.Y * 0.55, s.Z * 1.18), lt.CFrame * CF(0, s.Y * 0.28, 0), trim, "Block", SMOOTH)
		local text = (opts and opts.waistText) or ""
		if text ~= "" then
			textPatch(folder, lt, "WaistText", V3(s.X * 0.8, s.Y * 0.45, 0.02), band.CFrame * CF(0, 0, -band.Size.Z / 2 - 0.012), text:upper(), contrast(trim))
		end
	end
	local white = Color3.fromRGB(240, 240, 240)
	local socks = Looks.Color(a.socks, Color3.new(1, 1, 1))
	local tallBoots = a.shoeStyle ~= "Low-Top"
	-- boxing boots: laces and soles pick up the trim colour (black boots, red laces, red soles)
	local laceColor = tallBoots and trim or white
	local soleColor = tallBoots and trim or Color3.fromRGB(235, 235, 235)
	if shoeCond < 40 then
		laceColor = lerpColor(laceColor, Color3.fromRGB(170, 160, 140), 0.5)
	end
	for _, side in ipairs({ "Left", "Right" }) do
		local ul, ll = part(model, side .. "UpperLeg"), part(model, side .. "LowerLeg")
		local sign = side == "Left" and -1 or 1
		if ul then
			-- loose trunks over the thigh, ending above the knee (long trunks reach the knee)
			local us = ul.Size
			local low = a.trunkStyle == "Long" and -0.5 or -0.2 -- trunk leg opening, in leg heights from the centre
			-- the shell tops out just above the bottom of the (trunk coloured) lower torso, well under the
			-- waistband: it turns with the thigh, and a high front edge would swing up over the band
			-- when the boxer bends at the hips
			local top = 0.5
			if lt then
				top = math.clamp(((lt.Position.Y - lt.Size.Y * 0.5) - ul.Position.Y) / us.Y + 0.03, low + 0.3, 0.5)
			end
			local h = top - low
			local cy = (top + low) / 2
			mk(folder, ul, "TrunkShell", V3(us.X * 1.12, us.Y * h, us.Z * 1.2), ul.CFrame * CF(0, us.Y * cy, -us.Z * 0.03), trunks, "Block", SMOOTH)
			local px = sign * (us.X * 0.56 + 0.02)
			local panelH = top - low - 0.12
			local panelY = low + 0.08 + panelH / 2
			if a.trunkStyle == "Striped" then
				mk(folder, ul, "Stripe", V3(0.05, us.Y * panelH, us.Z * 0.45), ul.CFrame * CF(px, us.Y * panelY, -us.Z * 0.03), trim, "Block", SMOOTH)
			elseif a.trunkStyle == "Pro" then
				-- pro trunks: trim hem at the leg opening and a trim side panel with white stripes
				mk(folder, ul, "Hem", V3(us.X * 1.14, us.Y * 0.1, us.Z * 1.22), ul.CFrame * CF(0, us.Y * (low + 0.05), -us.Z * 0.03), trim, "Block", SMOOTH)
				mk(folder, ul, "SidePanel", V3(0.05, us.Y * panelH, us.Z * 0.62), ul.CFrame * CF(px, us.Y * panelY, -us.Z * 0.03), trim, "Block", SMOOTH)
				for k = -1, 1 do
					mk(folder, ul, "SideStripe", V3(0.062, us.Y * (panelH - 0.02), us.Z * 0.085), ul.CFrame * CF(px + sign * 0.006, us.Y * panelY, -us.Z * 0.03 + k * us.Z * 0.19), white, "Block", SMOOTH)
				end
			end
		end
		if ll then
			local s = ll.Size
			if a.trunkStyle == "Long" then
				mk(folder, ll, "TrunkLeg", V3(s.X * 1.06, s.Y * 0.25, s.Z * 1.06), ll.CFrame * CF(0, s.Y * 0.38, 0), trunks, "Block", SMOOTH)
			end
			if not tallBoots then
				mk(folder, ll, "Sock", V3(s.X * 1.03, s.Y * 0.38, s.Z * 1.03), ll.CFrame * CF(0, -s.Y * 0.31, 0), socks, "Block", SMOOTH)
			else
				-- boxing boot: tall laced shaft to mid-calf with the sock showing above it
				local top = -0.02 -- shaft top, in leg heights from the leg centre (about half the shin, like a real boxing boot)
				local h = 0.5 + top
				local cy = -0.5 + h / 2
				mk(folder, ll, "BootShaft", V3(s.X * 1.1, s.Y * h, s.Z * 1.16), ll.CFrame * CF(0, s.Y * cy, s.Z * 0.02), shoeColor, "Block", Enum.Material.Leather)
				mk(folder, ll, "Sock", V3(s.X * 1.05, s.Y * 0.09, s.Z * 1.08), ll.CFrame * CF(0, s.Y * (top + 0.045), s.Z * 0.01), socks, "Block", SMOOTH)
				local fz = -s.Z * 0.56 - 0.012
				for _, ex in ipairs({ -1, 1 }) do
					mk(folder, ll, "Eyelets", V3(0.035, s.Y * (h - 0.14), 0.03), ll.CFrame * CF(ex * s.X * 0.15, s.Y * (cy + 0.03), fz - 0.004), Color3.fromRGB(210, 210, 216), "Block", Enum.Material.Metal)
				end
				local n = 4
				local span = s.Y * (h - 0.16)
				for k = 0, n - 1 do
					local y = -s.Y * 0.5 + s.Y * 0.1 + (k + 0.5) * span / n
					for _, rot in ipairs({ 1, -1 }) do
						mk(folder, ll, "Lace", V3(s.X * 0.33, 0.035, 0.03), ll.CFrame * CF(0, y, fz - 0.01) * ANG(0, 0, rot * math.rad(26)), laceColor, "Block", SMOOTH)
					end
				end
			end
		end
		local foot = part(model, side .. "Foot")
		if foot then
			local fs = foot.Size
			if tallBoots then
				mk(folder, foot, "Sole", V3(fs.X * 1.06, 0.15, fs.Z * 1.08), foot.CFrame * CF(0, -fs.Y * 0.5 + 0.035, 0), soleColor, "Block", Enum.Material.Rubber)
			else
				mk(folder, foot, "Sole", V3(fs.X * 1.04, 0.08, fs.Z * 1.06), foot.CFrame * CF(0, -fs.Y * 0.5, 0), soleColor, "Block")
			end
			mk(folder, foot, "Laces", V3(0.25, 0.04, fs.Z * 0.5), foot.CFrame * CF(0, fs.Y * 0.5, -fs.Z * 0.1), laceColor, "Block")
			if shoeCond < 40 then
				-- scuffed toes and a split sole
				mk(folder, foot, "Scuff", V3(fs.X * 0.7, fs.Y * 0.5, 0.05), foot.CFrame * CF(0, 0, -fs.Z * 0.5 - 0.01), Color3.fromRGB(120, 110, 95), "Ellipsoid", SMOOTH, 0.3)
				mk(folder, foot, "SoleSplit", V3(fs.X * 0.5, 0.05, 0.08), foot.CFrame * CF(0, -fs.Y * 0.45, -fs.Z * 0.35), Color3.fromRGB(30, 30, 30), "Block")
			end
		end
	end
end

------------------------------------------------------------------------
-- Gloves / wraps
------------------------------------------------------------------------
local function wearColor(c, cond)
	local t = math.clamp((80 - (cond or 100)) / 80, 0, 1)
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, s * (1 - 0.35 * t), v * (1 - 0.3 * t))
end

local function initials(name)
	local out = ""
	for w in tostring(name or ""):gmatch("%S+") do
		out ..= w:sub(1, 1):upper()
	end
	return out:sub(1, 3)
end

local function handsBuild(model, app, gear, opts)
	local folder = getFolder(model, "Hands")
	local mode = opts and opts.hands or "gloves"
	if mode == "bare" then
		return
	end
	gear = gear or {}
	local g = app.gloves or {}
	if mode == "wraps" then
		local wc = wearColor(Looks.Color(app.attire and app.attire.wraps, Color3.new(1, 1, 1)), gear.wrapsCond)
		if (gear.wrapsCond or 100) < 40 then
			wc = lerpColor(wc, Color3.fromRGB(150, 130, 100), 0.35) -- dirty wraps
		end
		for _, side in ipairs({ "Left", "Right" }) do
			local hand, la = part(model, side .. "Hand"), part(model, side .. "LowerArm")
			if hand then
				mk(folder, hand, "Wrap", hand.Size * V3(1.08, 1.4, 1.08), hand.CFrame, wc, "Block", SMOOTH)
			end
			if la then
				mk(folder, la, "WrapWrist", V3(la.Size.X * 1.06, la.Size.Y * 0.3, la.Size.Z * 1.06), la.CFrame * CF(0, -la.Size.Y * 0.36, 0), wc, "Block", SMOOTH)
			end
		end
		return
	end
	local gloveDef = Catalog.Find(Catalog.Gloves, gear.gloves or "Worn") or Catalog.Gloves[1]
	local custom = gloveDef.custom or {}
	local cond = gear.glovesCond or 100
	local main = wearColor(Looks.Color(g.color, Color3.fromRGB(200, 25, 30)), cond)
	-- a white band round the cuff (customisable on gloves that allow trim colours)
	local trim = custom.trim and Looks.Color(g.trim, Color3.new(1, 1, 1)) or wearColor(Color3.fromRGB(236, 234, 228), cond)
	local finish = custom.finish and (g.finish or "Leather") or "Leather"
	if finish == "Metallic" and not custom.metallic then
		finish = "Patent"
	end
	local material, refl = Enum.Material.Leather, 0
	if finish == "Matte" then
		material = SMOOTH
	elseif finish == "Patent" then
		material, refl = SMOOTH, 0.22
	elseif finish == "Metallic" then
		material, refl = Enum.Material.Foil, 0.35
	end
	if gloveDef.id == "WorldChampion" then
		trim = Color3.fromRGB(255, 200, 40)
	end
	local stitchColor = darken(main, 0.55)
	if custom.stitching then
		if g.stitching == "Contrast" then
			stitchColor = trim
		elseif g.stitching == "Gold" then
			stitchColor = Color3.fromRGB(255, 200, 40)
		end
	end
	local sizeK = (gloveDef.id == "Worn" or gloveDef.id == "Cheap") and 0.95 or 1.0
	for _, side in ipairs({ "Left", "Right" }) do
		local hand, la = part(model, side .. "Hand"), part(model, side .. "LowerArm")
		if hand then
			local sign = side == "Left" and -1 or 1
			local base = math.max(hand.Size.X, hand.Size.Z)
			local gsize = V3(base * 1.4, base * 1.55, base * 1.5) * sizeK
			local gcf = hand.CFrame * CF(0, -hand.Size.Y * 0.2, -0.05)
			local glove = mk(folder, hand, side == "Left" and "GloveL" or "GloveR", gsize, gcf, main, "Ellipsoid", material)
			glove.Reflectance = refl
			mk(folder, hand, "Thumb", gsize * V3(0.35, 0.45, 0.4), gcf * CF(-sign * gsize.X * 0.42, 0.05, -gsize.Z * 0.15), main, "Ellipsoid", material)
			-- stitching lines across the knuckles
			local lines = (custom.stitching and g.stitching == "Double") and 2 or 1
			for i = 1, lines do
				mk(folder, hand, "Stitch", V3(0.03, 0.03, gsize.Z * 0.72), gcf * CF(sign * gsize.X * 0.47, gsize.Y * (0.02 - i * 0.12), 0), stitchColor)
			end
			-- logo on the back of the glove
			if custom.logo and g.logo and g.logo ~= "None" then
				local glyph = Catalog.LogoGlyphs[g.logo]
				if g.logo == "Initials" then
					glyph = initials(opts and opts.name)
				elseif g.logo == "Flag" then
					glyph = tostring(opts and opts.nat or "USA"):sub(1, 3):upper()
				end
				if glyph then
					textPatch(folder, hand, "Logo", V3(0.02, gsize.Y * 0.42, gsize.Z * 0.55), gcf * CF(sign * (gsize.X * 0.5 + 0.012), gsize.Y * 0.12, 0), glyph, trim,
						sign > 0 and Enum.NormalId.Right or Enum.NormalId.Left)
				end
			end
			-- wear: scratches, cracks, sweat marks
			if cond < 70 then
				local rng = Random.new(sign * 13 + math.floor(cond))
				local n = cond < 45 and 4 or 2
				for i = 1, n do
					local crack = cond < 45 and i % 2 == 0
					mk(folder, hand, crack and "Crack" or "Scratch", V3(0.03, gsize.Y * rng:NextNumber(0.2, 0.4), 0.03),
						gcf * CF(sign * gsize.X * 0.49, rng:NextNumber(-0.2, 0.25) * gsize.Y, rng:NextNumber(-0.3, 0.3) * gsize.Z) * ANG(rng:NextNumber(-1, 1), 0, 0),
						crack and darken(main, 0.35) or lerpColor(main, Color3.new(1, 1, 1), 0.4))
				end
				if cond < 30 then
					mk(folder, hand, "SweatMark", gsize * V3(0.1, 0.45, 0.5), gcf * CF(sign * gsize.X * 0.44, -gsize.Y * 0.2, 0), darken(main, 0.7), "Ellipsoid", material, 0.4)
				end
			end
			if gloveDef.aura then
				local sp = Instance.new("Sparkles")
				sp.SparkleColor = Color3.fromRGB(255, 210, 60)
				sp.Parent = glove
			end
		end
		if la then
			local s = la.Size
			local cuffCF = la.CFrame * CF(0, -s.Y * 0.32, 0)
			mk(folder, la, "Cuff", V3(s.X * 1.12, s.Y * 0.45, s.Z * 1.12), cuffCF, main, "Block", material)
			mk(folder, la, "CuffTrim", V3(s.X * 1.15, s.Y * 0.13, s.Z * 1.15), cuffCF * CF(0, s.Y * 0.07, 0), trim, "Block", material)
			if custom.embroidery then
				local sign = side == "Left" and -1 or 1
				local text = side == "Left" and (g.embName and opts and opts.name or "") or (g.embNick and opts and opts.nick or "")
				if text ~= "" then
					textPatch(folder, la, "Embroidery", V3(0.02, s.Y * 0.3, s.Z * 1.05), cuffCF * CF(sign * (s.X * 0.57 + 0.012), 0, 0), text:upper(), trim,
						sign > 0 and Enum.NormalId.Right or Enum.NormalId.Left)
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Robe (toggled during walkouts)
------------------------------------------------------------------------
function Body.SetRobe(model, app, on, opts)
	local folder = getFolder(model, "Robe")
	if not on then
		return
	end
	local a = app.attire or {}
	local robeId = opts and opts.robe or "Classic"
	if robeId == "None" then
		return
	end
	local color = Looks.Color(a.robe, Color3.fromRGB(200, 25, 30))
	local trim = robeId == "Champion" and Color3.fromRGB(255, 200, 40) or Looks.Color(a.robeTrim, Color3.new(1, 1, 1))
	local mat = Enum.Material.Fabric
	local ut, lt = part(model, "UpperTorso"), part(model, "LowerTorso")
	if ut then
		local s = ut.Size
		local shell = mk(folder, ut, "RobeTorso", s * V3(1.16, 1.06, 1.25), ut.CFrame, color, "Block", mat)
		mk(folder, ut, "Lapel", V3(0.25, s.Y * 1.05, 0.05), ut.CFrame * CF(-0.15, 0, -s.Z * 0.63) * ANG(0, 0, math.rad(12)), trim, "Block", mat)
		mk(folder, ut, "Lapel", V3(0.25, s.Y * 1.05, 0.05), ut.CFrame * CF(0.15, 0, -s.Z * 0.63) * ANG(0, 0, math.rad(-12)), trim, "Block", mat)
		local nick = opts and opts.nick or ""
		if nick ~= "" then
			textPatch(folder, ut, "RobeName", V3(s.X * 1.0, s.Y * 0.35, 0.02), shell.CFrame * CF(0, s.Y * 0.15, s.Z * 0.63 + 0.012), nick:upper(), trim, Enum.NormalId.Back)
		end
		if robeId == "Hooded" or robeId == "Champion" then
			mk(folder, ut, "Hood", V3(s.X * 0.75, s.Y * 0.55, s.Z * 0.8), ut.CFrame * CF(0, s.Y * 0.55, s.Z * 0.45), color, "Ellipsoid", mat)
		end
	end
	if lt then
		local s = lt.Size
		mk(folder, lt, "RobeSkirt", V3(s.X * 1.25, 2.2, s.Z * 1.35), lt.CFrame * CF(0, -1.0, 0), color, "Block", mat)
		mk(folder, lt, "RobeBelt", V3(s.X * 1.28, 0.22, s.Z * 1.38), lt.CFrame * CF(0, 0.1, 0), trim, "Block", mat)
	end
	for _, side in ipairs({ "Left", "Right" }) do
		local ua, la = part(model, side .. "UpperArm"), part(model, side .. "LowerArm")
		if ua then
			mk(folder, ua, "Sleeve", ua.Size * V3(1.2, 1.02, 1.2), ua.CFrame, color, "Block", mat)
		end
		if la then
			mk(folder, la, "SleeveLow", la.Size * V3(1.22, 0.7, 1.22), la.CFrame * CF(0, la.Size.Y * 0.12, 0), color, "Block", mat)
			mk(folder, la, "SleeveTrim", V3(la.Size.X * 1.25, 0.1, la.Size.Z * 1.25), la.CFrame * CF(0, -la.Size.Y * 0.22, 0), trim, "Block", mat)
		end
	end
end

------------------------------------------------------------------------
-- Build steps (called by Builder.Cosmetics) and helpers shared with Builder
------------------------------------------------------------------------
Body.Colors = colorBody -- (model, app, gear)
Body.Muscles = musclesBuild -- (model, app, build)
Body.Attire = attireBuild -- (model, app, opts, gear)
Body.Hands = handsBuild -- (model, app, gear, opts)
Body.frameOf = frameOf -- (app)
Body.avgDev = avgDev -- (build, keys)

return Body
