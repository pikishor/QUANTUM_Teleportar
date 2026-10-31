"""Shared Blender helpers for the Quantum Teleportar model scripts.

Run a model script with the bpy interpreter:  $BLENDER_PY tools/blender/model_player.py
Conventions (see ARCHITECTURE.md): 1 unit = 1 m, origin at ground contact, the model FRONT faces +Y in Blender,
which the glTF exporter (export_yup) turns into -Z in Godot. +X is the model's right, +Z is up.

What lives here
  * `Mat` / `make_material`: surface kinds. Opaque kinds ("fabric", "plating", "steel", "rubber", "glass", "carbon", "glow", "solid")
    are baked into ONE shared atlas material per model, "paint" into a second neutral atlas (the car body, tinted by its material
    colour), and flat materials (emissive lights) keep constant colours. See atlas.py / shade.py.
  * `Part`: a bmesh accumulator with hard-surface primitives (bevelled boxes, cylinders, spheres, lofts, tubes ...), per-face tint
    colours and weighted normals
  * `export_model`: cull hidden faces, build, bake the atlas, assign materials, export the GLB and move the textures out of it
  * `light` / `empty`: helper empties; a `qt_light` property makes tools/blender/post_import.gd create a real Light3D at import
"""
import json
import math
import os
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Euler, Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
MODELS_DIR = os.environ.get("QT_MODELS_DIR", os.path.join(ROOT, "assets", "models"))
TEX_DIR = os.environ.get("QT_TEX_DIR", os.path.join(ROOT, "assets", "textures"))
sys.path.insert(0, HERE)
import atlas  # noqa: E402
import glbtool  # noqa: E402
import shade  # noqa: E402


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


def paint(tex, srgb_hex):
    """Base albedo of a surface kind from an sRGB hex colour (the baker adds the wear and variation around it)."""
    return hexc(srgb_hex)


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
_PLACEHOLDERS = {}


def new_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()
    _PLACEHOLDERS.clear()
    atlas.reset()
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0


class Mat:
    """A surface kind. group: "atlas" / "paint" (baked textures) or "flat" (constant material in Blender, bmat set)."""

    def __init__(self, name, kind, group, bmat=None, color=(1.0, 1.0, 1.0)):
        self.name, self.kind, self.group, self.bmat, self.color = name, kind, group, bmat, color


def make_material(name, tex=None, color=(1.0, 1.0, 1.0), metallic=0.0, roughness=0.5, emit=None, emit_strength=1.0, alpha=1.0, cull=True):
    """Create (or fetch) a material.

    tex      surface kind baked into the model's atlas ("fabric", "plating", "steel", "rubber", "glass", "carbon", "glow", "solid"),
             or "paint" (a neutral second atlas; `color` is the default colour factor and what vehicles recolour through albedo_color)
    tex=None a flat material that stays separate (draw call!): constant `color` / `emit` (linear; strength > 1 exports
             KHR_materials_emissive_strength) / `alpha` < 1 for blended glass
    """
    if name in MATS:
        return MATS[name]
    if tex in shade.KINDS and tex != "paint":
        m = Mat(name, tex, "atlas")
    elif tex == "paint":
        m = Mat(name, "paint", "paint", color=color)
    else:
        bm = bpy.data.materials.new(name)
        bm.use_nodes = True
        nt = bm.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        bm.use_backface_culling = cull
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
            bm.surface_render_method = "BLENDED"
        m = Mat(name, "flat", "flat", bmat=bm)
    MATS[name] = m
    return m


def _placeholder(mat):
    key = mat.group + ":" + mat.kind
    if key not in _PLACEHOLDERS:
        _PLACEHOLDERS[key] = bpy.data.materials.new("ph_" + key)
    return _PLACEHOLDERS[key]


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
        self.uv = self.bm.loops.layers.uv.new("UVMap")          # filled by the atlas baker
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
            nf.material_index = fslot
            nf.smooth = True
            base = (f[lay[0]], f[lay[1]], f[lay[2]]) if lay else tcol
            for loop in nf.loops:
                loop[self.col] = (base[0], base[1], base[2], 1.0)
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
            mesh.materials.append(m.bmat if m.bmat is not None else _placeholder(m))
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


# ------------------------------------------------------------------ empties, lights and export
def empty(name, pos, rot=(0, 0, 0), display="PLAIN_AXES", size=0.05, matrix=None, props=None):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = display
    e.empty_display_size = size
    e.location = pos
    e.rotation_euler = Euler((math.radians(rot[0]), math.radians(rot[1]), math.radians(rot[2])), "XYZ")
    bpy.context.scene.collection.objects.link(e)
    if matrix is not None:
        e.matrix_world = matrix
    for k, v in (props or {}).items():
        e[k] = v
    return e


