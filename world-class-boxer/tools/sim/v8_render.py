"""Cycles renders of the v8 boxers exported by tools/sim/v8_scene.luau (world space, studs, +Y up, face -Z).

    /opt/bpyenv/bin/python tools/sim/v8_render.py SCENE_DIR OUT_DIR [--only id,id] [--samples N] [--no-lineup]
                                                 [--views 34,head,back]

Per look: three views (3/4 full body, front close-up of head + shoulders, back), a sheet <id>.jpg; then one cast
lineup (every look side by side) lineup.jpg. Reuses tools/hair/render.py (Scene, materials, add_mesh, camera, sheet)
and previews.py (rgba -> png). Geometry is exactly what the scene file says:
  * meshes: the tier MeshParts (world-space triangles), skin material tinted by the part colour, and the gear meshes
    (BuilderGear's pieces, world-space triangles) in a gear material by their Material / colour
  * head: the classic head revolved from AnatomyHairKit.CLASSIC (a cylinder of radius half the width whose top and
    bottom edges round off), scaled to the head's Size, at its CFrame; the face decal planar-projected onto its front
  * parts: Kit.mk gear by shape (Block, Ball, Cylinder along X, Ellipsoid, Wedge)
  * hair: world-space triangles with the tinted texture's alpha
"""
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "hair"))
import render  # noqa: E402
import previews  # noqa: E402
import bpy  # noqa: E402


def srgb2lin(c):
    c = np.asarray(c, dtype=np.float64)
    return tuple(np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4))


def cf_mat(cf):
    p = np.array(cf[:3])
    R = np.array(cf[3:]).reshape(3, 3)
    return p, R


# ---------------------------------------------------------------------------------------------- primitives (local)
def box(sx, sy, sz):
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    P, T = [], []
    faces = [((1, 0, 0), (0, 1, 0), (0, 0, 1)), ((-1, 0, 0), (0, 0, 1), (0, 1, 0)), ((0, 1, 0), (0, 0, 1), (1, 0, 0)),
             ((0, -1, 0), (1, 0, 0), (0, 0, 1)), ((0, 0, 1), (1, 0, 0), (0, 1, 0)), ((0, 0, -1), (0, 1, 0), (1, 0, 0))]
    h = np.array([hx, hy, hz])
    for n, u, v in faces:
        n, u, v = map(np.array, (n, u, v))
        c = n * h
        b = len(P)
        for a, bb in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            P.append(c + a * u * h + bb * v * h)
        T += [(b, b + 1, b + 2), (b, b + 2, b + 3)]
    return np.array(P), np.array(T)


def uv_sphere(rx, ry, rz, nu=24, nv=14):
    P, T = [], []
    for j in range(nv + 1):
        th = math.pi * j / nv
        for i in range(nu):
            ph = 2 * math.pi * i / nu
            P.append((rx * math.sin(th) * math.cos(ph), ry * math.cos(th), rz * math.sin(th) * math.sin(ph)))
    for j in range(nv):
        for i in range(nu):
            a, b = j * nu + i, j * nu + (i + 1) % nu
            c, d = a + nu, b + nu
            T += [(a, c, b), (b, c, d)]
    return np.array(P), np.array(T)


def cylinder_x(length, ry, rz, n=24):
    P, T = [], []
    for s in (-1, 1):
        for i in range(n):
            a = 2 * math.pi * i / n
            P.append((s * length / 2, ry * math.cos(a), rz * math.sin(a)))
    for i in range(n):
        j = (i + 1) % n
        T += [(i, j, n + i), (j, n + j, n + i)]
    c0, c1 = len(P), len(P) + 1
    P += [(-length / 2, 0, 0), (length / 2, 0, 0)]
    for i in range(n):
        j = (i + 1) % n
        T += [(c0, j, i), (c1, n + i, n + j)]
    return np.array(P), np.array(T)


def wedge(sx, sy, sz):
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    # Roblox WedgePart: full bottom, full back (+Z) face, the slope rising from the front-bottom edge to the back-top
    P = np.array([(-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz), (-hx, hy, hz), (hx, hy, hz)])
    T = np.array([(0, 2, 1), (0, 3, 2), (3, 4, 5), (3, 5, 2), (0, 1, 5), (0, 5, 4), (0, 4, 3), (1, 2, 5)])
    return P, T


