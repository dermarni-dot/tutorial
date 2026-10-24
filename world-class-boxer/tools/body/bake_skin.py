"""Skin surface maps for the body meshes (v16): a tangent-space normal map, a greyscale ColorMap (white skin with the
ambient occlusion and cavity baked in, so SurfaceAppearance.Color tints it to the boxer's skin tone) and a
RoughnessMap per (surface tier, part type), baked from a high surface onto the game meshes' own UVs.

    /opt/bpyenv/bin/python tools/body/bake_skin.py [--tiers 1,2,3,4,5] [--parts UpperTorso,UpperArm,...]
                                                   [--preview] [--samples N]

* The high surface is the part's own loft refined DENSE times further (build_body.BAKE_CAPTURE: the same muscle
  fields, the same v15 shaping at the finer grid, the bony bumps), plus fine detail displaced along its normal:
  skin pores, pec and deltoid striations, the tendons' insertions, veins on the forearm and biceps (tiers 4-5),
  creases at the elbow and the knee (`detail()`). The low surface is the exported game mesh.
* Both share the loft's parametrisation, so the bake is done in UV space exactly (no ray casting): a texel (u, v) is
  the loft point (phi = 2 pi u - pi, the ring s at v); the high normal there is written in the low mesh's tangent frame
  (build_body.vertex_tangents: tangent = +u, green = toward the top of the image: OpenGL, what Roblox reads; the meshes
  carry the same tangents). Roblox: SurfaceAppearance.NormalMap "OpenGL format - Tangent Space".
* AO / cavity: the high surface against Gaussian-blurred copies of itself (a groove sits below its neighbourhood),
  two scales; ColorMap = white x (1 - darkening), RoughnessMap = matte in the creases, a little glossier on the raised
  muscle. Both greyscale.
* Sharing: a part type has the same UVs on every frame and tier (the lofts' topology is fixed) and the muscle grooves
  sit at the same (phi, s) on every frame, so one set per (surface tier, part type) serves every frame: Lean,
  Athletic and Muscular use their tier's set, Power Build one tier softer, Heavyweight Build two (SURFACE_SHIFT,
  mirrored in BodySurfaceData.lua). The left limbs use the right limb's maps (mirrored meshes, same UVs: the tangent
  sign flips with the winding). Hands, feet and the LowerTorso (gloves / wraps, boots, trunks) get none.
* Out: tools/body/out/skin/T<n>/<Part>_{color,normal,rough}.png + skin.json; publish_skin.py uploads them.
"""
import argparse
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_body as B  # noqa: E402

OUT = os.path.join(HERE, "out", "skin")
SURF_PARTS = {"UpperTorso": 1024, "UpperArm": 512, "LowerArm": 512, "UpperLeg": 512, "LowerLeg": 512}
SURFACE_SHIFT = {"Lean": 0, "Athletic": 0, "Muscular": 0, "Power Build": 1, "Heavyweight Build": 2}
REF_FRAME = "Athletic"
DENSE = 8


def surface_tier(frame, tier):
    return max(1, int(tier) - SURFACE_SHIFT.get(frame, 0))


# ------------------------------------------------------------------------------------------ fine detail
def _noise(X, Y, wavelength, n=40, seed=1):
    """band-limited noise in metric coordinates: n plane waves, random directions, wavelengths jittered +-35 % round
    `wavelength` (no visible interference pattern), ~[-1, 1]"""
    rng = np.random.default_rng(seed)
    out = np.zeros_like(X)
    for _ in range(n):
        a = rng.uniform(0, math.pi)
        k = 2 * math.pi / (wavelength * rng.uniform(0.65, 1.35))
        out += np.sin(k * (np.cos(a) * X + np.sin(a) * Y) + rng.uniform(0, 2 * math.pi))
    return out / math.sqrt(n / 2)


