"""Long family hair: "Long Hair" for the Straight and Wavy hair types (two entries: "long" for Straight, "long_wavy"
for Wavy). Modelled in Blender (bpy 4.2), exported with hairlib.

    /opt/bpyenv/bin/python tools/hair/build_long.py [--render DIR] [--only long,long_wavy] [--no-tex] [--no-build]
                                                    [--samples N] [--views 34,side] [--looks f_brown] [--res WxH]

Writes tools/hair/textures/hair_straight.png, tools/hair/out/<key>/ (meshes + style.json) and
tools/hair/blend/<key>.blend; with --render, Cycles self-check renders and a sheet per style.
Debug: LONG_DEBUG=layercol (every layer its own vertex colour; needs a build), nocap, nocol, notex, shadow
(hair-on-hair shadows on: what castShadow = true would do), denoise; LONG_LAYERS=outer,... builds only those layers;
LONG_NOASSERT=1 finishes a build whose clearance check fails.

How the hair is built (game nominal head space, numerically; see CONTRACT.md):
* Texture "straight" (owned here): 1024 x 1024, four 256-px strips (dense clump, medium, wispy flyaway, wavy), drawn
  strand by strand at 2x and filtered down: long continuous strands from the root (v = 0) to tapered tips over the
  last ~15% (no V-shaped strip, no dark stacked tips), clumps with their own brightness (low-frequency variation, no
  wood grain), strand density, width and opacity thinning toward the strip's side edges (a feathered edge of loose
  strands over ~13% of the strip, never a clamped opaque column), a light root darkening, a darker under-fill in the
  dense strips, a transparent root (alpha 0 to v 0.015, full by ~0.085) and colour bled into the transparent texels.
* Style: centre parting that ends before the crown, the hair combed from it over the top of the ear and behind it
  (ears visible), falling as a continuous cone from ear to ear round the back (the hair's own volume holds it 0.08-0.2
  off the neck by the jaw line, wider than the skull below the ears), the side hair falling beside the neck as a wide
  sheet over the top of each shoulder, down its front onto the upper chest (the side chains), the rest down the back
  over the shoulder blades (the back curtain, a level hem with a slight U at y ~ -1.5 at length 0.5). The style's
  hairline recedes into the temple corners (0.05) and zigzags finely. Wavy: the same layout with planar S-waves in
  clumps from the ear line down (a low wave on the head already) and the wavy strip.
* Guides: every card is a guide strand (5 layers, innermost first: a hairline layer rooted along the front
  hairline, a dense scalp layer, inner, main and outer volume layers). Its scalp part is a great circle from its
  root on the parting (or the hairline) to its release point behind the ear / round the back, projected on the
  default skull at the layer's height profile (rising out of the parting and out of the hairline, the outer layers
  over a longer distance so the mass builds up from the forehead; the volume layers' roots end at the end of the
  parting and their back strands sweep over the crown at full height), kept inside the style hairline and above the
  ear. Its hanging part is constructed, not simulated (drape_path): fanned out to the hanging cone at the jaw line,
  down to the torso, then along the torso surface found with Blender BVH ray casts (forward over the shoulder for
  the side sheets, back over the trapezius and down the shoulder blades for the curtain), then collided (both skull
  tables, both heads, ear boxes, both torsos, the body proxy's neck + gap) and smoothed. The guides are kept in the
  .blend as curve objects.
* Cards: built from the guides as Blender meshes (one per layer; main and outer with 3 vertices across every row
  over the head and a row every <= 0.04 of arc over the crown), per-corner UVs, a "hang" vertex group and two
  Displace modifiers (Clouds) that break the hanging part into clumps; the evaluated meshes are read back. Card
  widths come from the spacing to the nearest card of the same layer (x the layer's overlap); hanging cards face
  away from the body (lying flat on the shoulder, never standing up as fins). Clearance is enforced on every vertex
  of every piece (male head with and without ears down the neck to the torso, female head forward through the
  runtime fit and inverse, both skull tables, ear boxes, both torsos) and asserted >= 0.022. Soft occlusion is
  baked into the vertex colours with BVH ray casts and smoothed spatially; near the hairline every layer grades
  into the painted cap's tone (no lighter rim on a darker band); tips are lifted to the mid-length's tone. A ring of
  short wispy cards breaks the hairline edge and two short cards lie over the front end of the parting.
* Pieces: static HairTop (everything over the head) and swinging chains split from the same cards: the back curtain
  in 4 chains, a side sheet each side (seg 1 below the anchor, pivot at its top; seg 2 'b' from the shoulders down,
  overlapping seg 1 by SEG_OVERLAP as a narrowing wedge tucked under it), hairfx swing, length "hang", hideUnder
  hood (HairTop too), castShadow false (a card's game shadow is its whole quad). Triangles of every piece are
  emitted innermost layer first; cards are two-sided with outward shading normals, except the hidden layers lying
  on the head (edge, scalp, inner, hairline ring, part cover: seen from outside only), which are one-sided there.
"""
import argparse
import json
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402
from PIL import Image, ImageFilter  # noqa: E402

TEX_DIR = os.path.join(HERE, "textures")
BLEND_DIR = os.path.join(HERE, "blend")
TEX_KEY = "straight"
TEX_PATH = os.path.join(TEX_DIR, f"hair_{TEX_KEY}.png")
TAU = 2 * math.pi
TEX_SIZE = 1024
STRIPS = {"dense": (0.0, 0.25), "medium": (0.25, 0.5), "wispy": (0.5, 0.75), "wavy": (0.75, 1.0)}


# =========================================================================================== texture
def _box1(a, r, axis):
    """box blur of radius r along axis (edge-clamped), via cumulative sums"""
    if r < 1:
        return a
    n = a.shape[axis]
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r + 1, r)
    c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis, dtype=np.float64)
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return ((hi - lo) / (2 * r + 1)).astype(np.float32)


def _blur(a, sigma):
    """~gaussian blur (three box passes per axis)"""
    if sigma <= 0.3:
        return a
    r = max(1, int(round(sigma * 0.9)))
    out = a.astype(np.float32)
    for _ in range(3):
        out = _box1(out, r, 0)
        out = _box1(out, r, 1)
    return out


def _smoothn(n, rng, k=5):
    """smooth 1d noise (n samples, unit-ish amplitude)"""
    g = rng.normal(0, 1, k + 3)
    x = np.linspace(0, k, n)
    i = np.floor(x).astype(int)
    f = x - i
    f = f * f * (3 - 2 * f)
    return g[i] * (1 - f) + g[i + 1] * f


class Canvas:
    """greyscale + alpha, 'over' compositing of anti-aliased near-vertical strands (one x per row)"""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.lum = np.zeros((h, w), np.float32)
        self.alp = np.zeros((h, w), np.float32)

    def strand(self, ys, xs, wid, shade, op, x_lo, x_hi):
        """ys: integer rows (increasing), xs: float centre per row, wid/shade/op per row"""
        m = (ys >= 0) & (ys < self.h)
        ys, xs, wid, shade, op = ys[m], xs[m], wid[m], shade[m], op[m]
        if len(ys) == 0:
            return
        r = np.maximum(0.5, wid * 0.5)
        R = int(np.ceil(r.max())) + 1
        base = np.floor(xs).astype(np.int64)
        for k in range(-R, R + 1):
            px = base + k
            d = np.abs(px + 0.5 - xs)
            cov = np.clip(r + 0.5 - d, 0, 1) * op
            ok = (cov > 0) & (px >= x_lo) & (px < x_hi)
            if not ok.any():
                continue
            yy, xx, c, s = ys[ok], px[ok], cov[ok], shade[ok]
            self.lum[yy, xx] = s * c + self.lum[yy, xx] * (1 - c)
            self.alp[yy, xx] = c + self.alp[yy, xx] * (1 - c)


def _strip(w, h, seed, n_strands, n_clumps, width_px, clump_k, fill, len_min, wave_amp=0.0, wave_per=0.0,
           stray=0.03, shade_lo=0.5, edge=0.09, tip_spread=0.25, root_dark=0.3, clump_lo=0.75, spread=0.5, root_soft=0.07, root_fade=0.06,
           root_clear=0.015, rag=0.0, clump_shade=0.0, edge_thin=0.0):
    """one card strip (w x h at 2x), roots at the top. Returns lum, alpha (0..1)."""
    rng = np.random.default_rng(seed)
    cv = Canvas(w, h)
    margin = edge * w
    # clump centre lines: evenly spread with jitter, meandering a little
    cx = (np.arange(n_clumps) + 0.5) / n_clumps
    cx = margin + (w - 2 * margin) * np.clip(cx + rng.normal(0, 0.25 / n_clumps, n_clumps), 0.02, 0.98)
    rows = np.arange(h)
    tt = rows / (h - 1)
    clump_lines = []
    wave_ph = rng.uniform(0, TAU)
    for c in range(n_clumps):
        mean = cx[c] + _smoothn(h, rng, 4) * w * 0.025
        if wave_amp:
            ph = wave_ph + rng.normal(0, 0.35)
            amp = wave_amp * w * rng.uniform(0.8, 1.2) * np.clip(tt / 0.12, 0, 1)
            mean = mean + amp * np.sin(ph + tt * TAU * wave_per)
        clump_lines.append(mean)
    clump_lines = np.array(clump_lines)
    clump_len = rng.uniform(clump_lo, 1.0, n_clumps)  # each clump's tip ends at its own length
    clump_len[rng.integers(n_clumps)] = 1.0
    cshade = rng.uniform(0.8, 1.0, n_clumps)  # per-clump brightness: low-frequency variation, not per-strand grain
    for k in range(n_strands):
        c = int(rng.integers(n_clumps))
        # roots spread over the strip, thinning toward its edges (a ragged edge made of strands, not a cut)
        if spread is None:  # spread evenly over the strip (a card reads as a full lock edge to edge)
            x0 = w * 0.5 + (w * 0.5 - margin * 0.3) * float(rng.uniform(-1, 1))
        else:
            x0 = w * 0.5 + (w * 0.5 - margin) * float(np.clip(rng.normal(0, spread), -1.15, 1.15))
        y0 = int(h * root_soft * rng.uniform(0.0, 1.0) ** 2.2)  # staggered roots: a soft root edge
        lmax = clump_len[c]
        L = rng.uniform(len_min, 1.0) ** 0.6 * lmax  # most strands reach near the tip
        # strands near the strip's side edges: thinner, fainter, shorter (the edge is a few loose strands)
        ex = min(x0, w - x0) / w
        ek = float(np.clip((ex - 0.03) / max(1e-6, edge_thin), 0, 1)) if edge_thin > 0 else 1.0
        if ek < 1:
            L = L * (0.55 + 0.45 * ek + 0.3 * rng.uniform(0, 1) * (1 - ek))
        y1 = int(h * min(1.0, L))
        if y1 - y0 < 16:
            continue
        ys = rows[y0:y1]
        t = (ys - y0) / max(1, (h - 1 - y0))
        # gathered into the clump toward the tip; a few strays leave it
        kc = clump_k * np.clip(t * 1.2, 0, 1) ** 2.2
        tgt = clump_lines[c][ys] + rng.normal(0, 1) * w * 0.012 * (1 - t * 0.6)
        xs = x0 * (1 - kc) + tgt * kc + _smoothn(len(ys), rng, 6) * w * 0.006
        if wave_amp:
            xs = xs + (clump_lines[c][ys] - clump_lines[c][ys].mean()) * (1 - kc) * 0.85
        if rng.random() < stray:
            xs = xs + (t ** 2.2) * rng.normal(0, 0.18) * w
        xs = np.clip(xs, 1.0, w - 2.0)  # (no clamp column: the edge mask below fades whatever leaves the strip)
        # tapered, staggered tip
        tl = (ys - y0) / max(1, y1 - y0)
        tip = np.clip((1 - tl) / tip_spread, 0, 1)
        wid = width_px * rng.uniform(0.75, 1.3) * (0.35 + 0.65 * tip ** 0.7)
        base = rng.uniform(shade_lo, 1.0)
        if clump_shade:
            base = cshade[c] * (1 - clump_shade) + base * clump_shade
        shade = base * (1 - root_dark * (1 - np.clip(t / 0.15, 0, 1)) ** 2) * (0.92 + 0.08 * _smoothn(len(ys), rng, 3))
        if wave_amp:
            # crests catch the light: brighten where the strand runs straight down
            slope = np.gradient(xs) if len(xs) > 2 else np.zeros_like(xs)
            shade = shade * (0.9 + 0.18 * np.exp(-(slope * 3.0) ** 2))
        op = rng.uniform(0.65, 1.0) * np.clip(tip / 0.45, 0, 1) ** 0.8 * np.clip((ys - y0) / (0.02 * h), 0.25, 1)
        if ek < 1:
            op = op * (0.45 + 0.55 * ek)
            wid = wid * (0.7 + 0.3 * ek)
        cv.strand(ys, xs, wid, shade, op, 0, w)
    lum, alp = cv.lum, cv.alp
    if fill > 0:
        # the deeper hair under the strands: a darker blurred body, strongest in the clump cores
        body = _blur(alp, w * 0.02)
        uu = (np.arange(w) + 0.5) / w
        core = np.clip((0.5 - np.abs(uu - 0.5)) / 0.2, 0, 1)
        core = (core * core * (3 - 2 * core))[None, :]
        body = np.clip(body * 1.25, 0, 1) ** 2 * fill * core
        bl = 0.55 + 0.25 * _blur(lum, w * 0.02) / np.maximum(_blur(alp, w * 0.02), 1e-3)
        lum = lum * alp + bl * body * (1 - alp)
        alp = alp + body * (1 - alp)
        lum = lum / np.maximum(alp, 1e-4)
    # edges: alpha to zero toward both strip edges (no card border)
    u = (np.arange(w) + 0.5) / w
    if rag > 0:
        # a ragged edge: its width wanders along v (never a straight line down the card)
        rl = edge * np.clip(1 + rag * _smoothn(h, rng, 22) + 0.5 * rag * _smoothn(h, rng, 70), 0.35, 2.0)
        rr = edge * np.clip(1 + rag * _smoothn(h, rng, 22) + 0.5 * rag * _smoothn(h, rng, 70), 0.35, 2.0)
        el = np.clip(u[None, :] / rl[:, None], 0, 1)
        er = np.clip((1 - u)[None, :] / rr[:, None], 0, 1)
        eu = np.minimum(el, er)
        eu = eu * eu * (3 - 2 * eu)
        alp = alp * eu
    else:
        eu = np.clip(np.minimum(u, 1 - u) / edge, 0, 1)
        eu = eu * eu * (3 - 2 * eu)
        alp = alp * eu[None, :]
    # the roots fade in (alpha 0 at v = 0, full by v = root_fade): a card's root edge never shows a line, and the
    # hairline / parting read as hair growing out of the scalp
    ev = np.clip((tt - root_clear) / root_fade, 0, 1)
    ev = ev * ev * (3 - 2 * ev)
    alp = alp * ev[:, None]
    return lum, alp


