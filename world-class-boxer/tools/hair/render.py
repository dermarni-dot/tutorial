"""Preview renderer (Blender Cycles, CPU) for heads with hair, before / after.

Lighting approximates the game's studio look (warm key, cool fill, two rims, soft shadows,
Filmic/AgX tone mapping). Meshes come in game head space (+Y up, -Z forward); the scene rotates
them so the head faces the camera.

    import render
    sc = render.Scene(res=(520, 620), samples=48)
    sc.add_mesh(mesh_dict, texture="hair_coily_tinted.png" or None, material="hair"|"skin"|"plastic",
                tint=(r, g, b), alpha=True)
    sc.render("out.png", view="34")     # views: front, 34, side, back, top34, back34

mesh_dict: {"p": [x,y,z,...], "uv": [u,v,...] (0,0 top-left), "c": [r,g,b,...] or rgba,
            "t": [a,b,c,...] 0- or 1-based (key "base": 0|1), "n": optional}
"""
import math
import os

import bpy
import numpy as np

VIEWS = {
    # (azimuth around the head in degrees, 0 = facing the face; elevation degrees; distance scale)
    "front": (0, 4, 1.0),
    "34": (35, 8, 1.0),
    "side": (90, 4, 1.0),
    "back": (180, 6, 1.0),
    "back34": (145, 10, 1.0),
    "top34": (35, 38, 1.05),
    "low34": (30, -12, 1.0),
}


def _reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


