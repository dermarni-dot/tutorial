"""Shared helpers for the hair-card builders (run inside Blender's Python: /opt/bpyenv/bin/python).

Coordinates: everything here is the game's NOMINAL head space, numerically (no axis conversion):
studs for a 1.2-stud head, +X the character's right, +Y up, -Z forward (the face), origin at the
Head part's centre. The game scales each piece by Head.Size / 1.2 per axis and a small affine skull
fit (see CONTRACT.md). Blender objects built from these arrays are rotated only for rendering.

A Piece is one MeshPart in the game: positions, normals, UVs (0,0 = top-left texel, v grows down,
like EditableImage rows), vertex colours (RGBA 0..1: RGB is baked occlusion, the game's texture
tint multiplies on top) and triangles (counter-clockwise from the front side).

Card textures (strands.py) run roots at the top of a strip (v = 0) and tips at the bottom (v = 1);
ATLAS gives each strip's u range so a builder only says which strip a card uses.
"""
import json
import math
import os
import struct

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
# the head the hair is modelled on: the classic Roblox head every boxer has (ref/classic, classic_ref.py; v9).
# HAIR_REF=organic selects the retired organic skull (ref/, the v7 meshes' reference)
REF = os.path.join(HERE, "ref") if os.environ.get("HAIR_REF") == "organic" else os.path.join(HERE, "ref", "classic")
CLASSIC = REF.endswith("classic")
OUT = os.environ.get("HAIR_OUT") or os.path.join(HERE, "out")


def _fit0():
    """the runtime skull fit's reference extents (CONTRACT.md): the reference skull.json's fit0 (the classic head:
    W 0.6, T 0.6, Fz -0.6, Bz 0.6), else the organic default male's"""
    try:
        with open(os.path.join(REF, "skull.json")) as f:
            d = json.load(f).get("fit0")
        if d:
            return {k: d[k] for k in ("W", "T", "Fz", "Bz")}
    except OSError:
        pass
    return dict(W=0.383, T=0.591, Fz=-0.460, Bz=0.520)


FIT0 = _fit0()

# ----------------------------------------------------------------------------------- zones (classic -> organic)
# The builders' zone tests (beside the ear, the temples, the fringe, the nape, the face guard ...) were written in
# the organic skull's coordinates. On the classic head every such test reads org(p): a piecewise-linear map that
# takes the classic head's landmarks onto the organic skull's (its sides x 0.6 -> 0.383; heights: the nape
# -0.3 -> -0.27, the ear's centre 0.035 -> -0.08 and top 0.2 -> 0.053, the front hairline 0.421 -> 0.336, the top
# 0.6 -> 0.611; depths: the face -0.6 -> -0.46, the ear 0.06 -> 0.15, the back 0.6 -> 0.52; the body far below
# unchanged). Geometry is never built through it: only the predicates. Identity on the organic reference.
_ZY = ((-2.5, -2.5), (-0.95, -0.95), (-0.6, -0.5), (-0.3, -0.27), (0.035, -0.08), (0.2, 0.053), (0.421, 0.336),
       (0.6, 0.611), (1.5, 1.5))
_ZZ = ((-1.6, -1.46), (-0.6, -0.46), (0.06, 0.15), (0.6, 0.52), (1.6, 1.52))
ZX = 0.383 / 0.6


def _pl(knots, v, inverse=False):
    a = np.array([k[1 if inverse else 0] for k in knots])
    b = np.array([k[0 if inverse else 1] for k in knots])
    return np.interp(v, a, b, left=None, right=None) + np.where(v < a[0], v - a[0], 0) + np.where(v > a[-1], v - a[-1], 0)


def org(p):
    """classic-head point(s) -> the organic skull's equivalent (zone tests only); identity when not CLASSIC"""
    if not CLASSIC:
        return p
    q = np.array(p, dtype=np.float64, copy=True)
    q[..., 0] = q[..., 0] * ZX
    q[..., 1] = _pl(_ZY, q[..., 1])
    q[..., 2] = _pl(_ZZ, q[..., 2])
    return q


def unorg(q):
    """the inverse of org"""
    if not CLASSIC:
        return q
    p = np.array(q, dtype=np.float64, copy=True)
    p[..., 0] = p[..., 0] / ZX
    p[..., 1] = _pl(_ZY, p[..., 1], inverse=True)
    p[..., 2] = _pl(_ZZ, p[..., 2], inverse=True)
    return p


