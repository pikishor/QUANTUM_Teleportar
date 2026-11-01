#!/usr/bin/env python3
"""Reproducible tileable PBR surface sets for the city shaders (numpy + Pillow only, fixed seeds, periodic by construction).

  python3 tools/textures/gen_surfaces.py [--out assets/textures] [--only asphalt,brick] [--scale 1.0]
  python3 tools/textures/gen_surfaces.py --patch-imports        (after tools/import.sh created the .import files: ASTC/BPTC settings)
  tools/textures/build_surfaces.sh                              (all of it: generate, import, patch, import)

Every set is two files, both sampled with ONE tap each by the shaders (see assets/shaders/surface_tex.gdshaderinc):
  surface_<name>_albedo.png  RGB = albedo as a DETAIL MODULATOR (mean luminance 0.5: the shader multiplies the world's own palette and macro tone by 2 x RGB, so
                             wear, tints and the day-night look stay under the world's control), A = dry roughness
  surface_<name>_normal.png  RG = tangent normal xy (z rebuilt), B = cavity / ambient occlusion, A = WET roughness (the wet variant of the same surface)
Extra: surface_decals.png  (R oil + tyre polish, G puddle tide-mark rings, B litter flecks, A gutter grime; one mask tap),
       surface_trim_albedo/normal.png (2048 x 1024 atlas of 4 x 2 cells of 512 px: shopfront and billboard trim).
Sizes: asphalt, sidewalk, brick, decals 2048; concrete, corrugated, painted metal, roof tar 1024; trim 2048 x 1024. PNG on disk, ASTC / BPTC at import."""
import argparse
import os
import re
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "textures"))
LUMA = np.array([0.2126, 0.7152, 0.0722], np.float32)


# --------------------------------------------------------------------------------------------- periodic noise toolbox
def _freq(n, m=None):
    return np.fft.fftfreq(m or n)[None, :], np.fft.fftfreq(n)[:, None]


def white(n, seed):
    return np.random.default_rng(seed).standard_normal((n, n)).astype(np.float32)


def norm(x):
    x = x - x.mean()
    return (x / (x.std() + 1e-9)).astype(np.float32)


def spectral(n, beta, seed, lo=0.0, hi=0.5):
    """Periodic 1/f^beta noise (unit variance), band limited to [lo, hi] cycles per pixel."""
    fx, fy = _freq(n)
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    amp = f ** (-beta / 2.0)
    amp[(f < lo) | (f > hi)] = 0.0
    amp[0, 0] = 0.0
    return norm(np.fft.ifft2(np.fft.fft2(white(n, seed)) * amp).real)


def blur(x, sx, sy=None):
    """Periodic gaussian blur (sigma in pixels, sx along x, sy along y)."""
    sy = sx if sy is None else sy
    fx, fy = _freq(x.shape[0], x.shape[1])
    g = np.exp(-2.0 * (np.pi ** 2) * ((fx * sx) ** 2 + (fy * sy) ** 2))
    return np.fft.ifft2(np.fft.fft2(x) * g).real.astype(np.float32)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return (t * t * (3.0 - 2.0 * t)).astype(np.float32)


def unit(x, lo=1.0, hi=99.0):
    a, b = np.percentile(x, [lo, hi])
    return np.clip((x - a) / (b - a + 1e-9), 0.0, 1.0).astype(np.float32)


def worley(n, cells, seed):
    """Periodic cellular noise: (F1 distance in cell units, hash 0..1 of the nearest point)."""
    r = np.random.default_rng(seed)
    pts = r.random((cells, cells, 2)).astype(np.float32)
    ids = r.random((cells, cells)).astype(np.float32)
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32) / n * cells
    ci = np.floor(xs).astype(np.int32)
    cj = np.floor(ys).astype(np.int32)
    best = np.full((n, n), 9.0, np.float32)
    bid = np.zeros((n, n), np.float32)
    for dj in (-1, 0, 1):
        for di in (-1, 0, 1):
            ii = (ci + di) % cells
            jj = (cj + dj) % cells
            d = np.sqrt((xs - (ci + di + pts[jj, ii, 0])) ** 2 + (ys - (cj + dj + pts[jj, ii, 1])) ** 2)
            m = d < best
            best = np.where(m, d, best)
            bid = np.where(m, ids[jj, ii], bid)
    return best, bid