def classic_profile(C, nr=10):
    """(rho, y) loop of the classic head's half section, nominal studs: AnatomyHairKit.ClassicField's surface."""
    r, h, rr = C["r"], C["h"], C["round"]
    pts = [(0.0, h)]
    for k in range(nr + 1):  # top round edge
        a = math.pi / 2 * (1 - k / nr)
        pts.append((r - rr + rr * math.cos(a), h - rr + rr * math.sin(a)))
    for k in range(nr + 1):  # bottom round edge
        a = -math.pi / 2 * k / nr
        pts.append((r - rr + rr * math.cos(a), -h + rr + rr * math.sin(a)))
    pts.append((0.0, -h))
    return pts


def classic_head(C, size, nseg=56):
    prof = classic_profile(C)
    P, T = [], []
    m = len(prof)
    for i in range(nseg):
        a = 2 * math.pi * i / nseg
        for rho, y in prof:
            P.append((rho * math.sin(a), y, -rho * math.cos(a)))
    for i in range(nseg):
        i2 = (i + 1) % nseg
        for j in range(m - 1):
            a, b = i * m + j, i * m + j + 1
            c, d = i2 * m + j, i2 * m + j + 1
            T += [(a, b, c), (b, d, c)]
    k = np.array(size) / 1.2
    return np.array(P) * k, np.array(T)


def classic_sdf(C, x, y, z):
    r, h, rr = C["r"], C["h"], C["round"]
    qx = math.sqrt(x * x + z * z) - (r - rr)
    qy = abs(y) - (h - rr)
    ox, oy = max(qx, 0), max(qy, 0)
    return math.sqrt(ox * ox + oy * oy) + min(max(qx, qy), 0) - rr


def face_decal(C, size, n=28, lift=0.006):
    """The Front-face decal (covering the head's box front, Size.X x Size.Y) projected along +Z onto the head."""
    k = np.array(size) / 1.2
    P, U, T = [], [], []
    for j in range(n + 1):
        for i in range(n + 1):
            u, v = i / n, j / n
            x, y = (u - 0.5) * 1.2, (0.5 - v) * 1.2
            # march from the front (-Z) to the surface
            z = -1.0
            while z < 0 and classic_sdf(C, x, y, z) > 0.0005:
                z += max(classic_sdf(C, x, y, z), 0.0005)
            z = min(z, 0.0) - lift
            P.append((x * k[0], y * k[1], z * k[2]))
            # (the image as the viewer facing the head sees it: its left edge on the head's +X, the character's
            # right; u here runs along +X)
            U.append((1 - u, v))
    for j in range(n):
        for i in range(n):
            a = j * (n + 1) + i
            T += [(a, a + n + 1, a + 1), (a + 1, a + n + 1, a + n + 2)]
    return np.array(P), np.array(U), np.array(T)


# ---------------------------------------------------------------------------------------------- materials
ROUGH = {"SmoothPlastic": 0.38, "Plastic": 0.5, "Leather": 0.48, "Fabric": 0.82, "Rubber": 0.9, "Sand": 0.95,
         "Metal": 0.3, "Foil": 0.2, "Neon": 0.5}