def _win(x, lo, pk, hi):
    """a smooth window: 0 outside (lo, hi), 1 at pk"""
    u = np.where(x < pk, (x - pk) / max(pk - lo, 1e-6), (x - pk) / max(hi - pk, 1e-6))
    return np.where(np.abs(u) < 1, (1 - u * u) ** 2, 0.0)


def _phiwin(a, c, w):
    d = (a - c + 180.0) % 360.0 - 180.0
    return _win(d, -w, 0.0, w)


def _vein(a, s, X, phi0, s_lo, s_hi, width, meander, seed):
    """a raised tube along s near azimuth phi0 (deg), meandering; X = metric arc coordinate per degree is approx"""
    rng = np.random.default_rng(seed)
    f1, f2, p1, p2 = rng.uniform(9, 14), rng.uniform(19, 27), rng.uniform(0, 6.3), rng.uniform(0, 6.3)
    c = phi0 + meander * (np.sin(f1 * s + p1) + 0.5 * np.sin(f2 * s + p2))
    d = (a - c + 180.0) % 360.0 - 180.0
    prof = np.exp(-((d / width) ** 2))
    return prof * _win(s, s_lo, 0.5 * (s_lo + s_hi), s_hi) ** 0.5


def detail(base, a, s, X, Y, n):
    """the fine displacement (prototype studs, along the normal) of part `base` at azimuth a (deg: 0 front, +90 the
    right limb's outer side), height s, metric surface coordinates X (round the ring) / Y (along it), tier n"""
    tr = B.TIERS[n]
    d, m = tr["d"], tr["m"]
    vein = float(np.clip((d - 0.7) / 0.3, 0, 1))
    out = 0.00032 * _noise(X, Y, 0.016, seed=3) + 0.00018 * _noise(X, Y, 0.007, seed=5)  # skin grain
    aa = np.abs(a) if base in ("UpperTorso", "LowerTorso") else a  # the torso is symmetric
    if base == "UpperTorso":
        # pec striations: fibres fanning from the sternum to the armpit (lines radiating from the insertion)
        th = np.arctan2(s - 3.32, np.radians(aa - 72.0) * 0.45)
        mask = _phiwin(aa, 38, 26) * _win(s, 2.95, 3.14, 3.40)
        out += 0.0008 * d * np.sin(th * 90.0) * mask * (0.6 + 0.4 * _noise(X, Y, 0.03, n=12, seed=7))
        # the serratus slips' fine edges and the abdominal skin folds stay out: the lobes carry them
    elif base == "UpperArm":
        # deltoid striations: fibres converging on the insertion
        th = np.arctan2(s - 3.12, np.radians(a - 80.0) * 0.30)
        mask = _win(s, 3.18, 3.40, 3.62) * (_phiwin(a, 60, 115))
        out += 0.0009 * d * np.sin(th * 80.0) * mask * (0.6 + 0.4 * _noise(X, Y, 0.03, n=12, seed=8))
        # veins: the cephalic along the outer biceps, the basilic on the inner arm (tiers 4-5)
        out += 0.0042 * vein * _vein(a, s, X, 32.0, 2.88, 3.32, 4.5, 4.0, 11)
        out += 0.0030 * vein * _vein(a, s, X, -98.0, 2.88, 3.20, 4.0, 3.0, 12)
        # the elbow's front crease
        out -= 0.0010 * (0.5 + 0.5 * m) * (0.5 + 0.5 * np.sin(Y * 2 * math.pi / 0.011)) * _win(s, 2.85, 2.885, 2.93) \
            * _phiwin(a, -12, 45)
    elif base == "LowerArm":
        # forearm veins: two meandering trunks and a cross branch (tiers 4-5), the tendons' cords at the wrist
        out += 0.0046 * vein * _vein(a, s, X, 18.0, 2.22, 2.78, 4.5, 6.0, 21)
        out += 0.0040 * vein * _vein(a, s, X, -44.0, 2.24, 2.74, 4.0, 5.0, 22)
        out += 0.0030 * vein * _vein(a, s, X, -12.0, 2.40, 2.62, 3.5, 14.0, 23)
        out += 0.0012 * (0.4 + 0.6 * d) * (_phiwin(a, -10, 5) + _phiwin(a, -32, 5)) * _win(s, 2.17, 2.26, 2.40)
        out -= 0.0010 * (0.5 + 0.5 * m) * (0.5 + 0.5 * np.sin(Y * 2 * math.pi / 0.011)) * _win(s, 2.76, 2.80, 2.84) \
            * _phiwin(a, -12, 45)
    elif base == "UpperLeg":
        # the back of the knee's creases, the quads' fibre grain above the knee
        out -= 0.0012 * (0.5 + 0.5 * np.sin(Y * 2 * math.pi / 0.012)) * _win(s, 0.99, 1.02, 1.07) * _phiwin(a, 180, 40)
        th = np.arctan2(s - 0.98, np.radians(a + 20.0) * 0.30)
        out += 0.0010 * d * np.sin(th * 34.0) * _win(s, 1.02, 1.14, 1.28) * _phiwin(a, -20, 45)
    elif base == "LowerLeg":
        out -= 0.0012 * (0.5 + 0.5 * np.sin(Y * 2 * math.pi / 0.012)) * _win(s, 0.89, 0.93, 0.97) * _phiwin(a, 180, 40)
        out += 0.0030 * vein * _vein(a, s, X, -96.0, 0.40, 0.86, 4.0, 4.0, 31)  # the great saphenous (inner calf)
        # the calf heads' fibre grain
        out += 0.0009 * d * np.sin((s * 90.0) + np.radians(a) * 3.0) * _win(s, 0.55, 0.72, 0.90) * \
            (_phiwin(a, -146, 30) + _phiwin(a, 146, 28))
    return out


