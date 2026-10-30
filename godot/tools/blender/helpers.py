"""Shared Blender helpers for the Quantum Teleportar model scripts.

Run a model script with the bpy interpreter:  $BLENDER_PY tools/blender/model_player.py
Conventions (see ARCHITECTURE.md): 1 unit = 1 m, origin at ground contact, the model FRONT faces +Y in Blender,
which the glTF exporter (export_yup) turns into -Z in Godot. +X is the model's right, +Z is up.

What lives here
  * material factory (PBR texture sets wired the way the glTF exporter wants them: base colour x factor x vertex colour,
    packed ORM texture, normal map; emissive / glass variants)
  * `Part`: a bmesh accumulator with hard-surface primitives (bevelled boxes, cylinders, spheres, lofts, tubes ...),
    box-projected world-scale UVs, per-part vertex tint and baked vertex ambient occlusion, weighted normals
  * `export_model`: GLB export + post-process that moves textures out of the file (shared files in assets/textures)
"""
import json
import math
import os
import sys

import bpy
import bmesh
from mathutils import Euler, Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
MODELS_DIR = os.environ.get("QT_MODELS_DIR", os.path.join(ROOT, "assets", "models"))
TEX_DIR = os.environ.get("QT_TEX_DIR", os.path.join(ROOT, "assets", "textures"))
sys.path.insert(0, HERE)
import glbtool  # noqa: E402

# metres covered by one texture tile (UVs are world scale so detail stays consistent between parts)
TEX_TILE = {"plating": 0.8, "metal_painted": 0.6, "fabric": 0.35, "carbon": 0.2, "rubber": 0.5,
            "concrete": 2.0, "asphalt": 2.0, "steel": 0.5, "glass": 0.5}
# mean linear albedo of each set (so `paint()` can aim at a final colour)
TEX_MEAN_LIN = {"plating": 0.36, "metal_painted": 0.80, "fabric": 0.56, "carbon": 0.012, "rubber": 0.015,
                "concrete": 0.19, "asphalt": 0.035, "steel": 0.19, "glass": 0.83}