def mean_radius(sk, th_max=2.0):
    """the reference skull's mean radius over its upper part (box partings, scalp grids: ~0.47 organic)"""
    m = sk.th <= th_max
    return float(np.mean(sk.r[m]))

# u ranges of the strips in each family atlas (must match strands.py)
ATLAS = {
    "straight": {"dense": (0.0, 0.25), "medium": (0.25, 0.5), "wispy": (0.5, 0.75), "wavy": (0.75, 1.0)},
    "coily": {"tight": (0.0, 0.5), "loose": (0.5, 1.0)},
    "braid": {"plait": (0.0, 0.5), "loc": (0.5, 1.0)},
    "cornrow": {"row": (0.0, 0.75), "baby": (0.75, 1.0)},
    "short": {"tile": (0.0, 1.0)},
}
TEXTURES = list(ATLAS)


# ----------------------------------------------------------------------------------- vectors
def v3(x, y, z):
    return np.array([x, y, z], dtype=np.float64)


def norm(a):
    n = float(np.linalg.norm(a))
    return a / n if n > 1e-12 else a


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


# ----------------------------------------------------------------------------------- skull
class Skull:
    """The default skull's radial table (tools/hair/ref/skull.json, exported from the game's own
    AnatomySkull by tools/sim/export_ref.luau). dir(theta, az) = (sin th sin az, cos th, sin th cos az):
    theta from +Y, az = 0 at the back (+Z), increasing toward the character's right (+X)."""

    def __init__(self, path=None):
        path = path or os.path.join(REF, "skull.json")
        with open(path) as f:
            d = json.load(f)
        self.data = d
        rt = d["radial"]
        self.c = v3(*(rt.get("centre") or d["centre"]))
        self.th = np.radians(np.asarray(rt["thetas"], dtype=np.float64))
        self.az = np.radians(np.asarray(rt["azimuths"], dtype=np.float64))
        self.r = np.asarray(rt["r"], dtype=np.float64)  # [len(th)][len(az)]

    @staticmethod
    def direction(theta, az):
        s = math.sin(theta)
        return v3(s * math.sin(az), math.cos(theta), s * math.cos(az))

    @staticmethod
    def angles(d):
        d = norm(d)
        theta = math.acos(max(-1.0, min(1.0, d[1])))
        az = math.atan2(d[0], d[2]) % (2 * math.pi)
        return theta, az

    def radius(self, theta, az):
        th = self.th
        theta = min(max(theta, th[0]), th[-1])
        i = int(np.searchsorted(th, theta) - 1)
        i = max(0, min(len(th) - 2, i))
        ti = (theta - th[i]) / (th[i + 1] - th[i])
        n = len(self.az)
        step = 2 * math.pi / n
        a = (az % (2 * math.pi)) / step
        j = int(math.floor(a)) % n
        tj = a - math.floor(a)
        j2 = (j + 1) % n
        r = self.r
        top = r[i][j] * (1 - tj) + r[i][j2] * tj
        bot = r[i + 1][j] * (1 - tj) + r[i + 1][j2] * tj
        return top * (1 - ti) + bot * ti

    def point(self, theta, az, off=0.0):
        """scalp point (plus off studs along the radial direction)"""
        return self.c + self.direction(theta, az) * (self.radius(theta, az) + off)

    def normal(self, theta, az, h=0.02):
        p0 = self.point(theta, az)
        pt = self.point(theta + h, az)
        pa = self.point(theta, az + h / max(0.15, math.sin(theta)))
        n = np.cross(pt - p0, pa - p0)
        n = norm(n)
        if np.dot(n, p0 - self.c) < 0:
            n = -n
        return n

    def project(self, p, off=0.0):
        """the scalp point (+off) under p, along the radial direction from the centre"""
        th, az = self.angles(p - self.c)
        return self.point(th, az, off), th, az

    def height(self, p):
        """how far p is outside the scalp along its radial direction"""
        d = p - self.c
        th, az = self.angles(d)
        return float(np.linalg.norm(d)) - self.radius(th, az)

    def hairline(self):
        return self.data.get("hairline")


