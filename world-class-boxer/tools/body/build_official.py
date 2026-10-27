"""The ring officials' clothes for the muscle-tier R15 body: the referee's short-sleeve button shirt (collar, placket and
buttons, chest pocket, badge, side and yoke seams, sleeve hems), the black bow tie, dress trousers (waistband, seat,
legs with front / back creases and hems at the shoes, belt and buckle) and black leather dress shoes (sole and heel,
laces); the spar coach (outfit "cornerman") wears the same cut as a team polo (short placket) with a towel over the
shoulder. Every piece is FITTED to the tier body part it is welded to, in build_gear.py's conventions (same helpers,
same rest space, same gear.json record format), in two detail sets:

    full   on the v10 tier bodies (build_body.build_tier)      -> tools/body/out/gear/{tier<N>,shared}/Off*.mesh
    lite   on the v9 lite bodies (tools/body/out/lite/tier<N>)  -> tools/body/out/lite/gear/{tier<N>,shared}/Off*.mesh

and writes tools/body/out/gear/official.json + tools/body/out/lite/gear/official.json (pieces, sets, tiers: the
gear.json format); publish_gear.py merges them into GearAssetData (group "official", styles Referee / Coach).

    /opt/bpyenv/bin/python tools/body/build_official.py            # build + export both sets
    /opt/bpyenv/bin/python tools/body/build_official.py --only full

How the clothes hold through the animations (the referee walks, bends over the count, reaches out to catch / separate
and waves it off overhead; tools/sim/v9_referee.luau renders them):
* the shirt is the convex hull of the UpperTorso (and the LowerTorso's top, turned) plus ease, tucked 0.35 deep into
  the trousers; the trousers' waist hulls the shirt of every tier it can show turned through the waist's twists and
  bends (WAIST_TURNS + the count's forward bend), so the hem never shows through the waistband
* a sleeve's top is a sphere about the shoulder pivot (the arm's own dome, BuilderBody's JOINT_DOME, plus ease): the arm
  turns it in place, raised overhead or not, and the shirt's yoke covers the torso under it
* the trouser leg ends round the knee in a sphere about the knee pivot (one radius for every tier: a thigh of one tier
  and a shin of another meet the same sphere); the shin's top is a smaller sphere inside it and its tube starts just
  outside it, so a bent knee shows a rounded knee, never a gap
* the leg's top is closed inside the seat through the walk's thigh swing (build_gear.HIP_SWING, as the trunks')
* the trouser hem hangs over the shoe's collar, both close to the ankle pivot
"""
import argparse
import json
import math
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "hair"))
sys.path.insert(0, HERE)
import build_body as bb  # noqa: E402
import build_gear as bg  # noqa: E402

OUT_FULL = os.path.join(HERE, "out", "gear")
OUT_LITE = os.path.join(HERE, "out", "lite", "gear")
TIERS = bg.TIER_IDS

# colour slots (BuilderBody paints them: the venue / fight picks the shirt colour)
SLOTS = ["shirt", "shirtTrim", "buttons", "badge", "bowtie", "trousers", "belt", "buckle", "dressShoes", "dressSoles",
         "dressLaces", "towel"]
TIER_OF_WAIST = ["LowerTorso", "UpperTorso", "LeftUpperLeg", "RightUpperLeg"]
# piece -> (body part base, slot, sided, shared over tiers, tierOf)
PIECES = {
    "OffShirt": ("UpperTorso", "shirt", False, False, None),
    "OffCollar": ("UpperTorso", "shirt", False, False, None),
    "OffPlacket": ("UpperTorso", "shirtTrim", False, False, None),
    "OffButtons": ("UpperTorso", "buttons", False, False, None),
    "OffPolo": ("UpperTorso", "shirtTrim", False, False, None),
    "OffPoloButtons": ("UpperTorso", "buttons", False, False, None),
    "OffPocket": ("UpperTorso", "shirtTrim", False, False, None),
    "OffBadge": ("UpperTorso", "badge", False, False, None),
    "OffBowTie": ("UpperTorso", "bowtie", False, False, None),
    "OffTowel": ("UpperTorso", "towel", False, False, None),
    "OffSleeve": ("UpperArm", "shirt", True, False, None),
    "OffSleeveHem": ("UpperArm", "shirtTrim", True, False, None),
    "OffWaist": ("LowerTorso", "trousers", False, False, TIER_OF_WAIST),
    "OffBelt": ("LowerTorso", "belt", False, False, TIER_OF_WAIST),
    "OffBuckle": ("LowerTorso", "buckle", False, False, TIER_OF_WAIST),
    "OffThigh": ("UpperLeg", "trousers", True, False, None),
    "OffShin": ("LowerLeg", "trousers", True, False, None),
    "OffShoe": ("Foot", "dressShoes", True, True, None),
    "OffSole": ("Foot", "dressSoles", True, True, None),
    "OffLaces": ("Foot", "dressLaces", True, True, None),
}
BASE = ["OffShirt", "OffCollar", "OffSleeve", "OffSleeveHem", "OffWaist", "OffThigh", "OffShin", "OffShoe", "OffSole",
        "OffLaces"]
SETS = {"official": {
    "Referee": BASE + ["OffPlacket", "OffButtons", "OffPocket", "OffBadge", "OffBowTie", "OffBelt", "OffBuckle"],
    "Coach": BASE + ["OffPolo", "OffPoloButtons", "OffTowel"],
}}

# heights (game rest space, every tier: the torso / leg pivots are shared)
Y_SHIRT_HEM = 3.10      # tucked: 0.35 under the waistband's top
Y_WAIST_TOP = 3.47      # the trousers' waistband top (just over the navel line)
Y_BELT = (3.26, 3.43)
Y_CROTCH = 2.42
Y_LEG_TOP = 2.86        # the trouser leg's closed top, inside the seat
Y_SLEEVE_HEM = 4.36     # short sleeve: two thirds down to the elbow (4.00)
Y_COLLAR = (5.15, 5.31)
# the waist turns (yaw, side bend, forward bend; deg) the shirt's tuck is cut round: an official never punches (the boxers'
# 22 deg twist), he walks, crouches in his stance (AnimGym: 6 deg), bends over the count (AnimFight: 16 deg) and leans
# into the catch (9 deg); a margin on each
WAIST_TURNS = ((10, 0, 0), (-10, 0, 0), (0, 6, 0), (0, -6, 0), (0, 0, 18), (8, 4, 14), (-8, -4, 14), (0, 0, -6))


