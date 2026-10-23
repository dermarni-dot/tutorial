-- BodyMapData: the Body tab's muscle map as one uploaded image sheet (tools/ui/out/bodymap.png). GENERATED
-- by tools/ui/build_bodymap.py - do not edit by hand. views[view] = the silhouette's rect on the sheet; masks[view]
-- = one entry per muscle belly: its rect on the sheet and its box in the view (fractions bx, by, bw, bh). The
-- glyphs are white (shaded) on transparent: tint with ImageColor3. id 0 = not uploaded: BodyMap draws frames.
local BodyMapData = {}
BodyMapData.id = 125837725133152
BodyMapData.size = Vector2.new(1024, 1024)
BodyMapData.view = { w = 300, h = 340 }
BodyMapData.views = {
	front = { x = 2, y = 2, w = 300, h = 340 },
	back = { x = 304, y = 2, w = 300, h = 340 },
}
BodyMapData.masks = {
	front = {
		{ id = "neckSCM", x = 606, y = 2, w = 14, h = 16, bx = 0.4367, by = 0.1265, bw = 0.0467, bh = 0.0471 },
		{ id = "neckSCM", x = 622, y = 2, w = 14, h = 16, bx = 0.5167, by = 0.1265, bw = 0.0467, bh = 0.0471 },
		{ id = "traps", x = 638, y = 2, w = 39, h = 15, bx = 0.3200, by = 0.1500, bw = 0.1300, bh = 0.0441 },
		{ id = "traps", x = 679, y = 2, w = 39, h = 15, bx = 0.5500, by = 0.1500, bw = 0.1300, bh = 0.0441 },
		{ id = "frontDelt", x = 720, y = 2, w = 31, h = 27, bx = 0.2333, by = 0.1647, bw = 0.1033, bh = 0.0794 },
		{ id = "frontDelt", x = 753, y = 2, w = 31, h = 27, bx = 0.6633, by = 0.1647, bw = 0.1033, bh = 0.0794 },
		{ id = "sideDelt", x = 786, y = 2, w = 21, h = 28, bx = 0.1800, by = 0.1735, bw = 0.0700, bh = 0.0824 },
		{ id = "sideDelt", x = 809, y = 2, w = 21, h = 28, bx = 0.7500, by = 0.1735, bw = 0.0700, bh = 0.0824 },
		{ id = "upperChest", x = 832, y = 2, w = 46, h = 14, bx = 0.3433, by = 0.1824, bw = 0.1533, bh = 0.0412 },
		{ id = "upperChest", x = 880, y = 2, w = 46, h = 14, bx = 0.5033, by = 0.1824, bw = 0.1533, bh = 0.0412 },
		{ id = "pecs", x = 928, y = 2, w = 48, h = 22, bx = 0.3400, by = 0.2147, bw = 0.1600, bh = 0.0647 },
		{ id = "pecs", x = 2, y = 344, w = 48, h = 22, bx = 0.5000, by = 0.2147, bw = 0.1600, bh = 0.0647 },
		{ id = "serratus", x = 52, y = 344, w = 14, h = 22, bx = 0.3167, by = 0.2676, bw = 0.0467, bh = 0.0647 },
		{ id = "serratus", x = 68, y = 344, w = 14, h = 22, bx = 0.6367, by = 0.2676, bw = 0.0467, bh = 0.0647 },
		{ id = "biceps", x = 84, y = 344, w = 25, h = 35, bx = 0.1900, by = 0.2382, bw = 0.0833, bh = 0.1029 },
		{ id = "biceps", x = 111, y = 344, w = 25, h = 35, bx = 0.7267, by = 0.2382, bw = 0.0833, bh = 0.1029 },
		{ id = "forearms", x = 138, y = 344, w = 23, h = 42, bx = 0.1600, by = 0.3441, bw = 0.0767, bh = 0.1235 },
		{ id = "forearms", x = 163, y = 344, w = 23, h = 42, bx = 0.7633, by = 0.3441, bw = 0.0767, bh = 0.1235 },
		{ id = "abs", x = 188, y = 344, w = 19, h = 11, bx = 0.4333, by = 0.2824, bw = 0.0633, bh = 0.0324 },
		{ id = "abs", x = 209, y = 344, w = 19, h = 11, bx = 0.5033, by = 0.2824, bw = 0.0633, bh = 0.0324 },
		{ id = "abs", x = 230, y = 344, w = 19, h = 11, bx = 0.4333, by = 0.3176, bw = 0.0633, bh = 0.0324 },
		{ id = "abs", x = 251, y = 344, w = 19, h = 11, bx = 0.5033, by = 0.3176, bw = 0.0633, bh = 0.0324 },
		{ id = "abs", x = 272, y = 344, w = 19, h = 11, bx = 0.4333, by = 0.3529, bw = 0.0633, bh = 0.0324 },
		{ id = "abs", x = 293, y = 344, w = 19, h = 11, bx = 0.5033, by = 0.3529, bw = 0.0633, bh = 0.0324 },
		{ id = "obliques", x = 314, y = 344, w = 16, h = 35, bx = 0.3633, by = 0.3088, bw = 0.0533, bh = 0.1029 },
		{ id = "obliques", x = 332, y = 344, w = 16, h = 35, bx = 0.5833, by = 0.3088, bw = 0.0533, bh = 0.1029 },
		{ id = "lowerAbs", x = 350, y = 344, w = 34, h = 18, bx = 0.4433, by = 0.3941, bw = 0.1133, bh = 0.0529 },
		{ id = "quads", x = 386, y = 344, w = 44, h = 68, bx = 0.3367, by = 0.5000, bw = 0.1467, bh = 0.2000 },
		{ id = "quads", x = 432, y = 344, w = 44, h = 68, bx = 0.5167, by = 0.5000, bw = 0.1467, bh = 0.2000 },
		{ id = "calves", x = 478, y = 344, w = 21, h = 45, bx = 0.3600, by = 0.7529, bw = 0.0700, bh = 0.1324 },
		{ id = "calves", x = 501, y = 344, w = 21, h = 45, bx = 0.5700, by = 0.7529, bw = 0.0700, bh = 0.1324 },
	},
	back = {
		{ id = "traps", x = 524, y = 344, w = 90, h = 21, bx = 0.3500, by = 0.1500, bw = 0.3000, bh = 0.0618 },
		{ id = "traps", x = 616, y = 344, w = 30, h = 24, bx = 0.4500, by = 0.2000, bw = 0.1000, bh = 0.0706 },
		{ id = "rearDelt", x = 648, y = 344, w = 30, h = 25, bx = 0.2000, by = 0.1706, bw = 0.1000, bh = 0.0735 },
		{ id = "rearDelt", x = 680, y = 344, w = 30, h = 25, bx = 0.7000, by = 0.1706, bw = 0.1000, bh = 0.0735 },
		{ id = "upperBack", x = 712, y = 344, w = 36, h = 17, bx = 0.3400, by = 0.2147, bw = 0.1200, bh = 0.0500 },
		{ id = "upperBack", x = 750, y = 344, w = 36, h = 17, bx = 0.5400, by = 0.2147, bw = 0.1200, bh = 0.0500 },
		{ id = "lats", x = 788, y = 344, w = 41, h = 52, bx = 0.3067, by = 0.2294, bw = 0.1367, bh = 0.1529 },
		{ id = "lats", x = 831, y = 344, w = 41, h = 52, bx = 0.5567, by = 0.2294, bw = 0.1367, bh = 0.1529 },
		{ id = "lowerBack", x = 874, y = 344, w = 15, h = 34, bx = 0.4400, by = 0.3500, bw = 0.0500, bh = 0.1000 },
		{ id = "lowerBack", x = 891, y = 344, w = 15, h = 34, bx = 0.5100, by = 0.3500, bw = 0.0500, bh = 0.1000 },
		{ id = "triceps", x = 908, y = 344, w = 25, h = 35, bx = 0.1900, by = 0.2382, bw = 0.0833, bh = 0.1029 },
		{ id = "triceps", x = 935, y = 344, w = 25, h = 35, bx = 0.7267, by = 0.2382, bw = 0.0833, bh = 0.1029 },
		{ id = "forearms", x = 962, y = 344, w = 23, h = 42, bx = 0.1600, by = 0.3441, bw = 0.0767, bh = 0.1235 },
		{ id = "forearms", x = 987, y = 344, w = 23, h = 42, bx = 0.7633, by = 0.3441, bw = 0.0767, bh = 0.1235 },
		{ id = "glutes", x = 2, y = 414, w = 42, h = 30, bx = 0.3600, by = 0.4559, bw = 0.1400, bh = 0.0882 },
		{ id = "glutes", x = 46, y = 414, w = 42, h = 30, bx = 0.5000, by = 0.4559, bw = 0.1400, bh = 0.0882 },
		{ id = "hamstrings", x = 90, y = 414, w = 40, h = 59, bx = 0.3433, by = 0.5382, bw = 0.1333, bh = 0.1735 },
		{ id = "hamstrings", x = 132, y = 414, w = 40, h = 59, bx = 0.5233, by = 0.5382, bw = 0.1333, bh = 0.1735 },
		{ id = "calves", x = 174, y = 414, w = 31, h = 48, bx = 0.3567, by = 0.7441, bw = 0.1033, bh = 0.1412 },
		{ id = "calves", x = 207, y = 414, w = 31, h = 48, bx = 0.5400, by = 0.7441, bw = 0.1033, bh = 0.1412 },
	},
}
return BodyMapData
