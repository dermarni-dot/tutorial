"""Afro family hair cards: "Afro" (Kinky / Coiled, and the Straight / Wavy afro the generated hair treats
as Kinky), its Curly variant, and the "High Top". Modelled in Blender (bpy 4.2), exported with hairlib.

    /opt/bpyenv/bin/python tools/hair/build_afro.py [--render DIR] [--only afro,afro_curly,hightop]
                                                    [--no-tex] [--samples N]

Writes tools/hair/textures/hair_coily.png (afro_tex.py), tools/hair/out/<key>/ (meshes + style.json),
tools/hair/blend/<key>.blend; with --render, Cycles self-check renders and a sheet per style.

How the hair is built (game nominal head space, numerically; see CONTRACT.md):
* The style's outer envelope is a height field over the default skull's scalp directions (a ray-cast
  egg / column + a few broad lobes), tapered to the scalp over a soft band inside the natural hairline
  (rounded, so the mass tucks down into the hairline at the forehead, temples and nape instead of
  ending in a brim).
* Each nested card layer is a real Blender mesh (a polar grid over the scalp at that layer's height) with
  modifiers: Displace by a Voronoi texture (the curl clusters: cauliflower lumps), Displace by Clouds (small
  lumps), both weighted by a vertex group that fades them out at the hairline, then Smooth. The evaluated
  layers are BVH trees; every card point is ray-cast onto its layer from the skull centre, so the cards lie
  on the lumpy layer, and the layer's displacement (valley / dome) bakes into the vertex occlusion.
* Cards: inner layers are large, nearly opaque clumps (scalp side first, so in-piece draw order is inside
  out), outer layers smaller and two-sided with lifted tips, then small crossed puffs that break up the
  silhouette, and a ring of short growing-out cards along the hairline (unscaled by the volume slider).
* Clearance: every vertex is ray-cast against the game's own head mesh (ref/head_m.obj) and kept at least
  CLEAR above it; ears are kept clear of their boxes; the female fit is checked against head_f.obj.
"""
import argparse
import json
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

import afro_tex  # noqa: E402
import hairlib as hl  # noqa: E402

TEX_DIR = os.path.join(HERE, "textures")
BLEND_DIR = os.path.join(HERE, "blend")
REF = hl.REF
CLEAR = 0.024  # minimum radial height of any vertex above the head mesh / skull table (nominal studs)
CLEAR_N = 0.0215  # minimum distance of any vertex from the head surface (male, and female through the fit)
EAR_CLEAR = 0.022
TIGHT = hl.ATLAS["coily"]["tight"]
LOOSE = hl.ATLAS["coily"]["loose"]
TAU = 2 * math.pi

SK = hl.Skull()
C = SK.c.copy()
SKD = SK.data


