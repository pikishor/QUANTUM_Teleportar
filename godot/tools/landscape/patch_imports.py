#!/usr/bin/env python3
"""Import settings of the landscape assets (the headless import writes lossless textures without mipmaps and auto-generated mesh LODs): run after tools/import.sh, then import again.
  python3 godot/tools/landscape/patch_imports.py
land_*.webp -> VRAM compressed with mipmaps (high quality: foliage alpha edges), land_trees.glb -> no auto LODs, no vertex compression (atlas UVs stay exact)."""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TEX = os.path.join(ROOT, "assets", "textures")
MODELS = os.path.join(ROOT, "assets", "models")


def patch(path, kv):
    s = open(path).read()
    for k, v in kv.items():
        if re.search(r"^%s=" % re.escape(k), s, flags=re.M):
            s = re.sub(r"^%s=.*$" % re.escape(k), "%s=%s" % (k, v), s, flags=re.M)
    open(path, "w").write(s)


n = 0
for fn in sorted(os.listdir(TEX)):
    if fn.startswith("land_") and fn.endswith(".webp.import"):
        hq = "false" if fn.startswith("land_bark") else "true"
        patch(os.path.join(TEX, fn), {"compress/mode": "2", "compress/high_quality": hq, "mipmaps/generate": "true"})
        n += 1
for fn in sorted(os.listdir(MODELS)):
    if fn.startswith("land_") and fn.endswith(".glb.import"):
        patch(os.path.join(MODELS, fn), {"meshes/generate_lods": "false", "meshes/force_disable_compression": "true", "meshes/ensure_tangents": "false", "meshes/create_shadow_meshes": "false"})
        n += 1
print("patched %d .import files" % n)
