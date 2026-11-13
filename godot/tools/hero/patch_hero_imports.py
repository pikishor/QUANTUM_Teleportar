#!/usr/bin/env python3
"""Pins the Godot import settings of the hero's textures (run after the first `tools/import.sh` that sees new files, then import again): VRAM compression (ASTC on phones, BPTC
on desktop) with mipmaps, in HIGH QUALITY for colour and normal maps, normal-map flag for normals. Covers the suit kit atlas (assets/textures/hero_suit_*) and the Quaternius skin / hair /
eye maps (assets_incoming/characters/hero/*.png), which were imported lossless without mipmaps: 48 MB of GPU memory and shimmering at a distance, now about 11 MB with mipmaps (skin colour in
DXT1 / ETC2, the body normal maps at 1K, everything else in high quality ASTC / BPTC); the APK grows by about 6 MB for all of it (ASTC 4x4 everywhere would have been +26 MB).
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
        is_orm = "_orm" in name
        is_skin = re.match(r"hero_(male|female)_(dark|light)\.png\.import$", name) is not None
        ch = {"compress/mode": "2", "compress/high_quality": "false" if (is_orm or is_skin) else "true", "mipmaps/generate": "true"}   # skin colour: DXT1 / ETC2 (half the bytes of BPTC / ASTC, smooth gradients survive it)
        if re.match(r"hero_(male|female)_normal\.png\.import$", name):
            ch["process/size_limit"] = "1024"                   # the 2K body normal map: 1K is plenty for a hero seen at 3 m and saves 4 MB of the APK and of the GPU memory per body
        if "_rough" in name:                                   # RGBA data (R roughness, G / B / A the suit mask): the alpha is not transparency, keep every texel exactly
            ch["process/fix_alpha_border"] = "false"
            ch["process/premult_alpha"] = "false"
        if "normal" in name:
            ch["compress/normal_map"] = "1"
        if patch(p, ch):
            purge(p)
            n += 1
    print("patched %d hero texture imports" % n)


main()
