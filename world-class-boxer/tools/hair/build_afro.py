"""Afro family hair cards: "Afro" (Kinky / Coiled and the Straight / Wavy afro the generated hair treats as
Kinky; its Curly variant as a second entry) and the "High Top". Modelled in Blender (bpy 4.2), exported with
hairlib (see CONTRACT.md).

    /opt/bpyenv/bin/python tools/hair/build_afro.py [--only afro,afro_curly,hightop] [--no-tex]
                                                    [--render] [--quick] [--views 34,side] [--looks m_black]

Writes tools/hair/textures/hair_coily.png (afro_tex.py), tools/hair/out/<key>/ (meshes + style.json),
tools/hair/blend/<key>.blend; with --render, Cycles self-check renders and one sheet per style in FAM_DIR.

How a style is built (game nominal head space, numerically):
* Envelope: the style's outer surface as a thickness field H over the scalp (rays from the skull centre):
  an egg for the afro (fullest at the top-back and above the ears, narrowing below), a superellipse
  column with a domed, round-cornered top for the high top. Near the hairline (the natural hairline; for
  the high top the high fade's top line and the front line-up) the thickness eases from the root layer up
  to the envelope over a soft, rounded span: the mass rises out of the hairline with no brim or ledge.
* Layers: each nested card layer (a fraction f of H) is a Blender mesh (a polar grid on the scalp) with
  modifiers: two Displace modifiers on Clouds textures (broad asymmetric lumps, then curl-cluster lumps),
  weighted by a vertex group that fades them out toward the hairline, and a Smooth. The evaluated layers
  become BVH trees.
* Cards: surface patches laid on each layer (every vertex of a patch ray-cast onto the evaluated layer, so
  a patch follows the lumps; random rotation and tilt, heavy overlap, a soft cloud texture with no outline),
  innermost layer first; fuzz fins (two-sided cards standing out of the outer layer) break up the
  silhouette; short tufts rooted along the hairline grow up and back out of it (sparse and short at the
  line, denser and longer behind it), over the shared scalp cap (entry cap). Shading normals are the
  layer's outward normals; vertex colours bake occlusion (deeper layers darker, lump valleys a little
  darker, the underside darker).
* Pieces: the root layer, the hairline tufts and anything lower than VOL_MIN over the scalp in one
  unscaled piece (length null: the volume slider never moves the hairline or sinks it into the head);
  the mass by region (front, top, back, left, right: length "volume"); the outer layer + fins of the top,
  back and sides as HairClump bounce pieces (stiff, small: they ride on the dense mass under them).
* Clearance: every vertex at least CLEAR over the male skull table and the head mesh (head_m.obj), and,
  through the runtime skull fit, over the female skull table and head_f.obj; checked again with the
  runtime's volume transform at volume factors 0.8 and 1.3.
"""
import argparse
import json
import math
import os
import struct
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
from hairlib import Piece, Skull  # noqa: E402

FAM_DIR = "/tmp/claude-0/-home-user-tutorial/3e72dc83-9506-5d11-a575-9dd4f250e9a5/scratchpad/fam/afro"
TEX_DIR = os.path.join(HERE, "textures")
BLEND_DIR = os.path.join(HERE, "blend")
REF = hl.REF
TAU = 2 * math.pi

CLEAR = 0.023  # min height of any vertex over the skull tables / head meshes (male, female through the fit)
H0 = 0.034  # the root layer's height over the skull
VOL_MIN = 0.068  # a card with any vertex lower than this goes to the unscaled piece
EAR_PAD = 0.022
SMIN = 0.08  # smallest surface patch (near the line)
CELLS = afro_tex.CELLS
FIN_T = (0.5, 0.75)
FIN_L = (0.75, 1.0)

SK = Skull()
SKF = Skull(os.path.join(REF, "skull_f.json"))
C = SK.c.copy()
SKD = SK.data
EARS = [(np.array(SKD["ears"][s]["min"]) - EAR_PAD, np.array(SKD["ears"][s]["max"]) + EAR_PAD)
        for s in ("left", "right")]


