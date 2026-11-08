#!/usr/bin/env python3
"""Poly Haven (CC0) 1K HDRIs -> tiny equirect sky probes for assets/shaders/sky.gdshader (urban light for the ambient + reflection radiance and the visible horizon).
Reads Radiance .hdr (RLE RGBE), box-downsamples to 256 x 128 and writes assets/textures/sky_probe_<name>.png, Reinhard-encoded (s = c / (1 + c), decode c = s / (1 - s)) so the dark night values keep their precision.
Inputs live in assets_incoming/polyhaven_raw/_hdri/ (see PROBES; fetch with curl from dl.polyhaven.org, not committed).
  python3 tools/materials/pack_sky_probes.py [--preview out.png]"""
import argparse, os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
## probe name -> (Poly Haven slug, exposure multiplier applied before encoding)
PROBES = {"dusk": ("sunset_jhbcentral", 1.0), "night": ("cobblestone_street_night", 1.0), "overcast": ("potsdamer_platz", 1.0)}


def read_hdr(path):
    with open(path, "rb") as f:
        data = f.read()
    pos = 0
    w = h = 0
    while True:
        end = data.index(b"\n", pos)
        line = data[pos:end]
        pos = end + 1
        if line.startswith(b"-Y") or line.startswith(b"+Y"):
            parts = line.split()
            h, w = int(parts[1]), int(parts[3])
            break
    img = np.zeros((h, w, 4), np.uint8)
    for y in range(h):
        if data[pos] != 2 or data[pos + 1] != 2 or (data[pos + 2] << 8 | data[pos + 3]) != w:
            raise ValueError("flat (non-RLE) HDR scanlines are not supported")
        pos += 4
        for c in range(4):
            x = 0
            while x < w:
                n = data[pos]; pos += 1
                if n > 128:
                    n -= 128
                    img[y, x:x + n, c] = data[pos]; pos += 1
                else:
                    img[y, x:x + n, c] = np.frombuffer(data, np.uint8, n, pos); pos += n
                x += n
    e = img[..., 3].astype(np.float32)
    scale = np.where(e > 0, np.ldexp(1.0, (e - 136).astype(np.int32)), 0.0).astype(np.float32)
    return img[..., :3].astype(np.float32) * scale[..., None]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(ROOT, "assets_incoming", "polyhaven_raw", "_hdri"))
    ap.add_argument("--out", default=os.path.join(ROOT, "assets", "textures"))
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    tiles = []
    for name, (slug, exp) in PROBES.items():
        hdr = read_hdr(os.path.join(a.src, "%s_1k.hdr" % slug)) * exp
        h, w, _ = hdr.shape
        small = hdr.reshape(128, h // 128, 256, w // 256, 3).mean(axis=(1, 3))
        s = small / (1.0 + small)
        im = Image.fromarray((np.clip(s, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")
        im.save(os.path.join(a.out, "sky_probe_%s.png" % name), optimize=True)
        lum = small @ np.array([0.2126, 0.7152, 0.0722], np.float32)
        print("%-9s <- %-24s mean %.3f  p99 %.2f  max %.1f" % (name, slug, lum.mean(), np.percentile(lum, 99), lum.max()))
        tiles.append(Image.fromarray((np.clip((small * 0.5) / (1 + small * 0.5), 0, 1) ** (1 / 2.2) * 255).astype(np.uint8), "RGB").resize((512, 256)))
    if a.preview:
        sheet = Image.new("RGB", (512, 256 * len(tiles)))
        for i, t in enumerate(tiles):
            sheet.paste(t, (0, 256 * i))
        sheet.save(a.preview)
    return 0


if __name__ == "__main__":
    sys.exit(main())