def _bleed(lum, alp, passes=6):
    """colour pushed into the transparent texels (mip levels do not halo dark or bright)"""
    w = alp.copy()
    l = lum * w
    out = lum.copy()
    for i in range(passes):
        r = 2 ** i
        bw = _blur(w, r)
        bl = _blur(l, r)
        fillv = bl / np.maximum(bw, 1e-5)
        m = (alp < 0.5) & (bw > 1e-4)
        k = np.clip(1 - alp * 2, 0, 1)
        out = np.where(m, out * (1 - k) + fillv * k, out)
    return out


def make_texture(path, size=TEX_SIZE, seed=1101, report=False):
    ss = 2  # drawn at 2x, box-filtered down
    W, H = size * ss, size * ss
    sw = W // 4
    specs = {
        # dense clump: the bulk of every layer; opaque nearly edge to edge, strands breaking out at the edges and tips
        "dense": dict(n_strands=int(sw * 0.8), spread=None, n_clumps=9, width_px=2.4, clump_k=0.35, fill=0.85,
                      len_min=0.9, clump_lo=0.93, stray=0.03, shade_lo=0.72, edge=0.13, tip_spread=0.16,
                      root_dark=0.1, rag=0.0, clump_shade=0.55, edge_thin=0.16, root_fade=0.07),
        # medium: a lighter lock (gaps between clumps; the layer under it shows through)
        "medium": dict(n_strands=int(sw * 0.45), spread=0.62, n_clumps=6, width_px=2.3, clump_k=0.55, fill=0.5,
                       len_min=0.78, clump_lo=0.86, root_soft=0.11, stray=0.05, shade_lo=0.68, edge=0.12,
                       tip_spread=0.2, root_dark=0.1, rag=0.0, clump_shade=0.5, edge_thin=0.12, root_fade=0.08),
        # wispy flyaways: a few loose strands, staggered lengths
        "wispy": dict(n_strands=int(sw * 0.14), n_clumps=4, width_px=2.0, clump_k=0.35, fill=0.0, len_min=0.3,
                      stray=0.35, shade_lo=0.65, edge=0.12, tip_spread=0.5, root_dark=0.05),
        # wavy: dense clumps on broad S-waves (2.5 waves root to tip), crests lighter
        "wavy": dict(n_strands=int(sw * 0.75), spread=None, n_clumps=7, width_px=2.5, clump_k=0.45, fill=0.8,
                     len_min=0.88, clump_lo=0.92, wave_amp=0.05, wave_per=2.5, stray=0.04, shade_lo=0.68, edge=0.13,
                     tip_spread=0.18, root_dark=0.1, rag=0.0, clump_shade=0.5, edge_thin=0.16, root_fade=0.07),
    }
    lum = np.zeros((H, W), np.float32)
    alp = np.zeros((H, W), np.float32)
    for i, (name, sp) in enumerate(specs.items()):
        l, a = _strip(sw, H, seed + 17 * i, **sp)
        lum[:, i * sw:(i + 1) * sw] = l
        alp[:, i * sw:(i + 1) * sw] = a
    # box filter to the final size (premultiplied)
    pl = (lum * alp).reshape(size, ss, size, ss).mean((1, 3))
    a = alp.reshape(size, ss, size, ss).mean((1, 3))
    l = pl / np.maximum(a, 1e-5)
    l = _bleed(l, a)
    l = np.clip(0.25 + 0.75 * np.clip(l, 0, 1), 0.25, 1.0)
    g = (l * 255 + 0.5).astype(np.uint8)
    A = (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)
    if report:
        q = size // 4
        for i, name in enumerate(specs):
            prof = a[int(size * 0.3):int(size * 0.6), i * q:(i + 1) * q].mean(0)
            print(name, " ".join(f"{x:.2f}" for x in prof[::16]))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(np.dstack([g, g, g, A]), "RGBA").save(path, optimize=True)
    return path




# =========================================================================================== reference
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

import hairlib as hl  # noqa: E402

REF = hl.REF
SK = hl.Skull()
C = SK.c.copy()
SKD = SK.data
SKF_PATH = os.path.join(REF, "skull_f.json")
SKF = hl.Skull(SKF_PATH) if os.path.exists(SKF_PATH) else None
EARS = [(np.array(SKD["ears"][s]["min"]), np.array(SKD["ears"][s]["max"])) for s in ("left", "right")]
FIT0 = dict(hl.FIT0)  # HairAssetData fit0 (the default male skull)
HEAD_LOW = -0.66 if hl.CLASSIC else -0.5  # (below this no part of the head: the full-head checks stop)
CLEAR_MIN = 0.0225  # every vertex over the head at least this far above the head meshes (both sexes, with ears) and the skull tables
EAR_CLEAR = 0.0225
AXIS_Z = 0.04  # the neck / body's vertical axis (x = 0, z = AXIS_Z)


def smooth(e0, e1, x):
    t = np.clip((np.asarray(x, dtype=np.float64) - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def unit(v):
    v = np.asarray(v, dtype=np.float64)
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-12)


def load_obj_mesh(path, obj):
    P, F, cur = [], [], None
    for line in open(path):
        if line.startswith("v "):
            P.append([float(x) for x in line.split()[1:4]])
        elif line.startswith("o "):
            cur = line.split(None, 1)[1].strip()
        elif line.startswith("f ") and cur == obj:
            ids = [int(t.split("/")[0]) - 1 for t in line.split()[1:]]
            for k in range(1, len(ids) - 1):
                F.append((ids[0], ids[k], ids[k + 1]))
    return np.asarray(P), F


def signed(bvh, p, maxd):
    """(nearest point, outward unit direction, signed distance) or None beyond maxd"""
    loc, n, _i, d = bvh.find_nearest(Vector(p), maxd)
    if loc is None:
        return None
    q = np.array(loc)
    nn = np.array(n)
    v = np.asarray(p) - q
    s = float(np.dot(v, nn))
    if d > 1e-7 and s >= 0:
        return q, v / d, d
    return q, nn, (-d if s < 0 else d)


class Ref:
    """the game's head (ears left out: thin shells give wrong inside / outside answers behind them; the ear boxes
    keep hair away from them) and upper torso, as BVH trees"""

    def __init__(self, sex):
        P, F = load_obj_mesh(os.path.join(REF, f"head_{sex}.obj"), "Head")
        sk = SKD
        if sex == "f" and SKF is not None:
            sk = SKF.data
        ears = [(np.array(sk["ears"][s]["min"]) - 0.012, np.array(sk["ears"][s]["max"]) + 0.012)
                for s in ("left", "right")]
        on_head = None
        if hl.CLASSIC:
            # the classic head: the ears are their own shells off its wall; only those are left out (no hole)
            Cc = SKD.get("classic") or {"r": 0.6, "h": 0.6, "round": 0.24}
            qx = np.sqrt(P[:, 0] ** 2 + P[:, 2] ** 2) - (Cc["r"] - Cc["round"])
            qy = np.abs(P[:, 1]) - (Cc["h"] - Cc["round"])
            sd = (np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2) + np.minimum(np.maximum(qx, qy), 0)
                  - Cc["round"])
            on_head = np.abs(sd) < 1e-3
        keep = [t for t in F if not any(np.all((P[list(t)] > lo) & (P[list(t)] < hi)) for lo, hi in ears)
                or (on_head is not None and on_head[list(t)].all())]
        self.headP, self.headF = P, F
        self.head = BVHTree.FromPolygons([tuple(p) for p in P], keep)
        # the whole head with the ears (unsigned distances: the clearance checks near the ears), in its own space
        # and, for the female head, mapped back into nominal space through the inverse runtime fit
        self.full = BVHTree.FromPolygons([tuple(p) for p in P], F)
        self.full_inv = None
        Pt, Ft = load_obj_mesh(os.path.join(REF, f"torso_{sex}.obj"), "UpperTorso")
        self.torsoP, self.torsoF = Pt, Ft
        self.torso = BVHTree.FromPolygons([tuple(p) for p in Pt], Ft)

    def height(self, p):
        r = signed(self.head, p, 1.0)
        return r[2] if r else 9.0


def make_refs():
    ref_m, ref_f = Ref("m"), Ref("f")
    Pn = inverse_fit(ref_f.headP, FIT_F)
    ref_f.full_inv = BVHTree.FromPolygons([tuple(p) for p in Pn], ref_f.headF)
    ref_m.full_inv = ref_m.full
    return ref_m, ref_f


def fit_of(sk):
    def plane_point(az, y_target):
        best = None
        for th in np.linspace(0.3, 2.6, 900):
            p = sk.point(th, math.radians(az))
            if best is None or abs(p[1] - y_target) < abs(best[1] - y_target):
                best = p
        return best
    return dict(W=plane_point(90, 0.15)[0], T=sk.c[1] + sk.radius(0.0, 0.0), Fz=plane_point(180, 0.2)[2],
                Bz=plane_point(0, 0.1)[2])


def female_fit():
    """the runtime skull fit (CONTRACT) that carries the pieces onto the default female skull"""
    if SKF is None:
        return dict(ax=0.965, ay=1.0, az=1.0, dz=0.0)
    ff = fit_of(SKF)
    return dict(ax=ff["W"] / FIT0["W"], ay=ff["T"] / FIT0["T"], az=(ff["Bz"] - ff["Fz"]) / (FIT0["Bz"] - FIT0["Fz"]),
                dz=(ff["Bz"] + ff["Fz"]) / 2 - (FIT0["Bz"] + FIT0["Fz"]) / 2)


FIT_F = female_fit()


def inverse_fit(P, fit):
    return (np.asarray(P) - [0, 0, fit["dz"]]) / [fit["ax"], fit["ay"], fit["az"]]


def near_full(bvh, p, maxd):
    """(unsigned distance, unit direction away from the surface) to the nearest point of a head with ears"""
    loc, n, _i, d = bvh.find_nearest(Vector(p), maxd)
    if loc is None:
        return None
    v = np.asarray(p) - np.array(loc)
    if d > 1e-7:
        u = v / d
        # inside a closed part of the mesh (the normal disagrees): push out along the normal instead
        if float(np.dot(u, np.array(n))) < -0.2 and not ear_zone(p):
            return -d, np.array(n)
        return d, u
    return 0.0, np.array(n)


def ear_zone(p):
    p = hl.org(p)
    return abs(p[0]) > 0.26 and -0.38 < p[1] < 0.12 and -0.02 < p[2] < 0.42


def apply_fit(P, fit):
    return np.asarray(P) * [fit["ax"], fit["ay"], fit["az"]] + [0, 0, fit["dz"]]


def skull_radius_v(sk, th, az):
    T = sk.th
    th = np.clip(th, T[0], T[-1])
    i = np.clip(np.searchsorted(T, th) - 1, 0, len(T) - 2)
    ti = (th - T[i]) / (T[i + 1] - T[i])
    n = len(sk.az)
    a = (az % TAU) / (TAU / n)
    j = np.floor(a).astype(np.int64) % n
    tj = a - np.floor(a)
    j2 = (j + 1) % n
    r = sk.r
    top = r[i, j] * (1 - tj) + r[i, j2] * tj
    bot = r[i + 1, j] * (1 - tj) + r[i + 1, j2] * tj
    return top * (1 - ti) + bot * ti


def polar(P, c):
    d = np.atleast_2d(P) - c
    r = np.linalg.norm(d, axis=1)
    th = np.arccos(np.clip(d[:, 1] / np.maximum(r, 1e-9), -1, 1))
    az = np.arctan2(d[:, 0], d[:, 2]) % TAU
    return d, r, th, az


def skull_height_v(sk, P):
    _d, r, th, az = polar(P, sk.c)
    return r - skull_radius_v(sk, th, az), th


def skull_push_v(P, off, th_max=2.55):
    """points pushed out radially to at least off above the male skull table and (through the female fit) the
    female one"""
    P = np.atleast_2d(np.asarray(P, dtype=np.float64))
    off = np.broadcast_to(np.asarray(off, dtype=np.float64), (len(P),))
    d, r, th, az = polar(P, C)
    need = skull_radius_v(SK, th, az) + off
    if SKF is not None:
        q = apply_fit(P, FIT_F)
        _dq, rq, thq, azq = polar(q, SKF.c)
        deficit = skull_radius_v(SKF, thq, azq) + off - rq
        need = np.where(thq <= th_max, np.maximum(need, r + deficit), need)
    m = (th <= th_max) & (r < need) & (r > 1e-6)
    out = P.copy()
    out[m] = C + d[m] / r[m, None] * need[m, None]
    return out


def ear_push(p, grow):
    """p pushed out of both ear boxes grown by grow (up, back, forward or outward: the nearest face)"""
    for lo, hi in EARS:
        lo2, hi2 = lo - grow, hi + grow
        if np.all(p > lo2) and np.all(p < hi2):
            side = 1.0 if lo[0] > 0 else -1.0
            cands = [(hi2[1] - p[1], 1, hi2[1]), (hi2[2] - p[2], 2, hi2[2]), (p[2] - lo2[2], 2, lo2[2])]
            cands.append((hi2[0] - p[0], 0, hi2[0]) if side > 0 else (p[0] - lo2[0], 0, lo2[0]))
            _d, ax, val = min(cands)
            p = p.copy()
            p[ax] = val
    return p


# ------------------------------------------------------------------------------------------- hairline
def _hairline(kind="Natural"):
    ln = SKD["hairline"]["lines"][kind]
    pts = [e[1:4] for side in ("right", "left") for e in ln[side] if e and len(e) >= 4]
    hgt = np.array([e for e in ln["height"] if e], dtype=np.float64)
    return np.array(pts, dtype=np.float64), hgt


HL_PTS, HL_H = _hairline()


def da_of(P):
    P = np.atleast_2d(P)
    return np.arctan2(np.abs(P[:, 0]), 0.05 - P[:, 2])


def hairline_y(P):
    return np.interp(da_of(P), HL_H[:, 0], HL_H[:, 1])


def scalp_of(P):
    d, _r, th, az = polar(P, C)
    r = skull_radius_v(SK, th, az)
    return C + unit(d) * r[:, None]


def edge_dist(P):
    """signed distance (studs) from the scalp point under P to the natural hairline: + inside the hair"""
    s = scalp_of(P)
    dd = np.sqrt(((s[:, None, :] - HL_PTS[None, :, :]) ** 2).sum(-1)).min(1)
    inside = s[:, 1] - hairline_y(s)
    return np.where(inside >= 0, dd, -dd)