# =============================================================================================== helpers
def sstep(e0, e1, x):
    t = np.clip((np.asarray(x, np.float64) - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def unit(v):
    v = np.asarray(v, np.float64)
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-12)


def da_of(P):
    P = np.atleast_2d(P)
    return np.arctan2(np.abs(P[:, 0]), -(P[:, 2] - 0.05))


def dirs_of(th, az):
    s = np.sin(th)
    return np.stack([s * np.sin(az), np.cos(th), s * np.cos(az)], axis=-1)


def angles_of(D):
    D = unit(D)
    th = np.arccos(np.clip(D[:, 1], -1, 1))
    az = np.arctan2(D[:, 0], D[:, 2]) % TAU
    return th, az


def skull_r(sk, th, az):
    """vectorised Skull.radius (bilinear in the radial table)"""
    T = sk.th
    th = np.clip(th, T[0], T[-1])
    i = np.clip(np.searchsorted(T, th) - 1, 0, len(T) - 2)
    ti = (th - T[i]) / (T[i + 1] - T[i])
    n = len(sk.az)
    a = (az % TAU) / (TAU / n)
    j = np.floor(a).astype(int) % n
    tj = a - np.floor(a)
    j2 = (j + 1) % n
    r = sk.r
    top = r[i, j] * (1 - tj) + r[i, j2] * tj
    bot = r[i + 1, j] * (1 - tj) + r[i + 1, j2] * tj
    return top * (1 - ti) + bot * ti


def skull_height(sk, P):
    """radial height of points over a skull table (vectorised)"""
    D = P - sk.c
    th, az = angles_of(D)
    return np.linalg.norm(D, axis=1) - skull_r(sk, th, az)


def in_ear(p):
    for lo, hi in EARS:
        if np.all(p > lo) and np.all(p < hi):
            return True
    return False


def rot(v, axis, a):
    axis = axis / np.linalg.norm(axis)
    return v * math.cos(a) + np.cross(axis, v) * math.sin(a) + axis * np.dot(axis, v) * (1 - math.cos(a))


# =============================================================================================== lines
class Line:
    """a hairline-like line on the scalp: polylines (3D) for distances and a height table (da -> y) for
    inside tests (inside = above the line)"""

    def __init__(self, polys, height):
        self.polys = [np.asarray(p, np.float64) for p in polys]
        segs = []
        for p in self.polys:
            segs.append(np.stack([p[:-1], p[1:]], axis=1))
        self.segs = np.concatenate(segs)
        h = np.asarray(sorted(height), np.float64)
        self.hda, self.hy = h[:, 0], h[:, 1]

    def y_at(self, da):
        return np.interp(da, self.hda, self.hy)

    def inside(self, P):
        return P[:, 1] > self.y_at(da_of(P))

    def dist(self, P, chunk=4000):
        """signed distance to the line (+ inside)"""
        P = np.atleast_2d(P)
        out = np.empty(len(P))
        A = self.segs[:, 0][None]
        B = self.segs[:, 1][None]
        AB = B - A
        L2 = np.maximum((AB ** 2).sum(-1), 1e-12)
        for s in range(0, len(P), chunk):
            Q = P[s:s + chunk][:, None]
            t = np.clip(((Q - A) * AB).sum(-1) / L2, 0, 1)
            X = A + AB * t[..., None]
            out[s:s + chunk] = np.sqrt(((Q - X) ** 2).sum(-1)).min(axis=1)
        sign = np.where(self.inside(P), 1.0, -1.0)
        return out * sign


def natural_line():
    L = SKD["hairline"]["lines"]["Natural"]
    left = [p[1:] for p in L["left"] if p]
    right = [p[1:] for p in L["right"] if p]
    back = [left[-1], right[-1]]
    front = [right[0], left[0]]
    return Line([left, right, back, front], L["height"])


def hightop_line():
    """the high top's foot: the front line-up (the natural hairline) to da 0.55, then the high fade's top line"""
    L = SKD["hairline"]["lines"]["Natural"]
    tl = SKD["fades"]["topLines"]["high"]
    da0 = 0.55
    polys, height = [], []
    for side in ("left", "right"):
        nat = [p for p in L[side] if p and p[0] < da0]
        top = tl[side]
        polys.append([p[1:] for p in nat] + [p[1:] for p in top])
    polys.append([polys[0][-1], polys[1][-1]])
    polys.append([polys[1][0], polys[0][0]])
    for da, y in L["height"]:
        if da < da0:
            height.append([da, y])
    for p in tl["right"]:
        height.append([p[0], p[2]])
    height.append([math.pi, tl["right"][-1][2]])
    return Line(polys, height)


# =============================================================================================== envelopes
def ray_hit(F, D, t0, t1, n=60):
    """first zero crossing of F along rays C + D t (F < 0 inside), t in [t0, t1] per ray (bisection after a
    coarse march)"""
    N = len(D)
    ts = np.linspace(0, 1, n)
    prev_t = t0.copy()
    prev_in = F(C + D * t0[:, None]) < 0
    hit = np.full(N, np.nan)
    lo = np.zeros(N)
    hi = np.zeros(N)
    for k in ts[1:]:
        t = t0 + (t1 - t0) * k
        cur_in = F(C + D * t[:, None]) < 0
        m = prev_in & ~cur_in & np.isnan(hit)
        lo[m], hi[m] = prev_t[m], t[m]
        hit[m] = 1
        prev_t, prev_in = t, cur_in
    m = np.isnan(hit)
    lo[m], hi[m] = t1[m], t1[m]
    start_out = F(C + D * t0[:, None]) >= 0  # the scalp is already outside the envelope: no hair above it
    lo[start_out], hi[start_out] = t0[start_out], t0[start_out]
    for _ in range(30):
        mid = (lo + hi) / 2
        ins = F(C + D * mid[:, None]) < 0
        lo = np.where(ins, mid, lo)
        hi = np.where(ins, hi, mid)
    return (lo + hi) / 2


def afro_sdf(scale=1.0):
    """an egg (pseudo-distance, < 0 inside): fullest at the top-back and above the ears, narrower below"""
    E = np.array([0.0, 0.2, 0.09])

    def F(P):
        x, y, z = P[:, 0], P[:, 1] - E[1], P[:, 2] - E[2]
        nar = 1 - 0.16 * sstep(0.05, -0.45, y)
        rx = (0.215 + 0.405 * scale) * nar
        ry = np.where(y > 0, 0.4 + 0.27 * scale, 0.45 + 0.2 * scale)
        rz = np.where(z > 0, 0.48 + 0.24 * scale, 0.45 + 0.22 * scale) * nar
        return np.sqrt((x / rx) ** 2 + (y / ry) ** 2 + (z / rz) ** 2) - 1

    return F


def smax(a, b, k):
    h = np.clip(0.5 - 0.5 * (b - a) / k, 0, 1)
    return a * h + b * (1 - h) + k * h * (1 - h)


def hightop_sdf(y_top=0.875):
    """a column of superellipse section that widens a little toward its top (its foot hugs the scalp at the
    fade's top line), the front face leaning back, a gently domed top with well-rounded corners"""
    yb = 0.2

    def F(P):
        x, y, z = P[:, 0], P[:, 1], P[:, 2]
        k = np.clip((y - yb) / (y_top - yb), 0, 1)
        kk = k ** 0.7
        hx = 0.385 + 0.085 * kk
        lean = 0.07 * (y - yb)
        hz = 0.47 - lean + 0.05 * kk
        cz = 0.045 + lean
        ax, az_ = np.abs(x) / hx, np.abs(z - cz) / hz
        p = 2.6
        r = (ax ** p + az_ ** p) ** (1 / p)
        d_side = (r - 1) * np.minimum(hx, hz)
        d_top = y - (y_top + 0.05 * (1 - np.minimum(1, r * r)))
        return smax(d_side, d_top, 0.15)

    return F


# =============================================================================================== scalp grid
class Grid:
    """a polar grid of scalp directions (theta from +Y, az from +Z toward +X), vertices kept where the style can
    have hair (and a margin band below its line, so rays near the line always hit a layer)"""

    def __init__(self, line, dth=2.0, daz=2.5, th_max=150.0, margin=0.08):
        self.dth, self.daz = math.radians(dth), math.radians(daz)
        nth = int(round(th_max / dth)) + 1
        naz = int(round(360 / daz))
        self.nth, self.naz = nth, naz
        th = np.radians(np.arange(nth) * dth)
        az = np.arange(naz) * self.daz
        TH, AZ = np.meshgrid(th, az, indexing="ij")
        self.TH, self.AZ = TH.ravel(), AZ.ravel()
        self.D = dirs_of(self.TH, self.AZ)
        self.R = skull_r(SK, self.TH, self.AZ)
        self.S = C + self.D * self.R[:, None]
        self.d = line.dist(self.S)
        self.keep = self.d > -margin
        quads = []
        for i in range(nth - 1):
            for j in range(naz):
                a, b = i * naz + j, i * naz + (j + 1) % naz
                c, d = (i + 1) * naz + (j + 1) % naz, (i + 1) * naz + j
                if self.keep[a] and self.keep[b] and self.keep[c] and self.keep[d]:
                    quads.append((a, d, c, b))
        self.quads = quads
        # outward winding check
        a, b, c, d = quads[len(quads) // 2]
        n = np.cross(self.S[b] - self.S[a], self.S[d] - self.S[a])
        if np.dot(n, self.S[a] - C) < 0:
            self.quads = [(a, b, c, d)[::-1] for (a, b, c, d) in quads]

    def interp(self, D, field):
        """bilinear lookup of a per-vertex field at directions D"""
        th, az = angles_of(D)
        fi = np.clip(th / self.dth, 0, self.nth - 1.001)
        i0 = np.floor(fi).astype(int)
        ti = fi - i0
        fa = az / self.daz
        j0 = np.floor(fa).astype(int) % self.naz
        tj = fa - np.floor(fa)
        j1 = (j0 + 1) % self.naz
        f = field
        idx = lambda i, j: i * self.naz + j  # noqa: E731
        sh = (-1,) + (1,) * (f.ndim - 1)
        ti, tj = ti.reshape(sh), tj.reshape(sh)
        a = f[idx(i0, j0)] * (1 - tj) + f[idx(i0, j1)] * tj
        b = f[idx(i0 + 1, j0)] * (1 - tj) + f[idx(i0 + 1, j1)] * tj
        return a * (1 - ti) + b * ti


# =============================================================================================== styles
STYLES = {
    "afro": dict(
        styles=["Afro"], types=["Kinky", "Coiled", "Straight", "Wavy"], cap={"cut": "full", "density": 1},
        cover="none", line="natural", shape="afro", scale=1.0, prefix="HairAfro",
        # shells: (f, tile size, -, cell, ao); band patches near the line: (layer, (f, size, cover, cell, ao))
        layers=[(0.0, 0.2, 0, "TILE_D", 0.5), (0.35, 0.2, 0, "TILE_D", 0.6), (0.62, 0.2, 0, "TILE_D", 0.7),
                (0.8, 0.2, 0, "TILE_S", 0.82), (0.91, 0.2, 0, "TILE_S", 0.9), (1.0, 0.2, 0, "TILE_S", 0.97)],
        band=[(0, (0.0, 0.12, 1.6, "CLOUD_A", 0.55)), (1, (0.35, 0.12, 1.3, "CLOUD_A", 0.65))],
        fins=dict(n=480, cell=FIN_T, length=(0.065, 0.095), width=(0.035, 0.05), sink=0.035),
        lumps=(0.11, 0.05), span=(0.2, 0.21, 0.22, 0.26), notes="rounded afro"),
    "afro_curly": dict(
        styles=["Afro"], types=["Curly"], cap={"cut": "full", "density": 1},
        cover="none", line="natural", shape="afro", scale=0.88, prefix="HairAfro",
        layers=[(0.0, 0.2, 0, "TILE_D", 0.5), (0.38, 0.2, 0, "TILE_D", 0.62), (0.68, 0.2, 0, "TILE_D", 0.72),
                (0.86, 0.22, 0, "TILE_S", 0.86), (1.0, 0.22, 0, "TILE_S", 0.95)],
        band=[(0, (0.0, 0.12, 1.6, "CLOUD_A", 0.55)), (1, (0.38, 0.12, 1.3, "CLOUD_A", 0.65))],
        fins=dict(n=340, cell=FIN_L, length=(0.1, 0.15), width=(0.05, 0.07), sink=0.035),
        lumps=(0.12, 0.07), span=(0.2, 0.21, 0.22, 0.26), notes="curly afro: open curl clusters, ringlets"),
    "hightop": dict(
        styles=["High Top"], types=None, cap={"cut": "style", "density": 1},
        cover="high", line="hightop", shape="hightop", prefix="HairTop",
        layers=[(0.0, 0.2, 0, "TILE_D", 0.5), (0.38, 0.2, 0, "TILE_D", 0.6), (0.65, 0.2, 0, "TILE_D", 0.7),
                (0.82, 0.2, 0, "TILE_S", 0.82), (0.92, 0.2, 0, "TILE_S", 0.9), (1.0, 0.2, 0, "TILE_S", 0.97)],
        band=[(0, (0.0, 0.09, 1.5, "CLOUD_A", 0.62))],
        fins=dict(n=340, cell=FIN_T, length=(0.05, 0.075), width=(0.04, 0.05), sink=0.022),
        lumps=(0.03, 0.025), span=(0.06, 0.1, 0.1, 0.1), notes="high top column over a high fade"),
}


def thickness(spec, grid):
    """H per grid vertex: the envelope eased in from the line"""
    D = grid.D
    if spec["shape"] == "afro":
        F = afro_sdf(spec["scale"])
    else:
        F = hightop_sdf()
    t = ray_hit(F, D, grid.R + 0.005, np.full(len(D), 1.6))
    Henv = np.maximum(t - grid.R, H0)
    da = da_of(grid.S)
    s_front, s_side, s_ear, s_back = spec["span"]
    span = np.interp(da, [0, 0.5, 1.0, 1.45, 1.95, 2.4, math.pi], [s_front, s_front, s_side, s_ear, s_ear, s_back, s_back])
    x = np.clip(grid.d / span, 0, 1)
    if spec["shape"] == "afro":
        ease = 0.5 * np.sqrt(1 - (1 - x) ** 2) + 0.5 * (1 - (1 - x) ** 2.2)
    else:
        ease = 1 - (1 - x) ** 2
    H = H0 + (Henv - H0) * ease
    if spec["shape"] == "afro":
        # in front of, over and behind the ears the hair stays short down low (a short rounded sideburn, the
        # ears clear), the mass swelling only above ear-top height
        y = grid.S[:, 1]
        low = sstep(0.85, 1.15, da) * sstep(2.45, 2.15, da)
        Hc = 0.045 + 0.95 * np.clip(y - 0.04, 0, None)
        H = np.minimum(H, Hc + (1 - low) * 10)
    H = np.where(grid.d > 0, H, H0)
    return H, span


# =============================================================================================== Blender
def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def coll(name):
    c = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(c)
    return c


def mesh_obj(name, P, F, collection):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(map(float, p)) for p in P], [], [tuple(map(int, f)) for f in F])
    me.update()
    ob = bpy.data.objects.new(name, me)
    collection.objects.link(ob)
    return ob


