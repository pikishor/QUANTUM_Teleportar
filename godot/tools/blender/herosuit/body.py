"""The Quaternius base body (Universal Base Characters, CC0) as a fitting surface for the hero suit kit.

The suit parts are modelled AGAINST this mesh: every conformal plate, band and ring is built by casting rays at the body, so armour hugs the real muscle shapes (and the
same topology can be re-fitted to the female body). Blender conventions of the whole kit: x = the character's right, y = forward (the front), z = up, metres, feet at z = 0.
The glTF kit space has the front at +Z and the character's left at +X, so  blender = (-x, z, y)  of the kit  (a proper rotation: triangle winding is kept).
"""
import json
import os

import bpy  # noqa: F401  (must be imported before bmesh and mathutils)
import bmesh
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
KIT_DIR = os.path.join(ROOT, "assets_incoming", "characters", "hero")
BONES = ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head", "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "thigh_l", "calf_l", "foot_l", "ball_l", "ball_leaf_l",
         "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r", "thigh_r", "calf_r", "foot_r", "ball_r", "ball_leaf_r"]


def kit_to_blender(p):
    return Vector((-p[0], p[2], p[1]))


def _accessor(d, binf, i):
    a = d["accessors"][i]
    bv = d["bufferViews"][a["bufferView"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    comp = {5126: "f", 5123: "H", 5125: "I", 5121: "B"}[a["componentType"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    return np.frombuffer(binf, dtype=np.dtype(comp).newbyteorder("<"), count=a["count"] * n, offset=off).reshape(a["count"], n)


def _node_globals(d):
    nodes = d["nodes"]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i

    def local(n):
        t = np.eye(4)
        if "matrix" in n:
            return np.array(n["matrix"]).reshape(4, 4).T
        tr = n.get("translation", [0, 0, 0])
        x, y, z, w = n.get("rotation", [0, 0, 0, 1])
        sc = n.get("scale", [1, 1, 1])
        r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)], [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                      [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
        t[:3, :3] = r * np.array(sc)
        t[:3, 3] = tr
        return t

    cache = {}

    def glob(i):
        if i in cache:
            return cache[i]
        t = local(nodes[i])
        if i in parent:
            t = glob(parent[i]) @ t
        cache[i] = t
        return t

    return glob


class Body:
    """The fitting surface: BVH + smooth normals, landmarks, slice centres."""

    def __init__(self, gender="male"):
        self.gender = gender
        path = os.path.join(KIT_DIR, "Superhero_%s_FullBody.gltf" % gender.capitalize())
        d = json.load(open(path))
        binf = open(path.replace(".gltf", ".bin"), "rb").read()
        mesh = max(d["meshes"], key=lambda m: len(_accessor(d, binf, m["primitives"][0]["attributes"]["POSITION"])))
        prim = mesh["primitives"][0]
        pos = _accessor(d, binf, prim["attributes"]["POSITION"]).astype(np.float64)
        idx = _accessor(d, binf, prim["indices"]).reshape(-1, 3).astype(np.int64)
        self.joints_names = [d["nodes"][j]["name"] for j in d["skins"][0]["joints"]]
        self.jv = _accessor(d, binf, prim["attributes"]["JOINTS_0"]).astype(np.int64)
        self.wv = _accessor(d, binf, prim["attributes"]["WEIGHTS_0"]).astype(np.float64)
        self.verts = np.stack([-pos[:, 0], pos[:, 2], pos[:, 1]], axis=1)
        self.tris = idx
        glob = _node_globals(d)
        names = {d["nodes"][j]["name"]: j for j in d["skins"][0]["joints"]}
        self.bone = {}
        for nm in BONES:
            if nm in names:
                g = glob(names[nm])
                self.bone[nm] = kit_to_blender(g[:3, 3])
        self.bm = bmesh.new()
        vs = [self.bm.verts.new(Vector(v)) for v in self.verts]
        for t in idx:
            try:
                self.bm.faces.new((vs[t[0]], vs[t[1]], vs[t[2]]))
            except ValueError:
                pass
        self.bm.verts.ensure_lookup_table()
        self.bm.faces.ensure_lookup_table()
        self.bm.normal_update()
        self.bvh = BVHTree.FromBMesh(self.bm)
        self.height = float(self.verts[:, 2].max())

    # ---- queries ---------------------------------------------------------------------------------------------------------------
    def _smooth_normal(self, face_index, loc):
        f = self.bm.faces[face_index]
        a, b, c = [v.co for v in f.verts]
        v0, v1, v2 = b - a, c - a, loc - a
        d00, d01, d11 = v0.dot(v0), v0.dot(v1), v1.dot(v1)
        d20, d21 = v2.dot(v0), v2.dot(v1)
        den = d00 * d11 - d01 * d01
        if abs(den) < 1e-12:
            return f.normal.copy()
        wv = (d11 * d20 - d01 * d21) / den
        ww = (d00 * d21 - d01 * d20) / den
        wu = 1.0 - wv - ww
        n = f.verts[0].normal * wu + f.verts[1].normal * wv + f.verts[2].normal * ww
        return n.normalized() if n.length > 1e-9 else f.normal.copy()

    def ray(self, origin, direction, maxd=3.0):
        """First hit of the body along the ray: (point, smooth OUTWARD normal) or None (rays from outside and from inside the body both work)."""
        o = Vector(origin)
        d = Vector(direction).normalized()
        loc, nor, fi, dist = self.bvh.ray_cast(o, d, maxd)
        if loc is None:
            return None
        return loc, self._smooth_normal(fi, loc)

    def nearest(self, p):
        loc, nor, fi, dist = self.bvh.find_nearest(Vector(p))
        if loc is None:
            return None
        return loc, self._smooth_normal(fi, loc)

    def slice_center(self, centre, axis, radius, thick=0.01):
        """Mean of the body vertices in a thin disc around `centre` perpendicular to `axis`, within `radius`: where the limb really is."""
        a = np.array(Vector(axis).normalized())
        c = np.array(centre)
        rel = self.verts - c
        along = rel @ a
        perp = rel - np.outer(along, a)
        m = (np.abs(along) < thick) & (np.linalg.norm(perp, axis=1) < radius)
        if m.sum() < 3:
            return Vector(centre)
        p = self.verts[m]
        return Vector(p.mean(axis=0))

    def radius_at(self, centre, axis, dirs, thick=0.012):
        """Distance from `centre` to the surface along each direction of `dirs` (rays from the centre, outward)."""
        out = []
        for d in dirs:
            r = self.ray(centre, d, 1.0)
            out.append(r[0].__sub__(Vector(centre)).length if r else 0.0)
        return out
