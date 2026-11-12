#!/usr/bin/env python3
"""Build assets/models/land_props.glb (the anchors kit of tools/landscape/props.py).
  godot/.venv-tools/bin/python godot/tools/landscape/build_land_props.py [--out-models DIR]
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402

import props  # noqa: E402
from mb import MeshBuilder, write_glb  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-models", default=os.environ.get("QT_MODELS_DIR", os.path.join(ROOT, "assets", "models")))
    a = ap.parse_args()
    meshes = props.build_all()
    for k, m in meshes.items():
        lo, hi = m.bounds()
        print("%-14s tris %4d  size %.1f x %.1f x %.1f" % (k, m.tri_count(), hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]))
    os.makedirs(a.out_models, exist_ok=True)
    size = write_glb(os.path.join(a.out_models, "land_props.glb"), meshes)
    print("land_props.glb %.0f KB" % (size / 1024.0))


if __name__ == "__main__":
    main()