# ------------------------------------------------------------------------------------------ grids
def _blur(F, sig_r, sig_c):
    """separable Gaussian over a (rings, cols[, k]) grid: clamped along the rings, wrapped round the cols; sigmas in
    grid steps"""
    def k1(sig):
        r = max(1, int(math.ceil(3 * sig)))
        x = np.arange(-r, r + 1)
        w = np.exp(-0.5 * (x / max(sig, 1e-6)) ** 2)
        return x, w / w.sum()
    x, w = k1(sig_c)
    G = sum(wi * np.roll(F, -xi, axis=1) for xi, wi in zip(x, w))
    x, w = k1(sig_r)
    R = F.shape[0]
    idx = np.arange(R)
    out = 0
    for xi, wi in zip(x, w):
        out = out + wi * G[np.clip(idx + xi, 0, R - 1)]
    return out


def _grid_normals(V):
    """outward normals of a (rings, cols, 3) grid wrapped round the cols"""
    dc = np.roll(V, -1, axis=1) - np.roll(V, 1, axis=1)
    dr = np.empty_like(V)
    dr[1:-1] = V[2:] - V[:-2]
    dr[0] = V[1] - V[0]
    dr[-1] = V[-1] - V[-2]
    n = np.cross(dc, dr)
    return n / np.maximum(np.linalg.norm(n, axis=2, keepdims=True), 1e-12)


def _bilinear(F, fi, fj, wrap):
    """sample a (R, C, ...) field at fractional indices (clamped rows; cols wrapped when wrap)"""
    R, C = F.shape[:2]
    fi = np.clip(fi, 0, R - 1)
    i0 = np.floor(fi).astype(int)
    i1 = np.minimum(i0 + 1, R - 1)
    ti = fi - i0
    if wrap:
        j0 = np.floor(fj).astype(int) % C
        j1 = (j0 + 1) % C
        tj = fj - np.floor(fj)
    else:
        fj = np.clip(fj, 0, C - 1)
        j0 = np.floor(fj).astype(int)
        j1 = np.minimum(j0 + 1, C - 1)
        tj = fj - j0
    if F.ndim == 3:
        ti, tj = ti[..., None], tj[..., None]
    return (F[i0, j0] * (1 - ti) * (1 - tj) + F[i0, j1] * (1 - ti) * tj + F[i1, j0] * ti * (1 - tj)
            + F[i1, j1] * ti * tj)