def smooth(e0, e1, x):
    t = np.clip((np.asarray(x, dtype=np.float64) - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def unit(v):
    v = np.asarray(v, dtype=np.float64)
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-12)


# ------------------------------------------------------------------------------------------- reference
def load_head(path):
    """the game's Head mesh (and ears) from ref/head_*.obj -> (verts, tris) in nominal space"""
    P, F, cur = [], [], None
    for line in open(path):
        if line.startswith("v "):
            P.append([float(x) for x in line.split()[1:4]])
        elif line.startswith("o "):
            cur = line.split(None, 1)[1].strip()
        elif line.startswith("f ") and cur == "Head":
            ids = [int(t.split("/")[0]) - 1 for t in line.split()[1:]]
            for k in range(1, len(ids) - 1):
                F.append((ids[0], ids[k], ids[k + 1]))
    return P, F


class Head:
    def __init__(self, path):
        P, F = load_head(path)
        self.P = np.asarray(P)
        self.bvh = BVHTree.FromPolygons([tuple(p) for p in P], F)

    def radius(self, d, origin=None):
        """distance from the skull centre to the head surface along d (the outermost hit: the ray leaves
        the skull once, but an ear or the jaw could be hit first going outward from inside)"""
        o = Vector(tuple(C if origin is None else origin))
        dv = Vector(tuple(d))
        far = o + dv * 2.0
        loc, _n, _i, dist = self.bvh.ray_cast(far, -dv, 2.0)  # from outside, inward: the outer surface
        if loc is None:
            return None
        return 2.0 - dist

    def nearest(self, p):
        loc, _n, _i, dist = self.bvh.find_nearest(Vector(tuple(p)))
        return dist


EARS = [(np.array(SKD["ears"][s]["min"]) - EAR_CLEAR, np.array(SKD["ears"][s]["max"]) + EAR_CLEAR)
        for s in ("left", "right")]


def in_ear(p):
    """points inside either ear's box (grown by EAR_CLEAR)"""
    p = np.atleast_2d(p)
    hits = np.zeros(len(p), bool)
    for lo, hi in EARS:
        hits |= np.all((p > lo) & (p < hi), axis=-1)
    return hits


# ------------------------------------------------------------------------------------------- hairline
def _hairline_points(kind="Natural"):
    ln = SKD["hairline"]["lines"][kind]
    pts = []
    for side in ("right", "left"):
        for e in ln[side]:
            if e and e is not False and len(e) >= 4:
                pts.append(e[1:4])
    hgt = np.array([e for e in ln["height"] if e], dtype=np.float64)
    return np.array(pts, dtype=np.float64), hgt


HL_PTS, HL_H = _hairline_points()


def da_of(p):
    p = np.atleast_2d(p)
    return np.arctan2(np.abs(p[:, 0]), 0.05 - p[:, 2])


def scalp_of(p):
    """radial projection of points onto the default scalp -> (scalp points, dirs)"""
    p = np.atleast_2d(np.asarray(p, dtype=np.float64))
    d = unit(p - C)
    r = np.array([SK.radius(*SK.angles(di)) for di in d])
    return C + d * r[:, None], d


def edge_dist(p, line_pts=None, line_h=None, extra=None):
    """signed distance (studs) from the scalp point under p to the natural hairline: + inside the hair"""
    line_pts = HL_PTS if line_pts is None else line_pts
    line_h = HL_H if line_h is None else line_h
    s, _d = scalp_of(p)
    dd = np.sqrt(((s[:, None, :] - line_pts[None, :, :]) ** 2).sum(-1)).min(1)
    inside = s[:, 1] - np.interp(da_of(s), line_h[:, 0], line_h[:, 1])
    sd = np.where(inside >= 0, dd, -dd)
    if extra is not None:
        sd = np.minimum(sd, extra(s))
    return sd


# ------------------------------------------------------------------------------------------- directions
def fib_dirs(n, seed, jitter=0.5):
    """n near-uniform directions (Fibonacci sphere, jittered, deterministic)"""
    rng = np.random.default_rng(seed)
    i = np.arange(n) + 0.5
    y = 1 - 2 * i / n
    r = np.sqrt(1 - y * y)
    phi = i * math.pi * (3 - math.sqrt(5))
    d = np.stack([r * np.cos(phi), y, r * np.sin(phi)], 1)
    d = d + rng.normal(0, jitter * math.sqrt(4 * math.pi / n) * 0.5, d.shape)
    return unit(d)


def dir_th_az(th, az):
    s = np.sin(th)
    return np.stack([s * np.sin(az), np.cos(th), s * np.cos(az)], -1)


# ------------------------------------------------------------------------------------------- envelopes
def lobes_fn(seed, n, amp, width):
    rng = np.random.default_rng(seed)
    D = unit(rng.normal(0, 1, (n, 3)) * [1, 0.7, 1] + [0, 0.5, 0])
    A = amp * rng.uniform(-0.6, 1.0, n)
    W = width * rng.uniform(0.7, 1.3, n)

    def f(d):
        d = np.atleast_2d(d)
        return (A[None] * np.exp(-(1 - d @ D.T) / W[None])).sum(1)
    return f


class Style:
    """one style entry's envelope, layers and card plan"""
    key = ""

    def outer(self, d):  # full (untapered) outer height above the scalp along d
        raise NotImplementedError

    def band(self, da):  # the taper band's width (studs) inside the hairline
        return np.interp(da, [0, 0.6, 1.2, 2.1, math.pi], self.bands)

    def region(self, p):  # signed distance inside the area this style grows on
        return edge_dist(p)

    def heights(self, d):
        """(h_out tapered, taper weight 0..1, edge distance) for directions d"""
        d = np.atleast_2d(d)
        r = np.array([SK.radius(*SK.angles(di)) for di in d])
        s = C + d * r[:, None]
        e = self.region(s)
        x = np.clip(e / self.band(da_of(s)), 0, 1)
        S = 1 - (1 - x) ** self.tuck_pow
        full = self.outer(d)
        h = self.h_root + (full - self.h_root) * S
        h = np.where(e < 0, self.h_root, h)
        return h, S, e


def ray_ellipsoid(o, d, E0, R):
    o = (o - E0) / R
    dd = d / R
    a = (dd * dd).sum(-1)
    b = 2 * (o * dd).sum(-1)
    c = (o * o).sum(-1) - 1
    disc = np.maximum(b * b - 4 * a * c, 0)
    return (-b + np.sqrt(disc)) / (2 * a)


class Afro(Style):
    def __init__(self, key="afro", curly=False):
        self.key = key
        self.curly = curly
        k = 0.93 if curly else 1.0
        self.E0 = np.array([0.0, 0.145, 0.1])
        self.R = np.array([0.67, 0.685, 0.675]) * k
        self.h_root = 0.032
        self.bands = [0.17, 0.17, 0.21, 0.23, 0.26]
        self.tuck_pow = 1.7
        self.lobes = lobes_fn(401 + (7 if curly else 0), 12, 0.06, 0.045)
        self.vor_amp = 0.07 if not curly else 0.06
        self.vor_size = 0.15 if not curly else 0.12

    def outer(self, d):
        d = np.atleast_2d(d)
        r = np.array([SK.radius(*SK.angles(di)) for di in d])
        o = np.repeat(C[None], len(d), 0)
        R = np.repeat(self.R[None], len(d), 0)
        t = ray_ellipsoid(o, d, self.E0, R)
        for _ in range(2):  # egg: fullest above the ears, narrower toward the bottom of the mass
            y = C[1] + d[:, 1] * t
            nk = 1 - 0.1 * smooth(self.E0[1] + 0.1, self.E0[1] - 0.45, y)
            R = np.stack([self.R[0] * nk, self.R[1] * np.ones_like(nk), self.R[2] * nk], 1)
            t = ray_ellipsoid(o, d, self.E0, R)
        h = t - r + self.lobes(d)
        return np.maximum(h, 0.07)


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def _topline(kind="high"):
    tl = SKD["fades"]["topLines"][kind]
    pts = []
    for side in ("right", "left"):
        for e in tl.get(side) or []:
            if e and len(e) >= 4:
                pts.append(e)
    pts = np.array(pts, dtype=np.float64)
    order = np.argsort(pts[:, 0])
    return pts[order]


class HighTop(Style):
    """the high top: a tall column of coils over a high fade (the cap paints the fade: cut "style"). Its
    section a superellipse (rounded, not a box), a little wider toward the soft-domed top, the front face
    leaning back, its foot rising from the fade's top line at the sides and back and from the line-up at the
    front. (After AnatomyHair R["High Top"].)"""

    def __init__(self, key="hightop"):
        self.key = key
        self.yb, self.yTop = 0.18, 0.86
        self.h_root = 0.03
        self.bands = [0.05, 0.06, 0.09, 0.1, 0.1]
        self.tuck_pow = 1.25
        self.lobes = lobes_fn(77, 10, 0.012, 0.035)
        self.vor_amp = 0.035
        self.vor_size = 0.13
        self.top = _topline("high")
        self.fade_top = SKD["fades"]["FADE_TOP"]["high"]
        self.names = {"mass": {"front": "HairTop01", "right": "HairTop02", "left": "HairTop03", "back": "HairTop04",
                               "top": "HairTop05"},
                      "clumps": CLUMPS, "edge": "HairTopEdge"}

    def sdf(self, P):
        P = np.atleast_2d(P)
        x, y, z = P[:, 0], P[:, 1], P[:, 2]
        k = np.clip((y - self.yb) / (self.yTop - self.yb), 0, 1)
        hx = 0.44 + 0.03 * k
        lean = 0.07 * (y - self.yb)
        hz = 0.5 - lean
        cz = 0.04 + lean
        ax, az = np.abs(x) / hx, np.abs(z - cz) / hz
        r = (ax ** 2.6 + az ** 2.6) ** (1 / 2.6)
        d_side = (r - 1) * np.minimum(hx, hz)
        d_top = y - (self.yTop + 0.04 * (1 - np.minimum(1, r * r)))
        return smax(d_side, d_top, 0.1)

    def normal_hint(self, p):
        e = 0.01
        g = np.array([(self.sdf(p + dv)[0] - self.sdf(p - dv)[0]) for dv in np.eye(3) * e])
        return unit(g)

    def outer(self, d):
        d = np.atleast_2d(d)
        r = np.array([SK.radius(*SK.angles(di)) for di in d])
        ts = np.arange(0.0, 0.75, 0.004)
        out = np.empty(len(d))
        for i, di in enumerate(d):
            P = C + di[None] * (r[i] + ts)[:, None]
            s = self.sdf(P)
            j = np.argmax(s > 0) if (s > 0).any() else len(ts) - 1
            out[i] = ts[j]
        return np.maximum(out + self.lobes(d), 0.05)

    def region(self, p):
        s, _ = scalp_of(p)
        e_front = edge_dist(s)
        da = da_of(s)
        yl = np.interp(da, self.top[:, 0], self.top[:, 2], left=np.nan, right=self.top[-1, 2])
        e_top = np.where(np.isnan(yl), 9.0, s[:, 1] - np.nan_to_num(yl, nan=0.0))
        return np.minimum(e_front, e_top)

    def cap_region(self, p):  # preview stand-in only: the high fade's coverage, roughly (full above the top line)
        s, _ = scalp_of(p)
        e = edge_dist(s)
        da = da_of(s)
        yl = np.interp(da, self.top[:, 0], self.top[:, 2], left=np.nan, right=self.top[-1, 2])
        fade = np.where(np.isnan(yl), 9.0, (s[:, 1] - np.nan_to_num(yl, nan=0.0)) + 0.06)
        return np.minimum(e, fade)


# ------------------------------------------------------------------------------------------- Blender layers
def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_layer(style, f, name, coll, n_th=96, n_az=160, th_max=math.radians(168)):
    """a Blender mesh over the scalp at fraction f of the style's height (f = None: h_root + 0.008),
    with Displace (Voronoi clusters, Clouds lumps) weighted by the taper, then Smooth. Returns the object."""
    th = np.linspace(0.0, th_max, n_th)
    az = np.linspace(0, TAU, n_az, endpoint=False)
    TH, AZ = np.meshgrid(th, az, indexing="ij")
    D = dir_th_az(TH.ravel(), AZ.ravel())
    if not hasattr(style, "_grid") or style._grid[0] != (n_th, n_az):
        h, S, e = style.heights(D)
        style._grid = ((n_th, n_az), h, S, e)
    _, h, S, e = style._grid
    r = np.array([SK.radius(*SK.angles(di)) for di in D])
    if f is None:
        hh = style.h_root + 0.006
    else:  # f > 1: the frizz shells just outside the outer layer (converging with it at the hairline)
        hh = style.h_root + min(f, 1.0) * (h - style.h_root) + max(0.0, f - 1.0) * 0.1 * S
    P = C + D * (r + hh)[:, None]
    faces = []
    for i in range(n_th - 1):
        for j in range(n_az):
            a = i * n_az + j
            b = i * n_az + (j + 1) % n_az
            c = (i + 1) * n_az + (j + 1) % n_az
            dd = (i + 1) * n_az + j
            faces.append((a, dd, c, b))  # outward
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(p) for p in P], [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    vg = ob.vertex_groups.new(name="mass")
    w = np.clip(S, 0, 1) * (0 if f is None else 1)
    for i, wi in enumerate(w):
        if wi > 1e-3:
            vg.add([i], float(wi), "REPLACE")
    if f is not None and f > 0:
        tv = bpy.data.textures.get("afro_clusters") or bpy.data.textures.new("afro_clusters", "VORONOI")
        tv.distance_metric = "DISTANCE"
        tv.color_mode = "INTENSITY"
        tv.noise_scale = style.vor_size
        tv.noise_intensity = 1.0
        tc = bpy.data.textures.get("afro_lumps") or bpy.data.textures.new("afro_lumps", "CLOUDS")
        tc.noise_scale = 0.045
        tc.noise_depth = 2
        m1 = ob.modifiers.new("clusters", "DISPLACE")
        m1.texture = tv
        m1.texture_coords = "GLOBAL"
        m1.direction = "NORMAL"
        m1.mid_level = 0.35
        m1.strength = -style.vor_amp * (0.35 + 0.65 * f)  # domes at the cell centres, valleys between
        m1.vertex_group = "mass"
        m2 = ob.modifiers.new("lumps", "DISPLACE")
        m2.texture = tc
        m2.texture_coords = "GLOBAL"
        m2.direction = "NORMAL"
        m2.mid_level = 0.5
        m2.strength = 0.022 * f
        m2.vertex_group = "mass"
        m3 = ob.modifiers.new("soften", "SMOOTH")
        m3.factor = 0.6
        m3.iterations = 3
    for p in me.polygons:
        p.use_smooth = True
    return ob


class Layer:
    """an evaluated layer: ray casts from the skull centre give (point, normal, displacement)"""

    def __init__(self, style, ob, f):
        self.ob = ob
        self.f = f
        dg = bpy.context.evaluated_depsgraph_get()
        self.bvh = BVHTree.FromObject(ob, dg)
        self.style = style

    def hit(self, d):
        dv = Vector(tuple(d))
        o = Vector(tuple(C))
        loc, n, _i, dist = self.bvh.ray_cast(o + dv * 1.6, -dv, 1.6)
        if loc is None:
            return None
        return np.array(loc), np.array(n)

    def point_normal(self, d, eps=0.012):
        """the layer point along d and a smooth normal (central differences of neighbouring hits)"""
        h0 = self.hit(d)
        if h0 is None:
            return None, None
        p0 = h0[0]
        t1 = unit(np.cross(d, [0, 1, 0]) if abs(d[1]) < 0.95 else np.cross(d, [1, 0, 0]))
        t2 = np.cross(d, t1)
        ps = []
        for t in (t1, -t1, t2, -t2):
            h = self.hit(unit(d + t * eps))
            ps.append(h[0] if h is not None else p0)
        n = unit(np.cross(ps[0] - ps[1], ps[2] - ps[3]))
        if np.dot(n, d) < 0:
            n = -n
        # shading: mostly the smooth envelope's direction (one soft volume), a little of the lumps
        e = self.style.normal_hint(p0) if hasattr(self.style, "normal_hint") else (
            unit(p0 - self.style.E0) if hasattr(self.style, "E0") else d)
        n = unit(0.85 * e + 0.15 * n)
        return p0, n


# ------------------------------------------------------------------------------------------- cards
def tangent_down(d):
    """the scalp's 'away from the crown' direction at d (theta increasing), in the tangent plane"""
    th, az = SK.angles(d)
    th = max(th, 0.05)
    e = np.array([math.cos(th) * math.sin(az), -math.sin(th), math.cos(th) * math.cos(az)])
    return unit(e)


def add_card(piece, pts, widths, ups, strip, shade=None, double=True, normals=None, twist=None):
    """hairlib.Piece.card with the game's winding: a one-sided card's triangles are counter-clockwise seen
    from its outer side (MeshKit's convention: the right-hand normal points out, along up / the shading
    normal). hairlib's card() emits its 'front' triangles the other way round (their right-hand normal is
    -up), so the one-sided triangles are flipped here; two-sided cards are unaffected."""
    n0 = len(piece.T)
    piece.card(pts, widths, ups, strip, shade=shade, double=double, normals=normals, twist=twist)
    if not double:
        piece.T[n0:] = [(a, c, b) for (a, b, c) in piece.T[n0:]]


def rotate(v, axis, a):
    axis = unit(axis)
    return v * math.cos(a) + np.cross(axis, v) * math.sin(a) + axis * np.dot(axis, v) * (1 - math.cos(a))


class Builder:
    def __init__(self, style, head):
        self.style = style
        self.head = head
        self.rng = np.random.default_rng(sum(map(ord, style.key)))
        self.stats = {"dropped": 0, "pushed": 0}

    def clear_push(self, p):
        """keep a point CLEAR above the head mesh (radially from the skull centre)"""
        d = unit(p - C)
        rh = self.head.radius(d)
        if rh is None:
            return p
        r = float(np.linalg.norm(p - C))
        if r < rh + CLEAR:
            self.stats["pushed"] += 1
            return C + d * (rh + CLEAR)
        return p

    def lay_card(self, layer, d0, rot, length, width, rows, lift, strip, ao, double, root_at=0.4,
                 min_edge=0.0, side_curl=0.0):
        """a card lying on the layer: centred on the ray d0, its axis rot radians from 'down', root at
        -root_at * length, tip at (1 - root_at) * length, tip lifted off the layer by lift * length.
        Returns (pts, widths, normals, shades) or None if it leaves the hair area / hits an ear."""
        p0, n0 = layer.point_normal(d0)
        if p0 is None:
            return None
        a = rotate(tangent_down(d0), n0, rot)
        a = unit(a - n0 * np.dot(a, n0))
        pts, nrm = [], []
        for i in range(rows + 1):
            t = i / rows
            q = p0 + a * (t - root_at) * length
            ph = layer.point_normal(unit(q - C))
            if ph[0] is None:
                return None
            p, n = ph
            p = p + n * (lift * length * t * t - 0.004)
            pts.append(p)
            nrm.append(n)
        pts = np.array(pts)
        side = unit(np.cross(a, n0))
        test = np.concatenate([pts, pts + side * width * 0.5, pts - side * width * 0.5])
        if min_edge is not None:
            e = self.style.region(test)
            if e.min() < min_edge:
                return None
        if in_ear(test).any():
            return None
        if test[:, 1].min() < -0.36:
            return None
        widths = [width * (1 - 0.12 * (i / rows)) for i in range(rows + 1)]
        return pts, widths, nrm

    def emit(self, piece, card, strip, ao_fn, double, twist=None):
        pts, widths, nrm = card
        add_card(piece, list(pts), widths, list(nrm), strip, shade=ao_fn, double=double, normals=list(nrm), twist=twist)

    def finish(self, piece, heads=()):
        """push every vertex clear of the head: radially above the head mesh and the skull table, then at
        least CLEAR_N from the nearest surface point, for the male head and (through the fit) each extra
        (head, fit) given"""
        out = []
        for p in piece.P:
            p = self.clear_push(np.array(p))
            d = unit(p - C)
            th, az = SK.angles(d)
            rs = SK.radius(th, az) + CLEAR
            r = float(np.linalg.norm(p - C))
            if r < rs:
                p = C + d * rs
            for _ in range(2):
                for head, fit in ((self.head, None),) + tuple(heads):
                    q = p if fit is None else p * [fit["ax"], fit["ay"], fit["az"]] + [0, 0, fit["dz"]]
                    loc, _n, _i, dist = head.bvh.find_nearest(Vector(tuple(q)))
                    if loc is not None and dist < CLEAR_N:
                        loc = np.array(loc)
                        q = loc + unit(q - loc) * CLEAR_N
                        self.stats["pushed"] += 1
                        p = q if fit is None else (q - [0, 0, fit["dz"]]) / [fit["ax"], fit["ay"], fit["az"]]
            out.append(tuple(p))
        piece.P = out


# ------------------------------------------------------------------------------------------- afro build
def region_of(d):
    th, az = SK.angles(d)
    if th < math.radians(38):
        return "top"
    a = math.degrees(az)
    if 135 <= a < 225:
        return "front"
    if 45 <= a < 135:
        return "right"
    if 225 <= a < 315:
        return "left"
    return "back"


MASS = {"front": "HairAfro01", "right": "HairAfro02", "left": "HairAfro03", "back": "HairAfro04", "top": "HairAfro05"}


def quadrant(d):
    x, z = d[0], d[2]
    return ("F" if z < 0.05 else "B") + ("R" if x >= 0 else "L")


CLUMPS = {"FR": "HairClump01", "FL": "HairClump02", "BR": "HairClump03", "BL": "HairClump04"}


def build_afro(style, head, coll):
    """returns (pieces in draw order, layers)"""
    t0 = time.time()
    B = Builder(style, head)
    rng = B.rng
    curly = getattr(style, "curly", False)
    names = getattr(style, "names", {"mass": MASS, "clumps": CLUMPS, "edge": "HairAfroEdge"})
    fr = [None, 0.34, 0.62, 0.86, 1.0, 1.15, 1.3]
    layers = []
    for i, f in enumerate(fr):
        ob = make_layer(style, f, f"{style.key}_layer{i}", coll)
        layers.append(Layer(style, ob, f))
    # Fabric: matte (kinky hair has almost no sheen; the generated afro uses it too)
    mass = {k: hl.Piece(v, "coily", length="volume", material="Fabric", castShadow=True)
            for k, v in names["mass"].items()}
    clumps = {k: hl.Piece(v, "coily", length="volume", material="Fabric", castShadow=False)
              for k, v in names["clumps"].items()}
    edge = hl.Piece(names["edge"], "coily", material="Fabric", castShadow=False)

    def under(p):  # the underside of the mass (nape, over the ears) is in its own shadow
        return 1 - 0.22 * float(smooth(0.12, -0.25, p[1]))

    tvor = bpy.data.textures["afro_clusters"]

    def crease(p, li):  # the valleys between the curl clusters (the Voronoi cells' borders) are darker
        f1 = tvor.evaluate(tuple(float(x) for x in p))[3]
        return 1 - (0.32 if li > 0 else 0.15) * float(smooth(0.35, 0.85, f1))

    # layer plan: (layer, count, length, width, rows, lift, strip, ao, double, min_edge)
    st_in = TIGHT
    st_out = LOOSE if curly else TIGHT
    plan = [
        (0, 230, 0.34, 0.19, 3, 0.04, TIGHT, 0.55, False, 0.0),
        (1, 250, 0.32, 0.17, 3, 0.05, TIGHT, 0.72, False, 0.008),
        (2, 420, 0.30, 0.16, 3, 0.06, st_in, 0.84, False, 0.015),
        (3, 640, 0.28, 0.15, 3, 0.07, st_out, 0.94, False, 0.025),
        # frizz shells: airy ringlet cards on the outside (the soft, broken silhouette); they bounce
        (5, 330, 0.26, 0.15, 3, 0.05, LOOSE, 1.0, False, 0.05),
        (6, 260, 0.24, 0.14, 3, 0.06, LOOSE, 1.0, False, 0.07),
    ]
    for (li, n, L, W, rows, lift, strip, ao, double, min_edge) in plan:
        lay = layers[li]
        dirs = fib_dirs(int(n / 0.56), seed=1000 + li * 17 + len(style.key))
        dirs = dirs[dirs[:, 1] > -0.75]
        kept = 0
        for d in dirs:
            s, _ = scalp_of(C + d)
            if style.region(s)[0] < min_edge + 0.01:
                continue
            ok = None
            base = rng.uniform(-1.3, 1.3) if li < 2 else rng.uniform(-math.pi, math.pi)
            sc = rng.uniform(0.85, 1.15)
            for rot, k in ((base, 1.0), (base + math.pi, 1.0), (base + math.pi / 2, 0.8), (base - math.pi / 2, 0.8),
                           (base, 0.6), (base + math.pi, 0.6)):
                ok = B.lay_card(lay, d, rot, L * sc * k, W * sc * (0.85 + 0.15 * k), rows, lift * rng.uniform(0.6, 1.3),
                                strip, ao, double, min_edge=min_edge)
                if ok is not None:
                    break
            if ok is None:
                B.stats["dropped"] += 1
                continue
            pts = ok[0]
            disp = float(np.linalg.norm(pts[len(pts) // 2] - C)) - float(
                np.linalg.norm(scalp_of(pts[len(pts) // 2])[0][0] - C))
            jitter = rng.uniform(0.95, 1.04)
            uf = under(pts[1]) * crease(pts[len(pts) // 2], li)

            def shade(t, ao=ao, uf=uf, jitter=jitter):
                v = ao * uf * jitter * (0.88 + 0.12 * t)
                return (min(1, v), min(1, v), min(1, v))
            target = mass[region_of(d)] if li <= 4 else clumps[quadrant(d)]
            B.emit(target, ok, strip, shade, double)
            kept += 1
        print(f"  layer {li}: {kept} cards")
    # hairline ring: short cards rooted just inside the hairline, growing out and up into the mass
    ring = layers[0]
    dirs = fib_dirs(5200, seed=9100)
    kept = 0
    for d in dirs:
        s, _ = scalp_of(C + d)
        e = style.region(s)[0]
        if not (0.006 < e < 0.08):
            continue
        front = float(np.cos(np.clip(da_of(s)[0], 0, math.pi)) > 0.3)
        if rng.random() > (0.75 if front else 0.5):
            continue
        p0, n0 = ring.point_normal(d)
        if p0 is None:
            continue
        # growth: away from the hairline (toward the crown), fanned
        g = -tangent_down(d)
        g = rotate(g, n0, rng.normal(0, 0.35))
        L = rng.uniform(0.09, 0.14)
        W = L * 0.55
        rise = rng.uniform(0.5, 0.95)
        pts = []
        for i in range(3):
            t = i / 2
            q = p0 + g * L * t
            ps, dd = scalp_of(q)
            rh = head.radius(dd[0])
            base = (rh if rh is not None else float(np.linalg.norm(ps[0] - C))) + CLEAR + 0.004
            pts.append(C + dd[0] * (base + rise * L * t * t))
        pts = np.array(pts)
        if in_ear(pts).any() or style.region(pts).min() < 0.006:
            continue
        ns = [unit(p - C) for p in pts]
        v0 = rng.uniform(0.6, 0.72)

        def shade(t, v0=v0):
            v = v0 * (0.85 + 0.25 * t)
            return (min(1, v), min(1, v), min(1, v))
        add_card(edge, list(pts), [W * 0.8, W, W * 0.9], ns, TIGHT, shade=shade, double=True, normals=ns)
        kept += 1
    print(f"  edge cards: {kept}")
    pieces = [edge] + [mass[k] for k in ("back", "left", "right", "top", "front")] + [clumps[k] for k in ("BL", "BR", "FL", "FR")]
    pieces = [p for p in pieces if p.nt > 0 and not any(p.name.startswith(s) for s in SKIP)]
    for p in pieces:
        B.finish(p, heads=((HEAD_F, FIT_F),))
    # bounce data: pivot on the scalp under the cluster's centroid, tip at the centroid
    for p in pieces:
        if p.name.startswith("HairClump"):
            cen = np.asarray(p.P).mean(0)
            piv, _ = scalp_of(cen)
            p.meta["hairfx"] = {"kind": "bounce", "stiff": 0.65, "mass": 1.3,
                                "pivot": [round(float(x), 4) for x in piv[0]], "tip": [round(float(x), 4) for x in cen]}
    print(f"  built {style.key} in {time.time() - t0:.1f}s, stats {B.stats}")
    return pieces, layers


# ------------------------------------------------------------------------------------------- checks
def fit_of(skull_path):
    """CONTRACT skull fit values (W, T, Fz, Bz) of a skull table"""
    s = hl.Skull(skull_path)

    def plane_point(az, y_target):
        best = None
        for th in np.linspace(0.3, 2.6, 900):
            p = s.point(th, math.radians(az))
            if best is None or abs(p[1] - y_target) < abs(best[1] - y_target):
                best = p
        return best
    W = plane_point(90, 0.15)[0]
    T = s.c[1] + s.radius(0.0, 0.0)
    Fz = plane_point(180, 0.2)[2]
    Bz = plane_point(0, 0.1)[2]
    return dict(W=W, T=T, Fz=Fz, Bz=Bz)


def clearance(pieces, head, fit=None):
    """min distance of any vertex to the head surface (and how many are inside it), optionally after a fit"""
    mind, inside, n = 9.0, 0, 0
    for p in pieces:
        P = np.asarray(p.P)
        if fit is not None:
            P = P * [fit["ax"], fit["ay"], fit["az"]] + [0, 0, fit["dz"]]
        for q in P[:: max(1, len(P) // 4000)]:
            dist = head.nearest(q)
            d = unit(q - C)
            rh = head.radius(d)
            r = float(np.linalg.norm(q - C))
            if rh is not None and r < rh:
                inside += 1
            mind = min(mind, dist)
            n += 1
    return mind, inside, n


def skull_height(pieces, skull, fit=None):
    m = 9.0
    for p in pieces:
        P = np.asarray(p.P)
        if fit is not None:
            P = P * [fit["ax"], fit["ay"], fit["az"]] + [0, 0, fit["dz"]]
        for q in P[:: max(1, len(P) // 3000)]:
            m = min(m, skull.height(q))
    return m


# ------------------------------------------------------------------------------------------- blend file
def save_blend(key, pieces, coll_guides, tex_path, path):
    root = bpy.data.objects.new("GameSpace (Y up, -Z face)", None)
    bpy.context.scene.collection.objects.link(root)
    root.rotation_euler = (math.pi / 2, 0, math.pi)
    for ob in coll_guides.objects:
        ob.parent = root
        ob.hide_render = True
        ob.hide_set(True)
    img = bpy.data.images.load(tex_path, check_existing=True)
    m = bpy.data.materials.new("hair_coily")
    m.use_nodes = True
    nt = m.node_tree
    bs = nt.nodes["Principled BSDF"]
    tx = nt.nodes.new("ShaderNodeTexImage")
    tx.image = img
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1
    nt.links.new(tx.outputs[0], mix.inputs[6])
    nt.links.new(vc.outputs[0], mix.inputs[7])
    tint = nt.nodes.new("ShaderNodeMix")
    tint.data_type = "RGBA"
    tint.blend_type = "MULTIPLY"
    tint.inputs[0].default_value = 1
    tint.inputs[7].default_value = (0.19, 0.13, 0.095, 1)
    nt.links.new(mix.outputs[2], tint.inputs[6])
    nt.links.new(tint.outputs[2], bs.inputs["Base Color"])
    nt.links.new(tx.outputs[1], bs.inputs["Alpha"])
    m.blend_method = "HASHED"
    hc = bpy.data.collections.new("hair (game pieces)")
    bpy.context.scene.collection.children.link(hc)
    for p in pieces:
        ob = hl.to_blender(p, bpy, material=m, collection=hc)
        ob.parent = root
    # the game's head for reference
    P, F = load_head(os.path.join(REF, "head_m.obj"))
    me = bpy.data.meshes.new("head_m")
    me.from_pydata([tuple(p) for p in P], [], F)
    hob = bpy.data.objects.new("head_m (reference)", me)
    bpy.context.scene.collection.objects.link(hob)
    hob.parent = root
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)


# ------------------------------------------------------------------------------------------- renders
def cap_standin(style, outdir):
    """a preview stand-in for the shared scalp cap the game paints per boxer: a polar mesh over the scalp at
    0.016 (u = az / 2pi, v = theta / 2.2 as CONTRACT.md), its texture the short tile repeated 8 x 4 with
    alpha = tile alpha x the natural hairline's soft coverage (cap cut "full")"""
    from PIL import Image
    gw, gh = 256, 128
    th = (np.arange(gh) + 0.5) / gh * 2.2
    az = (np.arange(gw) + 0.5) / gw * TAU
    TH, AZ = np.meshgrid(th, az, indexing="ij")
    D = dir_th_az(TH.ravel(), AZ.ravel())
    r = np.array([SK.radius(*SK.angles(d)) for d in D])
    S = C + D * r[:, None]
    e = style.cap_region(S) if hasattr(style, "cap_region") else edge_dist(S)
    cov = smooth(-0.012, 0.01, e).reshape(gh, gw)
    W, H = 1024, 512
    cov = np.asarray(Image.fromarray((cov * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float32) / 255
    tile = Image.open(os.path.join(TEX_DIR, "hair_short.png")).convert("RGBA").resize((W // 8, H // 4), Image.LANCZOS)
    t = np.tile(np.asarray(tile, np.float32) / 255, (4, 8, 1))
    t[..., 3] *= cov
    path = os.path.join(outdir, f"capstandin_{style.key}.png")
    Image.fromarray((np.clip(t, 0, 1) * 255).astype(np.uint8), "RGBA").save(path)
    p = hl.Piece("HairCap", "short")
    n_th, n_az = 60, 96
    ids = {}
    for i in range(n_th + 1):
        for j in range(n_az + 1):
            t_ = i / n_th * 2.2
            a_ = j / n_az * TAU
            d = dir_th_az(np.array([t_]), np.array([a_]))[0]
            ids[(i, j)] = p.vert(SK.point(t_, a_, 0.016), d, (j / n_az, i / n_th), (0.5, 0.5, 0.5))
    for i in range(n_th):
        for j in range(n_az):
            # counter-clockwise from outside
            p.tri(ids[(i, j)], ids[(i, j + 1)], ids[(i + 1, j + 1)])
            p.tri(ids[(i, j)], ids[(i + 1, j + 1)], ids[(i + 1, j)])
    return p, path


def single_sided(piece):
    """a render copy without the reversed duplicate triangles of two-sided cards (Cycles shades both sides
    of a face; coplanar duplicates would z-fight): of each pair, the triangle whose right-hand normal agrees
    with the shading normals is kept"""
    q = hl.Piece(piece.name, piece.tex)
    q.P, q.N, q.U, q.C = piece.P, piece.N, piece.U, piece.C
    P, N = np.asarray(piece.P), np.asarray(piece.N)
    seen = {}
    for t in piece.T:
        k = tuple(sorted(t))
        ng = np.cross(P[t[1]] - P[t[0]], P[t[2]] - P[t[0]])
        good = float(np.dot(ng, N[list(t)].sum(0))) >= 0
        if k not in seen or (good and not seen[k][1]):
            seen[k] = (t, good)
    q.T = [v[0] for v in seen.values()]
    return q


MATTE = {"Roughness": 0.8, "Specular IOR Level": 0.25, "Anisotropic": 0.0}
TINTS = {"black": (0.09, 0.078, 0.07), "darkbrown": (0.188, 0.129, 0.094), "blonde": (0.77, 0.61, 0.36)}
SKINS = {"mid": None, "deep": (0.2, 0.12, 0.08), "light": (0.72, 0.52, 0.4)}


def render_style(key, pieces, style, outdir, samples, looks):
    import render
    os.makedirs(outdir, exist_ok=True)
    tex = os.path.join(TEX_DIR, "hair_coily.png")
    short = os.path.join(TEX_DIR, "hair_short.png")
    cap, cap_tex = cap_standin(style, outdir)
    sheets = []
    for (head_name, tint_name, skin_name, views) in looks:
        tint = TINTS[tint_name]
        sc = render.Scene(res=(520, 620), samples=samples, focus=(0.0, 0.17, 0.02), dist=4.3)
        skin = SKINS[skin_name] or render.SKIN
        render.add_obj(sc, os.path.join(REF, f"head_{head_name}.obj"), tint=skin)
        tor = render.load_obj(os.path.join(REF, f"torso_{head_name}.obj"))
        for nm, md in tor.items():
            md = dict(md, c=None)
            sc.add_mesh(md, material="skin", tint=skin, name="torso")
        fit = None
        if head_name == "f":
            fit = FIT_F
        scl = (fit["ax"], fit["ay"], fit["az"]) if fit else (1, 1, 1)
        off = (0, 0, fit["dz"]) if fit else (0, 0, 0)
        sc.add_piece(single_sided(cap), texture=cap_tex, tint=tint, offset=off, scale=scl)
        for p in pieces:
            ob = sc.add_piece(single_sided(p), texture=tex, tint=tint, offset=off, scale=scl)
            if os.environ.get("AFRO_NOSHADOW"):
                ob.visible_shadow = False
            mat = json.loads(os.environ["AFRO_MAT"]) if os.environ.get("AFRO_MAT") else (
                MATTE if p.meta.get("material") == "Fabric" else None)
            if mat:  # Roblox Fabric is matte: the preview's hair material made rough, low specular, isotropic
                bs = ob.data.materials[0].node_tree.nodes["Principled BSDF"]
                for k, v in mat.items():
                    bs.inputs[k].default_value = v
        paths = []
        for v in views:
            path = os.path.join(outdir, f"{key}_{head_name}_{tint_name}_{v}.png")
            if v == "close":
                sc.render(path, view=(12, 4, 1.0), dist=2.2, focus=(0, 0.24, -0.15))
            else:
                sc.render(path, view=v)
            paths.append(path)
        sheets.append((paths, [f"{head_name} {tint_name} {v}" for v in views]))
    allp = [p for s in sheets for p in s[0]]
    alll = [l for s in sheets for l in s[1]]
    out = os.path.join(outdir, f"sheet_{key}.jpg")
    render.sheet(allp, out, cols=5, labels=alll, title=f"{key} ({sum(p.nt for p in pieces)} tris)",
                 cell=(312, 372))
    return out


# ------------------------------------------------------------------------------------------- main
STYLES = {
    "afro": dict(cls=lambda: Afro("afro"), entry=dict(styles=["Afro"], types=["Kinky", "Coiled", "Straight", "Wavy"],
                                                       cap={"cut": "full", "density": 1})),
    "afro_curly": dict(cls=lambda: Afro("afro_curly", curly=True),
                       entry=dict(styles=["Afro"], types=["Curly"], cap={"cut": "full", "density": 1})),
    "hightop": dict(cls=lambda: HighTop("hightop"),
                    entry=dict(styles=["High Top"], types=None, cap={"cut": "style", "density": 1})),
}

FIT_F = None
HEAD_F = None
SKIP = []


def main():
    global FIT_F, HEAD_F
    ap = argparse.ArgumentParser()
    ap.add_argument("--render", default="")
    ap.add_argument("--only", default="")
    ap.add_argument("--no-tex", action="store_true")
    ap.add_argument("--samples", type=int, default=48)
    ap.add_argument("--quick", action="store_true", help="renders: one look, fewer views")
    ap.add_argument("--skip", default="", help="debug: piece name prefixes to leave out")
    args = ap.parse_args()
    SKIP[:] = [s for s in args.skip.split(",") if s]
    t0 = time.time()
    os.makedirs(TEX_DIR, exist_ok=True)
    tex_path = os.path.join(TEX_DIR, "hair_coily.png")
    if not args.no_tex or not os.path.exists(tex_path):
        lum, alp = afro_tex.tex_coily(1024)
        afro_tex.save(tex_path, lum, alp)
        print(f"texture coily: {time.time() - t0:.1f}s")
    fm = dict(W=0.383, T=0.591, Fz=-0.460, Bz=0.520)
    ff = fit_of(os.path.join(REF, "skull_f.json")) if os.path.exists(os.path.join(REF, "skull_f.json")) else None
    if ff is None:
        FIT_F = dict(ax=0.965, ay=1.0, az=1.0, dz=0.0)
    else:
        FIT_F = dict(ax=ff["W"] / fm["W"], ay=ff["T"] / fm["T"], az=(ff["Bz"] - ff["Fz"]) / (fm["Bz"] - fm["Fz"]),
                     dz=(ff["Bz"] + ff["Fz"]) / 2 - (fm["Bz"] + fm["Fz"]) / 2)
    print("female fit", {k: round(v, 4) for k, v in FIT_F.items()})
    keys = [k for k in STYLES if not args.only or k in args.only.split(",")]
    report = {}
    head_m = None
    for key in keys:
        clear_scene()
        head_m = Head(os.path.join(REF, "head_m.obj"))
        head_f = HEAD_F = Head(os.path.join(REF, "head_f.obj"))
        style = STYLES[key]["cls"]()
        coll = bpy.data.collections.new("guides (card layers)")
        bpy.context.scene.collection.children.link(coll)
        print(f"style {key}")
        pieces, layers = build_afro(style, head_m, coll)
        entry = dict(STYLES[key]["entry"])
        cm, ci, _ = clearance(pieces, head_m)
        cf, cfi, _ = clearance(pieces, head_f, FIT_F)
        sm = skull_height(pieces, SK)
        sf = skull_height(pieces, hl.Skull(os.path.join(REF, "skull_f.json")), FIT_F) if ff else None
        entry["notes"] = (f"afro family (build_afro.py). min clearance above head mesh: male {cm:.4f}, "
                          f"female fit {cf:.4f}")
        data = hl.export_style(key, entry, pieces)
        save_blend(key, pieces, coll, tex_path, os.path.join(BLEND_DIR, f"{key}.blend"))
        rep = dict(tris=data["tris"], pieces={p.name: dict(nt=p.nt, hairfx=p.meta.get("hairfx", {}).get("kind"))
                                                for p in pieces},
                   clear_m=round(cm, 4), inside_m=ci, clear_f=round(cf, 4), inside_f=cfi, skull_m=round(sm, 4),
                   skull_f=round(sf, 4) if sf is not None else None)
        report[key] = rep
        print(json.dumps(rep))
        if args.render:
            looks = [("m", "black", "mid", ["34", "side", "back", "close", "top34"]),
                     ("m", "darkbrown", "deep", ["34", "side", "back", "close", "top34"]),
                     ("f", "darkbrown", "light", ["34", "side", "back", "close", "top34"])]
            if args.quick:
                looks = [("m", "darkbrown", "mid", ["34", "side", "back", "close", "top34"])]
            sheet = render_style(key, pieces, style, args.render, args.samples, looks)
            rep["sheet"] = sheet
            print("sheet", sheet)
    print(json.dumps(report, indent=1))
    print(f"total {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()
