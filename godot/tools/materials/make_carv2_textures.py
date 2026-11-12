#!/usr/bin/env python3
"""Textures of Cars v2 (numpy + PIL, deterministic): the shared tyre tread normal map and the paint flake normal map.

  .venv-tools/bin/python tools/materials/make_carv2_textures.py [out_dir]     # default: assets/textures

carv2_tread_normal.png   256 x 256, v runs over the tyre profile (0 = outer bead ... 1 = inner bead, the tread band is 0.30 .. 0.70, see carv2/wheels.py), u runs
                         once round the tyre and is repeated by the shader. OpenGL normal map (+Y up).
carv2_flake_normal.png   256 x 256 tileable: metallic flakes (hard speckle) and a faint orange peel (soft waves), sampled by the paint shader in object space.
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.abspath(os.path.join(HERE, "..", "..", "assets", "textures"))


def normal_from_height(h, strength):
    """Tileable central differences -> unit normals, packed 0..255 (OpenGL: green up)."""
    gx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    gy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    n = np.stack([-gx * strength, gy * strength, np.ones_like(h)], axis=-1)       # image y grows downwards: +Y up flips the sign of gy
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return ((n * 0.5 + 0.5) * 255.0 + 0.5).astype(np.uint8)


def blur_periodic(a, sigma):
    n = a.shape[0]
    f = np.fft.fftfreq(n)
    fx, fy = np.meshgrid(f, f)
    g = np.exp(-2.0 * (np.pi * sigma) ** 2 * (fx ** 2 + fy ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g))


def smooth_pulse(x, w, soft):
    """1 inside |x| < w, falling to 0 over `soft`."""
    return np.clip((w + soft - np.abs(x)) / soft, 0.0, 1.0)


def tread(n=256):
    u = (np.arange(n) + 0.5) / n
    v = (np.arange(n) + 0.5) / n
    U, V = np.meshgrid(u, v)
    h = np.zeros((n, n))
    band = smooth_pulse(V - 0.5, 0.185, 0.012)                      # the tread band 0.315 .. 0.685
    h += 0.55 * band
    for gv in (0.40, 0.5, 0.60):                                    # circumferential grooves
        h -= 0.6 * smooth_pulse(V - gv, 0.012, 0.012) * band
    for k in range(8):                                              # slanted lateral slots in the outer blocks
        for side, (v0, v1) in ((0, (0.315, 0.39)), (1, (0.61, 0.685))):
            slant = 0.045 if side == 0 else -0.045
            cu = (k + 0.5) / 8 + slant * (V - 0.5) * 4.0
            d = ((U - cu + 0.5) % 1.0) - 0.5
            mask = ((V > v0) & (V < v1)).astype(float)
            h -= 0.5 * smooth_pulse(d, 0.012, 0.010) * mask
    for k in range(8):                                              # the centre rib gets small sipes
        d = ((U - (k + 0.25) / 8 + 0.5) % 1.0) - 0.5
        mask = ((V > 0.415) & (V < 0.585)).astype(float)
        h -= 0.25 * smooth_pulse(d, 0.006, 0.008) * mask
    # sidewall: concentric ribs and some raised lettering blocks
    side = 1.0 - band
    h += 0.10 * side * (0.5 + 0.5 * np.sin(V * 2 * np.pi * 26.0))
    rng = np.random.RandomState(7)
    for _ in range(26):
        cu, cv = rng.rand(), rng.choice([0.14, 0.17, 0.83, 0.86])
        w = 0.01 + 0.02 * rng.rand()
        du = ((U - cu + 0.5) % 1.0) - 0.5
        h += 0.35 * smooth_pulse(du, w, 0.004) * smooth_pulse(V - cv, 0.012, 0.004)
    h = blur_periodic(h, 0.7)
    return normal_from_height(h, 4.0)


def flakes(n=256):
    rng = np.random.RandomState(11)
    speck = rng.randn(n, n)
    fine = blur_periodic(speck, 0.9)                                  # small bright metal flakes
    fine /= np.abs(fine).max()
    peel = blur_periodic(rng.randn(n, n), 7.0)
    peel /= np.abs(peel).max()
    h = 1.2 * fine + 0.25 * peel
    return normal_from_height(h, 5.0)


def main():
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(tread(), "RGB").save(os.path.join(OUT, "carv2_tread_normal.png"), optimize=True)
    Image.fromarray(flakes(), "RGB").save(os.path.join(OUT, "carv2_flake_normal.png"), optimize=True)
    for nme in ("carv2_tread_normal.png", "carv2_flake_normal.png"):
        print(nme, os.path.getsize(os.path.join(OUT, nme)), "bytes")


if __name__ == "__main__":
    main()
