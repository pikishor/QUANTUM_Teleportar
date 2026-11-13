#!/usr/bin/env python3
"""Pins the Godot import settings of the hero's textures (run after the first `tools/import.sh` that sees new files, then import again): VRAM compression (ASTC on phones, BPTC
on desktop) with mipmaps, in HIGH QUALITY for colour and normal maps, normal-map flag for normals. Covers the suit kit atlas (assets/textures/hero_suit_*) and the Quaternius skin / hair /
eye maps (assets_incoming/characters/hero/*.png), which were imported lossless without mipmaps: 48 MB of GPU memory and shimmering at a distance, now about 17 MB with mipmaps.
  python3 -I tools/hero/patch_hero_imports.py        (from godot/)
The cached import of every patched file is deleted so that the next `tools/import.sh` redoes it. Idempotent."""
import glob
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def patch(path, changes):
    text = open(path).read()
    new = text
    for key, value in changes.items():
        if re.search(r"^%s=" % re.escape(key), new, re.M):
            new = re.sub(r"^%s=.*$" % re.escape(key), lambda m, k=key, v=value: "%s=%s" % (k, v), new, flags=re.M)
        else:
            new = new.rstrip("\n") + "\n%s=%s\n" % (key, value)
    if new != text:
        open(path, "w").write(new)
        return True
    return False


def purge(import_path):
    base = os.path.basename(import_path)[:-len(".import")]
    for f in glob.glob(os.path.join(ROOT, ".godot", "imported", base + "-*")):
        os.remove(f)


def main():
    n = 0
    files = sorted(glob.glob(os.path.join(ROOT, "assets", "textures", "hero_suit_*.import")) + glob.glob(os.path.join(ROOT, "assets_incoming", "characters", "hero", "*.png.import")))
    for p in files:
        name = os.path.basename(p)
        if not (name.endswith(".png.import") or name.endswith(".jpg.import")):
            continue
        is_rough_or_orm = "_rough" in name or "_orm" in name
        ch = {"compress/mode": "2", "compress/high_quality": "false" if is_rough_or_orm else "true", "mipmaps/generate": "true"}
        if "normal" in name:
            ch["compress/normal_map"] = "1"
        if patch(p, ch):
            purge(p)
            n += 1
    print("patched %d hero texture imports" % n)


main()
