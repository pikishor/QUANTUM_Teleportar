#!/usr/bin/env python3
"""Pack CC0 PBR sets (ambientCG / Poly Haven naming) from assets_incoming/<kind>[_n]/ into assets/textures.
Per set: scanned_<kind>_albedo.png, scanned_<kind>_normal.png (OpenGL), scanned_<kind>_orm.png (R=AO, G=roughness, B=0 metal; metal kind gets B=1)
at --size 1024|2048, plus _half variants (LOW-tier halving). Usage: import_scanned.py [--src DIR] [--out DIR] [--size 2048]"""
import argparse, os, sys
from PIL import Image
KINDS = ("asphalt", "concrete", "metal", "brick", "tile")
SUF = {"color": ("_color", "_albedo", "_basecolor", "_diff"), "normal": ("_normalgl", "_normal_gl", "_nor_gl"),
       "rough": ("_roughness", "_rough"), "ao": ("_ambientocclusion", "_ao"), "disp": ("_displacement", "_height", "_disp")}
EXT = (".png", ".jpg", ".jpeg", ".exr")


def find(folder, role):
    for f in sorted(os.listdir(folder)):
        stem, ext = os.path.splitext(f.lower())
        if ext in EXT and any(stem.endswith(s) for s in SUF[role]):
            return os.path.join(folder, f)
    return None


def load(path, size, mode):
    if path is None:
        return None
    return Image.open(path).convert(mode).resize((size, size), Image.LANCZOS)


def kind_of(name):
    n = name.lower()
    for k in KINDS:
        if n.startswith(k) or k in n:
            return k
    return {"road": "asphalt", "pavingstones": "tile", "tiles": "tile", "bricks": "brick", "plaster": "concrete"}.get(n.rstrip("0123456789_"), None)


def process(folder, kind, size, out):
    col = load(find(folder, "color"), size, "RGB")
    if col is None:
        print("skip %s: no *_Color" % folder); return False
    nrm = load(find(folder, "normal"), size, "RGB") or Image.new("RGB", (size, size), (128, 128, 255))
    rough = load(find(folder, "rough"), size, "L") or Image.new("L", (size, size), 200)
    ao = load(find(folder, "ao"), size, "L") or Image.new("L", (size, size), 255)
    metal = Image.new("L", (size, size), 255 if kind == "metal" else 0)
    orm = Image.merge("RGB", (ao, rough, metal))
    for sz, tag in ((size, ""), (size // 2, "_half")):
        for img, nm in ((col, "albedo"), (nrm, "normal"), (orm, "orm")):
            im = img if sz == size else img.resize((sz, sz), Image.LANCZOS)
            im.save(os.path.join(out, "scanned_%s_%s%s.png" % (kind, nm, tag)))
    print("packed %s -> %s at %d" % (os.path.basename(folder), kind, size)); return True


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.normpath(os.path.join(here, "..", ".."))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets_incoming"))
    ap.add_argument("--out", default=os.path.join(root, "assets", "textures"))
    ap.add_argument("--size", type=int, default=2048, choices=(1024, 2048))
    a = ap.parse_args()
    if not os.path.isdir(a.src):
        print("no incoming folder, nothing to do (procedural fallback stays)"); return 0
    os.makedirs(a.out, exist_ok=True)
    done = 0
    for d in sorted(os.listdir(a.src)):
        p = os.path.join(a.src, d)
        if os.path.isdir(p):
            k = kind_of(d)
            if k is None:
                print("skip %s: name must contain one of %s" % (d, KINDS)); continue
            done += process(p, k, a.size, a.out)
    print("%d set(s) packed" % done); return 0


if __name__ == "__main__":
    sys.exit(main())
