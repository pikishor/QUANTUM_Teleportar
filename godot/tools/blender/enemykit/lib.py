"""Kit bookkeeping and geometry helpers of the enemy armour kit (wave 113, enemy look v3).

A kit PART is one helpers.Part (one exported mesh node). Its custom properties (glTF extras, read by scripts/roster/foe_kit.gd):
  bone   the source skeleton bone it is rigidly weighted to (spine_02, upperarm_l, Head, Rifle ...)  or  "chain:Sec1,Sec2,Sec3" for cloth that trails the motion (weights by height)
  kind   palette slot of scripts/roster/foe_kit.gd / assets/shaders/foe_body.gdshader (see K below)
  zone   glow zone (see Z): 1 visor, 2 weak point, 3 health pips, 4 telegraph (weapon / tell), 5 trim light, 6 jet
  looks  comma separated look ids the part belongs to ("*" = every look)
Vertex data: UV.x = baked ambient occlusion (1 = open), UV.y = convex edge wear (1 = a bright worn edge); neither needs a texture.
Blender axes of the whole kit: x = the character's right, y = forward, z = up, metres, feet at z = 0 (the exporter turns +Y into glTF -Z), exactly like the hero suit kit.
Parts that exist on both sides are built once on the right (+x) with mirror=True and split by the sign of x into NAME_r / NAME_l (herosuit/kitlib.split_lr).
"""
import math
import os
import sys

import bmesh
import bpy  # noqa: F401
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
BL = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, BL)
sys.path.insert(0, os.path.join(BL, "herosuit"))
import helpers  # noqa: E402
from helpers import Part  # noqa: E402
from kitlib import split_lr  # noqa: E402

# palette slots (COLOR.b x 16 of the merged mesh, FoeKit.KIND_*)
K_PLATE_A, K_PLATE_B, K_TRIM, K_DARK, K_RUBBER, K_FABRIC_A, K_FABRIC_B, K_GLASS, K_GLOW, K_BRASS, K_CLOTH, K_MARK, K_HAZARD, K_STEEL, K_POLY = range(1, 16)
# glow zones (COLOR.a, FoeKit.ZONE_*)
Z_NONE, Z_VISOR, Z_WEAK, Z_PIPS, Z_TELL, Z_TRIM, Z_JET = range(7)

R = math.radians


class Kit:
    def __init__(self):
        self.parts = []
        self.mat = helpers.make_material("enemy_kit", color=(0.5, 0.5, 0.5))

    def new(self, name):
        return Part(name, seed=3 + len(self.parts) * 5)

    def done(self, part, bone, kind, zone=0, looks="*", lr=False, chain=None):
        """Registers `part`. lr=True: it was built on the right with mirror=True; the bone name must end in `_r` (the left twin gets `_l`)."""
        if part.vertex_count() == 0:
            return
        if lr:
            right, left = split_lr(part)
            for side, p in (("r", right), ("l", left)):
                if p.vertex_count() == 0:
                    continue
                self._finish(p, bone[:-2] + "_" + side if bone.endswith("_r") else bone, kind, zone, looks, chain)
        else:
            self._finish(part, bone, kind, zone, looks, chain)

    def _finish(self, p, bone, kind, zone, looks, chain):
        p.props["bone"] = bone
        p.props["kind"] = int(kind)
        p.props["zone"] = int(zone)
        p.props["looks"] = looks
        if chain is not None:                                   # cloth on the Sec1-3 chain: three pivots "x,y,z;x,y,z;x,y,z" in MODEL space (x right, y up, z back) and the parent bone
            p.props["chain_pos"] = ";".join("%.4f,%.4f,%.4f" % (c[0], c[2], -c[1]) for c in chain["pos"])
            p.props["chain_parent"] = chain.get("parent", "spine_02")
            p.props["bone"] = "chain:Sec1,Sec2,Sec3"
        self.parts.append(p)

    def tri_count(self, look=None):
        n = 0
        for p in self.parts:
            ls = p.props["looks"].split(",")
            if look is None or "*" in ls or look in ls:
                n += p.tri_count()
        return n


# ------------------------------------------------------------------------------------------------------------------------------------------------
# geometry helpers: surfaces of revolution (helmets, caps, hats), open shells, strips
# ------------------------------------------------------------------------------------------------------------------------------------------------

def lathe(p, mat, profile, center=(0, 0, 0), sx=1.0, sy=1.0, segs=14, tint=(1, 1, 1), bevel=0.0, sharp=70.0, closed=False, tilt=0.0, zskew=None):
    """A surface of revolution about the vertical axis through `center`, elliptic cross section (sx, sy). profile = [(radius, z), ...] relative to the centre; the OUTSIDE is on the RIGHT of the
    direction of travel with r to the right and z up (a dome: from the rim up over the top; a closed ring: counter clockwise). tilt (radians) pitches the whole shape about x (+ = nose down).
    zskew(r, a) adds to z (a peak, a back flare). Returns nothing; the shell is added to `p`."""
    verts, faces = [], []
    n = len(profile)
    cx, cy, cz = center
    ct, st = math.cos(tilt), math.sin(tilt)
    for k, (r, z) in enumerate(profile):
        for j in range(segs):
            a = 2.0 * math.pi * j / segs
            x = r * sx * math.cos(a)
            y = r * sy * math.sin(a)
            zz = z + (zskew(r, a) if zskew else 0.0)
            yy = y * ct - zz * st
            z2 = y * st + zz * ct
            verts.append((cx + x, cy + yy, cz + z2))
    for k in range(n - 1):
        for j in range(segs):
            a = k * segs + j
            b = k * segs + (j + 1) % segs
            c = (k + 1) * segs + (j + 1) % segs
            d = (k + 1) * segs + j
            faces.append((a, b, c, d))
    p.raw(verts, faces, p_mat(p), tint, closed=closed, bevel=bevel, bsegs=1, bangle=40.0, sharp=sharp)


