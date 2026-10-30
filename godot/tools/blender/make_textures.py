#!/usr/bin/env python3
"""Procedural PBR texture sets for Quantum Teleportar (numpy only, no PIL/bpy needed).

For every set `<name>` this writes three tileable maps:
  <name>_albedo.png   sRGB colour, kept close to neutral so models can tint it with material factors / vertex colours
  <name>_orm.png      glTF packing: R = ambient occlusion, G = roughness, B = metallic
  <name>_normal.png   tangent-space normal map, OpenGL convention (+Y up), which is what glTF and Godot expect

Usage:  python3 make_textures.py [--size 1024] [--out DIR] [--only a,b] [--preview FILE]
Big 1K maps go to assets/generated/textures (git-ignored); `--size 512` writes the compact set that is committed.
Everything is deterministic (fixed seeds), so the output is reproducible.
"""
import argparse
import os
import struct
import sys
import time
import zlib

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))


# ------------------------------------------------------------------ PNG writer (no dependencies)
def write_png(path, arr):
    """8-bit grayscale / RGB / RGBA PNG. Tries filters None/Sub/Up and keeps the smallest result."""
    arr = np.ascontiguousarray(np.clip(arr, 0, 255).astype(np.uint8))
    h, w = arr.shape[:2]
    ch = 1 if arr.ndim == 2 else arr.shape[2]
    flat = arr.reshape(h, w * ch)
    bpp = ch
    best = None
    for ftype in (0, 1, 2):
        if ftype == 0:
            filt = flat
        elif ftype == 1:
            filt = flat.copy()
            filt[:, bpp:] = (flat[:, bpp:].astype(np.int16) - flat[:, :-bpp].astype(np.int16)).astype(np.uint8)
        else:
            filt = flat.copy()
            filt[1:] = (flat[1:].astype(np.int16) - flat[:-1].astype(np.int16)).astype(np.uint8)
        raw = np.concatenate([np.full((h, 1), ftype, np.uint8), filt], axis=1).tobytes()
        comp = zlib.compress(raw, 9)
        if best is None or len(comp) < len(best):
            best = comp
    ct = {1: 0, 3: 2, 4: 6}[ch]

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ct, 0, 0, 0)))
        f.write(chunk(b"IDAT", best))
        f.write(chunk(b"IEND", b""))


# ------------------------------------------------------------------ tileable noise toolbox
def rng(seed):
    return np.random.default_rng(seed)


def n01(a):
    a = a - a.min()
    return a / max(float(a.max()), 1e-9)


def fbm(n, beta=2.0, seed=0, lo=0.0, hi=0.5):
    """Spectral noise: power ~ 1/f^beta, band limited to [lo, hi] cycles per pixel. Tileable. Returns 0..1."""
    w = rng(seed).standard_normal((n, n))
    spec = np.fft.rfft2(w)
    fy = np.fft.fftfreq(n)[:, None]
    fx = np.fft.rfftfreq(n)[None, :]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    filt = f ** (-beta / 2.0)
    filt[(f < lo) | (f > hi)] = 0.0
    filt[0, 0] = 0.0
    out = np.fft.irfft2(spec * filt, s=(n, n))
    out = (out - out.mean()) / (out.std() * 6.0 + 1e-9) + 0.5
    return np.clip(out, 0.0, 1.0)


def blur(a, sigma, sigma_y=None):
    """Periodic gaussian blur by FFT."""
    n = a.shape[0]
    sy = sigma if sigma_y is None else sigma_y
    fy = np.fft.fftfreq(a.shape[0])[:, None]
    fx = np.fft.rfftfreq(a.shape[1])[None, :]
    g = np.exp(-2.0 * np.pi ** 2 * ((sigma * fx) ** 2 + (sy * fy) ** 2))
    return np.fft.irfft2(np.fft.rfft2(a) * g, s=a.shape)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0 + 1e-12), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def grid(n):
    y, x = np.mgrid[0:n, 0:n].astype(np.float64)
    return x, y