def make_texture(name, kind, scale, depth=2, seed_off=0.0):
    tex = bpy.data.textures.new(name, kind)
    tex.noise_scale = scale
    if kind == "CLOUDS":
        tex.noise_depth = depth
        tex.noise_basis = "BLENDER_ORIGINAL"
        tex.noise_type = "SOFT_NOISE"
    return tex


class Layer:
    """one card layer: a Blender object (grid + Displace / Smooth modifiers), its evaluated surface (BVH),
    smooth normals and lump value per grid vertex"""

    def __init__(self, idx, f, spec, grid, H, span, collection, texs):
        self.f = f
        # (the layers keep a little apart where they converge toward the line: no coincident shells)
        h = np.maximum(H0 + f * (H - H0), np.where(grid.d > 0, H0 + 0.006 * idx, H0))
        self.h = h
        P = grid.S + grid.D * h[:, None]
        used = sorted({i for q in grid.quads for i in q})
        remap = -np.ones(len(P), int)
        remap[used] = np.arange(len(used))
        self.used = np.array(used)
        faces = [tuple(remap[i] for i in q) for q in grid.quads]
        self.faces = faces
        ob = mesh_obj(f"Layer{idx}_f{f:.2f}", P[used], faces, collection)
        self.ob = ob
        # the lumps fade out toward the line, and grow outward through the layers
        w = f * sstep(0.0, span * 1.1, grid.d) ** 1.3
        vg = ob.vertex_groups.new(name="lumps")
        for k, i in enumerate(used):
            vg.add([k], float(w[i]), "REPLACE")
        a1, a2 = spec["lumps"]
        m1 = ob.modifiers.new("BroadLumps", "DISPLACE")
        m1.texture = texs[0]
        m1.texture_coords = "GLOBAL"
        m1.direction = "NORMAL"
        m1.strength = a1 * 2
        m1.mid_level = 0.5
        m1.vertex_group = "lumps"
        m2 = ob.modifiers.new("CurlClusters", "DISPLACE")
        m2.texture = texs[1]
        m2.texture_coords = "GLOBAL"
        m2.direction = "NORMAL"
        m2.strength = a2 * 2
        m2.mid_level = 0.5
        m2.vertex_group = "lumps"
        sm = ob.modifiers.new("Smooth", "SMOOTH")
        sm.factor = 0.6
        sm.iterations = 2
        dg = bpy.context.evaluated_depsgraph_get()
        eo = ob.evaluated_get(dg)
        me = eo.to_mesh()
        n = len(me.vertices)
        co = np.empty(n * 3)
        me.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        nr = np.empty(n * 3)
        me.vertex_normals.foreach_get("vector", nr)
        nr = nr.reshape(-1, 3)
        eo.to_mesh_clear()
        self.P = co
        self.bvh = BVHTree.FromPolygons([tuple(p) for p in co], faces)
        # full-grid fields for lookups
        N = np.zeros((len(P), 3))
        N[used] = nr
        N[~np.isin(np.arange(len(P)), used)] = grid.D[~np.isin(np.arange(len(P)), used)]
        self.N = unit(N)
        disp = np.zeros(len(P))
        disp[used] = np.linalg.norm(co - C, axis=1) - np.linalg.norm(P[used] - C, axis=1)
        sd = float(np.std(disp[used])) or 1.0
        self.lump = np.clip(disp / (2 * sd), -1, 1)
        self.area = 0.0
        for fc in faces:
            pts = co[list(fc)]
            self.area += 0.5 * np.linalg.norm(np.cross(pts[2] - pts[0], pts[1] - pts[0])) + \
                0.5 * np.linalg.norm(np.cross(pts[3] - pts[0], pts[2] - pts[0]))
        self.grid = grid

    def hit(self, d):
        loc, nrm, idx, dist = self.bvh.ray_cast(Vector(tuple(C)), Vector(tuple(d)))
        if loc is None:
            return None
        return np.array(loc)

    def normal(self, D):
        return unit(self.grid.interp(np.atleast_2d(D), self.N))

    def lump_at(self, D):
        return self.grid.interp(np.atleast_2d(D), self.lump)


