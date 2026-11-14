"""Material swatches of the weapon kit (wave 114): 28 tileable 128 x 128 PBR swatches generated with numpy (no photos, no downloads), packed 4 x 8 into three 512 x 1024 images
(albedo sRGB, ORM linear = chip mask / roughness / metallic, normal linear) that Godot imports as texture arrays (one layer per swatch, so every swatch wraps on its own).

Convention of the runtime shader (assets/shaders/weapon_pbr.gdshader): ALBEDO = swatch.rgb * 2 * vertex colour. Relative swatches are authored around 0.5 (so the vertex colour IS the base albedo
and the swatch only adds grain, streaks, stipple and wear); absolute swatches (camo, hazard stripes, labels) are authored in their own colours and used with a vertex colour of 0.5.
The ORM red channel is a chip mask for the edge wear (worn paint shows bare metal where the wear mask of the vertex plus this noise is high).
Run:  python weapon_mats.py [outdir]   (default: assets/models/weapons)
"""
import math
import os
import sys

import numpy as np

N = 128
COLS = 4
ROWS = 8                                                              # 32 layers: 512 x 1024 images, slices 4 x 8

NAMES = ["POLY", "RUBBER", "STEEL_P", "STEEL_B", "STEEL_BRIGHT", "ALLOY", "ANODISED", "WOOD_DARK", "WOOD_LIGHT", "CERAMIC", "PAINT", "CAMO_A", "CAMO_B", "CAMO_C",
         "CARBON", "BRASS", "LEATHER", "GLASS", "CORE", "COIL", "HAZARD", "SCREEN", "FABRIC", "CHROME", "TITANIUM", "RUBBER_SMOOTH", "GLOSS", "LABEL"]
(POLY, RUBBER, STEEL_P, STEEL_B, STEEL_BRIGHT, ALLOY, ANODISED, WOOD_DARK, WOOD_LIGHT, CERAMIC, PAINT, CAMO_A, CAMO_B, CAMO_C,
 CARBON, BRASS, LEATHER, GLASS, CORE, COIL, HAZARD, SCREEN, FABRIC, CHROME, TITANIUM, RUBBER_SMOOTH, GLOSS, LABEL) = range(len(NAMES))

# per layer: how many metres one tile covers (the shader scales the object-space projection by 1 / tile), metallic hint for the previews and the report
TILE = {POLY: 0.05, RUBBER: 0.035, STEEL_P: 0.06, STEEL_B: 0.08, STEEL_BRIGHT: 0.08, ALLOY: 0.08, ANODISED: 0.07, WOOD_DARK: 0.14, WOOD_LIGHT: 0.14, CERAMIC: 0.12, PAINT: 0.1,
        CAMO_A: 0.3, CAMO_B: 0.3, CAMO_C: 0.3, CARBON: 0.05, BRASS: 0.05, LEATHER: 0.06, GLASS: 0.1, CORE: 0.06, COIL: 0.04, HAZARD: 0.12, SCREEN: 0.06, FABRIC: 0.04,
        CHROME: 0.1, TITANIUM: 0.08, RUBBER_SMOOTH: 0.05, GLOSS: 0.1, LABEL: 0.06}