def worley(n, cells, seed):
    """Tileable cellular noise. Returns (F1 distance in cell units, F2, per-cell random value of the nearest cell)."""
    r = rng(seed)
    pts = r.random((cells, cells, 2))
    vals = r.random((cells, cells))
    x, y = grid(n)
    xs = x / n * cells
    ys = y / n * cells
    cx = np.floor(xs).astype(int)
    cy = np.floor(ys).astype(int)
    f1 = np.full((n, n), 9.0)
    f2 = np.full((n, n), 9.0)
    rid = np.zeros((n, n))
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            nx = (cx + dx) % cells
            ny = (cy + dy) % cells
            px = cx + dx + pts[ny, nx, 0]
            py = cy + dy + pts[ny, nx, 1]
            d = np.hypot(xs - px, ys - py)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            rid = np.where(closer, vals[ny, nx], rid)
            f1 = np.where(closer, d, f1)
    return f1, f2, rid


def splat_disks(n, count, rmin, rmax, seed, profile="dome"):
    """Periodic field of random disks (max-combined). Returns height field 0..1 (dome / flat / ring profile)."""
    r = rng(seed)
    acc = np.zeros((n, n))
    for _ in range(count):
        cx, cy = r.integers(0, n, 2)
        rad = r.uniform(rmin, rmax)
        k = int(np.ceil(rad)) + 1
        xs = (cx + np.arange(-k, k + 1)) % n
        ys = (cy + np.arange(-k, k + 1)) % n
        gx, gy = np.meshgrid(np.arange(-k, k + 1), np.arange(-k, k + 1))
        d = np.hypot(gx, gy) / rad
        if profile == "dome":
            h = np.sqrt(np.clip(1.0 - d * d, 0.0, 1.0))
        elif profile == "ring":
            h = np.clip(1.0 - np.abs(d - 0.8) * 4.0, 0.0, 1.0)
        else:
            h = (d < 1.0).astype(float)
        sub = acc[np.ix_(ys, xs)]
        acc[np.ix_(ys, xs)] = np.maximum(sub, h)
    return acc


def splat_lines(n, count, lmin, lmax, seed, angle=None, jitter=0.15, step=0.7):
    """Periodic random line segments (scratches). angle in radians (None = random). Returns 0..1 mask after a slight blur."""
    r = rng(seed)
    acc = np.zeros((n, n))
    for _ in range(count):
        x0, y0 = r.uniform(0, n, 2)
        ang = r.uniform(0, np.pi) if angle is None else angle + r.normal(0, jitter)
        ln = r.uniform(lmin, lmax)
        t = np.arange(0.0, ln, step)
        wob = np.cumsum(r.normal(0, 0.02, t.size))
        xs = (x0 + np.cos(ang + wob) * t).astype(int) % n
        ys = (y0 + np.sin(ang + wob) * t).astype(int) % n
        fade = np.sin(np.pi * t / ln) * r.uniform(0.4, 1.0)
        np.maximum.at(acc, (ys, xs), fade)
    return np.clip(blur(acc, 0.6) * 2.2, 0.0, 1.0)


