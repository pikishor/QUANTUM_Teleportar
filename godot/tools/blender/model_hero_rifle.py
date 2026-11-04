"""The hero's rifle (quantum realism): a compact bullpup-style carbine, about 1.5k triangles, built from bevelled boxes and smooth tubes with glowing seam strips.

Blender axes: butt at the origin, the muzzle looks down +Y (glTF -Z), up is +Z, the barrel line is z = 0.012. The vertex colour carries the material in G (1 = glow seam, 0 = metal);
HeroCharacter merges the mesh into the hero's single surface (gear mode) and the hero shader lights the seams with the suit trim colour. Length 0.86 m, no textures, no materials.
Run: tools/blender/build_all.sh hero_rifle   (writes assets/models/hero_rifle.glb)
"""
import math
import os

import bpy
import bmesh
from mathutils import Euler, Matrix, Vector

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models", "hero_rifle.glb")

bpy.ops.wm.read_factory_settings(use_empty=True)
bm = bmesh.new()
col = bm.loops.layers.color.new("Color")


def _paint(faces, glow):
    for f in faces:
        for lp in f.loops:
            lp[col] = (0.0, 1.0 if glow else 0.0, 0.0, 1.0)


def box(size, pos, rot=(0, 0, 0), glow=False, bevel=0.003, taper=None):
    """A bevelled box centred at pos (x right, y forward, z up). taper = (front_scale_x, front_scale_z) narrows the +Y end."""
    before = set(bm.faces)
    r = bmesh.ops.create_cube(bm, size=1.0)
    verts = r["verts"]
    for v in verts:
        if taper is not None and v.co.y > 0:
            v.co.x *= taper[0]
            v.co.z *= taper[1]
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    mat = Matrix.Translation(pos) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=mat, verts=verts)
    if bevel > 0.0:
        edges = list({e for v in verts for e in v.link_edges})
        res = bmesh.ops.bevel(bm, geom=edges, offset=min(bevel, min(size) * 0.3), segments=1, affect="EDGES")
    _paint([f for f in bm.faces if f not in before], glow)


def tube(r, y0, y1, pos=(0, 0, 0), glow=False, segs=16, r1=None):
    """A smooth tube along +Y from y0 to y1 (radius r at the rear, r1 at the front), capped."""
    before = set(bm.faces)
    rr = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r, radius2=r if r1 is None else r1, depth=y1 - y0)
    verts = rr["verts"]
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(pos) + Vector((0, (y0 + y1) * 0.5, 0))) @ Matrix.Rotation(-math.pi / 2, 4, "X"), verts=verts)
    faces = [f for f in bm.faces if f not in before]
    for f in faces:
        f.smooth = abs(f.normal.y) < 0.5
    _paint(faces, glow)


