"""Strand textures of the braids family (numpy + PIL; no Blender needed), used by build_braids.py.

    python3 tools/hair/braids_tex.py OUTDIR      # writes hair_braid.png and hair_cornrow.png

Both are 1024 x 1024 greyscale albedo (0.25..1) with straight alpha, laid out as hairlib.ATLAS says:

* braid   u 0.00-0.50  "plait": a three-strand plait wrapping round a tube. The strip covers HALF the tube's
                       circumference (the builders map it twice round: a plait shows the same chevrons from the
                       front and from the back); its u edges are the tube's sides, where the lobes come round
                       from behind (darker: the gap between the stacked side lobes). Lobes alternate from the
                       right and the left edge, run in and down over the centre and tuck under the next lobe
                       from the other side; every lobe is a bundle of fine strands running along it, rounded
                       (bright crown, dark creases where it meets its neighbours). 4 lobes (2 plait periods)
                       per v repeat, tileable in v and wrapping in u. Opaque (alpha 1).
          u 0.50-1.00  "loc": strands.py's matted rope, unchanged (kept for compatibility; the locs family
                       has its own atlas).
* cornrow u 0.00-0.75  "row": a flat underhand plait lying on the scalp seen from above (v runs along the row),
                       4 lobes per v repeat, tileable in v. The lobes reach the row's sides as the hair fed in
                       from the partings: their outer ends fray into single strands and the alpha falls to 0 at
                       both u edges, so the scalp shows along the partings.
          u 0.75-0.875 "baby": sparse crisp edge hairs (roots at v = 0, tips at v = 1), alpha 0 between them.
          u 0.875-1.0  "pad": 4 soft-edged patches of short combed hair stacked in v (box-braid partings).
Mip friendly: strands are >= 2 px wide, the fine detail is band-limited, and colour bleeds into transparent texels.
"""
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import strands  # noqa: E402  (the shared starting textures: the loc strip and the strand splatter)

SIZE = 1024
PLAIT_HALVES = 4  # lobes per v repeat (braid and cornrow): 2 plait periods
ROW_HALVES = 4


def _pnoise(h, w, sx, sy, seed):
    """periodic band-limited noise (zero mean, unit std), feature size sx px across, sy px down"""
    rng = np.random.default_rng(seed)
    f = np.fft.fft2(rng.normal(0, 1, (h, w)))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-((fx * sx) ** 2 + (fy * sy) ** 2) * (math.pi ** 2) / 2.0)
    n = np.real(np.fft.ifft2(f * g))
    return (n - n.mean()) / (n.std() + 1e-9)


def _pblur(a, sx, sy):
    h, w = a.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2 * (math.pi ** 2) * ((sx * fx) ** 2 + (sy * fy) ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g))


def _smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def _fibres(n, seed, smooth=1.2):
    """a 1-D periodic table of strand tones (one entry per strand-width step): strands of random
    brightness, a few darker gaps, band-limited so a strand is ~2 entries wide"""
    rng = np.random.default_rng(seed)
    t = rng.uniform(0, 1, n) ** 0.7
    t[rng.random(n) < 0.12] *= 0.35  # gaps between strand bundles
    f = np.fft.fft(t)
    fr = np.fft.fftfreq(n)
    t = np.real(np.fft.ifft(f * np.exp(-2 * (math.pi * smooth * fr) ** 2)))
    return (t - t.min()) / (t.max() - t.min() + 1e-9)


def _lookup(table, x):
    n = len(table)
    x = np.mod(x, n)
    i = np.floor(x).astype(np.int64)
    f = x - i
    return table[i % n] * (1 - f) + table[(i + 1) % n] * f


