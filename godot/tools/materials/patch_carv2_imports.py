#!/usr/bin/env python3
"""Pin the Godot import settings of the Cars v2 assets (run after the first `tools/import.sh` that sees them, then import again):
the two shared textures are VRAM compressed normal maps with mipmaps. (The cv2_*.glb models keep Godot's defaults: no import script, tangents on, engine LODs.)"""
import glob
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CH = {"compress/mode": "2", "compress/high_quality": "false", "compress/normal_map": "1", "mipmaps/generate": "true"}


def main():
    n = 0
    for p in sorted(glob.glob(os.path.join(ROOT, "assets", "textures", "carv2_*.png.import"))):
        text = open(p).read()
        new = text
        for k, v in CH.items():
            new = re.sub(r"^%s=.*$" % re.escape(k), "%s=%s" % (k, v), new, flags=re.M)
        if new != text:
            open(p, "w").write(new)
            base = os.path.basename(p)[:-len(".import")]
            for f in glob.glob(os.path.join(ROOT, ".godot", "imported", base + "-*")):
                os.remove(f)
            n += 1
    print("patched %d .import files" % n)


if __name__ == "__main__":
    main()