# ----------------------------------------------------------------------------------- pieces
class Piece:
    """One game MeshPart. hairfx / hideUnder follow AnatomyHair's piece contract (CONTRACT.md)."""

    def __init__(self, name, tex, **meta):
        self.name = name
        self.tex = tex  # family atlas key (TEXTURES) or "cap"
        self.meta = meta  # hairfx, hideUnder, length, material, ...
        self.P, self.N, self.U, self.C = [], [], [], []
        self.T = []

    @property
    def nv(self):
        return len(self.P)

    @property
    def nt(self):
        return len(self.T)

    def vert(self, p, n, uv, c=(1.0, 1.0, 1.0, 1.0)):
        self.P.append(tuple(float(x) for x in p))
        self.N.append(tuple(float(x) for x in norm(np.asarray(n, dtype=np.float64))))
        self.U.append((float(uv[0]), float(uv[1])))
        c = tuple(float(x) for x in c)
        if len(c) == 3:
            c = c + (1.0,)
        self.C.append(c)
        return len(self.P) - 1

    def tri(self, a, b, c):
        self.T.append((a, b, c))

    def quad(self, a, b, c, d):
        # a b / d c  (counter-clockwise a, b, c, d seen from the front)
        self.T.append((a, b, c))
        self.T.append((a, c, d))

    def merge(self, other):
        base = self.nv
        self.P += other.P
        self.N += other.N
        self.U += other.U
        self.C += other.C
        self.T += [(a + base, b + base, c + base) for a, b, c in other.T]

    # -- builders ------------------------------------------------------------------------------
    def card(self, pts, widths, up, strip, v0=0.0, v1=1.0, shade=None, double=True, normals=None, twist=None):
        """A strand card along the polyline pts (root first). widths: one per point (studs).
        up: the card's facing hint per point (usually the outward scalp normal): the card lies in
        the plane spanned by the tangent and the side vector cross(tangent, up). strip: (u0, u1).
        shade(t) -> (r, g, b) occlusion per point (t = 0 root .. 1 tip). normals: per-point shading
        normals (default: up, so a layer of cards shades like one soft surface)."""
        pts = [np.asarray(p, dtype=np.float64) for p in pts]
        n = len(pts)
        u0, u1 = strip
        rows = []
        for i in range(n):
            if i == 0:
                tan = pts[1] - pts[0]
            elif i == n - 1:
                tan = pts[-1] - pts[-2]
            else:
                tan = pts[i + 1] - pts[i - 1]
            tan = norm(tan)
            upi = norm(np.asarray(up[i] if isinstance(up, (list, tuple)) else up, dtype=np.float64))
            side = norm(np.cross(tan, upi))
            if twist is not None:
                a = twist[i]
                face = norm(np.cross(side, tan))
                side = norm(side * math.cos(a) + face * math.sin(a))
            t = i / (n - 1)
            v = v0 + (v1 - v0) * t
            sh = shade(t) if shade else (1.0, 1.0, 1.0)
            nn = normals[i] if normals is not None else upi
            hw = widths[i] * 0.5
            a = self.vert(pts[i] - side * hw, nn, (u0, v), sh)
            b = self.vert(pts[i] + side * hw, nn, (u1, v), sh)
            rows.append((a, b))
        for i in range(n - 1):
            a, b = rows[i]
            c, d = rows[i + 1][1], rows[i + 1][0]
            # front side faces +up: a(left,root) b(right,root) c(right,next) d(left,next)
            self.T.append((a, d, c))
            self.T.append((a, c, b))
            if double:
                self.T.append((a, c, d))
                self.T.append((a, b, c))
        return rows

    def tube(self, pts, radii, sides, strip, v_per_stud=None, v_len=1.0, shade=None, ups=None, cap_tip=True,
             flatten=1.0):
        """A round tube along pts (locs, braids, twists, cornrow ridges). radii per point. u wraps
        round the tube inside strip (u0..u1), v runs along it: v_per_stud repeats the texture once
        per that many studs (tileable textures), else v goes 0..v_len. flatten < 1 squashes the
        section along ups (cornrows lie flat on the scalp)."""
        pts = [np.asarray(p, dtype=np.float64) for p in pts]
        n = len(pts)
        u0, u1 = strip
        # parallel-transport frame
        tan0 = norm(pts[1] - pts[0])
        ref = np.asarray(ups[0], dtype=np.float64) if ups is not None else v3(0, 0, 1)
        if abs(np.dot(ref, tan0)) > 0.95:
            ref = v3(1, 0, 0)
        nrm = norm(np.cross(np.cross(tan0, ref), tan0))
        acc = 0.0
        rings = []
        prev_tan = tan0
        for i in range(n):
            if i == 0:
                tan = tan0
            elif i == n - 1:
                tan = norm(pts[-1] - pts[-2])
            else:
                tan = norm(pts[i + 1] - pts[i - 1])
            # rotate nrm from prev_tan to tan
            ax = np.cross(prev_tan, tan)
            s = float(np.linalg.norm(ax))
            if s > 1e-9:
                ax = ax / s
                ang = math.atan2(s, float(np.dot(prev_tan, tan)))
                nrm = (nrm * math.cos(ang) + np.cross(ax, nrm) * math.sin(ang)
                       + ax * np.dot(ax, nrm) * (1 - math.cos(ang)))
            if ups is not None:  # keep the flattening axis on the given up
                up = norm(np.asarray(ups[i], dtype=np.float64))
                nrm = norm(up - tan * np.dot(up, tan))
            prev_tan = tan
            bin_ = norm(np.cross(tan, nrm))
            if i > 0:
                acc += float(np.linalg.norm(pts[i] - pts[i - 1]))
            t = i / (n - 1)
            v = acc / v_per_stud if v_per_stud else v_len * t
            sh = shade(t) if shade else (1.0, 1.0, 1.0)
            ring = []
            for k in range(sides + 1):
                a = 2 * math.pi * k / sides
                d = nrm * math.cos(a) * flatten + bin_ * math.sin(a)
                dn = norm(nrm * math.cos(a) / max(0.2, flatten) + bin_ * math.sin(a))
                ring.append(self.vert(pts[i] + d * radii[i], dn, (u0 + (u1 - u0) * k / sides, v), sh))
            rings.append(ring)
        for i in range(n - 1):
            r0, r1 = rings[i], rings[i + 1]
            for k in range(sides):
                self.quad(r0[k], r1[k], r1[k + 1], r0[k + 1])
        if cap_tip:
            tip = pts[-1] + norm(pts[-1] - pts[-2]) * radii[-1] * 0.6
            sh = shade(1.0) if shade else (1.0, 1.0, 1.0)
            c = self.vert(tip, norm(pts[-1] - pts[-2]), ((u0 + u1) / 2, rings[-1][0] and self.U[rings[-1][0]][1]), sh)
            r = rings[-1]
            for k in range(sides):
                self.tri(r[k], c, r[k + 1])
        return rings

    # -- data ----------------------------------------------------------------------------------
    def bbox(self):
        P = np.asarray(self.P)
        lo, hi = P.min(axis=0), P.max(axis=0)
        return lo, hi

    def sample_points(self, n=160):
        """a decimated point cloud on the geometry (HairFX's body / canvas tests): every vertex
        group's extremes plus a farthest-point sample"""
        P = np.asarray(self.P)
        if len(P) <= n:
            return P
        idx = [int(np.argmin(P[:, 1])), int(np.argmax(P[:, 1])), int(np.argmin(P[:, 0])), int(np.argmax(P[:, 0])),
               int(np.argmin(P[:, 2])), int(np.argmax(P[:, 2]))]
        d = np.full(len(P), np.inf)
        for i in idx:
            d = np.minimum(d, np.linalg.norm(P - P[i], axis=1))
        while len(idx) < n:
            i = int(np.argmax(d))
            idx.append(i)
            d = np.minimum(d, np.linalg.norm(P - P[i], axis=1))
        return P[idx]


