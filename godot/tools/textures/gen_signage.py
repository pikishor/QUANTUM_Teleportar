#!/usr/bin/env python3
"""Reproducible neon-sign glyph atlas and word tables for the city's signage (numpy + Pillow only, no randomness).

  python3 tools/textures/gen_signage.py [--out assets/textures] [--shader assets/shaders/signage_words.gdshaderinc]
  python3 tools/textures/gen_signage.py --patch-imports        (after tools/import.sh created the .import file: lossless, mipmaps on)

Font design ("alien-latin"): a monoline stroke font on a 4 x 6 unit grid, chamfered corners instead of round bowls, flat terminals. Strokes are polylines; the
atlas stores the DISTANCE to the nearest stroke (not a coverage mask), so the shader draws a tube of any width, a white-hot core and a halo from ONE texture tap.
Atlas: 8 x 8 cells of 48 x 64 px (1 unit = 8 px, the glyph box sits at x 1..5, y 1..7 of a 6 x 8 unit cell), 8-bit, R = 1 - distance / DMAX (DMAX = 1.5 units).
Cell index = position in ALPHABET (0 = blank). The word / marquee tables are emitted as GDShader constants so the indexes can never drift from the atlas."""
import argparse
import os
import re

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.normpath(os.path.join(HERE, "..", ".."))
DEFAULT_OUT = os.path.join(GODOT, "assets", "textures")
DEFAULT_SHADER = os.path.join(GODOT, "assets", "shaders", "signage_words.gdshaderinc")

COLS = ROWS = 8
CELL_W, CELL_H = 48, 64
UNIT = 8.0
DMAX = 1.5
ALPHABET = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.:!/+&'<>*?=_"

