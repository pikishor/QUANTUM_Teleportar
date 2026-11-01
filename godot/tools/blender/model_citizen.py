"""Pedestrian "citizen" (the crowd of the living city): ONE low-poly mesh (about 700 triangles) of a clothed human-alien hybrid with every optional
piece the six archetypes need (hood, long coat tail, backpack, swept crest and visor, umbrella). The crowd shader (assets/shaders/prop_crowd_core.gdshaderinc)
shows the pieces an archetype wears, swings the limbs and tail in the vertex stage and colours the surfaces from a cyber-noir palette, so six silhouettes
cost ONE draw call. No texture: the colour comes from the vertex colours.

Vertex colour contract (COLOR_0, linear values written as given):
  R  surface   0 skin, 0.15 visor / eyes (emissive), 0.3 dark (hair, shoes, gloves, umbrella ribs), 0.5 trousers, 0.7 accent (scarf, bag, trim), 1.0 coat
  G  piece     0 body, 0.1 hood, 0.2 coat tail, 0.3 backpack, 0.4 crest, 0.5 scarf, 0.6 visor   (piece id = round(G * 10), shown per archetype by the shader)
  B  baked shadow 0..1 (hood interior, under the arms, face under the hood, between the legs): multiplies the light
  A  part tag  0 body, 0.2 left leg, 0.4 right leg, 0.6 left arm, 0.8 right arm, 0.9 coat tail, 1.0 umbrella (the walk cycle pivots)
Authored at 1.76 m, origin at the feet, facing +Y in Blender (= -Z in Godot), limb pivots: hips (+-0.1, 0.9), shoulders (+-0.27, 1.42).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: F401,E402
import bmesh  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

import glbtool  # noqa: E402
import helpers  # noqa: E402
from helpers import Part, make_material, new_scene, set_detail  # noqa: E402

new_scene()
set_detail(0.8)
M = make_material("Citizen", color=(0.5, 0.5, 0.5))
chunks = []


def chunk(name, surf, g=0.0, b=1.0, tag=0.0):
    p = Part(name, (0, 0, 0), seed=len(chunks) + 1)
    chunks.append((p, (surf, g, b), tag))
    return p


def cut_front(p, y_min):
    """Delete the faces whose centre lies in front of y_min (an open hood)."""
    doomed = [f for f in p.bm.faces if f.calc_center_median().y > y_min]
    bmesh.ops.delete(p.bm, geom=doomed, context="FACES")


# ------------------------------------------------------------------ legs (tag 0.2 left x < 0, 0.4 right), shoes, hips
for s, tag in ((-1, 0.2), (1, 0.4)):
    x0 = 0.1 * s
    leg = chunk("leg%d" % s, 0.5, 0.0, 0.85, tag)
    leg.tube([(x0, 0.0, 0.93), (x0, 0.015, 0.5), (x0, 0.0, 0.1)], [(0.078, 0.08), (0.064, 0.066), (0.048, 0.05)], mat=M, tint=(0.5, 0.0, 0.85), n=6, exp=2.0, sub=1)
    shoe = chunk("shoe%d" % s, 0.3, 0.0, 1.0, tag)
    shoe.box((0.1, 0.24, 0.085), (x0, 0.04, 0.045), mat=M, tint=(0.3, 0.0, 1.0), top=(0.8, 0.7))
hip = chunk("hip", 0.5, 0.0, 0.8)
hip.tube([(0, 0, 0.84), (0, 0, 0.96)], [(0.185, 0.115), (0.19, 0.12)], mat=M, tint=(0.5, 0.0, 0.8), n=8, sub=0)

# ------------------------------------------------------------------ coat torso, optional long tail, shoulders
coat = chunk("coat", 1.0, 0.0, 1.0)
coat.tube([(0, 0, 0.93), (0, 0, 1.15), (0, 0.005, 1.36), (0, 0.01, 1.5)], [(0.185, 0.115), (0.2, 0.125), (0.215, 0.13), (0.15, 0.1)], mat=M, tint=(1.0, 0.0, 1.0), n=8, exp=2.2, sub=0)
coat.loft([helpers.ring_se(0, 0.0, 1.5, 0.17, 0.11, 8, 2.2, plane="xy"), helpers.ring_se(0, 0.01, 1.57, 0.06, 0.06, 8, 2.0, plane="xy")], mat=M, tint=(1.0, 0.0, 0.9))   # collar
belt = chunk("belt", 0.7, 0.0, 1.0)
belt.tube([(0, 0, 0.935), (0, 0, 0.965)], [(0.192, 0.122), (0.192, 0.122)], mat=M, tint=(0.7, 0.0, 1.0), n=8, sub=0)
tail = chunk("tail", 1.0, 0.2, 0.7, 0.9)
tail.tube([(0, 0, 0.95), (0, -0.01, 0.62), (0, -0.03, 0.34)], [(0.2, 0.128), (0.235, 0.15), (0.27, 0.165)], mat=M, tint=(1.0, 0.2, 0.7), n=6, exp=2.4, sub=0, caps=(False, False))
tail_in = chunk("tail_in", 0.3, 0.2, 0.3, 0.9)
tail_in.tube([(0, 0, 0.95), (0, -0.01, 0.62), (0, -0.03, 0.34)], [(0.19, 0.118), (0.22, 0.14), (0.255, 0.155)], mat=M, tint=(0.3, 0.2, 0.3), n=6, exp=2.4, sub=0, caps=(False, False))
tail_in.bm.faces.ensure_lookup_table()
bmesh.ops.reverse_faces(tail_in.bm, faces=tail_in.bm.faces[:])          # the inside of the coat hem, so the open tail reads as cloth from both sides

# ------------------------------------------------------------------ arms (tags 0.6 left, 0.8 right) with gloves
for s, tag in ((-1, 0.6), (1, 0.8)):
    arm = chunk("arm%d" % s, 1.0, 0.0, 0.8, tag)
    arm.tube([(0.265 * s, 0.0, 1.45), (0.295 * s, 0.01, 1.15), (0.285 * s, 0.05, 0.9)], [(0.062, 0.062), (0.052, 0.052), (0.043, 0.043)], mat=M, tint=(1.0, 0.0, 0.8), n=6, sub=0)
    hand = chunk("hand%d" % s, 0.3, 0.0, 1.0, tag)
    hand.sphere((0.04, 0.045, 0.055), (0.285 * s, 0.055, 0.86), mat=M, tint=(0.3, 0.0, 1.0), segs=5, rings=3)

# ------------------------------------------------------------------ head, hair, face patch, neck, hood, scarf, crest and visor
neck = chunk("neck", 0.0, 0.0, 0.6)
neck.tube([(0, 0.0, 1.5), (0, 0.01, 1.58)], [(0.05, 0.05), (0.048, 0.048)], mat=M, tint=(0.0, 0.0, 0.6), n=6, sub=0)
headc = chunk("head", 0.0, 0.0, 1.0)
headc.sphere((0.092, 0.108, 0.118), (0, 0.01, 1.64), mat=M, tint=(0.0, 0.0, 1.0), segs=8, rings=5)
hair = chunk("hair", 0.3, 0.0, 1.0)
hair.sphere((0.098, 0.113, 0.1), (0, -0.005, 1.675), mat=M, tint=(0.3, 0.0, 1.0), segs=8, rings=4)
cut_front(hair, 0.045)
face = chunk("face", 0.0, 0.0, 0.55)                                                    # under a hood / hair the face is dim: the baked shadow
face.sphere((0.07, 0.05, 0.09), (0, 0.07, 1.62), mat=M, tint=(0.0, 0.0, 0.55), segs=6, rings=4)
brow = chunk("brow", 0.3, 0.0, 0.5)
brow.box((0.15, 0.03, 0.02), (0, 0.108, 1.675), mat=M, tint=(0.3, 0.0, 0.5))
hood = chunk("hood", 1.0, 0.1, 1.0)
hood.sphere((0.135, 0.15, 0.155), (0, -0.01, 1.65), mat=M, tint=(1.0, 0.1, 1.0), segs=8, rings=5)
cut_front(hood, 0.065)
hood_in = chunk("hood_in", 0.3, 0.1, 0.12)
hood_in.sphere((0.125, 0.14, 0.145), (0, -0.01, 1.65), mat=M, tint=(0.3, 0.1, 0.12), segs=8, rings=5)
cut_front(hood_in, 0.055)
bmesh.ops.reverse_faces(hood_in.bm, faces=hood_in.bm.faces[:])
drape = chunk("hood_drape", 1.0, 0.1, 0.9)                                               # the hood's drape over the shoulders
drape.tube([(0, -0.07, 1.62), (0, -0.1, 1.5), (0, -0.07, 1.4)], [(0.15, 0.07), (0.2, 0.1), (0.24, 0.12)], mat=M, tint=(1.0, 0.1, 0.9), n=8, sub=0, caps=(False, False))
scarf = chunk("scarf", 0.7, 0.5, 1.0)
scarf.torus(0.095, 0.034, (0, 0.005, 1.52), mat=M, tint=(0.7, 0.5, 1.0), segs=8, sides=3)
scarf.box((0.07, 0.03, 0.22), (0.05, 0.1, 1.4), rot=(8, 0, -6), mat=M, tint=(0.7, 0.5, 1.0))
visor = chunk("visor", 0.15, 0.6, 1.0)
visor.box((0.15, 0.03, 0.03), (0, 0.108, 1.655), mat=M, tint=(0.15, 0.6, 1.0))
for k, (dy, dz, ex) in enumerate([(0.0, 0.0, 0.0), (-0.06, 0.02, 0.0)]):
    crest = chunk("crest%d" % k, 0.3, 0.4, 1.0)
    crest.rod((0, -0.02 + dy, 1.74 + dz), (0, -0.36 + dy, 1.86 + dz), 0.03, mat=M, tint=(0.3, 0.4, 1.0), r2=0.004, segs=5)
for s in (-1, 1):
    fin = chunk("fin%d" % s, 0.3, 0.4, 1.0)
    fin.rod((s * 0.07, -0.03, 1.7), (s * 0.15, -0.3, 1.78), 0.022, mat=M, tint=(0.3, 0.4, 1.0), r2=0.003, segs=5)

# ------------------------------------------------------------------ backpack and umbrella
bag = chunk("bag", 0.7, 0.3, 1.0)
bag.box((0.27, 0.13, 0.36), (0, -0.175, 1.22), mat=M, tint=(0.7, 0.3, 1.0), top=(0.9, 0.9))
strap = chunk("strap", 0.3, 0.3, 1.0)
for s in (-1, 1):
    strap.box((0.035, 0.26, 0.04), (s * 0.12, -0.03, 1.42), rot=(-30, 0, 0), mat=M, tint=(0.3, 0.3, 1.0))
shaft = chunk("shaft", 0.3, 0.0, 1.0, 1.0)
shaft.cyl(0.012, 0.5, (0, 0, 1.5), mat=M, tint=(0.3, 0.0, 1.0), segs=4, caps=(False, False))
dome = chunk("dome", 0.7, 0.0, 1.0, 1.0)
dome.sphere((0.64, 0.64, 0.14), (0, 0, 1.9), mat=M, tint=(0.7, 0.0, 1.0), segs=8, rings=3)
bmesh.ops.delete(dome.bm, geom=[f for f in dome.bm.faces if f.calc_center_median().z < 1.9], context="FACES")
dome_in = chunk("dome_in", 0.3, 0.0, 0.4, 1.0)
dome_in.sphere((0.62, 0.62, 0.13), (0, 0, 1.9), mat=M, tint=(0.3, 0.0, 0.4), segs=8, rings=3)
bmesh.ops.delete(dome_in.bm, geom=[f for f in dome_in.bm.faces if f.calc_center_median().z < 1.9], context="FACES")
bmesh.ops.reverse_faces(dome_in.bm, faces=dome_in.bm.faces[:])

# ------------------------------------------------------------------ build, colour, join, export
print({p.name: sum(len(f.verts) - 2 for f in p.bm.faces) for p, _, _ in chunks})
objs = []
for p, rgb, tag in chunks:
    if not p.bm.faces:
        continue
    o = p.build(weighted=False)
    me = o.data
    attr = me.color_attributes["Col"]
    n = len(attr.data)
    arr = np.empty((n, 4), np.float32)
    arr[:, :3] = rgb
    arr[:, 3] = tag
    attr.data.foreach_set("color", arr.reshape(-1))
    for poly in me.polygons:
        poly.use_smooth = True
    objs.append(o)
bpy.ops.object.select_all(action="DESELECT")
for o in objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = "Citizen"
body.data.name = "Citizen"
body.data.materials.clear()
body.data.materials.append(M.bmat if M.bmat is not None else helpers._placeholder(M))
tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
os.makedirs(helpers.MODELS_DIR, exist_ok=True)
path = os.path.join(helpers.MODELS_DIR, "citizen.glb")
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True, export_image_format="AUTO",
                          export_materials="EXPORT", export_vertex_color="ACTIVE", export_cameras=False, export_lights=False, export_animations=False,
                          export_skins=False, export_morph=False, export_extras=False, export_tangents=False)
js, _ = glbtool.read_glb(path)
lo, hi = glbtool.bounds(js)
print("MODEL citizen        tris=%-6d size=%6.1f KB  bounds x[%.2f,%.2f] y[%.2f,%.2f] z[%.2f,%.2f] (glTF axes, front=-Z)" % (
    glbtool.triangle_count(js), os.path.getsize(path) / 1024.0, lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))