# ----------------------------------------------------------------------------------- .mesh writer
def front_faces(piece):
    """Triangles wound so the front face (counter-clockwise, the side Roblox draws) agrees with the
    outward shading normals. A triangle that appears twice (a two-sided card's reversed copy) is
    kept as it is; every other one is flipped when its geometric normal points against the mean of
    its vertices' normals. card() / tube() used to wind inward, and builders work around that in
    different ways, so the writer settles it for every family."""
    P = np.asarray(piece.P, dtype=np.float64)
    N = np.asarray(piece.N, dtype=np.float64)
    T = np.asarray(piece.T, dtype=np.int64)
    if len(T) == 0:
        return []
    # pair copies by position, not index: a builder may duplicate the vertices of the back side
    Q = np.round(P / 1e-5).astype(np.int64)
    tkey = [tuple(sorted(tuple(Q[v]) for v in t)) for t in T]
    keys = {}
    for i, k in enumerate(tkey):
        keys.setdefault(k, []).append(i)
    g = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    s = N[T[:, 0]] + N[T[:, 1]] + N[T[:, 2]]
    out = []
    for i, t in enumerate(T):
        a, b, c = (int(x) for x in t)
        if len(keys[tkey[i]]) == 1 and float(np.dot(g[i], s[i])) < 0:
            out.append((a, c, b))
        else:
            out.append((a, b, c))
    return out