def recess(P):
    """the style's own hairline, this far inside the natural one: receding into the temple corners (0.05 at the
    corner), a fine irregular zigzag everywhere (no straight brim), the centre at the natural line"""
    P = np.atleast_2d(P)
    da = da_of(P)
    dsg = np.arctan2(P[:, 0], 0.05 - P[:, 2])
    r = 0.05 * np.exp(-((da - 0.64) / 0.2) ** 2) + 0.012 * smooth(0.25, 0.5, da) * smooth(1.1, 0.85, da)
    zig = 0.0045 * np.sin(dsg * 47.0 + 0.4) + 0.003 * np.sin(dsg * 113.0 + 1.3) + 0.002 * np.sin(dsg * 211.0)
    return np.maximum(0.0, r + zig + 0.004)


def style_edge(P):
    """signed distance from the scalp point under P to the style's hairline (+ inside the hair)"""
    return edge_dist(P) - recess(P)


def theta_at(az, f_ok, lo=0.02, hi=2.55):
    """the largest polar angle at azimuth az (rad) where f_ok(scalp point) still holds (bisection; f_ok true
    near the top of the head)"""
    for _ in range(36):
        m = (lo + hi) / 2
        if f_ok(SK.point(m, az)):
            lo = m
        else:
            hi = m
    return lo


# =========================================================================================== styles
# layers, innermost first. n: strands per side; off: (top, side) height above the scalp (the side is the fuller: the
# hair piles up as it falls from the parting over the parietal bulge); strips {strip: weight}; margin: kept this far
# inside the natural hairline; tip: tip y at length 0.5 (and its spread); wmax: (over the head, hanging) card width
# limit; overlap: card width / spacing to the nearest neighbour card of the same layer (coverage: > 1 everywhere);
# rel: release heights (behind the ear, back centre) where the strands leave the head.
LAYERS = [
    # the hairline layer: rooted along the front hairline (centre to the temple), swept back over the top of the ear
    dict(name="edge", n=8, off=(0.03, 0.032), gap=0.08, strips={"dense": 0.55, "medium": 0.45}, margin=0.007, tip=-0.72,
         tip_var=0.05, wmax=(0.15, 0.17), overlap=1.75, shade=0.97, phase=0.0, rel=(0.03, 0.0), root="hairline",
         fmax=0.3),
    # the dense scalp layer (hides the scalp; the painted cap under it)
    dict(name="scalp", n=12, off=(0.029, 0.031), gap=0.08, strips={"dense": 1.0}, margin=0.016, tip=-1.3, tip_var=0.05,
         wmax=(0.2, 0.17), overlap=1.9, shade=0.93, phase=0.0, rel=(0.0, -0.13)),
    # the volume: every layer higher, the sides fuller than the top
    dict(name="inner", n=13, off=(0.076, 0.09), gap=0.12, strips={"dense": 0.85, "medium": 0.15}, margin=0.024, tip=-1.4,
         tip_var=0.06, wmax=(0.2, 0.17), overlap=1.7, shade=0.965, phase=0.37, lift0=0.0, ramp=0.2, rel=(0.05, -0.05)),
    dict(name="main", n=13, off=(0.114, 0.13), gap=0.16, strips={"dense": 0.75, "medium": 0.25}, margin=0.03,
         tip=-1.48, tip_var=0.07, wmax=(0.2, 0.18), overlap=1.6, shade=0.985, phase=0.71, lift0=0.3, ramp=0.14,
         rel=(0.09, 0.03)),
    dict(name="outer", n=10, off=(0.15, 0.165), gap=0.2, strips={"dense": 0.5, "medium": 0.5}, margin=0.036,
         tip=-1.46, tip_var=0.08, wmax=(0.23, 0.19), overlap=1.6, shade=1.0, phase=0.19, lift0=0.32, ramp=0.16,
         rel=(0.12, 0.08)),
]
LAYER = {L["name"]: L for L in LAYERS}
THREE_COL = ("main", "outer")
# the layers rise out of the hairline over this distance (the outer ones over a longer one: the hair mass builds up
# from the forehead instead of standing on it as a brim)
HL_RAMP = {"edge": 0.19, "scalp": 0.19, "inner": 0.26, "main": 0.33, "outer": 0.4}


def hl_ramp(layer, P):
    """the rise distance from the hairline: the full HL_RAMP over the forehead, half of it over the temples and the
    sides (the side silhouette stands off the head there)"""
    r = HL_RAMP.get(layer, 0.19)
    return r * (1 - 0.5 * smooth(0.4, 0.8, da_of(P)))  # layers whose cards get a middle column over the head (no shingle steps)
SINGLE_SIDED = ("edge", "scalp", "inner", "hairline", "partx")
FLYAWAYS = dict(n=0, strip="wispy", w=(0.03, 0.045), len=(0.16, 0.3), shade=1.0)

STYLES = {
    "long": dict(entry=dict(styles=["Long Hair"], types=["Straight"], cap={"cut": "full", "density": 1}),
                 wavy=False, volume=1.0, seed=7),
    "long_wavy": dict(entry=dict(styles=["Long Hair"], types=["Wavy"], cap={"cut": "full", "density": 1}),
                      wavy=True, volume=1.1, seed=8),
}

PSI_FRONT = 1.125  # part angle (from +Y toward the face) just inside the front hairline
PSI_BACK = -0.32  # the part's back end, behind the crown
PART_X = 0.005  # the subtle centre parting: roots this far either side of x = 0 (the cap shows as scalp between)
PSI_PART_END = 0.15  # the parting ends here, before the crown: behind it the roots cross the centre line
PART_CROSS = 0.04
AZ_EAR = 56.0  # the frontmost release azimuth (degrees from the back): just behind the ear
LOCK_AZ = 41.0  # strands released further forward than this (just behind the ear) drape forward over the shoulder
ANCHOR_Y = {"back": -0.14, "side": -0.2}  # hanging chains start here (their pivot height)
SEG2_Y = {"back": -0.80, "side": -0.80}  # and the second segment from here (the shoulders)
CHAINS = ["HairClump01", "HairClump02", "HairClump03", "HairClump04", "HairClump05", "HairClump06"]
HAIRLINE_CARDS = True  # a ring of short sparse wispy cards rooted on the hairline (an irregular growing edge)
HAIRFX = dict(stiff=0.3, mass=1.0, mass2=0.8)
# the classic head (ref/classic): its ears sit further back round the head (the release behind them at ~70 deg from
# the back), the hair falls straight from its vertical side walls (the jaw-line cone below the head's bottom
# corner, as wide as the head), and the chains swing only from below the head
CL = dict(yA=-0.45, rA_min=0.0, lock_x=0.53, tx=(0.36, 0.2), head_y=0.2, oh_y=-0.4, ear_band=(-0.35, 0.15, 0.2),
          vol_band=(-0.08, -0.42, -0.84, -0.7), over_ear=(0.2, -0.06, 0.31, 0.02))
if hl.CLASSIC:
    AZ_EAR, LOCK_AZ = 70.0, 52.0
    ANCHOR_Y = {"back": -0.52, "side": -0.55}
    CL = dict(yA=-0.66, rA_min=0.64, lock_x=0.74, tx=(0.56, 0.18), head_y=0.62, oh_y=-0.62,
              ear_band=(-0.25, 0.33, 0.42), vol_band=(-0.5, -0.68, -0.92, -0.8), over_ear=(0.42, -0.11, 0.29, 0.1))
    for _L, _n in zip(LAYERS, (8, 13, 14, 13, 10)):
        _L["n"] = _n  # (the larger head: ~1.1x the strands per layer, the cards a little wider)
        _L["wmax"] = (_L["wmax"][0] * 1.12, _L["wmax"][1] * 1.06)
SEG_OVERLAP = 0.05  # chain joints: segment 2 overlaps segment 1 by this much (no seam when they swing)


def psi_root(f, layer):
    """the root's part angle for a strand at f: the volume layers' roots end at the end of the parting (their back
    strands sweep over the crown at full height: no root ends, no notch there); the layers under them run on to
    behind the crown"""
    pb = PSI_PART_END - 0.06 if layer["name"] in ("main", "outer") else PSI_BACK
    return PSI_FRONT + (pb - PSI_FRONT) * f


def part_point(psi, side, cross=None):
    d = np.array([0.0, math.cos(psi), -math.sin(psi)])
    p = C + d * SK.radius(*SK.angles(d))
    if cross is None:
        cross = PART_CROSS * float(smooth(PSI_PART_END, PSI_PART_END - 0.25, psi))
    p[0] = side * PART_X - side * cross
    return scalp_of(p)[0]


def release_az(f):
    """release azimuth (rad, from the back, unsigned) of a strand at f along the parting (0 front .. 1 back)"""
    return math.radians(AZ_EAR) * (1 - f) ** 1.1


def release_point(f, side, rel):
    """where a strand leaves the head: every strand goes over the top of the ear and leaves behind it (f = 0, just
    behind the ear) round the back to the centre (f = 1), at the layer's heights rel = (behind the ear, back
    centre): the outer layers leave near the widest part of the head and fall straight, the inner ones follow the
    skull further under the occiput"""
    az = side * release_az(f)
    y = rel[0] + (rel[1] - rel[0]) * f
    if hl.CLASSIC:
        y = float(hl.unorg(np.array([0.3, y, 0.3]))[1])  # (the organic release heights, mapped)
    th = theta_at(az, lambda p: p[1] > y)
    return SK.point(th, az)


def scalp_path(f, side, layer, vol, rng, n=48):
    """the strand's path over the scalp (points ON the skull, then lifted by offs): a great circle from its root
    on the parting (or the hairline) to its release point, kept a margin inside the natural hairline and above the
    ear"""
    if layer.get("root") == "hairline":
        # on the hairline at da (temple .. front centre), just inside it
        da_r = 1.02 * (1 - f / layer["fmax"]) + 0.03
        hp = HL_PTS[HL_PTS[:, 0] > 0] if side > 0 else HL_PTS[HL_PTS[:, 0] <= 0]
        dd = da_of(hp)
        o = np.argsort(dd)
        hp, dd = hp[o], dd[o]
        hp, dd = hp[dd < 1.22], dd[dd < 1.22]
        h = np.array([np.interp(da_r, dd, hp[:, k]) for k in range(3)])
        th, az = SK.angles(h - C)
        R = SK.point(theta_at(az, lambda q: style_edge(q[None])[0] >= layer["margin"], hi=th + 0.05), az)
        Q = release_point(0.05 + f * 0.5, side, layer["rel"])
    else:
        psi = psi_root(f, layer)
        cross = None
        if layer["name"] in ("main", "outer"):
            cross = PART_CROSS * float(smooth(0.8, 1.0, f))  # the backmost cross the centre line
        R = part_point(psi, side, cross)
        Q = release_point(f, side, layer["rel"])
    a, b = unit(R - C), unit(Q - C)
    om = math.acos(float(np.clip(np.dot(a, b), -1, 1)))
    t = np.linspace(0, 1, n)
    D = (np.sin((1 - t) * om)[:, None] * a + np.sin(t * om)[:, None] * b) / math.sin(om)
    hw = 0.05
    margin = layer["margin"]
    for _it in range(4):
        _d, _r, th, az = polar(C + D, C)
        P = C + D * skull_radius_v(SK, th, az)[:, None]
        for i in range(1, n - 1):
            p = P[i]
            # inside the hairline by the margin (the front strands run along it: their front edge is the hairline)
            if style_edge(p[None])[0] < margin:
                th_i = theta_at(az[i], lambda q: style_edge(q[None])[0] >= margin, lo=0.02, hi=th[i])
                p = SK.point(th_i, az[i])
            # above the ear: its box top + clearance + the card's half width (the card lies near vertical there)
            ox, oz0, oz1, oy = CL["over_ear"]
            if side * p[0] > ox and oz0 < p[2] < oz1:
                ytop = EARS[0][1][1] + EAR_CLEAR + hw * 0.9 + 0.012
                k = smooth(oz1, oz1 - 0.06, p[2]) * smooth(oz0, oz0 + 0.11, p[2])
                ylim = oy + (ytop - oy) * k
                if p[1] < ylim:
                    th_i = theta_at(az[i], lambda q: q[1] >= ylim, lo=0.02, hi=th[i])
                    p = SK.point(th_i, az[i])
            P[i] = p
        # relax (keep the ends): no kinks where the guards bent the path
        D = unit(P - C)
        for _s in range(3):
            D[1:-1] = unit(D[1:-1] * 0.5 + (D[:-2] + D[2:]) * 0.25)
    _d, _r, th, az = polar(C + D, C)
    P = C + D * skull_radius_v(SK, th, az)[:, None]
    # heights: rising out of the parting and the hairline, fuller over the sides
    s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    ed = style_edge(P)
    base = 0.0225
    o_top, o_side = layer["off"]
    yk = smooth(0.14, 0.5, hl.org(P)[:, 1])
    tgt = (o_side + (o_top - o_side) * yk) * vol
    # the sides gather in toward the ear (the hair tucks behind it): no shelf over the ear, a rounded silhouette
    sideness = smooth(0.55, 0.9, np.abs(P[:, 0]) / np.maximum(np.linalg.norm((P - C)[:, [0, 2]], axis=1), 1e-6))
    tgt = tgt * (1 - 0.3 * smooth(0.3, 0.06, hl.org(P)[:, 1]) * sideness)
    if layer.get("root") != "hairline":
        # the frontmost strands (the lower edge of every layer, over the temple and the ear) lie lower: the layers
        # thin out into the temple instead of ending in stacked shelves
        tgt = base + (tgt - base) * (0.62 + 0.38 * smooth(0.0, 0.55, f))
    # the deeper layers rise out of the parting from the scalp; the upper ones lie over them already lifted (a
    # narrow parting groove under a smooth dome, not a ridge either side of the parting)
    k0 = layer.get("lift0", 0.0)
    if layer.get("root") != "hairline" and layer["name"] not in ("main", "outer"):
        # behind the end of the parting the roots cross the centre line already lifted (no groove to the crown)
        k0 = max(k0, 0.4 * float(smooth(PSI_PART_END, PSI_PART_END - 0.3, psi)))
    # (from the scalp at the parting: an upper layer starting lifted shows its root edge end-on along the part)
    ramp = np.minimum(k0 + (1 - k0) * smooth(0.0, layer.get("ramp", 0.2), s), smooth(0.0, hl_ramp(layer["name"], P), ed))
    off = base + (tgt - base) * ramp
    Pn = C + unit(P - C) * (np.linalg.norm(P - C, axis=1) + off)[:, None]
    return Pn, off, s


