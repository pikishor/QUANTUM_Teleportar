#!/usr/bin/env python3
"""Pin the Godot import settings of the generated assets (run after the first `tools/import.sh`, then import again).

  textures  *_albedo / *_orm -> VRAM compressed (ASTC/ETC2 on phones, BC on desktop); *_normal -> VRAM compressed normal map
  audio     *.wav            -> uncompressed PCM16 (exact samples, no decode cost; music loops through its smpl chunk)

Godot writes defaults (lossless textures, QOA audio) into the .import files; the .import files are committed, so this only has to
be run when assets are added.
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def patch(path, changes):
    with open(path) as f:
        text = f.read()
    new = text
    for key, value in changes.items():
        if re.search(r"^%s=" % re.escape(key), new, re.M):
            new = re.sub(r"^%s=.*$" % re.escape(key), "%s=%s" % (key, value), new, flags=re.M)
        else:
            new = new.rstrip("\n") + "\n%s=%s\n" % (key, value)
    if new != text:
        with open(path, "w") as f:
            f.write(new)
        return True
    return False


def main():
    n = 0
    tex = os.path.join(ROOT, "assets", "textures")
    for fn in sorted(os.listdir(tex)):
        if not fn.endswith(".png.import"):
            continue
        ch = {"compress/mode": "2", "compress/high_quality": "false", "mipmaps/generate": "true"}
        if fn.endswith("_normal.png.import"):
            ch["compress/normal_map"] = "1"
        n += patch(os.path.join(tex, fn), ch)
    aud = os.path.join(ROOT, "assets", "audio")
    for fn in sorted(os.listdir(aud)):
        if fn.endswith(".wav.import"):
            n += patch(os.path.join(aud, fn), {"compress/mode": "0"})
    print("patched %d .import files" % n)


if __name__ == "__main__":
    sys.exit(main())