# =============================================================================================== cards
def fib_dirs(n, seed):
    rng = np.random.default_rng(seed)
    i = np.arange(n) + 0.5
    y = 1 - 2 * i / n
    r = np.sqrt(1 - y * y)
    a = i * math.pi * (3 - math.sqrt(5)) + rng.normal(0, 0.6, n) / math.sqrt(n) * 6
    D = np.stack([r * np.cos(a), y, r * np.sin(a)], axis=1)
    D += rng.normal(0, 0.35 / math.sqrt(n), D.shape)
    return unit(D)


def region_of(d):
    """front / top / back / left / right by the direction from the skull centre"""
    if d[1] > 0.8:
        return "top"
    az = math.atan2(d[0], d[2]) % TAU
    deg = math.degrees(az)
    if 135 <= deg < 225:
        return "front" if d[1] < 0.62 else "top"
    if 45 <= deg < 135:
        return "right"
    if 225 <= deg < 315:
        return "left"
    return "back"


class Card:
    __slots__ = ("P", "N", "U", "C", "T", "layer", "region", "kind")

    def __init__(self, layer, kind):
        self.P, self.N, self.U, self.C, self.T = [], [], [], [], []
        self.layer = layer
        self.kind = kind
        self.region = None

    def to_piece(self, piece):
        base = piece.nv
        for p, n, u, c in zip(self.P, self.N, self.U, self.C):
            piece.vert(p, n, u, c)
        for a, b, c in self.T:
            piece.tri(a + base, b + base, c + base)