# =========================================================================================== guides
class Strand:
    __slots__ = ("side", "f", "layer", "li", "scalp", "off", "hang", "tip_y", "lock", "strip", "mirror", "v0",
                 "seed", "G", "s_rel", "wave_ph", "body_off", "w", "fly", "vend", "shade", "order", "rootk", "gap",
                 "az_rel", "s0")

    def __init__(self, **kw):
        for k in self.__slots__:
            setattr(self, k, kw.get(k))
        if self.vend is None:
            self.vend = 1.0
        if self.order is None:
            self.order = self.li


def pick(rng, weights):
    keys = list(weights)
    p = np.array([weights[k] for k in keys], dtype=np.float64)
    return keys[int(rng.choice(len(keys), p=p / p.sum()))]


def make_strands(cfg, log):
    rng = np.random.default_rng(cfg["seed"])
    vol = cfg["volume"]
    out = []
    for li, L in enumerate(LAYERS):
        n = L["n"]
        for side in (1, -1):
            for i in range(n):
                f = (i + 0.5 + L["phase"] * 0.8 + rng.uniform(-0.15, 0.15)) / (n + 0.4)
                f = float(np.clip(f, 0.0, 1.0)) * L.get("fmax", 1.0)
                P, off, _s = scalp_path(f, side, L, vol, rng)
                Q = P[-1]
                az = math.degrees(abs(math.atan2(Q[0], Q[2] - AXIS_Z)))
                lock = az > LOCK_AZ
                # the hem: nearly straight across the back (a slight U), the side locks ending on the front of the
                # shoulder (resting on it), every card staggered (no straight cut)
                if lock:
                    # the side sheets: over the front of the shoulder onto the upper chest
                    tip = -1.26 - 0.08 * rng.uniform(0, 1) + rng.normal(0, 0.02) + (0.06 if li < 2 else 0.0)
                    if L["tip"] > -1.0:
                        tip = L["tip"] + rng.normal(0, 0.02)  # (a hidden layer ending under the others)
                else:
                    # a level hem with a slight U (the sides a little shorter), staggered per card
                    tip = L["tip"] - 0.03 * smooth(0.2, 1.0, f) + 0.05 * (az / LOCK_AZ) ** 2
                    tip += rng.uniform(-1, 1) * L["tip_var"] + rng.normal(0, 0.025)
                strip = pick(rng, L["strips"])
                if L["name"] == "outer" and f > 0.6 and rng.random() < 0.2:
                    strip = "wispy"  # a few loose outer cards, at the back only (never over the front 120 degrees)
                if cfg["wavy"] and strip in ("dense", "medium") and li >= 2 and rng.random() < 0.85:
                    strip = "wavy"
                psi = psi_root(f, L)
                # (no darker roots where they cross over the crown or rise from the parting on top: they show
                # edge-on against the sky there)
                rk = 1.0 if (L.get("root") == "hairline" or psi < PSI_PART_END + 0.1
                             or L["name"] in ("main", "outer")) else 0.86
                out.append(Strand(side=side, f=f, layer=L["name"], li=li, scalp=P, off=off, tip_y=tip, lock=lock,
                                  strip=strip, mirror=bool(rng.random() < 0.5), v0=float(rng.uniform(0, 0.02)),
                                  seed=int(rng.integers(1 << 30)), wave_ph=float(f * 2.2 + li * 0.5 + rng.normal(0, 0.25)),
                                  body_off=(0.02 if lock else 0.013) + 0.005 * li, w=None, fly=False, rootk=rk,
                                  gap=L["gap"] * vol, az_rel=az))
    log(f"  {len(out)} strands ({sum(st.lock for st in out)} forward locks)")
    return out


_BODY = SKD["body"]["surface"]
BODY_Y = np.array([r[0] for r in _BODY["rows"]], dtype=np.float64)  # descending, 0.05 apart
BODY_R = np.array([r[1] for r in _BODY["rows"]], dtype=np.float64)  # (rows, 36 azimuths: 0 = +Z back, 90 = +X)


def body_r(y, az):
    """the body proxy's radius (neck capsule, trapezius, torso; skull.json body) from the axis x = z = 0 at height
    y and azimuth az (rad, from +Z toward +X)"""
    y = np.asarray(y, dtype=np.float64)
    fy = np.clip((BODY_Y[0] - y) / (BODY_Y[0] - BODY_Y[1]), 0, len(BODY_Y) - 1.001)
    i = np.floor(fy).astype(np.int64)
    ty = fy - i
    a = (np.asarray(az) % TAU) / (TAU / BODY_R.shape[1])
    j = np.floor(a).astype(np.int64) % BODY_R.shape[1]
    tj = a - np.floor(a)
    j2 = (j + 1) % BODY_R.shape[1]
    r0 = BODY_R[i, j] * (1 - tj) + BODY_R[i, j2] * tj
    r1 = BODY_R[i + 1, j] * (1 - tj) + BODY_R[i + 1, j2] * tj
    return r0 * (1 - ty) + r1 * ty


def volume_push(P, gap):
    """the hanging mass: points between the jaw line and the shoulders kept at least gap (flaring in from the
    release, out to the full gap by the jaw, back to nothing on the shoulders) outside the body proxy (the hair's
    own volume holds it off the neck: a cone from behind the ears, not ropes on the neck)"""
    P = np.atleast_2d(P)
    y = P[:, 1]
    b0, b1, b2, b3 = CL["vol_band"]
    g = np.asarray(gap) * smooth(b0, b1, y) * smooth(b2, b3, y)  # (below: the proxy trapezius, far wider than the torsos)
    r = np.hypot(P[:, 0], P[:, 2])
    az = np.arctan2(P[:, 0], P[:, 2])
    need = body_r(y, az) + g
    m = (g > 1e-4) & (r < need) & (np.abs(az) < math.radians(115)) & (r > 1e-6)
    out = P.copy()
    out[m, 0] *= need[m] / r[m]
    out[m, 2] *= need[m] / r[m]
    return out


def chain_smooth(X, passes=2, k=0.3):
    X = X.copy()
    for _ in range(passes):
        Y = X.copy()
        Y[:, 1:-1] = X[:, 1:-1] * (1 - k) + (X[:, :-2] + X[:, 2:]) * (k / 2)
        X = Y
    return X


class Body:
    """the upper torso (male and female together: the outermost of the two) probed with Blender BVH ray casts:
    its top surface under a point and its front / back face at a height"""

    def __init__(self, refs):
        self.trees = [ref.torso for ref in refs]

    def top(self, x, z):
        best = None
        for t in self.trees:
            loc, _n, _i, _d = t.ray_cast(Vector((x, -0.3, z)), Vector((0.0, -1.0, 0.0)), 2.0)
            if loc is not None and (best is None or loc[1] > best):
                best = float(loc[1])
        return best

    def face(self, x, y, d):
        """z of the back (d = +1) or front (d = -1) face at (x, y): the outermost hit of a ray coming in"""
        best = None
        for t in self.trees:
            loc, _n, _i, _d = t.ray_cast(Vector((x, y, 2.0 * d)), Vector((0.0, 0.0, -d)), 4.0)
            if loc is not None and (best is None or loc[2] * d > best * d):
                best = float(loc[2])
        return best


BODY_TREES = []  # the torsos (set by build_style): the hanging cards lie flat on them


def hang_normals(P):
    """the outward direction of a hanging card: away from the body axis, turning to the torso's surface normal
    where the card lies on it (over the shoulder a card lies flat on it instead of standing up as a fin)"""
    P = np.atleast_2d(P)
    h = unit(np.stack([P[:, 0], np.zeros(len(P)), P[:, 2] - AXIS_Z], 1))
    out = h.copy()
    for i, p in enumerate(P):
        best = None
        for t in BODY_TREES:
            r = signed(t, p, 0.14)
            if r is not None and (best is None or r[2] < best[2]):
                best = r
        if best is not None:
            w = float(smooth(0.13, 0.05, best[2]))
            out[i] = unit(h[i] * (1 - w) + best[1] * w)
    return out


def bezier(P0, P1, P2, P3, n):
    t = np.linspace(0, 1, n)[:, None]
    return ((1 - t) ** 3) * P0 + 3 * ((1 - t) ** 2) * t * P1 + 3 * (1 - t) * t * t * P2 + (t ** 3) * P3


def resample(P, step):
    P = np.asarray(P)
    s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    n = max(3, int(math.ceil(s[-1] / step)) + 1)
    return at_s(P, s, np.linspace(0, s[-1], n))


def drape_path(st, body, phi, tx):
    """the hanging part of one strand, constructed (not simulated): from its release point Q fanning out to the
    hanging cone at the jaw line (azimuth phi about the body axis, the layer's gap outside the neck: the hair's own
    volume), falling to the shoulder, then lying on the torso: the side sheets (st.lock) over the top of the
    shoulder at x = tx and down its front onto the upper chest, the back curtain back over the trapezius and down
    the shoulder blades. Points about 0.02 apart, down to below the strand's tip height."""
    Q = st.scalp[-1]
    TQ = unit(st.scalp[-1] - st.scalp[-3])
    bo = st.body_off
    yA = CL["yA"]
    rA = max(float(body_r(yA, phi)) + st.gap, CL["rA_min"] + 0.5 * st.gap)
    A = np.array([rA * math.sin(phi), yA, rA * math.cos(phi)])
    if st.lock:
        A[0] = math.copysign(min(abs(A[0]), CL["lock_x"]), A[0])
    # release -> the cone (leaving the head along the strand's own direction, turning down)
    seg1 = bezier(Q, Q + TQ * 0.09 + np.array([0, -0.03, 0]), A + np.array([0, 0.13, 0]), A, 16)
    pts = list(seg1)
    # straight down the cone (the side sheets drifting to their own x), to the torso
    x_t = math.copysign(tx, A[0]) if st.lock else A[0]
    y = yA
    land = None
    while y > -1.6:
        y -= 0.02
        k = float(smooth(yA, -0.85, y))
        x = A[0] + (x_t - A[0]) * k if st.lock else A[0]
        z = A[2]
        ty = body.top(x, z)
        if ty is not None and y < ty + bo:
            land = (x, ty + bo, z)
            break
        pts.append(np.array([x, y, z]))
    if land is None:
        return resample(pts, 0.02)
    x, y, z = land
    pts.append(np.array(land))
    d = -1.0 if st.lock else 1.0  # over the shoulder: forward (the side sheets) or back (the curtain)
    # along the top of the shoulder until it falls away
    for _k in range(80):
        z2 = z + d * 0.012
        ty = body.top(x, z2)
        if ty is None or ty + bo < y - 0.014:
            break
        z, y = z2, ty + bo
        pts.append(np.array([x, y, z]))
    # down the face (front of the shoulder and the chest, or the back), x drifting to the hem
    x_hem = x if st.lock else x * 1.04
    y0 = y
    while y > st.tip_y - 0.06:
        y -= 0.02
        xx = x + (x_hem - x) * float(smooth(y0, y0 - 0.4, y))
        fz = body.face(xx, y, d)
        if fz is None:
            fz = z
        z = fz + d * bo if d * (fz + d * bo) > d * z - 0.03 else z  # never back into the body, never jumping
        pts.append(np.array([xx, y, z]))
    return resample(pts, 0.02)


def hang_strands(strands, refs, cfg, log):
    """the hanging parts, draped over the body (drape_path), then collided (skull tables, both heads, ear boxes,
    both torsos, the hanging volume) and smoothed a few times"""
    t0 = time.time()
    body = Body(refs)
    rs = np.random.default_rng(cfg["seed"] + 3)
    # side sheets' x on the shoulder: per layer, by release azimuth (the backmost furthest out): a sheet ~0.2 wide
    tx = {}
    for li in range(len(LAYERS)):
        for sd in (1, -1):
            ids = [i for i, st in enumerate(strands) if st.lock and st.li == li and st.side == sd]
            ids.sort(key=lambda i: strands[i].az_rel)
            for r, i in enumerate(ids):
                g = (r + 0.5) / max(1, len(ids))
                tx[i] = CL["tx"][0] + CL["tx"][1] * (1 - g) + rs.uniform(-0.015, 0.015)
    for i, st in enumerate(strands):
        a = st.az_rel
        if st.lock:
            ph = 64 + 30 * float(np.clip((a - LOCK_AZ) / max(1e-6, AZ_EAR - LOCK_AZ), 0, 1))
        else:
            ph = a * 68.0 / LOCK_AZ
        phi = math.radians(ph) * st.side
        H = drape_path(st, body, phi, tx.get(i, 0.0))
        # collide + smooth (the release end fixed)
        for _it in range(4):
            Hn = collide_pts(H, st.off[-1], st.body_off, refs)
            Hn = volume_push(Hn, st.gap * 0.85)
            Hn[0] = H[0]
            H = chain_smooth(Hn[None], 1, 0.35)[0]
            H[0] = Hn[0]
        H = collide_pts(H, st.off[-1], st.body_off, refs)
        below = np.nonzero(H[:, 1] < st.tip_y)[0]
        if len(below) and below[0] > 1:
            j = int(below[0])
            a_, b_ = H[j - 1], H[j]
            t = (a_[1] - st.tip_y) / max(1e-9, a_[1] - b_[1])
            H = np.vstack([H[:j], a_ + (b_ - a_) * t])
        st.hang = H
        st.s_rel = None
    log(f"  drape {len(strands)} strands: {time.time() - t0:.1f}s")
    return strands


def collide_pts(P, off, body_off, refs, head=True):
    """points out of the skull tables, the head meshes, both torsos and the ear boxes"""
    P = skull_push_v(P, off)
    off = np.broadcast_to(np.asarray(off, dtype=np.float64), (len(P),))
    body_off = np.broadcast_to(np.asarray(body_off, dtype=np.float64), (len(P),))
    for idx in range(len(P)):
        p = P[idx]
        if head and p[1] < CL["head_y"]:
            oh = off[idx] if p[1] > CL["oh_y"] else min(off[idx], body_off[idx] + 0.01)
            for ref in refs:
                r = signed(ref.head, p, oh + 0.06)
                if r is not None and r[2] < oh:
                    p = r[0] + r[1] * oh
        if p[1] < -0.45:
            for ref in refs:
                r = signed(ref.torso, p, body_off[idx] + 0.06)
                if r is not None and r[2] < body_off[idx]:
                    p = r[0] + r[1] * body_off[idx]
        if CL["ear_band"][0] < p[1] < CL["ear_band"][1] and abs(p[0]) > CL["ear_band"][2]:
            p = ear_push(p, EAR_CLEAR + 0.03)
        P[idx] = p
    return P


def densify(P, sub=4):
    """Catmull-Rom through P -> (dense points, arc length at each)"""
    P = np.asarray(P)
    ext = np.vstack([2 * P[0] - P[1], P, 2 * P[-1] - P[-2]])
    out = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for t in np.linspace(0, 1, sub, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(P[-1])
    D = np.array(out)
    s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(D, axis=0), axis=1))])
    return D, s