class V8Scene(render.Scene):
    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        self.lights = []
        for ob in self.sc.collection.objects:
            if ob.type == "LIGHT":
                self.lights.append((ob, tuple(ob.location), ob.data.energy, getattr(ob.data, "size", 1.0)))
        self._gmats = {}
        self.floor()

    def rig(self, centre_game, scale):
        """the studio light rig of render.Scene (built round a head at the origin), moved and scaled"""
        from mathutils import Vector
        bpy.context.view_layer.update()
        c = self.root.matrix_world @ Vector(tuple(centre_game))
        for ob, loc, energy, size in self.lights:
            ob.location = c + Vector(loc) * scale
            ob.data.energy = energy * scale * scale
            if ob.data.type == "AREA":
                ob.data.size = size * scale
            ob.rotation_quaternion = (c - ob.location).to_track_quat("-Z", "Y")

    def floor(self):
        P = np.array([(-30, 0, -30), (30, 0, -30), (30, 0, 30), (-30, 0, 30)], dtype=float)
        T = np.array([(0, 2, 1), (0, 3, 2)])
        md = {"p": P.ravel(), "t": T.ravel(), "base": 0}
        ob = self.add_mesh(md, material="plastic", tint=(0.05, 0.052, 0.058), name="floor", smooth=False)
        ob.data.materials[0].node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.8

    def gear_mat(self, color, material, refl):
        key = (tuple(round(c, 3) for c in color), material, round(refl, 2))
        if key in self._gmats:
            return self._gmats[key]
        m = bpy.data.materials.new("g" + str(len(self._gmats)))
        m.use_nodes = True
        bs = m.node_tree.nodes["Principled BSDF"]
        bs.inputs["Base Color"].default_value = (*srgb2lin(color), 1)
        r = ROUGH.get(material, 0.5)
        if refl > 0.05:
            r = min(r, 0.22)
        bs.inputs["Roughness"].default_value = r
        if material in ("Metal", "Foil"):
            bs.inputs["Metallic"].default_value = 0.8
        self._gmats[key] = m
        return m

    def add_world(self, P, T, name, mat=None, uv=None, normals=None, smooth=True, **kw):
        md = {"p": np.asarray(P).ravel(), "t": np.asarray(T).ravel(), "base": 0}
        if uv is not None:
            md["uv"] = np.asarray(uv).ravel()
        if normals is not None:
            md["n"] = np.asarray(normals).ravel()
        ob = self.add_mesh(md, name=name, smooth=smooth, **kw)
        if mat is not None:
            ob.data.materials.clear()
            ob.data.materials.append(mat)
        return ob


def place(P, cf, offset):
    p, R = cf_mat(cf)
    return P @ R.T + p + offset


def add_boxer(sc, scene_dir, d, offset=(0, 0, 0)):
    off = np.array(offset, dtype=float)
    for m in d["meshes"]:
        P = np.asarray(m["p"]).reshape(-1, 3) + off
        T = np.asarray(m["t"]).reshape(-1, 3) - 1
        col = m["color"]
        # a tier part in the head's colour is skin; the gear meshes and a part painted another colour (the trunks'
        # LowerTorso under the seat, a woman's torso without the mesh top) take a gear material
        skin = d["head"]["color"]
        skinlike = (not m.get("gear") and m["material"] in ("SmoothPlastic", "Plastic")
                    and max(abs(a - b) for a, b in zip(col, skin)) < 0.02)
        if skinlike:
            sc.add_world(P, T, m["name"], material="skin", tint=srgb2lin(col), normals=m["n"])
        else:
            sc.add_world(P, T, m["name"], mat=sc.gear_mat(col, m["material"], m.get("reflectance", 0)), normals=m["n"])
    hd = d["head"]
    P, T = classic_head(hd["classic"], hd["size"])
    sc.add_world(place(P, hd["cf"], off), T, "Head", material="skin", tint=srgb2lin(hd["color"]))
    dec = hd.get("decal")
    if dec and dec.get("file"):
        P, U, T = face_decal(hd["classic"], hd["size"])
        sc.add_world(place(P, hd["cf"], off), T, "face", uv=U, texture=dec["file"], material="plastic", alpha=True,
                     smooth=True)
    for g in d["parts"]:
        sx, sy, sz = g["size"]
        sh = g["shape"]
        if sh == "Block":
            P, T = box(sx, sy, sz)
            smooth = False
        elif sh == "Ball":
            r = min(sx, sy, sz) / 2
            P, T = uv_sphere(r, r, r)
            smooth = True
        elif sh == "Cylinder":
            r = min(sy, sz) / 2
            P, T = cylinder_x(sx, r, r)
            smooth = True
        elif sh == "Ellipsoid":
            P, T = uv_sphere(sx / 2, sy / 2, sz / 2)
            smooth = True
        elif sh == "Wedge":
            P, T = wedge(sx, sy, sz)
            smooth = False
        elif sh == "Head":
            # a SpecialMesh Head (the classic head's shape at the part's size: the headgear shell / band)
            P, T = classic_head(d["head"]["classic"], (sx, sy, sz))
            smooth = True
        else:
            print("unknown shape", sh, g["name"])
            continue
        ob = sc.add_world(place(P, g["cf"], off), T, g["name"], mat=sc.gear_mat(g["color"], g["material"],
                                                                             g.get("reflectance", 0)), smooth=smooth)
        if not smooth:
            for poly in ob.data.polygons:
                poly.use_smooth = False
    for h in d["hair"]:
        tex = previews.tex_path(scene_dir, h.get("texture"))
        P = np.asarray(h["p"]).reshape(-1, 3) + off
        md = {"p": P.ravel(), "n": h["n"], "uv": h["uv"], "t": h["t"], "base": 1}
        sc.add_mesh(md, texture=tex, material="hair", alpha=tex is not None, name=h["name"])


