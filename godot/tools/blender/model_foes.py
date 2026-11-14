"""The alien and machine bodies of the enemy roster v3 (wave 113): assets/models/foes/<id>.glb, one skinned mesh and a handful of clips each (idle walk run attack hit dead jump). See creaturekit/.
Run:  .venv-tools/bin/python tools/blender/model_foes.py [id ...]     (about 10 s per body)"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "creaturekit"))
import bpy  # noqa: E402
import helpers  # noqa: E402
from helpers import new_scene  # noqa: E402
import lib  # noqa: E402
import species  # noqa: E402

want = [a for a in sys.argv[sys.argv.index("--") + 1:]] if "--" in sys.argv else sys.argv[1:]
outdir = os.path.join(helpers.MODELS_DIR, "foes")
os.makedirs(outdir, exist_ok=True)
t0 = time.time()
made = species.build_all()
for name in list(made.keys()):
    if want and name not in want:
        continue
    new_scene()
    c = species.build_all()[name] if False else made[name]
    arm_obj, mesh_obj = c.build()
    tris = sum(len(p.vertices) - 2 for p in mesh_obj.data.polygons)
    path = os.path.join(outdir, name + ".glb")
    lib.export(arm_obj, mesh_obj, path)
    print("FOE %-14s tris=%d bones=%d clips=%s (%.1fs) %s" % (name, tris, len(c.order), ",".join(c.clips.keys()), time.time() - t0, os.path.getsize(path)))