def light(name, pos, kind="omni", color=(1.0, 1.0, 1.0), energy=1.0, rng=6.0, direction=None, angle=40.0, mask="world",
          attenuation=1.4, spot_attenuation=1.0, fade=(35.0, 15.0), group="light", size=0.05):
    """A real Light3D created at import (tools/blender/post_import.gd) from this empty.
    mask: "world" lights everything in range, "own" only the model itself (the model's meshes are put on the actor-fill layer),
    so a fill light can lift a character without lighting the street around it. fade = (begin, length) in metres: the light
    fades out and switches off with the camera distance. Spot lights shine along `direction` (a Blender-space vector, front = +Y)."""
    spec = dict(type=kind, color=list(color), energy=energy, range=rng, angle=angle, mask=mask, attenuation=attenuation,
                spot_attenuation=spot_attenuation, fade=list(fade), group=group)
    m = None
    if direction is not None:
        m = Matrix.Translation(Vector(pos)) @ frame_z(direction) @ rotm(90, 0, 0)       # local +Y (glTF -Z) along `direction`
    return empty(name, pos, display="SPHERE" if kind == "omni" else "CONE", size=size, matrix=m, props={"qt_light": json.dumps(spec)})


def tag(obj, **kw):
    """Custom properties the import script understands: vis_end (metres, fade the node out), no_shadow, no_lod."""
    for k, v in kw.items():
        obj["qt_" + k] = v


def export_model(name, parts, extras=(), groups=None, size=1024, decals=(), seed=1, ao_dist=0.3, ao_strength=0.75, max_ppm=900.0,
                 emit_strength=2.0, report=True, cull=True, jpeg=True, normal_scale=1.0):
    """Cull hidden faces, build the parts, bake the atlas, assign the baked materials and export assets/models/<name>.glb.

    parts   Part objects (not yet built); extras: extra Blender objects (empties, lights) to export with them
    groups  {group: dict(base=<texture file prefix>, material=<Blender material name>, emit_strength=.., color=..)} for the baked
            groups; by default one "atlas" group named after the model, plus a "paint" group when a paint material exists.
    """
    if groups is None:
        groups = {"atlas": dict(base=name, material="Gear")}
        if any(m.group == "paint" for p in parts for m in p.slots):
            groups["paint"] = dict(base=name + "_paint", material="Body")
    removed = atlas.cull_hidden(parts) if cull else 0
    objs = [p.build() for p in parts]
    res = atlas.bake(name, parts, groups, TEX_DIR, size=size, decals=decals, seed=seed, ao_dist=ao_dist, ao_strength=ao_strength,
                     max_ppm=max_ppm, emit_gain=1.0, jpeg=jpeg, normal_scale=normal_scale, log=report)
    gmats = {}
    for gname, r in res.items():
        cfg = groups[gname]
        color = cfg.get("color")
        if color is None:
            color = next((m.color for p in parts for m in p.slots if m.group == gname), (1.0, 1.0, 1.0))
        gmats[gname] = atlas.make_baked_material(cfg.get("material", gname), r.base, r.ext, r.has_emit,
                                                 cfg.get("emit_strength", emit_strength), color)
    for p in parts:
        me = p.obj.data
        new_mats, mapping = [], []
        for m in p.slots:
            bm_ = gmats[m.group] if m.group in gmats else m.bmat
            if bm_ not in new_mats:
                new_mats.append(bm_)
            mapping.append(new_mats.index(bm_))
        mi = np.empty(len(me.polygons), np.int32)
        me.polygons.foreach_get("material_index", mi)
        me.polygons.foreach_set("material_index", np.array(mapping, np.int32)[mi])
        me.materials.clear()
        for bm_ in new_mats:
            me.materials.append(bm_)
    objs = objs + list(extras)
    os.makedirs(MODELS_DIR, exist_ok=True)
    path = os.path.join(MODELS_DIR, name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                              export_image_format="AUTO", export_materials="EXPORT", export_vertex_color="NONE",
                              export_cameras=False, export_lights=False, export_animations=False, export_skins=False,
                              export_morph=False, export_extras=True, export_tangents=False)
    done = glbtool.externalize_images(path, TEX_DIR)
    js, binary = glbtool.read_glb(path)
    leftovers = [i.get("name") for i in js.get("images", []) if "bufferView" in i]
    if leftovers:
        print("WARNING: images without a texture file were left embedded:", leftovers)
    if report:
        lo, hi = glbtool.bounds(js)
        surfaces = sum(len(m["primitives"]) for node in js["nodes"] if "mesh" in node for m in [js["meshes"][node["mesh"]]])
        print("MODEL %-14s tris=%-6d surfaces=%-2d size=%6.1f KB textures=%d culled=%d  bounds x[%.2f,%.2f] y[%.2f,%.2f] z[%.2f,%.2f] (glTF axes, front=-Z)" % (
            name, glbtool.triangle_count(js), surfaces, os.path.getsize(path) / 1024.0, len(done), removed, lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))
    return path