# polylines on the 4 x 6 grid (x right, y up); a one-point polyline is a dot
S = {
    "A": [[(0, 0), (0, 4), (1, 6), (3, 6), (4, 4), (4, 0)], [(0, 3), (4, 3)]],
    "B": [[(0, 0), (0, 6), (3, 6), (4, 5), (4, 4), (3, 3), (0, 3)], [(3, 3), (4, 2), (4, 1), (3, 0), (0, 0)]],
    "C": [[(4, 5), (3, 6), (1, 6), (0, 5), (0, 1), (1, 0), (3, 0), (4, 1)]],
    "D": [[(0, 0), (0, 6), (2, 6), (4, 4), (4, 2), (2, 0), (0, 0)]],
    "E": [[(4, 6), (0, 6), (0, 0), (4, 0)], [(0, 3), (3, 3)]],
    "F": [[(4, 6), (0, 6), (0, 0)], [(0, 3), (3, 3)]],
    "G": [[(4, 5), (3, 6), (1, 6), (0, 5), (0, 1), (1, 0), (3, 0), (4, 1), (4, 3), (2, 3)]],
    "H": [[(0, 0), (0, 6)], [(4, 0), (4, 6)], [(0, 3), (4, 3)]],
    "I": [[(1, 6), (3, 6)], [(2, 6), (2, 0)], [(1, 0), (3, 0)]],
    "J": [[(4, 6), (4, 1), (3, 0), (1, 0), (0, 1)]],
    "K": [[(0, 0), (0, 6)], [(4, 6), (0, 2.5)], [(1.4, 3.6), (4, 0)]],
    "L": [[(0, 6), (0, 0), (4, 0)]],
    "M": [[(0, 0), (0, 6), (2, 3.4), (4, 6), (4, 0)]],
    "N": [[(0, 0), (0, 6), (4, 0), (4, 6)]],
    "O": [[(1, 0), (0, 1), (0, 5), (1, 6), (3, 6), (4, 5), (4, 1), (3, 0), (1, 0)]],
    "P": [[(0, 0), (0, 6), (3, 6), (4, 5), (4, 4), (3, 3), (0, 3)]],
    "Q": [[(1, 0), (0, 1), (0, 5), (1, 6), (3, 6), (4, 5), (4, 1), (3, 0), (1, 0)], [(2.5, 2), (4, 0)]],
    "R": [[(0, 0), (0, 6), (3, 6), (4, 5), (4, 4), (3, 3), (0, 3)], [(2, 3), (4, 0)]],
    "S": [[(4, 5), (3, 6), (1, 6), (0, 5), (0, 4), (1, 3), (3, 3), (4, 2), (4, 1), (3, 0), (1, 0), (0, 1)]],
    "T": [[(0, 6), (4, 6)], [(2, 6), (2, 0)]],
    "U": [[(0, 6), (0, 1), (1, 0), (3, 0), (4, 1), (4, 6)]],
    "V": [[(0, 6), (2, 0), (4, 6)]],
    "W": [[(0, 6), (1, 0), (2, 3), (3, 0), (4, 6)]],
    "X": [[(0, 6), (4, 0)], [(4, 6), (0, 0)]],
    "Y": [[(0, 6), (2, 3), (4, 6)], [(2, 3), (2, 0)]],
    "Z": [[(0, 6), (4, 6), (0, 0), (4, 0)]],
    "0": [[(1, 0), (0, 1), (0, 5), (1, 6), (3, 6), (4, 5), (4, 1), (3, 0), (1, 0)], [(1, 1.2), (3, 4.8)]],
    "1": [[(0.5, 5), (2, 6), (2, 0)], [(0.5, 0), (3.5, 0)]],
    "2": [[(0, 5), (1, 6), (3, 6), (4, 5), (4, 4), (0, 0), (4, 0)]],
    "3": [[(0, 5), (1, 6), (3, 6), (4, 5), (4, 4), (3, 3), (1.5, 3)], [(3, 3), (4, 2), (4, 1), (3, 0), (1, 0), (0, 1)]],
    "4": [[(3, 0), (3, 6), (0, 2), (4, 2)]],
    "5": [[(4, 6), (0, 6), (0, 3), (3, 3), (4, 2), (4, 1), (3, 0), (1, 0), (0, 1)]],
    "6": [[(4, 5), (3, 6), (1, 6), (0, 5), (0, 1), (1, 0), (3, 0), (4, 1), (4, 2), (3, 3), (0, 3)]],
    "7": [[(0, 6), (4, 6), (1.5, 0)]],
    "8": [[(1, 3), (0, 4), (0, 5), (1, 6), (3, 6), (4, 5), (4, 4), (3, 3), (1, 3), (0, 2), (0, 1), (1, 0), (3, 0), (4, 1), (4, 2), (3, 3)]],
    "9": [[(0, 1), (1, 0), (3, 0), (4, 1), (4, 5), (3, 6), (1, 6), (0, 5), (0, 4), (1, 3), (4, 3)]],
    "-": [[(0.6, 3), (3.4, 3)]],
    ".": [[(2, 0)]],
    ":": [[(2, 1.2)], [(2, 4.2)]],
    "!": [[(2, 6), (2, 2)], [(2, 0)]],
    "/": [[(0, 0), (4, 6)]],
    "+": [[(0.6, 3), (3.4, 3)], [(2, 1.3), (2, 4.7)]],
    "&": [[(4, 0), (1, 4), (1, 5), (2, 6), (3, 5), (3, 4), (0, 1), (1, 0), (3, 0), (4, 2)]],
    "'": [[(2, 6), (2, 4.2)]],
    "<": [[(3.6, 6), (0.4, 3), (3.6, 0)]],
    ">": [[(0.4, 6), (3.6, 3), (0.4, 0)]],
    "*": [[(2, 1), (2, 5)], [(0.4, 2), (3.6, 4)], [(0.4, 4), (3.6, 2)]],
    "?": [[(0, 5), (1, 6), (3, 6), (4, 5), (4, 4), (2, 3), (2, 2)], [(2, 0)]],
    "=": [[(0.6, 4), (3.4, 4)], [(0.6, 2), (3.4, 2)]],
    "_": [[(0, 0), (4, 0)]],
}

# shop words first, the ones of 7 letters or fewer before the longer ones (the vertical blade signs stack letters and only take the short ones)
SHORT_WORDS = ["NOODLES", "CLINIC", "ARMS", "HOTEL", "CLUB", "24H", "TECH", "BAR", "PAWN", "RAMEN", "CAFE", "SYNTH", "MARKET", "REPAIR", "NEON", "DATA", "BIO LAB"]
LONG_WORDS = ["QUANTA BAR", "OPEN 24H", "NO ENTRY", "VAEL WATCH", "CURFEW 22"]
WORDS = SHORT_WORDS + LONG_WORDS
WARN_FIRST = WORDS.index("NO ENTRY")           # words from here on are warnings (hazard colours, no dying shop tubes)
MARQUEE = "VAEL WATCH - CURFEW 22:00 * NOODLES 24H * CLINIC * ARMS * HOTEL * TECH * CLUB * PAWN * REPORT RIFT SIGHTS * "
MAXLEN = 12