# ------------------------------------------------------------------ colour helpers
def lin(c):
    """sRGB component 0..1 -> linear."""
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexc(h):
    """'#rrggbb' (sRGB) -> linear (r, g, b) tuple."""
    h = h.lstrip("#")
    return tuple(lin(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


def scale_c(c, k):
    return (c[0] * k, c[1] * k, c[2] * k)


# ------------------------------------------------------------------ matrices
def rotm(rx=0.0, ry=0.0, rz=0.0):
    return Euler((math.radians(rx), math.radians(ry), math.radians(rz)), "XYZ").to_matrix().to_4x4()


def xform(pos=(0, 0, 0), rot=(0, 0, 0)):
    return Matrix.Translation(Vector(pos)) @ rotm(*rot)


def frame_z(direction, up=(0, 0, 1)):
    """4x4 rotation whose +Z axis points along `direction` (x axis derived from `up`)."""
    z = Vector(direction).normalized()
    u = Vector(up)
    x = u.cross(z)
    if x.length < 1e-5:
        x = Vector((1, 0, 0)).cross(z)
        if x.length < 1e-5:
            x = Vector((0, 1, 0)).cross(z)
    x.normalize()
    y = z.cross(x)
    m = Matrix.Identity(4)
    for i in range(3):
        m[i][0], m[i][1], m[i][2] = x[i], y[i], z[i]
    return m


# ------------------------------------------------------------------ scene + materials
MATS = {}
_IMAGES = {}


def new_scene():
    global _GLTF_GROUP
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()
    _IMAGES.clear()
    _GLTF_GROUP = None
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0


class Mat:
    def __init__(self, bmat, tile, vcol, name):
        self.bmat, self.tile, self.vcol, self.name = bmat, tile, vcol, name


def _image(name, colorspace):
    if name not in _IMAGES:
        im = bpy.data.images.new(name, 4, 4)       # stand-in: the real PNG in assets/textures is linked by name in glbtool
        im.colorspace_settings.name = colorspace
        _IMAGES[name] = im
    return _IMAGES[name]


_GLTF_GROUP = None


def _gltf_output_group():
    global _GLTF_GROUP
    if _GLTF_GROUP is None or _GLTF_GROUP.name not in bpy.data.node_groups:
        g = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        g.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
        _GLTF_GROUP = g
    return _GLTF_GROUP


def paint(tex, srgb_hex):
    """Colour factor that makes texture set `tex` come out at about the given sRGB colour (clamped to 1)."""
    target = hexc(srgb_hex)
    mean = TEX_MEAN_LIN[tex]
    return tuple(min(1.0, c / mean) for c in target)


def make_material(name, tex=None, color=(1.0, 1.0, 1.0), metallic=0.0, roughness=0.5, emit=None, emit_strength=1.0,
                  alpha=1.0, tile=None, vcol=True, cull=True):
    """Create (or fetch) a material.

    tex      texture-set name from assets/textures (<tex>_albedo/_orm/_normal.png); None = plain factors
    color    linear colour factor multiplied with the albedo texture (use paint() / hexc())
    emit     linear emissive colour (the surface is then black + emission, strength > 1 exports KHR_materials_emissive_strength)
    alpha    < 1 -> blended glass
    tile     metres per texture tile (default per set)
    vcol     multiply by the vertex colour layer (tints + baked AO)
    """
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    m.use_backface_culling = cull
    if tex:
        ta = nt.nodes.new("ShaderNodeTexImage")
        ta.image = _image(tex + "_albedo", "sRGB")
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs["B"].default_value = (color[0], color[1], color[2], 1.0)
        nt.links.new(ta.outputs["Color"], mix.inputs["A"])
        last = mix
        if vcol:
            vc = nt.nodes.new("ShaderNodeVertexColor")
            vc.layer_name = "Col"
            mix2 = nt.nodes.new("ShaderNodeMix")
            mix2.data_type = "RGBA"
            mix2.blend_type = "MULTIPLY"
            mix2.inputs["Factor"].default_value = 1.0
            nt.links.new(mix.outputs["Result"], mix2.inputs["A"])
            nt.links.new(vc.outputs["Color"], mix2.inputs["B"])
            last = mix2
        nt.links.new(last.outputs["Result"], bsdf.inputs["Base Color"])
        to = nt.nodes.new("ShaderNodeTexImage")
        to.image = _image(tex + "_orm", "Non-Color")
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(to.outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
        grp = nt.nodes.new("ShaderNodeGroup")
        grp.node_tree = _gltf_output_group()
        nt.links.new(sep.outputs["Red"], grp.inputs["Occlusion"])
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = _image(tex + "_normal", "Non-Color")
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    else:
        if vcol and emit is None and alpha >= 1.0:
            vc = nt.nodes.new("ShaderNodeVertexColor")
            vc.layer_name = "Col"
            mix2 = nt.nodes.new("ShaderNodeMix")
            mix2.data_type = "RGBA"
            mix2.blend_type = "MULTIPLY"
            mix2.inputs["Factor"].default_value = 1.0
            mix2.inputs["A"].default_value = (color[0], color[1], color[2], 1.0)
            nt.links.new(vc.outputs["Color"], mix2.inputs["B"])
            nt.links.new(mix2.outputs["Result"], bsdf.inputs["Base Color"])
        else:
            bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
    if emit is not None:
        bsdf.inputs["Base Color"].default_value = (0.0, 0.0, 0.0, 1.0)
        bsdf.inputs["Emission Color"].default_value = (emit[0], emit[1], emit[2], 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    else:
        bsdf.inputs["Emission Strength"].default_value = 0.0
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        m.surface_render_method = "BLENDED"
    mat = Mat(m, tile if tile else TEX_TILE.get(tex, 0.5), vcol, name)
    MATS[name] = mat
    return mat


# ------------------------------------------------------------------ raw geometry generators (local coordinates)
def g_box(sx, sy, sz, top=(1.0, 1.0), top_off=(0.0, 0.0)):
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    tx, ty = top
    ox, oy = top_off
    v = [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
         (-hx * tx + ox, -hy * ty + oy, hz), (hx * tx + ox, -hy * ty + oy, hz),
         (hx * tx + ox, hy * ty + oy, hz), (-hx * tx + ox, hy * ty + oy, hz)]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return v, f


def g_cyl(r0, r1, length, segs=12, ry0=None, ry1=None, cap0=True, cap1=True):
    """Cylinder / cone / elliptic cylinder along Z, centred on the origin."""
    ry0 = r0 if ry0 is None else ry0
    ry1 = r1 if ry1 is None else ry1
    v, f = [], []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        v.append((r0 * math.cos(a), ry0 * math.sin(a), -length / 2))
    for i in range(segs):
        a = 2 * math.pi * i / segs
        v.append((r1 * math.cos(a), ry1 * math.sin(a), length / 2))
    for i in range(segs):
        j = (i + 1) % segs
        f.append((i, j, segs + j, segs + i))
    if cap0:
        f.append(tuple(reversed(range(segs))))
    if cap1:
        f.append(tuple(range(segs, 2 * segs)))
    return v, f


def g_sphere(rx, ry, rz, segs=12, rings=8):
    v = [(0, 0, rz), (0, 0, -rz)]
    for r in range(1, rings):
        t = math.pi * r / rings
        z = rz * math.cos(t)
        s = math.sin(t)
        for i in range(segs):
            a = 2 * math.pi * i / segs
            v.append((rx * s * math.cos(a), ry * s * math.sin(a), z))
    f = []
    for i in range(segs):
        j = (i + 1) % segs
        f.append((0, 2 + j, 2 + i))
    for r in range(rings - 2):
        b0 = 2 + r * segs
        b1 = b0 + segs
        for i in range(segs):
            j = (i + 1) % segs
            f.append((b0 + i, b0 + j, b1 + j, b1 + i))
    last = 2 + (rings - 2) * segs
    for i in range(segs):
        j = (i + 1) % segs
        f.append((1, last + i, last + j))
    return v, f


def g_torus(R, r, segs=20, sides=8, rz=None):
    rz = r if rz is None else rz
    v, f = [], []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        for k in range(sides):
            b = 2 * math.pi * k / sides
            rad = R + r * math.cos(b)
            v.append((rad * math.cos(a), rad * math.sin(a), rz * math.sin(b)))
    for i in range(segs):
        i2 = (i + 1) % segs
        for k in range(sides):
            k2 = (k + 1) % sides
            f.append((i * sides + k, i2 * sides + k, i2 * sides + k2, i * sides + k2))
    return v, f


def g_loft(rings, cap0=True, cap1=True):
    """Quads between consecutive rings (each ring: list of (x, y, z), same length), optional fan caps."""
    n = len(rings[0])
    v = [p for ring in rings for p in ring]
    f = []
    for k in range(len(rings) - 1):
        for i in range(n):
            j = (i + 1) % n
            f.append((k * n + i, k * n + j, (k + 1) * n + j, (k + 1) * n + i))
    if cap0:
        f.append(tuple(reversed(range(n))))
    if cap1:
        base = (len(rings) - 1) * n
        f.append(tuple(range(base, base + n)))
    return v, f


def g_poly(pts, depth):
    """Polygon (x, y list, counter clockwise) extruded along Z (centred)."""
    n = len(pts)
    h = depth / 2
    v = [(x, y, -h) for x, y in pts] + [(x, y, h) for x, y in pts]
    f = [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        f.append((i, j, n + j, n + i))
    return v, f


def g_revolve(profile, segs=24, closed=True):
    """Surface of revolution around the local X axis. profile: list of (radius, x). Faces are wound arbitrarily:
    use closed=True so Part._add can recalc outward normals."""
    v = []
    for r, x in profile:
        for i in range(segs):
            a = 2 * math.pi * i / segs
            v.append((x, r * math.cos(a), r * math.sin(a)))
    f = []
    m = len(profile)
    last = m if closed else m - 1
    for j in range(last):
        j2 = (j + 1) % m
        for i in range(segs):
            i2 = (i + 1) % segs
            f.append((j * segs + i, j * segs + i2, j2 * segs + i2, j2 * segs + i))
    return v, f


def ring_se(cx, cy, cz, rx, ry, n=12, exp=2.0, plane="xy"):
    """Super-ellipse ring (exp 2 = ellipse, larger = squarer). plane 'xy' horizontal, 'xz' (facing y), 'yz' (facing x)."""
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        c, s = math.cos(a), math.sin(a)
        u = rx * math.copysign(abs(c) ** (2.0 / exp), c)
        w = ry * math.copysign(abs(s) ** (2.0 / exp), s)
        if plane == "xy":
            pts.append((cx + u, cy + w, cz))
        elif plane == "xz":
            pts.append((cx + u, cy, cz + w))
        else:
            pts.append((cx, cy + u, cz + w))
    return pts


def catmull(points, sub=3):
    """Catmull-Rom resampling of a polyline (list of Vectors) with `sub` extra points per segment."""
    pts = [Vector(p) for p in points]
    if len(pts) < 3 or sub <= 0:
        return pts
    out = []
    ext = [pts[0] * 2 - pts[1]] + pts + [pts[-1] * 2 - pts[-2]]
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for k in range(sub + 1):
            t = k / (sub + 1)
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(pts[-1])
    return out


def tube_rings(points, radii, n=10, up=(0, 0, 1), exp=2.0, sub=3):
    """Rings around a smooth path. radii: scalar or (rx, ry) per control point (interpolated)."""
    ctrl = [Vector(p) for p in points]
    rad = [(r, r) if not isinstance(r, (tuple, list)) else tuple(r) for r in radii]
    path = catmull(ctrl, sub)
    # radius per path point: interpolate along control index
    m = len(path)
    rings = []
    tans = []
    for i in range(m):
        a = path[max(0, i - 1)]
        b = path[min(m - 1, i + 1)]
        t = (b - a)
        tans.append(t.normalized() if t.length > 1e-9 else Vector((0, 0, 1)))
    nrm = Vector(up) - tans[0] * Vector(up).dot(tans[0])
    if nrm.length < 1e-4:
        nrm = Vector((1, 0, 0)) - tans[0] * tans[0].x
    nrm.normalize()
    for i in range(m):
        if i > 0:
            nrm = nrm - tans[i] * nrm.dot(tans[i])
            if nrm.length < 1e-6:
                nrm = Vector((1, 0, 0)).cross(tans[i])
            nrm.normalize()
        bn = tans[i].cross(nrm)
        pos = i / (m - 1) * (len(rad) - 1)
        k = min(int(pos), len(rad) - 2)
        f = pos - k
        rx = rad[k][0] * (1 - f) + rad[k + 1][0] * f
        ry = rad[k][1] * (1 - f) + rad[k + 1][1] * f
        ring = []
        for j in range(n):
            a = 2 * math.pi * j / n
            c, s = math.cos(a), math.sin(a)
            u = rx * math.copysign(abs(c) ** (2.0 / exp), c)
            w = ry * math.copysign(abs(s) ** (2.0 / exp), s)
            p = path[i] + nrm * u + bn * w
            ring.append((p.x, p.y, p.z))
        rings.append(ring)
    return rings


# ------------------------------------------------------------------ Part: accumulating mesh builder
class Part:
    """One exported mesh object. Geometry is kept in world coordinates until build() moves it to `origin`."""

    def __init__(self, name, origin=(0.0, 0.0, 0.0), seed=1):
        self.name = name
        self.origin = Vector(origin)
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.col = self.bm.loops.layers.float_color.new("Col")
        self.slots = []
        self.obj = None
        self.seed = seed
        self._n = 0

    # -- helpers
    def _slot(self, mat):
        if isinstance(mat, str):
            mat = MATS[mat]
        if mat not in self.slots:
            self.slots.append(mat)
        return self.slots.index(mat), mat

    def _rand(self):
        self._n += 1
        x = math.sin(self.seed * 12.9898 + self._n * 78.233) * 43758.5453
        return x - math.floor(x)

    def _add(self, verts, faces, mat, tint, xf, bevel, bsegs, bangle, sharp, mirror, closed, jitter, face_mats=None,
             outward_from=None, flip=False):
        slot, mat = self._slot(mat)
        t = bmesh.new()
        vs = [t.verts.new(xf @ Vector(p)) for p in verts]
        lr = lg = lb = None
        if face_mats is not None:
            lr = t.faces.layers.float.new("tr")
            lg = t.faces.layers.float.new("tg")
            lb = t.faces.layers.float.new("tb")
        for fi, f in enumerate(faces):
            try:
                nf = t.faces.new([vs[i] for i in f])
                if face_mats is not None:
                    fm = face_mats[fi]
                    ft = tint
                    if isinstance(fm, tuple):
                        fm, ft = fm
                    nf.material_index = self._slot(fm)[0]
                    nf[lr], nf[lg], nf[lb] = ft[0], ft[1], ft[2]
            except ValueError:
                pass
        t.verts.index_update()
        t.edges.index_update()
        t.faces.index_update()
        if closed:
            bmesh.ops.recalc_face_normals(t, faces=t.faces[:])
        if os.environ.get("QT_DEBUG") and closed:
            cen = sum((v.co for v in t.verts), Vector()) / max(1, len(t.verts))
            outn = sum(1 for f in t.faces if f.normal.dot(f.calc_center_median() - cen) > 0)
            print("   [debug] closed prim faces=%d outward=%d (%.0f%%)" % (len(t.faces), outn, 100.0 * outn / max(1, len(t.faces))))
        if flip:
            for f in list(t.faces):
                f.normal_flip()
        if outward_from is not None:
            o = Vector(outward_from)
            for f in list(t.faces):
                f.normal_update()
                if f.normal.dot(f.calc_center_median() - o) < 0:
                    f.normal_flip()
        if bevel > 0.0:
            edges = [e for e in t.edges if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(bangle)]
            if edges:
                bmesh.ops.bevel(t, geom=edges, offset=bevel, offset_type="OFFSET", segments=bsegs, profile=0.5,
                                affect="EDGES", clamp_overlap=True, loop_slide=True)
        t.verts.index_update()
        t.edges.index_update()
        k = 1.0 + (self._rand() - 0.5) * 2.0 * jitter if jitter else 1.0
        tcol = (tint[0] * k, tint[1] * k, tint[2] * k)
        off = (self._rand() * 7.0, self._rand() * 7.0)
        lay = (lr, lg, lb) if face_mats is not None else None
        self._merge(t, slot, mat, tcol, sharp, False, off, face_mats is not None, lay)
        if mirror:
            self._merge(t, slot, mat, tcol, sharp, True, off, face_mats is not None, lay)
        t.free()

    def _merge(self, t, slot, mat, tcol, sharp, mirror, off, perface=False, lay=None):
        bm = self.bm
        vmap = {}
        for v in t.verts:
            co = v.co.copy()
            if mirror:
                co.x = -co.x
            vmap[v.index] = bm.verts.new(co)
        for f in t.faces:
            vs = [vmap[v.index] for v in f.verts]
            if mirror:
                vs.reverse()
            try:
                nf = bm.faces.new(vs)
            except ValueError:
                continue
            fslot = self.slots.index(self.slots[f.material_index]) if perface else slot
            fmat = self.slots[fslot]
            tile = fmat.tile
            nf.material_index = fslot
            nf.smooth = True
            nf.normal_update()
            n = nf.normal
            ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
            base = (f[lay[0]], f[lay[1]], f[lay[2]]) if lay else tcol
            fcol = base if fmat.vcol else (1.0, 1.0, 1.0)
            for loop in nf.loops:
                p = loop.vert.co
                if az >= ax and az >= ay:
                    u, w = p.x, p.y
                elif ax >= ay:
                    u, w = p.y, p.z
                else:
                    u, w = p.x, p.z
                loop[self.uv].uv = (u / tile + off[0], w / tile + off[1])
                loop[self.col] = (fcol[0], fcol[1], fcol[2], 1.0)
        thr = math.radians(sharp)
        for e in t.edges:
            a = e.calc_face_angle(None)
            if a is not None and a > thr:
                e2 = bm.edges.get((vmap[e.verts[0].index], vmap[e.verts[1].index]))
                if e2:
                    e2.smooth = False

    def _xf(self, pos, rot, frame):
        return (Matrix.Translation(Vector(pos)) @ (frame if frame is not None else rotm(*rot)))

    # -- primitives ----------------------------------------------------------------------------------
    def box(self, size, pos=(0, 0, 0), rot=(0, 0, 0), mat=None, tint=(1, 1, 1), top=(1.0, 1.0), top_off=(0.0, 0.0),
            bevel=0.0, bsegs=1, bangle=30.0, sharp=50.0, mirror=False, jitter=0.0, frame=None):
        v, f = g_box(size[0], size[1], size[2], top, top_off)
        self._add(v, f, mat, tint, self._xf(pos, rot, frame), bevel, bsegs, bangle, sharp, mirror, True, jitter)

    def cyl(self, r, length, pos=(0, 0, 0), rot=(0, 0, 0), axis="z", mat=None, tint=(1, 1, 1), r2=None, segs=12,
            ry=None, ry2=None, caps=(True, True), bevel=0.0, bsegs=1, bangle=30.0, sharp=50.0, mirror=False,
            jitter=0.0, frame=None):
        v, f = g_cyl(r, r if r2 is None else r2, length, segs, ry, ry2, caps[0], caps[1])
        if frame is None:
            base = {"z": Matrix.Identity(4), "x": rotm(0, 90, 0), "y": rotm(-90, 0, 0)}[axis]
            frame = rotm(*rot) @ base
        self._add(v, f, mat, tint, self._xf(pos, rot, frame), bevel, bsegs, bangle, sharp, mirror, True, jitter)

    def sphere(self, r, pos=(0, 0, 0), rot=(0, 0, 0), mat=None, tint=(1, 1, 1), scale=(1, 1, 1), segs=12, rings=8,
               mirror=False, jitter=0.0, frame=None):
        rr = r if isinstance(r, (tuple, list)) else (r * scale[0], r * scale[1], r * scale[2])
        v, f = g_sphere(rr[0], rr[1], rr[2], segs, rings)
        self._add(v, f, mat, tint, self._xf(pos, rot, frame), 0.0, 1, 30.0, 89.0, mirror, True, jitter)

    def torus(self, R, r, pos=(0, 0, 0), rot=(0, 0, 0), mat=None, tint=(1, 1, 1), segs=20, sides=8, mirror=False,
              jitter=0.0, frame=None, rz=None):
        v, f = g_torus(R, r, segs, sides, rz)
        self._add(v, f, mat, tint, self._xf(pos, rot, frame), 0.0, 1, 30.0, 89.0, mirror, True, jitter)

    def loft(self, rings, mat=None, tint=(1, 1, 1), caps=(True, True), closed=True, mirror=False, bevel=0.0,
             bsegs=1, bangle=30.0, sharp=70.0, jitter=0.0, face_mats=None, outward_from=None, flip=False):
        v, f = g_loft(rings, caps[0], caps[1])
        self._add(v, f, mat, tint, Matrix.Identity(4), bevel, bsegs, bangle, sharp, mirror, closed and caps[0] and caps[1], jitter,
                  face_mats, outward_from, flip)

    def tube(self, points, radii, mat=None, tint=(1, 1, 1), n=10, exp=2.0, up=(0, 0, 1), caps=(True, True), sub=3,
             mirror=False, sharp=75.0, jitter=0.0):
        rings = tube_rings(points, radii, n, up, exp, sub)
        v, f = g_loft(rings, caps[0], caps[1])
        self._add(v, f, mat, tint, Matrix.Identity(4), 0.0, 1, 30.0, sharp, mirror, caps[0] and caps[1], jitter)

    def revolve(self, profile, pos=(0, 0, 0), mat=None, tint=(1, 1, 1), segs=24, closed=True, mirror=False, jitter=0.0,
                sharp=75.0, frame=None, face_mats=None):
        """Revolve (radius, x) profile around the X axis through `pos`."""
        v, f = g_revolve(profile, segs, closed)
        self._add(v, f, mat, tint, self._xf(pos, (0, 0, 0), frame), 0.0, 1, 30.0, sharp, mirror, closed, jitter, face_mats)

    def poly(self, pts, depth, pos=(0, 0, 0), rot=(0, 0, 0), mat=None, tint=(1, 1, 1), bevel=0.0, bsegs=1, bangle=30.0,
             sharp=50.0, mirror=False, jitter=0.0, frame=None):
        v, f = g_poly(pts, depth)
        self._add(v, f, mat, tint, self._xf(pos, rot, frame), bevel, bsegs, bangle, sharp, mirror, True, jitter)

    def raw(self, verts, faces, mat, tint=(1, 1, 1), closed=False, bevel=0.0, bsegs=1, bangle=30.0, sharp=50.0,
            mirror=False, jitter=0.0):
        self._add(verts, faces, mat, tint, Matrix.Identity(4), bevel, bsegs, bangle, sharp, mirror, closed, jitter)

    def bar(self, a, b, w, h, mat=None, tint=(1, 1, 1), up=(0, 0, 1), bevel=0.0, bsegs=1, taper=(1, 1), mirror=False,
            jitter=0.0, sharp=50.0):
        """Box between two points: length a->b, cross-section w (perpendicular to `up`) x h."""
        a, b = Vector(a), Vector(b)
        d = b - a
        fr = frame_z(d, up)
        self.box((w, h, d.length), (a + b) / 2, mat=mat, tint=tint, top=taper, bevel=bevel, bsegs=bsegs, mirror=mirror,
                 jitter=jitter, frame=fr, sharp=sharp)

    def rod(self, a, b, r, mat=None, tint=(1, 1, 1), r2=None, segs=8, caps=(True, True), mirror=False, jitter=0.0,
            bevel=0.0, sharp=60.0):
        a, b = Vector(a), Vector(b)
        d = b - a
        self.cyl(r, d.length, (a + b) / 2, mat=mat, tint=tint, r2=r2, segs=segs, caps=caps, mirror=mirror,
                 jitter=jitter, frame=frame_z(d), bevel=bevel, sharp=sharp)

    # -- finishing -----------------------------------------------------------------------------------
    def vertex_count(self):
        return len(self.bm.verts)

    def tri_count(self):
        if self.obj is not None:
            return self.tris
        return sum(len(f.verts) - 2 for f in self.bm.faces)

    def build(self, weighted=True):
        bm = self.bm
        self.tris = sum(len(f.verts) - 2 for f in bm.faces)
        bmesh.ops.translate(bm, vec=-self.origin, verts=bm.verts)
        bm.normal_update()
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        for m in self.slots:
            mesh.materials.append(m.bmat)
        obj = bpy.data.objects.new(self.name, mesh)
        obj.location = self.origin
        bpy.context.scene.collection.objects.link(obj)
        if weighted:
            mod = obj.modifiers.new("wn", "WEIGHTED_NORMAL")
            mod.mode = "FACE_AREA"
            mod.weight = 50
            mod.keep_sharp = True
            mod.thresh = 0.01
            with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj]):
                bpy.ops.object.modifier_apply(modifier=mod.name)
        self.obj = obj
        return obj


# ------------------------------------------------------------------ ambient occlusion baked into vertex colours
def bake_ao(parts, samples=20, dist=0.3, strength=0.7):
    """Per-vertex AO against the geometry of all `parts` (world space), multiplied into each part's vertex colours."""
    verts, polys, offsets = [], [], []
    for p in parts:
        offsets.append(len(verts))
        p.bm.verts.ensure_lookup_table()
        p.bm.verts.index_update()
        base = len(verts)
        verts.extend([v.co.copy() for v in p.bm.verts])
        for f in p.bm.faces:
            polys.append([base + v.index for v in f.verts])
    tree = BVHTree.FromPolygons(verts, polys, epsilon=0.0)
    dirs = []
    golden = math.pi * (3.0 - math.sqrt(5.0))
    for i in range(samples):
        z = math.sqrt((i + 0.5) / samples)
        r = math.sqrt(max(0.0, 1.0 - z * z))
        dirs.append((r * math.cos(i * golden), r * math.sin(i * golden), z))
    for p in parts:
        bm = p.bm
        bm.normal_update()
        ao = {}
        for v in bm.verts:
            n = v.normal
            if n.length < 0.5:
                ao[v.index] = 1.0
                continue
            t = n.cross(Vector((0, 0, 1)))
            if t.length < 0.1:
                t = n.cross(Vector((1, 0, 0)))
            t.normalize()
            b = n.cross(t)
            org = v.co + n * 0.004
            hit = 0.0
            for d in dirs:
                w = t * d[0] + b * d[1] + n * d[2]
                res = tree.ray_cast(org, w, dist)
                if res[0] is not None:
                    hit += 1.0 - res[3] / dist
            ao[v.index] = 1.0 - strength * hit / samples
        for f in bm.faces:
            if not p.slots[f.material_index].vcol:
                continue
            for loop in f.loops:
                c = loop[p.col]
                k = ao[loop.vert.index]
                loop[p.col] = (c[0] * k, c[1] * k, c[2] * k, 1.0)


def vertex_gradient(part, axis, v0, v1, c0, c1=(1.0, 1.0, 1.0)):
    """Multiply vertex colours by a gradient along a world axis (0/1/2): colour c0 at v0 -> c1 at v1 (grime, fade)."""
    bm = part.bm
    for f in bm.faces:
        if not part.slots[f.material_index].vcol:
            continue
        for loop in f.loops:
            t = (loop.vert.co[axis] - v0) / (v1 - v0)
            t = min(1.0, max(0.0, t))
            t = t * t * (3 - 2 * t)
            k = tuple(c0[i] + (c1[i] - c0[i]) * t for i in range(3))
            c = loop[part.col]
            loop[part.col] = (c[0] * k[0], c[1] * k[1], c[2] * k[2], 1.0)


# ------------------------------------------------------------------ empties and export
def empty(name, pos, rot=(0, 0, 0), display="PLAIN_AXES", size=0.05):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = display
    e.empty_display_size = size
    e.location = pos
    e.rotation_euler = Euler((math.radians(rot[0]), math.radians(rot[1]), math.radians(rot[2])), "XYZ")
    bpy.context.scene.collection.objects.link(e)
    return e


def export_model(name, objects, report=True):
    """Export `objects` as assets/models/<name>.glb (textures referenced from assets/textures)."""
    os.makedirs(MODELS_DIR, exist_ok=True)
    path = os.path.join(MODELS_DIR, name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                              export_image_format="AUTO", export_materials="EXPORT", export_vertex_color="MATERIAL",
                              export_cameras=False, export_lights=False, export_animations=False, export_skins=False,
                              export_morph=False, export_extras=False, export_tangents=False)
    done = glbtool.externalize_images(path, TEX_DIR)
    js, binary = glbtool.read_glb(path)
    leftovers = [i.get("name") for i in js.get("images", []) if "bufferView" in i]
    if leftovers:
        print("WARNING: images without a texture file were left embedded:", leftovers)
    if report:
        lo, hi = glbtool.bounds(js)
        print("MODEL %-14s tris=%-6d size=%6.1f KB textures=%d  bounds x[%.2f,%.2f] y[%.2f,%.2f] z[%.2f,%.2f] (glTF axes, front=-Z)" % (
            name, glbtool.triangle_count(js), os.path.getsize(path) / 1024.0, len(done), lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))
    return path