def bake_part(n, base, res):
    """the (normal, color, rough) images (uint8 arrays res x res) of a part at tier n, on the reference frame"""
    tr = B.TIERS[n]
    fr = B.frame_of(REF_FRAME)
    G, Jo = B.game_joints(tr, n, fr)
    key = B.ANCHOR[base] if base in ("UpperTorso", "LowerTorso") else "Right" + B.ANCHOR[base]
    lp = B.BUILDERS[base](tr, fr)
    B.BAKE_CAPTURE.clear()
    B.BAKE_CAPTURE["sub"] = DENSE
    try:
        B.BUILDERS[base](tr, fr)
        grids = B.BAKE_CAPTURE.get("grids") or []
    finally:
        B.BAKE_CAPTURE.clear()
    assert len(grids) == 1, (base, len(grids))
    g = grids[0]
    V, N, S_d, phd = g["V"], g["N"], g["S"], g["phis"]
    O, A, X, Z = [np.asarray(v, float) for v in g["frame"]]
    # azimuth (deg) and metric surface coordinates of every dense point, the fine detail along the normal
    C = V.mean(axis=1, keepdims=True)
    rel = V - C
    ax_ = np.einsum("rck,k->rc", rel, X)
    az_ = np.einsum("rck,k->rc", rel, Z)
    ang = np.degrees(np.arctan2(ax_, -az_))
    rad = np.sqrt(ax_ ** 2 + az_ ** 2)
    Xm = np.radians(ang) * rad.mean(axis=1, keepdims=True)
    Ym = np.repeat(S_d[:, None], V.shape[1], axis=1)
    disp = detail(base, ang, Ym, Xm, Ym, n)
    Vh = V + N * disp[..., None]
    # into game space (the exported mesh's mapping), the high normals there
    Sx = B.game_scale(base) * np.array(B.part_extra(fr, base), float)
    Vg = G[key] + (Vh - Jo[key]) * Sx
    Nh = _grid_normals(Vg)
    ref = N / Sx
    if np.mean(np.sum(Nh * ref, axis=2)) < 0:
        Nh = -Nh
    # AO / cavity: the surface against its blurred neighbourhood (in grid steps from the mean spacing, studs)
    sc = np.mean(np.linalg.norm(np.roll(Vg, -1, axis=1) - Vg, axis=2))
    sr = np.mean(np.linalg.norm(Vg[1:] - Vg[:-1], axis=2))
    h_c = np.sum((Vg - _blur(Vg, 0.010 / sr, 0.010 / sc)) * Nh, axis=2)
    h_a = np.sum((Vg - _blur(Vg, 0.045 / sr, 0.045 / sc)) * Nh, axis=2)
    # the low mesh in game space, its tangent frames
    lg = B.to_game(lp, base, key, Jo, G, fr)
    RL, nL, S_l, s_lo, s_hi = lp["grid"]
    S_l = np.asarray(S_l)
    tg, sg = B.vertex_tangents(lg["P"], lg["N"], lg["U"], lg["T"])
    Pl = np.asarray(lg["P"])[: RL * nL].reshape(RL, nL, 3)
    Nl = np.asarray(lg["N"])[: RL * nL].reshape(RL, nL, 3)
    Tl = tg[: RL * nL].reshape(RL, nL, 3)
    Wl = sg[: RL * nL].reshape(RL, nL)
    Ul = np.asarray(lg["U"])[: RL * nL].reshape(RL, nL, 2)
    uu = Ul[0, :, 0]
    vv = Ul[:, 0, 1]
    # texels -> (phi, s)
    yy, xx = np.mgrid[0:res, 0:res]
    u = (xx + 0.5) / res
    v = (yy + 0.5) / res
    o = np.argsort(vv)
    s = np.interp(v, vv[o], S_l[o])
    phi = 2 * math.pi * u - math.pi
    # dense samples
    fi_d = np.interp(s, S_d, np.arange(len(S_d)))
    # (explicit wrap: one more knot at phd[0] + 2 pi -> column C, which _bilinear wraps to 0)
    ph = np.asarray(phd)
    xp = np.concatenate([ph, [ph[0] + 2 * math.pi]])
    phi_m = np.where(phi < ph[0], phi + 2 * math.pi, phi)
    fj_d = np.interp(phi_m, xp, np.arange(len(xp), dtype=float))
    nh = _bilinear(Nh, fi_d, fj_d, True)
    hc = _bilinear(h_c, fi_d, fj_d, True)
    ha = _bilinear(h_a, fi_d, fj_d, True)
    # low frames (the grid carries the seam column: no wrap)
    fi_l = np.interp(s, S_l, np.arange(RL))
    fj_l = np.interp(u, uu, np.arange(nL))
    nl = _bilinear(Nl, fi_l, fj_l, False)
    tl = _bilinear(Tl, fi_l, fj_l, False)
    wl = np.sign(_bilinear(Wl, fi_l, fj_l, False) + 1e-9)
    nl = nl / np.maximum(np.linalg.norm(nl, axis=2, keepdims=True), 1e-12)
    tl = tl - nl * np.sum(tl * nl, axis=2, keepdims=True)
    tl = tl / np.maximum(np.linalg.norm(tl, axis=2, keepdims=True), 1e-12)
    bl = np.cross(nl, tl) * wl[..., None]
    nh = nh / np.maximum(np.linalg.norm(nh, axis=2, keepdims=True), 1e-12)
    ts = np.stack([np.sum(nh * tl, axis=2), np.sum(nh * bl, axis=2), np.sum(nh * nl, axis=2)], axis=2)
    ts[..., 2] = np.maximum(ts[..., 2], 0.05)
    ts = ts / np.linalg.norm(ts, axis=2, keepdims=True)
    normal = np.clip(np.round((ts * 0.5 + 0.5) * 255), 0, 255).astype(np.uint8)
    # occlusion: cavity (fine) and AO (broad), in game studs below the neighbourhood
    dark = 0.55 * np.clip(-hc / 0.005, 0, 1) + 0.45 * np.clip(-ha / 0.016, 0, 1)
    color = np.clip(1.0 - 0.32 * dark, 0, 1)
    rough = np.clip(0.60 - 0.10 * np.clip(ha / 0.010, 0, 1) + 0.18 * dark, 0.35, 0.90)
    c8 = np.clip(np.round(color * 255), 0, 255).astype(np.uint8)
    r8 = np.clip(np.round(rough * 255), 0, 255).astype(np.uint8)
    stats = {"normalDev": float(np.degrees(np.arccos(np.clip(ts[..., 2], -1, 1))).mean()),
             "colorMin": float(color.min()), "roughMean": float(rough.mean())}
    return normal, c8, r8, stats


