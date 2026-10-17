"""Afro family hair cards: "Afro" (Kinky / Coiled and the Straight / Wavy afro the generated hair treats as
Kinky; its Curly variant as a second entry) and the "High Top". Modelled in Blender (bpy 4.2), exported with
hairlib (see CONTRACT.md).

    /opt/bpyenv/bin/python tools/hair/build_afro.py [--only afro,afro_curly,hightop] [--no-tex]
                                                    [--render] [--quick] [--views 34,side] [--looks m_black]
                                                    [--stock] [--volume 0.8,1.3] [--dye Tips]

Writes tools/hair/textures/hair_coily.png (afro_tex.py), tools/hair/out/<key>/ (meshes + style.json),
tools/hair/blend/<key>.blend; with --render, Cycles self-check renders and one sheet per style in FAM_DIR.

How a style is built (game nominal head space, numerically):
* Envelope: the style's outer surface as a thickness field H over the scalp (rays from the skull centre).
  Afro: an egg, fullest at the top-back and over the sides, the front held back; it rolls down to the
  natural hairline (a rounded, quarter-circle-like ease, no shelf), and over the ears comes down at full
  thickness to just above the ear tops before rounding under into the sideburn; fuller over the sides
  (y 0.2-0.5) and at the upper back. High top: a rounded-rectangle
  column (slightly barrel-curved, tapering a little toward its top, raked forward) with a flat top sloping
  down to the back and a fairly crisp edge; it grows out of the high fade: from cap height at the fade's top
  line the thickness lengthens smoothly (zero slope at the line) over ~0.2 of height, no foot ring.
* Layers: each nested layer (a fraction f of H) is a Blender mesh (a polar grid on the scalp) with modifiers:
  two Displace modifiers on Clouds textures (broad asymmetric lumps, then curl-cluster lumps; the layers
  from f 0.5 out take the same lumps, so they move in parallel and a trough never shows the core), weighted
  by a vertex group that fades them out toward the hairline, and a Smooth. The evaluated layers become BVH
  trees.
* Shells: each layer is covered by a continuous shell of quads on a cube-sphere grid of rays from the skull
  centre (each layer turned at random), ray-cast onto the evaluated layer, 4 quads per repeat of a tileable
  coil tile (dense tile inside, sparse tiles outside). At the shell's edge near the line a quad's outside
  corners are pulled in along the quad to the edge (no stair steps, no holes); the high top's sparse
  outer shells start at the fade's top line (along a ragged line), the dense core further up under them, so
  coverage builds up out of the fade with no dark rim at the foot.
* Occlusion (vertex colour) from each vertex's depth under the outer surface (gentle: ~0.94 at the surface,
  >= ~0.66 in the core), a little darker in curl-cluster valleys and underneath; shading normals are the
  layer's outward normals, biased up a little.
* Texture (afro_tex.py): every cell in the atlas's bottom quarter (v 0.75-1), the outer tiles in the bottom
  eighth: the game dyes by v (Tips / Ombre), and an afro shows all its layers, so all of it takes the dye alike
  (no undyed core blotches, no undyed band at the hairline); the core is darker by its own albedo.
* Hairline: small soft coil-cloud patches on the outer layer within ~0.1 of the line (drawn over every
  shell's edge), short tufts rooted along the line growing up and back (not along the sideburns), over the
  shared scalp cap (entry cap). Fins: fuzz cards rooted under the outer layer, laid 25-50 degrees off it and
  curving round it, facing outward.
* Pieces: the root (unscaled, length null): layers 0-1, every shell within 0.09 of the line, the hairline
  patches and tufts; the mass by region (front, top, back, left, right; length "volume"): every layer from 2
  out, so the whole mass scales with the slider; bounce clumps (HairClump01-04, volume + bounce): round
  patches of the outermost shell with their fins, cut out of the mass (the shells under them stay whole).
  Cards low on the sides, behind the ears and at the nape (centre y < LOW_Y) stay in the root piece (scaled,
  they would swing out under the mass at the slider's extremes); no fins there.
* Clearance: every vertex at least CLEAR over the male skull table and the head mesh (head_m.obj), and,
  through the runtime skull fit, over the female skull table and head_f.obj; the volume pieces also at the
  slider's extremes (0.8, 1.3) through the runtime's volume transform.
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
EAR_PAD = 0.022
SMIN = 0.08  # smallest surface patch (near the line)
CELLS = afro_tex.CELLS
FIN_T = CELLS["FIN_T"]
FIN_L = CELLS["FIN_L"]

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
    """an egg (pseudo-distance, < 0 inside): fullest at the top-back and over the sides, narrower below, the
    front held back (the mass sits behind the forehead line and rolls down to it rather than shelving over it)"""
    E = np.array([0.0, 0.2, 0.1])

    def F(P):
        x, y, z = P[:, 0], P[:, 1] - E[1], P[:, 2] - E[2]
        nar = 1 - 0.14 * sstep(0.05, -0.45, y)
        side = 0.05 * sstep(-0.15, 0.1, y) * sstep(0.55, 0.3, y)  # fuller over the sides (y 0.2-0.5 nominal)
        back = 0.04 * sstep(-0.1, 0.15, y)  # and the upper back
        rx = (0.235 + 0.39 * scale + side) * nar
        ry = np.where(y > 0, 0.41 + 0.27 * scale, 0.45 + 0.2 * scale)
        rz = np.where(z > 0, 0.48 + 0.24 * scale + back, 0.42 + 0.18 * scale) * nar
        return np.sqrt((x / rx) ** 2 + (y / ry) ** 2 + (z / rz) ** 2) - 1

    return F


def smax(a, b, k):
    h = np.clip(0.5 - 0.5 * (b - a) / k, 0, 1)
    return a * h + b * (1 - h) + k * h * (1 - h)


def smin(a, b, k):
    return -smax(-a, -b, k)


def hightop_sdf():
    """the high top's column: a rounded-rectangle section (a little barrel-curved, tapering slightly toward the
    top), raked forward a touch, with a flat top that slopes down from the front to the back and a fairly crisp,
    rounded edge (the Displace lumps break it up). Its foot is not modelled here: the thickness ramps up out of
    the fade (thickness())"""
    yb, y1 = 0.25, 0.87

    def F(P):
        x, y, z = P[:, 0], P[:, 1], P[:, 2]
        k = np.clip((y - yb) / (y1 - yb), 0, 1)
        barrel = 0.018 * np.sin(math.pi * k)
        hx = 0.455 + barrel - 0.05 * k
        hz = 0.53 + barrel - 0.045 * k
        cz = 0.05 - 0.055 * k
        ax, az_ = np.abs(x) / hx, np.abs(z - cz) / hz
        p = 2.5
        r = (ax ** p + az_ ** p) ** (1 / p)
        d_side = (r - 1) * np.minimum(hx, hz)
        ytop = 0.855 + 0.045 * np.clip(-(z - cz) / hz, -1, 1)
        d_top = y - ytop
        return smax(d_side, d_top, 0.085)

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
# layers: (f = fraction of the envelope thickness, shell tile). Shell occlusion comes from each vertex's depth
# under the outer surface (not from the layer index): where the layers converge toward the line every layer is
# near the surface and light, so no dark rim forms there.
STYLES = {
    "afro": dict(
        styles=["Afro"], types=["Kinky", "Coiled", "Straight", "Wavy"], cap={"cut": "full", "density": 1},
        cover="none", line="natural", shape="afro", scale=1.0, prefix="HairAfro",
        layers=[(0.0, "TILE_D"), (0.3, "TILE_D"), (0.55, "TILE_D"), (0.74, "TILE_S2"), (0.87, "TILE_S"),
                (1.0, "TILE_S")],
        band=[(0, (0.0, 0.12, 1.6, "CLOUD_A")), (1, (0.3, 0.12, 1.2, "CLOUD_A"))],
        fins=dict(n=420, cell=FIN_T, length=(0.05, 0.08), width=(0.04, 0.055), sink=0.03, angle=(28, 50)),
        puffs=dict(radius=0.17),
        lumps=(0.08, 0.032), span=(0.24, 0.22, 0.27, 0.24), edge=True, notes="rounded afro"),
    "afro_curly": dict(
        styles=["Afro"], types=["Curly"], cap={"cut": "full", "density": 1},
        cover="none", line="natural", shape="afro", scale=0.88, prefix="HairAfro",
        layers=[(0.0, "TILE_D"), (0.32, "TILE_D"), (0.6, "TILE_D"), (0.8, "TILE_S2"), (1.0, "TILE_L")],
        band=[(0, (0.0, 0.12, 1.6, "CLOUD_A")), (1, (0.32, 0.12, 1.2, "CLOUD_A"))],
        fins=dict(n=380, cell=FIN_L, length=(0.06, 0.09), width=(0.05, 0.07), sink=0.03, angle=(30, 50)),
        puffs=dict(radius=0.17),
        lumps=(0.085, 0.045), span=(0.24, 0.22, 0.27, 0.24), edge=True,
        notes="curly afro: looser curl surface, bigger curl clusters"),
    "hightop": dict(
        styles=["High Top"], types=None, cap={"cut": "style", "density": 1},
        cover="high", line="hightop", shape="hightop", prefix="HairTop",
        layers=[(0.0, "TILE_D"), (0.35, "TILE_D"), (0.62, "TILE_D"), (0.8, "TILE_S2"), (0.91, "TILE_S"),
                (1.0, "TILE_S")],
        band=[], stagger=True, edge_jitter=0.022,
        fins=dict(n=300, cell=FIN_T, length=(0.04, 0.06), width=(0.035, 0.045), sink=0.02, angle=(25, 45),
                  above=0.13, gravity=0.0),
        puffs=None, edge_fade=False,
        lumps=(0.058, 0.026), span=(0.06, 0.1, 0.2, 0.2), edge=True,
        notes="high top: a column grown out of a high fade"),
}

# per tile cell: (world size of one repeat in u, quads per repeat in u, in v): square quads, ~1200 px / stud
# on the outer tiles (384 x 192 px -> 0.32 x 0.16), half that on the dense core (128 x 192 px -> 0.2 x 0.3)
SHELL_REPEAT = {"TILE_S": (0.32, 4, 2), "TILE_S2": (0.32, 4, 2), "TILE_L": (0.32, 4, 2), "TILE_D": (0.2, 2, 3)}


def thickness(spec, grid, line):
    """H per grid vertex: the envelope, eased in from the line"""
    D = grid.D
    F = afro_sdf(spec["scale"]) if spec["shape"] == "afro" else hightop_sdf()
    t = ray_hit(F, D, grid.R + 0.005, np.full(len(D), 1.6))
    Henv = np.maximum(t - grid.R, H0)
    da = da_of(grid.S)
    s_front, s_side, s_ear, s_back = spec["span"]
    span = np.interp(da, [0, 0.5, 1.0, 1.45, 1.95, 2.4, math.pi], [s_front, s_front, s_side, s_ear, s_ear, s_back, s_back])
    y = grid.S[:, 1]
    if spec["shape"] == "afro":
        x = np.clip(grid.d / span, 0, 1)
        # a rounded roll down to the line (quarter-circle-like), not a wall
        ease = 0.6 * np.sqrt(1 - (1 - x) ** 2) + 0.4 * (1 - (1 - x) ** 2)
        H = H0 + (Henv - H0) * ease
        # over and around the ears the mass comes down at full thickness to just above the ear tops, then
        # rounds under into the short sideburn and the hair behind the ear (the ears stay clear)
        low = sstep(0.8, 1.1, da) * sstep(2.55, 2.25, da)
        Hc = H0 + 2.3 * np.clip(y - 0.03, 0, None)
        H = H * (1 - low) + smin(H, Hc, 0.05) * low
    else:
        # the column grows out of the fade: from cap height at the fade's top line it lengthens smoothly over
        # ~0.09 of height (zero slope at the line: no step, no rim); at the front line-up it rises quicker
        vert = y - line.y_at(da)
        x = np.clip(vert / span, 0, 1)
        front = sstep(0.62, 0.42, da)
        ease = front * (1 - (1 - x) ** 1.8) + (1 - front) * x * x * (3 - 2 * x)
        H = H0 + (Henv - H0) * ease
    H = np.where(grid.d > 0, np.maximum(H, H0), H0)
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
        self.depth = np.maximum(H - h, 0.0)  # under the outer surface (occlusion)
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
        # (from f 0.5 out the layers take the same lumps: they move in parallel, so an outer layer's trough never
        # dips onto the dark core under it)
        w = min(1.0, f / 0.5) * sstep(0.0, span * 1.1, grid.d) ** 1.3
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

    def depth_at(self, D):
        return self.grid.interp(np.atleast_2d(D), self.depth)


def occlusion(depth, lump, ny):
    """soft occlusion from the depth under the outer surface (gentle: 0.94 at the surface, >= ~0.66 deep in the core:
    the deepest visible hair is no darker than ~0.7x the surface; the core's dense tile is darker by albedo too),
    a little darker in curl-cluster valleys and on the underside"""
    o = 0.94 - 0.27 * np.clip(depth / 0.24, 0, 1) ** 0.85
    o = o * (1 + 0.03 * lump) * (1 - 0.08 * sstep(-0.2, -0.8, ny))
    return np.clip(o, 0.64, 1.0)


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
        return "front" if d[1] < 0.74 else "top"
    if 45 <= deg < 135:
        return "right"
    if 225 <= deg < 315:
        return "left"
    return "back"


NORMAL_UP = np.array([0.0, 0.35, 0.0])


class Card:
    __slots__ = ("P", "N", "U", "C", "T", "layer", "region", "kind", "clump", "dline")

    def __init__(self, layer, kind):
        self.P, self.N, self.U, self.C, self.T = [], [], [], [], []
        self.layer = layer
        self.kind = kind
        self.region = None
        self.clump = None
        self.dline = 9.0

    def to_piece(self, piece):
        base = piece.nv
        for p, n, u, c in zip(self.P, self.N, self.U, self.C):
            # shading normals biased up a little (a soft volume lit from above: the underside of the mass does
            # not go black where it faces down)
            n = unit(np.asarray(n, np.float64) + NORMAL_UP)
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


def shell_dmin(spec, li):
    """how close to the line a layer's shell comes: the dense inner shells stop a little further back (their
    edges hide under the soft hairline patches and the sparse outer shells, which come closer)"""
    f, cell = spec["layers"][li]
    k = spec.get("dense_back", 0.012)
    if spec.get("stagger"):
        # (the high top: coverage builds up out of the fade: the sparse outer shells start at the fade's top line,
        # the dense core further up, so its edge sits under three sparse shells, never a dark rim at the foot)
        if cell == "TILE_D":
            # (at the front line-up and its temple corners the dense core comes close: no translucent strip of
            # sparse shells over the skin there)
            return 0.045 + 0.012 * li
        return 0.025 + 0.006 * (len(spec["layers"]) - 1 - li)
    if cell == "TILE_D":
        return 0.026 + k * li
    return 0.024 + 0.002 * li


def shell_cards(layer, li, spec, line, rng, region_fn=region_of):
    """a continuous shell on the evaluated layer: a cube-sphere grid of rays (each layer turned at random, so
    no seam lines up through the layers), SHELL_REPEAT quads per repeat of a tileable coil cell (UVs inset by
    1.5 texels, so no quad samples the neighbouring cell)"""
    f, cell = spec["layers"][li]
    u0, v0, u1, v1 = CELLS[cell]
    e = 1.5 / 1024
    u0, v0, u1, v1 = u0 + e, v0 + e, u1 - e, v1 - e
    rep_u, su, sv = SHELL_REPEAT[cell]
    r = float(np.linalg.norm(layer.P - C, axis=1).mean())
    N = su * int(math.ceil(r * math.pi / 2 / rep_u))
    dmin = shell_dmin(spec, li)
    jit = spec.get("edge_jitter", 0.0) * min(1.0, li)
    ph = rng.uniform(0, TAU, 4)
    ph_i, ph_j = (2, 1) if cell == "TILE_S2" else (0, 0)  # (the middle shells: TILE_S at another phase)

    def ragged(D):
        """a ragged shell edge (irregular along the line, so no ruled horizontal edge)"""
        if not jit:
            return 0.0
        th, az = angles_of(np.atleast_2d(D))
        n = (np.sin(7 * az + ph[0]) * 0.5 + np.sin(13 * az + ph[1]) * 0.3 + np.sin(29 * az + ph[2]) * 0.2
             + np.sin(5 * th + 3 * az + ph[3]) * 0.3)
        return jit * n

    def bias(D, S):
        """the high top's dense core comes close at the front line-up and its temple corners (no translucent
        strip of sparse shells over the skin there)"""
        if not (spec.get("stagger") and cell == "TILE_D"):
            return 0.0
        return (0.03 + 0.008 * li) * sstep(1.05, 0.55, da_of(S))

    cards = []
    for face in cube_dirs(N, rand_rot(rng)):
        D = face.reshape(-1, 3)
        S = C + D * skull_r(SK, *angles_of(D))[:, None]
        dd = (line.dist(S) - ragged(D) + bias(D, S)).reshape(N + 1, N + 1)
        okv = dd > dmin
        P = np.full((N + 1, N + 1, 3), np.nan)
        for i in range(N + 1):
            for j in range(N + 1):
                if okv[i, j]:
                    h = layer.hit(face[i, j])
                    if h is not None:
                        P[i, j] = h
        Nn = layer.normal(D).reshape(N + 1, N + 1, 3)
        Lu = layer.lump_at(D).reshape(N + 1, N + 1)
        Dp = layer.depth_at(D).reshape(N + 1, N + 1)

        def dd_of(d):
            sd = (C + d * skull_r(SK, *angles_of(d[None]))[:, None])
            return float(line.dist(sd)[0] - np.ravel(ragged(d))[0] + np.ravel(bias(d[None], sd))[0])

        for i in range(N):
            for j in range(N):
                q = P[i:i + 2, j:j + 2]
                corners = ((0, 0), (1, 0), (1, 1), (0, 1))
                valid = [not np.isnan(P[i + a, j + b]).any() for (a, b) in corners]
                if not any(valid):
                    continue
                if not all(valid):
                    # a quad across the shell's edge: its outside corners are pulled in along the quad to the
                    # edge (dmin from the line), UVs with them, so the shell reaches the line without stair steps
                    if any(dd[i + a, j + b] < -0.2 for (a, b) in corners):
                        continue
                dc = unit(np.mean([face[i + a, j + b] for (a, b), v in zip(corners, valid) if v], axis=0))
                fuv_c = np.mean([((((i + ph_i) % su) + a) / su, (((j + ph_j) % sv) + b) / sv) for (a, b), v in zip(corners, valid) if v],
                                axis=0)
                cd = Card(li, "shell")
                okq = True
                for (a, b), v in zip(corners, valid):
                    ii, jj = i + a, j + b
                    fu = (((i + ph_i) % su) + a) / su
                    fv = (((j + ph_j) % sv) + b) / sv
                    if v:
                        p, d = P[ii, jj], face[ii, jj]
                        nn, lu, dp = Nn[ii, jj], Lu[ii, jj], Dp[ii, jj]
                    else:
                        lo, hi = 0.0, 1.0
                        for _ in range(9):
                            m = (lo + hi) / 2
                            if dd_of(unit(dc + (face[ii, jj] - dc) * m)) > dmin:
                                lo = m
                            else:
                                hi = m
                        d = unit(dc + (face[ii, jj] - dc) * lo)
                        p = layer.hit(d)
                        if p is None:
                            okq = False
                            break
                        fu, fv = fuv_c + (np.array([fu, fv]) - fuv_c) * lo
                        nn = layer.normal(d)[0]
                        lu = float(layer.lump_at(d)[0])
                        dp = float(layer.depth_at(d)[0])
                    occ = float(occlusion(dp, lu, nn[1]))
                    cd.P.append(p)
                    cd.N.append(nn)
                    cd.U.append((u0 + (u1 - u0) * fu, v0 + (v1 - v0) * fv))
                    cd.C.append((occ, occ, occ, 1.0))
                if not okq:
                    continue
                # (a degenerate sliver is dropped)
                Pq = np.asarray(cd.P)
                area = 0.5 * np.linalg.norm(np.cross(Pq[2] - Pq[0], Pq[1] - Pq[0])) + \
                    0.5 * np.linalg.norm(np.cross(Pq[3] - Pq[0], Pq[2] - Pq[0]))
                if area < 2e-5:
                    continue
                cd.T = [(0, 1, 2), (0, 2, 3)]
                cd.dline = float(dd[i:i + 2, j:j + 2].min())
                cd.region = region_fn(unit(Pq.mean(axis=0) - C))
                cards.append(cd)
    return cards


def patch_cards(layer, li, spec, line, rng, params, band=None, select=None, lift=(0.0, 0.0), kind="patch",
                seed=0, region_fn=region_of):
    """surface patches on a layer: 3 x 3 vertex grids ray-cast onto it, rotated, tilted, domed (band: only
    within that distance of the line; select: a direction filter; lift: raised off the layer)"""
    f, size, cover, cell0 = params
    e = 1.5 / 1024
    ncand = 30000
    D = fib_dirs(ncand, 101 + li * 7 + len(spec["prefix"]) + seed)
    S = C + D * skull_r(SK, *angles_of(D))[:, None]
    dd = line.dist(S)
    # patch size shrinks toward the line (its visible cloud stays inside the hairline)
    s = np.minimum(size, np.maximum(SMIN, dd / 0.42))
    ok = dd > 0.42 * SMIN
    if band is not None:
        ok &= dd < band
    if select is not None:
        ok &= select(D)
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
        lf = rng.uniform(*lift)
        flip = rng.random(2) < 0.5
        cell = cell0
        u0, v0, u1, v1 = CELLS[cell]
        u0, v0, u1, v1 = u0 + e, v0 + e, u1 - e, v1 - e
        cd = Card(li, kind)
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
                h = h + nn * ((tilt[0] * a + tilt[1] * b) * sk * 0.5 + dome * (1 - 0.5 * (a * a + b * b)) + lf)
                uu = (a + 1) / 2
                vv = (b + 1) / 2
                if flip[0]:
                    uu = 1 - uu
                if flip[1]:
                    vv = 1 - vv
                lu = float(layer.lump_at(qd)[0])
                occ = float(occlusion(max(0.0, float(layer.depth_at(qd)[0]) - lf), lu, nn[1]))
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
    """a two-sided strip card along pts (root first) in the plane of the strand and `side`; strip: the atlas
    cell (u0, v0, u1, v1), v0 / v1 the root / tip as fractions of the cell's height"""
    n = len(pts)
    e = 1.5 / 1024
    u0, cv0, u1, cv1 = strip[0] + e, strip[1] + e, strip[2] - e, strip[3] - e
    rows = []
    for i, p in enumerate(pts):
        t = i / (n - 1)
        v = cv0 + (cv1 - cv0) * (v0 + (v1 - v0) * t)
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
    """fuzz fins out of the outer layer: rooted a little under it, laid at 25-50 degrees off the surface and
    curving back round it (never straight out along the normal), the card's plane facing outward (seen face-on
    from outside, never as an edge-on splinter); two-sided, outward shading normals"""
    fs = spec["fins"]
    D = fib_dirs(fs["n"] * 6, 977 + len(spec["prefix"]))
    S = C + D * skull_r(SK, *angles_of(D))[:, None]
    dd = line.dist(S)
    ok = dd > fs.get("above", 0.07)
    if spec["shape"] == "hightop":
        ok &= (S[:, 1] - line.y_at(da_of(S))) > fs.get("above", 0.07)
    else:
        ok &= ~((S[:, 1] < 0.06) & (da_of(S) > 0.8))  # (not low on the sides, behind the ears or at the nape)
    ok = np.nonzero(ok)[0]
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
        # a slight preference for lying downhill (gravity) on the sides
        g = np.array([0, -1.0, 0])
        gt = g - n * np.dot(g, n)
        if np.linalg.norm(gt) > 0.2:
            tang = unit(tang + fs.get("gravity", 0.5) * unit(gt))
        a = math.radians(rng.uniform(*fs["angle"]))
        dirv = unit(tang * math.cos(a) + n * math.sin(a))
        L = rng.uniform(*fs["length"])
        w = rng.uniform(*fs["width"])
        root = c - n * fs["sink"]
        side = unit(np.cross(dirv, n))
        curl = rng.normal(0, 0.12)
        pts = [root + dirv * L * t - n * (L * 0.22 * t * t) + side * (L * curl * t * t) for t in (0.0, 0.55, 1.0)]
        cd = Card(li + 1, "fin")
        strand_card(cd, pts, [w, w * 0.95, w * 0.8], side, n, fs["cell"], 0.0, 1.0,
                    lambda t: float(np.clip(0.86 + 0.14 * t, 0.4, 1)))
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
                if not spec.get("edge_fade", True) and float(da_of(q)[0]) > 0.6:
                    continue  # (the high top: tufts only at the front line-up, not along the fade)
                tang = unit(P[i + 1] - P[i])
                if abs(tang[1]) > 0.6:
                    continue  # (not along the sideburns: there a tuft is seen edge-on, as a streak)
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
                o0 = 0.74 + 0.06 * row
                strand_card(cd, pts, [w, w, w * 0.85][-len(pts):], side, n, FIN_T, 0.0, 0.94,
                            lambda t, o0=o0: o0 + (0.96 - o0) * t)
                cd.region = "base"
                cards.append(cd)
    return cards