# ------------------------------------------------------------------------------------------ the bodies
class LiteBodies:
    """the v9 lite tier bodies (tools/body/out/lite/tier<N>/*.mesh, recentred mesh + its rest centre), the joints of
    the full set (the same rest-space pivots)"""

    def __init__(self, full):
        with open(os.path.join(HERE, "out", "lite", "body_tiers.json")) as f:
            bt = json.load(f)
        self.t = {}
        for n in TIERS:
            parts = {}
            for name, e in bt["tiers"][str(n)]["parts"].items():
                P, N, T = read_mesh(os.path.join(HERE, "out", "lite", "tier%d" % n, e["mesh_file"]))
                parts[name] = {"P": P + np.array(e["rest_center"]), "N": N, "T": T,
                               "U": np.zeros((len(P), 2))}
            parts["_J"] = full.t[n]["_J"]
            self.t[n] = parts

    def part(self, n, name):
        return self.t[n][name]

    def J(self, n, k):
        return np.array(self.t[n]["_J"][k], float)

    def centre(self, n, name):
        P = self.t[n][name]["P"]
        return (P.min(0) + P.max(0)) / 2


def read_mesh(path):
    with open(path, "rb") as f:
        b = f.read()
    i = b.index(b"\n") + 1
    hs, vs, fs_, nv, nf = struct.unpack_from("<HBBII", b, i)
    i += hs
    P, N = np.zeros((nv, 3)), np.zeros((nv, 3))
    for k in range(nv):
        v = struct.unpack_from("<3f3f", b, i + k * vs)
        P[k], N[k] = v[:3], v[3:6]
    i += nv * vs
    T = np.array(struct.unpack_from("<%dI" % (3 * nf), b, i), np.int64).reshape(-1, 3)
    return P, N, T


# ------------------------------------------------------------------------------------------ helpers
def phis_of(n):
    return 2 * math.pi * (np.arange(n) / n - 0.5)


def bump(phis, at_deg, w_deg):
    d = np.abs(((phis - math.radians(at_deg)) + math.pi) % (2 * math.pi) - math.pi)
    return np.exp(-0.5 * (d / math.radians(w_deg)) ** 2)