def bake_all(tiers, parts):
    from PIL import Image
    rec = {"version": 1, "parts": {}, "tiers": {}, "shift": SURFACE_SHIFT, "refFrame": REF_FRAME, "dense": DENSE}
    for n in tiers:
        d = os.path.join(OUT, "T%d" % n)
        os.makedirs(d, exist_ok=True)
        rec["tiers"][str(n)] = {}
        for base in parts:
            res = SURF_PARTS[base]
            nm, cm, rm, st = bake_part(n, base, res)
            files = {}
            for kind, arr, mode in (("normal", nm, "RGB"), ("color", cm, "L"), ("rough", rm, "L")):
                fn = os.path.join(d, "%s_%s.png" % (base, kind))
                im = Image.fromarray(arr, mode)
                if kind == "color":
                    im = im.convert("RGB")
                im.save(fn, optimize=True)
                files[kind] = os.path.relpath(fn, HERE)
            rec["tiers"][str(n)][base] = {"files": files, "size": res, "stats": st}
            rec["parts"][base] = res
            print("T%d %-10s %4d px  normal dev %.1f deg  color min %.2f  rough %.2f" % (
                n, base, res, st["normalDev"], st["colorMin"], st["roughMean"]), flush=True)
    path = os.path.join(OUT, "skin.json")
    old = json.load(open(path)) if os.path.exists(path) else {}
    for k, v in rec["tiers"].items():
        old.setdefault("tiers", {})[k] = {**old.get("tiers", {}).get(k, {}), **v}
    old.update({k: rec[k] for k in ("version", "shift", "refFrame", "dense")})
    old.setdefault("parts", {}).update(rec["parts"])
    json.dump(old, open(path, "w"), indent=1)
    return old