METALLIC = {STEEL_P, STEEL_B, STEEL_BRIGHT, ALLOY, ANODISED, BRASS, CHROME, TITANIUM}
EMISSIVE = {CORE, COIL, SCREEN}
ABSOLUTE = {CAMO_A, CAMO_B, CAMO_C, HAZARD, LABEL}
# average colour (linear, as the 2 * swatch * vertex colour convention gives with tint 1) for the LOD1 colour classes of FoeArms and the previews
LAYER_BASE = {POLY: (0.05, 0.052, 0.056), RUBBER: (0.035, 0.036, 0.04), STEEL_P: (0.17, 0.18, 0.19), STEEL_B: (0.1, 0.11, 0.13), STEEL_BRIGHT: (0.55, 0.56, 0.58), ALLOY: (0.5, 0.52, 0.55),
              ANODISED: (0.3, 0.3, 0.34), WOOD_DARK: (0.07, 0.04, 0.024), WOOD_LIGHT: (0.35, 0.22, 0.11), CERAMIC: (0.5, 0.52, 0.55), PAINT: (0.3, 0.3, 0.3), CAMO_A: (0.12, 0.14, 0.07),
              CAMO_B: (0.35, 0.28, 0.16), CAMO_C: (0.25, 0.27, 0.3), CARBON: (0.03, 0.03, 0.035), BRASS: (0.62, 0.42, 0.14), LEATHER: (0.13, 0.07, 0.04), GLASS: (0.04, 0.07, 0.1),
              CORE: (0.2, 0.9, 1.0), COIL: (0.2, 0.8, 1.0), HAZARD: (0.5, 0.4, 0.05), SCREEN: (0.02, 0.05, 0.06), FABRIC: (0.12, 0.12, 0.09), CHROME: (0.7, 0.72, 0.75),
              TITANIUM: (0.3, 0.32, 0.36), RUBBER_SMOOTH: (0.03, 0.03, 0.033), GLOSS: (0.4, 0.4, 0.42), LABEL: (0.4, 0.4, 0.35)}


def _fft(n, rng, beta=1.0, sx=1.0, sy=1.0):
    """Periodic noise with a 1/f^beta spectrum; sx scales the frequency along u (columns), sy along v (rows): sx > 1 stretches the features along u."""
    f = np.fft.fft2(rng.standard_normal((n, n)))
    fu = np.fft.fftfreq(n)[None, :] * sx
    fv = np.fft.fftfreq(n)[:, None] * sy
    r = np.sqrt(fu ** 2 + fv ** 2)
    r[0, 0] = 1.0
    f = f / r ** beta
    f[0, 0] = 0.0
    o = np.real(np.fft.ifft2(f))
    return (o - o.mean()) / max(o.std(), 1e-9)


def _voronoi(n, cells, rng, jitter=0.8):
    """Periodic cellular noise: returns (distance to the nearest feature point, id of that point), both in [0, 1]."""
    pts = (np.stack(np.meshgrid(np.arange(cells), np.arange(cells), indexing="ij"), axis=-1) + 0.5 + (rng.rand(cells, cells, 2) - 0.5) * jitter) / cells
    yy, xx = np.meshgrid((np.arange(n) + 0.5) / n, (np.arange(n) + 0.5) / n, indexing="ij")
    best = np.full((n, n), 9.0)
    ids = np.zeros((n, n))
    for a in range(cells):
        for b in range(cells):
            py, px = pts[a, b]
            for oy in (-1, 0, 1):
                for ox in (-1, 0, 1):
                    d = np.hypot(yy - (py + oy), xx - (px + ox))
                    m = d < best
                    best = np.where(m, d, best)
                    ids = np.where(m, (a * cells + b) / float(cells * cells), ids)
    return np.clip(best * cells * 0.9, 0, 1), ids