def height_to_normal(h, strength):
    """OpenGL-convention normal map (+Y up in the image) from a height field (rows run downward)."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    nx = -dx * strength
    ny = dy * strength
    nz = np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    out = np.stack([nx / ln, ny / ln, nz / ln], axis=-1)
    return (out * 0.5 + 0.5) * 255.0


def cavity(h, sigma, gain):
    """Cheap ambient occlusion / convexity from a height field: positive = convex (edges), negative = cavities."""
    return (h - blur(h, sigma)) * gain


def lerp(a, b, t):
    return a + (b - a) * t


def rgb(r, g, b):
    return np.array([r, g, b], dtype=np.float64)


def colorize(base, t):
    """base: (3,) colour; t: (n, n) factor -> (n, n, 3)."""
    return t[..., None] * base[None, None, :]


def pack(albedo, ao, rough, metal, height, nstrength):
    a = np.clip(albedo, 0, 1) * 255.0
    orm = np.stack([np.clip(ao, 0, 1), np.clip(rough, 0, 1), np.clip(metal, 0, 1)], axis=-1) * 255.0
    return a, orm, height_to_normal(height, nstrength)


def px(n, v):
    """Convert a size given for a 1024 texture to the current resolution."""
    return v * n / 1024.0


# ------------------------------------------------------------------ the sets
def stamp(acc, cx, cy, rad, kind="dome", gain=1.0):
    """Max-combine a small periodic stamp (dome / hex head) into acc in place."""
    k = int(np.ceil(rad)) + 2
    xs = (int(cx) + np.arange(-k, k + 1)) % acc.shape[1]
    ys = (int(cy) + np.arange(-k, k + 1)) % acc.shape[0]
    gx, gy = np.meshgrid(np.arange(-k, k + 1), np.arange(-k, k + 1))
    if kind == "hex":
        d = np.maximum(np.maximum(np.abs(gx), np.abs(gx * 0.5 + gy * 0.866)), np.abs(gx * 0.5 - gy * 0.866)) / rad
        hgt = np.clip((1.0 - d) * 5.0, 0, 1) * 0.9 + np.clip(1.0 - d, 0, 1) * 0.1
    else:
        d = np.hypot(gx, gy) / rad
        hgt = np.sqrt(np.clip(1.0 - d * d, 0.0, 1.0))
    acc[np.ix_(ys, xs)] = np.maximum(acc[np.ix_(ys, xs)], hgt * gain)


def make_plating(n):
    """Riveted armour/industrial plating with seams, bolts, rain streaks and edge wear (tile ~0.8 m)."""
    r = rng(11)
    x, y = grid(n)
    row_edges = np.array([0.0, r.uniform(0.38, 0.55) * n])
    col_sets = [np.array([0.0, r.uniform(0.35, 0.65)]) * n,
                np.array([r.uniform(0.0, 0.1), r.uniform(0.38, 0.5), r.uniform(0.72, 0.85)]) * n]
    seam_d = np.full((n, n), 1e9)
    panel_id = np.zeros((n, n))
    row_idx = np.searchsorted(row_edges, y[:, 0], side="right") - 1
    for e in row_edges:
        d = np.abs(y - e)
        seam_d = np.minimum(seam_d, np.minimum(d, n - d))
    for ri, cols in enumerate(col_sets):
        cols = np.sort(cols)
        m = np.broadcast_to((row_idx == ri)[:, None], (n, n))
        cidx = (np.searchsorted(cols, x[0], side="right") - 1) % len(cols)
        for e in cols:
            d = np.abs(x - e)
            d = np.minimum(d, n - d)
            seam_d = np.where(m, np.minimum(seam_d, d), seam_d)
        panel_id = np.where(m, ri * 10 + cidx[None, :], panel_id)
    pr = rng(12)
    bright = np.zeros((n, n))
    for i in np.unique(panel_id):
        bright[panel_id == i] = pr.uniform(-0.07, 0.07)
    w = px(n, 5.0)
    groove = np.clip(1.0 - seam_d / w, 0.0, 1.0) ** 1.5
    h = -groove * 0.55
    rivets = np.zeros((n, n))
    spacing = px(n, 56.0)
    for sx in np.arange(spacing * 0.5, n, spacing):
        for ey in row_edges:
            for off in (-px(n, 16.0), px(n, 16.0)):
                stamp(rivets, sx, (ey + off) % n, px(n, 5.5))
    h += rivets * 0.55
    bolts = np.zeros((n, n))
    for _ in range(14):
        bx, by = r.integers(0, n, 2)
        stamp(bolts, bx, by, px(n, 9.0), "hex")
    h += bolts * 0.7
    macro = fbm(n, 3.0, 13)
    h += (macro - 0.5) * 0.25
    h += (fbm(n, 0.8, 14, lo=0.05) - 0.5) * 0.06
    scr = splat_lines(n, int(160 * n / 1024), px(n, 40), px(n, 220), 15)
    h -= scr * 0.12
    cav = cavity(h, px(n, 3.0), 2.2)
    wear_noise = fbm(n, 1.2, 16, lo=0.01)
    wear = np.clip(smooth(0.0, 0.18, cav) * smooth(0.35, 0.6, wear_noise) + smooth(0.45, 0.8, scr) * 0.5, 0, 1)
    streak = n01(blur(fbm(n, 0.5, 17, lo=0.02), 0.8, px(n, 70.0)))
    below = np.roll(blur(np.maximum(rivets, bolts), 1.5, px(n, 55.0)), int(px(n, 38.0)), axis=0)
    grime = np.clip(0.16 * smooth(0.45, 0.8, streak) + 2.2 * below * smooth(0.3, 0.7, streak), 0, 0.55)
    grime = np.clip(grime + 0.12 * smooth(0.5, 0.9, macro) + 0.35 * groove, 0, 0.8)
    paint = 0.66 + bright + (fbm(n, 1.5, 18) - 0.5) * 0.08
    alb = lerp(paint, 0.78, wear) * (1.0 - grime * 0.62)
    albedo = np.repeat(alb[..., None], 3, axis=2)
    ao = np.clip(1.0 - np.clip(-cav, 0, 1) * 2.2 - groove * 0.5 - grime * 0.25, 0.25, 1.0)
    rough = 0.52 + (fbm(n, 1.0, 19) - 0.5) * 0.18 + grime * 0.28 - wear * 0.22 + groove * 0.15
    metal = np.clip(0.18 + wear * 0.75 + scr * 0.4 - grime * 0.15, 0, 1)
    return pack(albedo, ao, rough, metal, h * px(n, 11.0), 1.0)


def make_metal_painted(n):
    """Clear-coated automotive/helmet paint: faint orange peel, sparse stone chips, fine swirl scratches. Neutral so it can be tinted."""
    peel = fbm(n, 1.4, 22, lo=0.03, hi=0.2)
    fine = fbm(n, 0.5, 23, lo=0.1, hi=0.5)
    h = (peel - 0.5) * 0.10 + (fine - 0.5) * 0.015
    chips = splat_disks(n, int(260 * n / 1024), px(n, 1.2), px(n, 4.0), 24, "flat")
    chip_cluster = smooth(0.55, 0.78, fbm(n, 2.6, 25))
    chip_mask = np.clip(chips * chip_cluster, 0, 1)
    ring = np.clip(blur(chip_mask, px(n, 1.4)) * 3.0, 0, 1)
    h -= ring * 0.18
    scr = splat_lines(n, int(160 * n / 1024), px(n, 60), px(n, 380), 26)
    h -= scr * 0.02
    film = fbm(n, 3.2, 27)
    film_m = smooth(0.45, 0.85, film)
    alb = 0.93 - film_m * 0.04 + (fine - 0.5) * 0.02 - scr * 0.02
    alb = np.where(chip_mask > 0.5, 0.30, alb)
    alb = lerp(alb, 0.62, np.where(chip_mask > 0.5, 0.0, np.clip(ring - chip_mask, 0, 1) * 0.5))
    albedo = np.repeat(np.clip(alb, 0, 1)[..., None], 3, axis=2)
    ao = np.clip(1.0 - chip_mask * 0.4, 0.5, 1.0)
    rough = 0.24 + (peel - 0.5) * 0.06 + film_m * 0.18 + scr * 0.10
    rough = np.where(chip_mask > 0.5, 0.5, rough)
    metal = 0.30 + (fine - 0.5) * 0.04
    metal = np.where(chip_mask > 0.5, 0.95, metal)
    return pack(albedo, ao, rough, metal, h * px(n, 4.0), 1.0)


def _weave(n, period, pattern):
    """Return (height, warp_mask) for a woven cloth. pattern 'plain' or 'twill'."""
    x, y = grid(n)
    p = period
    i = np.floor(x / p).astype(int)
    j = np.floor(y / p).astype(int)
    u = (x / p) % 1.0
    v = (y / p) % 1.0
    if pattern == "plain":
        warp_over = ((i + j) % 2) == 0
    else:
        warp_over = ((i + j) % 4) < 2
    across_u = np.sin(np.pi * u) ** 0.7
    across_v = np.sin(np.pi * v) ** 0.7
    along_u = 0.78 + 0.22 * np.sin(np.pi * u)
    along_v = 0.78 + 0.22 * np.sin(np.pi * v)
    warp_h = across_u * along_v   # vertical thread: profile across x, undulating along y
    weft_h = across_v * along_u
    h = np.where(warp_over, 0.55 + 0.45 * warp_h, 0.25 + 0.45 * weft_h)
    return h, warp_over


def make_fabric(n):
    """Ripstop cordura-like nylon weave (tile ~0.35 m): fine weave, faint ripstop grid, soft mottling and wear."""
    period = n / 128.0
    h, warp = _weave(n, period, "plain")
    x, y = grid(n)
    rip = (((x / period) % 16) < 1.0) | (((y / period) % 16) < 1.0)
    h = np.where(rip, h + 0.07, h)
    tx = rng(32).uniform(0.95, 1.0, 128)
    ty = rng(33).uniform(0.95, 1.0, 128)
    ci = (x / period).astype(int) % 128
    cj = (y / period).astype(int) % 128
    thread_var = np.where(warp, tx[ci], ty[cj])
    fuzz = fbm(n, 0.3, 34, lo=0.15)
    macro = fbm(n, 3.0, 35)
    mid = fbm(n, 2.0, 36, lo=0.01, hi=0.12)
    wear = smooth(0.55, 0.85, fbm(n, 2.4, 37))
    h = h + (fuzz - 0.5) * 0.10
    cav = cavity(h, period * 0.7, 1.0)
    alb = (0.78 + cav * 0.16) * thread_var * (0.94 + (macro - 0.5) * 0.14 + (mid - 0.5) * 0.10) * (1.0 + wear * 0.06)
    alb = np.where(rip, alb * 1.015, alb)
    albedo = np.repeat(np.clip(alb, 0, 1)[..., None], 3, axis=2)
    ao = np.clip(0.80 + 0.2 * h - np.clip(-cav, 0, 1) * 0.5, 0.45, 1.0)
    rough = 0.86 + (fuzz - 0.5) * 0.08 + (macro - 0.5) * 0.08 - wear * 0.06
    metal = np.zeros((n, n))
    return pack(albedo, ao, rough, metal, h * 1.5 * (n / 1024.0), 1.0)


def make_carbon(n):
    """2x2 twill carbon fibre under a clear coat."""
    period = n / 64.0
    h, warp = _weave(n, period, "twill")
    x, y = grid(n)
    fuzz = fbm(n, 0.4, 41, lo=0.1)
    h = h + (fuzz - 0.5) * 0.05
    cav = cavity(h, period * 0.6, 1.8)
    # tows catch light differently depending on direction
    base = np.where(warp, 0.115, 0.07)
    alb = (base + cav * 0.07 + (fuzz - 0.5) * 0.015)
    albedo = np.repeat(np.clip(alb, 0, 1)[..., None], 3, axis=2) * np.array([1.0, 1.0, 1.02])
    ao = np.clip(0.72 + 0.28 * h - np.clip(-cav, 0, 1) * 0.6, 0.35, 1.0)
    rough = 0.22 + (fuzz - 0.5) * 0.06 + np.where(warp, 0.0, 0.05) + np.clip(-cav, 0, 1) * 0.2
    metal = np.full((n, n), 0.08)
    return pack(albedo, ao, rough, metal, h * 2.4 * (n / 1024.0), 0.55)


def make_rubber(n):
    """Matte rubber / neoprene / grip: fine grain, scuff streaks, dust."""
    grain = fbm(n, 0.2, 51, lo=0.12)
    mid = fbm(n, 1.6, 52, lo=0.02, hi=0.2)
    macro = fbm(n, 3.0, 53)
    scuff = splat_lines(n, int(px(n, 220) * n / 1024), px(n, 40), px(n, 260), 54, angle=0.0, jitter=0.08)
    h = (grain - 0.5) * 0.5 + (mid - 0.5) * 0.35 - scuff * 0.2
    alb = 0.115 + (mid - 0.5) * 0.04 + (macro - 0.5) * 0.04 + scuff * 0.05
    albedo = np.repeat(np.clip(alb, 0, 1)[..., None], 3, axis=2)
    cav = cavity(h, px(n, 2.0), 1.2)
    ao = np.clip(1.0 + cav * 0.8, 0.5, 1.0)
    rough = 0.88 + (grain - 0.5) * 0.12 - scuff * 0.12
    metal = np.zeros((n, n))
    return pack(albedo, ao, rough, metal, h * 3.0 * (n / 1024.0), 1.0)


def make_concrete(n):
    """Weathered cast concrete: aggregate pits, stains, hairline cracks (tile ~2 m)."""
    r = rng(61)
    macro = fbm(n, 3.0, 62)
    mid = fbm(n, 2.0, 63, lo=0.01)
    fine = fbm(n, 0.8, 64, lo=0.05)
    f1, f2, rid = worley(n, int(px(n, 90)) or 8, 65)
    pits = smooth(0.55, 0.15, f1) * smooth(0.62, 0.9, rid)
    pits = np.clip(pits, 0, 1)
    pits_small = splat_disks(n, int(px(n, 1400) * n / 1024), px(n, 1.0), px(n, 3.2), 66, "dome")
    cracks = splat_lines(n, int(px(n, 22) * n / 1024), px(n, 120), px(n, 520), 67, jitter=0.5, step=0.6)
    cracks = np.clip(blur(cracks, 0.4) * 1.8, 0, 1)
    stain = smooth(0.5, 0.85, blur(fbm(n, 2.4, 68), 0.5, px(n, 40.0)))
    h = (macro - 0.5) * 0.4 + (mid - 0.5) * 0.4 + (fine - 0.5) * 0.35 - pits * 0.45 - pits_small * 0.4 - cracks * 0.7
    cav = cavity(h, px(n, 3.0), 1.5)
    alb = 0.50 + (macro - 0.5) * 0.12 + (mid - 0.5) * 0.12 + (fine - 0.5) * 0.06 - stain * 0.15 - pits * 0.12 - pits_small * 0.1 - cracks * 0.2
    albedo = np.stack([alb * 1.0, alb * 0.99, alb * 0.96], axis=-1)
    ao = np.clip(1.0 + cav * 1.2 - pits * 0.3 - cracks * 0.5, 0.3, 1.0)
    rough = 0.86 + (mid - 0.5) * 0.14 - stain * 0.08 + pits * 0.06
    metal = np.zeros((n, n))
    return pack(albedo, ao, rough, metal, h * px(n, 9.0), 1.0)


def make_asphalt(n):
    """Dark asphalt with aggregate, hairline cracks and broad soft wet sheen (no discrete puddles, so it never looks like a pattern)."""
    cells = int(px(n, 150)) or 8
    f1, f2, rid = worley(n, cells, 72)
    stone = smooth(0.42, 0.1, f1) * (0.35 + 0.65 * rid)
    f1b, _, ridb = worley(n, int(px(n, 330)) or 12, 73)
    stone_small = smooth(0.4, 0.08, f1b) * (0.3 + 0.7 * ridb)
    sand = fbm(n, 0.3, 74, lo=0.15)
    macro = fbm(n, 3.0, 75)
    mid = fbm(n, 2.0, 76, lo=0.01)
    cracks = splat_lines(n, int(px(n, 14) * n / 1024), px(n, 160), px(n, 600), 77, jitter=0.4, step=0.6)
    cracks = np.clip(blur(cracks, 0.5) * 1.8, 0, 1)
    wet = 0.5 * smooth(0.3, 0.9, blur(fbm(n, 3.0, 78), 3.0))   # soft broad sheen mask (never mirror-like)
    h = stone * 0.45 + stone_small * 0.3 + (sand - 0.5) * 0.25 - cracks * 0.6 + (mid - 0.5) * 0.2
    h = h * (1.0 - wet * 0.45)
    cav = cavity(h, px(n, 2.5), 1.5)
    alb = 0.17 + stone * 0.2 + stone_small * 0.1 + (sand - 0.5) * 0.05 + (mid - 0.5) * 0.04 - cracks * 0.07
    alb = alb * (1.0 - wet * 0.18)
    albedo = np.repeat(np.clip(alb, 0, 1)[..., None], 3, axis=2)
    ao = np.clip(1.0 + cav * 1.4 - cracks * 0.5, 0.4, 1.0)
    rough = 0.78 + (sand - 0.5) * 0.1 - stone * 0.15 + (mid - 0.5) * 0.12
    rough = lerp(rough, 0.34 + (sand - 0.5) * 0.06 + stone * 0.15, wet)
    metal = np.zeros((n, n))
    return pack(albedo, ao, rough, metal, h * px(n, 6.0), 1.0)


def make_steel(n):
    """Parkerized / brushed gunmetal and bare steel: brushed grain, pitting, scratches, oily wear."""
    grain = fbm(n, 0.2, 81, lo=0.05)
    brush = blur(grain, px(n, 26.0), 0.35)
    brush = n01(brush)
    brush2 = n01(blur(fbm(n, 0.2, 82, lo=0.05), px(n, 10.0), 0.3))
    macro = fbm(n, 3.0, 83)
    pits = splat_disks(n, int(px(n, 900) * n / 1024), px(n, 0.8), px(n, 2.6), 84, "dome")
    scr = splat_lines(n, int(px(n, 340) * n / 1024), px(n, 50), px(n, 420), 85, angle=0.0, jitter=0.25)
    scr2 = splat_lines(n, int(px(n, 90) * n / 1024), px(n, 60), px(n, 300), 86)
    h = (brush - 0.5) * 0.35 + (brush2 - 0.5) * 0.2 - pits * 0.4 - scr * 0.18 - scr2 * 0.12
    alb = 0.47 + (brush - 0.5) * 0.12 + (macro - 0.5) * 0.1 + scr * 0.1 + scr2 * 0.08 - pits * 0.12
    albedo = np.stack([alb * 0.96, alb * 0.98, alb * 1.03], axis=-1)
    ao = np.clip(1.0 - pits * 0.5, 0.5, 1.0)
    rough = 0.40 + (brush - 0.5) * 0.18 + (macro - 0.5) * 0.14 - scr * 0.12 + pits * 0.1
    metal = np.clip(0.92 + (macro - 0.5) * 0.2 - pits * 0.25, 0.4, 1.0)
    return pack(albedo, ao, rough, metal, h * px(n, 4.0), 1.0)


def make_glass(n):
    """Dirty glass for visors/windscreens: dust film, smudges, rain droplets and short trails. Neutral albedo."""
    smudge = fbm(n, 2.6, 91)
    dust = fbm(n, 0.4, 92, lo=0.08)
    drops = np.zeros((n, n))
    r = rng(93)
    for _ in range(int(70 * n / 1024)):
        cx, cy = r.integers(0, n, 2)
        rad = r.uniform(px(n, 4.0), px(n, 14.0))
        stamp(drops, cx, cy, rad)
        if r.random() < 0.35:   # a short running trail below the droplet
            ln = int(r.uniform(px(n, 30), px(n, 120)))
            for t in range(0, ln, 2):
                stamp(drops, cx + r.normal(0, 0.6), (cy + t) % n, max(1.2, rad * 0.22 * (1 - t / ln)), gain=0.55)
    h = drops * 0.8 + (smudge - 0.5) * 0.08 + (dust - 0.5) * 0.02
    film = smooth(0.45, 0.85, smudge)
    alb = 0.93 - film * 0.025 - (dust - 0.5) * 0.02
    albedo = np.repeat(np.clip(alb, 0, 1)[..., None], 3, axis=2)
    ao = np.ones((n, n))
    rough = 0.05 + film * 0.30 + np.clip((dust - 0.5) * 0.2, 0, 1) - drops * 0.045
    metal = np.zeros((n, n))
    return pack(albedo, ao, rough, metal, h * px(n, 7.0), 1.0)


SETS = {
    "plating": make_plating,
    "metal_painted": make_metal_painted,
    "fabric": make_fabric,
    "carbon": make_carbon,
    "rubber": make_rubber,
    "concrete": make_concrete,
    "asphalt": make_asphalt,
    "steel": make_steel,
    "glass": make_glass,
}


def preview_sheet(out_path, built, tile=256):
    """Contact sheet: one row per set (albedo | roughness | metallic | normal | tiled 2x2 albedo)."""
    rows = []
    for name, (a, orm, nm) in built.items():
        step = max(1, a.shape[0] // tile)
        A = a[::step, ::step][:tile, :tile]
        R = np.repeat(orm[::step, ::step, 1:2][:tile, :tile], 3, axis=2)
        M = np.repeat(orm[::step, ::step, 2:3][:tile, :tile], 3, axis=2)
        N = nm[::step, ::step][:tile, :tile]
        T = np.tile(A, (2, 2, 1))[::2, ::2][:tile, :tile]
        rows.append(np.concatenate([A, R, M, N, T], axis=1))
    write_png(out_path, np.concatenate(rows, axis=0))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--out", default=os.path.join(ROOT, "assets", "generated", "textures"))
    ap.add_argument("--only", default="")
    ap.add_argument("--preview", default="")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    only = [s for s in args.only.split(",") if s]
    built = {}
    for name, fn in SETS.items():
        if only and name not in only:
            continue
        t0 = time.time()
        a, orm, nm = fn(args.size)
        write_png(os.path.join(args.out, name + "_albedo.png"), a.mean(axis=2))   # neutral grey: models tint it with material factors
        write_png(os.path.join(args.out, name + "_orm.png"), orm)
        write_png(os.path.join(args.out, name + "_normal.png"), nm)
        built[name] = (a, orm, nm)
        sizes = [os.path.getsize(os.path.join(args.out, name + s)) for s in ("_albedo.png", "_orm.png", "_normal.png")]
        print("%-14s %4d px  %.1fs  albedo %5d KB  orm %5d KB  normal %5d KB" % (name, args.size, time.time() - t0, sizes[0] // 1024, sizes[1] // 1024, sizes[2] // 1024))
    if args.preview and built:
        preview_sheet(args.preview, built)
        print("preview", args.preview)


if __name__ == "__main__":
    sys.exit(main())