def height_to_normal(h, strength):
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    return np.clip(-gx * strength, -0.95, 0.95), np.clip(-gy * strength, -0.95, 0.95)


def modulate(rgb):
    """Rescale an albedo so its mean luminance is exactly 0.5 (a detail modulator)."""
    return np.clip(rgb * (0.5 / (rgb @ LUMA).mean()), 0.0, 1.0).astype(np.float32)


def u8(x):
    return (np.clip(x, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def tint(*c):
    return np.array(c, np.float32)[None, None, :]


def save_pair(out, name, rgb, rough, nx, ny, cavity, wet_rough):
    alb = np.dstack([modulate(rgb), np.clip(rough, 0, 1)])
    nrm = np.dstack([nx * 0.5 + 0.5, ny * 0.5 + 0.5, np.clip(cavity, 0, 1), np.clip(wet_rough, 0, 1)])
    for suffix, arr in (("albedo", alb), ("normal", nrm)):
        path = os.path.join(out, "surface_%s_%s.png" % (name, suffix))
        Image.fromarray(u8(arr), "RGBA").save(path, optimize=True, compress_level=9)
        print("  %-34s %6.1f MB" % (os.path.basename(path), os.path.getsize(path) / 1e6))


# ----------------------------------------------------------------------------------------------------- the surfaces
def asphalt(n, out):
    """Wearing course: bitumen film, exposed aggregate, pits, hairline cracks, sealed patches. Tile 3.2 m (1.6 mm per pixel at 2K)."""
    k = n / 2048.0
    st = smooth(1.0, 2.1, norm(blur(white(n, 11), 1.1 * k + 0.2)))                       # bright aggregate tops
    st2 = smooth(1.2, 2.4, norm(blur(white(n, 12), 2.4 * k + 0.2)))                      # larger stones
    pits = smooth(1.3, 2.6, -norm(blur(white(n, 13), 0.9 * k + 0.2)))
    macro = spectral(n, 2.2, 14, hi=0.02)
    mid = spectral(n, 1.4, 15, lo=0.004, hi=0.12)
    seal = smooth(0.6, 1.1, spectral(n, 2.6, 16, hi=0.01))                               # darker sealed patches
    crack = np.exp(-(spectral(n, 2.4, 17, lo=0.002, hi=0.03) / 0.035) ** 2) * smooth(0.2, 0.9, spectral(n, 2.8, 18, hi=0.006))   # patchy hairline cracks
    base = 1.0 + 0.16 * macro + 0.10 * mid + 0.55 * st + 0.35 * st2 - 0.40 * pits - 0.30 * seal - 0.55 * crack
    rgb = np.clip(base, 0.05, None)[..., None] * np.dstack([np.ones_like(base), 1.01 + 0.03 * st, 1.04 + 0.05 * (1 - st)])
    h = 0.45 * st + 0.35 * st2 - 0.55 * pits - 0.7 * crack + 0.15 * mid
    nx, ny = height_to_normal(blur(h, 0.5), 2.2 * (k + 0.5))
    rough = 0.80 + 0.10 * st2 - 0.05 * st + 0.05 * seal
    cavity = 1.0 - 0.55 * pits - 0.5 * crack - 0.12 * seal
    wet_rough = 0.07 + 0.50 * smooth(0.15, 1.0, unit(h)) ** 1.5 + 0.1 * st2        # a water film fills the pits, only the stone tops stay rough
    save_pair(out, "asphalt", rgb, rough, nx, ny, cavity, wet_rough)


def sidewalk(n, out):
    """Broom-finished slab concrete: air pores, fine aggregate, trowel and broom streaks, stains. Tile 2.4 m."""
    k = n / 2048.0
    fine = norm(blur(white(n, 21), 0.8 * k + 0.2))
    mid = spectral(n, 1.6, 22, lo=0.003, hi=0.1)
    macro = spectral(n, 2.4, 23, hi=0.015)
    broom = norm(blur(white(n, 24), 26.0 * k + 1.0, 0.7 * k + 0.2))                     # streaks along x
    trowel = norm(blur(spectral(n, 2.0, 25, hi=0.03), 3.0 * k + 0.2, 0.5))
    pores = smooth(1.6, 2.8, -norm(blur(white(n, 26), 1.0 * k + 0.2)))
    fleck = smooth(1.7, 3.0, norm(blur(white(n, 27), 0.9 * k + 0.2)))
    stain = smooth(0.7, 1.3, spectral(n, 2.4, 28, hi=0.012))
    base = 1.0 + 0.11 * macro + 0.08 * mid + 0.07 * fine + 0.06 * broom + 0.05 * trowel - 0.65 * pores + 0.28 * fleck - 0.28 * stain
    rgb = np.clip(base, 0.05, None)[..., None] * tint(1.0, 0.985, 0.955)
    h = 0.30 * fine + 0.35 * broom - 0.9 * pores + 0.10 * mid + 0.15 * fleck
    nx, ny = height_to_normal(blur(h, 0.45), 1.8 * (k + 0.5))
    save_pair(out, "sidewalk", rgb, 0.83 - 0.06 * trowel + 0.05 * pores, nx, ny, 1.0 - 0.6 * pores,
              0.30 + 0.25 * smooth(-1, 2, broom) + 0.15 * fine)


def concrete(n, out):
    """Tower wall concrete (no panel seams: the shader owns the layout): pores, vertical rain streaks, bleeding. Tile 2 m."""
    k = n / 1024.0
    fine = norm(blur(white(n, 31), 0.7 * k + 0.2))
    mid = spectral(n, 1.7, 32, lo=0.004, hi=0.12)
    macro = spectral(n, 2.3, 33, hi=0.02)
    pores = smooth(1.5, 2.7, -norm(blur(white(n, 34), 0.9 * k + 0.2)))
    streak = norm(blur(white(n, 35), 1.2 * k + 0.2, 40.0 * k + 1.0))                    # vertical rain streaks
    bleed = smooth(0.5, 1.4, streak) * smooth(0.0, 1.0, macro)
    base = 1.0 + 0.10 * macro + 0.09 * mid + 0.08 * fine - 0.6 * pores - 0.16 * bleed + 0.06 * streak
    rgb = np.clip(base, 0.05, None)[..., None] * tint(1.0, 1.0, 0.985)
    nx, ny = height_to_normal(blur(0.35 * fine + 0.20 * mid - 0.9 * pores, 0.5), 1.6)
    save_pair(out, "concrete", rgb, 0.84 - 0.05 * mid, nx, ny, 1 - 0.55 * pores, 0.34 + 0.2 * smooth(-1, 2, fine) + 0.1 * bleed)


def brick(n, out):
    """8 x 8 bricks, 0.46 x 0.22 m each (tile 3.68 x 1.76 m stretched to the square texture), odd rows offset by half a brick exactly like the facade
    shader's layout: per-brick colour, bevelled edges, chipped corners, sandy mortar joints recessed."""
    cell = n // 8
    ys, xs = np.mgrid[0:n, 0:n]
    row = ys // cell
    xx = xs + (row % 2) * (cell // 2)
    col = (xx // cell) % 8
    lx = (xx % cell).astype(np.float32)
    ly = (ys % cell).astype(np.float32)
    d_mm = np.minimum(np.minimum(lx, cell - 1 - lx) * (460.0 / cell), np.minimum(ly, cell - 1 - ly) * (220.0 / cell))
    r = np.random.default_rng(41)
    bval = r.random((8, 8)).astype(np.float32)[row, col]
    bhue = r.random((8, 8)).astype(np.float32)[row, col]
    k = n / 2048.0
    fine = norm(blur(white(n, 42), 0.9 * k + 0.2))
    mid = spectral(n, 1.6, 43, lo=0.004, hi=0.12)
    pit = smooth(1.6, 2.8, -norm(blur(white(n, 44), 1.1 * k + 0.2)))
    chip = smooth(0.7, 1.4, norm(blur(white(n, 45), 5.0 * k + 0.5))) * smooth(9.0, 3.0, d_mm)
    mortar = smooth(5.5, 4.5, d_mm)
    bevel = smooth(4.5, 13.0, d_mm)
    brickc = np.stack([0.60 + 0.30 * bval, 0.38 + 0.18 * bval - 0.10 * bhue, 0.30 + 0.12 * bval - 0.16 * bhue], -1)   # red, ochre, dark plum
    brickc = brickc * (1.0 + 0.10 * mid[..., None] + 0.12 * fine[..., None]) * (1.0 - 0.45 * pit[..., None]) * (1.0 - 0.35 * chip[..., None])
    mort_c = tint(0.34, 0.31, 0.27) * (1.0 + 0.2 * fine[..., None])
    rgb = brickc * (1 - mortar[..., None]) + mort_c * mortar[..., None]
    lum = (rgb @ LUMA)[..., None]
    rgb = lum + 0.4 * (rgb - lum)                    # the modulator keeps only a hint of hue (the building's own tint decides the colour)
    h = bevel * (0.8 + 0.12 * mid + 0.10 * fine - 0.4 * pit) - 0.35 * mortar - 0.3 * chip
    nx, ny = height_to_normal(blur(h, 0.6 * k + 0.2), 3.2)
    save_pair(out, "brick", rgb, 0.88 - 0.06 * bval + 0.06 * mortar, nx, ny, 1 - 0.55 * mortar - 0.5 * pit - 0.25 * chip,
              0.38 + 0.25 * mortar + 0.12 * fine)


def corrugated(n, out):
    """Corrugated sheet (20 ridges per 1.52 m tile, ridges vertical): painted over galvanised, rust runs, scratches. Also the roller shutters."""
    k = n / 1024.0
    xs = np.broadcast_to((np.arange(n, dtype=np.float32) / n)[None, :], (n, n))
    ridge = 0.5 + 0.5 * np.sin(2 * np.pi * 20 * xs)
    fine = norm(blur(white(n, 51), 0.8 * k + 0.2))
    macro = spectral(n, 2.2, 52, hi=0.02)
    run = norm(blur(white(n, 53), 1.0 * k + 0.2, 60.0 * k + 1.0))
    rust = smooth(0.8, 1.6, run + 0.6 * spectral(n, 2.2, 54, hi=0.03)) * smooth(-0.6, 0.8, macro)
    scr = smooth(2.2, 3.4, norm(blur(white(n, 55), 14.0 * k + 1.0, 0.6 * k + 0.2)))
    chip = smooth(1.9, 3.0, norm(blur(white(n, 56), 1.4 * k + 0.2)))
    paint = tint(0.52, 0.56, 0.60) * (1 + 0.1 * macro[..., None] + 0.05 * fine[..., None])
    metal = tint(0.70, 0.72, 0.74) * (0.85 + 0.15 * ridge[..., None])
    bare = np.clip(scr * 0.8 + chip * 0.9, 0, 1)
    rgb = paint * (1 - bare[..., None]) + metal * bare[..., None]
    rgb = rgb * (1 - rust[..., None]) + tint(0.55, 0.28, 0.12) * (0.85 + 0.15 * fine[..., None]) * rust[..., None]
    rgb = rgb * (0.88 + 0.22 * ridge[..., None])
    nx, ny = height_to_normal(ridge + 0.04 * fine - 0.1 * rust, 0.55 * k)
    save_pair(out, "corrugated", rgb, 0.52 + 0.28 * rust - 0.12 * bare + 0.06 * fine, nx, ny, 0.72 + 0.28 * ridge - 0.25 * rust,
              0.18 + 0.4 * rust + 0.06 * fine)


def painted_metal(n, out):
    """Painted steel plate: orange peel, brushed scratches in two directions, paint chips down to bare steel and rust bloom, dirt in the low spots. Tile 1 m."""
    k = n / 1024.0
    peel = norm(blur(white(n, 61), 2.2 * k + 0.2))
    fine = norm(blur(white(n, 62), 0.7 * k + 0.2))
    macro = spectral(n, 2.3, 63, hi=0.02)
    sh = smooth(2.3, 3.5, norm(blur(white(n, 64), 18.0 * k + 1.0, 0.55 * k + 0.2)))
    sv = smooth(2.4, 3.6, norm(blur(white(n, 65), 0.55 * k + 0.2, 16.0 * k + 1.0)))
    scratch = np.maximum(sh, sv)
    chip_d, chip_id = worley(n, 18, 66)
    chips = smooth(0.30, 0.18, chip_d) * smooth(0.55, 0.8, unit(blur(white(n, 67), 4.0 * k + 0.5))) * (chip_id > 0.45)
    chips = np.clip(chips + smooth(2.0, 3.2, norm(blur(white(n, 68), 1.6 * k + 0.2))) * 0.8, 0, 1)
    rust = smooth(0.5, 1.2, spectral(n, 2.4, 69, hi=0.025)) * chips
    dirt = smooth(0.6, 1.3, spectral(n, 2.0, 70, hi=0.04))
    paint = tint(0.55, 0.55, 0.57) * (1 + 0.09 * macro[..., None] + 0.03 * peel[..., None])
    steel = tint(0.48, 0.50, 0.52) * (0.8 + 0.2 * fine[..., None])
    rgb = paint * (1 - chips[..., None]) + steel * chips[..., None]
    rgb = rgb * (1 - rust[..., None]) + tint(0.50, 0.24, 0.10) * rust[..., None]
    rgb = rgb * (1 - 0.18 * dirt[..., None]) * (1 + 0.10 * scratch[..., None])
    nx, ny = height_to_normal(blur(0.12 * peel + 0.03 * fine - 0.45 * chips - 0.12 * scratch, 0.4), 2.0)
    save_pair(out, "painted_metal", rgb, 0.46 + 0.04 * peel - 0.14 * scratch + 0.22 * chips + 0.2 * rust, nx, ny, 1 - 0.4 * chips - 0.2 * dirt,
              0.16 + 0.30 * chips + 0.2 * rust)


def roof_tar(n, out):
    """Ballasted membrane roof: rounded gravel in black bitumen, bare tar patches where the gravel blew away. Tile 2 m."""
    k = n / 1024.0
    d1, gid = worley(n, 64, 71)
    d2, gid2 = worley(n, 40, 72)
    stone = smooth(0.62, 0.30, d1) * (gid > 0.18)
    stone2 = smooth(0.55, 0.25, d2) * (gid2 > 0.55) * (1 - stone)
    dome = np.sqrt(np.clip(1 - (d1 / 0.62) ** 2, 0, 1)) * stone + 0.7 * np.sqrt(np.clip(1 - (d2 / 0.55) ** 2, 0, 1)) * stone2
    bare = smooth(0.55, 1.1, spectral(n, 2.4, 73, hi=0.02))
    cover = np.clip((stone + stone2) * (1 - 0.85 * bare), 0, 1)
    fine = norm(blur(white(n, 74), 0.8 * k + 0.2))
    macro = spectral(n, 2.3, 75, hi=0.03)
    gv = 0.55 + 0.9 * (gid * 0.6 + gid2 * 0.4)
    stone_c = tint(0.74, 0.72, 0.69) * gv[..., None]
    tar_c = tint(0.20, 0.205, 0.22) * (1 + 0.15 * macro[..., None] + 0.1 * fine[..., None])
    rgb = tar_c * (1 - cover[..., None]) + stone_c * cover[..., None] * (1 + 0.15 * fine[..., None])
    nx, ny = height_to_normal(blur(dome * (1 - 0.6 * bare) + 0.04 * fine, 0.5), 2.6)
    save_pair(out, "roof_tar", rgb, 0.9 - 0.12 * cover + 0.06 * bare, nx, ny, 0.35 + 0.65 * smooth(0.0, 0.6, dome + 0.35 * bare),
              0.12 + 0.5 * cover * smooth(0.0, 0.7, dome))


def decals(n, out):
    """One RGBA mask (tile 12 m, sparse, so the repeat does not read): R oil stains and tyre polish, G puddle tide-mark rings, B litter flecks, A gutter grime."""
    k = n / 2048.0
    oil = smooth(1.1, 1.9, spectral(n, 2.6, 81, hi=0.02) + 0.35 * spectral(n, 1.6, 82, lo=0.01, hi=0.1))
    oil = oil * (0.6 + 0.4 * unit(spectral(n, 1.8, 83, lo=0.01, hi=0.2)))
    oil = np.clip(oil + 0.8 * smooth(0.0, 0.5, (norm(blur(white(n, 84), 5 * k + 0.5)) - 1.6) * 1.2), 0, 1)     # small droplets beside the stains
    pb = spectral(n, 2.7, 85, hi=0.015) + 0.25 * spectral(n, 1.8, 86, lo=0.01, hi=0.08)
    ring = np.exp(-((pb - 0.55) / 0.045) ** 2) * 0.9 + np.exp(-((pb - 0.78) / 0.03) ** 2) * 0.6 + np.exp(-((pb - 0.36) / 0.05) ** 2) * 0.4
    ring = ring * (0.55 + 0.45 * unit(spectral(n, 1.6, 87, lo=0.01, hi=0.2)))                                 # a broken tide line
    r = np.random.default_rng(88)
    lit = np.zeros((n, n), np.float32)
    yy, xx = np.mgrid[-24:25, -24:25].astype(np.float32)
    ar = np.arange(-24, 25)
    for _ in range(520):                                                                                      # paper, cans, bags: small oriented rectangles
        cx, cy = r.integers(0, n, 2)
        w, hh = r.integers(int(6 * k) + 2, int(26 * k) + 5), r.integers(int(4 * k) + 2, int(14 * k) + 4)
        a = r.random() * np.pi
        u = xx * np.cos(a) + yy * np.sin(a)
        v = -xx * np.sin(a) + yy * np.cos(a)
        m = ((np.abs(u) < w / 2) & (np.abs(v) < hh / 2)).astype(np.float32) * (0.5 + 0.5 * r.random())
        ix = np.ix_((cy + ar) % n, (cx + ar) % n)
        lit[ix] = np.maximum(lit[ix], m)
    grime = smooth(0.0, 1.0, norm(blur(white(n, 89), 3 * k + 0.5, 90 * k + 2)) * 0.8 + 0.5 * spectral(n, 2.0, 90, hi=0.05))
    path = os.path.join(out, "surface_decals.png")
    Image.fromarray(u8(np.dstack([oil, np.clip(ring, 0, 1), lit, grime])), "RGBA").save(path, optimize=True, compress_level=9)
    print("  %-34s %6.1f MB" % (os.path.basename(path), os.path.getsize(path) / 1e6))


def trim(n, out):
    """2048 x 1024 atlas, 4 x 2 cells of 512 px: row 0 = brushed sign bezel, awning stripes, shopfront mullion gasket, neon channel back;
    row 1 = shutter slats, LED cabinet bezel with screws, peeling painted trim, vent louvres. A cell's uv (0..1) is sampled clamped (no tiling)."""
    c = 512
    rgb = np.zeros((2 * c, 4 * c, 3), np.float32)
    rough = np.zeros((2 * c, 4 * c), np.float32)
    hgt = np.zeros((2 * c, 4 * c), np.float32)
    cav = np.ones((2 * c, 4 * c), np.float32)
    ys, xs = np.mgrid[0:c, 0:c].astype(np.float32) / c
    f = norm(blur(white(c, 101), 0.7))
    brush = norm(blur(white(c, 102), 30.0, 0.6))
    pn = norm(blur(white(c, 103), 6.0))

    def put(cx, cy, col, ro, h, cv):
        sl = (slice(cy * c, (cy + 1) * c), slice(cx * c, (cx + 1) * c))
        rgb[sl], rough[sl], hgt[sl], cav[sl] = col, ro, h, cv

    e = np.minimum(np.minimum(xs, 1 - xs), np.minimum(ys, 1 - ys))
    bev = smooth(0.0, 0.07, e)
    put(0, 0, tint(0.55, 0.56, 0.58) * (1 + 0.08 * brush[..., None] + 0.05 * f[..., None]) * (0.7 + 0.3 * bev[..., None]), 0.35 + 0.1 * (1 - bev),
        bev * 0.7 + 0.03 * brush, 0.6 + 0.4 * bev)
    stripe = (np.floor(xs * 8) % 2).astype(np.float32)[..., None]
    weave = 0.5 + 0.5 * np.sin(xs * 2 * np.pi * 120) * np.sin(ys * 2 * np.pi * 120)
    put(1, 0, (tint(0.62, 0.20, 0.16) * stripe + tint(0.66, 0.64, 0.58) * (1 - stripe)) * (0.88 + 0.12 * weave[..., None]), 0.9, 0.12 * weave, 0.8 + 0.2 * weave)
    g = np.exp(-((xs - 0.5) / 0.045) ** 2)
    put(2, 0, tint(0.30, 0.31, 0.33) * (1 + 0.1 * f[..., None]) * (1 - 0.7 * g[..., None]), 0.5 + 0.3 * g, -0.8 * g + 0.3 * bev, 1 - 0.8 * g)
    ch = smooth(0.30, 0.34, ys) * smooth(0.70, 0.66, ys)
    put(3, 0, tint(0.18, 0.18, 0.20) * (1 + 0.15 * f[..., None]) * (1 - 0.5 * ch[..., None]), 0.55, -0.5 * ch + 0.1 * f, 1 - 0.5 * ch)
    slat = np.sin(((ys * 16) % 1.0) * np.pi)
    put(0, 1, tint(0.50, 0.52, 0.54) * (0.75 + 0.35 * slat[..., None]) * (1 + 0.1 * f[..., None]), 0.5, slat * 0.8, 0.45 + 0.55 * slat)
    fr = smooth(0.0, 0.015, e) * smooth(0.14, 0.11, e)
    lip = smooth(0.11, 0.115, e) * smooth(0.15, 0.13, e)
    scr = np.zeros((c, c), np.float32)
    for sx_ in (0.06, 0.94):
        for sy_ in (0.06, 0.94):
            scr = np.maximum(scr, smooth(0.022, 0.014, np.sqrt((xs - sx_) ** 2 + (ys - sy_) ** 2)))
    put(1, 1, tint(0.20, 0.21, 0.23) * (1 + 0.12 * f[..., None]) * (0.6 + 0.4 * fr[..., None]) + 0.25 * scr[..., None], 0.42, 0.5 * fr + 0.2 * lip + 0.4 * scr,
        1 - 0.3 * (1 - fr))
    peel = smooth(0.9, 1.6, pn)
    put(2, 1, (tint(0.58, 0.16, 0.14) * (1 - peel[..., None]) + tint(0.32, 0.30, 0.28) * peel[..., None]) * (1 + 0.1 * f[..., None]), 0.6 + 0.25 * peel,
        -0.4 * peel + 0.05 * f, 1 - 0.4 * peel)
    lou = smooth(0.0, 0.25, (ys * 10) % 1.0) * smooth(0.9, 0.6, (ys * 10) % 1.0)
    put(3, 1, tint(0.22, 0.23, 0.25) * (0.35 + 0.65 * lou[..., None]) * (1 + 0.1 * f[..., None]), 0.55, lou * 0.9, 0.25 + 0.75 * lou)
    nx, ny = height_to_normal(blur(hgt, 0.5), 2.5)
    save_pair(out, "trim", rgb, rough, nx, ny, cav, rough * 0.6)


SETS = {
    "asphalt": (asphalt, 2048), "sidewalk": (sidewalk, 2048), "brick": (brick, 2048), "concrete": (concrete, 1024),
    "corrugated": (corrugated, 1024), "painted_metal": (painted_metal, 1024), "roof_tar": (roof_tar, 1024),
    "decals": (decals, 2048), "trim": (trim, 512),
}


def patch_imports(out):
    """VRAM compression (ASTC 4x4 / BPTC, high quality) with mipmaps. The packed normal texture stays a plain colour texture (normal_map=0): RG + cavity + wet
    roughness are packed, so the engine must not treat it as a two-channel normal map."""
    n = 0
    for fn in sorted(os.listdir(out)):
        if not (fn.startswith("surface_") and fn.endswith(".png.import")):
            continue
        p = os.path.join(out, fn)
        s = open(p).read()
        for key, val in (("compress/mode", "2"), ("compress/high_quality", "true"), ("compress/normal_map", "0"), ("mipmaps/generate", "true"),
                         ("compress/channel_pack", "0"), ("process/fix_alpha_border", "false")):
            s = re.sub(r"^%s=.*$" % re.escape(key), "%s=%s" % (key, val), s, flags=re.M)
        open(p, "w").write(s)
        n += 1
    print("patched %d .import files" % n)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--only", default="")
    ap.add_argument("--scale", type=float, default=1.0, help="size multiplier (0.25 for quick tests; the trim atlas keeps its 512 px cells)")
    ap.add_argument("--patch-imports", action="store_true")
    a = ap.parse_args()
    if a.patch_imports:
        patch_imports(a.out)
        return 0
    os.makedirs(a.out, exist_ok=True)
    for name in [x for x in a.only.split(",") if x] or list(SETS):
        fn, size = SETS[name]
        size = size if name == "trim" else max(64, int(size * a.scale) // 8 * 8)
        print(name, size)
        fn(size, a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