def _normal(h, strength):
    """Tangent-space normal from a periodic height field (u along columns)."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 * strength
    nx, ny, nz = -dx, -dy, np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / ln, ny / ln, nz / ln], axis=-1)


def _scratches(n, rng, count, length, along_u=True, k=1.0):
    img = np.zeros((n, n))
    for _ in range(count):
        x, y = rng.randint(0, n), rng.randint(0, n)
        a = (0.0 if along_u else math.pi / 2) + (rng.rand() - 0.5) * 0.5
        L = int(length * (0.4 + rng.rand()))
        for t in range(L):
            img[int(y + math.sin(a) * t) % n, int(x + math.cos(a) * t) % n] += k * (0.5 + 0.5 * rng.rand())
    return np.clip(img, 0, 1)


def _blur(img, r):
    f = np.fft.fft2(img)
    fu = np.fft.fftfreq(img.shape[1])[None, :]
    fv = np.fft.fftfreq(img.shape[0])[:, None]
    g = np.exp(-(fu ** 2 + fv ** 2) * (2 * math.pi * r) ** 2 / 2)
    return np.real(np.fft.ifft2(f * g))


def _sw(rgb, rough, metal, chips, normal):
    return {"rgb": np.clip(rgb, 0, 1), "rough": np.clip(rough, 0.02, 1), "metal": np.clip(metal, 0, 1), "chips": np.clip(chips, 0, 1), "normal": normal}


def swatch(layer, seed=1):
    rng = np.random.RandomState(1000 + layer * 17 + seed)
    n = N
    fine = _fft(n, rng, 0.2)
    mid = _fft(n, rng, 1.2)
    big = _fft(n, rng, 2.0)
    chips = np.clip(0.5 + 0.35 * _fft(n, rng, 0.8), 0, 1)
    one = np.ones((n, n))
    g = lambda v: np.stack([v, v, v], axis=-1)
    if layer == POLY:
        vd, _ = _voronoi(n, 22, rng, 0.9)
        h = 0.6 * (1 - vd) + 0.25 * fine
        return _sw(g(0.5 + 0.025 * fine + 0.03 * (1 - vd)), 0.6 + 0.06 * mid, 0 * one, chips, _normal(h, 1.1))
    if layer == RUBBER:
        vd, _ = _voronoi(n, 12, rng, 0.9)
        h = 0.9 * (1 - vd) ** 0.7 + 0.1 * fine
        return _sw(g(0.5 + 0.03 * fine - 0.06 * vd), 0.82 + 0.06 * mid, 0 * one, chips, _normal(h, 4.0))
    if layer == STEEL_P:
        h = 0.5 * fine + 0.3 * _fft(n, rng, 0.0)
        return _sw(g(0.5 + 0.035 * fine + 0.02 * mid), 0.56 + 0.05 * fine, one, chips, _normal(h, 0.8))
    if layer == STEEL_B:
        st = _fft(n, rng, 0.6, 7.0, 1.0)
        return _sw(g(0.5 + 0.03 * st + 0.015 * mid), 0.3 + 0.04 * st, one, chips, _normal(0.1 * st, 0.6))
    if layer == STEEL_BRIGHT:
        sc = _scratches(n, rng, 26, 60, True, 0.35)
        st = _fft(n, rng, 0.5, 8.0, 1.0)
        return _sw(g(0.5 + 0.03 * st + 0.015 * mid - 0.05 * sc), 0.16 + 0.04 * st + 0.08 * sc, one, chips, _normal(0.25 * st - 0.4 * sc, 0.9))
    if layer == ALLOY:
        st = _fft(n, rng, 0.5, 9.0, 1.0)
        return _sw(g(0.5 + 0.05 * st), 0.38 + 0.07 * st, one, chips, _normal(0.18 * st, 0.8))
    if layer == ANODISED:
        return _sw(g(0.5 + 0.025 * fine + 0.02 * mid), 0.44 + 0.04 * fine, one, chips, _normal(0.3 * fine, 0.8))
    if layer in (WOOD_DARK, WOOD_LIGHT):
        fq = 14 if layer == WOOD_DARK else 9
        v = np.arange(n)[:, None] / n
        warp = 0.07 * _fft(n, rng, 1.0, 3.0, 1.0)
        rings = np.sin(2 * math.pi * (v * fq + warp * fq)) * 0.5 + 0.5
        fib = _fft(n, rng, 0.2, 14.0, 1.0)
        lum = 0.5 + 0.3 * (rings - 0.5) + 0.1 * fib + 0.03 * big
        return _sw(g(lum), 0.5 + 0.08 * rings, 0 * one, chips, _normal(0.5 * fib + 0.3 * rings, 1.8))
    if layer == CERAMIC:
        return _sw(g(0.5 + 0.012 * fine + 0.02 * big), 0.2 + 0.03 * mid, 0 * one, chips, _normal(0.1 * big, 0.5))
    if layer == PAINT:
        peel = _fft(n, rng, 0.1)
        return _sw(g(0.5 + 0.02 * peel + 0.025 * big), 0.46 + 0.04 * peel, 0 * one, chips, _normal(0.25 * peel, 0.9))
    if layer in (CAMO_A, CAMO_B, CAMO_C):
        cols = {CAMO_A: [(0.075, 0.085, 0.04), (0.04, 0.06, 0.03), (0.12, 0.085, 0.045), (0.02, 0.022, 0.02)],
                CAMO_B: [(0.4, 0.31, 0.18), (0.26, 0.19, 0.1), (0.5, 0.42, 0.27), (0.14, 0.1, 0.06)],
                CAMO_C: [(0.34, 0.36, 0.4), (0.2, 0.22, 0.26), (0.5, 0.52, 0.55), (0.1, 0.11, 0.13)]}[layer]
        a = _fft(n, rng, 1.6)
        b = _fft(n, rng, 1.9)
        c = _fft(n, rng, 2.4)
        img = np.zeros((n, n, 3))
        img[:] = cols[0]
        for k, (field, thr) in enumerate(((a, 0.35), (b, 0.5), (c, 0.9))):
            m = (field > thr)[..., None]
            img = np.where(m, np.array(cols[k + 1]), img)
        img = img * (0.72 + 0.07 * fine[..., None])
        return _sw(img, 0.62 + 0.05 * fine, 0 * one, chips, _normal(0.2 * fine, 1.0))
    if layer == CARBON:
        u = np.arange(n)[None, :] / n * 32
        v = np.arange(n)[:, None] / n * 32
        wv = np.sin(2 * math.pi * (u + v)) * np.sin(2 * math.pi * (u - v) * 0.5)
        tw = 0.5 + 0.5 * np.sign(np.sin(math.pi * (np.floor(u) + np.floor(v)))) * 0.4
        h = 0.5 * wv + 0.2 * tw
        return _sw(g(0.5 + 0.2 * wv + 0.05 * fine), 0.24 + 0.08 * wv, 0 * one, chips, _normal(h, 2.0))
    if layer == BRASS:
        st = _fft(n, rng, 0.5, 8.0, 1.0)
        return _sw(g(0.5 + 0.05 * st + 0.03 * mid), 0.32 + 0.05 * st, one, chips, _normal(0.15 * st, 0.6))
    if layer == LEATHER:
        vd, _ = _voronoi(n, 16, rng, 1.0)
        creases = np.clip(1 - vd * 2.2, 0, 1)
        return _sw(g(0.5 + 0.06 * fine - 0.1 * (1 - creases) + 0.04 * mid), 0.68 + 0.08 * creases, 0 * one, chips, _normal(0.7 * creases + 0.2 * fine, 3.0))
    if layer == GLASS:
        return _sw(g(0.5 + 0.01 * big), 0.04 + 0.01 * fine, 0.15 * one, chips, _normal(0.0 * fine, 0.1))
    if layer == CORE:
        vd, ids = _voronoi(n, 10, rng, 1.0)
        veins = np.clip(1 - vd * 1.3, 0, 1) ** 1.6
        core = 0.45 + 0.5 * veins + 0.1 * mid
        return _sw(g(np.clip(core, 0, 1)), 0.2 + 0.05 * fine, 0.0 * one, chips, _normal(0.3 * veins, 1.2))
    if layer == COIL:
        u = np.arange(n)[None, :] / n
        band = 0.5 + 0.5 * np.sin(2 * math.pi * u * 8)
        return _sw(g(np.clip(0.2 + 0.7 * band ** 2 + 0.05 * fine, 0, 1)), 0.25 + 0.1 * band, 0.4 * one, chips, _normal(0.8 * band, 2.0))
    if layer == HAZARD:
        u = np.arange(n)[None, :] / n
        v = np.arange(n)[:, None] / n
        s = (np.floor((u + v) * 8) % 2).astype(float)
        col = np.where(s[..., None] > 0.5, np.array((0.65, 0.5, 0.04)), np.array((0.025, 0.025, 0.025)))
        return _sw(col * (1 + 0.1 * fine[..., None]), 0.5 + 0.05 * fine, 0 * one, chips, _normal(0.15 * fine, 0.8))
    if layer == SCREEN:
        v = np.arange(n)[:, None] / n
        scan = 0.5 + 0.5 * np.sin(2 * math.pi * v * 64)
        grid = (np.floor(np.arange(n)[None, :] / 4) % 2) * 0.1
        return _sw(g(np.clip(0.3 + 0.35 * scan + grid + 0.1 * fine, 0, 1)), 0.1 * one, 0.1 * one, chips, _normal(0.1 * scan, 0.5))
    if layer == FABRIC:
        u = np.arange(n)[None, :] / n * 40
        v = np.arange(n)[:, None] / n * 40
        wv = np.sin(2 * math.pi * u) * np.sin(2 * math.pi * v)
        return _sw(g(0.5 + 0.12 * wv + 0.05 * fine), 0.9 + 0.04 * fine, 0 * one, chips, _normal(wv, 1.8))
    if layer == CHROME:
        return _sw(g(0.5 + 0.01 * mid), 0.05 + 0.02 * np.abs(fine), one, chips, _normal(0.05 * mid, 0.4))
    if layer == TITANIUM:
        st = _fft(n, rng, 0.5, 6.0, 1.0)
        return _sw(g(0.5 + 0.05 * st + 0.03 * big), 0.32 + 0.05 * st, one, chips, _normal(0.15 * st, 0.6))
    if layer == RUBBER_SMOOTH:
        return _sw(g(0.5 + 0.02 * fine), 0.93 + 0.03 * fine, 0 * one, chips, _normal(0.2 * fine, 0.8))
    if layer == GLOSS:
        return _sw(g(0.5 + 0.015 * big), 0.22 + 0.03 * mid, 0 * one, chips, _normal(0.05 * big, 0.4))
    if layer == LABEL:
        u = np.arange(n)[None, :]
        v = np.arange(n)[:, None]
        bars = ((u // 3) % 2 == 0) & (rng.rand(1, n // 3 + 1).repeat(3, axis=1)[:, :n] > 0.45)
        band = ((v // 32) % 2 == 0)
        col = np.where((bars & band)[..., None], np.array((0.03, 0.03, 0.03)), np.array((0.55, 0.52, 0.42)))
        return _sw(col, 0.6 * one, 0 * one, chips, _normal(0.0 * fine, 0.1))
    return _sw(g(0.5 + 0 * fine), 0.5 * one, 0 * one, chips, _normal(0.0 * fine, 0.1))


def srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def build_atlas(outdir):
    A = np.zeros((ROWS * N, COLS * N, 3), dtype=np.uint8)
    O = np.zeros_like(A)
    R = np.zeros_like(A)
    for i in range(len(NAMES)):
        s = swatch(i)
        r, c = divmod(i, COLS)
        sl = (slice(r * N, (r + 1) * N), slice(c * N, (c + 1) * N))
        rgb = s["rgb"]
        A[sl] = np.round(srgb(rgb) * 255).astype(np.uint8)             # authored in linear (relative swatches around 0.5), stored sRGB, the sampler decodes it back
        O[sl + (0,)] = np.round(s["chips"] * 255).astype(np.uint8)
        O[sl + (1,)] = np.round(s["rough"] * 255).astype(np.uint8)
        O[sl + (2,)] = np.round(s["metal"] * 255).astype(np.uint8)
        R[sl] = np.round((s["normal"] * 0.5 + 0.5) * 255).astype(np.uint8)
    os.makedirs(outdir, exist_ok=True)
    from PIL import Image
    Image.fromarray(A).save(os.path.join(outdir, "weapon_atlas_alb.png"), optimize=True)
    Image.fromarray(O).save(os.path.join(outdir, "weapon_atlas_orm.png"), optimize=True)
    Image.fromarray(R).save(os.path.join(outdir, "weapon_atlas_nrm.png"), optimize=True)
    return [os.path.join(outdir, f) for f in ("weapon_atlas_alb.png", "weapon_atlas_orm.png", "weapon_atlas_nrm.png")]


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models", "weapons")
    for p in build_atlas(out):
        print(p, os.path.getsize(p) // 1024, "KB")