# =============================================================================================== pieces
BAND_D = 0.09  # shells this close to the line stay in the root piece too (the layers have converged there)
BASE_LAYERS = 1  # layers 0..BASE_LAYERS (with the hairline patches and tufts) form the unscaled root piece
MIN_MASS_TRIS = 300  # a region mass smaller than this joins its neighbour (no MeshPart for a label)


def low_card(cd):
    """a card low on the sides, behind the ears or at the nape (y < LOW_Y, not at the front): it stays in the
    unscaled root piece (scaled about the piece's scalp point it would swing out below the mass at the slider's
    extremes, as flakes under the ear and at the nape)"""
    P = np.asarray(cd.P)
    c = P.mean(axis=0)
    return c[1] < LOW_Y and float(da_of(c[None])[0]) > 0.8


LOW_Y = 0.08


def make_pieces(spec, cards, names):
    """cards -> hairlib Pieces: the root (unscaled: layers 0-1, the hairline patches and tufts), the mass by
    region (volume: every layer from 2 out, down to the line, so the whole mass scales with the slider), the
    bounce puffs (volume, bounce)"""
    groups = {}
    for cd in cards:
        if cd.clump:
            key = "clump:" + cd.clump
        elif cd.kind in ("edge", "patch") or cd.layer <= BASE_LAYERS or (cd.kind == "shell" and cd.dline < BAND_D) \
                or low_card(cd):
            key = "base"
        else:
            key = "mass:" + cd.region
        groups.setdefault(key, []).append(cd)
    # a tiny region joins its neighbour: front -> top, others -> top
    for r in list(names["mass"]):
        cs = groups.get("mass:" + r)
        if cs and r != "top" and sum(len(c.T) for c in cs) < MIN_MASS_TRIS:
            groups.setdefault("mass:top", []).extend(groups.pop("mass:" + r))
    pieces = []
    order = ["base"] + ["mass:" + r for r in names["mass"]] + ["clump:" + r for r in names["clump"]]
    kind_rank = {"shell": 0, "patch": 1, "edge": 2, "fin": 3, "puff": 4}
    for key in order:
        cs = groups.get(key)
        if not cs:
            continue
        # innermost layer first (scalp side first), patches before fins / tufts of the same layer
        # (the hairline patches lie on the outer layer: drawn after every shell, over the shells' edges)
        cs.sort(key=lambda c: (c.layer + (100 if c.kind == "patch" else 0) + (200 if c.kind == "edge" else 0),
                               kind_rank[c.kind]))
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
            p.meta["hairfx"] = {"kind": "bounce", "stiff": 0.9, "mass": 0.6,
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

    def enforce_volume(self, pieces, factors=(0.8, 1.3), passes=4):
        """push the volume pieces' vertices out until they clear CLEAR at the slider's extremes too"""
        for _ in range(passes):
            moved = 0
            for p in pieces:
                if p.meta.get("length") != "volume":
                    continue
                P = np.asarray(p.P)
                low = np.full(len(P), 9.0)
                for Vf in factors:
                    Q = np.asarray(volume_placed(p, Vf).P)
                    H = self.heights(Q)
                    low = np.minimum(low, np.min(np.stack(list(H.values())), axis=0))
                bad = low < CLEAR
                if not bad.any():
                    continue
                D = unit(P - C)
                P[bad] += D[bad] * ((CLEAR - low[bad]) / 0.75 + 0.003)[:, None]
                p.P = [tuple(map(float, q)) for q in P]
                moved += int(bad.sum())
            if not moved:
                break

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
CLUMPS = [("top", (0.0, 0.92, 0.38)), ("back", (0.0, 0.25, 1.0)), ("left", (-1.0, 0.55, 0.12)),
          ("right", (1.0, 0.55, 0.12))]

def build_style(key, spec, clr, rng_seed=7):
    t0 = time.time()
    clear_scene()
    rng = np.random.default_rng(rng_seed + len(key) * 13)
    line = natural_line() if spec["line"] == "natural" else hightop_line()
    grid = Grid(line)
    H, span = thickness(spec, grid, line)
    c_layers = coll("Layers (card guides, modifiers live)")
    texs = [make_texture("BroadLumps", "CLOUDS", 0.24, 2), make_texture("CurlClusters", "CLOUDS", 0.075, 1)]
    layers = [Layer(i, L[0], spec, grid, H, span, c_layers, texs) for i, L in enumerate(spec["layers"])]
    cards = []
    for li, layer in enumerate(layers):
        cards += shell_cards(layer, li, spec, line, rng)
    # the shells' edges near the line hide under small cloud patches (and the tufts over them)
    # (on the outer layer, lifted a little: over every shell's edge near the line)
    for bi, (li, prm) in enumerate(spec["band"]):
        cards += patch_cards(layers[-1], len(layers) - 1, spec, line, rng, prm, band=0.1, lift=(0.001, 0.004),
                             seed=bi * 3)
    fins = fin_cards(layers[-1], len(layers) - 1, spec, line, rng)
    cards += fins
    if spec.get("edge", True):
        cards += edge_cards(line, spec, rng)
    # bounce clumps: round patches (radius ~0.17) of the outermost shell, with the fins rooted in them, cut out of
    # the static mass; the next shell in (sparse) and the dense core stay whole under them, so a clump moving a
    # little never opens a gap
    if spec.get("puffs"):
        pf = spec["puffs"]
        r_out = float(np.linalg.norm(layers[-1].P - C, axis=1).mean())
        last = len(layers) - 1
        for ci, (cname, cdir) in enumerate(CLUMPS):
            cdir = unit(np.array(cdir))
            lim = math.cos(pf["radius"] / r_out)
            for cd in cards:
                if cd.clump is not None or cd.dline < BAND_D:
                    continue
                if (cd.kind == "shell" and cd.layer == last) or cd.kind == "fin":
                    d = unit(np.asarray(cd.P).mean(axis=0) - C) if cd.kind == "shell" else unit(np.asarray(cd.P[0]) - C)
                    if d @ cdir > lim:
                        cd.clump = cname
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
    clr.enforce_volume(pieces)
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
    "closeside": ((100, 4, 1.0), 1.9, (0.3, 0.36, 0.08)),
    "front": ("front", 3.9, (0.0, 0.17, 0.03)),
    "closeback": ((180, 10, 1.0), 1.6, (0.0, 0.3, 0.4)),
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


def clip_alpha(mat, thr=0.5):
    """the worst case of the game's alpha (a hard cut-out at thr instead of blending: no soft card edge left to
    hide behind), for the --roblox check"""
    if mat.get("clipped"):
        return
    nt = mat.node_tree
    bs = nt.nodes["Principled BSDF"]
    links = [l for l in nt.links if l.to_socket == bs.inputs["Alpha"]]
    if links:
        src = links[0].from_socket
        nt.links.remove(links[0])
        gt = nt.nodes.new("ShaderNodeMath")
        gt.operation = "GREATER_THAN"
        gt.inputs[1].default_value = thr
        nt.links.new(src, gt.inputs[0])
        nt.links.new(gt.outputs[0], bs.inputs["Alpha"])
    mat["clipped"] = 1


def bake_dye(tex, base, alt, dye, out, bands=12):
    """the game's tint (HairAssetKit.Tint with Kit.Palette's pal.at, approximately): per row v (root 0 .. tip 1)
    the base colour lerped to the dye's by smoothstep(0.6, 0.85, v) (Tips) or (0.25, 0.95, v) (Ombre), darker
    roots / lighter tips for coily hair, a band's own +-10% across u (12 bands), times the greyscale; alpha kept"""
    from PIL import Image
    im = np.asarray(Image.open(tex).convert("RGBA")).astype(np.float64) / 255
    h, w = im.shape[:2]
    v = (np.arange(h) + 0.5) / h
    k = sstep(0.6, 0.85, v) if dye == "Tips" else sstep(0.25, 0.95, v)
    col = np.asarray(base)[None] * (1 - k[:, None]) + np.asarray(alt)[None] * k[:, None]
    shade = (0.9 + 0.1 * sstep(0, 0.4, v)) * (1 + 0.02 * sstep(0.5, 1, v))
    col *= shade[:, None]
    bi = np.minimum(bands - 1, ((np.arange(w) + 0.5) / w * bands).astype(int))
    rnd = np.array([(math.sin(b * 12.9898 + 4.1414) * 43758.5453) % 1 for b in range(bands)])
    bv = 0.9 + 0.2 * ((rnd * 13.7) % 1)
    rgb = im[..., :3] * col[:, None, :] * bv[bi][None, :, None]
    Image.fromarray((np.dstack([np.clip(rgb, 0, 1), im[..., 3:]]) * 255 + 0.5).astype(np.uint8), "RGBA").save(out)
    return out


def render_style(key, spec, pieces, looks, views, res, samples, cull=True, vol=None, tag="", dye=None, clip=False):
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
        htint = tint
        if dye:
            tex = bake_dye(os.path.join(TEX_DIR, "hair_coily.png"), tint, HAIR_TINTS["blonde"], dye,
                           os.path.join(FAM_DIR, f"dye_{dye}_{tint_name}.png"))
            htint = (1.0, 1.0, 1.0)
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
            ob = sc.add_piece(P, texture=tex, tint=htint, offset=off, scale=tuple(s))
            if cull:
                cull_backfaces(ob.data.materials[0])
                fabric(ob.data.materials[0])
            if clip:
                clip_alpha(ob.data.materials[0])
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
    ap.add_argument("--roblox", action="store_true",
                    help="also a game-like check: one-sided (culled), Fabric, alpha cut out at 0.5 (34, close34)")
    ap.add_argument("--volume", default="", help="also render at these volume factors, e.g. 0.8,1.3")
    ap.add_argument("--dye", default="", help="also a dye preview (Tips / Ombre, blonde over the look's colour)")
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
            if args.roblox:
                p5, l5 = render_style(key, STYLES[key], built[key], [looks[0]], ["34", "close34"], res, samples,
                                      tag="_roblox", clip=True)
                print("roblox", p5, flush=True)
            for dy in [x for x in args.dye.split(",") if x]:
                p4, l4 = render_style(key, STYLES[key], built[key], [looks[1] if len(looks) > 1 else looks[0]],
                                      ["34", "close34"], res, samples, tag=f"_dye{dy}", dye=dy)
                print("dye", p4, flush=True)
            for vf in [float(x) for x in args.volume.split(",") if x]:
                p3, l3 = render_style(key, STYLES[key], built[key], [looks[0]], ["34", "side", "back", "top34"], res, samples,
                                      vol=vf, tag=f"_vol{vf}")
                print("volume", p3, flush=True)
    return report


if __name__ == "__main__":
    main()