# ------------------------------------------------------------------------------------------ previews
def skin_material(bpy, st, n, base, cache):
    """a Cycles material as Roblox draws a SurfaceAppearance: base color = skin x ColorMap (the tint multiplies),
    the RoughnessMap, the tangent-space NormalMap (Blender's normal map node: OpenGL, green up, MikkTSpace tangents
    from the UVs)"""
    key = (n, base)
    if key in cache:
        return cache[key]
    d = os.path.join(OUT, "T%d" % n)
    m = bpy.data.materials.new("skin_T%d_%s" % (n, base))
    m.use_nodes = True
    nt = m.node_tree
    bs = nt.nodes["Principled BSDF"]
    def img(kind, non_color):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(os.path.join(d, "%s_%s.png" % (base, kind)))
        if non_color:
            t.image.colorspace_settings.name = "Non-Color"
        return t
    col, nor, rou = img("color", False), img("normal", True), img("rough", True)
    mix = nt.nodes.new("ShaderNodeMixRGB")
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1.0
    mix.inputs[1].default_value = tuple(B.SKIN) + (1.0,)
    nt.links.new(col.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], bs.inputs["Base Color"])
    nt.links.new(rou.outputs[0], bs.inputs["Roughness"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.space = "TANGENT"
    nm.uv_map = "UVMap"
    nt.links.new(nor.outputs[0], nm.inputs["Color"])
    nt.links.new(nm.outputs[0], bs.inputs["Normal"])
    cache[key] = m
    return m


def plain_material(bpy, rough=0.6):
    m = bpy.data.materials.new("skin_plain")
    m.use_nodes = True
    bs = m.node_tree.nodes["Principled BSDF"]
    bs.inputs["Base Color"].default_value = tuple(B.SKIN) + (1.0,)
    bs.inputs["Roughness"].default_value = rough
    return m


def render_previews(bpy, frames, tiers, samples, dest, tag):
    """close-up strips (chest, back, arm side / back, legs) and a lineup per tier, with the maps ("after") or plain
    skin ("before"), into dest"""
    os.makedirs(dest, exist_ok=True)
    built = {(f, n): B.build_tier(bpy, n, frame=f) for f in frames for n in tiers}
    outs = []
    for n in tiers:
        for name, title, views, sp in B.MUSCLE_SHEETS:
            for view, yaw, only, cy, hgt in views:
                W = 1800
                width = len(frames) * sp
                st = B.Stage(bpy, (W, int(round(W * hgt / width))), samples)
                cache = {}
                plain = plain_material(bpy)
                labels = []
                for i, f in enumerate(frames):
                    parts = built[(f, n)]
                    place = B.M4(B.roty(yaw), (-(i - (len(frames) - 1) / 2) * sp, 0, 0))
                    _, Sm = B.height_norm(parts)
                    pm = B.pose_mats(parts["_J"], sh=8.0, el=7.0)
                    for pn in only:
                        base = pn.replace("Right", "").replace("Left", "")
                        mat = skin_material(bpy, st, surface_tier(f, n), base, cache) \
                            if (tag == "after" and base in SURF_PARTS) else plain
                        st.add("R%s_%d_%s" % (view, i, pn), parts[pn], place @ Sm @ pm[pn], mat)
                    labels.append("%s T%d %s (%s)" % (f.split(" ")[0], n, view, "maps" if tag == "after" else "no maps"))
                q = st.shoot(os.path.join(dest, "%s_%s_t%d_%s.png" % (name, view, n, tag)), 0, cy, width, elev=4)
                B.label(q, labels, strip=34)
                outs.append(q)
    return outs


def render_lineups(bpy, tiers, samples, dest, tag):
    """the five frames, whole and bare, front and back at each tier, at game distance (a lineup like the in-game
    sheets), with the maps ("after") or plain skin ("before")"""
    os.makedirs(dest, exist_ok=True)
    outs = []
    frames = list(B.FRAME_ORDER)
    for n in tiers:
        built = {f: B.build_tier(bpy, n, frame=f) for f in frames}
        for view, yaw in (("front", 0.0), ("back", 180.0)):
            st = B.Stage(bpy, (2200, 820), samples)
            st.floor()
            cache = {}
            plain = plain_material(bpy)
            sp = 4.0
            labels = []
            for i, f in enumerate(frames):
                parts = built[f]
                x = -(i - (len(frames) - 1) / 2) * sp
                if yaw:
                    x = -x
                place = B.M4(B.roty(yaw), (x, 0, 0))
                hs, Sm = B.height_norm(parts)
                pm = B.pose_mats(parts["_J"])
                for pn, lp in parts.items():
                    if pn.startswith("_"):
                        continue
                    base = pn.replace("Right", "").replace("Left", "")
                    mat = skin_material(bpy, st, surface_tier(f, n), base, cache) \
                        if (tag == "after" and base in SURF_PARTS) else plain
                    st.add("L%d_%s" % (i, pn), lp, place @ Sm @ pm[pn], mat)
                neck = np.array(parts["_J"]["Neck"]) * np.array([1.0, hs, 1.0])
                hd = B.head_size(parts.get("_frame"))
                st.add("L%d_Head" % i, None, place, st.headmat("determined"),
                       D=B.head_mesh(neck + np.array([0, hd / 2, 0]), hd))
                labels.append("%s T%d" % (f, n))
            if yaw:
                labels = labels[::-1]
            q = st.shoot(os.path.join(dest, "lineup_t%d_%s_%s.png" % (n, view, tag)), 0, 3.25, len(frames) * sp + 0.4)
            B.label(q, labels, "Bare bodies, tier %d, %s, %s" % (n, view, "with the skin maps" if tag == "after" else
                                                                     "no maps (the current build)"))
            outs.append(q)
    return outs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tiers", default="1,2,3,4,5")
    ap.add_argument("--parts", default=",".join(SURF_PARTS))
    ap.add_argument("--no-bake", action="store_true")
    ap.add_argument("--preview", default="", help="frames (keys) for the close-up previews, e.g. lean,muscular,power")
    ap.add_argument("--preview-tiers", default="5")
    ap.add_argument("--samples", type=int, default=16)
    ap.add_argument("--dest", default=os.path.join(B.SCRATCH, "realism"))
    ap.add_argument("--lineups", default="", help="tiers for the whole-body lineups, e.g. 1,3,5")
    a = ap.parse_args()
    if not a.no_bake:
        bake_all([int(x) for x in a.tiers.split(",")], a.parts.split(","))
    if a.preview:
        import bpy
        frames = [B.frame_of(k)["id"] for k in a.preview.split(",")]
        pt = [int(x) for x in a.preview_tiers.split(",")]
        for tag in ("before", "after"):
            for p in render_previews(bpy, frames, pt, a.samples, a.dest, tag):
                print("sheet", p)
    if a.lineups:
        import bpy
        for tag in ("before", "after"):
            for p in render_lineups(bpy, [int(x) for x in a.lineups.split(",")], a.samples, a.dest, tag):
                print("sheet", p)


if __name__ == "__main__":
    main()