def plait_field(w, h, halves, seed, drop=0.95, over=0.10, wid=0.98, strands_across=70, wobble=0.7):
    """The three-strand plait as a z-buffered set of lobes over a w x h pixel grid (u across, v along;
    `halves` lobes per v repeat, periodic in v and wrapping in u). Lobe k comes in from the right edge
    (k even) or the left (k odd) at v = k / halves, runs in and down past the centre (drop: lobe units down,
    over: fraction of the width past the centre) and tucks under the next lobe; it is an almond-section
    bundle (half-width wid lobe units) measured in isotropic pixels. Returns per pixel of the lobe on top:
    (height 0..1, tone, fibre 0..1, a = along 0..1, d = distance from its own edge 0..1)."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    hp = h / halves
    rng = np.random.default_rng(seed)
    nz = _pnoise(h, w, 40, 40, seed + 1)  # slow wobble of the strands inside a lobe
    best = np.full((h, w), -1.0)
    second = np.full((h, w), -1.0)
    tone = np.zeros((h, w))
    fib = np.zeros((h, w))
    fine = np.zeros((h, w))
    along = np.zeros((h, w))
    edge = np.zeros((h, w))
    table = _fibres(2048, seed + 2, smooth=1.0)
    for k in range(halves):
        s = 1 if k % 2 == 0 else -1
        E = np.array([w if s > 0 else 0.0, k * hp])
        T = np.array([w * 0.5 - s * over * w, k * hp + drop * hp])
        ax = T - E
        L = float(np.linalg.norm(ax))
        ax /= L
        nrm = np.array([-ax[1], ax[0]])
        for wrap in (-h, 0, h):
            px = xx - E[0]
            py = yy + wrap - E[1]
            a = (px * ax[0] + py * ax[1]) / L
            c = px * nrm[0] + py * nrm[1]
            ac = np.clip(a, 0, 1)
            c = c - 0.10 * L * np.sin(ac * math.pi) * s  # a little S-bow
            W = hp * wid * (1 - 0.45 * _smooth(0.6, 1.1, a)) * (0.85 + 0.15 * _smooth(-0.2, 0.25, a))
            b = c / W
            prof = np.sqrt(np.clip(1 - b * b, 0, 1))
            env = (0.62 + 0.38 * _smooth(-0.15, 0.3, a)) * (1 - 0.85 * _smooth(0.7, 1.12, a))
            hgt = prof * env
            ok = (a > -0.35) & (a < 1.12) & (np.abs(b) < 1)
            hgt = np.where(ok, hgt, -1)
            top = hgt > best
            second = np.where(top, best, np.maximum(second, hgt))
            if not top.any():
                continue
            best = np.where(top, hgt, best)
            kk = k % halves
            idx = (b * 0.5 + 0.5) * strands_across + kk * 211.7 + wobble * nz + 0.6 * np.sin(ac * 2.3 + kk)
            f = 0.75 * _lookup(table, idx) + 0.25 * _lookup(table, idx * 2.3 + 977)
            fib = np.where(top, f, fib)
            fine = np.where(top, _lookup(table, idx * 3.7 + 431), fine)
            tone = np.where(top, 0.9 + 0.1 * ((kk * 0.618) % 1.0), tone)
            along = np.where(top, a, along)
            d = (w - xx) / w if s > 0 else xx / w
            edge = np.where(top, d, edge)
    # contact creases: where the lobe on top only just covers the one under it (their heights meet)
    crease = np.where(second > 0, _smooth(0.0, 0.5, best - second) ** 0.7, 1.0)
    best = np.clip(best, 0, 1)
    return best, tone, fib, along, edge, crease, fine


def plait_lobes(w, h, halves, seed, drop=1.65, over=0.16, wid=0.8, bow=0.06, strands_across=110, wobble=0.35):
    """A three-strand plait seen from one side as overlapping lobes painted in ORDER (not by height): lobe k
    enters from the right edge (k even) or the left (k odd) at v = k / halves, sweeps in and down along an
    S-bowed axis past the centre (drop lobe units down, over: fraction of the width past the centre), and the
    next lobe (k + 1, from the other edge) lies on top of its tail, which is where it tucks under. So the only
    boundaries are each lobe's own outline over the one below it (a herringbone of offset almonds), never a
    symmetric crease line running across the whole width. Periodic in v (halves lobes per repeat), wrapping in
    u. Returns per pixel: the top lobe's k, its height 0..1 (rounded section x envelope), along a 0..1,
    across b -1..1, fibre tone, fine fibre tone."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    hp = h / halves
    nz = _pnoise(h, w, 40, 40, seed + 1)
    table = _fibres(2048, seed + 2, smooth=1.0)
    K = np.full((h, w), -1, np.int64)
    H = np.zeros((h, w))
    Aa = np.zeros((h, w))
    Bb = np.zeros((h, w))
    F = np.zeros((h, w))
    G = np.zeros((h, w))
    order = sorted([(k * hp - wrap, k, wrap) for k in range(halves) for wrap in (h, 0, -h)])
    for _vpos, k, wrap in order:
        s = 1 if k % 2 == 0 else -1
        E = np.array([w + 0.06 * w if s > 0 else -0.06 * w, k * hp])
        T = np.array([w * 0.5 - s * over * w, k * hp + drop * hp])
        ax = T - E
        L = float(np.linalg.norm(ax))
        ax /= L
        nrm = np.array([-ax[1], ax[0]])
        px = xx - E[0]
        py = yy + wrap - E[1]
        a = (px * ax[0] + py * ax[1]) / L
        c = px * nrm[0] + py * nrm[1]
        ac = np.clip(a, 0, 1)
        c = c - bow * L * np.sin(ac * math.pi) * s  # S-bow: the lobe bulges downward in its middle
        Wd = hp * wid * (0.8 + 0.2 * np.sin(np.clip(a * 1.1, 0, 1) * math.pi) ** 0.5) * (1 - 0.5 * _smooth(0.72, 1.08, a))
        b = c / Wd
        ok = (a > -0.3) & (a < 1.06) & (np.abs(b) < 1)
        if not ok.any():
            continue
        prof = np.sqrt(np.clip(1 - b * b, 0, 1))
        env = (0.55 + 0.45 * _smooth(-0.1, 0.35, a)) * (1 - 0.8 * _smooth(0.62, 1.06, a))
        idx = (b * 0.5 + 0.5) * strands_across + k * 211.7 + wobble * nz + 0.8 * np.sin(ac * 2.6 + k)
        f = 0.75 * _lookup(table, idx) + 0.25 * _lookup(table, idx * 2.3 + 977)
        g = _lookup(table, idx * 3.7 + 431)
        K = np.where(ok, k, K)
        H = np.where(ok, prof * env, H)
        Aa = np.where(ok, a, Aa)
        Bb = np.where(ok, b, Bb)
        F = np.where(ok, f, F)
        G = np.where(ok, g, G)
    return K, H, Aa, Bb, F, G


