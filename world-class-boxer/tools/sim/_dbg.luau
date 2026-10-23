--!nocheck
local FS = require("./fightsim")
local S = FS.new()
local Config, Random = S.Config, S.H.globals.Random
local function data(h) local d = S.Boxer({ style = "BoxerPuncher", level = 60 }, Random.new(5)); d.height, d.reach = h, h; return d end
local f = S.NewFight(data(60), data(84), 3, 11)
f.sp = { base = 4.3, min = 3.4, minSep = 3.25, inside = 3.65, clinch = 4.8, pivot = 3.9, cover = 5.8 }
local G, OG = f:Geo(f.P), f:Geo(f.O)
print("P stand", G.stand, G.source, "O stand", OG.stand, OG.source, "P data.height", f.P.data.height, "app", f.P.data.app and f.P.data.app.height)
local t = f:HitTest(f.P, f.O, "jab", false, 4.4)
print("P>O jab 4.4", t.ok, t.zone, t.why, t.redirected, t.dy)
local HG = S.H.require("HitGeometry")
local t2 = HG.Test(G, OG, "jab", false, 4.4, { floor = 3.4, bend = 0 })
print("direct", t2.ok, t2.zone, t2.why, t2.redirected, t2.dy, "bend", f:Bend(f.O))
