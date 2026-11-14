"""The enemy armour kit (wave 113, enemy look v3): helmets, vests, pauldrons, packs, shields and props of 13 human looks fitted to the Quaternius base body, exported as
assets/models/enemy_kit.glb with one mesh node per part and the part data in the glTF extras (bone, kind, zone, looks: see enemykit/lib.py). FoeKit (scripts/roster/foe_kit.gd) merges
the parts of one look into the enemy's single skinned surface, so the armour costs no draw call. UV.x of every part = baked ambient occlusion, UV.y = convex edge wear (no textures).

Run:  tools/blender/build_all.sh enemy_kit
"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "herosuit"))
sys.path.insert(0, os.path.join(HERE, "enemykit"))
import bpy  # noqa: E402
import helpers  # noqa: E402
from helpers import new_scene  # noqa: E402
from herosuit.body import Body  # noqa: E402
from enemykit import lib, parts  # noqa: E402

NAME = "enemy_kit"
t0 = time.time()
new_scene()
body = Body("male")
kit = lib.Kit()
parts.build(kit, body)
looks = sorted({l for p in kit.parts for l in p.props["looks"].split(",") if l != "*"})
print("KIT parts=%d tris=%d (%.1fs)" % (len(kit.parts), kit.tri_count(), time.time() - t0))
for l in looks:
    print("KIT   %-14s tris=%d" % (l, kit.tri_count(l)))
objs = []
ao_sum = 0.0
for p in kit.parts:
    o = p.build()
    o.name = p.props["looks"].split(",")[0].replace("*", "shared") + "__" + p.name
    objs.append(o)
    ao_sum += lib.bake_vertex_data(o, body.bvh)
print("KIT baked vertex data for %d parts, mean AO %.2f (%.1fs)" % (len(objs), ao_sum / max(1, len(objs)), time.time() - t0))
out = os.path.join(helpers.MODELS_DIR, NAME + ".glb")
lib.export(objs, out)
print("MODEL %s parts=%d -> %s (%.1fs)" % (NAME, len(objs), out, time.time() - t0))