def at_s(D, S, s):
    s = np.atleast_1d(s)
    return np.stack([np.interp(s, S, D[:, k]) for k in range(3)], -1)


def finish_guides(strands, refs, cfg, log):
    """scalp part + hanging part = the guide; the Wavy entry's S-waves down the hanging part"""
    for st in strands:
        G = np.vstack([st.scalp, st.hang[1:]])
        s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(G, axis=0), axis=1))])
        st.s_rel = float(s[len(st.scalp) - 1])
        if cfg["wavy"]:
            # waves from just above the release (the ear line / under the occiput), growing toward the tips; every
            # clump of cards (a 22 degree sector of release azimuth, the locks their own) shares a phase, period
            # and amplitude, so the hair waves in S-shaped clumps and the hem does not repeat
            Q = st.scalp[-1]
            sector = int(math.floor(math.degrees(math.atan2(Q[0], Q[2] - AXIS_Z)) / 22.0)) + (100 if st.lock else 0)
            cr = np.random.default_rng(abs(sector) * 7919 + cfg["seed"] * 31 + (1 if sector < 0 else 0))
            c_amp, c_per, c_ph = cr.uniform(0.8, 1.2), cr.uniform(0.48, 0.58), cr.uniform(0, TAU)
            sh = s - st.s_rel
            amp = 0.038 * c_amp * smooth(-0.06, 0.25, sh) * (0.7 + 0.5 * smooth(0.0, 1.0, sh))
            amp = amp * (1 + 0.1 * math.sin(st.seed % 97))
            if st.layer in ("main", "outer"):
                # a low wave already on the head from the ear line down (the side silhouette shows it)
                amp = amp + 0.011 * smooth(-0.34, -0.14, sh) * (1 - smooth(-0.06, 0.2, sh))
            T = unit(np.gradient(G, axis=0))
            out = unit(np.stack([G[:, 0], np.zeros(len(G)), G[:, 2] - AXIS_Z], 1))
            lat = unit(np.cross(T, out))
            ph = TAU * sh / c_per + c_ph + 0.25 * math.sin(st.wave_ph)
            # a planar wave (sideways, a little in and out with the same phase): S-shapes, no helix / rope twist
            G = G + (np.sin(ph)[:, None] * (lat * 0.85 + out * 0.3)) * amp[:, None]
            m = sh > -0.36
            G[m] = collide_pts(G[m], st.off[-1], st.body_off, refs)
        st.G = G
    return strands


ROOT_V = 0.09  # the texture's root fade (clear to v 0.015, full by ~0.085) ...
EDGE_IN = 0.006  # card edges this far inside the hairline
# ... is mapped onto this much of every card's root (studs), whatever the card's length: longer on the layers
# whose roots show (the outer ones rising out of the parting, the hairline cards)
ROOT_LEN = {"edge": 0.04, "hairline": 0.03, "main": 0.05, "outer": 0.06, "partx": 0.03}


def root_len(L, layer=None):
    return min(ROOT_LEN.get(layer, 0.025), L * 0.3)


def card_v(s, L, v0, v1, layer=None, s0=0.0):
    """v along a card (from its first row s0): the root fade over the first root_len studs, then linear to the
    tip"""
    s = np.asarray(s) - s0
    L = L - s0
    sr = root_len(L, layer)
    t = np.where(s < sr, ROOT_V * s / sr, ROOT_V + (1 - ROOT_V) * (s - sr) / max(1e-6, L - sr))
    return v0 + (v1 - v0) * t


def card_rows(st, cfg, rng=None):
    """sample the guide into card rows (arc lengths), with rows forced at the chain splits; returns a dict"""
    D, S = densify(st.G, 4)
    L = float(S[-1])
    kind = "side" if st.lock else "back"
    splits = {}
    for nm, yv in (("a", ANCHOR_Y[kind]), ("b", SEG2_Y[kind])):
        j = np.nonzero((D[:, 1] < yv) & (S > st.s_rel))[0]
        if len(j) and not st.fly:
            j = int(j[0])
            t = (D[j - 1, 1] - yv) / max(1e-9, D[j - 1, 1] - D[j, 1])
            splits[nm] = float(S[j - 1] + (S[j] - S[j - 1]) * t)
    if "a" in splits and "b" in splits and splits["b"] - SEG_OVERLAP > splits["a"] + 0.05:
        splits["b0"] = splits["b"] - SEG_OVERLAP  # segment 2 starts this far above its pivot (tucked under seg 1)
    # rows: finer where the guide bends (turning per stud), coarse down the straight hanging part
    Tn = unit(np.gradient(D, axis=0))
    ang = np.arccos(np.clip((Tn[1:] * Tn[:-1]).sum(1), -1, 1))
    kap = np.concatenate([[0], ang / np.maximum(np.diff(S), 1e-6)])
    kap = np.convolve(kap, np.ones(7) / 7, mode="same")
    hmin_hang, hmax_hang = (0.12, 0.15) if cfg["wavy"] else (0.11, 0.22)
    # the volume layers' cards start at staggered points along their strands (no row of card ends lined up
    # along the parting)
    s0 = 0.0
    if rng is not None and st.layer in ("main", "outer"):
        s0 = float(rng.uniform(0.0, 0.028 if st.f < 0.4 else 0.05))
    st.s0 = s0
    sr = root_len(L - s0, st.layer)
    rows = [s0, s0 + sr]
    s = s0 + sr
    while s < L - 1e-6:
        k = float(np.interp(s, S, kap))
        if s < st.s_rel and st.layer == "outer":
            # over the head: a row every <= 0.04 of arc over the crown and the top (a smooth silhouette, no
            # stair steps), 0.06 down the sides
            yy = float(np.interp(s, S, D[:, 1]))
            hmin, hmax, kk = 0.038, (0.04 if yy > 0.36 else 0.07), 0.3
        elif s < st.s_rel and st.layer == "main":
            hmin, hmax, kk = 0.07, 0.1, 0.3  # (under the outer layer)
        elif s < st.s_rel:
            # (the layers under them: hidden, coarse)
            hmin, hmax, kk = 0.09, 0.16, 0.3
        elif st.layer in ("edge", "scalp"):  # (hidden under the others down the hanging part)
            hmin, hmax, kk = hmin_hang * 1.5, hmax_hang * 1.3, 0.22
        else:
            hmin, hmax, kk = hmin_hang, hmax_hang, 0.22
        h = float(np.clip(kk / max(k, 1e-6), hmin, hmax))
        if st.lock and s > st.s_rel and float(np.interp(s, S, D[:, 1])) < -0.72:
            h = min(h, 0.1)  # over the rounded shoulder: shorter rows (a long chord would cut into it)
        if s < s0 + 0.1:
            h = min(h, 0.05)
        s = min(L, s + h)
        if L - s < 0.02:
            s = L
        rows.append(s)
    for v in splits.values():
        j = int(np.argmin(np.abs(np.array(rows) - v)))
        if 0 < j < len(rows) - 1:
            rows[j] = v
        else:
            rows.append(v)
    rows = np.array(sorted(set(round(x, 7) for x in rows)))
    P = at_s(D, S, rows)
    idx = {nm: int(np.argmin(np.abs(rows - v))) for nm, v in splits.items()}
    return dict(s=rows, P=P, L=L, split=idx, kind=kind, D=D)


def chain_of(st, p_anchor):
    if st.lock:
        return CHAINS[4] if st.side < 0 else CHAINS[5]
    az = math.degrees(math.atan2(p_anchor[0], p_anchor[2] - AXIS_Z))
    if az < -20:
        return CHAINS[0]
    if az < 0:
        return CHAINS[1]
    if az < 20:
        return CHAINS[2]
    return CHAINS[3]


class Card:
    """one card: a frame along its guide rows (phase 1), then (finish, given the widths) rows of (left, right)
    vertices with normals, uvs, hang weights, split into piece segments"""

    def __init__(self, st, rows, rng):
        s, P, L = rows["s"], rows["P"], rows["L"]
        n = len(s)
        T = unit(np.gradient(P, axis=0))
        rad = unit(P - C)
        hor = hang_normals(P) if not st.fly else unit(np.stack([P[:, 0], np.zeros(n), P[:, 2] - AXIS_Z], 1))
        b = smooth(st.s_rel - 0.05, st.s_rel + 0.25, s) if not st.fly else np.zeros(n)
        nout = unit(rad * (1 - b)[:, None] + hor * b[:, None])
        side = unit(np.cross(T, nout))
        face = unit(np.cross(side, T))
        tw = rng.uniform(-0.3, 0.3) * smooth(st.s_rel + 0.1, st.s_rel + 0.6, s) if not st.fly else np.zeros(n)
        if st.lock:
            tw = tw * 0.25  # the side sheets lie flat on the shoulder (no rope twist)
        side = unit(side * np.cos(tw)[:, None] + face * np.sin(tw)[:, None])
        face = unit(np.cross(side, T))
        face = np.where((face * nout).sum(1, keepdims=True) < 0, -face, face)
        self.st, self.rows, self.n, self.s, self.L = st, rows, n, s, L
        self.P, self.T, self.side, self.face, self.nout, self.b = P, T, side, face, nout, b
        self.wscale = rng.uniform(0.94, 1.06)

    def finish(self, w):
        st, rows, n, s, L, P = self.st, self.rows, self.n, self.s, self.L, self.P
        side, face, nout, b = self.side, self.face, self.nout, self.b
        w = np.asarray(w) * (1 - 0.2 * smooth(L * 0.75, L, s)) * self.wscale
        self.w = w
        hw = w * 0.5
        self.left = P - side * hw[:, None]
        self.right = P + side * hw[:, None]
        # over the scalp each vertex keeps its own height: a card edge running near the hairline dips to the
        # scalp there (the hair mass thins into the hairline instead of ending in a lifted card edge)
        sc = s < st.s_rel + 1e-6
        if sc.any() and st.layer != "hairline":
            # card edges stay just inside the natural hairline (the card narrows there): the hairline is the
            # strips' soft side edges and the hairline ring's roots, never a card clipped to the line
            for E in (self.left, self.right):
                ids = np.nonzero(sc)[0]
                bad = ids[style_edge(E[ids]) < EDGE_IN]
                for i in bad:
                    for t in (0.85, 0.7, 0.55, 0.4, 0.25, 0.1):
                        q = P[i] + (E[i] - P[i]) * t
                        if style_edge(q[None])[0] >= EDGE_IN or t == 0.1:
                            E[i] = q
                            break
        if sc.any() and st.off is not None:
            ss = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(st.scalp, axis=0), axis=1))])
            row_off = np.interp(s[sc], ss, st.off)
            for E in (self.left, self.right):
                Pe = E[sc]
                ed = style_edge(Pe)
                oe = np.minimum(row_off, 0.0225 + (row_off - 0.0225) * smooth(0.0, hl_ramp(st.layer, Pe), ed))
                oe = np.maximum(oe, 0.0225)
                _d, _r, th, az = polar(Pe, C)
                E[sc] = C + unit(Pe - C) * (skull_radius_v(SK, th, az) + oe)[:, None]
        # the middle column: on the layer's shell over the scalp (the guide point), else halfway between the edges
        self.mid = (self.left + self.right) / 2
        self.k3 = np.zeros(n, dtype=bool)
        if st.layer in THREE_COL and sc.any():
            self.mid[sc] = P[sc]
            # the middle column wherever the card lies on the head (and one row past it, into the hanging part)
            last = int(np.nonzero(sc)[0].max())
            self.k3[:min(n, last + 2)] = True
        # shading normals: outward from the head (one soft volume over the scalp), a little of the card's own
        # facing down the hanging part (the locks catch the light separately there)
        kf = 0.3 * b
        self.N = unit(face * kf[:, None] + nout * (1 - kf)[:, None])
        u0, u1 = STRIPS[st.strip]
        du = float(np.random.default_rng(st.seed).uniform(-0.004, 0.004))  # per-card strip offset (no repeat)
        u0, u1 = u0 + du + 0.004, u1 + du - 0.004
        if st.mirror:
            u0, u1 = u1, u0
        self.u = (u0, u1)
        self.v = card_v(s, L, st.v0, st.vend, st.layer, st.s0 or 0.0)
        self.hangw = smooth(st.s_rel, st.s_rel + 0.35, s) if not st.fly else np.zeros(n)
        rk = st.rootk if st.rootk is not None else 0.86
        self.rootk = rk + (1 - rk) * smooth(0.0, 0.1, s)
        # piece segments: (piece name, first row, last row)
        sp = rows["split"]
        self.tuck = None
        if "a" in sp and "b" in sp and sp["a"] < sp["b"] < n - 1:
            a, bb = sp["a"], sp["b"]
            b0 = sp.get("b0", bb)
            b0 = bb if not (a < b0 < bb) else b0
            ch = chain_of(st, P[a])
            self.segs = [("HairTop", 0, a), (ch, a, bb), (ch + "b", b0, n - 1)]
            self.tuck = (b0, bb)  # rows of segment 2 above its pivot: tucked under segment 1
        elif "a" in sp and sp["a"] < n - 1:
            a = sp["a"]
            ch = chain_of(st, P[a])
            self.segs = [("HairTop", 0, a), (ch, a, n - 1)]
        else:
            self.segs = [("HairTop", 0, n - 1)]


def assign_widths(cards, log):
    """card widths from the spacing to the nearest card of the same layer on either side (coverage everywhere:
    where the strands fan out from the parting the cards widen, where they gather they narrow), times the layer's
    overlap, smoothed along the card and limited"""
    by = {}
    for cd in cards:
        if cd.st.layer in LAYER:
            by.setdefault(cd.st.layer, []).append(cd)
    for name, cl in by.items():
        L = LAYER[name]
        dens = [cd.rows["D"] for cd in cl]
        allp = np.vstack(dens)
        ids = np.concatenate([np.full(len(d), k) for k, d in enumerate(dens)])
        for k, cd in enumerate(cl):
            W = np.zeros(cd.n)
            other = ids != k
            Q = allp[other]
            for i in range(cd.n):
                dv = Q - cd.P[i]
                lat = dv @ cd.side[i]
                alo = np.abs(dv @ cd.T[i])
                nrm = np.abs(dv @ cd.nout[i])
                ok = (alo < 0.45 * np.abs(lat) + 0.006) & (nrm < 0.5 * np.abs(lat) + 0.02)
                dl = np.abs(lat[ok & (lat < 0)])
                dr = lat[ok & (lat > 0)]
                dl = float(dl.min()) if len(dl) else None
                dr = float(dr.min()) if len(dr) else None
                if dl is None and dr is None:
                    d = 0.12
                elif dl is None or dr is None:
                    d = dl if dr is None else dr
                else:
                    d = max(dl, dr)
                W[i] = d
            W = np.convolve(np.pad(W, 2, mode="edge"), np.ones(5) / 5, mode="valid")
            hang = cd.s > cd.st.s_rel
            wmax = np.where(hang, L["wmax"][1], L["wmax"][0])
            # root: never wider than the root fade allows to look natural
            W = np.clip(W * L["overlap"], 0.035, wmax)
            cd.finish(W)
    for cd in cards:
        if cd.st.layer not in LAYER:
            w0, w1, w2 = cd.st.w
            cd.finish(w0 + (w1 - w0) * smooth(0.0, 0.3, cd.s / max(cd.L, 1e-6)))
    ws = np.concatenate([cd.w for cd in cards])
    log(f"  card widths {ws.min():.3f} .. {ws.max():.3f} (median {np.median(ws):.3f})")