def head_focus(d):
    p = np.array(d["head"]["cf"][:3])
    return p + np.array([0, -0.32, 0])


def render_look(scene_dir, out_dir, look, samples, views):
    d = json.load(open(os.path.join(scene_dir, look["file"])))
    paths, labels = [], []
    res = (480, 760)
    sc = V8Scene(res=res, samples=samples, lens=50, bg=(0.11, 0.115, 0.125))
    add_boxer(sc, scene_dir, d)
    top = d["head"]["cf"][1] + d["head"]["size"][1] / 2 + 0.1
    body_focus = (0, top / 2, 0)
    body_dist = (top / 2 + 0.45) / math.tan(math.atan(18 / 50)) * 1.0
    for v in views:
        p = os.path.join(out_dir, f"{look['id']}_{v}.png")
        if v == "34":
            sc.cam.data.lens = 50
            sc.rig(body_focus, 3.0)
            sc.render(p, view=(35, 8, 1.0), dist=body_dist, focus=body_focus)
            labels.append("3/4 full body")
        elif v == "back":
            sc.cam.data.lens = 50
            sc.rig(body_focus, 3.0)
            # the back gets the key from behind too (the rig lights the front)
            sc.render(p, view=(180, 6, 1.0), dist=body_dist, focus=body_focus)
            labels.append("back")
        elif v == "head":
            f = head_focus(d)
            sc.cam.data.lens = 85
            sc.rig(tuple(f), 1.25)
            sc.render(p, view=(0, 3, 1.0), dist=1.25 / math.tan(math.atan(18 / 85)), focus=tuple(f))
            labels.append("front close-up")
        paths.append(p)
    title = f"{look['label']}   [tiers {look['tierKey']}, {look['frame']}, hair entry {look['hair'].get('entry')}]"
    render.sheet(paths, os.path.join(out_dir, f"{look['id']}.jpg"), cols=len(paths), labels=labels, title=title)
    print("rendered", look["id"], flush=True)


def render_lineup(scene_dir, out_dir, looks, samples):
    n = len(looks)
    gap = 2.7
    sc = V8Scene(res=(1800, 760), samples=samples, lens=50, bg=(0.11, 0.115, 0.125))
    labels = []
    for i, look in enumerate(looks):
        d = json.load(open(os.path.join(scene_dir, look["file"])))
        # (the boxers face -Z, the camera looks at their fronts: +X is the viewer's left)
        x = -(i - (n - 1) / 2) * gap
        add_boxer(sc, scene_dir, d, offset=(x, 0, 0))
        labels.append((look, x))
    width = (n - 1) * gap + 2.4
    focus = (0, 3.1, 0)
    # horizontal fov (sensor 36 mm across the width)
    dist = (width / 2) / math.tan(math.atan(18 / 50)) * 1.12
    sc.rig(focus, 6.0)
    p = os.path.join(out_dir, "lineup.png")
    sc.render(p, view=(14, 7, 1.0), dist=dist, focus=focus)
    from bpy_extras.object_utils import world_to_camera_view
    from mathutils import Vector
    M = sc.root.matrix_world
    xs = [world_to_camera_view(sc.sc, sc.cam, M @ Vector((x, 0.0, 0.0))).x for _, x in labels]
    from PIL import Image, ImageDraw, ImageFont
    im = Image.open(p).convert("RGB")
    W = Image.new("RGB", (im.width, im.height + 80), (26, 27, 30))
    W.paste(im, (0, 46))
    dr = ImageDraw.Draw(W)
    tf = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 16)
    dr.text((12, 11), "v8 cast lineup (Builder.Cosmetics + HairAssets.Build, classic heads, tier bodies, mesh gear)", fill=(235, 235, 235),
            font=tf)
    for i, look in enumerate(looks):
        cx = xs[i] * im.width
        txt = f"{look['id']} (T{look['tierKey'][0]})"
        dr.text((cx - dr.textlength(txt, font=f) / 2, im.height + 52), txt, fill=(210, 210, 210), font=f)
    W.save(os.path.join(out_dir, "lineup.jpg"), quality=88)
    print("rendered lineup", flush=True)