class Scene:
    def __init__(self, res=(520, 620), samples=48, bg=(0.105, 0.11, 0.12), focus=(0.0, 0.05, 0.0),
                 dist=3.3, lens=85):
        _reset()
        sc = bpy.context.scene
        self.sc = sc
        sc.render.engine = "CYCLES"
        sc.cycles.device = "CPU"
        sc.cycles.samples = samples
        sc.cycles.use_denoising = True
        sc.cycles.max_bounces = 6
        sc.cycles.transparent_max_bounces = 64  # stacked hair cards
        sc.render.resolution_x, sc.render.resolution_y = res
        sc.render.film_transparent = False
        try:
            sc.view_settings.view_transform = "AgX"
        except TypeError:
            sc.view_settings.view_transform = "Filmic"
        sc.view_settings.look = "None"
        world = bpy.data.worlds.new("w")
        sc.world = world
        world.use_nodes = True
        bgn = world.node_tree.nodes["Background"]
        bgn.inputs[0].default_value = (*bg, 1)
        bgn.inputs[1].default_value = 0.35
        self.focus = np.array(focus)  # game space
        self.dist = dist
        self.lens = lens
        self.root = bpy.data.objects.new("root", None)  # game space -> Blender (Y up -> Z up)
        sc.collection.objects.link(self.root)
        self.root.rotation_euler = (math.pi / 2, 0, math.pi)  # face (-Z game) toward Blender -Y
        self._lights()
        cam = bpy.data.cameras.new("cam")
        cam.lens = lens
        cam.clip_start = 0.01
        self.cam = bpy.data.objects.new("cam", cam)
        sc.collection.objects.link(self.cam)
        sc.camera = self.cam
        self._mats = {}

    def _light(self, name, kind, energy, loc, color, size=1.0):
        ld = bpy.data.lights.new(name, kind)
        ld.energy = energy
        ld.color = color
        if kind == "AREA":
            ld.size = size
        ob = bpy.data.objects.new(name, ld)
        ob.location = loc
        self.sc.collection.objects.link(ob)
        d = -np.array(loc)
        # point the light at the origin
        ob.rotation_mode = "QUATERNION"
        from mathutils import Vector
        ob.rotation_quaternion = Vector(tuple(d)).to_track_quat("-Z", "Y")
        return ob

    def _lights(self):
        self._light("key", "AREA", 150, (1.6, -2.0, 1.9), (1.0, 0.93, 0.84), 1.4)
        self._light("fill", "AREA", 70, (-2.2, -1.4, 0.6), (0.78, 0.86, 1.0), 2.2)
        self._light("rimL", "AREA", 120, (-1.4, 2.0, 1.6), (0.9, 0.95, 1.0), 0.9)
        self._light("rimR", "AREA", 90, (1.6, 1.8, 1.0), (1.0, 0.96, 0.9), 0.9)
        self._light("top", "AREA", 50, (0, 0.2, 3.0), (1, 1, 1), 2.0)

    # ------------------------------------------------------------------ materials
    def material(self, kind, texture=None, tint=(1, 1, 1), alpha=False, key=None):
        key = key or (kind, texture, tuple(round(x, 3) for x in tint), alpha)
        if key in self._mats:
            return self._mats[key]
        m = bpy.data.materials.new(str(key)[:60])
        m.use_nodes = True
        nt = m.node_tree
        bs = nt.nodes["Principled BSDF"]
        out = nt.nodes["Material Output"]
        vc = nt.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "Col"
        tintn = nt.nodes.new("ShaderNodeRGB")
        tintn.outputs[0].default_value = (*tint, 1)
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs[0].default_value = 1.0
        nt.links.new(vc.outputs[0], mul.inputs[6])
        nt.links.new(tintn.outputs[0], mul.inputs[7])
        base = mul.outputs[2]
        if texture:
            img = bpy.data.images.load(os.path.abspath(texture), check_existing=True)
            img.alpha_mode = "STRAIGHT"
            tx = nt.nodes.new("ShaderNodeTexImage")
            tx.image = img
            tx.interpolation = "Cubic"
            mul2 = nt.nodes.new("ShaderNodeMix")
            mul2.data_type = "RGBA"
            mul2.blend_type = "MULTIPLY"
            mul2.inputs[0].default_value = 1.0
            nt.links.new(tx.outputs[0], mul2.inputs[6])
            nt.links.new(base, mul2.inputs[7])
            base = mul2.outputs[2]
            if alpha:
                nt.links.new(tx.outputs[1], bs.inputs["Alpha"])
                m.blend_method = "HASHED"
        nt.links.new(base, bs.inputs["Base Color"])
        if kind == "hair":
            bs.inputs["Roughness"].default_value = 0.42
            bs.inputs["Specular IOR Level"].default_value = 0.45
            try:
                bs.inputs["Anisotropic"].default_value = 0.6
            except KeyError:
                pass
            bs.inputs["Coat Weight"].default_value = 0.0
        elif kind == "skin":
            bs.inputs["Roughness"].default_value = 0.5
            bs.inputs["Subsurface Weight"].default_value = 0.12
            bs.inputs["Subsurface Radius"].default_value = (0.05, 0.02, 0.01)
            bs.inputs["Subsurface Scale"].default_value = 0.05
        else:
            bs.inputs["Roughness"].default_value = 0.55
        self._mats[key] = m
        return m

    # ------------------------------------------------------------------ meshes
    def add_mesh(self, md, texture=None, material="plastic", tint=(1, 1, 1), alpha=False, name="mesh",
                 smooth=True):
        P = np.asarray(md["p"], dtype=np.float64).reshape(-1, 3)
        T = np.asarray(md["t"], dtype=np.int64).reshape(-1, 3)
        if md.get("base", None) == 1 or (md.get("base") is None and T.min() >= 1 and T.max() == len(P)):
            T = T - 1
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(p) for p in P], [], [tuple(t) for t in T])
        me.update()
        C = md.get("c")
        U = md.get("uv")
        if C is not None and len(C):
            C = np.asarray(C, dtype=np.float64)
            ch = 4 if len(C) == 4 * len(P) else 3
            C = C.reshape(-1, ch)
        if U is not None and len(U):
            U = np.asarray(U, dtype=np.float64).reshape(-1, 2)
        me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="CORNER")
        if U is not None and len(U):
            me.uv_layers.new(name="UVMap")
        # fetch both only after creating them: adding a layer reallocates the others' data
        col = me.color_attributes["Col"]
        uvl = me.uv_layers["UVMap"] if U is not None and len(U) else None
        A = md.get("a")
        for poly in me.polygons:
            if smooth:
                poly.use_smooth = True
            for li, vi in zip(poly.loop_indices, poly.vertices):
                if uvl is not None:
                    uvl.data[li].uv = (U[vi][0], 1.0 - U[vi][1])
                if C is not None and len(C):
                    c = C[vi]
                    a = c[3] if len(c) == 4 else (A[vi] if A is not None else 1.0)
                    col.data[li].color = (c[0], c[1], c[2], a)
                else:
                    col.data[li].color = (1, 1, 1, 1)
        if md.get("n") is not None and len(md["n"]) == 3 * len(P):
            N = np.asarray(md["n"], dtype=np.float64).reshape(-1, 3)
            try:
                me.normals_split_custom_set_from_vertices([tuple(n) for n in N])
            except Exception:
                pass
        ob = bpy.data.objects.new(name, me)
        ob.parent = self.root
        me.materials.append(self.material(material, texture, tint, alpha))
        self.sc.collection.objects.link(ob)
        return ob

    def add_piece(self, piece, texture=None, tint=(1, 1, 1), offset=(0, 0, 0), scale=(1, 1, 1)):
        P = (np.asarray(piece.P) * np.asarray(scale)) + np.asarray(offset)
        md = {"p": P.ravel(), "t": np.asarray(piece.T).ravel(), "uv": np.asarray(piece.U).ravel(),
              "c": np.asarray(piece.C).ravel(), "n": np.asarray(piece.N).ravel(), "base": 0}
        return self.add_mesh(md, texture=texture, material="hair", tint=tint, alpha=texture is not None,
                             name=piece.name)

    # ------------------------------------------------------------------ camera
    def place_camera(self, view="34", dist=None, focus=None):
        az, el, ds = VIEWS[view] if isinstance(view, str) else view
        f = np.array(focus if focus is not None else self.focus)
        d = (dist or self.dist) * ds
        a, e = math.radians(az), math.radians(el)
        # game space: face toward -Z; camera on the face side at az 0, az + toward the character's right
        cg = f + np.array([math.sin(a) * math.cos(e), math.sin(e), -math.cos(a) * math.cos(e)]) * d
        # game -> Blender: root rotation (x, y, z) -> (-x, z, ... ) computed through the root matrix
        from mathutils import Vector
        bpy.context.view_layer.update()
        M = self.root.matrix_world
        cb = M @ Vector(tuple(cg))
        fb = M @ Vector(tuple(f))
        self.cam.location = cb
        self.cam.rotation_mode = "QUATERNION"
        self.cam.rotation_quaternion = (fb - cb).to_track_quat("-Z", "Y")

    def render(self, path, view="34", dist=None, focus=None):
        self.place_camera(view, dist, focus)
        self.sc.render.filepath = os.path.abspath(path)
        bpy.ops.render.render(write_still=True)
        return path