def hairline_strands(cfg, rng, spacing=0.025, length=(0.03, 0.12)):
    """a ring of short sparse wispy cards rooted on the natural hairline (front, temples, down toward the
    sideburns), lying flat in the growth direction (back and away from the parting at the front, back and down
    over the temples), roots jittered across the line: the hairline is fine hair growing out of the scalp at an
    irregular edge, not a card border. Light (no root darkening) and half covering"""
    pts = HL_PTS[np.argsort(np.arctan2(HL_PTS[:, 0], 0.05 - HL_PTS[:, 2]))]
    da = np.arctan2(pts[:, 0], 0.05 - pts[:, 2])
    keep = np.abs(da) < 1.22
    pts, da = pts[keep], da[keep]
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    sl = np.concatenate([[0], np.cumsum(seg)])
    out = []
    n = int(sl[-1] / spacing)
    for k in range(n + 1):
        sk = (k + rng.uniform(-0.4, 0.4)) * sl[-1] / n
        sk = float(np.clip(sk, 0, sl[-1]))
        h = at_s(pts, sl, sk)[0]
        dah = float(np.interp(sk, sl, da))
        sgn = 1.0 if dah > 0 else -1.0
        if abs(dah) < 0.03:
            sgn = 1.0 if k % 2 else -1.0
        a = float(smooth(0.15, 1.0, abs(dah)))
        # growth / comb direction: back and away from the parting at the front, back and down over the temples
        d0 = unit(np.array([sgn * (0.75 - 0.55 * a), -0.05 - 0.45 * a, 0.65 + 0.4 * a]))
        d0 = unit(d0 + rng.normal(0, 0.18, 3))
        h2 = at_s(pts, sl, min(sl[-1], sk + 0.01))[0] - at_s(pts, sl, max(0.0, sk - 0.01))[0]
        nrm0 = unit(h - C)
        inward = unit(np.cross(nrm0, unit(h2)))
        if np.dot(inward, np.array([0.0, 1.0, 0.3])) < 0:
            inward = -inward
        th, az = SK.angles(h - C)
        jit = float(np.clip(rng.normal(0.004, 0.007), -0.004, 0.016)) + float(recess(h[None])[0])
        p = scalp_of((SK.point(th, az) + inward * jit)[None])[0]
        P = [p]
        ln = rng.uniform(*length)
        nst = 3
        for _i in range(nst):
            nrm = unit(p - C)
            kk = smooth(0.0, 2.0, _i)
            dd = unit(inward * (1 - kk) * 0.6 + d0 * (0.4 + 0.6 * kk))
            d = unit(dd - nrm * float(np.dot(dd, nrm)))
            q = scalp_of((p + d * ln / nst)[None])[0]
            P.append(q)
            p = q
        P = np.array(P)
        t = np.linspace(0, 1, len(P))
        P = C + unit(P - C) * (np.linalg.norm(P - C, axis=1) + 0.0228 + 0.005 * t)[:, None]
        wd = rng.uniform(0.026, 0.042)
        st = Strand(side=int(sgn), f=0.0, layer="hairline", li=len(LAYERS) + 1, scalp=P,
                    off=np.full(len(P), 0.0228), hang=None, tip_y=P[-1, 1], lock=False,
                    strip="wispy", mirror=bool(rng.random() < 0.5), v0=0.0,
                    vend=rng.uniform(0.55, 0.85), seed=int(rng.integers(1 << 30)), wave_ph=0.0, body_off=0.05,
                    w=(wd, wd, wd * 0.8), fly=True, shade=1.0, order=-1, rootk=1.0)
        st.G = P
        st.s_rel = float(np.linalg.norm(np.diff(P, axis=0), axis=1).sum())
        out.append(st)
    return out


def part_cover_strands(cfg, rng, n=2):
    """a few short cards crossing the front end of the parting (no bald patch where it meets the hairline)"""
    out = []
    for k in range(n):
        sgn = 1.0  # (all from one side: hair fallen over the parting, not a lacing)
        psi = 1.06 - 0.075 * k + rng.uniform(-0.015, 0.015)
        # a shallow diagonal back over the parting (in the comb direction, not a lacing across it)
        a = unit(np.array([-sgn * 0.02, math.cos(psi), -math.sin(psi)]))
        b = unit(np.array([sgn * 0.05, math.cos(psi - 0.2), -math.sin(psi - 0.2)]))
        om = math.acos(float(np.clip(np.dot(a, b), -1, 1)))
        t = np.linspace(0, 1, 5)
        D = (np.sin((1 - t) * om)[:, None] * a + np.sin(t * om)[:, None] * b) / math.sin(om)
        P = scalp_of(C + D * 0.4)
        off = 0.028 + 0.006 * t
        P = C + unit(P - C) * (np.linalg.norm(P - C, axis=1) + off)[:, None]
        if style_edge(P[:1])[0] < 0.02:
            continue
        wd = rng.uniform(0.035, 0.045)
        st = Strand(side=int(sgn), f=0.0, layer="partx", li=len(LAYERS) + 2, scalp=P, off=off, hang=None,
                    tip_y=P[-1, 1], lock=False, strip="medium", mirror=bool(rng.random() < 0.5), v0=0.0,
                    vend=rng.uniform(0.75, 0.9), seed=int(rng.integers(1 << 30)), wave_ph=0.0, body_off=0.05,
                    w=(wd * 0.8, wd, wd * 0.7), fly=True, shade=1.0, order=1.5, rootk=1.0)
        st.G = P
        st.s_rel = float(np.linalg.norm(np.diff(P, axis=0), axis=1).sum())
        out.append(st)
    return out


def flyaway_strands(strands, cfg, rng):
    """a few short wispy cards lying just over the outer layer behind the crown (never in front of it: wisps over
    the temples catch the light edge-on)"""
    outer = [st for st in strands if st.layer == "outer" and st.f > 0.55]
    out = []
    for i in range(FLYAWAYS["n"] * 2):
        src = outer[int(rng.integers(len(outer)))]
        D, S = densify(src.scalp, 2)
        ln = rng.uniform(*FLYAWAYS["len"])
        s0 = rng.uniform(0.12, max(0.14, src.s_rel - ln - 0.04))
        ss = np.linspace(s0, s0 + ln, 9)
        P = at_s(D, S, ss)
        t = np.linspace(0, 1, 9)
        lift = 0.003 + 0.004 * t
        P = P + unit(P - C) * lift[:, None]
        P = P + np.cross(unit(P - C), unit(np.gradient(P, axis=0))) * (rng.normal(0, 0.012) * t ** 2)[:, None]
        st = Strand(side=src.side, f=src.f, layer="fly", li=len(LAYERS), scalp=P, off=None, hang=None,
                    tip_y=P[-1, 1], lock=False, strip=FLYAWAYS["strip"], mirror=bool(rng.random() < 0.5),
                    v0=float(rng.uniform(0.25, 0.5)), seed=int(rng.integers(1 << 30)), wave_ph=0.0,
                    body_off=0.08, w=(FLYAWAYS["w"][0], FLYAWAYS["w"][1], FLYAWAYS["w"][1]), fly=True, rootk=1.0)
        st.G = P
        st.s_rel = float(np.linalg.norm(np.diff(P, axis=0), axis=1).sum())
        out.append(st)
    return out