def distance_cell(strokes):
    """Distance (units) to the nearest stroke for every pixel centre of one 48 x 64 cell."""
    ys, xs = np.mgrid[0:CELL_H, 0:CELL_W].astype(np.float32)
    px = (xs + 0.5) / UNIT - 1.0              # glyph grid x (box at 0..4)
    py = 7.0 - (ys + 0.5) / UNIT              # glyph grid y, up (box at 0..6, the cell is 8 tall)
    d = np.full((CELL_H, CELL_W), 99.0, np.float32)
    for line in strokes:
        pts = line if len(line) > 1 else [line[0], line[0]]
        for (ax, ay), (bx, by) in zip(pts[:-1], pts[1:]):
            vx, vy = bx - ax, by - ay
            L2 = vx * vx + vy * vy
            t = np.zeros_like(px) if L2 == 0 else np.clip(((px - ax) * vx + (py - ay) * vy) / L2, 0.0, 1.0)
            dx = px - (ax + t * vx)
            dy = py - (ay + t * vy)
            d = np.minimum(d, np.sqrt(dx * dx + dy * dy))
    return d


def build_atlas():
    img = np.zeros((ROWS * CELL_H, COLS * CELL_W), np.uint8)
    for i, ch in enumerate(ALPHABET):
        if ch == " ":
            continue
        d = distance_cell(S[ch])
        v = np.clip(1.0 - d / DMAX, 0.0, 1.0)
        r, c = divmod(i, COLS)
        img[r * CELL_H:(r + 1) * CELL_H, c * CELL_W:(c + 1) * CELL_W] = np.round(v * 255.0).astype(np.uint8)
    return img


def idx(text):
    return [ALPHABET.index(ch) for ch in text]


def shader_text():
    out = ["// GENERATED by tools/textures/gen_signage.py (do not edit): word and marquee tables for the sign shaders; indexes are cells of signage_atlas.png.",
           "// ALPHABET = " + repr(ALPHABET),
           "const int SW_N = %d;" % len(WORDS),
           "const int SW_SHORT = %d;          // words 0..SW_SHORT-1 have 7 letters or fewer (vertical blade signs)" % len(SHORT_WORDS),
           "const int SW_WARN = %d;           // words from here on are warnings" % WARN_FIRST,
           "const int SW_VAEL = %d;           // VAEL WATCH" % WORDS.index("VAEL WATCH"),
           "const int SW_MAX = %d;" % MAXLEN,
           "// " + ", ".join("%d %s" % (i, w) for i, w in enumerate(WORDS))]
    lens = [len(w) for w in WORDS]
    assert max(lens) <= MAXLEN
    out.append("const int SW_LEN[%d] = int[%d](%s);" % (len(WORDS), len(WORDS), ", ".join(map(str, lens))))
    flat = []
    for w in WORDS:
        flat += idx(w) + [0] * (MAXLEN - len(w))
    out.append("const int SW_CH[%d] = int[%d](%s);" % (len(flat), len(flat), ", ".join(map(str, flat))))
    m = idx(MARQUEE)
    out.append("const int MQ_LEN = %d;" % len(m))
    out.append("const int MQ_CH[%d] = int[%d](%s);" % (len(m), len(m), ", ".join(map(str, m))))
    return "\n".join(out) + "\n"


def patch_imports(out_dir):
    p = os.path.join(out_dir, "signage_atlas.png.import")
    if not os.path.exists(p):
        raise SystemExit("run tools/import.sh first (no %s)" % p)
    s = open(p).read()
    s = re.sub(r"compress/mode=\d", "compress/mode=0", s)
    s = re.sub(r"mipmaps/generate=\w+", "mipmaps/generate=true", s)
    open(p, "w").write(s)
    print("patched", p)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--shader", default=DEFAULT_SHADER)
    ap.add_argument("--patch-imports", action="store_true")
    a = ap.parse_args()
    if a.patch_imports:
        patch_imports(a.out)
        return
    assert len(ALPHABET) <= COLS * ROWS and set(ALPHABET) - {" "} <= set(S)
    img = build_atlas()
    path = os.path.join(a.out, "signage_atlas.png")
    Image.fromarray(img, "L").save(path, optimize=True)
    open(a.shader, "w").write(shader_text())
    print("wrote", path, os.path.getsize(path), "bytes;", a.shader)


if __name__ == "__main__":
    main()