def p_mat(p):
    return helpers.MATS["enemy_kit"]


def arc_profile(r0, z0, r1, z1, bulge=0.0, n=5):
    """Points on a gentle arc from (r0, z0) to (r1, z1); bulge > 0 pushes the middle outward (radially)."""
    out = []
    for i in range(n + 1):
        t = i / n
        out.append((r0 + (r1 - r0) * t + bulge * math.sin(math.pi * t), z0 + (z1 - z0) * t))
    return out


def dome_profile(rim_r, rim_z, top_z, n=6, power=1.0, start=0.0):
    """From the rim (rim_r at rim_z) up over a rounded top to the pole at top_z. Ellipse arc (quarter), `start` raises the starting angle."""
    out = []
    for i in range(n + 1):
        t = math.radians(90.0 * (1.0 - i / n)) if True else 0.0
        t = math.radians(start + (90.0 - start) * (1.0 - i / n))
        out.append((rim_r * math.sin(t) ** power if i < n else 0.0, rim_z + (top_z - rim_z) * math.cos(t) if i < n else top_z))
    out[-1] = (0.0, top_z)
    return out


def box(p, size, pos, rot=(0, 0, 0), bevel=0.006, kind_tint=(1, 1, 1), top=(1.0, 1.0), mirror=False, bsegs=1, bangle=30.0):
    # a bevel quadruples the triangles of a box (12 -> 44): only boxes that are big enough to show it get one
    if min(size) < 0.034 or max(size) < 0.075:
        bevel = 0.0
    elif min(size) < 0.06:
        bevel = min(bevel, 0.004)
    p.box(size, pos, rot, mat=p_mat(p), tint=kind_tint, top=top, bevel=bevel, bsegs=bsegs, bangle=bangle, mirror=mirror)


def cyl(p, r, length, pos, rot=(0, 0, 0), axis="z", r2=None, segs=10, bevel=0.0, mirror=False, caps=(True, True), ry=None, ry2=None):
    p.cyl(r, length, pos, rot, axis=axis, mat=p_mat(p), r2=r2, segs=segs, bevel=bevel, mirror=mirror, caps=caps, ry=ry, ry2=ry2)


def sphere(p, r, pos, scale=(1, 1, 1), segs=10, rings=6, mirror=False, rot=(0, 0, 0)):
    p.sphere(r, pos, rot, mat=p_mat(p), scale=scale, segs=segs, rings=rings, mirror=mirror)


def rod(p, a, b, r, r2=None, segs=6, mirror=False, caps=(True, True)):
    p.rod(a, b, r, mat=p_mat(p), r2=r2, segs=segs, caps=caps, mirror=mirror)


def bar(p, a, b, w, h, up=(0, 0, 1), bevel=0.004, taper=(1, 1), mirror=False):
    p.bar(a, b, w, h, mat=p_mat(p), up=up, bevel=bevel, taper=taper, mirror=mirror)


# ------------------------------------------------------------------------------------------------------------------------------------------------
# vertex data: ambient occlusion and edge wear, baked with rays (no texture)
# ------------------------------------------------------------------------------------------------------------------------------------------------

def _fib_dirs(n):
    out = []
    ga = math.pi * (3.0 - math.sqrt(5.0))
    for i in range(n):
        u = (i + 0.5) / n
        r = math.sqrt(u)                       # cosine weighted
        th = ga * i
        out.append((r * math.cos(th), r * math.sin(th), math.sqrt(max(0.0, 1.0 - u))))
    return out


DIRS = _fib_dirs(14)


def bake_vertex_data(obj, body_bvh, max_d=0.2, strength=0.85):
    """UV.x = ambient occlusion (rays against the part itself and the body), UV.y = convex edge wear. Writes both into the UV layer of `obj` (one value per vertex, all loops)."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    bm.normal_update()
    own = BVHTree.FromBMesh(bm)
    ao = []
    edge = []
    for v in bm.verts:
        n = v.normal.copy()
        if n.length < 1e-6:
            n = Vector((0, 0, 1))
        n.normalize()
        o = v.co + n * 0.004
        t1 = n.cross(Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((1, 0, 0))).normalized()
        t2 = n.cross(t1)
        occ = 0.0
        for d in DIRS:
            dv = t1 * d[0] + t2 * d[1] + n * d[2]
            best = max_d
            h = own.ray_cast(o, dv, max_d)
            if h[0] is not None:
                best = min(best, h[3])
            if body_bvh is not None:
                h2 = body_bvh.ray_cast(o, dv, max_d)
                if h2[0] is not None:
                    best = min(best, h2[3])
            if best < max_d:
                occ += 1.0 - best / max_d
        a = 1.0 - strength * occ / len(DIRS)
        ao.append(min(1.0, max(0.0, a)))
        e = 0.0
        for ed in v.link_edges:
            if len(ed.link_faces) == 2:
                ang = ed.calc_face_angle_signed(0.0)
                if ang > 0.0:
                    e = max(e, ang)
        edge.append(min(1.0, e / 1.1))
    bm.free()
    uvl = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
    for li, loop in enumerate(me.loops):
        uvl.data[li].uv = (ao[loop.vertex_index], edge[loop.vertex_index])
    return float(np.mean(ao))


def body_bvh(body):
    return body.bvh


def export(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True, export_materials="NONE", export_extras=True,
                              export_cameras=False, export_lights=False, export_animations=False, export_skins=False, export_morph=False, export_texcoords=True,
                              export_vertex_color="ACTIVE")