def tex_plait(w, h, seed=41):
    """the plait strip: steep S-bowed lobes from alternate edges, each a bundle of fine strands (1-2 px) running
    along it, rounded (bright crown, darker toward its outline), a short soft shadow cast by each lobe onto the
    one beneath (only there), and a dark pocket where a lobe's tail tucks under the next"""
    halves = PLAIT_HALVES
    K, H, A, B, F, G = plait_lobes(w, h, halves, seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    u = (xx + 0.5) / w
    grain = _pnoise(h, w, 1.2, 14, seed + 5)
    crown = np.clip(H, 0, 1) ** 0.6
    lum = (0.30 + 0.70 * crown) * (0.66 + 0.34 * F) * (0.9 + 0.1 * G) * (1 + 0.035 * grain)
    # per lobe a slightly different tone (three strands)
    lum *= np.choose(np.clip(K, 0, halves - 1), [0.97, 1.0, 0.93, 1.03, 0.96, 1.0][:halves])
    # the shadow each lobe casts on the one under it (a soft band just outside its outline, on the lower lobe)
    sh = np.zeros((h, w))
    for k in range(halves):
        nxt = (K == (k + 1) % halves).astype(np.float64)
        bl = np.clip(_pblur(nxt, 5, 7) * 2.0, 0, 1)
        sh = np.where(K == k, bl, sh)
    lum *= 1 - 0.45 * sh
    # the tuck pocket: the tail of a lobe as it dives under (a > 0.8) goes dark
    lum *= 1 - 0.5 * _smooth(0.78, 1.04, A)
    side = np.minimum(u, 1 - u)
    lum *= 0.82 + 0.18 * _smooth(0.0, 0.16, side)
    lum = _pblur(lum, 0.5, 0.7)
    return np.clip(lum, 0.25, 1.0), np.ones_like(lum)


def tex_row(w, h, seed=51):
    """a cornrow seen from above: plait lobes across the row; toward the row's sides every lobe thins into
    separate strands (the hair fed in from the parting) and the alpha reaches 0 BEFORE the lobe's darker
    outline, so no dark rim lands on the parting skin"""
    hgt, tone, fib, along, edge, crease, finef = plait_field(w, h, ROW_HALVES, seed, drop=0.95, over=0.10, wid=0.8,
                                                             strands_across=90, wobble=0.35)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    u = (xx + 0.5) / w
    grain = _pnoise(h, w, 1.2, 12, seed + 5)
    crown = np.clip(hgt, 0, 1) ** 0.7
    side = np.minimum(u, 1 - u) * 2  # 0 at the row's edges, 1 in the middle
    lum = (0.48 + 0.52 * crown) * (0.72 + 0.28 * fib) * (0.9 + 0.1 * finef) * tone * (1 + 0.04 * grain)
    lum *= 0.62 + 0.38 * _pblur(crease, 1.4, 1.4)  # a soft gap between lobes, not a cartoon outline
    occl = _pblur(hgt, 3, 3)
    lum *= 0.86 + 0.14 * np.clip(occl / 0.6, 0, 1)
    # alpha: solid over the braided core, single strands toward the partings, 0 at the edges
    thr = 1.05 - 1.25 * _smooth(0.04, 0.45, side)
    alp = np.clip((0.55 * finef + 0.45 * fib - thr) * 4.0, 0, 1)
    alp *= _smooth(0.02, 0.10, side)
    alp *= _smooth(0.10, 0.26, hgt)  # the lobe outline (low height, dark) is already transparent
    alp = np.clip(_pblur(alp, 0.5, 0.7), 0, 1)
    lum = _pblur(lum, 0.5, 0.8)
    return np.clip(lum, 0.25, 1.0), alp


def tex_baby(w, h, seed=57):
    """sparse, crisp edge hairs: 1-2 px curling strands with clear alpha 0 between them"""
    l, a = strands._strand_field(w, h, seed, count=int(w * 0.3), width_px=1.5, waviness=3.0, curl_amp=1.6,
                                 length=(0.35, 0.8), taper=0.7, dark_root=0.2, x_range=(0.04, 0.96), flyaway=0.15)
    a = np.where(a > 0.12, a, 0.0)
    return np.clip(0.3 + 0.7 * l, 0.25, 1.0), np.clip(a, 0, 1)


def tex_braid(size=SIZE, seed=41):
    w = h = size
    half = w // 2
    lum = np.zeros((h, w), np.float32)
    alp = np.zeros((h, w), np.float32)
    lum[:, :half], alp[:, :half] = tex_plait(half, h, seed)
    # the loc strip exactly as strands.py makes it
    rng = np.random.default_rng(seed)  # noqa: F841 (strands draws its own)
    yy, xx = np.mgrid[0:h, 0:half].astype(np.float32)
    uu = (xx + 0.5) / half
    rim = np.abs(np.sin(uu * math.pi))
    n1 = strands._noise(h, half, seed + 3, 10)
    n2 = strands._noise(h, half, seed + 4, 3)
    fibre = 0.6 + 0.4 * np.sin((xx / half * 31 + n1 * 6 + yy / h * 3) * math.tau)
    lum[:, half:] = np.clip((0.35 + 0.5 * n1 + 0.15 * n2) * fibre * (0.6 + 0.4 * rim), 0, 1)
    alp[:, half:] = 1.0
    l, a = strands._coil_field(half, h, seed + 9, coils=int(size * 0.8), radius_px=size / 260, tight=0.8, fill=0)
    lum[:, half:] = lum[:, half:] * (1 - a * 0.5) + l * a * 0.5
    return lum, alp


def tex_pad(w, h, seed=61, patches=4):
    """box-parting pads (u .875-1 of the cornrow atlas): `patches` rounded squares stacked in v, each a uniform
    fill of short hair combed along v (toward the braid), alpha feathered over the outer ~6 % so neighbouring
    pads leave a thin, even skin line (the parting) between them and the hairline edge is soft, never ragged"""
    ph = h // patches
    lum = np.zeros((h, w))
    alp = np.zeros((h, w))
    for k in range(patches):
        l, a = strands._strand_field(w, ph, seed + k, count=int(w * 2.6), width_px=1.6, waviness=0.5, curl_amp=0.3,
                                     length=(0.6, 1.0), taper=0.5, dark_root=0.2, x_range=(0.0, 1.0), flyaway=0.03)
        yy, xx = np.mgrid[0:ph, 0:w].astype(np.float64)
        u = (xx + 0.5) / w * 2 - 1
        v = (yy + 0.5) / ph * 2 - 1
        q = 8.0  # superellipse: a rounded square
        rr = (np.abs(u) ** q + np.abs(v) ** q) ** (1 / q)
        mask = 1 - _smooth(0.86, 0.98, rr)
        base = 0.6 + 0.12 * _pnoise(ph, w, 3, 24, seed + 40 + k).clip(-1.5, 1.5)
        lum[k * ph:(k + 1) * ph] = np.where(a > 0.05, 0.5 * l + 0.5 * base, base)
        alp[k * ph:(k + 1) * ph] = np.clip((0.8 + 0.2 * a) * mask, 0, 1)
    return np.clip(0.3 + 0.7 * lum, 0.25, 1.0), alp


def tex_cornrow(size=SIZE, seed=51):
    """row u 0-.75, baby hairs u .75-.875, box-parting patches u .875-1 (4 patches stacked in v)"""
    w = h = size
    rw = int(w * 0.75)
    bw = int(w * 0.875)
    lum = np.zeros((h, w), np.float32)
    alp = np.zeros((h, w), np.float32)
    lum[:, :rw], alp[:, :rw] = tex_row(rw, h, seed)
    lum[:, rw:bw], alp[:, rw:bw] = tex_baby(bw - rw, h, seed + 6)
    lum[:, bw:], alp[:, bw:] = tex_pad(w - bw, h, seed + 10)
    return lum, alp


def save(path, lum, alp):
    lum = np.asarray(lum, np.float64)
    alp = np.clip(np.asarray(alp, np.float64), 0, 1)
    # bleed: transparent texels take the local mean colour of the hair around them (no dark mip halos)
    wsum = _pblur(alp, 10, 10)
    csum = _pblur(lum * alp, 10, 10)
    near = np.where(wsum > 1e-4, csum / np.maximum(wsum, 1e-4), float((lum * alp).sum() / max(1e-6, alp.sum())))
    lum = np.where(alp > 0.03, lum, near)
    lum = np.clip(lum, 0.25, 1.0)
    rgb = (lum * 255 + 0.5).astype(np.uint8)
    a = (alp * 255 + 0.5).astype(np.uint8)
    Image.fromarray(np.dstack([rgb, rgb, rgb, a]), "RGBA").save(path, optimize=True)


def build(outdir):
    os.makedirs(outdir, exist_ok=True)
    out = {}
    for name, fn in (("braid", tex_braid), ("cornrow", tex_cornrow)):
        lum, alp = fn()
        p = os.path.join(outdir, f"hair_{name}.png")
        save(p, lum, alp)
        out[name] = p
    return out


if __name__ == "__main__":
    print(build(sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "textures")))