def blue_noise(S, rad, ok, rng, cell=0.04):
    """dart throwing: candidates in random order, kept when no kept one lies closer than its radius (an even,
    gap-free spread, unlike independent random picks)"""
    keep = np.zeros(len(S), bool)
    order = np.nonzero(ok)[0]
    rng.shuffle(order)
    buckets = {}
    for k in order:
        key = tuple((S[k] // cell).astype(int))
        r = rad[k]
        span = int(math.ceil(r / cell))
        hit = False
        for dx in range(-span, span + 1):
            for dy in range(-span, span + 1):
                for dz in range(-span, span + 1):
                    for j in buckets.get((key[0] + dx, key[1] + dy, key[2] + dz), ()):
                        if np.sum((S[j] - S[k]) ** 2) < (0.5 * (r + rad[j])) ** 2:
                            hit = True
                            break
                    if hit:
                        break
                if hit:
                    break
            if hit:
                break
        if not hit:
            keep[k] = True
            buckets.setdefault(key, []).append(k)
    return keep


def cube_dirs(N, R):
    """an equi-angular cube-sphere grid: per face (N+1) x (N+1) directions, rotated by R"""
    out = []
    a = np.tan(np.linspace(-math.pi / 4, math.pi / 4, N + 1))
    A, B = np.meshgrid(a, a, indexing="ij")
    one = np.ones_like(A)
    for axis in range(3):
        for sgn in (1.0, -1.0):
            V = np.zeros(A.shape + (3,))
            V[..., axis] = sgn * one
            V[..., (axis + 1) % 3] = A * sgn
            V[..., (axis + 2) % 3] = B
            out.append(unit(V.reshape(-1, 3) @ R.T).reshape(N + 1, N + 1, 3))
    return out


def rand_rot(rng):
    q = rng.normal(size=4)
    q /= np.linalg.norm(q)
    w, x, y, z = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def shell_cards(layer, li, spec, line, rng, dmin=0.03, region_fn=region_of):
    """a continuous shell on the evaluated layer: a cube-sphere grid of rays (each layer turned at random, so
    no seam lines up through the layers), two quads per tile of a tileable coil cell"""
    f, tile_sz, _, cell, ao = spec["layers"][li]
    u0, v0, u1, v1 = CELLS[cell]
    e = 0.6 / 1024
    u0, v0, u1, v1 = u0 + e, v0 + e, u1 - e, v1 - e
    r = float(np.linalg.norm(layer.P - C, axis=1).mean())
    N = 2 * int(math.ceil(r * math.pi / 2 / tile_sz))
    cards = []
    for face in cube_dirs(N, rand_rot(rng)):
        D = face.reshape(-1, 3)
        S = C + D * skull_r(SK, *angles_of(D))[:, None]
        dd = line.dist(S).reshape(N + 1, N + 1)
        gap = layer.grid.interp(D, layer.h - H0).reshape(N + 1, N + 1)
        okv = dd > dmin
        if li:
            okv &= gap > 0.004 + 0.0075 * li
        P = np.full((N + 1, N + 1, 3), np.nan)
        for i in range(N + 1):
            for j in range(N + 1):
                if okv[i, j]:
                    h = layer.hit(face[i, j])
                    if h is not None:
                        P[i, j] = h
        Nn = layer.normal(D).reshape(N + 1, N + 1, 3)
        Lu = layer.lump_at(D).reshape(N + 1, N + 1)
        for i in range(N):
            for j in range(N):
                q = P[i:i + 2, j:j + 2]
                if np.isnan(q).any():
                    continue
                cd = Card(li, "shell")
                for (a, b) in ((0, 0), (1, 0), (1, 1), (0, 1)):
                    ii, jj = i + a, j + b
                    nn = Nn[ii, jj]
                    occ = ao * (1 + 0.06 * Lu[ii, jj]) * (1 - 0.22 * sstep(0.0, -0.7, nn[1]) * (1 - f * 0.5))
                    occ = float(np.clip(occ, 0.4, 1.0))
                    fu = ((i % 2) + a) / 2
                    fv = ((j % 2) + b) / 2
                    cd.P.append(P[ii, jj])
                    cd.N.append(nn)
                    cd.U.append((u0 + (u1 - u0) * fu, v0 + (v1 - v0) * fv))
                    cd.C.append((occ, occ, occ, 1.0))
                cd.T = [(0, 1, 2), (0, 2, 3)]
                cd.region = region_fn(unit(P[i:i + 2, j:j + 2].reshape(-1, 3).mean(axis=0) - C))
                cards.append(cd)
    return cards


def patch_cards(layer, li, spec, line, rng, prev=None, region_fn=region_of, band=None, params=None):
    """surface patches on a layer: 3 x 3 vertex grids ray-cast onto it, rotated, tilted, domed (band: only
    within that distance of the line)"""
    f, size, cover, cell, ao = params or spec["layers"][li]
    u0, v0, u1, v1 = CELLS[cell]
    ncand = 30000
    D = fib_dirs(ncand, 101 + li * 7 + len(spec["prefix"]))
    S = C + D * skull_r(SK, *angles_of(D))[:, None]
    dd = line.dist(S)
    # patch size shrinks toward the line (its visible cloud stays inside the hairline)
    s = np.minimum(size, np.maximum(SMIN, dd / 0.42))
    ok = dd > 0.42 * SMIN
    if band is not None:
        ok &= dd < band
    if prev is not None:
        # where the layers have converged toward the line, the layer under this one already covers it
        gap = layer.grid.interp(D, layer.h - H0)
        ok &= gap > 0.004 + 0.012 * li
    ok = ok & blue_noise(S, s * (0.62 / math.sqrt(cover)), ok, rng)
    cards = []
    for k in np.nonzero(ok)[0]:
        d = D[k]
        c = layer.hit(d)
        if c is None:
            continue
        n = layer.normal(d)[0]
        t1 = unit(np.cross(n, [0.0, 1.0, 0.0]) if abs(n[1]) < 0.95 else np.cross(n, [1.0, 0, 0]))
        t2 = np.cross(n, t1)
        phi = rng.uniform(0, TAU)
        e1 = t1 * math.cos(phi) + t2 * math.sin(phi)
        e2 = np.cross(n, e1)
        sk = s[k] * rng.uniform(0.85, 1.15)
        tilt = rng.normal(0, 0.07, 2)
        dome = rng.uniform(0.003, 0.008) * (0.4 + f)
        flip = rng.random(2) < 0.5
        cd = Card(li, "patch")
        okc = True
        grid_idx = {}
        for a in (-1, 0, 1):
            for b in (-1, 0, 1):
                q = c + (e1 * a + e2 * b) * sk * 0.5
                h = layer.hit(unit(q - C))
                if h is None:
                    okc = False
                    break
                qd = unit(h - C)
                nn = layer.normal(qd)[0]
                h = h + nn * ((tilt[0] * a + tilt[1] * b) * sk * 0.5 + dome * (1 - 0.5 * (a * a + b * b)))
                uu = (a + 1) / 2
                vv = (b + 1) / 2
                if flip[0]:
                    uu = 1 - uu
                if flip[1]:
                    vv = 1 - vv
                lu = float(layer.lump_at(qd)[0])
                occ = ao * (1 + 0.07 * lu) * (1 - 0.22 * sstep(0.0, -0.7, nn[1]) * (1 - f * 0.5))
                occ = float(np.clip(occ, 0.4, 1.0))
                grid_idx[(a, b)] = len(cd.P)
                cd.P.append(h)
                cd.N.append(nn)
                cd.U.append((u0 + (u1 - u0) * uu, v0 + (v1 - v0) * vv))
                cd.C.append((occ, occ, occ, 1.0))
            if not okc:
                break
        if not okc:
            continue
        for a in (-1, 0):
            for b in (-1, 0):
                i00, i10 = grid_idx[(a, b)], grid_idx[(a + 1, b)]
                i11, i01 = grid_idx[(a + 1, b + 1)], grid_idx[(a, b + 1)]
                cd.T.append((i00, i10, i11))
                cd.T.append((i00, i11, i01))
        cd.region = region_fn(unit(c - C))
        cards.append(cd)
    return cards


def strand_card(cd, pts, widths, side, normal, strip, v0, v1, occ):
    """a two-sided strip card along pts (root first) in the plane of the strand and `side`"""
    n = len(pts)
    u0, u1 = strip
    rows = []
    for i, p in enumerate(pts):
        t = i / (n - 1)
        v = v0 + (v1 - v0) * t
        o = occ(t)
        hw = widths[i] * 0.5
        a = len(cd.P)
        cd.P += [p - side * hw, p + side * hw]
        cd.N += [normal, normal]
        cd.U += [(u0, v), (u1, v)]
        cd.C += [(o, o, o, 1.0), (o, o, o, 1.0)]
        rows.append((a, a + 1))
    for i in range(n - 1):
        a, b = rows[i]
        c, d = rows[i + 1][1], rows[i + 1][0]
        cd.T += [(a, d, c), (a, c, b), (a, c, d), (a, b, c)]


def fin_cards(layer, li, spec, line, rng, region_fn=region_of):
    """fuzz fins standing out of the outer layer (two-sided, outward shading normals)"""
    fs = spec["fins"]
    D = fib_dirs(fs["n"] * 6, 977 + len(spec["prefix"]))
    S = C + D * skull_r(SK, *angles_of(D))[:, None]
    dd = line.dist(S)
    ok = np.nonzero(dd > 0.07)[0]
    rng.shuffle(ok)
    cards = []
    for k in ok:
        if len(cards) >= fs["n"]:
            break
        d = D[k]
        c = layer.hit(d)
        if c is None:
            continue
        n = layer.normal(d)[0]
        t1 = unit(np.cross(n, [0.0, 1.0, 0.0]) if abs(n[1]) < 0.95 else np.cross(n, [1.0, 0, 0]))
        t2 = np.cross(n, t1)
        phi = rng.uniform(0, TAU)
        tang = t1 * math.cos(phi) + t2 * math.sin(phi)
        lean = rng.uniform(0.4, 1.1)
        g = np.array([0, -1.0, 0])
        dirv = unit(n + tang * lean + g * 0.12)
        L = rng.uniform(*fs["length"])
        w = rng.uniform(*fs["width"])
        root = c - n * fs["sink"]
        bend = unit(np.cross(dirv, np.cross(g, dirv)) + 1e-6) if abs(dirv[1]) < 0.98 else tang
        pts = [root + dirv * L * t + bend * (L * 0.1 * t * t) for t in (0.0, 1.0)]
        psi = rng.uniform(0, TAU)
        tv = t1 * math.cos(psi) + t2 * math.sin(psi)
        side = unit(tv - dirv * np.dot(tv, dirv))
        cd = Card(li + 1, "fin")
        strand_card(cd, pts, [w, w * 0.85], side, n, fs["cell"], 0.5, 1.0,
                    lambda t: float(np.clip(0.9 + 0.1 * t, 0.4, 1)))
        cd.region = region_fn(unit(c - C))
        cards.append(cd)
    return cards


def scalp_normal(p):
    th, az = Skull.angles(p - C)
    return SK.normal(th, az)


def edge_cards(line, spec, rng, step=0.0135):
    """short tufts rooted along the line, growing up and back out of it: sparse and short at the line,
    denser and longer behind it"""
    cards = []
    hs = H0 - 0.008
    for poly in line.polys[:2]:
        P = np.asarray(poly)
        seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
        acc = np.concatenate([[0], np.cumsum(seg)])
        total = acc[-1]
        ns = int(total / step)
        for row, (d0, keep, Lr, wr) in enumerate(((0.006, 0.55, (0.022, 0.034), (0.02, 0.028)),
                                                  (0.02, 0.85, (0.032, 0.05), (0.026, 0.034)),
                                                  (0.038, 1.0, (0.045, 0.065), (0.03, 0.04)))):
            for k in range(ns):
                if rng.random() > keep:
                    continue
                s = (k + rng.uniform(0.1, 0.9)) / ns * total
                i = min(len(P) - 2, int(np.searchsorted(acc, s) - 1))
                tl = (s - acc[i]) / max(seg[i], 1e-9)
                q = P[i] + (P[i + 1] - P[i]) * tl
                tang = unit(P[i + 1] - P[i])
                n = scalp_normal(q)
                g = unit(np.cross(n, tang))
                if line.dist((q + g * 0.02)[None])[0] < line.dist((q - g * 0.02)[None])[0]:
                    g = -g
                dcur = d0 + rng.uniform(-0.004, 0.006)
                root = q + g * dcur
                root, _, _ = SK.project(root, hs)
                if line.dist(root[None])[0] < 0.003:
                    continue
                # the tuft rises out of the line, up and back over the scalp (never down over the face)
                alpha = math.radians(rng.uniform(14, 32))
                L = rng.uniform(*Lr)
                w = rng.uniform(*wr)
                g2 = rot(g, n, rng.normal(0, 0.45))
                dirv = unit(g2 * math.cos(alpha) + n * math.sin(alpha))
                pts = []
                ts = (0.0, 1.0) if row < 2 else (0.0, 0.5, 1.0)
                for t in ts:
                    p = root + dirv * L * t
                    hp = SK.height(p)
                    if hp < hs:
                        p, _, _ = SK.project(p, hs)
                    pts.append(p)
                if any(in_ear(p) for p in pts):
                    continue
                side = unit(np.cross(dirv, n))
                cd = Card(1, "edge")  # drawn over the root shell and its patches (they grow out through it)
                o0 = 0.5 + 0.08 * row
                strand_card(cd, pts, [w, w, w * 0.85][-len(pts):], side, n, FIN_T, 0.5, 0.97,
                            lambda t, o0=o0: o0 + (0.9 - o0) * t)
                cd.region = "base"
                cards.append(cd)
    return cards


# =============================================================================================== pieces
def card_min_height(cd):
    return float(skull_height(SK, np.asarray(cd.P)).min())


def make_pieces(spec, cards, names):
    """cards -> hairlib Pieces: base (unscaled), mass by region (volume), clumps (bounce)"""
    groups = {}
    for cd in cards:
        if cd.kind == "edge" or card_min_height(cd) < VOL_MIN:
            key = "base"
        elif cd.layer >= len(spec["layers"]) - 1 and cd.region in names["clump"]:
            key = "clump:" + cd.region
        else:
            key = "mass:" + cd.region
        groups.setdefault(key, []).append(cd)
    pieces = []
    order = ["base"] + ["mass:" + r for r in names["mass"]] + ["clump:" + r for r in names["clump"]]
    for key in order:
        cs = groups.get(key)
        if not cs:
            continue
        # innermost layer first (scalp side first), patches before fins / tufts of the same layer
        kind_rank = {"shell": 0, "patch": 1, "edge": 2, "fin": 3}
        cs.sort(key=lambda c: (c.layer, kind_rank[c.kind]))
        if key == "base":
            name = names["base"]
            meta = dict(length=None, castShadow=True)
        elif key.startswith("mass:"):
            name = names["mass"][key[5:]]
            meta = dict(length="volume", castShadow=True)
        else:
            name = names["clump"][key[6:]]
            meta = dict(length="volume", castShadow=False)
        p = Piece(name, "coily", material="Fabric", hideUnder={"headgear": True, "hood": True}, **meta)
        for cd in cs:
            cd.to_piece(p)
        if key.startswith("clump:"):
            P = np.asarray(p.P)
            tip = P.mean(axis=0)
            piv, _, _ = SK.project(tip, 0.0)
            p.meta["hairfx"] = {"kind": "bounce", "stiff": 0.85, "mass": 1.2,
                                "pivot": [round(float(x), 4) for x in piv], "tip": [round(float(x), 4) for x in tip]}
        pieces.append(p)
    return pieces


# =============================================================================================== clearance
def load_head(path):
    import render
    md = render.load_obj(path)["Head"]
    P = md["p"].reshape(-1, 3)
    T = md["t"].reshape(-1, 3)
    return P, T, BVHTree.FromPolygons([tuple(p) for p in P], [tuple(int(i) for i in t) for t in T])


def head_dist(bvh, P):
    out = np.empty(len(P))
    for i, p in enumerate(P):
        loc, nrm, idx, dist = bvh.find_nearest(Vector(tuple(p)))
        if loc is None:
            out[i] = 1.0
            continue
        # (the nearest face's normal is trusted close to the surface only: far out it can be a fold's back)
        out[i] = dist if (dist > 0.08 or np.dot(p - np.array(loc), np.array(nrm)) >= 0) else -dist
    return out


def measure_fit(sk, xs=1.0):
    """the runtime skull fit's extents on a radial table (CONTRACT): W at y 0.15 toward +X, T straight up,
    Fz at y 0.2 toward -Z, Bz at y 0.1 toward +Z (xs: the table squeezed in x)"""
    cz, cy = float(sk.c[2]), float(sk.c[1])

    def h(p):
        q = np.array([p[0] / xs, p[1], p[2]])
        return sk.height(q)

    def cross(o, dv):
        lo, hi = 0.0, 1.6
        for _ in range(50):
            m = (lo + hi) / 2
            if h(o + dv * m) < 0:
                lo = m
            else:
                hi = m
        return (lo + hi) / 2

    W = cross(np.array([0, 0.15, cz]), np.array([1.0, 0, 0]))
    T = cy + cross(np.array([0, cy, cz]), np.array([0, 1.0, 0]))
    Fz = cz - cross(np.array([0, 0.2, cz]), np.array([0, 0, -1.0]))
    Bz = cz + cross(np.array([0, 0.1, cz]), np.array([0, 0, 1.0]))
    return W, T, Fz, Bz


def fit_of(sk, xs=1.0):
    W0, T0, F0, B0 = measure_fit(SK)
    W, T, Fz, Bz = measure_fit(sk, xs)
    return np.array([W / W0, T / T0, (Bz - Fz) / (B0 - F0)]), (Bz + Fz) / 2 - (B0 + F0) / 2


class Clearance:
    def __init__(self):
        self.hm = load_head(os.path.join(REF, "head_m.obj"))
        self.hf = load_head(os.path.join(REF, "head_f.obj"))
        self.fit_f = fit_of(SKF)
        self.fit_n = fit_of(SK, 0.965)

    def apply(self, P, fit):
        s, dz = fit
        Q = P * s
        Q[:, 2] += dz
        return Q

    def heights(self, P):
        """per vertex: male table, male head mesh, female table (fit), female head mesh (fit), male narrow"""
        Pf = self.apply(P, self.fit_f)
        Pn = self.apply(P, self.fit_n)
        hn = skull_height(SK, Pn / np.array([0.965, 1, 1]))  # (radially close enough: a 3.5% squeeze)
        return {
            "skull_m": skull_height(SK, P),
            "head_m": head_dist(self.hm[2], P),
            "skull_f": skull_height(SKF, Pf),
            "head_f": head_dist(self.hf[2], Pf),
            "skull_m_narrow": hn,
        }

    def enforce(self, pieces, passes=3):
        """push any vertex closer than CLEAR outward along its ray from the skull centre"""
        for _ in range(passes):
            moved = 0
            for p in pieces:
                P = np.asarray(p.P)
                H = self.heights(P)
                low = np.min(np.stack(list(H.values())), axis=0)
                bad = low < CLEAR
                if not bad.any():
                    continue
                D = unit(P - C)
                P[bad] += D[bad] * (CLEAR - low[bad] + 0.003)[:, None]
                p.P = [tuple(map(float, q)) for q in P]
                moved += int(bad.sum())
            if not moved:
                break
        return self.report(pieces)

    def report(self, pieces):
        out = {}
        for p in pieces:
            H = self.heights(np.asarray(p.P))
            for k, v in H.items():
                out[k] = round(min(out.get(k, 9.0), float(v.min())), 4)
        return out

    def volume_check(self, pieces, factors=(0.8, 1.3)):
        """the runtime's volume placement (HairAssetKit.Place: about the scalp point under the piece's bbox
        centre, evenly by kc in [0.94, 1.10], then the rest per axis) -> min heights of the volume pieces"""
        res = {}
        S = {"cx": 0.0, "cy": float(C[1]), "cz": float(C[2])}
        for Vf in factors:
            worst = {}
            for p in pieces:
                if p.meta.get("length") != "volume":
                    continue
                P = np.asarray(p.P)
                lo, hi = P.min(axis=0), P.max(axis=0)
                b = (lo + hi) / 2
                d = b - np.array([S["cx"], S["cy"], S["cz"]])
                dn = d / np.linalg.norm(d)
                A, _, _ = SK.project(C + dn, 0.0)
                kc = min(max(Vf, 0.94), 1.10)
                ko = Vf / kc - 1
                w = 1 / max(dn * dn)
                Q = A + (P - A) * kc
                Q = A + (Q - A) * (1 + ko * dn * dn * w)
                H = self.heights(Q)
                for k, v in H.items():
                    worst[k] = round(min(worst.get(k, 9.0), float(v.min())), 4)
            res[str(Vf)] = worst
        return res


# =============================================================================================== build
def build_style(key, spec, clr, rng_seed=7):
    t0 = time.time()
    clear_scene()
    rng = np.random.default_rng(rng_seed + len(key) * 13)
    line = natural_line() if spec["line"] == "natural" else hightop_line()
    grid = Grid(line)
    H, span = thickness(spec, grid)
    c_layers = coll("Layers (card guides, modifiers live)")
    texs = [make_texture("BroadLumps", "CLOUDS", 0.24, 2), make_texture("CurlClusters", "CLOUDS", 0.075, 1)]
    layers = [Layer(i, L[0], spec, grid, H, span, c_layers, texs) for i, L in enumerate(spec["layers"])]
    cards = []
    for li, layer in enumerate(layers):
        cards += shell_cards(layer, li, spec, line, rng)
    # the shells' edges near the line hide under small cloud patches (and the tufts over them)
    for li, prm in spec["band"]:
        cards += patch_cards(layers[li], li, spec, line, rng, None, band=0.13, params=prm)
    cards += fin_cards(layers[-1], len(layers) - 1, spec, line, rng)
    cards += edge_cards(line, spec, rng)
    # cards whose vertices reach into an ear's box are dropped
    cards = [c for c in cards if not any(in_ear(np.asarray(p)) for p in c.P)]
    pre = spec["prefix"]
    names = {"base": pre + "01",
             "mass": {"front": pre + "02", "top": pre + "03", "back": pre + "04", "left": pre + "05", "right": pre + "06"},
             "clump": {"top": "HairClump01", "back": "HairClump02", "left": "HairClump03", "right": "HairClump04"}}
    cnt = {}
    for c in cards:
        k = f"{c.kind}{c.layer}"
        cnt[k] = cnt.get(k, 0) + len(c.T)
    print("tris by card kind/layer", cnt, flush=True)
    pieces = make_pieces(spec, cards, names)
    cl = clr.enforce(pieces)
    vol = clr.volume_check(pieces)
    for L in layers:
        L.ob.hide_set(True)
        L.ob.hide_render = True
    print(f"{key}: {len(cards)} cards, {sum(p.nt for p in pieces)} tris, clearance {cl} ({time.time() - t0:.1f}s)",
          flush=True)
    return pieces, cl, vol, layers


def export(key, spec, pieces, cl, vol):
    d = os.path.join(hl.OUT, key)
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.endswith(".mesh") or f == "style.json":
                os.remove(os.path.join(d, f))
    entry = {"styles": spec["styles"], "types": spec["types"], "cap": spec["cap"], "family": "afro",
             "notes": spec["notes"],
             "checks": {"clearance": cl, "volume": vol, "clear_min": CLEAR}}
    return hl.export_style(key, entry, pieces)


def save_blend(key, pieces):
    """the layers (with live modifiers), the exported pieces (textured) and the reference head"""
    tex_path = os.path.join(TEX_DIR, "hair_coily.png")
    mat = bpy.data.materials.new("hair_coily")
    mat.use_nodes = True
    nt = mat.node_tree
    bs = nt.nodes["Principled BSDF"]
    img = bpy.data.images.load(tex_path, check_existing=True)
    img.alpha_mode = "STRAIGHT"
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
    nt.links.new(mix.outputs[2], bs.inputs["Base Color"])
    nt.links.new(tx.outputs[1], bs.inputs["Alpha"])
    bs.inputs["Roughness"].default_value = 0.8
    mat.blend_method = "HASHED"
    c = coll("Pieces (exported, game nominal space: +Y up)")
    for p in pieces:
        hl.to_blender(p, bpy, material=mat, collection=c)
    import render
    md = render.load_obj(os.path.join(REF, "head_m.obj"))["Head"]
    ch = coll("Reference head (head_m)")
    mesh_obj("head_m", md["p"].reshape(-1, 3), md["t"].reshape(-1, 3), ch)
    os.makedirs(BLEND_DIR, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND_DIR, f"{key}.blend"), compress=True)


# =============================================================================================== renders
def read_mesh_v2(path, name):
    with open(path, "rb") as f:
        data = f.read()
    i = data.index(b"\n") + 1
    hs, vs, fs, nv, nt = struct.unpack_from("<HBBII", data, i)
    i += hs
    p = Piece(name, "cap")
    for k in range(nv):
        x, y, z, nx, ny, nz, u, v = struct.unpack_from("<3f3f2f", data, i + k * vs)
        r, g, b, a = struct.unpack_from("<4B", data, i + k * vs + 36)
        p.vert((x, y, z), (nx, ny, nz), (u, v), (r / 255, g / 255, b / 255, a / 255))
    i += nv * vs
    for k in range(nt):
        p.tri(*struct.unpack_from("<3I", data, i + k * fs))
    return p


def grid_at(g, theta, az):
    th_ = np.radians(np.asarray(SKD["radial"]["thetas"], np.float64))
    az_ = np.radians(np.asarray(SKD["radial"]["azimuths"], np.float64))
    th = np.clip(theta, th_[0], th_[-1])
    dth = th_[1] - th_[0]
    fi = th / dth
    i0 = np.clip(np.floor(fi).astype(int), 0, len(th_) - 2)
    ti = fi - i0
    n = len(az_)
    fa = (az % TAU) / (TAU / n)
    j0 = np.floor(fa).astype(int) % n
    tj = fa - np.floor(fa)
    j1 = (j0 + 1) % n
    a = g[i0, j0] * (1 - tj) + g[i0, j1] * tj
    b = g[i0 + 1, j0] * (1 - tj) + g[i0 + 1, j1] * tj
    return a * (1 - ti) + b * ti


def paint_cap(kind, out, density=1.0, size=1024):
    """the game's painted cap (HairAssetKit.PaintCap, as tools/hair/build_fades.py does it): the shortcoil tile
    repeated over the cap's polar UV, kept by rank as the cut's coverage falls (skull.json Kit.Cut grid)"""
    from PIL import Image
    capj = json.load(open(os.path.join(hl.OUT, "cap", "style.json")))
    th_max = capj["thetaMax"]
    nu, nv = capj["tile"]
    tile8 = np.asarray(Image.open(os.path.join(TEX_DIR, "hair_shortcoil.png")).convert("RGBA"))
    key = tile8[..., 3].astype(np.int64) * 256 + tile8[..., 0].astype(np.int64)
    flat = key.ravel()
    hist = np.bincount(flat, minlength=65536).astype(np.float64)
    below = np.cumsum(hist) - hist
    rank = ((below + hist * 0.5) / flat.size)[key]
    tile = tile8.astype(np.float64) / 255
    th_, tw_ = tile.shape[:2]
    j, i = np.mgrid[0:size, 0:size]
    u = (i + 0.5) / size
    v = (j + 0.5) / size
    cov = np.asarray(SKD["fades"]["coverage"][kind], np.float64)
    c = np.clip(grid_at(cov, v * th_max, u * TAU), 0, 1) * density
    tu = ((u * nu * tw_) % tw_).astype(int)
    tv = ((v * nv * th_) % th_).astype(int)
    K = 4
    inv = 1.0 / K
    t = np.where(c >= 1, -inv, (1 - c) * (1 + inv) - inv)
    q = np.clip((rank[tv, tu] - t) * K, 0, 1)
    keep = np.where(c <= 0.002, 0.0, q * q * (3 - 2 * q))
    g = tile[tv, tu, 0]
    a = tile[tv, tu, 3] * keep
    Image.fromarray((np.dstack([g, g, g, a]) * 255 + 0.5).astype(np.uint8), "RGBA").save(out)
    return out


HAIR_TINTS = {"black": (0.09, 0.08, 0.075), "darkbrown": (48 / 255, 33 / 255, 24 / 255),
              "blonde": (196 / 255, 156 / 255, 92 / 255)}
SKINS = {"mid": (0.42, 0.26, 0.17), "deep": (0.2, 0.12, 0.08), "light": (0.7, 0.5, 0.38)}
LOOKS = {  # name -> head, torso, skin, hair tint, female
    "m_black": ("head_m", "torso_m", "mid", "black", False),
    "m_darkbrown": ("head_m", "torso_m", "deep", "darkbrown", False),
    "f_darkbrown": ("head_f", "torso_f", "light", "darkbrown", True),
    "m_blonde": ("head_m", "torso_m", "light", "blonde", False),
}
VIEWS = {  # name -> (render view, dist, focus)
    "34": ("34", 3.9, (0.0, 0.17, 0.03)),
    "side": ("side", 3.9, (0.0, 0.17, 0.03)),
    "back": ("back", 3.9, (0.0, 0.17, 0.03)),
    "close": ("front", 1.75, (0.0, 0.3, 0.0)),
    "close34": ((32, 3, 1.0), 2.3, (0.0, 0.26, 0.0)),
    "top34": ("top34", 3.9, (0.0, 0.2, 0.03)),
}


def fabric(mat):
    """Roblox Fabric (what the pieces use): matte, no sheen (render.py's hair material is a little glossy)"""
    if mat.get("fabric"):
        return
    bs = mat.node_tree.nodes["Principled BSDF"]
    bs.inputs["Roughness"].default_value = 0.92
    bs.inputs["Specular IOR Level"].default_value = 0.12
    bs.inputs["Anisotropic"].default_value = 0.0
    mat["fabric"] = 1


def cull_backfaces(mat):
    """Roblox draws one side of a triangle: the back side transparent (Cycles: Geometry.Backfacing)"""
    if mat.get("culled"):
        return
    nt = mat.node_tree
    out = nt.nodes["Material Output"]
    bs = nt.nodes["Principled BSDF"]
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(geo.outputs["Backfacing"], mix.inputs[0])
    nt.links.new(bs.outputs[0], mix.inputs[1])
    nt.links.new(tr.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    mat["culled"] = 1


def render_style(key, spec, pieces, looks, views, res, samples, cull=True, vol=None, tag=""):
    import render
    os.makedirs(FAM_DIR, exist_ok=True)
    capP = read_mesh_v2(os.path.join(hl.OUT, "cap", "HairCap.mesh"), "HairCap")
    capimg = paint_cap(spec["cover"], os.path.join(FAM_DIR, f"cap_{spec['cover']}.png"))
    tex = os.path.join(TEX_DIR, "hair_coily.png")
    clr_fit = fit_of(SKF)
    paths, labels = [], []
    for look in looks:
        head, torso, skin, tint_name, female = LOOKS[look]
        tint = HAIR_TINTS[tint_name]
        s, dz = (clr_fit if female else (np.ones(3), 0.0))
        sc = render.Scene(res=res, samples=samples)
        render.add_obj(sc, os.path.join(REF, f"{head}.obj"), tint=SKINS[skin])
        render.add_obj(sc, os.path.join(REF, f"{torso}.obj"), tint=SKINS[skin])
        off = (0, 0, dz)
        ob = sc.add_piece(capP, texture=capimg, tint=tint, offset=off, scale=tuple(s))
        if cull:
            cull_backfaces(ob.data.materials[0])
        for p in pieces:
            P = p
            if vol is not None and p.meta.get("length") == "volume":
                P = volume_placed(p, vol)
            ob = sc.add_piece(P, texture=tex, tint=tint, offset=off, scale=tuple(s))
            if cull:
                cull_backfaces(ob.data.materials[0])
                fabric(ob.data.materials[0])
        for v in views:
            view, dist, focus = VIEWS[v]
            fn = os.path.join(FAM_DIR, f"{key}{tag}_{look}_{v}.png")
            sc.render(fn, view=view, dist=dist, focus=focus)
            paths.append(fn)
            labels.append(f"{look} {v}")
    return paths, labels


def volume_placed(p, Vf):
    P = np.asarray(p.P)
    lo, hi = P.min(axis=0), P.max(axis=0)
    b = (lo + hi) / 2
    dn = unit(b - C)
    A, _, _ = SK.project(C + dn, 0.0)
    kc = min(max(Vf, 0.94), 1.10)
    ko = Vf / kc - 1
    w = 1 / max(dn * dn)
    Q = A + (P - A) * kc
    Q = A + (Q - A) * (1 + ko * dn * dn * w)
    q = Piece(p.name, p.tex, **p.meta)
    q.P = [tuple(x) for x in Q]
    q.N, q.U, q.C, q.T = p.N, p.U, p.C, p.T
    return q


# =============================================================================================== main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--no-tex", action="store_true")
    ap.add_argument("--render", action="store_true")
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--views", default="")
    ap.add_argument("--looks", default="")
    ap.add_argument("--stock", action="store_true", help="also one stock-material, all-triangles view")
    ap.add_argument("--volume", default="", help="also render at these volume factors, e.g. 0.8,1.3")
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    t0 = time.time()
    if not args.no_tex:
        L, A = afro_tex.tex_coily()
        afro_tex.save(os.path.join(TEX_DIR, "hair_coily.png"), L, A)
        print(f"texture coily: 1024x1024 ({time.time() - t0:.1f}s)", flush=True)
    clr = Clearance()
    print("female fit", clr.fit_f, "narrow fit", clr.fit_n, flush=True)
    only = [k for k in args.only.split(",") if k] or list(STYLES)
    report = {}
    built = {}
    for key in only:
        spec = STYLES[key]
        pieces, cl, vol, layers = build_style(key, spec, clr)
        data = export(key, spec, pieces, cl, vol)
        save_blend(key, pieces)
        report[key] = {"tris": data["tris"], "pieces": {p.name: {"tris": p.nt, "length": p.meta.get("length"),
                                                                 "hairfx": p.meta.get("hairfx")} for p in pieces},
                       "clearance": cl, "volume": vol}
        built[key] = pieces
    print(f"build done in {time.time() - t0:.1f}s", flush=True)
    print(json.dumps(report, indent=1))
    if args.render:
        import render
        res, samples = ((300, 360), 12) if args.quick else ((520, 620), 48)
        looks = [x for x in args.looks.split(",") if x] or ["m_black", "m_darkbrown", "f_darkbrown"]
        views = [x for x in args.views.split(",") if x] or ["34", "side", "back", "close", "close34", "top34"]
        for key in only:
            paths, labels = render_style(key, STYLES[key], built[key], looks, views, res, samples)
            tag = "_quick" if args.quick else ""
            out = os.path.join(FAM_DIR, f"sheet_{key}{tag}.jpg")
            render.sheet(paths, out, cols=len(views), labels=labels,
                         title=f"{key}: {', '.join(STYLES[key]['styles'])} "
                               f"[{'/'.join(STYLES[key]['types']) if STYLES[key]['types'] else 'all types'}] "
                               f"{report[key]['tris']} tris + shared cap")
            print("sheet", out, flush=True)
            if args.stock:
                p2, l2 = render_style(key, STYLES[key], built[key], [looks[0]], ["34"], res, samples, cull=False,
                                      tag="_stock")
                print("stock", p2, flush=True)
            for vf in [float(x) for x in args.volume.split(",") if x]:
                p3, l3 = render_style(key, STYLES[key], built[key], [looks[0]], ["34", "side"], res, samples,
                                      vol=vf, tag=f"_vol{vf}")
                print("volume", p3, flush=True)
    return report


if __name__ == "__main__":
    main()
