#!/usr/bin/env python3
"""Pin the Godot import settings of the generated assets (run after the first `tools/import.sh`, then import again).

  models    *.glb            -> import script tools/blender/post_import.gd (lights, light layers, visibility ranges, shadow flags)
  textures  *_albedo/_orm/_emit (png or jpg) -> VRAM compressed (ASTC/ETC2 on phones, BC on desktop), mipmaps
            *_normal.png   -> VRAM compressed normal map
  audio     *.wav            -> uncompressed PCM16 (exact samples, no decode cost; music loops through its smpl chunk)

Godot writes defaults (lossless textures, QOA audio, no import script) into the .import files; the .import files are committed, so this
only has to be run when assets are added. A changed .import file alone does not always trigger a reimport, so the cached import of every
patched asset is deleted (.godot/imported/<file>-*) and the next `tools/import.sh` rebuilds it.
"""
import glob
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
IMPORT_SCRIPT = '"res://tools/blender/post_import.gd"'


def patch(path, changes):
    with open(path) as f:
        text = f.read()
    new = text
    for key, value in changes.items():
        if re.search(r"^%s=" % re.escape(key), new, re.M):
            new = re.sub(r"^%s=.*$" % re.escape(key), lambda m, k=key, v=value: "%s=%s" % (k, v), new, flags=re.M)
        else:
            new = new.rstrip("\n") + "\n%s=%s\n" % (key, value)
    if new != text:
        with open(path, "w") as f:
            f.write(new)
        return True
    return False


def purge(import_path):
    """Forget the cached import of the asset this .import file belongs to, so the next import redoes it."""
    base = os.path.basename(import_path)[:-len(".import")]
    for f in glob.glob(os.path.join(ROOT, ".godot", "imported", base + "-*")):
        os.remove(f)


def main():
    n = 0
    tex = os.path.join(ROOT, "assets", "textures")
    for fn in sorted(os.listdir(tex)):
        if not (fn.endswith(".png.import") or fn.endswith(".jpg.import")):
            continue
        ch = {"compress/mode": "2", "compress/high_quality": "false", "mipmaps/generate": "true"}
        if fn.endswith("_normal.png.import"):
            ch["compress/normal_map"] = "1"
        p = os.path.join(tex, fn)
        if patch(p, ch):
            purge(p)
            n += 1
    mdl = os.path.join(ROOT, "assets", "models")
    for fn in sorted(os.listdir(mdl)):
        if fn.endswith(".glb.import"):
            p = os.path.join(mdl, fn)
            if patch(p, {"import_script/path": IMPORT_SCRIPT}):
                purge(p)
                n += 1
    aud = os.path.join(ROOT, "assets", "audio")
    for fn in sorted(os.listdir(aud)):
        if fn.endswith(".wav.import"):
            p = os.path.join(aud, fn)
            if patch(p, {"compress/mode": "0"}):
                purge(p)
                n += 1
    print("patched %d .import files" % n)


if __name__ == "__main__":
    sys.exit(main())
