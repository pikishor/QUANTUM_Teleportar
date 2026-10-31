#!/usr/bin/env python3
"""Procedural fire-and-smoke flipbook for the explosion VFX (numpy only, reproducible: fixed seeds).

Output: assets/textures/fx_flipbook.png, an 8 x 8 grid of 128 px frames (1024 x 1024, RGB 8 bit, no alpha, so VRAM compression stays cheap).
Channels (all 0..1, linear, not sRGB):
  R  fire heat: a fireball that grows fast, is eroded by churning noise and cools to nothing at about 80 % of the animation (shader maps heat to a colour ramp)
  G  smoke density: a puff that expands slowly and rises over the whole animation, fading in and out
  B  smoke shading: lit from below early on (the fire), mottled by a second noise; the shader tints it
Frame order is row-major, frame 0 at the top left; every frame is zero within 6 % of its border, so linear filtering never bleeds into a neighbour.

    python3 tools/make_fx_flipbook.py            (from the godot/ directory; takes about 3 s)
"""
import os
import struct
import sys
import zlib

import numpy as np

GRID = 8
FRAME = 128
FRAMES = GRID * GRID
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "textures", "fx_flipbook.png")


def noise_volume(seed, beta, cutoff, tscale):
    """Smooth 3D fractal noise (time, y, x) in 0..1, from filtered white noise: temporally coherent, so frames churn rather than flicker."""
    rng = np.random.default_rng(seed)
    white = rng.standard_normal((FRAMES, FRAME, FRAME))
    spec = np.fft.rfftn(white)
    kt = np.fft.fftfreq(FRAMES)[:, None, None] * FRAMES * tscale
    ky = np.fft.fftfreq(FRAME)[None, :, None] * FRAME
    kx = np.fft.rfftfreq(FRAME)[None, None, :] * FRAME
    k = np.sqrt(kt * kt + ky * ky + kx * kx)
    amp = np.where(k < 1.0, 0.0, 1.0 / np.maximum(k, 1.0) ** beta) * np.exp(-((k / cutoff) ** 2))
    vol = np.fft.irfftn(spec * amp, s=white.shape, axes=(0, 1, 2))
    lo, hi = np.percentile(vol, 1.0), np.percentile(vol, 99.0)
    return np.clip((vol - lo) / (hi - lo), 0.0, 1.0)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def build():
    ys, xs = np.mgrid[0:FRAME, 0:FRAME]
    X = (xs + 0.5) / FRAME
    Y = (ys + 0.5) / FRAME
    edge = 1.0 - smoothstep(0.38, 0.47, np.maximum(np.abs(X - 0.5), np.abs(Y - 0.5)))
    n_fire = noise_volume(11, 1.35, 16.0, 0.45)
    n_smoke = noise_volume(23, 1.15, 12.0, 0.3)
    n_detail = noise_volume(37, 0.9, 22.0, 0.5)
    sheet = np.zeros((GRID * FRAME, GRID * FRAME, 3), np.uint8)
    for f in range(FRAMES):
        u = f / (FRAMES - 1)
        shift = int(round(f * 0.55))                             # the noise scrolls upwards: flames and smoke rise
        nf = np.roll(n_fire[f], -shift, axis=0)
        ns = np.roll(n_smoke[f], -int(shift * 0.5), axis=0)
        nd = np.roll(n_detail[f], -shift, axis=0)
        # fire: fast growth, noise eroded rim, hot centre, cools out by u = 0.8
        grow = 1.0 - (1.0 - min(u / 0.5, 1.0)) ** 2
        r = 0.08 + 0.33 * grow
        cy = 0.56 - 0.09 * u
        d = np.hypot(X - 0.5, (Y - cy) * 0.85)
        heat = np.clip((r - d) / 0.16 + (nf - 0.5) * (0.9 + 0.9 * u), 0.0, 1.0)
        core = np.clip(1.0 - d / (r * 0.55 + 1e-3), 0.0, 1.0) ** 1.5 * (1.0 - u) ** 2
        life = np.clip(1.0 - u / 0.8, 0.0, 1.0) ** 1.35
        fire = np.clip(heat * life * 0.95 + core * 0.55, 0.0, 1.0)
        # smoke: slow expansion, rises, fades in and out
        rs = 0.13 + 0.29 * np.sqrt(u)
        cys = 0.62 - 0.2 * u
        ds = np.hypot(X - 0.5, (Y - cys) * 0.9)
        dens = np.clip((rs - ds) / 0.2 + (ns - 0.5) * 1.6, 0.0, 1.0)
        dens *= smoothstep(0.0, 0.1, u) * (1.0 - smoothstep(0.62, 1.0, u))
        shade = np.clip(0.4 + 0.9 * (nd - 0.5) + 0.55 * (Y - cys) / max(rs, 1e-3) * (1.0 - u), 0.0, 1.0)
        img = np.stack([fire * edge, dens * edge, shade * edge], axis=-1)
        gy, gx = divmod(f, GRID)
        sheet[gy * FRAME:(gy + 1) * FRAME, gx * FRAME:(gx + 1) * FRAME] = (np.round(img * 63.0) * 4.0).clip(0, 255).astype(np.uint8)   # 6 bit: compresses far better, VRAM formats lose the rest anyway
    return sheet


def write_png(path, rgb):
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[y].tobytes() for y in range(h))
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else OUT
    write_png(out, build())
    print("wrote", os.path.normpath(out), os.path.getsize(out) // 1024, "KB")