Z = 0.0
# stock and butt
box((0.044, 0.03, 0.115), (0, 0.015, -0.01), bevel=0.006)                     # butt pad
box((0.036, 0.16, 0.085), (0, 0.11, 0.0), taper=(1.0, 0.9), bevel=0.005)       # stock
box((0.03, 0.12, 0.022), (0, 0.13, 0.05), bevel=0.004)                         # cheek riser
box((0.002, 0.08, 0.012), (0.0185, 0.12, 0.0), glow=True, bevel=0.0)           # stock seam (right)
box((0.002, 0.08, 0.012), (-0.0185, 0.12, 0.0), glow=True, bevel=0.0)          # stock seam (left)
# receiver
box((0.06, 0.24, 0.07), (0, 0.29, 0.012), bevel=0.005)                         # upper receiver
box((0.054, 0.2, 0.05), (0, 0.285, -0.048), bevel=0.005)                       # lower receiver
box((0.003, 0.17, 0.008), (0.0305, 0.29, 0.022), glow=True, bevel=0.0)         # receiver seam (right)
box((0.003, 0.17, 0.008), (-0.0305, 0.29, 0.022), glow=True, bevel=0.0)        # receiver seam (left)
box((0.003, 0.06, 0.03), (0.0285, 0.30, -0.05), glow=True, bevel=0.0)          # quantum cell window (right)
box((0.003, 0.06, 0.03), (-0.0285, 0.30, -0.05), glow=True, bevel=0.0)         # quantum cell window (left)
box((0.012, 0.05, 0.012), (0.034, 0.34, 0.03), bevel=0.002)                    # ejection cover
box((0.014, 0.03, 0.014), (-0.036, 0.37, 0.02), bevel=0.003)                   # charging handle
# grip, trigger guard, trigger, magazine
box((0.034, 0.05, 0.11), (0, 0.235, -0.115), rot=(-14, 0, 0), bevel=0.006)     # pistol grip
box((0.002, 0.012, 0.07), (0.0175, 0.236, -0.115), rot=(-14, 0, 0), glow=True, bevel=0.0)
box((0.01, 0.1, 0.012), (0, 0.33, -0.095), bevel=0.003)                        # trigger guard bottom
box((0.01, 0.012, 0.05), (0, 0.38, -0.075), bevel=0.003)                       # trigger guard front
box((0.008, 0.012, 0.03), (0, 0.325, -0.078), rot=(-15, 0, 0), bevel=0.002)    # trigger
box((0.034, 0.06, 0.13), (0, 0.405, -0.13), rot=(8, 0, 0), bevel=0.005)        # magazine
box((0.036, 0.064, 0.025), (0, 0.412, -0.205), rot=(8, 0, 0), bevel=0.004)     # magazine base
box((0.002, 0.03, 0.08), (0.0185, 0.404, -0.13), rot=(8, 0, 0), glow=True, bevel=0.0)    # mag glow slot (right)
box((0.002, 0.03, 0.08), (-0.0185, 0.404, -0.13), rot=(8, 0, 0), glow=True, bevel=0.0)   # mag glow slot (left)
# top rail with teeth, optic
box((0.028, 0.46, 0.012), (0, 0.38, 0.053), bevel=0.002)                       # rail base
for i in range(14):
    box((0.032, 0.014, 0.012), (0, 0.17 + i * 0.031, 0.062), bevel=0.0015)     # rail teeth
tube(0.021, 0.24, 0.35, pos=(0, 0, 0.098))                                      # optic body
tube(0.027, 0.235, 0.255, pos=(0, 0, 0.098))                                    # optic rear ring
tube(0.027, 0.335, 0.355, pos=(0, 0, 0.098))                                    # optic front ring
tube(0.017, 0.354, 0.358, pos=(0, 0, 0.098), glow=True)                         # lens
box((0.012, 0.04, 0.03), (0, 0.29, 0.073), bevel=0.002)                        # optic mount
box((0.012, 0.04, 0.03), (0, 0.31, 0.073), bevel=0.002)
# handguard, barrel, muzzle device
tube(0.033, 0.41, 0.66, pos=(0, 0, 0.012), segs=12)                             # handguard
for i in range(5):
    tube(0.0345, 0.43 + i * 0.045, 0.447 + i * 0.045, pos=(0, 0, 0.012), glow=(i % 2 == 0), segs=12)    # ribs (alternate glowing)
box((0.003, 0.2, 0.01), (0.0345, 0.535, 0.012), glow=True, bevel=0.0)           # handguard seam (right)
box((0.003, 0.2, 0.01), (-0.0345, 0.535, 0.012), glow=True, bevel=0.0)          # handguard seam (left)
box((0.02, 0.1, 0.02), (0, 0.52, -0.036), bevel=0.004)                         # under rail
tube(0.012, 0.66, 0.76, pos=(0, 0, 0.012), segs=12)                             # barrel
tube(0.02, 0.76, 0.86, pos=(0, 0, 0.012), segs=12, r1=0.017)                    # muzzle device
tube(0.0215, 0.78, 0.79, pos=(0, 0, 0.012), glow=True, segs=12)                 # muzzle glow ring
tube(0.0215, 0.835, 0.85, pos=(0, 0, 0.012), segs=12)
box((0.008, 0.025, 0.02), (0, 0.755, 0.04), bevel=0.002)                       # front sight
# sling mounts
box((0.008, 0.02, 0.014), (0.03, 0.03, 0.02), bevel=0.002)
box((0.008, 0.02, 0.014), (-0.03, 0.4, -0.01), bevel=0.002)

me = bpy.data.meshes.new("HeroRifle")
bm.to_mesh(me)
tris = sum(len(p.vertices) - 2 for p in me.polygons)
ob = bpy.data.objects.new("HeroRifle", me)
bpy.context.scene.collection.objects.link(ob)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_apply=True, export_vertex_color="ACTIVE", export_materials="NONE", export_yup=True)
print("MODEL hero_rifle tris=%d" % tris)