def render_hairfit(scene_dir, out_dir, looks, samples):
    """head close-ups (3/4, side, back 3/4, top 3/4) of every rest-pose look: how the hair sits on the classic head"""
    views = [("3/4", (35, 6, 1.0)), ("side", (90, 2, 1.0)), ("back 3/4", (145, 8, 1.0)), ("top 3/4", (35, 40, 1.0))]
    rows = []
    for look in looks:
        if look.get("pose", "rest") != "rest":
            continue
        d = json.load(open(os.path.join(scene_dir, look["file"])))
        sc = V8Scene(res=(340, 340), samples=samples, lens=85, bg=(0.11, 0.115, 0.125))
        add_boxer(sc, scene_dir, d)
        f = tuple(np.array(d["head"]["cf"][:3]) + np.array([0, 0.02, 0]))
        sc.rig(f, 1.0)
        paths = []
        for name, v in views:
            p = os.path.join(out_dir, f"{look['id']}_fit_{name.replace('/', '').replace(' ', '')}.png")
            sc.render(p, view=v, dist=0.78 / math.tan(math.atan(18 / 85)), focus=f)
            paths.append(p)
        rows.append((look, paths))
        print("hairfit", look["id"], flush=True)
    from PIL import Image, ImageDraw, ImageFont
    w, h, lab = 340, 340, 24
    W = Image.new("RGB", (4 * w, 46 + len(rows) * (h + lab)), (26, 27, 30))
    dr = ImageDraw.Draw(W)
    tf = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 20)
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
    dr.text((12, 12), "v8 hair on the classic head (HairAssets.Build placement): 3/4, side, back 3/4, top 3/4", fill=(235, 235, 235), font=tf)
    for r, (look, paths) in enumerate(rows):
        y = 46 + r * (h + lab)
        for c, p in enumerate(paths):
            W.paste(Image.open(p).convert("RGB"), (c * w, y))
        dr.text((8, y + h + 3), f"{look['id']}: {look['hair'].get('entry')}  ({views[0][0]}, {views[1][0]}, {views[2][0]}, {views[3][0]})",
                fill=(210, 210, 210), font=f)
    W.save(os.path.join(out_dir, "hairfit.jpg"), quality=88)


if __name__ == "__main__":
    argv = sys.argv[1:]
    if "--" in sys.argv:
        argv = sys.argv[sys.argv.index("--") + 1:]
    scene_dir, out_dir = argv[0], argv[1]
    opts = {}
    i = 2
    while i < len(argv):
        k = argv[i]
        if k in ("--no-lineup", "--lineup-only", "--no-hairfit"):
            opts[k] = True
            i += 1
        else:
            opts[k] = argv[i + 1]
            i += 2
    os.makedirs(out_dir, exist_ok=True)
    idx = json.load(open(os.path.join(scene_dir, "index.json")))
    only = set(opts["--only"].split(",")) if "--only" in opts else None
    looks = [l for l in idx["looks"] if not only or l["id"] in only]
    samples = int(opts.get("--samples", 40))
    views = opts.get("--views", "34,head,back").split(",")
    if not opts.get("--lineup-only"):
        for l in looks:
            render_look(scene_dir, out_dir, l, samples, views)
    if not opts.get("--no-lineup"):
        render_lineup(scene_dir, out_dir, [l for l in idx["looks"]], samples)
    if not opts.get("--no-hairfit"):
        render_hairfit(scene_dir, out_dir, [l for l in idx["looks"] if not only or l["id"] in only], samples)