def write_mesh_v2(path, piece):
    """Roblox mesh format 2.00: header, then per vertex position, normal, uv, tangent (int8 x4),
    colour (uint8 RGBA), then faces (uint32 x3). UVs as the game uses them (0,0 top-left)."""
    piece.T = front_faces(piece)
    nv, nt = piece.nv, piece.nt
    assert nv > 0 and nt > 0, piece.name
    out = bytearray(b"version 2.00\n")
    out += struct.pack("<HBBII", 12, 40, 12, nv, nt)
    for (p, n, uv, c) in zip(piece.P, piece.N, piece.U, piece.C):
        out += struct.pack("<3f3f2f", p[0], p[1], p[2], n[0], n[1], n[2], uv[0], uv[1])
        out += struct.pack("<4b", 0, 0, -127, 127)
        out += struct.pack("<4B", *[max(0, min(255, int(round(x * 255)))) for x in c])
    for a, b, c in piece.T:
        out += struct.pack("<3I", a, b, c)
    with open(path, "wb") as f:
        f.write(bytes(out))
    return len(out)


def piece_record(piece, mesh_file):
    lo, hi = piece.bbox()
    cen = (lo + hi) / 2
    size = hi - lo
    rec = {
        "mesh_file": os.path.basename(mesh_file),
        "tex": piece.tex,
        "bbox": [round(float(x), 5) for x in list(cen) + list(size)],
        "nv": piece.nv,
        "nt": piece.nt,
        "points": [round(float(x), 4) for p in piece.sample_points() for x in p],
    }
    rec.update(piece.meta)
    return rec


def export_style(style_key, entry, pieces, outdir=None):
    """Writes every piece's .mesh and a style JSON (the manifest entry before upload).
    entry: style-level fields (styles, types, cap, notes ...)."""
    outdir = outdir or os.path.join(OUT, style_key)
    os.makedirs(outdir, exist_ok=True)
    recs = {}
    for p in pieces:
        assert p.nt <= 20000 and p.nv <= 60000, (p.name, p.nv, p.nt)
        fn = os.path.join(outdir, p.name + ".mesh")
        write_mesh_v2(fn, p)
        recs[p.name] = piece_record(p, fn)
    data = dict(entry)
    data["key"] = style_key
    data["pieces"] = recs
    data["tris"] = sum(p.nt for p in pieces)
    with open(os.path.join(outdir, "style.json"), "w") as f:
        json.dump(data, f, indent=1)
    return data


# ----------------------------------------------------------------------------------- Blender
def to_blender(piece, bpy, material=None, collection=None):
    """Builds a Blender mesh object from a Piece (for renders and for inspection). Game space is
    kept numerically; the caller rotates the object (game +Y up -> Blender +Z up: rotate X +90)."""
    me = bpy.data.meshes.new(piece.name)
    me.from_pydata([tuple(p) for p in piece.P], [], [tuple(t) for t in piece.T])
    me.update()
    me.uv_layers.new(name="UVMap")
    me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="CORNER")
    uv = me.uv_layers["UVMap"]  # fetched after both exist: adding a layer reallocates the others
    col = me.color_attributes["Col"]
    for poly in me.polygons:
        for li, vi in zip(poly.loop_indices, poly.vertices):
            u, v = piece.U[vi]
            uv.data[li].uv = (u, 1.0 - v)  # Blender UVs are v-up
            col.data[li].color = piece.C[vi]
    # shading normals from the piece (cards shade like one soft surface)
    me.normals_split_custom_set_from_vertices([tuple(n) for n in piece.N])
    ob = bpy.data.objects.new(piece.name, me)
    if material is not None:
        me.materials.append(material)
    (collection or bpy.context.scene.collection).objects.link(ob)
    return ob