# =========================================================================================== Blender meshes
def card_mesh(cards, name, coll, displace=0.022, seed=0):
    """all cards of a layer as one Blender mesh (three vertices per row: left, middle, right, per-corner UVs and colours, a "hang"
    vertex group) with a Displace modifier (Clouds) breaking the hanging part into clumps; returns the object
    and per-card vertex index bases"""
    V, F, UV, Wg = [], [], [], []
    bases = []
    for cd in cards:
        base = len(V)
        bases.append(base)
        um = (cd.u[0] + cd.u[1]) / 2
        for i in range(cd.n):
            V += [tuple(cd.left[i]), tuple(cd.mid[i]), tuple(cd.right[i])]
            UV += [(cd.u[0], 1.0 - cd.v[i]), (um, 1.0 - cd.v[i]), (cd.u[1], 1.0 - cd.v[i])]
            Wg += [cd.hangw[i]] * 3
        for i in range(cd.n - 1):
            r0, r1 = base + 3 * i, base + 3 * i + 3
            F.append((r0, r0 + 1, r1 + 1, r1))
            F.append((r0 + 1, r0 + 2, r1 + 2, r1 + 1))
    me = bpy.data.meshes.new(name)
    me.from_pydata(V, [], F)
    me.update()
    uvl = me.uv_layers.new(name="UVMap")
    uv = np.array(UV)
    loops_v = np.zeros(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", loops_v)
    uvl.data.foreach_set("uv", uv[loops_v].ravel())
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    vg = ob.vertex_groups.new(name="hang")
    Wg = np.asarray(Wg)
    for wv in np.unique(np.round(Wg, 2)):
        ids = np.nonzero(np.abs(np.round(Wg, 2) - wv) < 1e-6)[0].tolist()
        if wv > 0:
            vg.add(ids, float(wv), "REPLACE")
    if displace > 0:
        tex = bpy.data.textures.new(f"{name}_clumps", type="CLOUDS")
        tex.noise_scale = 0.22
        tex.noise_depth = 2
        tex.noise_basis = "BLENDER_ORIGINAL"
        md = ob.modifiers.new("clumps", "DISPLACE")
        md.texture = tex
        md.texture_coords = "GLOBAL"
        md.direction = "NORMAL"
        md.strength = displace
        md.mid_level = 0.5
        md.vertex_group = "hang"
        tex2 = bpy.data.textures.new(f"{name}_sway", type="CLOUDS")
        tex2.noise_scale = 0.6
        md2 = ob.modifiers.new("sway", "DISPLACE")
        md2.texture = tex2
        md2.texture_coords = "GLOBAL"
        md2.direction = "X"
        md2.strength = displace * 0.8
        md2.mid_level = 0.5
        md2.vertex_group = "hang"
    return ob, bases


def evaluated_positions(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    P = np.zeros(len(me.vertices) * 3)
    me.vertices.foreach_get("co", P)
    ev.to_mesh_clear()
    return P.reshape(-1, 3)


def guide_curves(strands, name, coll):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    for st in strands:
        sp = cu.splines.new("POLY")
        sp.points.add(len(st.G) - 1)
        for i, p in enumerate(st.G):
            sp.points[i].co = (p[0], p[1], p[2], 1.0)
    cu.bevel_depth = 0.002
    ob = bpy.data.objects.new(name, cu)
    coll.objects.link(ob)
    return ob


# =========================================================================================== clearance, occlusion
def enforce_clearance(P, refs, hang_mask):
    """every vertex over the head CLEAR_MIN above the male head mesh, both skull tables (female through the fit)
    and the female head (through the fit); out of the ear boxes; hanging vertices off both torsos"""
    P = P.copy()
    # nothing on the forehead below the hairline
    # (the forehead: lifted to the hairline; beside the face, lower down: out to the side of the face)
    Po = hl.org(P)
    fr = (Po[:, 2] < -0.2) & (np.abs(Po[:, 0]) < 0.3) & (Po[:, 1] > 0.05)
    if fr.any():
        hy = hairline_y(P[fr]) - 0.003
        Q = P[fr]
        Q[:, 1] = np.maximum(Q[:, 1], hy)
        P[fr] = Q
    fc = (Po[:, 2] < -0.2) & (np.abs(Po[:, 0]) < 0.3) & (Po[:, 1] > -0.45) & (Po[:, 1] <= 0.05)
    if fc.any():
        P[fc, 0] = np.sign(P[fc, 0]) * (0.66 if hl.CLASSIC else 0.3)
    over = P[:, 1] > (-0.62 if hl.CLASSIC else -0.42)
    P[over] = skull_push_v(P[over], CLEAR_MIN + 0.0005)
    ref_m, ref_f = refs
    sc = np.array([FIT_F["ax"], FIT_F["ay"], FIT_F["az"]])
    cm = CLEAR_MIN + 0.0005
    for i in range(len(P)):
        p = P[i]
        if p[1] > -0.95:  # (every piece, the chains too, down the neck to the torso; below it the neck is buried)
            # (the classic head reaches y -0.6: its full mesh checked down to there)
            r = signed(ref_m.head, p, CLEAR_MIN + 0.03)
            if r is not None and r[2] < CLEAR_MIN:
                p = r[0] + r[1] * cm
            # the whole male head with its ears
            r = near_full(ref_m.full, p, CLEAR_MIN + 0.02) if p[1] > HEAD_LOW else None
            if r is not None and r[0] < CLEAR_MIN:
                p = p + r[1] * (cm - r[0])
            # the female head: forward (the hair carried onto it by the runtime fit, measured there) ...
            q = apply_fit(p, FIT_F)
            r = signed(ref_f.head, q, CLEAR_MIN + 0.03)
            if r is not None and r[2] < CLEAR_MIN:
                q2 = r[0] + r[1] * cm
                p = p + (q2 - q) / sc
                q = apply_fit(p, FIT_F)
            r = near_full(ref_f.full, q, CLEAR_MIN + 0.02) if p[1] > HEAD_LOW else None
            if r is not None and r[0] < CLEAR_MIN:
                p = p + r[1] * (cm - r[0]) / sc
            # ... and inverse (the female head carried back into nominal space)
            r = near_full(ref_f.full_inv, p, CLEAR_MIN + 0.02) if p[1] > HEAD_LOW else None
            if r is not None and r[0] < CLEAR_MIN:
                p = p + r[1] * (cm - r[0])
        if CL["ear_band"][0] < p[1] < CL["ear_band"][1] and abs(p[0]) > CL["ear_band"][2]:
            p = ear_push(p, EAR_CLEAR)
        if p[1] < -0.45:
            for _k in range(4):
                for ref in refs:
                    r = signed(ref.torso, p, 0.3)
                    if r is not None and r[2] < 0.012:
                        p = r[0] + r[1] * 0.0135
        P[i] = p
    return P


def smooth_field(P, val, radius):
    """per-vertex values averaged over every vertex within radius (gaussian weights; Blender KD tree)"""
    from mathutils.kdtree import KDTree
    kd = KDTree(len(P))
    for i, p in enumerate(P):
        kd.insert(Vector(p), i)
    kd.balance()
    out = np.empty(len(P))
    for i, p in enumerate(P):
        hits = kd.find_range(Vector(p), radius)
        idx = np.array([h[1] for h in hits])
        d = np.array([h[2] for h in hits])
        w = np.exp(-(d / (radius * 0.5)) ** 2)
        out[i] = float((val[idx] * w).sum() / w.sum())
    return out


def hemi_dirs(n=12, seed=3):
    rng = np.random.default_rng(seed)
    out = []
    for k in range(n):
        u, v = (k + rng.uniform(0, 1)) / n, rng.uniform(0, 1)
        r = math.sqrt(u)
        a = TAU * v
        out.append((r * math.cos(a), r * math.sin(a), math.sqrt(max(0.0, 1 - u))))
    return np.array(out)


def bake_ao(P, Nout, hair_tris, refs, dist=0.08):
    """ambient occlusion per vertex: cosine-distributed rays round the outward normal against the hair cards
    (partial occluders) and the head / torso (full)"""
    hair = BVHTree.FromPolygons([tuple(p) for p in P], hair_tris)
    body = [refs[0].head, refs[0].torso]
    H = hemi_dirs(12)
    ao = np.ones(len(P))
    for i in range(len(P)):
        n = Nout[i]
        t1 = unit(np.cross(n, [0.0, 1.0, 0.0] if abs(n[1]) < 0.9 else [1.0, 0.0, 0.0]))
        t2 = np.cross(n, t1)
        o = P[i] + n * 0.004
        occ = 0.0
        for h in H:
            d = t1 * h[0] + t2 * h[1] + n * h[2]
            hit = 0.0
            loc, _nn, _ix, dd = hair.ray_cast(Vector(o), Vector(d), dist)
            if loc is not None:
                hit = 0.45 * (1 - dd / dist) ** 0.5
            for bv in body:
                loc, _nn, _ix, dd = bv.ray_cast(Vector(o), Vector(d), dist)
                if loc is not None:
                    hit = max(hit, 1.0 * (1 - dd / dist) ** 0.5)
            occ += hit
        ao[i] = 1 - occ / len(H)
    return ao


# =========================================================================================== build
LAYER_DEBUG_COL = [(1, 1, 0), (1, 0.2, 0.2), (0.2, 1, 0.2), (0.2, 0.4, 1), (1, 0.3, 1), (0, 1, 1), (1, 1, 1)]


def build_style(key, cfg, refs, coll, log):
    rng = np.random.default_rng(cfg["seed"] * 101 + 5)
    BODY_TREES[:] = [ref.torso for ref in refs]
    strands = make_strands(cfg, log)
    hang_strands(strands, refs, cfg, log)
    finish_guides(strands, refs, cfg, log)
    fly = flyaway_strands(strands, cfg, rng) + (hairline_strands(cfg, rng) if HAIRLINE_CARDS else [])
    fly += part_cover_strands(cfg, rng)
    allst = strands + fly
    guide_curves(strands, f"{key} guides", coll)
    guide_curves(fly, f"{key} flyaway guides", coll)
    cards = []
    only = [x for x in os.environ.get("LONG_LAYERS", "").split(",") if x]  # debug: build only these layers
    for st in allst:
        cd = Card(st, card_rows(st, cfg, rng), rng)
        if not only or st.layer in only:
            cards.append(cd)
    assign_widths(cards, log)
    # Blender: one mesh per layer, Displace modifiers on the hanging part; read back the evaluated positions
    by_layer = {}
    for cd in cards:
        by_layer.setdefault(cd.st.li, []).append(cd)
    mat = hair_material()
    layer_names = [L["name"] for L in LAYERS] + ["flyaways", "hairline", "part cover"]
    allP, allN, metas = [], [], []
    for li in sorted(by_layer):
        cl = sorted(by_layer[li], key=lambda c: (c.st.f, c.st.side))
        ob, bases = card_mesh(cl, f"{key} cards {layer_names[li]}", coll,
                              displace=0.0 if li >= len(LAYERS) else 0.016 + 0.004 * li, seed=li)
        ob.data.materials.append(mat)
        P = evaluated_positions(ob)
        for cd, base in zip(cl, bases):
            Pc = P[base:base + 3 * cd.n]
            cd.left, cd.mid, cd.right = Pc[0::3].copy(), Pc[1::3].copy(), Pc[2::3].copy()
            metas.append(cd)
    # clearance (one pass over every vertex)
    V = np.vstack([np.stack([cd.left, cd.mid, cd.right], 1).reshape(-1, 3) for cd in metas])
    for _ in range(3):
        V = enforce_clearance(V, refs, None)
    k = 0
    for cd in metas:
        Pc = V[k:k + 3 * cd.n]
        cd.left, cd.mid, cd.right = Pc[0::3].copy(), Pc[1::3].copy(), Pc[2::3].copy()
        k += 3 * cd.n
    # occlusion
    tris = []
    k = 0
    NO = []
    for cd in metas:
        for i in range(cd.n - 1):
            r0, r1 = k + 3 * i, k + 3 * i + 3
            tris += [(r0, r0 + 1, r1 + 1), (r0, r1 + 1, r1), (r0 + 1, r0 + 2, r1 + 2), (r0 + 1, r1 + 2, r1 + 1)]
        NO.append(np.repeat(cd.nout, 3, axis=0))
        k += 3 * cd.n
    NO = np.vstack(NO)
    t0 = time.time()
    ao = bake_ao(V, NO, tris, refs)
    ao = smooth_field(V, ao, 0.075)  # spatially smooth: no card reads as its own lighter / darker rectangle
    log(f"  occlusion {len(V)} verts: {time.time() - t0:.1f}s")
    k = 0
    for cd in metas:
        a = ao[k:k + 3 * cd.n].reshape(-1, 3).mean(1)
        shade = cd.st.shade or (LAYERS[cd.st.li]["shade"] if cd.st.li < len(LAYERS) else FLYAWAYS["shade"])
        cd.col = np.clip((0.68 + 0.32 * a) * shade * cd.rootk, 0.5, 1.0)
        # near the hairline every layer is light (no dark under-band beneath the front hair)
        ed = style_edge(cd.P)
        over = cd.s < cd.st.s_rel + 1e-6
        # toward the painted cap's tone at the hairline: a gradient from the cap (its short tile at vertex colour
        # 0.86) into the hair over ~0.15 studs, no lighter rim standing on a darker band
        wn = smooth(0.18, 0.02, ed) * over
        cd.col = cd.col * (1 - wn) + 0.66 * wn
        # the tips as light as the mid-length (stacked low-alpha tips must not read as a dark brush)
        cd.col = np.clip(cd.col * (1 + 0.12 * smooth(0.8, 1.0, cd.s / max(cd.L, 1e-6)) * (~over)), 0.5, 1.0)
        if cd.st.layer == "hairline":
            cd.col = np.full_like(cd.col, 0.68)  # the hairline ring lies on the cap: the cap's tone (no rim)
        elif cd.st.layer == "edge":
            cd.col = np.maximum(cd.col, 0.62)
        k += 3 * cd.n
    # pieces: innermost layer first, front to back within a layer
    pieces = {}
    seg_rows = {}
    for cd in metas:
        for (nm, r0, r1) in cd.segs:
            seg_rows.setdefault(nm, []).append((cd, r0, r1))
    order = ["HairTop"] + [c for ch in CHAINS for c in (ch, ch + "b")]
    tri_stats = {}
    for nm in order:
        if nm not in seg_rows:
            continue
        p = hl.Piece(nm, TEX_KEY)
        for cd, r0, r1 in sorted(seg_rows[nm], key=lambda x: (x[0].st.order, x[0].st.f)):
            _nt0 = len(p.T)
            ids = []
            for i in range(r0, r1 + 1):
                c = float(cd.col[i])
                dl = np.zeros(3)
                wk = 1.0
                if nm.endswith("b") and cd.tuck and cd.tuck[0] <= i < cd.tuck[1]:
                    # the overlap above the joint lies just under segment 1 and narrows to a point toward its top
                    # (no doubled, darker band across the card at the joint; no seam when the chain swings)
                    dl = -cd.face[i] * 0.005
                    t = (cd.s[i] - cd.s[cd.tuck[0]]) / max(1e-6, cd.s[cd.tuck[1]] - cd.s[cd.tuck[0]])
                    wk = 0.25 + 0.75 * float(smooth(0.0, 1.0, t))
                rgb = (c, c, c)
                if "layercol" in os.environ.get("LONG_DEBUG", ""):  # debug: every layer its own colour
                    rgb = LAYER_DEBUG_COL[min(cd.st.li, len(LAYER_DEBUG_COL) - 1)]
                mc = (cd.left[i] + cd.right[i]) / 2
                L_ = mc + (cd.left[i] - mc) * wk
                R_ = mc + (cd.right[i] - mc) * wk
                a = p.vert(L_ + dl, cd.N[i], (cd.u[0], cd.v[i]), (*rgb, 1.0))
                b = p.vert(R_ + dl, cd.N[i], (cd.u[1], cd.v[i]), (*rgb, 1.0))
                m = None
                if cd.k3[i]:  # a middle column: the card follows the curve of the head across its width
                    m = p.vert(cd.mid[i] + dl, cd.N[i], ((cd.u[0] + cd.u[1]) / 2, cd.v[i]), (*rgb, 1.0))
                ids.append((a, m, b))
            for i in range(len(ids) - 1):
                a, m0, b = ids[i]
                d, m1, c = ids[i + 1]
                # every face and its reversed twin (two-sided); the writer orients them by the shading normals
                if m0 is not None and m1 is not None:
                    fs = [(a, m0, m1), (a, m1, d), (m0, b, c), (m0, c, m1)]
                elif m0 is not None:
                    fs = [(a, m0, d), (m0, c, d), (m0, b, c)]
                elif m1 is not None:
                    fs = [(a, b, m1), (a, m1, d), (b, c, m1)]
                else:
                    fs = [(a, b, c), (a, c, d)]
                # hidden layers lying on the head (under the main / outer layers, the scalp under them) are seen
                # from outside only: one side (the writer winds it outward by the shading normals)
                one = (nm == "HairTop" and cd.st.layer in SINGLE_SIDED
                       and cd.s[min(i + 1 + r0, len(cd.s) - 1)] < cd.st.s_rel - 0.02)
                for t in fs:
                    p.T += [t] if one else [t, (t[0], t[2], t[1])]
            tri_stats[(nm if nm == "HairTop" else "chains", cd.st.layer)] = (
                tri_stats.get((nm if nm == "HairTop" else "chains", cd.st.layer), 0) + len(p.T) - _nt0)
        pieces[nm] = (p, seg_rows[nm])
    log("  triangles by piece / layer: " + ", ".join(f"{a}/{b} {n}" for (a, b), n in sorted(tri_stats.items())))
    out = []
    for nm, (p, segs) in pieces.items():
        # castShadow off: a card's shadow in the game's shadow map is its whole quad (texture alpha is not used),
        # which would print hard rectangles on the face, the neck and the inner layers; the baked vertex
        # occlusion stands in for the hair's self-shadowing
        if nm == "HairTop":
            p.meta = dict(material="SmoothPlastic", castShadow=False, hideUnder={"headgear": False, "hood": True})
        else:
            chain = nm.rstrip("b")
            seg = 2 if nm.endswith("b") else 1
            top = np.array([(cd.left[r0] + cd.right[r0]) / 2 for cd, r0, r1 in segs]).mean(0)
            if seg == 1:
                # the pivot at the piece's top: a 'hang' stretch about it never pushes geometry up into HairTop
                top[1] = float(np.asarray(p.P)[:, 1].max())
            bot = np.array([(cd.left[r1] + cd.right[r1]) / 2 for cd, r0, r1 in segs]).mean(0)
            fx = dict(kind="swing", chain=chain.replace("Hair", ""), seg=seg, stiff=HAIRFX["stiff"],
                      mass=HAIRFX["mass"] if seg == 1 else HAIRFX["mass2"],
                      pivot=[round(float(x), 4) for x in top], tip=[round(float(x), 4) for x in bot])
            if seg == 2:
                fx["parent"] = chain
            p.meta = dict(hairfx=fx, length="hang", material="SmoothPlastic", castShadow=False,
                          hideUnder={"headgear": False, "hood": True})
        out.append(p)
    # seg 2 pivots are their seg 1 tips (the same rows): make them identical
    byname = {p.name: p for p in out}
    for p in out:
        fx = p.meta.get("hairfx")
        if fx and fx["seg"] == 2 and fx["parent"] in byname:
            fx["pivot"] = list(byname[fx["parent"]].meta["hairfx"]["tip"])
    return out, metas


def hair_material(name="hair_straight"):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bs = nt.nodes["Principled BSDF"]
    tx = nt.nodes.new("ShaderNodeTexImage")
    tx.image = bpy.data.images.load(TEX_PATH, check_existing=True)
    tx.image.alpha_mode = "STRAIGHT"
    tint = nt.nodes.new("ShaderNodeRGB")
    tint.outputs[0].default_value = (0.19, 0.13, 0.09, 1)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1
    nt.links.new(tx.outputs[0], mix.inputs[6])
    nt.links.new(tint.outputs[0], mix.inputs[7])
    nt.links.new(mix.outputs[2], bs.inputs["Base Color"])
    nt.links.new(tx.outputs[1], bs.inputs["Alpha"])
    m.blend_method = "HASHED"
    return m


def clearance_report(pieces, refs):
    ref_m, ref_f = refs
    out = dict(head_m=9.0, head_m_ears=9.0, skull_m=9.0, head_f_fit=9.0, head_f_inv=9.0, skull_f_fit=9.0,
               skull_m_narrow=9.0, inside_m=0, ear_box=9.0, face_below_hairline=0, torso_m=9.0, torso_f=9.0)
    for p in pieces:
        P = np.asarray(p.P)
        for lo, hi in EARS:
            dd = np.maximum(lo - P, P - hi)
            out["ear_box"] = min(out["ear_box"], float(np.max(dd, axis=1).min()))
        Po = hl.org(P)
        fr = (Po[:, 2] < -0.2) & (np.abs(Po[:, 0]) < 0.3) & (Po[:, 1] > -0.4)
        if fr.any():
            out["face_below_hairline"] += int((P[fr, 1] < hairline_y(P[fr]) - 0.005).sum())
        out["face_below_hairline"] += int(((Po[:, 2] < -0.2) & (np.abs(Po[:, 0]) < 0.299) & (Po[:, 1] > -0.45)
                                           & (Po[:, 1] <= 0.05)).sum())
        Pf = apply_fit(P, FIT_F)
        hm, thm = skull_height_v(SK, P)
        hn, thn = skull_height_v(SK, P / np.array([0.965, 1, 1]))
        near = (hm < 0.12) & (Po[:, 1] > -0.3) & (thm < 2.55)
        if near.any():
            out["skull_m"] = min(out["skull_m"], float(hm[near].min()))
            out["skull_m_narrow"] = min(out["skull_m_narrow"], float(hn[near].min()))
            if SKF is not None:
                hf, thf = skull_height_v(SKF, Pf)
                out["skull_f_fit"] = min(out["skull_f_fit"], float(hf[near].min()))
        for q, qf in zip(P, Pf):
            if q[1] > -0.95:  # (every piece, down the neck to the torso; below it the neck is buried in it)
                h = ref_m.height(q)
                out["head_m"] = min(out["head_m"], h)
                if h < 0:
                    out["inside_m"] += 1
                rr = near_full(ref_m.full, q, 0.3) if q[1] > HEAD_LOW else None
                if rr is not None:
                    out["head_m_ears"] = min(out["head_m_ears"], rr[0])
                # the female head both ways: forward (hair through the fit, the whole head with ears) and inverse
                # (the female head carried back into nominal space through the inverse fit)
                hf = ref_f.height(qf)
                rr = near_full(ref_f.full, qf, 0.3) if q[1] > HEAD_LOW else None
                if rr is not None:
                    hf = min(hf, rr[0])
                out["head_f_fit"] = min(out["head_f_fit"], hf)
                rr = near_full(ref_f.full_inv, q, 0.3) if q[1] > HEAD_LOW else signed(ref_f.full_inv, q, 0.3)
                if rr is not None and q[1] <= HEAD_LOW:
                    rr = (rr[2],)
                if rr is not None:
                    out["head_f_inv"] = min(out["head_f_inv"], rr[0])
            if q[1] < -0.45:
                for nm, ref in (("torso_m", ref_m), ("torso_f", ref_f)):
                    r = signed(ref.torso, q, 0.3)
                    if r is not None:
                        out[nm] = min(out[nm], r[2])
    # how the hanging hair rests on the body: per 'b' segment, the median gap from its lower 30% to each torso
    gaps = {}
    for p in pieces:
        if not p.name.endswith("b"):
            continue
        P = np.asarray(p.P)
        lo = P[P[:, 1] <= np.quantile(P[:, 1], 0.3)]
        g = []
        for ref in (ref_m, ref_f):
            d = [signed(ref.torso, q, 1.0) for q in lo]
            g.append(round(float(np.median([r[2] for r in d if r is not None])), 3))
        gaps[p.name] = g
    res = {k: (round(v, 4) if isinstance(v, float) else v) for k, v in out.items()}
    res["rest_gap_m_f"] = gaps
    bad = [k for k in ("head_m", "head_m_ears", "head_f_fit", "head_f_inv", "skull_m", "skull_f_fit",
                       "skull_m_narrow", "ear_box") if out[k] < 0.022]
    bad += [k for k in ("inside_m", "face_below_hairline") if out[k]]
    bad += [k for k in ("torso_m", "torso_f") if out[k] < 0.01]
    assert not bad or os.environ.get("LONG_NOASSERT"), ("clearance below threshold", bad, res)
    return res


# =========================================================================================== blend file
def save_blend(key, coll, refs, path):
    """the style's Blender scene: guide curves, card meshes (with their Displace modifiers), the exported pieces
    and the reference head / torso, under a root rotated from game space (+Y up) to Blender's +Z up"""
    root = bpy.data.objects.new(f"{key} (game head space)", None)
    bpy.context.scene.collection.objects.link(root)
    root.rotation_euler = (math.pi / 2, 0, math.pi)
    for ob in list(coll.objects):
        if ob.parent is None:
            ob.parent = root
    ref = refs[0]
    for nm, P, F in (("head_m (reference)", ref.headP, ref.headF), ("torso_m (reference)", ref.torsoP, ref.torsoF)):
        me = bpy.data.meshes.new(nm)
        me.from_pydata([tuple(p) for p in P], [], F)
        ob = bpy.data.objects.new(nm, me)
        bpy.context.scene.collection.objects.link(ob)
        ob.parent = root
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)


def pieces_to_blender(pieces, coll):
    sub = bpy.data.collections.new("exported pieces")
    coll.children.link(sub)
    mat = hair_material()
    for p in pieces:
        hl.to_blender(single_sided(p), bpy, material=mat, collection=sub)


def single_sided(piece):
    """a copy without the reversed twins of the two-sided card triangles (Cycles / Blender shade both sides)"""
    q = hl.Piece(piece.name, piece.tex)
    q.P, q.N, q.U, q.C = piece.P, piece.N, piece.U, piece.C
    seen = set()
    for t in piece.T:
        k = tuple(sorted(t))
        if k in seen:
            continue
        seen.add(k)
        q.T.append(t)
    return q


# =========================================================================================== renders
TINTS = {"black": (0.09, 0.078, 0.07), "brown": (0.188, 0.129, 0.094), "blonde": (0.77, 0.61, 0.36),
         "darkblonde": (0.30, 0.21, 0.12)}
SKINS = {"mid": None, "light": (0.72, 0.52, 0.4), "tan": (0.56, 0.38, 0.27), "deep": (0.2, 0.12, 0.08)}
LOOKS = {
    "f_brown": ("f", "brown", "light"),
    "f_blonde": ("f", "blonde", "tan"),
    "m_darkblonde": ("m", "darkblonde", "mid"),
    "m_black": ("m", "black", "deep"),
}
VIEWS = ["front", "34", "side", "back", "close", "top34", "top34L"]


def cap_standin(density, outdir):
    """the shared scalp cap as the game paints it for cut "full": the short tile (8 x 4), alpha = tile alpha x
    natural-hairline coverage x density"""
    gw, gh = 256, 128
    capj = json.load(open(os.path.join(hl.OUT, "cap", "style.json")))
    theta_max = float(capj.get("thetaMax", 2.2))
    th = (np.arange(gh) + 0.5) / gh * theta_max
    az = (np.arange(gw) + 0.5) / gw * TAU
    TH, AZ = np.meshgrid(th, az, indexing="ij")
    s_ = np.sin(TH.ravel())
    D = np.stack([s_ * np.sin(AZ.ravel()), np.cos(TH.ravel()), s_ * np.cos(AZ.ravel())], -1)
    S = scalp_of(C + D * 0.4)
    cov = (smooth(-0.012, 0.01, edge_dist(S)) * density).reshape(gh, gw)
    W, H = 1024, 512
    cov = np.asarray(Image.fromarray((cov * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float32) / 255
    tile = Image.open(os.path.join(TEX_DIR, "hair_short.png")).convert("RGBA").resize((W // 8, H // 4), Image.LANCZOS)
    t = np.tile(np.asarray(tile, np.float32) / 255, (4, 8, 1))
    t[..., 3] *= cov
    path = os.path.join(outdir, "capstandin_long.png")
    Image.fromarray((np.clip(t, 0, 1) * 255).astype(np.uint8), "RGBA").save(path)
    # the game's shared cap mesh (out/cap) when it exists: its polar UV (v = theta / thetaMax), vertex colour 0.86
    if os.path.exists(os.path.join(hl.OUT, "cap", "HairCap.mesh")):
        return load_pieces("cap")[0], path
    p = hl.Piece("HairCap", "short")
    n_th, n_az = 60, 96
    ids = {}
    for i in range(n_th + 1):
        for j in range(n_az + 1):
            t_ = i / n_th * 2.2
            a_ = j / n_az * TAU
            d = hl.Skull.direction(t_, a_)
            ids[(i, j)] = p.vert(SK.point(t_, a_, 0.016), d, (j / n_az, i / n_th), (0.55, 0.55, 0.55))
    for i in range(n_th):
        for j in range(n_az):
            p.tri(ids[(i, j)], ids[(i + 1, j + 1)], ids[(i, j + 1)])
            p.tri(ids[(i, j)], ids[(i + 1, j)], ids[(i + 1, j + 1)])
    return p, path




def render_style(key, pieces, outdir, samples, looks, views, res=(520, 620), tex=TEX_PATH):
    import render
    os.makedirs(outdir, exist_ok=True)
    cap, cap_tex = cap_standin(1.0, outdir)
    paths, labels = [], []
    for look in looks:
        head_name, tint_name, skin_name = LOOKS[look]
        tint = TINTS[tint_name]
        sc = render.Scene(res=res, samples=samples, focus=(0.0, -0.32, 0.04), dist=6.6)
        skin = SKINS[skin_name] or render.SKIN
        render.add_obj(sc, os.path.join(REF, f"head_{head_name}.obj"), tint=skin)
        for _nm, md in render.load_obj(os.path.join(REF, f"torso_{head_name}.obj")).items():
            sc.add_mesh(dict(md, c=None), material="skin", tint=skin, name="torso")
        scl, off = (1, 1, 1), (0, 0, 0)
        if head_name == "f":
            scl, off = (FIT_F["ax"], FIT_F["ay"], FIT_F["az"]), (0, 0, FIT_F["dz"])
        dbg = os.environ.get("LONG_DEBUG", "")
        if "nocap" not in dbg:
            sc.add_piece(cap, texture=cap_tex, tint=tint, offset=off, scale=scl)
        # no denoiser by default: it smears the strand texture into plastic (the game shows the texels as they are);
        # LONG_DEBUG=denoise turns it back on
        sc.sc.cycles.use_denoising = "denoise" in dbg.replace("nodenoise", "")
        for p in pieces:
            q = single_sided(p)
            if "nocol" in dbg:
                q.C = [(1.0, 1.0, 1.0, 1.0)] * len(q.C)
            ob = sc.add_piece(q, texture=None if "notex" in dbg else tex, tint=tint, offset=off, scale=scl)
            # the pieces ship with castShadow = false (in the game's shadow map a card is its whole opaque quad), so
            # the game-faithful preview has no hair-on-hair ray-traced shadows: the baked vertex occlusion is all
            # the self-shadowing, as in game. LONG_DEBUG=shadow turns them on (the stress test: what castShadow =
            # true would do)
            if "shadow" not in dbg:
                ob.visible_shadow = False
        for v in views:
            path = os.path.join(outdir, f"{key}_{look}_{v}.png")
            if v == "close":
                sc.render(path, view=(16, 6, 1.0), dist=2.5, focus=(0, 0.22, -0.12))
            elif v == "top34":
                sc.render(path, view="top34", dist=4.9, focus=(0, 0.1, 0.0))
            elif v == "top34L":
                sc.render(path, view=(-35, 38, 1.05), dist=4.9, focus=(0, 0.1, 0.0))
            elif v == "top":
                sc.render(path, view=(0, 82, 1.0), dist=4.6, focus=(0, 0.2, 0.0))
            elif v == "closeL":
                sc.render(path, view=(-40, 10, 1.0), dist=2.7, focus=(0, 0.15, -0.05))
            elif v == "side":
                sc.render(path, view="side")
            else:
                sc.render(path, view=v)
            paths.append(path)
            labels.append(f"{look} {v}")
    out = os.path.join(outdir, f"sheet_{key}.jpg")
    render.sheet(paths, out, cols=len(views), labels=labels,
                 title=f"{key} ({sum(p.nt for p in pieces)} tris, {len(pieces)} pieces)", cell=(312, 372))
    return out


def load_pieces(key):
    """the exported pieces back from out/<key> (for renders without a rebuild)"""
    import struct
    d = json.load(open(os.path.join(hl.OUT, key, "style.json")))
    out = []
    for nm, rec in d["pieces"].items():
        b = open(os.path.join(hl.OUT, key, rec["mesh_file"]), "rb").read()
        i = b.index(b"\n") + 1
        _hs, _vs, _fs, nv, nt = struct.unpack("<HBBII", b[i:i + 12])
        i += 12
        p = hl.Piece(nm, rec["tex"])
        for _k in range(nv):
            x = struct.unpack("<3f3f2f", b[i:i + 32])
            i += 36
            c = struct.unpack("<4B", b[i:i + 4])
            i += 4
            p.P.append(x[0:3])
            p.N.append(x[3:6])
            p.U.append(x[6:8])
            p.C.append(tuple(v / 255 for v in c))
        for _k in range(nt):
            p.T.append(struct.unpack("<3I", b[i:i + 12]))
            i += 12
        out.append(p)
    return out


# =========================================================================================== main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--render", default="")
    ap.add_argument("--only", default="")
    ap.add_argument("--no-tex", action="store_true")
    ap.add_argument("--no-build", action="store_true", help="render the exported pieces without rebuilding")
    ap.add_argument("--samples", type=int, default=48)
    ap.add_argument("--views", default="")
    ap.add_argument("--looks", default="")
    ap.add_argument("--res", default="520x620")
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    t0 = time.time()

    def log(*a):
        print(f"[{time.time() - t0:6.1f}s]", *a, flush=True)
    if not args.no_build and (not args.no_tex or not os.path.exists(TEX_PATH)):
        make_texture(TEX_PATH)
        log("texture", TEX_PATH)
    log("female fit", {k: round(float(v), 4) for k, v in FIT_F.items()})
    keys = [k for k in STYLES if not args.only or k in args.only.split(",")]
    report = {}
    for key in keys:
        cfg = STYLES[key]
        if not args.no_build:
            bpy.ops.wm.read_factory_settings(use_empty=True)
            refs = make_refs()
            coll = bpy.data.collections.new(f"{key} (long family)")
            bpy.context.scene.collection.children.link(coll)
            log(f"style {key}")
            pieces, _metas = build_style(key, cfg, refs, coll, log)
            clr = clearance_report(pieces, refs)
            log("  clearance", clr)
            entry = dict(cfg["entry"])
            entry.update(family="long", clearance=clr, texture_strips={k: list(v) for k, v in STRIPS.items()})
            data = hl.export_style(key, entry, pieces)
            log(f"  exported {key}: {data['tris']} tris, {len(pieces)} pieces")
            pieces_to_blender(pieces, coll)
            save_blend(key, coll, refs, os.path.join(BLEND_DIR, f"{key}.blend"))
            log("  saved", os.path.join(BLEND_DIR, f"{key}.blend"))
            report[key] = dict(tris=data["tris"], pieces={p.name: p.nt for p in pieces}, clearance=clr)
        if args.render:
            pieces = load_pieces(key)
            looks = args.looks.split(",") if args.looks else (
                ["f_brown", "f_blonde", "m_darkblonde"] if key == "long" else ["m_darkblonde", "f_brown", "f_blonde"])
            views = args.views.split(",") if args.views else VIEWS
            w, h = (int(x) for x in args.res.split("x"))
            sheet = render_style(key, pieces, args.render, args.samples, looks, views, res=(w, h))
            log("  sheet", sheet)
    if report:
        print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
