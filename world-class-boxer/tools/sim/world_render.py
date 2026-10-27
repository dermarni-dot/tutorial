"""Cycles renders of the WORLD dumped by tools/sim/world_scene.luau (studs, Roblox axes: +Y up).

    /opt/bpyenv/bin/python tools/sim/world_render.py SCENE.json OUT_DIR [--only view,view] [--samples N]
                                                     [--res 1280x720] [--tag before]

Views are listed in VIEWS below (gym, venues by tier, city day / night, menu stage); each one names the roots of
the scene it draws, a camera (eye, target, fov) and a light mode. Geometry is exactly what the scene file says:
Parts by Shape (Block, Ball, Cylinder along X, Wedge) and SpecialMesh (Sphere, Cylinder along Y, Brick, Head),
merged into one mesh per material class with the part colours as vertex colours; SurfaceGuis rasterised with
PIL (frames, gradients, text) onto a quad on their face (glowing when LightInfluence < 1); Point / Spot / Surface
lights as Blender lights; Neon parts emit. Night mode turns on the NightLight-tagged lights and lenses.
Approximate by design: no Roblox textures for materials (a little procedural grain instead), no Beams/particles.
"""
import json
import math
import os
import sys
import hashlib

import numpy as np
import bpy
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))

ROOT = os.path.dirname(os.path.dirname(HERE))


def asset_files():
    """rbxassetid number -> local image file (the uploads' caches: tools/world, tools/ui)"""
    out = {}
    for cache in ("tools/world/uploaded.json", "tools/ui/uploaded.json"):
        p = os.path.join(ROOT, cache)
        if os.path.exists(p):
            for e in json.load(open(p)).values():
                if e.get("id") and e.get("file"):
                    out[str(e["id"])] = os.path.join(ROOT, e["file"])
    return out


ASSETS = asset_files()
_img_cache = {}


def asset_image(tex):
    """'rbxassetid://N' -> PIL RGBA image or None"""
    if not tex:
        return None
    n = tex.split("//")[-1]
    path = ASSETS.get(n)
    if not path or not os.path.exists(path):
        return None
    if path not in _img_cache:
        _img_cache[path] = Image.open(path).convert("RGBA")
    return _img_cache[path]


FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_COND = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
FONT_SERIF = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
# the game's own families (Shared.Typography), the real TTFs (tools/ui/fonts, OFL): Bangers for the signs,
# Montserrat for their second lines, Oswald for numbers; (family, named instance of a variable font)
FONT_DIR = os.path.join(ROOT, "tools", "ui", "fonts")
FAMILY_TTF = {
    "Bangers": (os.path.join(FONT_DIR, "Bangers-Regular.ttf"), None),
    "Montserrat": (os.path.join(FONT_DIR, "Montserrat[wght].ttf"), "Bold"),
    "Oswald": (os.path.join(FONT_DIR, "Oswald[wght].ttf"), "Bold"),
}


def srgb2lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_b(v):
    """Roblox (x, y, z) -> Blender (x, -z, y)."""
    v = np.asarray(v, dtype=np.float64)
    return np.stack([v[..., 0], -v[..., 2], v[..., 1]], axis=-1)


# ----------------------------------------------------------------------------------------------- primitives
def box(h):
    hx, hy, hz = h
    P = np.array([[-hx, -hy, -hz], [hx, -hy, -hz], [hx, hy, -hz], [-hx, hy, -hz],
                  [-hx, -hy, hz], [hx, -hy, hz], [hx, hy, hz], [-hx, hy, hz]])
    F = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (2, 3, 7, 6), (1, 2, 6, 5), (0, 4, 7, 3)]
    return P, F


def ellipsoid(r, nu=16, nv=10):
    P, F = [], []
    for j in range(nv + 1):
        th = math.pi * j / nv
        for i in range(nu):
            ph = 2 * math.pi * i / nu
            P.append((r[0] * math.sin(th) * math.cos(ph), r[1] * math.cos(th), r[2] * math.sin(th) * math.sin(ph)))
    for j in range(nv):
        for i in range(nu):
            a, b = j * nu + i, j * nu + (i + 1) % nu
            F.append((a, b, b + nu, a + nu))
    return np.array(P), F


def cyl(length, ra, rb, axis, n=16):
    """cylinder along axis 0 (X) or 1 (Y); ra, rb = radii on the other two axes"""
    P, F = [], []
    for s in (-1, 1):
        for i in range(n):
            a = 2 * math.pi * i / n
            u, w = ra * math.cos(a), rb * math.sin(a)
            if axis == 0:
                P.append((s * length / 2, u, w))
            else:
                P.append((u, s * length / 2, w))
    for i in range(n):
        j = (i + 1) % n
        F.append((i, j, n + j, n + i))
    F.append(tuple(range(n - 1, -1, -1)))
    F.append(tuple(range(n, 2 * n)))
    return np.array(P), F


def wedge(h):
    hx, hy, hz = h
    P = np.array([[-hx, -hy, -hz], [hx, -hy, -hz], [hx, -hy, hz], [-hx, -hy, hz], [-hx, hy, hz], [hx, hy, hz]])
    F = [(0, 1, 2, 3), (3, 2, 5, 4), (0, 4, 5, 1), (0, 3, 4), (1, 5, 2)]
    return P, F