def smooth01(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def turned(lp, about, turns, **o):
    out = []
    for yw, rl, pt in turns:
        R = bb.roty(yw) @ bb.rotz(rl) @ bb.rotx(pt)
        out.append(({"P": (lp["P"] - about) @ R.T + about, "T": lp["T"]}, dict(o)))
    return out


def grid_normals(G):
    L = bg.sheet(np.asarray(G))
    R, n = len(G), len(G[0])
    return L["N"].reshape(R, n + 1, 3)[:, :n]


def disc(p, nrm, r, h, nside=10):
    """a flat round disc (button, badge, plate): its back h * 0.4 behind p, its face h * 0.6 in front, a rounded rim"""
    nrm = np.asarray(nrm, float) / np.linalg.norm(nrm)
    ref = np.array([0.0, 1.0, 0.0]) if abs(nrm[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    u = np.cross(nrm, ref)
    u /= np.linalg.norm(u)
    v = np.cross(nrm, u)
    a = 2 * math.pi * np.arange(nside) / nside
    D = np.outer(np.cos(a), u) + np.outer(np.sin(a), v)
    p = np.asarray(p, float)
    back, face = p - nrm * h * 0.4, p + nrm * h * 0.6
    G = [back + D * r * 0.9, back + D * r, face - nrm * h * 0.25 + D * r, face + D * r * 0.88]
    return bg.sheet(np.array(G), pole_lo=back, pole_hi=face, nref=[1, 2])


def squash(lp, centre, axis, k):
    """scale lp along a unit axis about centre by k (flattens a tube into a strap / a bow)"""
    a = np.asarray(axis, float) / np.linalg.norm(axis)
    P = lp["P"] - centre
    d = P @ a
    out = dict(lp)
    out["P"] = centre + P + np.outer(d * (k - 1), a)
    N = lp["N"].copy()
    dn = N @ a
    N = N + np.outer(dn * (1 / k - 1), a)
    out["N"] = N / np.linalg.norm(N, axis=1, keepdims=True)
    return out


def fn_at(fn, y, ang, n=96):
    """a radius function evaluated on a full ring of n directions, interpolated at the angles asked (a hull radius
    taken along one direction alone comes out too small: radial() smooths over its samples)"""
    ph = phis_of(n)
    r = fn(y, ph)
    a = (np.atleast_1d(ang) + math.pi) / (2 * math.pi) * n
    j0 = np.floor(a).astype(int) % n
    f = a - np.floor(a)
    return r[j0] * (1 - f) + r[(j0 + 1) % n] * f


def hit(lp, o, d, lift):
    return bg.surf_hit(lp, o, d, lift)


# ------------------------------------------------------------------------------------------ the shirt
def shirt_field(B, n, nseg):
    """(ys, rings, c, fn): the shirt on the UpperTorso of tier n. fn(y, phis) = the cloth's radius"""
    ut = B.part(n, "UpperTorso")
    c = np.array([0.0, float((ut["P"][:, 2].min() + ut["P"][:, 2].max()) / 2)])
    wj = B.J(n, "Waist")
    # the LowerTorso's top under the shirt (every tier: the hips can show another tier), turned the other way about
    # the waist (the shirt turns with the chest)
    lts = []
    for k in TIERS:
        lt = B.part(k, "LowerTorso")
        lts.append((lt, dict(ymin=3.30)))
        inv = tuple((-a, -b, -c_) for a, b, c_ in WAIST_TURNS)
        lts += turned(lt, wj, inv, ymin=3.30)
    srcs = [ut] + lts

    def ease(y):
        blouse = 0.022 * math.exp(-0.5 * ((y - 3.60) / 0.09) ** 2)   # blousing over the belt
        chest = 0.008 * math.exp(-0.5 * ((y - 4.45) / 0.25) ** 2)
        return 0.032 + blouse + chest

    def fn(y, ph):
        yy = max(y, 3.33)
        r = bg.radial(srcs, yy, c, ph, sigma=2.0, nfin=max(16, len(ph)))
        r = bg.smooth_circ(bg.max_circ(r, 2), 1.5)
        if y < 3.33:
            r = r * (1 - 0.03 * (3.33 - y) / 0.23)
        return r + ease(y)
    return fn, c, srcs


def shirt(B, n, nseg, dense=None):
    """the shirt body (OffShirt) + its dense grid (for the patches) -> (lp, (G dense, ys, phis), fn, c)"""
    fn, c, _ = shirt_field(B, n, nseg)
    ys = [Y_SHIRT_HEM, 3.22, 3.36, 3.50, 3.62, 3.76, 3.95, 4.15, 4.35, 4.55, 4.72, 4.84, 4.93, 5.00, 5.06, 5.11,
          5.16, 5.20]
    nd = dense or nseg * 4
    ph = phis_of(nd)
    side = bump(ph, 90, 2.2) + bump(ph, -90, 2.2)
    back = np.clip(-np.cos(ph), 0, 1)
    rows = []
    for y in ys:
        r = fn(y, ph)
        r = r + 0.0045 * side * (y < 4.75)                                  # side seams
        r = r + 0.004 * back ** 0.5 * (abs(y - 4.93) < 0.005)               # the back yoke seam
        rows.append(bg.ring(c, r, ph, y))
    G = np.array(rows)
    top = bg.lip(G[-1], c, (0, 1, 0), 0.02)
    bot, pole = bg.tuck(G[0], c, (0, -1, 0), 0.02)
    k = nd // nseg
    GG = np.array(bot[::-1] + list(G) + top)
    lp = bg.sheet(GG[:, ::k], pole_lo=pole, nref=range(2, 2 + len(ys)))
    return lp, (G, ys, ph), fn, c


def collar(B, n, fn, c, nseg):
    """a stand collar round the torso's top (under the head's rim), its two points folded down onto the chest"""
    ph = phis_of(nseg)
    y0, y1 = Y_COLLAR
    front = np.clip(np.cos(ph), 0, 1)
    # the stand is lower at the front (the head's rounded rim sits over it), a little taller at the back
    hy = y1 - 0.05 * front ** 2
    rows = []
    for i, t in enumerate(np.linspace(0, 1, 5)):
        Y = y0 + (hy - y0) * t
        R = np.array([fn_at(fn, yy, p)[0] for yy, p in zip(Y, ph)])
        R = R + 0.012 + 0.010 * math.sin(math.pi * t)
        Rg = np.stack([c[0] + R * np.sin(ph), Y, c[1] - R * np.cos(ph)], axis=1)
        rows.append(Rg)
    G = np.array(rows)
    bot, pole = bg.tuck(G[0], c, (0, -1, 0), 0.02)
    top = bg.lip(G[-1], c, (0, 1, 0), 0.018)
    stand = bg.sheet(np.array(bot[::-1] + list(G) + top), pole_lo=pole, nref=range(2, 7))
    # the collar points: flat tabs from the stand's front down and out over the chest (either side of the bow tie)
    tabs = []
    for sx in (-1, 1):
        a0 = math.radians(sx * 13)
        pts, rad = [], []
        for t in np.linspace(0, 1, 5):
            a = a0 + math.radians(sx * 16) * t
            y = 5.22 - 0.15 * t
            r = fn_at(fn, y, a)[0] + 0.022 - 0.004 * t
            pts.append(np.array([c[0] + r * math.sin(a), y, c[1] - r * math.cos(a)]))
            rad.append(0.045 - 0.025 * t)
        tab = bb.tube(pts, rad, nside=8, kcap=2)
        nrm = np.array([math.sin(a0), 0.25, -math.cos(a0)])
        tabs.append(squash(tab, pts[2], nrm, 0.28))
    return bg.merge([stand] + tabs)


def placket(Gd, ys, ph, y_from, w_deg=4.6, lift=0.007):
    """the button strip down the front centre, from y_from to the collar (a tape on the shirt)"""
    Nd = grid_normals(Gd)
    cols = np.where(np.abs(ph) <= math.radians(w_deg))[0]
    rows = [i for i, y in enumerate(ys) if y >= y_from - 1e-6]
    S = np.array([Gd[i][cols] + Nd[i][cols] * lift for i in rows])
    Ns = np.array([Nd[i][cols] for i in rows])
    return bg.strip_patch(S, Ns, piping=0.003)


def buttons(shirt_lp, c, yset, lift=0.010, r=0.028):
    out = []
    for y in yset:
        p = hit(shirt_lp, (c[0], y, -2.0), (0, 0, 1), lift)
        if p is None:
            continue
        out.append(disc(p, (0, 0.15, -1), r, 0.013, nside=10))
    return bg.merge(out)


def patch(Gd, ys, ph, y0, y1, a_deg, w_deg, lift):
    """a rectangular patch (rows y0..y1 interpolated on the shirt grid, columns a +- w) lifted off the shirt"""
    Nd = grid_normals(Gd)
    cols = np.where(np.abs(((ph - math.radians(a_deg)) + math.pi) % (2 * math.pi) - math.pi) <= math.radians(w_deg))[0]
    S, Ns = [], []
    for y in np.linspace(y0, y1, 5):
        j = max(i for i, yy in enumerate(ys) if yy <= y)
        j = min(j, len(ys) - 2)
        t = (y - ys[j]) / (ys[j + 1] - ys[j])
        row = Gd[j][cols] * (1 - t) + Gd[j + 1][cols] * t
        nr = Nd[j][cols] * (1 - t) + Nd[j + 1][cols] * t
        S.append(row + nr * lift)
        Ns.append(nr)
    return bg.strip_patch(np.array(S), np.array(Ns), piping=0.003)


def pocket(Gd, ys, ph):
    """the chest pocket on the left chest (-X): the pocket and its flap"""
    body = patch(Gd, ys, ph, 4.30, 4.56, -27, 9.5, 0.008)
    flap = patch(Gd, ys, ph, 4.52, 4.60, -27, 10.2, 0.015)
    return bg.merge([body, flap])


def badge(shirt_lp, c):
    """the referee's badge on the right chest: a round enamel badge with a raised rim"""
    a = math.radians(27)
    d = np.array([math.sin(a), 0.0, -math.cos(a)])
    o = np.array([c[0], 4.47, c[1]])
    p = hit(shirt_lp, o + d * 2.0, -d, 0.018)
    if p is None:
        return None
    face = disc(p, d, 0.075, 0.014, nside=16)
    rim = disc(p + d * 0.004, d, 0.082, 0.008, nside=16)
    return bg.merge([face, rim])


def bow_tie(collar_lp, c):
    """two puffed wings and the knot, at the collar's front under the chin"""
    y = 5.17
    p = hit(collar_lp, (c[0], y, -2.0), (0, 0, 1), 0.0)
    if p is None:
        p = np.array([0.0, y, -0.4])
    zc = p[2] - 0.05
    wings = []
    for sx in (-1, 1):
        pts = [(sx * 0.035, y, zc), (sx * 0.095, y, zc + 0.004), (sx * 0.165, y, zc + 0.012)]
        w = bb.tube(pts, [0.036, 0.062, 0.058], nside=10, kcap=3)
        wings.append(squash(w, np.array([0, y, zc]), (0, 0, 1), 0.5))
    knot = squash(bb.tube([(0, y, zc - 0.004), (0, y, zc + 0.004)], [0.034, 0.034], nside=10, kcap=2),
                  np.array([0, y, zc]), (0, 1, 0), 1.15)
    return bg.merge(wings + [knot])


def towel(body_lp, shirt_lp, c):
    """the coach's towel folded over the right shoulder, hanging down the chest and the back: a thick terry band"""
    path = []
    for t in np.linspace(0, 1, 17):
        a = math.pi * t
        x = 0.46 + 0.05 * math.sin(a)
        o = np.array([x, 4.60, c[1]])
        dv = np.array([0.0, math.sin(a), -math.cos(a)])
        # (cast on the closed UpperTorso: the shirt is open at the neck) + the shirt's ease + a little air
        # (on the shirt, or on the closed UpperTorso + the shirt's ease where the ray passes the shirt's neck opening:
        # whichever is further out)
        hs = [q for q in (hit(body_lp, o, -dv, 0.07), hit(shirt_lp, o, -dv, 0.02)) if q is not None]
        h = max(hs, key=lambda q: float(np.dot(q - o, dv))) if hs else None
        if h is not None:
            path.append(h)
    path = np.array(path)
    # (the ends hang straight down a little further)
    path = np.vstack([path[:1] + np.array([0, -0.22, -0.02]), path, path[-1:] + np.array([0, -0.22, 0.02])])
    n = len(path)
    Tn = np.gradient(path, axis=0)
    Tn /= np.linalg.norm(Tn, axis=1, keepdims=True)
    Nn = path - np.array([0.45, 4.45, c[1]])
    Nn = Nn - Tn * np.einsum("ij,ij->i", Nn, Tn)[:, None]
    Nn /= np.linalg.norm(Nn, axis=1, keepdims=True)
    S = np.cross(Tn, Nn)
    S /= np.linalg.norm(S, axis=1, keepdims=True)
    w, th = 0.30, 0.035
    # a closed band round the towel's section (a rounded rectangle), ends closed on poles
    ang = 2 * math.pi * np.arange(16) / 16
    rows = []
    for i in range(n):
        ca, sa = np.cos(ang), np.sin(ang)
        x = (w / 2) * np.sign(ca) * np.minimum(1.0, np.abs(ca) * 1.8)
        y = (th / 2) * np.sign(sa) * np.minimum(1.0, np.abs(sa) * 1.8)
        rows.append(path[i] + np.outer(x, S[i]) + np.outer(y + th / 2, Nn[i]))
    return bg.sheet(np.array(rows), pole_lo=path[0] + Nn[0] * th / 2 - Tn[0] * 0.01,
                    pole_hi=path[-1] + Nn[-1] * th / 2 + Tn[-1] * 0.01)


# ------------------------------------------------------------------------------------------ sleeves
def sleeve(B, n, nseg):
    """the right short sleeve on the UpperArm of tier n: a sphere about the shoulder pivot over the arm's dome, the
    tube down to the hem, flaring a little; returns (sleeve, hem band)"""
    ua = B.part(n, "RightUpperArm")
    S = B.J(n, "RightShoulder")
    ph = phis_of(nseg)
    P = ua["P"]
    top = P[P[:, 1] > S[1]]
    Rs = float(np.max(np.linalg.norm(top - S, axis=1))) + 0.036
    ys = list(np.linspace(Y_SLEEVE_HEM, S[1] - 0.06, 6))
    rows = []
    cax = np.array([S[0], S[2]])
    for y in ys:
        cc = bg.centroid([ua], y)
        cc = cax if cc is None else cc
        w = smooth01((y - (S[1] - 0.40)) / 0.34)
        cc = cc * (1 - w) + cax * w
        r = bg.radial([ua], y, cc, ph, sigma=2.0, nfin=max(16, nseg)) + 0.036
        r = r + 0.026 * smooth01((Y_SLEEVE_HEM + 0.20 - y) / 0.20)            # the hem stands off the arm
        dy = S[1] - y
        rsph = math.sqrt(max(Rs * Rs - dy * dy, 0.0))
        r = np.maximum(r, rsph * w)
        r = bg.smooth_circ(r, 1.0)
        rows.append(bg.ring(cc, r, ph, y))
    # the dome: rings on the sphere about the pivot, up to a pole over the shoulder
    for a in np.radians([0, 20, 40, 58, 74]):
        y = S[1] + Rs * math.sin(a)
        rows.append(bg.ring(cax, np.full(nseg, Rs * math.cos(a)), ph, y))
    pole = np.array([S[0], S[1] + Rs, S[2]])
    G = np.array(rows)
    lipr = bg.lip(G[0], (G[0][:, 0].mean(), G[0][:, 2].mean()), (0, -1, 0), 0.026)
    GG = np.array(lipr[::-1] + list(G))
    sl = bg.sheet(GG, pole_hi=pole, nref=range(2, 2 + len(ys)))
    # the hem band: the bottom 0.07 + the lip, 0.006 out
    Nd = grid_normals(GG)
    t = 0.07 / (ys[1] - ys[0])
    up = GG[2] * (1 - t) + GG[3] * t
    nu = Nd[2] * (1 - t) + Nd[3] * t
    hrows = [GG[0] + Nd[0] * 0.006, GG[1] + Nd[1] * 0.006, GG[2] + Nd[2] * 0.006, up + nu * 0.006]
    tuck_r = up + nu * 0.006 + np.array([0, 0.01, 0]) - nu * 0.01
    hem = bg.sheet(np.array(hrows + [tuck_r]), nref=[2, 3])
    return sl, hem


# ------------------------------------------------------------------------------------------ trousers
class Field:
    """a seat's radius (min over the waist pieces of the tiers given) on a (y, phi) grid"""

    def __init__(self, fns, c, y0, y1):
        self.c = np.asarray(c, float)
        self.ys = np.arange(y0, y1 + 0.001, 0.01)
        self.ph = phis_of(96)
        self.R = np.array([np.min([f(y, self.ph) for f in fns], axis=0) for y in self.ys])
        self.y0 = y0

    def radius(self, y, ang):
        yi = np.clip((np.asarray(y) - self.ys[0]) / 0.01, 0, len(self.ys) - 1.001)
        i0 = np.floor(yi).astype(int)
        fy = yi - i0
        a = (np.asarray(ang) + math.pi) / (2 * math.pi) * 96
        j0 = np.floor(a).astype(int) % 96
        j1 = (j0 + 1) % 96
        fa = a - np.floor(a)
        r0 = self.R[i0, j0] * (1 - fa) + self.R[i0, j1] * fa
        r1 = self.R[i0 + 1, j0] * (1 - fa) + self.R[i0 + 1, j1] * fa
        return r0 * (1 - fy) + r1 * fy

    def inside(self, P, clr):
        d = P[:, [0, 2]] - self.c
        ang = np.arctan2(d[:, 0], -d[:, 1])
        dist = np.linalg.norm(d, axis=1)
        return (P[:, 1] < self.y0) | (dist <= self.radius(P[:, 1], ang) - clr)


def waist(B, n, shirts, nseg):
    """the trousers' top on the LowerTorso of tier n (worn when the highest of its tierOf parts is n): waistband, seat,
    the fly seam; hulls the LowerTorso, the UpperTorso and the shirt of tier n and under (turned through the waist's
    twists and bends) and the thighs (swung through the walk). -> (lp, c, fn)"""
    lower = [k for k in TIERS if k <= n]
    lt = B.part(n, "LowerTorso")
    c = np.array([0.0, float((lt["P"][:, 2].min() + lt["P"][:, 2].max()) / 2)])
    wj = B.J(n, "Waist")
    srcs = []
    for k in lower:
        srcs.append(B.part(k, "LowerTorso"))
        ut = B.part(k, "UpperTorso")
        srcs.append((ut, dict(ymin=3.0)))
        srcs += turned(ut, wj, WAIST_TURNS, ymin=3.0)
        sh = shirts[k]
        srcs.append((sh, dict(ymin=3.0)))
        srcs += turned(sh, wj, WAIST_TURNS, ymin=3.0)
        for s in ("Right", "Left"):
            srcs.append(B.part(k, s + "UpperLeg"))
    # (no swung thighs: the seat stays snug and the trouser legs flare out to its edge; a swung leg's top creases
    # into the seat, cloth into cloth of the same colour)

    def off(y):
        return 0.018 + 0.016 * smooth01((Y_BELT[0] - y) / 0.5)

    def fn(y, ph):
        return bg.radial(srcs, y, c, ph, sigma=3.0, nfin=max(16, len(ph))) + off(y)
    ph = phis_of(nseg)
    fly = bump(ph, -7, 2.5)
    ys = [Y_WAIST_TOP, 3.40, 3.30, 3.20, 3.08, 2.95, 2.82, 2.70, 2.58, 2.49, Y_CROTCH]
    rows = []
    for y in ys:
        r = fn(y, ph) + 0.004 * fly * (2.62 < y < 3.22)
        rows.append(bg.ring(c, r, ph, y))
    G = list(rows)
    e = G[-1]
    w = bg.inward(e, c)
    r1 = e + np.array([0, -0.018, 0]) + w * 0.022
    r2 = e + np.array([0, -0.035, 0]) + w * 0.16
    ctr = np.array([c[0], Y_CROTCH - 0.035, c[1]])
    top = bg.lip(G[0], c, (0, 1, 0), 0.025)
    GG = np.array(top[::-1] + G + [r1, r2])
    lp = bg.sheet(GG, pole_hi=ctr, nref=range(2, 2 + len(ys)))
    return lp, c, fn


def belt(fn, c, nseg):
    """the belt: a leather band round the waistband with stitched edges, and the buckle at the front"""
    ph = phis_of(nseg)
    y0, y1 = Y_BELT
    rows = []
    for i, y in enumerate(np.linspace(y0, y1, 5)):
        edge = 0.0 if i in (0, 4) else 1.0
        st = -0.0025 if i in (1, 3) else 0.0
        rows.append(bg.ring(c, fn(y, ph) + 0.012 + 0.004 * edge + st, ph, y))
    top = bg.lip(rows[-1], c, (0, 1, 0), 0.012)
    bot = bg.lip(rows[0], c, (0, -1, 0), 0.012)
    band = bg.sheet(np.array(bot[::-1] + rows + top), nref=range(2, 7))
    # the buckle: a rounded rectangular frame, its prong across the middle
    yc = (y0 + y1) / 2
    Pb = band["P"]
    zf = float(Pb[np.abs(Pb[:, 0]) < 0.04][:, 2].min()) - 0.022   # (in front of the band's own front)
    hw, hh = 0.105, 0.085
    loop = []
    for a in np.linspace(0, 2 * math.pi, 21):
        ca, sa = math.cos(a), math.sin(a)
        x = hw * np.sign(ca) * min(1.0, abs(ca) * 1.6)
        yy = hh * np.sign(sa) * min(1.0, abs(sa) * 1.6)
        loop.append((x, yc + yy, zf))
    frame = bb.tube(loop, [0.018] * len(loop), nside=6, kcap=1)
    frame = squash(frame, np.array([0, yc, zf]), (0, 0, 1), 0.6)
    plate = disc(np.array([0, yc, zf + 0.008]), (0, 0, -1), 0.07, 0.008, nside=12)
    plate = squash(plate, np.array([0, yc, zf]), (1, 0, 0), 1.25)
    prong = bb.tube([(-hw * 0.9, yc, zf - 0.006), (hw * 0.6, yc, zf - 0.008)], [0.009, 0.009], nside=5, kcap=1)
    return band, bg.merge([frame, plate, prong])


def knee_radius(B):
    """the trousers' knee sphere (every tier: a thigh of one tier, a shin of another meet it): the widest knee + ease"""
    r = 0.0
    for n in TIERS:
        k = B.J(n, "RightKnee")
        for nm in ("RightUpperLeg", "RightLowerLeg"):
            P = B.part(n, nm)["P"]
            m = np.abs(P[:, 1] - k[1]) < 0.12
            r = max(r, float(np.max(np.linalg.norm(P[m][:, [0, 2]] - k[[0, 2]], axis=1))))
    return r + 0.05


def thigh(B, n, field, Rk, nseg):
    """the right trouser leg on the UpperLeg of tier n: closed inside the seat at the top, a straight drape over the
    thigh, the front and back creases, ending in the knee sphere"""
    ph = phis_of(nseg)
    ul = B.part(n, "RightUpperLeg")
    hip = B.J(n, "RightHip")
    K = B.J(n, "RightKnee")
    kax = np.array([K[0], K[2]])
    crease = bump(ph, 0, 3.0) + bump(ph, 180, 3.0)
    ys = [Y_LEG_TOP, 2.66, 2.52, 2.41, 2.36, 2.30, 2.20, 2.05, 1.85, 1.68, K[1] + 0.12, K[1]]
    rows = []
    for y in ys:
        cc = bg.centroid([ul], min(y, 2.75))
        cc = np.array([hip[0], 0.0]) if cc is None else cc
        w = smooth01((K[1] + 0.5 - y) / 0.5)
        cc = cc * (1 - w) + kax * w
        r = bg.radial([ul], min(y, 2.75), cc, ph, sigma=3.0, nfin=max(16, nseg)) + 0.045
        r = bg.smooth_circ(np.maximum(r, bg.smooth_circ(r, 6)), 1.0)
        r = r * (1 - w) + np.maximum(r, Rk) * w
        r = r + 0.006 * crease * (y < 2.55)
        Rg = bg.ring(cc, r, ph, y)
        side = np.sin(ph)
        if field.y0 - 0.16 < y <= field.y0 - 0.01:
            # just under the seat's edge the leg flares out to it (outer side, front, back), so the seat ends in a
            # seam, not an overhang (build_gear.trunk_leg's)
            ds = Rg[:, [0, 2]] - field.c
            ang = np.arctan2(ds[:, 0], -ds[:, 1])
            lim = field.radius(field.y0, ang)
            dist = np.linalg.norm(ds, axis=1)
            w = np.clip(1 - (field.y0 - y) / 0.16, 0, 1) ** 1.5
            near = np.clip(1 - (lim - dist - 0.02) / 0.22, 0, 1) * np.clip(1.0 + side * 1.4, 0, 1)
            want = np.maximum(dist, dist + (lim - 0.012 - dist) * w * near)
            kk = want / np.maximum(dist, 1e-9)
            Rg[:, 0] = field.c[0] + ds[:, 0] * kk
            Rg[:, 2] = field.c[1] + ds[:, 1] * kk
        if y > field.y0 - 0.16:
            d = Rg[:, [0, 2]] - cc
            kbest = np.ones(len(Rg))
            done = np.zeros(len(Rg), bool)
            for kk in np.arange(1.0, 0.39, -0.02):
                Q = Rg.copy()
                Q[:, 0] = cc[0] + d[:, 0] * kk
                Q[:, 2] = cc[1] + d[:, 1] * kk
                ok = np.ones(len(Rg), bool)
                for deg in bg.HIP_SWING:
                    ok &= field.inside(bg.swung(Q, hip, deg), 0.012 if y > field.y0 else 0.0)
                new = ok & ~done
                kbest[new] = kk
                done |= ok
                if done.all():
                    break
            kbest[~done] = 0.4
            rr = bg.radial([ul], min(y, 2.75), cc, ph, sigma=3.0, nfin=max(16, nseg))
            kfloor = (rr + 0.008) / np.maximum(np.linalg.norm(d, axis=1), 1e-9)
            kbest = np.minimum(1.0, np.maximum(kbest, kfloor))
            Rg[:, 0] = cc[0] + d[:, 0] * kbest
            Rg[:, 2] = cc[1] + d[:, 1] * kbest
        rows.append(Rg)
    # under the knee pivot: the sphere
    for a in np.radians([22, 45, 66, 82]):
        rows.append(bg.ring(kax, np.full(nseg, Rk * math.cos(a)), ph, K[1] - Rk * math.sin(a)))
    pole = np.array([K[0], K[1] - Rk, K[2]])
    topc, tpole = bg.tuck(rows[0], rows[0][:, [0, 2]].mean(0), (0, 1, 0), 0.03)
    G = np.array(topc[::-1] + rows)
    return bg.sheet(G, pole_lo=tpole, pole_hi=pole, nref=range(2, 2 + len(ys)))


def shin(B, n, Rk, Rh, nseg):
    """the right trouser shin on the LowerLeg of tier n: its top a sphere inside the thigh's knee sphere, the tube from
    just outside that sphere straight down to the hem over the shoe (lower at the back), creases, the hem's lip"""
    ph = phis_of(nseg)
    ll = B.part(n, "RightLowerLeg")
    K = B.J(n, "RightKnee")
    Ak = B.J(n, "RightAnkle")
    ax = np.array([K[0], K[2]])
    crease = bump(ph, 0, 3.0) + bump(ph, 180, 3.0)
    rows = []
    Ri = Rk - 0.012
    for a in np.radians([80, 62, 40, 18]):
        rows.append(bg.ring(ax, np.full(nseg, Ri * math.cos(a)), ph, K[1] + Ri * math.sin(a)))
    front = np.cos(ph)
    yh = 0.235 + 0.06 * np.clip(front, -1, 1) * 0.5 + 0.03     # the hem: 0.295 at the front, 0.235 at the back
    ys = [K[1], K[1] - 0.10, 1.15, 0.95, 0.75, 0.58, 0.46, 0.38]
    for y in ys:
        t = (K[1] - y) / (K[1] - 0.38)
        cc = bg.centroid([ll], max(y, 0.5))
        cc = ax if cc is None else cc
        cc = ax * 0.6 + cc * 0.4
        r_body = bg.radial([ll], max(y, 0.5), cc, ph, sigma=3.0, nfin=max(16, nseg)) + 0.035
        rr = np.full(nseg, (Rk + 0.006) * (1 - t) + Rh * t)
        r = np.maximum(rr, bg.smooth_circ(r_body, 4))
        r = r + 0.006 * crease
        rows.append(bg.ring(cc, r, ph, y))
    # the hem: the last ring follows the hem line (front higher), then the lip turns in
    last = rows[-1].copy()
    hem = last.copy()
    hem[:, 1] = yh
    hem[:, 0] = last[:, 0] + (last[:, 0] - last[:, 0].mean()) * 0.02
    hem[:, 2] = last[:, 2] + (last[:, 2] - last[:, 2].mean()) * 0.02
    rows.append(hem)
    c_h = (hem[:, 0].mean(), hem[:, 2].mean())
    lipr = bg.lip(hem, c_h, (0, -1, 0), 0.028)
    pole = np.array([K[0], K[1] + Ri, K[2]])
    G = np.array(rows + lipr)
    return bg.sheet(G[::-1], pole_lo=None, pole_hi=pole, nref=range(2, len(rows)))


# ------------------------------------------------------------------------------------------ shoes
def shoe(B, nseg):
    """the dress shoe on the (shared) foot: the foot inflated 0.03, the toe a little longer and lower, flat on the
    sole; the welt sole with a raised heel block; three lace bars over the instep"""
    ft = B.part(3, "RightFoot")
    up = bg.offset_lp(ft, 0.030)
    P = up["P"].copy()
    zmin = P[:, 2].min()
    # a sleeker last: the toe box a little lower and longer
    zt = P[:, 2] < zmin + 0.22
    P[zt, 2] -= 0.025 * smooth01((zmin + 0.22 - P[zt, 2]) / 0.22)
    P[zt, 1] = 0.045 + (P[zt, 1] - 0.045) * (1 - 0.18 * smooth01((zmin + 0.22 - P[zt, 2]) / 0.22))
    P[:, 1] = np.maximum(P[:, 1], 0.045)
    up["P"] = P
    # the sole: footprint outline + welt, heel block at the back (rings at heights varying with z)
    ph = phis_of(nseg)
    c = bg.centroid([up], 0.06)
    r = bg.radial([up], 0.06, c, ph, sigma=2.0, nfin=nseg) + 0.018
    base = bg.ring(c, r, ph, 0.0)
    zb = base[:, 2]
    heel = smooth01((zb - (c[1] + 0.10)) / 0.06)
    htop = 0.050 + 0.035 * heel
    rows = []
    for yy, dr in ((0.004, -0.012), (0.0, 0.0)):
        R = bg.ring(c, r + dr, ph, yy)
        rows.append(R)
    R = bg.ring(c, r + 0.004, ph, 0.0)
    R[:, 1] = htop * 0.55
    rows.append(R)
    R = bg.ring(c, r + 0.004, ph, 0.0)
    R[:, 1] = htop
    rows.append(R)
    R = bg.ring(c, r - 0.05, ph, 0.0)
    R[:, 1] = htop + 0.004
    rows.append(R)
    ctr_lo = np.array([c[0], 0.004, c[1]])
    ctr_hi = np.array([c[0], htop.min(), c[1]])
    sole = bg.sheet(np.array(rows), pole_lo=ctr_lo, pole_hi=ctr_hi, nref=[1, 2, 3])
    # laces: three bars over the instep
    X = B.J(3, "RightAnkle")[0]
    bars = []
    for z in (-0.13, -0.19, -0.25):
        L = hit(up, (X - 0.06, 1.0, z), (0, -1, 0), 0.010)
        Rr = hit(up, (X + 0.06, 1.0, z), (0, -1, 0), 0.010)
        if L is not None and Rr is not None:
            bars.append(bb.tube([L, Rr], [0.013, 0.013], nside=5, kcap=1))
    return up, sole, bg.merge(bars)


def shoe_collar_radius(shoe_lp, B):
    A = B.J(3, "RightAnkle")
    P = shoe_lp["P"]
    m = (P[:, 1] > 0.20) & (P[:, 1] < 0.40) & (P[:, 2] > A[2] - 0.12)
    return float(np.max(np.linalg.norm(P[m][:, [0, 2]] - A[[0, 2]], axis=1)))


# ------------------------------------------------------------------------------------------ build / export
def build_set(B, lite):
    ns = 24 if lite else 48       # ring segments (torso); limbs use half
    nl = 16 if lite else 32
    gear = {n: {} for n in TIERS}
    shoe_up, sole, laces = shoe(B, 32 if lite else 48)
    Rh = shoe_collar_radius(shoe_up, B) + 0.03
    Rk = knee_radius(B)
    shirts, info = {}, {}
    for n in TIERS:
        lp, (Gd, ys, ph), fn, c = shirt(B, n, ns)
        shirts[n] = lp
        info[n] = (Gd, ys, ph, fn, c)
    waist_fns, wc = {}, None
    waists = {}
    for n in TIERS:
        w, c, fn = waist(B, n, shirts, ns)
        waists[n] = (w, fn)
        waist_fns[n] = fn
        wc = c
    for n in TIERS:
        d = gear[n]
        Gd, ys, ph, fn, c = info[n]
        sh = shirts[n]
        d["OffShirt"] = (sh, "UpperTorso")
        col = collar(B, n, fn, c, ns)
        d["OffCollar"] = (col, "UpperTorso")
        d["OffPlacket"] = (placket(Gd, ys, ph, 3.36), "UpperTorso")
        d["OffButtons"] = (buttons(sh, c, [3.68, 3.98, 4.28, 4.58, 4.88]), "UpperTorso")
        d["OffPolo"] = (placket(Gd, ys, ph, 4.72, w_deg=5.2), "UpperTorso")
        d["OffPoloButtons"] = (buttons(sh, c, [4.84, 5.0]), "UpperTorso")
        d["OffPocket"] = (pocket(Gd, ys, ph), "UpperTorso")
        d["OffBadge"] = (badge(sh, c), "UpperTorso")
        d["OffBowTie"] = (bow_tie(col, c), "UpperTorso")
        d["OffTowel"] = (towel(B.part(n, "UpperTorso"), sh, c), "UpperTorso")
        w, wfn = waists[n]
        d["OffWaist"] = (w, "LowerTorso")
        band, buckle = belt(wfn, wc, ns)
        d["OffBelt"] = (band, "LowerTorso")
        d["OffBuckle"] = (buckle, "LowerTorso")
        # a trouser leg of tier n is worn under a waist of tier n or higher
        field = Field([waist_fns[k] for k in TIERS if k >= n], wc, Y_CROTCH, 3.10)
        R = {"OffSleeve": None, "OffSleeveHem": None}
        R["OffSleeve"], R["OffSleeveHem"] = sleeve(B, n, nl)
        R["OffThigh"] = thigh(B, n, field, Rk, nl)
        R["OffShin"] = shin(B, n, Rk, Rh, nl)
        R["OffShoe"], R["OffSole"], R["OffLaces"] = shoe_up, sole, laces
        for k, lp in R.items():
            base = PIECES[k][0]
            d[k + "_R"] = (lp, "Right" + base)
            d[k + "_L"] = (bb.mirror_lp(lp), "Left" + base)
    return gear


def export(B, gear, out_dir):
    os.makedirs(os.path.join(out_dir, "shared"), exist_ok=True)
    data = {"version": 1, "slots": SLOTS, "pieces": {}, "sets": SETS, "tiers": {}}
    for name, (base, slot, sided, shared, tier_of) in PIECES.items():
        for side in (("R", "L") if sided else ("",)):
            key = name + ("_" + side if side else "")
            rec = {"part": (("Right" if side == "R" else "Left") + base) if side else base, "slot": slot,
                   "group": "official", "shared": shared}
            if tier_of:
                rec["tierOf"] = tier_of
            data["pieces"][key] = rec
    written = {}
    for n in TIERS:
        td = os.path.join(out_dir, "tier%d" % n)
        os.makedirs(td, exist_ok=True)
        rec = {}
        for key, (lp, part) in gear[n].items():
            base = key[:-2] if key.endswith(("_R", "_L")) else key
            if PIECES[base][3]:
                rel = "shared/%s.mesh" % key
                if rel not in written:
                    written[rel] = bg.write_piece(os.path.join(out_dir, rel), gear[3][key][0])
                _, size, nt = written[rel]
                lo, hi = lp["P"].min(0), lp["P"].max(0)
                cen = (lo + hi) / 2
            else:
                rel = "tier%d/%s.mesh" % (n, key)
                cen, size, nt = bg.write_piece(os.path.join(out_dir, rel), lp)
            pc = B.centre(n, part)
            rec[key] = {"file": rel, "part": part, "offset": [round(float(x), 4) for x in cen - pc],
                        "size": [round(float(x), 4) for x in size], "nt": nt}
        data["tiers"][str(n)] = rec
    worn = {}
    for style, names in SETS["official"].items():
        tot = 0
        for p in names:
            for key in ([p + "_R", p + "_L"] if PIECES[p][2] else [p]):
                tot += data["tiers"]["5"][key]["nt"]
        worn[style] = tot
    data["worn_tris_tier5"] = worn
    with open(os.path.join(out_dir, "official.json"), "w") as f:
        json.dump(data, f, indent=1)
    return data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="full,lite")
    a = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    full = bg.Bodies()
    for which in a.only.split(","):
        B = full if which == "full" else LiteBodies(full)
        gear = build_set(B, which == "lite")
        data = export(B, gear, OUT_FULL if which == "full" else OUT_LITE)
        print(which, "worn tris (tier 5):", data["worn_tris_tier5"])
        for n in TIERS:
            print("  tier %d:" % n, " ".join("%s=%d" % (k, v["nt"]) for k, v in data["tiers"][str(n)].items()
                                           if not k.endswith("_L")))


if __name__ == "__main__":
    main()
