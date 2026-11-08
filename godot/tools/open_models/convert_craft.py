#!/usr/bin/env python3
"""Open-source aircraft, boat and tank -> game vehicles (round 5, vehicle roster).

Sources (all CC0, see art_sources/open_craft/<pack>/License + SOURCE.md; the raw .blend / .glb files are NOT committed):
    heli   "Half-finished Chopper" (OpenGameArt, CC0)          chopper.blend
    plane  "Light Aircraft" (OpenGameArt, CC0)                  light_aircraft_1.blend + its colour textures
    tank   "Heavy Tank [extra low poly, RTS]" (OpenGameArt, CC0) heavy_tank00.glb + nod.png
    boat   Kenney "Watercraft Kit" via OpenGameArt (CC0)        boat-speed-a.glb + colormap.png
Output: godot/assets/models/xv_<id>.glb, the VehicleVisual contract: one mesh "Body" (surfaces Body = the paint, Details, Trim, Glass),
animated parts as their own nodes with the origin on their pivot: heli Rotor / TailRotor, plane Prop, tank Turret. Nose = -Z, up = +Y, the ground at y = 0.
No texture is exported: the textures are sampled per face into flat materials (no texture memory).

Run from godot/ with the tool venv (bpy 5.2):
    .venv-tools/bin/python tools/open_models/convert_craft.py <dir with the downloaded files> [heli plane tank boat]
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.environ.get("QT_MODELS_DIR", os.path.join(GODOT, "assets", "models"))

# role -> (colour linear rgb, roughness, metallic)
ROLES = {
    "Body": ((0.5, 0.5, 0.5), 0.5, 0.2),
    "Details": ((0.045, 0.047, 0.052), 0.6, 0.3),
    "Trim": ((0.62, 0.63, 0.65), 0.5, 0.2),
    "Glass": ((0.05, 0.08, 0.12), 0.12, 0.0),
}


def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


class Tex:
    def __init__(self, path):
        img = bpy.data.images.load(path)
        img.colorspace_settings.name = "Non-Color"
        self.w, self.h = img.size
        self.px = np.array(img.pixels[:], dtype=np.float32).reshape(self.h, self.w, 4)

    def at(self, u, v):
        x = min(self.w - 1, max(0, int((u % 1.0) * self.w)))
        y = min(self.h - 1, max(0, int((v % 1.0) * self.h)))
        return tuple(float(c) for c in self.px[y, x][:3])


class Group:
    """Faces in world space: verts, faces (index tuples into verts), roles, smooth flags."""

    def __init__(self):
        self.v = []
        self.f = []
        self.role = []
        self.smooth = []

    def add_object(self, ob, role_of, tex=None, only=None):
        me = ob.data
        m = ob.matrix_world
        base = len(self.v)
        self.v += [tuple(m @ v.co) for v in me.vertices]
        uv = me.uv_layers.active.data if me.uv_layers.active else None
        for p in me.polygons:
            if only is not None and not only(p, me):
                continue
            col = None
            if tex is not None and uv is not None:
                u = sum(uv[l].uv[0] for l in p.loop_indices) / p.loop_total
                w = sum(uv[l].uv[1] for l in p.loop_indices) / p.loop_total
                col = tex.at(u, w)
            mat = me.materials[p.material_index].name if p.material_index < len(me.materials) and me.materials[p.material_index] else ""
            self.f.append(tuple(base + i for i in p.vertices))
            self.role.append(role_of(mat, col))
            self.smooth.append(p.use_smooth)

    def transform(self, mat):
        self.v = [tuple(mat @ Vector(x)) for x in self.v]

    def bbox(self):
        a = np.array(self.v)
        return a.min(axis=0), a.max(axis=0)


def split_loose(ob):
    """Loose part index of every polygon of ob (union-find over shared vertices) -> list of sets of polygon indices."""
    me = ob.data
    parent = list(range(len(me.vertices)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for p in me.polygons:
        a = find(p.vertices[0])
        for i in p.vertices[1:]:
            b = find(i)
            if a != b:
                parent[b] = a
    parts = {}
    for p in me.polygons:
        parts.setdefault(find(p.vertices[0]), set()).add(p.index)
    return list(parts.values())


def part_bbox(ob, polys):
    me = ob.data
    m = ob.matrix_world
    pts = [m @ me.vertices[i].co for pi in polys for i in me.polygons[pi].vertices]
    a = np.array([tuple(p) for p in pts])
    return a.min(axis=0), a.max(axis=0)


def make_mesh_object(name, g, origin=(0.0, 0.0, 0.0), double_sided_roles=()):
    """Blender object from a Group, vertices re-based on `origin`; one material per role used."""
    if not g.f:
        return None
    verts = [tuple(np.array(x) - np.array(origin)) for x in g.v]
    me = bpy.data.meshes.new(name)
    faces = list(g.f)
    roles = list(g.role)
    smooth = list(g.smooth)
    for i in range(len(g.f)):                                      # thin blades have no back: add a flipped copy so they show from both sides
        if g.role[i] in double_sided_roles:
            faces.append(tuple(reversed(g.f[i])))
            roles.append(g.role[i])
            smooth.append(g.smooth[i])
    me.from_pydata(verts, [], faces)
    used = []
    for r in roles:
        if r not in used:
            used.append(r)
    for r in used:
        me.materials.append(role_material(r))
    for i, p in enumerate(me.polygons):
        p.material_index = used.index(roles[i])
        p.use_smooth = smooth[i]
    me.update()
    me.validate()
    ob = bpy.data.objects.new(name, me)
    ob.location = origin
    bpy.context.scene.collection.objects.link(ob)
    return ob


_mats = {}


def role_material(r):
    if r in _mats:
        return _mats[r]
    col, rough, metal = ROLES[r]
    m = bpy.data.materials.new(r)
    m.use_nodes = True
    m.use_backface_culling = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    _mats[r] = m
    return m


def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()
    ext = os.path.splitext(path)[1].lower()
    if ext == ".blend":
        with bpy.data.libraries.load(path) as (src, dst):
            dst.objects = src.objects
        for o in dst.objects:
            if o is not None and o.type == "MESH":
                bpy.context.scene.collection.objects.link(o)
    else:
        bpy.ops.import_scene.gltf(filepath=path)
    bpy.context.view_layer.update()
    return {o.name: o for o in bpy.context.scene.objects if o.type == "MESH"}


def fit(groups, rot_z_deg, length, ground="min"):
    """Rotate every group about Z (nose to +Y), scale so the total length (Y extent of all groups) is `length`, centre on X/Y, ground at z = 0. Returns (scale, offset) applied."""
    R = Matrix.Rotation(math.radians(rot_z_deg), 4, "Z")
    for g in groups:
        g.transform(R)
    lo = np.min([g.bbox()[0] for g in groups], axis=0)
    hi = np.max([g.bbox()[1] for g in groups], axis=0)
    s = length / (hi[1] - lo[1])
    cx = (lo[0] + hi[0]) * 0.5
    cy = (lo[1] + hi[1]) * 0.5
    T = Matrix.Scale(s, 4) @ Matrix.Translation((-cx, -cy, -lo[2]))
    for g in groups:
        g.transform(T)
    return s


def pivot_of(g, axis_z=None):
    lo, hi = g.bbox()
    c = (lo + hi) * 0.5
    return (float(c[0]), float(c[1]), float(c[2] if axis_z is None else axis_z))


def export(name, objs):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    keep = [o for o in objs if o is not None]
    for o in list(bpy.context.scene.objects):
        if o not in keep:
            bpy.data.objects.remove(o, do_unlink=True)
    for o in keep:
        o.select_set(True)
    path = os.path.join(OUT, "xv_%s.glb" % name)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_texcoords=False, export_yup=True,
                              export_cameras=False, export_lights=False, export_extras=False, export_materials="EXPORT")
    tris = sum(len(p.vertices) - 2 for o in keep for p in o.data.polygons)
    print("wrote", path, os.path.getsize(path), "bytes,", tris, "tris")


# ------------------------------------------------------------------------------------------------------------------------------------------

def heli(src):
    obs = load(os.path.join(src, "chopper", "chopper.blend"))
    ob = obs["Cube.001"]
    parts = split_loose(ob)
    body, rotor, tail, det, glass = Group(), Group(), Group(), Group(), Group()
    for polys in parts:
        lo, hi = part_bbox(ob, polys)
        sub = lambda p, me, polys=polys: p.index in polys
        size = hi - lo
        if lo[2] > 10.0 and size[0] > 20.0:
            tgt, role = rotor, "Details"
        elif size[1] < 0.01 and lo[0] < -25.0:
            tgt, role = tail, "Details"
        elif lo[2] > 7.5 and size[0] < 4.0:
            tgt, role = det, "Details"                         # rotor mast
        elif hi[2] < 0.0 or size[2] < 0.5:
            tgt, role = det, "Details"                         # skids, floor
        elif size[0] > 10.0 and size[1] > 8.0 and lo[0] > -9.0:
            tgt, role = glass, "Glass"                         # the cabin glass shell
        else:
            tgt, role = body, "Body"
        tgt.add_object(ob, lambda mat, col, role=role: role, only=sub)
    # the tail rotor is a single quad: widen it into two crossed blades with thickness so it shows
    s = fit([body, rotor, tail, det, glass], 90.0, 11.0)
    # body keeps glass as a surface of the same mesh
    body.v_off = len(body.v)
    n0 = len(body.v)
    body.v += glass.v
    body.f += [tuple(i + n0 for i in f) for f in glass.f]
    body.role += glass.role
    body.smooth += glass.smooth
    n1 = len(body.v)
    body.v += det.v
    body.f += [tuple(i + n1 for i in f) for f in det.f]
    body.role += det.role
    body.smooth += det.smooth
    rp = pivot_of(rotor)
    tp = pivot_of(tail)
    for objn in list(bpy.context.scene.objects):
        bpy.data.objects.remove(objn, do_unlink=True)
    o_body = make_mesh_object("Body", body)
    o_rot = make_mesh_object("Rotor", rotor, origin=rp, double_sided_roles=("Details",))
    o_tail = make_mesh_object("TailRotor", tail, origin=tp, double_sided_roles=("Details",))
    export("heli", [o_body, o_rot, o_tail])


def plane(src):
    obs = load(os.path.join(src, "lightac", "light_aircraft_1.blend"))
    tex = Tex(os.path.join(src, "lightac", "LightAircraft_TEX_Red.png"))
    wtex = Tex(os.path.join(src, "lightac", "LightAircraftWing_TEX_Red.png"))

    def role_body(mat, col):
        return "Body"

    def role_tex(mat, col):
        if col is None:
            return "Body"
        r, g, b = col
        if b > r + 0.05 and b > 0.7:
            return "Glass"
        if max(col) < 0.35:
            return "Details"
        if min(col) > 0.8:
            return "Trim"
        return "Body"

    body, prop = Group(), Group()
    body.add_object(obs["Body"], role_tex, tex=tex)
    for nm in ("Wing", "Tail", "Ailerons"):
        body.add_object(obs[nm], lambda mat, col: "Body" if mat not in ("Strut",) else "Details", tex=None)
    gear = obs["Landing Gear"]
    body.add_object(gear, lambda mat, col: "Details")
    prop.add_object(obs["Prop"], lambda mat, col: "Details" if mat != "PropCone" else "Trim")
    fit([body, prop], -90.0, 9.6)
    for objn in list(bpy.context.scene.objects):
        bpy.data.objects.remove(objn, do_unlink=True)
    o_body = make_mesh_object("Body", body)
    o_prop = make_mesh_object("Prop", prop, origin=pivot_of(prop))
    export("plane", [o_body, o_prop])


def tank(src):
    obs = load(os.path.join(src, "heavytank", "heavy_tank00.glb"))
    tex = Tex(os.path.join(src, "heavytank", "nod.png"))

    def role_tex(mat, col):
        if col is None:
            return "Body"
        r, g, b = col
        if r > 0.45 and g < 0.2:
            return "Details"
        if max(col) < 0.32:
            return "Details"
        return "Body"

    hull, turret = Group(), Group()
    hull.add_object(obs["chassis"], role_tex, tex=tex)
    turret.add_object(obs["turret"], role_tex, tex=tex)
    fit([hull, turret], 0.0, 8.4)
    # the turret ring: the middle of the turret body, not of the barrel
    lo, hi = turret.bbox()
    body_pts = np.array([v for v in turret.v if v[1] < lo[1] + (hi[1] - lo[1]) * 0.5])
    pv = (float((body_pts[:, 0].min() + body_pts[:, 0].max()) * 0.5), float((body_pts[:, 1].min() + body_pts[:, 1].max()) * 0.5), float(lo[2]))
    for objn in list(bpy.context.scene.objects):
        bpy.data.objects.remove(objn, do_unlink=True)
    o_body = make_mesh_object("Body", hull)
    o_tur = make_mesh_object("Turret", turret, origin=pv)
    export("tank", [o_body, o_tur])


def boat(src):
    obs = load(os.path.join(src, "watercraft", "Models", "GLB format", "boat-speed-a.glb"))
    tex = Tex(os.path.join(src, "watercraft", "Models", "GLB format", "Textures", "colormap.png"))
    (ob,) = obs.values()
    cols = {}

    def role_tex(mat, col):
        cols[tuple(round(c, 2) for c in col)] = cols.get(tuple(round(c, 2) for c in col), 0) + 1
        r, g, b = col
        lum = 0.3 * r + 0.59 * g + 0.11 * b
        if lum < 0.3:
            return "Details"
        if min(col) > 0.82:
            return "Trim"
        return "Body"

    g = Group()
    g.add_object(ob, role_tex, tex=tex)
    print("palette colours of the boat:", sorted(cols.items(), key=lambda kv: -kv[1])[:8])
    lo, hi = g.bbox()
    # the nose is the narrow end: compare the widths of the two ends
    ys = np.array([v[1] for v in g.v])
    xs = np.array([v[0] for v in g.v])
    end_lo = np.ptp(xs[ys < lo[1] + (hi[1] - lo[1]) * 0.15])
    end_hi = np.ptp(xs[ys > hi[1] - (hi[1] - lo[1]) * 0.15])
    fit([g], 0.0 if end_hi < end_lo else 180.0, 5.2)
    for objn in list(bpy.context.scene.objects):
        bpy.data.objects.remove(objn, do_unlink=True)
    o_body = make_mesh_object("Body", g)
    export("boat", [o_body])


MODELS = {"heli": heli, "plane": plane, "tank": tank, "boat": boat}

if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    src = args[0]
    which = args[1:] or list(MODELS)
    for w in which:
        MODELS[w](src)