def sheet(paths, out, cols, labels=None, title=None, cell=None, bg=(26, 27, 30)):
    """Lays renders out in a grid with captions (PIL)."""
    from PIL import Image, ImageDraw, ImageFont
    ims = [Image.open(p).convert("RGB") for p in paths]
    w, h = cell or ims[0].size
    rows = (len(ims) + cols - 1) // cols
    top = 46 if title else 0
    lab = 26 if labels else 0
    W = Image.new("RGB", (cols * w, top + rows * (h + lab)), bg)
    d = ImageDraw.Draw(W)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 17)
        tfont = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
    except OSError:
        font = tfont = ImageFont.load_default()
    if title:
        d.text((12, 11), title, fill=(235, 235, 235), font=tfont)
    for i, im in enumerate(ims):
        r, c = divmod(i, cols)
        x, y = c * w, top + r * (h + lab)
        W.paste(im.resize((w, h)), (x, y))
        if labels:
            d.text((x + 8, y + h + 3), labels[i], fill=(210, 210, 210), font=font)
    W.save(out, quality=90)
    return out


def load_obj(path):
    """OBJ from tools/sim/export_ref.luau: 'o' objects, 'v x y z [r g b]', 'vt u v' (v up), 'f a/b ...'.
    Returns {name: mesh_dict} in the file's space (game head space), uv converted to v-down."""
    objs = {}
    P, C, VT = [], [], []
    cur = None
    for line in open(path):
        if line.startswith("v "):
            f = line.split()
            P.append([float(x) for x in f[1:4]])
            C.append([float(x) for x in f[4:7]] if len(f) >= 7 else [0.8, 0.8, 0.8])
        elif line.startswith("vt "):
            f = line.split()
            VT.append([float(f[1]), float(f[2])])
        elif line.startswith("o "):
            cur = objs.setdefault(line.split(None, 1)[1].strip(), {"faces": []})
        elif line.startswith("f "):
            if cur is None:
                cur = objs.setdefault("mesh", {"faces": []})
            cur["faces"].append([tuple(int(x) if x else 0 for x in (tok.split("/") + ["", ""])[:2])
                                 for tok in line.split()[1:]])
    out = {}
    for name, o in objs.items():
        remap, p, c, uv, t = {}, [], [], [], []
        for face in o["faces"]:
            ids = []
            for vi, ti in face:
                key = (vi, ti)
                if key not in remap:
                    remap[key] = len(p)
                    p.append(P[vi - 1])
                    c.append(C[vi - 1])
                    uv.append([VT[ti - 1][0], 1.0 - VT[ti - 1][1]] if ti else [0.0, 0.0])
                ids.append(remap[key])
            for k in range(1, len(ids) - 1):
                t.append([ids[0], ids[k], ids[k + 1]])
        if t:
            out[name] = {"p": np.ravel(p), "c": np.ravel(c), "uv": np.ravel(uv), "t": np.ravel(t), "base": 0}
    return out


SKIN = (0.42, 0.26, 0.17)  # a mid-brown skin for self-check renders (the head's vertex colours are data)


def add_obj(scene, path, material="skin", tint=SKIN, skip=(), vertex_colors=False):
    obs = []
    for name, md in load_obj(path).items():
        if name in skip:
            continue
        if not vertex_colors:
            md = dict(md, c=None)
            if name.startswith("Eye"):
                md["c"] = np.tile([2.2, 2.2, 2.2], len(md["p"]) // 3)
            elif name.startswith("Mouth") or name.startswith("Lid"):
                md["c"] = np.tile([0.85, 0.75, 0.75], len(md["p"]) // 3)
        obs.append(scene.add_mesh(md, material=material if name in ("Head", "EarL", "EarR") else "plastic",
                                  tint=tint, name=name))
    return obs