def part_geom(p):
    s = np.array(p["s"], dtype=np.float64)
    sh = p.get("sh", "Block")
    mesh = p.get("mesh")
    off = np.zeros(3)
    big = max(s)
    seg = 24 if big > 6 else (16 if big > 1.5 else 10)
    if mesh:
        k = mesh["k"]
        sc = np.array(mesh["s"], dtype=np.float64)
        off = np.array(mesh["o"], dtype=np.float64)
        if k == "Sphere":
            P, F = ellipsoid(s * sc / 2, seg, max(6, seg // 2))
        elif k == "Cylinder":
            d = s * sc
            P, F = cyl(d[1], d[0] / 2, d[2] / 2, 1, seg)
        elif k == "Head":
            d = s * sc
            P, F = cyl(d[1], d[0] / 2, d[2] / 2, 1, seg)
        elif k == "Wedge":
            P, F = wedge(s * sc / 2)
        else:
            P, F = box(s * sc / 2)
    elif sh == "Ball":
        r = min(s) / 2
        P, F = ellipsoid((r, r, r), seg, max(6, seg // 2))
    elif sh == "Cylinder":
        P, F = cyl(s[0], min(s[1], s[2]) / 2, min(s[1], s[2]) / 2, 0, seg)
    elif sh == "Wedge":
        P, F = wedge(s / 2)
    else:
        P, F = box(s / 2)
    cf = p["cf"]
    pos = np.array(cf[:3])
    R = np.array(cf[3:]).reshape(3, 3)
    W = (P + off) @ R.T + pos
    return W, F


# ----------------------------------------------------------------------------------------------- materials
MAT_CLASS = {
    "Neon": "neon", "Glass": "glass", "Metal": "metal", "DiamondPlate": "metal", "Foil": "metal", "CorrodedMetal": "metal",
    "SmoothPlastic": "smooth", "Plastic": "plastic", "Marble": "smooth", "Ice": "glass", "Glacier": "glass",
    "Brick": "brick", "Fabric": "rough", "Grass": "rough", "Concrete": "rough", "Rubber": "rough", "Ground": "rough",
    "Sand": "rough", "Snow": "rough", "Asphalt": "rough", "Pavement": "rough", "Slate": "rough", "Granite": "rough",
    "Limestone": "rough", "Cobblestone": "rough", "Leather": "plastic", "Wood": "wood", "WoodPlanks": "wood",
    "ForceField": "skip",
}


# Roblox adds Lighting.Ambient as a flat fill on every surface the sky cannot see (Future lighting; the
# venues' profiles set it on fight nights). Cycles only gets it through windows and bounces, so a closed
# hall rendered far darker than the game shows it: apply_lighting sets this per view (linear RGB, x the
# surface colour as emission) so the previews follow the real Ambient value.
AMBIENT_FILL = (0.0, 0.0, 0.0)
AMBIENT_K = 0.55


def make_material(name, kind, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    col = attr.outputs["Color"]
    rough = {"neon": 0.5, "glass": 0.05, "metal": 0.32, "smooth": 0.32, "plastic": 0.5, "brick": 0.85, "rough": 0.9,
             "wood": 0.6}[kind]
    bsdf.inputs["Roughness"].default_value = rough
    if kind in ("rough", "brick", "wood"):
        # a little grain: noise darkens / lightens the vertex colour
        tc = nt.nodes.new("ShaderNodeTexCoord")
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = {"rough": 0.9, "brick": 1.0, "wood": 2.0}[kind]
        noise.inputs["Detail"].default_value = 6
        nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 0.35
        nt.links.new(col, mix.inputs[6])
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].color = (0.75, 0.75, 0.75, 1)
        ramp.color_ramp.elements[1].color = (1.25, 1.25, 1.25, 1)
        nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], mix.inputs[7])
        col = mix.outputs[2]
        if kind == "brick":
            bt = nt.nodes.new("ShaderNodeTexBrick")
            bt.inputs["Scale"].default_value = 1.2
            bt.inputs["Mortar Size"].default_value = 0.03
            bt.inputs["Color1"].default_value = (1, 1, 1, 1)
            bt.inputs["Color2"].default_value = (0.82, 0.82, 0.82, 1)
            bt.inputs["Mortar"].default_value = (0.55, 0.55, 0.55, 1)
            nt.links.new(tc.outputs["Object"], bt.inputs["Vector"])
            mix2 = nt.nodes.new("ShaderNodeMix")
            mix2.data_type = "RGBA"
            mix2.blend_type = "MULTIPLY"
            mix2.inputs["Factor"].default_value = 1.0
            nt.links.new(col, mix2.inputs[6])
            nt.links.new(bt.outputs["Color"], mix2.inputs[7])
            col = mix2.outputs[2]
    nt.links.new(col, bsdf.inputs["Base Color"])
    if kind == "metal":
        bsdf.inputs["Metallic"].default_value = 0.75
    if kind == "neon":
        bsdf.inputs["Emission Strength"].default_value = 4.0
        nt.links.new(attr.outputs["Color"], bsdf.inputs["Emission Color"])
    elif max(AMBIENT_FILL) > 1e-4 and kind != "glass":
        amb = nt.nodes.new("ShaderNodeMix")
        amb.data_type = "RGBA"
        amb.blend_type = "MULTIPLY"
        amb.inputs["Factor"].default_value = 1.0
        nt.links.new(col, amb.inputs[6])
        amb.inputs[7].default_value = (*AMBIENT_FILL, 1.0)
        nt.links.new(amb.outputs[2], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = AMBIENT_K
    shader = bsdf.outputs["BSDF"]
    if kind == "glass" or alpha < 0.999:
        a = alpha if kind != "glass" else min(alpha, 0.35)
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        mixs = nt.nodes.new("ShaderNodeMixShader")
        mixs.inputs["Fac"].default_value = a
        nt.links.new(tr.outputs["BSDF"], mixs.inputs[1])
        nt.links.new(shader, mixs.inputs[2])
        shader = mixs.outputs["Shader"]
    nt.links.new(shader, out.inputs["Surface"])
    return m


# ----------------------------------------------------------------------------------------------- GUIs
FACE_AXES = {
    # face: (normal, u (gui x, left -> right), v (gui y, top -> bottom)) in part space
    "Front": ((0, 0, -1), (-1, 0, 0), (0, -1, 0)),
    "Back": ((0, 0, 1), (1, 0, 0), (0, -1, 0)),
    "Right": ((1, 0, 0), (0, 0, -1), (0, -1, 0)),
    "Left": ((-1, 0, 0), (0, 0, 1), (0, -1, 0)),
    "Top": ((0, 1, 0), (1, 0, 0), (0, 0, 1)),
    "Bottom": ((0, -1, 0), (1, 0, 0), (0, 0, -1)),
}


def face_dims(size, face):
    n, u, v = (np.array(a) for a in FACE_AXES[face])
    s = np.array(size)
    return abs(u) @ s, abs(v) @ s, abs(n) @ s


_font_cache = {}


def font(path, px, var=None):
    key = (path, px, var)
    if key not in _font_cache:
        f = ImageFont.truetype(path, max(6, int(px)))
        if var:
            try:
                f.set_variation_by_name(var)
            except Exception:
                pass
        _font_cache[key] = f
    return _font_cache[key]


def face_for(it):
    """(ttf path, variation) of a SurfaceGui text item: its FontFace family (it.font + it.wt), else the enum"""
    fam = it.get("font")
    if fam in FAMILY_TTF and os.path.exists(FAMILY_TTF[fam][0]):
        path, var = FAMILY_TTF[fam]
        wt = it.get("wt")
        if var and wt in ("Thin", "ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold", "Black"):
            var = wt
        return path, var
    if fam in ("Garamond", "Antique", "Bodoni"):
        return FONT_SERIF, None
    if fam in ("Oswald", "Bangers", "Michroma", "GothamBlack", "FredokaOne"):
        return FONT_COND, None
    return FONT_BOLD, None


def c255(c, a=255):
    return (int(max(0, min(1, c[0])) * 255), int(max(0, min(1, c[1])) * 255), int(max(0, min(1, c[2])) * 255), a)


def draw_gui(g, W, Hh):
    img = Image.new("RGBA", (W, Hh), (0, 0, 0, 0))
    for it in g["items"]:
        x0, y0 = it["x"] * W, it["y"] * Hh
        x1, y1 = x0 + it["w"] * W, y0 + it["h"] * Hh
        if x1 <= x0 or y1 <= y0:
            continue
        layer = Image.new("RGBA", (W, Hh), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        bt = it.get("bt", 0)
        if bt < 0.99:
            a = int((1 - bt) * 255)
            if it.get("grad"):
                kps = it["grad"]
                rot = it.get("grot", 0) % 360
                vertical = 45 < rot < 135 or 225 < rot < 315
                n = int((y1 - y0) if vertical else (x1 - x0)) + 1
                for i in range(max(1, n)):
                    t = i / max(1, n - 1)
                    if 90 <= rot < 270:
                        t = 1 - t
                    c = kps[-1][1]
                    for k in range(len(kps) - 1):
                        if kps[k][0] <= t <= kps[k + 1][0]:
                            f = (t - kps[k][0]) / max(1e-6, kps[k + 1][0] - kps[k][0])
                            c = [kps[k][1][j] * (1 - f) + kps[k + 1][1][j] * f for j in range(3)]
                            break
                    base = it["bg"]
                    cc = [c[j] * base[j] for j in range(3)]
                    if vertical:
                        d.line([(x0, y0 + i), (x1, y0 + i)], fill=c255(cc, a))
                    else:
                        d.line([(x0 + i, y0), (x0 + i, y1)], fill=c255(cc, a))
            else:
                d.rectangle([x0, y0, x1, y1], fill=c255(it["bg"], a))
        if it.get("img") and it.get("it", 0) < 0.99:
            src = asset_image(it["img"])
            if src is not None:
                if it.get("rect"):
                    ox, oy, rw, rh = it["rect"]
                    src = src.crop((ox, oy, ox + rw, oy + rh))
                bw, bh = int(x1 - x0), int(y1 - y0)
                if bw > 1 and bh > 1:
                    # ScaleType Fit: keep the aspect
                    sc = min(bw / src.width, bh / src.height)
                    iw, ih = max(1, int(src.width * sc)), max(1, int(src.height * sc))
                    im2 = src.resize((iw, ih), Image.LANCZOS)
                    tint = it.get("ic") or (1, 1, 1)
                    if tint != [1, 1, 1] and tint != (1, 1, 1):
                        arr = np.array(im2).astype(np.float64)
                        arr[..., :3] *= np.array(tint)[None, None, :]
                        im2 = Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGBA")
                    layer.alpha_composite(im2, (int(x0 + (bw - iw) / 2), int(y0 + (bh - ih) / 2)))
        txt = it.get("text")
        if txt and it.get("tt", 0) < 0.99:
            lines = txt.replace("<br/>", "\n").split("\n")
            fpath, fvar = face_for(it)
            bw, bh = x1 - x0, y1 - y0
            if it.get("ts", 0) and it["ts"] > 0:
                px = it["ts"] * Hh
            else:
                px = bh / max(1, len(lines)) * 0.8
            # shrink to fit the width
            for _ in range(12):
                f = font(fpath, px, fvar)
                wmax = max(d.textlength(ln, font=f) for ln in lines) if lines else 0
                if wmax <= bw * 0.96 or px < 7:
                    break
                px *= 0.85
            f = font(fpath, px, fvar)
            lh = px * 1.1
            ty = y0 + (bh - lh * len(lines)) / 2
            for ln in lines:
                tw = d.textlength(ln, font=f)
                d.text((x0 + (bw - tw) / 2, ty), ln, font=f, fill=c255(it["tc"], int((1 - it.get("tt", 0)) * 255)))
                ty += lh
        img = Image.alpha_composite(img, layer)
    return img


# ----------------------------------------------------------------------------------------------- scene build
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


class Builder:
    def __init__(self, tmpdir):
        self.tmp = tmpdir
        self.mats = {}
        self.buckets = {}
        self.gui_count = 0

    def mat(self, kind, alpha):
        key = (kind, round(alpha, 1))
        if key not in self.mats:
            self.mats[key] = make_material("m_%s_%d" % (kind, int(alpha * 10)), kind, alpha)
        return key

    def add_part(self, p, night):
        t = p.get("t", 0)
        if t >= 0.97:
            return
        m = p.get("m", "Plastic")
        col = p["col"]
        tags = p.get("tg") or []
        if "NightLens" in tags:
            if night:
                m, col = "Neon", (1.0, 0.925, 0.784)
            else:
                m, col = "SmoothPlastic", (0.784, 0.784, 0.77)
        kind = MAT_CLASS.get(m, "plastic")
        if kind == "skip":
            return
        key = self.mat(kind, 1 - t)
        W, F = part_geom(p)
        b = self.buckets.setdefault(key, {"P": [], "F": [], "C": [], "n": 0})
        base = b["n"]
        b["P"].append(W)
        lin = list(srgb2lin(col)) + [1.0]
        for f in F:
            b["F"].append(tuple(i + base for i in f))
            b["C"].append(lin)
        b["n"] += len(W)

    def add_beam(self, bm):
        if bm.get("t", 0) > 0.6:
            return
        a, b = np.array(bm["a"]), np.array(bm["b"])
        d = b - a
        L = np.linalg.norm(d)
        if L < 0.01:
            return
        w = max(0.05, bm.get("w", 0.2))
        x = d / L
        up = np.array((0, 1.0, 0)) if abs(x[1]) < 0.9 else np.array((1.0, 0, 0))
        z = np.cross(x, up)
        z /= np.linalg.norm(z)
        y = np.cross(z, x)
        R = np.column_stack([x, y, z])
        cf = list((a + b) / 2) + list(R.ravel())
        kind = "neon" if bm.get("glow", 0) > 0.5 else "smooth"
        self.add_part({"s": [L, w, w], "cf": cf, "col": bm.get("col", (1, 1, 1)), "m": "Neon" if kind == "neon" else "SmoothPlastic",
                       "t": bm.get("t", 0), "sh": "Cylinder"}, False)

    def add_decal(self, dc, part):
        face = dc.get("face", "Front")
        if face not in FACE_AXES:
            return
        src = asset_image(dc.get("tex"))
        if src is None:
            return
        fw, fh, depth = face_dims(part["s"], face)
        if fw <= 0.01 or fh <= 0.01:
            return
        tiled = dc.get("k") == "Texture"
        key = hashlib.md5((dc.get("tex", "") + str(dc.get("col")) + str(dc.get("t"))).encode()).hexdigest()[:12]
        path = os.path.join(self.tmp, "dc_" + key + ".png")
        if not os.path.exists(path):
            im = src.copy()
            arr = np.array(im).astype(np.float64)
            col = dc.get("col") or (1, 1, 1)
            arr[..., :3] *= np.array(col)[None, None, :]
            arr[..., 3] *= (1 - dc.get("t", 0))
            Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGBA").save(path)
        n, u, v = (np.array(a, dtype=np.float64) for a in FACE_AXES[face])
        R = np.array(part["cf"][3:]).reshape(3, 3)
        pos = np.array(part["cf"][:3])
        c = n * (depth / 2 + 0.015)
        corners = [c - u * fw / 2 - v * fh / 2, c + u * fw / 2 - v * fh / 2, c + u * fw / 2 + v * fh / 2, c - u * fw / 2 + v * fh / 2]
        Wc = to_b(np.array(corners) @ R.T + pos)
        me = bpy.data.meshes.new("decal")
        me.from_pydata(Wc.tolist(), [], [(0, 1, 2, 3)])
        uvl = me.uv_layers.new()
        if tiled:
            su, sv = dc.get("su") or 8, dc.get("sv") or 8
            uvs = [(0, fh / sv), (fw / su, fh / sv), (fw / su, 0), (0, 0)]
        else:
            uvs = [(0, 1), (1, 1), (1, 0), (0, 0)]
        for li, uv in enumerate(uvs):
            uvl.data[li].uv = uv
        mk = ("decal", path)
        m = self.mats.get(mk)
        if m is None:
            m = bpy.data.materials.new("dc_" + key)
            m.use_nodes = True
            nt = m.node_tree
            bsdf = nt.nodes["Principled BSDF"]
            tex = nt.nodes.new("ShaderNodeTexImage")
            tex.image = bpy.data.images.load(path)
            tex.extension = "REPEAT" if tiled else "CLIP"
            nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
            nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
            bsdf.inputs["Roughness"].default_value = 0.8
            self.mats[mk] = m
        me.materials.append(m)
        ob = bpy.data.objects.new("decal", me)
        bpy.context.scene.collection.objects.link(ob)
        self.gui_count += 1

    def flush(self):
        for key, b in self.buckets.items():
            if not b["P"]:
                continue
            P = to_b(np.concatenate(b["P"]))
            me = bpy.data.meshes.new("mesh_%s" % (key[0]))
            me.from_pydata(P.tolist(), [], b["F"])
            me.update()
            ca = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
            # per face colour -> corners
            cols = np.repeat(np.array(b["C"]), [len(f) for f in b["F"]], axis=0)
            ca.data.foreach_set("color", cols.astype(np.float32).ravel())
            me.materials.append(self.mats[key])
            ob = bpy.data.objects.new("obj_%s_%s" % key, me)
            bpy.context.scene.collection.objects.link(ob)
            for poly in me.polygons:
                poly.use_smooth = False
        self.buckets = {}

    def add_gui(self, g, part):
        face = g["face"]
        if face not in FACE_AXES:
            return
        fw, fh, depth = face_dims(part["s"], face)
        if fw <= 0.01 or fh <= 0.01 or not g["items"]:
            return
        ppu = 48
        W = int(min(1024, max(16, fw * ppu)))
        Hh = int(min(1024, max(16, fh * ppu)))
        key = hashlib.md5(json.dumps(g["items"], sort_keys=True).encode() + str((W, Hh)).encode()).hexdigest()[:16]
        path = os.path.join(self.tmp, key + ".png")
        if not os.path.exists(path):
            img = draw_gui(g, W, Hh)
            if img.getbbox() is None:
                return
            img.save(path)
        n, u, v = (np.array(a, dtype=np.float64) for a in FACE_AXES[face])
        R = np.array(part["cf"][3:]).reshape(3, 3)
        pos = np.array(part["cf"][:3])
        c = n * (depth / 2 + 0.02)
        corners = [c - u * fw / 2 - v * fh / 2, c + u * fw / 2 - v * fh / 2, c + u * fw / 2 + v * fh / 2, c - u * fw / 2 + v * fh / 2]
        Wc = to_b(np.array(corners) @ R.T + pos)
        me = bpy.data.meshes.new("gui")
        me.from_pydata(Wc.tolist(), [], [(0, 1, 2, 3)])
        uvl = me.uv_layers.new()
        for li, uv in zip(range(4), [(0, 1), (1, 1), (1, 0), (0, 0)]):
            uvl.data[li].uv = uv
        glow = max(0.0, 1.0 - g.get("light", 1)) * g.get("bright", 1)
        mk = (path, round(glow, 1))
        m = self.mats.get(mk)
        if m is None:
            m = bpy.data.materials.new("gui_" + key)
            m.use_nodes = True
            nt = m.node_tree
            bsdf = nt.nodes["Principled BSDF"]
            tex = nt.nodes.new("ShaderNodeTexImage")
            tex.image = bpy.data.images.load(path)
            tex.interpolation = "Linear"
            nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
            nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
            bsdf.inputs["Roughness"].default_value = 0.6
            if glow > 0.05:
                nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
                bsdf.inputs["Emission Strength"].default_value = 1.5 * glow
            self.mats[mk] = m
        me.materials.append(m)
        ob = bpy.data.objects.new("gui", me)
        bpy.context.scene.collection.objects.link(ob)
        self.gui_count += 1


def add_light(L, part, night, power_k):
    if not L.get("on", True):
        tags = L.get("tg") or []
        if not (night and "NightLight" in tags):
            return
    col = srgb2lin(L["col"])
    b = L["b"]
    r = L["r"]
    if b <= 0 or r <= 0:
        return
    R = np.array(part["cf"][3:]).reshape(3, 3)
    pos = np.array(part["cf"][:3])
    face = L.get("face", "Front")
    n = np.array(FACE_AXES.get(face, FACE_AXES["Front"])[0], dtype=np.float64)
    nW = R @ n
    k = L["k"]
    if k == "PointLight":
        ld = bpy.data.lights.new("pl", "POINT")
        ld.shadow_soft_size = 0.3
        loc = pos
    elif k == "SpotLight":
        ld = bpy.data.lights.new("sl", "SPOT")
        ld.spot_size = math.radians(max(5, min(179, L.get("a", 90))))
        ld.spot_blend = 0.4
        ld.shadow_soft_size = 0.2
        loc = pos + nW * (np.abs(n) @ np.array(part["s"]) / 2 + 0.05)
    else:
        ld = bpy.data.lights.new("al", "AREA")
        fw, fh, depth = face_dims(part["s"], face)
        ld.shape = "RECTANGLE"
        ld.size, ld.size_y = max(0.2, fw), max(0.2, fh)
        ld.spread = math.radians(max(10, min(180, L.get("a", 90))))
        loc = pos + nW * (depth / 2 + 0.05)
    ld.color = tuple(col)
    # Roblox brightness x range^2: a light that reaches its range reads about like the engine's
    ld.energy = power_k * b * (r ** 2) * (0.5 if k == "SurfaceLight" else 1.0)
    ob = bpy.data.objects.new("light", ld)
    ob.location = tuple(to_b(loc))
    if k != "PointLight":
        d = to_b(nW)
        # a Blender spot / area points along its local -Z
        z = -d / np.linalg.norm(d)
        x = np.cross((0, 0, 1), z)
        if np.linalg.norm(x) < 1e-6:
            x = np.array((1.0, 0, 0))
        x /= np.linalg.norm(x)
        y = np.cross(z, x)
        M = np.column_stack([x, y, z])
        import mathutils
        ob.rotation_euler = mathutils.Matrix(M.tolist()).to_euler()
    bpy.context.scene.collection.objects.link(ob)


# ------------------------------------------------------------------------------------------ lighting
# The views were tuned against the Lighting the server set before Config.Lighting (these numbers); the
# scene's exported Lighting (world_scene.luau: scene["lighting"] / scene["venueLighting"]) moves the sun,
# the fills and the exposure relative to them, so a brighter / warmer Lighting in the game renders
# brighter / warmer here too. Approximate: Cycles is not Future lighting.
REF = {"Brightness": 3.6, "Ambient": (138, 132, 126), "OutdoorAmbient": (150, 158, 172), "ExposureCompensation": 0.1,
       "venueExposure": 0.16, "venueBright": 0.4, "venueAmbient": (68, 70, 84)}
# the zone grades Ambience stacks on the global grade out of fights (client ColorCorrection "ZoneGrade";
# the approximate middle entries of Ambience.GRADES: GymWarm tier 2, Street, StreetNight)
ZONE_GRADES = {
    "interior": {"b": 0.02, "c": 0.04, "s": 0.08, "tint": (255, 245, 232)},
    "day": {"b": 0.03, "c": 0.06, "s": 0.14, "tint": (255, 250, 240)},
    "night": {"b": 0.04, "c": 0.08, "s": 0.2, "tint": (232, 228, 255)},
}


def lum(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def col01(c):
    """an exported colour (0..1 floats, or 0..255 ints) -> 0..1 floats"""
    c = tuple(float(x) for x in c[:3])
    return tuple(x / 255.0 for x in c) if max(c) > 1.0 else c


def lighting_for(scene, view):
    """(global Lighting dict or {}, the venue profile for a venue / crowd root or None)"""
    L = scene.get("lighting") or {}
    VL = scene.get("venueLighting") or {}
    venue = None
    for r in view.get("roots", []):
        name = r
        for prefix in ("venue_", "VenueDetail_", "VenueFX_"):
            if r.startswith(prefix):
                name = r[len(prefix):]
        for kind in VL:
            if name == kind or name.startswith(kind + "_"):
                venue = kind
    return L, VL.get(venue) if venue else None


def setup_world(mode, sun_strength, L=None, V=None):
    sc = bpy.context.scene
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes["Background"]
    props = (L or {}).get("props") or {}
    night_cfg = (L or {}).get("night") or {}
    sun_k = float(props.get("Brightness", REF["Brightness"])) / REF["Brightness"]
    amb = srgb2lin(col01(props.get("Ambient", REF["Ambient"])))
    out = srgb2lin(col01(props.get("OutdoorAmbient", REF["OutdoorAmbient"])))
    amb_k = lum(amb) / lum(srgb2lin(col01(REF["Ambient"])))
    out_k = lum(out) / lum(srgb2lin(col01(REF["OutdoorAmbient"])))
    sun_col = srgb2lin(col01(props.get("ColorShift_Top", (255, 245, 230))))
    sun_col = sun_col / max(1e-6, sun_col.max())
    if mode == "night":
        if V:
            # a fight night: the venue's Ambient is the fill the whole bowl sits in
            fill = srgb2lin(col01(V.get("ambient", REF["venueAmbient"])))
            bg.inputs["Color"].default_value = (*(fill * 0.3), 1)
        else:
            # the town after dark: Ambience eases OutdoorAmbient to Config.Lighting.Night
            sky = srgb2lin(col01(night_cfg.get("OutdoorAmbient", (82, 98, 164))))
            bg.inputs["Color"].default_value = (*(sky * 0.09), 1)
        bg.inputs["Strength"].default_value = 1.0
    elif mode == "interior":
        # the roof hides the sky: the world is the hall's fill (Ambient) with a little window blue
        tint = amb / max(1e-6, amb.max())
        c = np.array((0.45, 0.52, 0.62)) * 0.45 + tint * 0.55
        bg.inputs["Color"].default_value = (*c, 1)
        bg.inputs["Strength"].default_value = 0.6 * amb_k
    else:
        sky = nt.nodes.new("ShaderNodeTexSky")
        sky.sky_type = "NISHITA"
        sky.sun_elevation = math.radians(48)
        sky.sun_rotation = math.radians(200)
        sky.sun_intensity = 0.25 * sun_k
        sky.air_density = 1.2
        nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
        bg.inputs["Strength"].default_value = 0.35 * out_k
    if mode in ("day", "interior") and sun_strength > 0:
        sd = bpy.data.lights.new("sun", "SUN")
        sd.energy = sun_strength * sun_k
        sd.angle = math.radians(1.5 + 4.0 * float(props.get("ShadowSoftness", 0.2)))
        sd.color = tuple(np.array((1.0, 0.96, 0.9)) * sun_col) if L else (1.0, 0.96, 0.9)
        so = bpy.data.objects.new("sun", sd)
        so.rotation_euler = (math.radians(42), 0, math.radians(200))
        sc.collection.objects.link(so)
    if mode == "night":
        sd = bpy.data.lights.new("moon", "SUN")
        k = (float(V.get("bright", REF["venueBright"])) / REF["venueBright"]) if V else 1.0
        sd.energy = 0.08 * min(3.0, k)
        sd.color = (0.6, 0.7, 1.0)
        so = bpy.data.objects.new("moon", sd)
        so.rotation_euler = (math.radians(50), 0, math.radians(120))
        sc.collection.objects.link(so)


def exposure_for(view, L, V):
    """the view's tuned exposure plus how far the game's ExposureCompensation moved from the reference"""
    e = view.get("exposure", 0.0)
    if V:
        return e + float(V.get("exposure", REF["venueExposure"])) - REF["venueExposure"]
    props = (L or {}).get("props") or {}
    # Ambience adds the zone's offset on the base (LightLevels.Zones: the main hall GymWarm +0.15)
    zone = 0.15 if view.get("mode") == "interior" else 0.0
    return e + zone + float(props.get("ExposureCompensation", REF["ExposureCompensation"])) - REF["ExposureCompensation"]


def grade_for(mode, L, V):
    """ColorCorrection + Bloom as the game stacks them for this view -> ({b, c, s, tint}, {intensity, threshold, size})"""
    if V:
        g = {"b": 0.0, "c": float(V.get("contrast", 0)) + 0.02, "s": float(V.get("saturation", 0)), "tint": col01(V.get("tint", (1, 1, 1)))}
        bloom = {"intensity": float(V.get("bloomI", 0.5)), "threshold": float(V.get("bloomT", 1.4)), "size": float(V.get("bloomS", 28))}
        return g, bloom
    ch = (L or {}).get("children") or {}
    gg = ch.get("GymGrade") or {}
    z = ZONE_GRADES.get(mode, ZONE_GRADES["day"])
    tint = np.array(col01(gg.get("TintColor", (1, 1, 1)))) * np.array(col01(z["tint"]))
    g = {"b": float(gg.get("Brightness", 0)) + z["b"], "c": float(gg.get("Contrast", 0)) + z["c"], "s": float(gg.get("Saturation", 0)) + z["s"], "tint": tuple(tint)}
    bb = ch.get("GymBloom") or {}
    bloom = {"intensity": float(bb.get("Intensity", 0.3)), "threshold": float(bb.get("Threshold", 1.6)), "size": float(bb.get("Size", 28))}
    return g, bloom


def setup_grade(sc, grade, bloom):
    """the compositor: Roblox's ColorCorrectionEffect (saturation, contrast, brightness, tint) and BloomEffect, approximated"""
    sc.use_nodes = True
    nt = sc.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    rl = nt.nodes.new("CompositorNodeRLayers")
    last = rl.outputs["Image"]
    if bloom and bloom["intensity"] > 0.02:
        gl = nt.nodes.new("CompositorNodeGlare")
        try:
            gl.glare_type = "BLOOM"
        except TypeError:
            gl.glare_type = "FOG_GLOW"
        gl.quality = "MEDIUM"
        # Roblox's threshold is on the tonemapped value; Blender's on the scene-linear one
        gl.threshold = max(0.3, 0.9 * bloom["threshold"])
        gl.mix = -1.0 + min(0.6, 0.6 * bloom["intensity"])
        try:
            gl.size = int(max(6, min(9, 5 + bloom["size"] / 12)))
        except Exception:
            pass
        nt.links.new(last, gl.inputs["Image"])
        last = gl.outputs["Image"]
    hs = nt.nodes.new("CompositorNodeHueSat")
    hs.inputs["Saturation"].default_value = max(0.0, 1.0 + grade["s"])
    nt.links.new(last, hs.inputs["Image"])
    last = hs.outputs["Image"]
    bc = nt.nodes.new("CompositorNodeBrightContrast")
    bc.inputs["Bright"].default_value = grade["b"] * 60.0
    bc.inputs["Contrast"].default_value = grade["c"] * 60.0
    nt.links.new(last, bc.inputs["Image"])
    last = bc.outputs["Image"]
    tint = tuple(grade.get("tint", (1, 1, 1)))
    if any(abs(t - 1.0) > 0.002 for t in tint):
        mx = nt.nodes.new("CompositorNodeMixRGB")
        mx.blend_type = "MULTIPLY"
        mx.inputs["Fac"].default_value = 1.0
        mx.inputs[2].default_value = (*tint, 1.0)
        nt.links.new(last, mx.inputs[1])
        last = mx.outputs["Image"]
    comp = nt.nodes.new("CompositorNodeComposite")
    nt.links.new(last, comp.inputs["Image"])


def apply_lighting(sc, scene, view):
    """the world (sky / sun / fills), the exposure and the compositor grade for a view -> (mode, night)"""
    global AMBIENT_FILL
    mode = view.get("mode", "day")
    L, V = lighting_for(scene, view)
    props = (L or {}).get("props") or {}
    if V:
        AMBIENT_FILL = tuple(srgb2lin(col01(V.get("ambient", REF["venueAmbient"]))))
    elif mode == "interior":
        AMBIENT_FILL = tuple(srgb2lin(col01(props.get("Ambient", REF["Ambient"]))))
    else:
        AMBIENT_FILL = (0.0, 0.0, 0.0)
    setup_world(mode, view.get("sun", 3.5), L, V)
    sc.view_settings.exposure = exposure_for(view, L, V)
    g, bloom = grade_for(mode, L, V)
    setup_grade(sc, g, bloom)
    return mode, mode == "night"


def look_at(ob, eye, target):
    import mathutils
    e, t = to_b(np.array(eye, dtype=np.float64)), to_b(np.array(target, dtype=np.float64))
    ob.location = tuple(e)
    d = mathutils.Vector(tuple(t - e))
    ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def near(p, centre, radius, below=None):
    if below is not None and p["cf"][1] - p["s"][1] / 2 > below:
        return False
    if centre is None:
        return True
    q = np.array(p["cf"][:3])
    return np.linalg.norm(q - centre) <= radius + max(p["s"])


def render_view(scene, view, out, samples, res, tmpdir):
    reset()
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 4
    sc.cycles.diffuse_bounces = 2
    sc.cycles.glossy_bounces = 2
    sc.cycles.transparent_max_bounces = 8
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.image_settings.file_format = "JPEG"
    sc.render.image_settings.quality = 90
    sc.view_settings.view_transform = "AgX"
    mode, night = apply_lighting(sc, scene, view)
    B = Builder(tmpdir)
    centre = np.array(view["cull"][0]) if view.get("cull") else None
    radius = view["cull"][1] if view.get("cull") else 0
    nparts = 0
    for rname in view["roots"]:
        root = scene["roots"].get(rname)
        if not root:
            continue
        parts = root["parts"]
        keep = [near(p, centre, radius, view.get("below")) for p in parts]
        for p, k in zip(parts, keep):
            if k:
                B.add_part(p, night)
                nparts += 1
        for g in root.get("guis", []):
            if keep[g["part"] - 1]:
                B.add_gui(g, parts[g["part"] - 1])
        for dc in root.get("decals", []):
            if keep[dc["part"] - 1]:
                B.add_decal(dc, parts[dc["part"] - 1])
        for bm in root.get("beams", []):
            if centre is None or np.linalg.norm(np.array(bm["a"]) - centre) <= radius:
                B.add_beam(bm)
        for L in root.get("lights", []):
            if keep[L["part"] - 1]:
                add_light(L, parts[L["part"] - 1], night, view.get("light_k", 2.0))
    B.flush()
    cd = bpy.data.cameras.new("cam")
    if view.get("ortho"):
        cd.type = "ORTHO"
        cd.ortho_scale = view["ortho"]
    cd.lens_unit = "FOV"
    # fov = the vertical field of view (as Roblox's Camera.FieldOfView); Blender's angle is the horizontal one
    vf = math.radians(view.get("fov", 60))
    cd.angle = 2 * math.atan(math.tan(vf / 2) * res[0] / res[1])
    cd.clip_start = 0.3
    cd.clip_end = 5000
    cam = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    look_at(cam, view["eye"], view["target"])
    sc.render.filepath = out
    print("render", os.path.basename(out), "parts", nparts, "guis", B.gui_count, flush=True)
    bpy.ops.render.render(write_still=True)


# ----------------------------------------------------------------------------------------------- views
GYM = ["server_gym_and_city", "LocalGym", "WorldDetail_gym"]
CITY = ["server_gym_and_city", "LocalCity", "WorldDetail_city"]
VIEWS = {
    # the gym (the roof hides the sky: interior light mode)
    "gym_ring": {"roots": GYM, "eye": (-30, 13, 22), "target": (0, 4, -30), "fov": 50, "mode": "interior", "cull": ((0, 10, -20), 140)},
    "gym_bags": {"roots": GYM, "eye": (40, 9, 10), "target": (-10, 4, -50), "fov": 50, "mode": "interior", "cull": ((0, 10, -20), 140)},
    "gym_ringclose": {"roots": GYM, "eye": (-16, 9, -28), "target": (2, 3, -48), "fov": 50, "mode": "interior", "cull": ((0, 10, -40), 90)},
    "gym_stations": {"roots": GYM, "eye": (-8, 7, 2), "target": (-24, 4, -16), "fov": 50, "mode": "interior", "cull": ((-10, 10, -20), 90)},
    "gym_weights": {"roots": GYM, "eye": (-55, 9, 16), "target": (-95, 3, -40), "fov": 50, "mode": "interior", "cull": ((-70, 10, -20), 110)},
    "gym_lobby": {"roots": GYM, "eye": (-20, 9, 70), "target": (30, 4, 20), "fov": 50, "mode": "interior", "cull": ((10, 10, 40), 120)},
    "gym_cardio": {"roots": GYM, "eye": (56, 9, 14), "target": (100, 3, -42), "fov": 50, "mode": "interior", "cull": ((80, 10, -30), 110)},
    "gym_desk": {"roots": GYM, "eye": (29, 7.5, 50), "target": (33, 3.5, 77), "fov": 55, "mode": "interior", "cull": ((30, 8, 66), 45)},
    "gym_lockers": {"roots": GYM, "eye": (-56, 8, 62), "target": (-88, 4, 26), "fov": 52, "mode": "interior", "cull": ((-78, 10, 45), 80)},
    "gym_walls_w": {"roots": GYM, "eye": (24, 8, -24), "target": (-50, 6, -46), "fov": 50, "mode": "interior", "cull": ((-10, 10, -40), 110)},
    "gym_walls_n": {"roots": GYM, "eye": (-4, 7, -36), "target": (-26, 6, -79), "fov": 55, "mode": "interior", "cull": ((-20, 10, -60), 70)},
    "gym_ceiling": {"roots": GYM, "eye": (10, 5, 14), "target": (-14, 25, -40), "fov": 60, "mode": "interior", "cull": ((0, 18, -20), 130)},
    "gym_corner": {"roots": GYM, "eye": (-29, 6.5, -47), "target": (-15, 2.4, -62), "fov": 50, "mode": "interior", "cull": ((-18, 6, -58), 50)},
    "gym_kitwall": {"roots": GYM, "eye": (35, 6.5, -62), "target": (45, 5.5, -76), "fov": 58, "mode": "interior", "cull": ((40, 8, -70), 40)},
    "gym_bagwall": {"roots": GYM, "eye": (-37, 6.5, -63), "target": (-48, 5, -76), "fov": 58, "mode": "interior", "cull": ((-42, 8, -70), 40)},
    "gym_weights2": {"roots": GYM, "eye": (-64, 7.5, -12), "target": (-51, 3, -56), "fov": 55, "mode": "interior", "cull": ((-58, 8, -40), 60)},
    "gym_whiteboard": {"roots": GYM, "eye": (-90, 7, -4), "target": (-109, 5, 11), "fov": 55, "mode": "interior", "cull": ((-100, 8, 6), 40)},
    "gym_weighin": {"roots": GYM, "eye": (86, 7, -4), "target": (103, 4.5, 16), "fov": 52, "mode": "interior", "cull": ((98, 8, 8), 50)},
    # the city
    # the signage: the gym's front banner (+Z wall, seen from the lobby) and the motto (north wall), the shop fronts
    "gym_banner": {"roots": GYM, "eye": (-14, 8, 8), "target": (0, 19, 79), "fov": 55, "mode": "interior", "cull": ((0, 14, 50), 110)},
    "gym_motto": {"roots": GYM, "eye": (14, 8, -8), "target": (0, 22, -79), "fov": 55, "mode": "interior", "cull": ((0, 14, -50), 110)},
    "city_signs_day": {"roots": CITY, "eye": (-230, 9, 170), "target": (-180, 10, 187), "fov": 48, "mode": "day", "cull": ((-200, 10, 185), 160)},
    "city_signs_night": {"roots": CITY, "eye": (-230, 9, 170), "target": (-180, 10, 187), "fov": 48, "mode": "night", "cull": ((-200, 10, 185), 160), "exposure": 1.0},
    "city_signs_east": {"roots": CITY, "eye": (40, 9, 170), "target": (100, 10, 187), "fov": 48, "mode": "day", "cull": ((80, 10, 185), 160)},
    "city_main_day": {"roots": CITY, "eye": (-150, 7, 348), "target": (140, 10, 330), "fov": 55, "mode": "day", "cull": ((0, 10, 330), 600)},
    "city_main_night": {"roots": CITY, "eye": (-150, 7, 348), "target": (140, 10, 330), "fov": 55, "mode": "night", "cull": ((0, 10, 330), 600), "exposure": 1.0},
    "city_front_day": {"roots": CITY, "eye": (28, 7, 138), "target": (-2, 7, 84), "fov": 50, "mode": "day", "cull": ((0, 10, 110), 220)},
    "city_shops_day": {"roots": CITY, "eye": (40, 6, 168), "target": (80, 7, 186), "fov": 50, "mode": "day", "cull": ((60, 10, 180), 160)},
    "city_aerial_day": {"roots": CITY, "eye": (-140, 90, 290), "target": (0, 0, 150), "fov": 45, "mode": "day", "cull": ((0, 10, 150), 400)},
    # venues by tier (camera from the crowd side, ring centre at the anchor)
    "venue_t1_community": {"roots": ["venue_CommunityCenter", "VenueDetail_CommunityCenter"], "eye": (4500 - 26, 14, 4000 + 30), "target": (4500, 4, 4000), "fov": 48, "mode": "night", "exposure": 1.2},
    "venue_t2_club": {"roots": ["venue_ClubArena", "VenueDetail_ClubArena"], "eye": (5000 - 32, 16, 4000 + 36), "target": (5000, 5, 4000), "fov": 48, "mode": "night", "exposure": 1.2},
    "venue_t3_arena": {"roots": ["venue_Arena", "VenueDetail_Arena"], "eye": (5500 - 44, 24, 4000 + 50), "target": (5500, 6, 4000), "fov": 48, "mode": "night", "exposure": 1.2},
    "venue_t4_stadium": {"roots": ["venue_Stadium", "VenueDetail_Stadium"], "eye": (4000 - 60, 34, 4500 + 70), "target": (4000, 6, 4500), "fov": 48, "mode": "night", "exposure": 1.2},
    "venue_t3_wide": {"roots": ["venue_Arena", "VenueDetail_Arena"], "eye": (5500 - 70, 52, 4000 + 84), "target": (5500, 18, 4000), "fov": 55, "mode": "night", "exposure": 1.2},
    # the Arena on a world title night with VenueFX's show rig (world_scene runs VenueFX.Start on it: roots venue_Arena_show + VenueFX_Arena)
    "venue_t3_title": {"roots": ["venue_Arena_show", "VenueDetail_Arena", "VenueFX_Arena"], "eye": (5500 - 30, 14, 4000 + 34), "target": (5500, 5, 4000), "fov": 48, "mode": "night", "exposure": 1.2},
    # the same arena on a regular card's walkout: red / blue promotion colours, the spots sweeping in their gels
    "venue_t3_card": {"roots": ["venue_Arena_card", "VenueDetail_Arena", "VenueFX_ArenaCard"], "eye": (5500 - 30, 14, 4000 + 34), "target": (5500, 5, 4000), "fov": 48, "mode": "night", "exposure": 1.2},
    "venue_t3_card_wide": {"roots": ["venue_Arena_card", "VenueDetail_Arena", "VenueFX_ArenaCard"], "eye": (5500 - 70, 52, 4000 + 84), "target": (5500, 18, 4000), "fov": 55, "mode": "night", "exposure": 1.2},
    "venue_t3_title_wide": {"roots": ["venue_Arena_show", "VenueDetail_Arena", "VenueFX_Arena"], "eye": (5500 - 70, 52, 4000 + 84), "target": (5500, 18, 4000), "fov": 55, "mode": "night", "exposure": 1.2},
    "venue_t4_wide": {"roots": ["venue_Stadium", "VenueDetail_Stadium"], "eye": (4000 - 110, 70, 4500 + 120), "target": (4000, 22, 4500), "fov": 55, "mode": "night", "exposure": 1.2},
    "venue_t2_aisle": {"roots": ["venue_ClubArena", "VenueDetail_ClubArena"], "eye": (5000, 9, 4000 + 60), "target": (5000 + 5, 5, 4000 + 22), "fov": 50, "mode": "night", "exposure": 1.2},
    "venue_spar_gym": {"roots": ["venue_Gym", "VenueDetail_Gym"], "eye": (4500 - 18, 11, 4500 + 20), "target": (4500, 4, 4500), "fov": 48, "mode": "interior", "exposure": 0.3},
    # plans (orthographic, from above, roof cut away)
    "plan_gym": {"roots": GYM, "eye": (0, 200, 0.01), "target": (0, 0, 0), "ortho": 240, "mode": "interior", "below": 26, "cull": ((0, 10, 0), 170), "sun": 2.0},
    "plan_main": {"roots": CITY, "eye": (0, 300, 175.01), "target": (0, 0, 175), "ortho": 300, "mode": "day", "cull": ((0, 10, 175), 200)},
    # the title screen
    "menu_wide": {"roots": ["menu"], "eye": (12, 1410, 20), "target": (-6, 1402, -18), "fov": 60, "mode": "night", "sun": 0.0, "exposure": 2.0},
    "menu_stage": {"roots": ["menu"], "camera": "menu", "mode": "night", "sun": 0.0, "exposure": 1.6},
}


def main():
    argv = sys.argv[1:]
    scene_path, out_dir = argv[0], argv[1]
    only = None
    samples, res, tag = 48, (1280, 720), ""
    i = 2
    while i < len(argv):
        a = argv[i]
        if a == "--only":
            only = argv[i + 1].split(",")
            i += 1
        elif a == "--samples":
            samples = int(argv[i + 1])
            i += 1
        elif a == "--res":
            res = tuple(int(x) for x in argv[i + 1].split("x"))
            i += 1
        elif a == "--tag":
            tag = "_" + argv[i + 1]
            i += 1
        i += 1
    scene = json.load(open(scene_path))
    os.makedirs(out_dir, exist_ok=True)
    tmpdir = os.path.join(os.path.dirname(os.path.abspath(scene_path)), "gui_png")
    os.makedirs(tmpdir, exist_ok=True)
    for name, view in VIEWS.items():
        if only and name not in only:
            continue
        v = dict(view)
        if v.get("camera"):
            cam = scene.get("cameras", {}).get(v["camera"])
            if not cam:
                continue
            cf = cam["cf"]
            pos = np.array(cf[:3])
            R = np.array(cf[3:]).reshape(3, 3)
            look = -R[:, 2]
            v["eye"] = tuple(pos)
            v["target"] = tuple(pos + look * 10)
            v["fov"] = cam.get("fov", 40)
        render_view(scene, v, os.path.join(out_dir, name + tag + ".jpg"), samples, res, tmpdir)


if __name__ == "__main__":
    main()
