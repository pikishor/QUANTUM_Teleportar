"""Texel shading for the baked model atlases (numpy only, no bpy): surface kinds, procedural noise and decals.

The baker (atlas.py) hands every shading function the same context `c` for the texels of one kind (index array `i` into the
context arrays): object-space position `P` (metres), shading normal `N`, base colour `C` (linear, from the model script), the
distance to the nearest convex / concave crease `cx` / `cc` (metres, 9 for "far"), ambient occlusion `ao`, the texel's pixel
coordinates `uv` (for directional patterns that follow the surface), and the output arrays
alb (linear), rough, metal, emit (linear colour, multiplied by the material's emission strength in Godot) and height (metres, drives the
normal map).

Wear comes from the geometry: convex creases (bevelled edges) chip and brighten, concave creases and low areas collect grime,
cavities (ao) darken, and large-scale noise breaks up every flat colour so no surface reads as clean plastic.
"""
import math

import numpy as np


# ------------------------------------------------------------------ small helpers
def sm(e0, e1, x):
    """smoothstep from e0 to e1 (works with e0 > e1 to invert)."""
    t = np.clip((x - e0) / (e1 - e0 + 1e-12), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


class Noise:
    """Deterministic value noise on a hashed lattice: 3D (object space, continuous across UV seams) and 2D (texture space, for
    patterns that follow the surface, like brushed metal)."""

    def __init__(self, seed=1):
        r = np.random.default_rng(seed)
        self.t3 = r.random((64, 64, 64)).astype(np.float32)
        self.t2 = r.random((256, 256)).astype(np.float32)
        self.off = r.random((16, 3)) * 61.0

    def v3(self, x, y, z):
        xi = np.floor(x)
        yi = np.floor(y)
        zi = np.floor(z)
        fx = (x - xi).astype(np.float32)
        fy = (y - yi).astype(np.float32)
        fz = (z - zi).astype(np.float32)
        xi = xi.astype(np.int64)
        yi = yi.astype(np.int64)
        zi = zi.astype(np.int64)
        ux, uy, uz = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy), fz * fz * (3 - 2 * fz)
        x0, x1 = xi & 63, (xi + 1) & 63
        y0, y1 = yi & 63, (yi + 1) & 63
        z0, z1 = zi & 63, (zi + 1) & 63
        t = self.t3
        c00 = t[x0, y0, z0] * (1 - ux) + t[x1, y0, z0] * ux
        c10 = t[x0, y1, z0] * (1 - ux) + t[x1, y1, z0] * ux
        c01 = t[x0, y0, z1] * (1 - ux) + t[x1, y0, z1] * ux
        c11 = t[x0, y1, z1] * (1 - ux) + t[x1, y1, z1] * ux
        return (c00 * (1 - uy) + c10 * uy) * (1 - uz) + (c01 * (1 - uy) + c11 * uy) * uz

    def fbm3(self, P, freq, octaves=4, gain=0.5, seed=0):
        """Fractal value noise at P * freq (freq in cycles per metre), 0..1, mean 0.5."""
        total = np.zeros(len(P), np.float32)
        amp, norm = 1.0, 0.0
        for o in range(octaves):
            q = P * (freq * (2.03 ** o)) + self.off[(seed + o) % 16]
            total += amp * self.v3(q[:, 0], q[:, 1], q[:, 2])
            norm += amp
            amp *= gain
        return total / norm

    def v2(self, x, y):
        xi = np.floor(x)
        yi = np.floor(y)
        fx = (x - xi).astype(np.float32)
        fy = (y - yi).astype(np.float32)
        xi = xi.astype(np.int64)
        yi = yi.astype(np.int64)
        ux, uy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        x0, x1 = xi & 255, (xi + 1) & 255
        y0, y1 = yi & 255, (yi + 1) & 255
        t = self.t2
        return (t[y0, x0] * (1 - ux) + t[y0, x1] * ux) * (1 - uy) + (t[y1, x0] * (1 - ux) + t[y1, x1] * ux) * uy

    def fbm2(self, x, y, octaves=3, gain=0.5):
        total = np.zeros(len(x), np.float32)
        amp, norm = 1.0, 0.0
        for o in range(octaves):
            k = 2.03 ** o
            total += amp * self.v2(x * k + 17.0 * o, y * k + 31.0 * o)
            norm += amp
            amp *= gain
        return total / norm


class Ctx:
    """Per-texel inputs and outputs of one bake. All arrays have one row per valid texel."""

    def __init__(self, noise, P, N, C, ao, cx, cc, uvpx, T, px_per_m):
        self.noise = noise
        self.P, self.N, self.C, self.ao, self.cx, self.cc, self.uv, self.T = P, N, C, ao, cx, cc, uvpx, T
        self.ppm = px_per_m
        n = len(P)
        self.alb = np.full((n, 3), 0.1, np.float32)
        self.rough = np.full(n, 0.6, np.float32)
        self.metal = np.zeros(n, np.float32)
        self.emit = np.zeros((n, 3), np.float32)
        self.height = np.zeros(n, np.float32)

    def f3(self, i, freq, octaves=4, seed=0):
        return self.noise.fbm3(self.P[i], freq, octaves, 0.5, seed)

    def f2(self, i, fx, fy, octaves=3, ox=0.0, oy=0.0):
        """Noise in texture space, `fx`/`fy` in cycles per metre along the island axes (so patterns follow the surface)."""
        u = self.uv[i, 0] / self.ppm
        v = self.uv[i, 1] / self.ppm
        return self.noise.fbm2(u * fx + ox, v * fy + oy, octaves)


# ------------------------------------------------------------------ surface kinds
def grime_mask(c, i, base=0.8, low=0.5, cavity=1.0, crease=0.4, seed=3):
    """Dirt: cavities, low parts of the model (spray and dust), concave creases, broken up by noise (0..1)."""
    P = c.P[i]
    mott = c.noise.fbm3(P, 6.0, 3, 0.5, seed)
    low_k = sm(low, 0.0, P[:, 2]) * (0.35 + 0.65 * mott)
    return np.clip(base * (1.0 - c.ao[i]) * cavity + low_k * 0.7 + crease * sm(0.012, 0.0, c.cc[i]) * (0.5 + mott), 0.0, 1.0)


def streaks(c, i, freq=38.0, length=3.0, seed=5):
    """Vertical rain/drip streak mask 0..1 (noise stretched along the world Z axis)."""
    P = c.P[i].copy()
    P[:, 2] *= 1.0 / length
    return sm(0.52, 0.9, c.noise.fbm3(P, freq, 3, 0.5, seed))


def shade_fabric(c, i):
    P, C = c.P[i], c.C[i]
    mott = c.noise.fbm3(P, 5.0, 4, 0.5, 1)
    fine = c.noise.fbm3(P, 150.0, 2, 0.5, 2)
    weave = 0.5 + 0.5 * np.sin(c.uv[i, 0] / c.ppm * 2 * math.pi * 330.0) * np.sin(c.uv[i, 1] / c.ppm * 2 * math.pi * 330.0)
    alb = C * (0.78 + 0.44 * mott)[:, None] * (0.93 + 0.14 * fine)[:, None] * (0.97 + 0.03 * weave)[:, None]
    edge = sm(0.007, 0.0, c.cx[i]) * (0.35 + 0.65 * c.noise.fbm3(P, 70.0, 2, 0.5, 4))
    alb = alb * (1.0 + 0.7 * edge)[:, None] + 0.012 * edge[:, None]
    dirt = grime_mask(c, i, 0.9, 0.45, 1.0, 0.5, 3)
    alb = alb * (1.0 - 0.55 * dirt)[:, None] * np.array([1.0, 0.96, 0.9])
    c.alb[i] = alb
    c.rough[i] = np.clip(0.86 + 0.10 * (fine - 0.5) + 0.06 * dirt - 0.12 * edge, 0, 1)
    c.metal[i] = 0.0
    c.height[i] = 0.00035 * (fine - 0.5) + 0.0002 * (weave - 0.5) - 0.0006 * sm(0.004, 0.0, c.cc[i]) - 0.0004 * dirt


def shade_plating(c, i):
    """Painted composite armour: paint chips to bare metal along edges and scratches, panel grooves, rain streaks, grime."""
    P, C = c.P[i], c.C[i]
    mott = c.noise.fbm3(P, 4.0, 4, 0.5, 11)
    fine = c.noise.fbm3(P, 120.0, 2, 0.5, 12)
    nz = c.noise.fbm3(P, 55.0, 3, 0.5, 13)
    ridge = 1.0 - np.abs(2.0 * c.noise.fbm3(P, 22.0, 2, 0.5, 14) - 1.0)
    scratch = sm(0.965, 0.995, ridge) * sm(0.45, 0.7, nz)
    chip = sm(0.0065, 0.0008, c.cx[i]) * sm(0.18, 0.62, nz) + scratch * 0.8
    chip = np.clip(chip, 0.0, 1.0)
    paint = C * (0.84 + 0.32 * mott)[:, None] * (0.95 + 0.1 * fine)[:, None]
    bare = np.array([0.50, 0.50, 0.52]) * (0.75 + 0.5 * fine)[:, None]
    dirt = grime_mask(c, i, 0.8, 0.45, 1.0, 0.7, 5)
    st = streaks(c, i)
    gr = np.clip(dirt + 0.35 * st * (0.4 + 0.6 * mott), 0, 1)
    alb = paint * (1.0 - 0.5 * gr)[:, None] * np.array([1.0, 0.97, 0.92])
    alb = alb * (1.0 - chip[:, None]) + bare * chip[:, None] * (1.0 - 0.45 * dirt[:, None])
    groove = sm(0.0025, 0.0, c.cc[i])
    alb = alb * (1.0 - 0.5 * groove)[:, None]
    c.alb[i] = alb
    c.rough[i] = np.clip(lerp(0.50 + 0.12 * (mott - 0.5) + 0.12 * gr, 0.34 + 0.1 * fine, chip), 0, 1)
    c.metal[i] = np.clip(chip * 0.95, 0, 1)
    c.height[i] = -0.0006 * chip - 0.0009 * groove + 0.0002 * (fine - 0.5) - 0.0002 * st


def shade_steel(c, i):
    """Parkerized / gunmetal: brushed streaks along the surface, polished edge wear, oily patches."""
    P, C = c.P[i], c.C[i]
    mott = c.noise.fbm3(P, 8.0, 3, 0.5, 21)
    brush = c.f2(i, 18.0, 900.0, 3, 5.0, 9.0)
    nz = c.noise.fbm3(P, 60.0, 3, 0.5, 22)
    edge = sm(0.0045, 0.0005, c.cx[i]) * sm(0.15, 0.6, nz)
    dirt = grime_mask(c, i, 0.7, 0.4, 0.8, 0.5, 23)
    base = C * (0.8 + 0.4 * mott)[:, None] * (0.85 + 0.3 * brush)[:, None]
    polished = np.array([0.46, 0.47, 0.50]) * (0.8 + 0.4 * brush)[:, None]
    alb = base * (1.0 - edge[:, None]) + polished * edge[:, None]
    alb = alb * (1.0 - 0.4 * dirt)[:, None]
    c.alb[i] = alb
    c.rough[i] = np.clip(0.42 + 0.22 * (brush - 0.5) + 0.18 * dirt - 0.18 * edge, 0.1, 1)
    c.metal[i] = np.clip(0.82 + 0.18 * edge - 0.25 * dirt, 0, 1)
    c.height[i] = 0.0002 * (brush - 0.5) - 0.0003 * sm(0.003, 0.0, c.cc[i])


def shade_rubber(c, i):
    P, C = c.P[i], c.C[i]
    grain = c.noise.fbm3(P, 160.0, 2, 0.5, 31)
    mott = c.noise.fbm3(P, 6.0, 3, 0.5, 32)
    scuff = sm(0.006, 0.0, c.cx[i]) * (0.3 + 0.7 * c.noise.fbm3(P, 50.0, 2, 0.5, 33))
    dirt = grime_mask(c, i, 0.8, 0.5, 1.0, 0.5, 34)
    dust = np.array([0.1, 0.095, 0.09])
    alb = C * (0.8 + 0.4 * mott)[:, None] * (0.9 + 0.2 * grain)[:, None]
    alb = alb * (1.0 - scuff[:, None]) + (dust + C * 0.5) * scuff[:, None] * 0.6
    alb = alb + dust * 0.5 * dirt[:, None] * sm(0.5, 0.0, P[:, 2])[:, None]
    c.alb[i] = alb
    c.rough[i] = np.clip(0.9 + 0.1 * (grain - 0.5) - 0.2 * scuff, 0.3, 1)
    c.metal[i] = 0.0
    c.height[i] = 0.0005 * (grain - 0.5)


def shade_glass(c, i):
    """Dark tinted glass / visors: glossy, with a thin film of dust and rain."""
    P, C = c.P[i], c.C[i]
    film = sm(0.45, 0.85, c.noise.fbm3(P, 9.0, 3, 0.5, 41))
    drops = sm(0.78, 0.9, c.noise.fbm3(P, 85.0, 2, 0.5, 42))
    streak = streaks(c, i, 55.0, 5.0, 43)
    c.alb[i] = C * (1.0 + 0.8 * film)[:, None]
    c.rough[i] = np.clip(0.05 + 0.20 * film + 0.12 * streak - 0.03 * drops, 0.02, 1)
    c.metal[i] = 0.1
    c.height[i] = 0.0003 * drops


def shade_carbon(c, i):
    """2x2 twill carbon fibre under clear coat."""
    P, C = c.P[i], c.C[i]
    u = c.uv[i, 0] / c.ppm * 220.0
    v = c.uv[i, 1] / c.ppm * 220.0
    a = np.floor(u + v) % 4 < 2
    b = np.floor(u - v) % 4 < 2
    tow = np.where(a ^ b, 1.0, 0.45)
    fine = c.noise.fbm3(P, 180.0, 2, 0.5, 51)
    c.alb[i] = (C * (0.65 + 0.7 * tow)[:, None] * (0.9 + 0.2 * fine)[:, None]) * (1.0 - 0.3 * grime_mask(c, i, 0.7, 0.3, 1.0, 0.3, 52))[:, None]
    c.rough[i] = np.clip(0.22 + 0.1 * (1 - tow), 0, 1)
    c.metal[i] = 0.05
    c.height[i] = 0.0003 * tow


def shade_paint(c, i):
    """Clear-coated car paint, neutral (the material's colour factor tints it): dust and road grime low on the body, faint
    orange peel, stone chips on the nose edge."""
    P = c.P[i]
    mott = c.noise.fbm3(P, 3.0, 3, 0.5, 61)
    peel = c.noise.fbm3(P, 90.0, 2, 0.5, 62)
    dirt = grime_mask(c, i, 0.55, 0.55, 0.6, 0.6, 63)
    st = streaks(c, i, 30.0, 4.0, 64)
    chip = sm(0.004, 0.0, c.cx[i]) * sm(0.55, 0.8, c.noise.fbm3(P, 70.0, 2, 0.5, 65))
    alb = (0.93 + 0.04 * (mott - 0.5) - 0.02 * peel)[:, None] * np.ones((1, 3))
    alb = alb * (1.0 - 0.5 * np.clip(dirt + 0.25 * st, 0, 1))[:, None] * np.array([1.0, 0.97, 0.93])
    alb = alb * (1.0 - chip[:, None]) + np.array([0.45, 0.45, 0.47]) * chip[:, None]
    c.alb[i] = alb
    c.rough[i] = np.clip(0.30 + 0.05 * (peel - 0.5) + 0.30 * dirt + 0.12 * st - 0.08 * chip, 0.06, 1)      # the game adds a wet clear coat on top
    c.metal[i] = np.clip(0.50 - 0.25 * dirt + 0.45 * chip, 0, 1)
    c.height[i] = 0.00012 * (peel - 0.5) - 0.0004 * chip


def shade_glow(c, i):
    """Emitting parts: the model script's colour is the emission colour, the surface itself is black."""
    c.alb[i] = 0.01
    c.rough[i] = 0.4
    c.metal[i] = 0.0
    c.emit[i] = c.C[i]
    c.height[i] = 0.0


def shade_solid(c, i):
    """Hidden or low-value surfaces (undersides, insides): a flat dark colour, no detail."""
    c.alb[i] = c.C[i]
    c.rough[i] = 0.8
    c.metal[i] = 0.0
    c.height[i] = 0.0


def shade_chitin(c, i):
    """Living shell (aliens): glossy mottled chitin, lighter along ridges, darker in the grooves between plates, no paint chips."""
    P, C = c.P[i], c.C[i]
    mott = c.noise.fbm3(P, 7.0, 3, 0.5, 51)
    fine = c.noise.fbm3(P, 95.0, 2, 0.5, 52)
    band = 0.5 + 0.5 * np.sin(P[:, 2] * 70.0 + 3.0 * mott)                      # faint growth rings along the height
    edge = sm(0.007, 0.0, c.cx[i])
    cav = grime_mask(c, i, 0.9, 0.5, 1.0, 0.5, 6)
    groove = sm(0.003, 0.0, c.cc[i])
    alb = C * (0.8 + 0.4 * mott)[:, None] * (0.94 + 0.1 * fine)[:, None] * (0.93 + 0.1 * band)[:, None]
    alb = alb * (1.0 - 0.3 * cav - 0.45 * groove)[:, None] + C * (edge * 0.4)[:, None]
    c.alb[i] = alb
    c.rough[i] = np.clip(0.52 + 0.16 * mott + 0.2 * cav - 0.15 * edge, 0.2, 1.0)
    c.metal[i] = 0.04 + 0.12 * edge
    c.height[i] = -0.0009 * groove + 0.00025 * (fine - 0.5) + 0.0002 * (band - 0.5)


def panel_seams(c, i, freq, width=0.0035, jitter=0.35, seed=61):
    """Armour plate / scute seams: a noise-warped 3D grid of thin grooves (planes cut the surface into irregular plates). Returns (groove 0..1,
    per-plate tone -1..1, plate id hash) so plates differ in value and each seam can be pressed into the normal map."""
    P = c.P[i]
    w = np.stack([c.noise.fbm3(P, 9.0, 2, 0.5, seed + k) for k in range(3)], axis=1) - 0.5
    Q = P * freq + w * (jitter * 2.0)
    F = Q - np.floor(Q)
    d = np.minimum(F, 1.0 - F)                                                   # distance to the nearest cell wall per axis (cell units)
    dmin = np.sort(d, axis=1)[:, :2]                                             # the two nearest walls: seams meet in corners
    gw = width * freq
    groove = sm(gw, gw * 0.25, dmin[:, 0])
    cell = np.floor(Q).astype(np.int64)
    h = (cell[:, 0] * 73856093) ^ (cell[:, 1] * 19349663) ^ (cell[:, 2] * 83492791)
    tone = ((h & 1023) / 1023.0) * 2.0 - 1.0
    return groove, tone, dmin[:, 0]


def shade_shell(c, i):
    """Lacquered chitin (the hero, the troopers): the chitin look with a wet clear coat (low roughness, a little metal on the ridges), a
    smoother low-frequency mottle so the shell reads as polished plates, and bright ridge lines."""
    P, C = c.P[i], c.C[i]
    mott = c.noise.fbm3(P, 5.0, 3, 0.5, 51)
    fine = c.noise.fbm3(P, 60.0, 2, 0.5, 52)
    edge = sm(0.008, 0.0, c.cx[i])
    cav = grime_mask(c, i, 0.8, 0.5, 1.0, 0.5, 6)
    groove = sm(0.003, 0.0, c.cc[i])
    seam, tone, wall = panel_seams(c, i, 11.0)                                  # plates about 9 cm across: seams, a per-plate value shift
    seam2, tone2, _ = panel_seams(c, i, 31.0, 0.0045, 0.5, 71)                  # finer scutes (about 3 cm): visible when close
    pit = c.noise.fbm3(P, 180.0, 1, 0.5, 53)                                    # chitin pores / cloth grain, mostly in the normal map
    alb = C * (0.78 + 0.34 * mott)[:, None] * (0.95 + 0.1 * fine)[:, None] * (1.0 + 0.16 * tone + 0.07 * tone2)[:, None]
    alb = alb * (1.0 - 0.22 * cav - 0.4 * groove - 0.55 * seam - 0.25 * seam2)[:, None] + C * (edge * 0.55 + 0.5 * sm(0.03, 0.012, wall) * (1.0 - seam))[:, None] * 0.6
    c.alb[i] = alb
    c.rough[i] = np.clip(0.38 + 0.14 * mott + 0.15 * cav + 0.12 * seam - 0.12 * edge + 0.05 * tone, 0.2, 1.0)
    c.metal[i] = 0.0 + 0.06 * edge                                          # no metal: there is no environment to reflect at night, metal turns black
    c.height[i] = -0.0007 * groove - 0.0011 * seam - 0.0005 * seam2 + 0.0003 * tone + 0.00012 * (fine - 0.5) + 0.0001 * (pit - 0.5)


def shade_silk(c, i):
    """Phase cloak: smooth satin ribbons, a very soft value gradient along the height, no grain (a grain on thin strands shimmers like dither)."""
    P, C = c.P[i], c.C[i]
    g = 0.5 + 0.5 * np.sin(P[:, 2] * 9.0)
    alb = C * (0.85 + 0.25 * g)[:, None]
    c.alb[i] = alb
    c.rough[i] = 0.42
    c.metal[i] = 0.2
    c.height[i] = 0.00012 * np.sin(P[:, 2] * 420.0)                          # long fine threads (along the drape): a normal-map weave that is smooth in the albedo


KINDS = {
    "shell": shade_shell, "silk": shade_silk,
    "fabric": shade_fabric, "plating": shade_plating, "steel": shade_steel, "rubber": shade_rubber, "glass": shade_glass,
    "carbon": shade_carbon, "paint": shade_paint, "glow": shade_glow, "solid": shade_solid, "chitin": shade_chitin,
}


# ------------------------------------------------------------------ decals (projected onto the finished surfaces)
class Decal:
    """A painted marking projected along -`facing` onto texels inside a box. `up` is the marking's vertical axis, `size` = (width,
    height) in metres, `depth` the box depth. `fn(u, v, aux)` gets decal coordinates 0..1 (u right, v up) and returns
    (alpha, colour_linear_rgb, emit_rgb_or_None). `kinds` limits it to some surface kinds."""

    def __init__(self, center, facing, up, size, fn, depth=0.04, kinds=("plating", "fabric", "steel", "paint"), min_dot=0.35,
                 rough=None):
        self.c = np.array(center, dtype=np.float64)
        f = np.array(facing, dtype=np.float64)
        self.f = f / np.linalg.norm(f)
        u = np.array(up, dtype=np.float64)
        u = u - self.f * np.dot(u, self.f)
        self.up = u / np.linalg.norm(u)
        self.right = np.cross(self.up, self.f)
        self.size, self.depth, self.fn, self.kinds, self.min_dot, self.rough = size, depth, fn, kinds, min_dot, rough


def apply_decals(c, decals, kind_of):
    for d in decals:
        rel = c.P - d.c
        lu = rel @ d.right
        lv = rel @ d.up
        ld = rel @ d.f
        m = (np.abs(lu) < d.size[0] * 0.5) & (np.abs(lv) < d.size[1] * 0.5) & (np.abs(ld) < d.depth) & ((c.N @ d.f) > d.min_dot)
        if d.kinds:
            m &= np.isin(kind_of, [KIND_IDS[k] for k in d.kinds if k in KIND_IDS])
        idx = np.nonzero(m)[0]
        if not len(idx):
            continue
        u = lu[idx] / d.size[0] + 0.5
        v = lv[idx] / d.size[1] + 0.5
        alpha, col, emit = d.fn(u, v, c, idx)
        alpha = np.clip(alpha, 0.0, 1.0)
        col = np.asarray(col, dtype=np.float64)
        if col.ndim == 1:
            col = np.broadcast_to(col, (len(idx), 3))
        c.alb[idx] = c.alb[idx] * (1 - alpha[:, None]) + col * alpha[:, None]
        c.rough[idx] = lerp(c.rough[idx], 0.55 if d.rough is None else d.rough, alpha)
        c.metal[idx] *= (1 - alpha)
        c.height[idx] -= 0.00025 * alpha
        if emit is not None:
            c.emit[idx] = np.maximum(c.emit[idx], np.asarray(emit) * alpha[:, None])


KIND_IDS = {k: n for n, k in enumerate(KINDS)}


# decal painters: fn(u, v, ctx, idx) -> (alpha, colour, emit)
def p_stripes(n=4, duty=0.5, angle=45.0, colour=(0.6, 0.45, 0.05), wear=0.35):
    a = math.radians(angle)

    def fn(u, v, c, idx):
        t = (u * math.cos(a) + v * math.sin(a)) * n
        al = (np.mod(t, 1.0) < duty).astype(np.float64)
        worn = c.noise.fbm3(c.P[idx], 90.0, 2, 0.5, 71)
        al = al * (0.85 - wear * sm(0.45, 0.75, worn))
        return al, colour, None
    return fn


def p_chevrons(n=3, colour=(0.55, 0.06, 0.05), wear=0.35, thick=0.22):
    def fn(u, v, c, idx):
        t = (np.abs(u - 0.5) * 1.6 + (1.0 - v)) * n
        al = (np.mod(t, 1.0) < thick * 1.6).astype(np.float64) * sm(0.0, 0.04, v) * sm(1.0, 0.96, v)
        worn = c.noise.fbm3(c.P[idx], 90.0, 2, 0.5, 72)
        return al * (0.9 - wear * sm(0.45, 0.75, worn)), colour, None
    return fn


def p_box(colour=(0.5, 0.5, 0.5), border=0.0, wear=0.3, emit=None):
    def fn(u, v, c, idx):
        al = np.ones_like(u)
        if border > 0:
            e = np.minimum(np.minimum(u, 1 - u), np.minimum(v, 1 - v))
            al = (e < border).astype(np.float64)
        worn = c.noise.fbm3(c.P[idx], 80.0, 2, 0.5, 73)
        al = al * (0.92 - wear * sm(0.5, 0.8, worn))
        return al, colour, (None if emit is None else np.asarray(emit))
    return fn


def p_ring(colour=(0.6, 0.6, 0.6), r0=0.28, r1=0.4, wear=0.3, cross=False):
    def fn(u, v, c, idx):
        r = np.hypot((u - 0.5) * 2, (v - 0.5) * 2)
        al = ((r > r0 * 2) & (r < r1 * 2)).astype(np.float64)
        if cross:
            al = np.maximum(al, ((np.abs(u - 0.5) < 0.045) | (np.abs(v - 0.5) < 0.045)).astype(np.float64) * (r < r1 * 2))
        worn = c.noise.fbm3(c.P[idx], 80.0, 2, 0.5, 74)
        return al * (0.9 - wear * sm(0.5, 0.8, worn)), colour, None
    return fn


def p_barcode(colour=(0.7, 0.7, 0.68), bars=14, wear=0.3, seed=3):
    r = np.random.default_rng(seed)
    pattern = r.random(bars) > 0.42
    wid = r.uniform(0.5, 1.0, bars)

    def fn(u, v, c, idx):
        k = np.clip((u * bars).astype(int), 0, bars - 1)
        fr = (u * bars) % 1.0
        al = (pattern[k] & (fr < wid[k])).astype(np.float64) * sm(0.0, 0.05, v) * sm(1.0, 0.95, v)
        worn = c.noise.fbm3(c.P[idx], 80.0, 2, 0.5, 75)
        return al * (0.9 - wear * sm(0.5, 0.8, worn)), colour, None
    return fn


def p_glyphs(colour=(0.75, 0.75, 0.72), cells=6, rows=1, seed=5, wear=0.35, stroke=0.12):
    """Pseudo-script stencil text (random strokes in a 3x5 grid per cell, no real lettering)."""
    r = np.random.default_rng(seed)
    pat = r.random((cells * rows, 5, 3)) > 0.5
    pat[:, :, 1] |= r.random((cells * rows, 5)) > 0.6

    def fn(u, v, c, idx):
        al = np.zeros_like(u)
        cu = u * cells
        cv = (1.0 - v) * rows
        ci = np.clip(cu.astype(int), 0, cells - 1)
        ri = np.clip(cv.astype(int), 0, rows - 1)
        fu = cu - np.floor(cu)
        fv = cv - np.floor(cv)
        gx = np.clip(((fu - 0.15) / 0.7 * 3).astype(int), 0, 2)
        gy = np.clip(((fv - 0.1) / 0.8 * 5).astype(int), 0, 4)
        inside = (fu > 0.15) & (fu < 0.85) & (fv > 0.1) & (fv < 0.9)
        cell = pat[ci + ri * cells, gy, gx]
        sub_u = ((fu - 0.15) / 0.7 * 3) % 1.0
        sub_v = ((fv - 0.1) / 0.8 * 5) % 1.0
        dot = (np.abs(sub_u - 0.5) < 0.5 - stroke) & (np.abs(sub_v - 0.5) < 0.5 - stroke * 0.6)
        al = (inside & cell & dot).astype(np.float64)
        worn = c.noise.fbm3(c.P[idx], 100.0, 2, 0.5, 76)
        return al * (0.9 - wear * sm(0.4, 0.8, worn)), colour, None
    return fn


def p_glow_bar(colour, power=1.0):
    def fn(u, v, c, idx):
        e = np.minimum(np.minimum(u, 1 - u), np.minimum(v, 1 - v))
        al = sm(0.0, 0.18, e)
        return al, np.array([0.01, 0.01, 0.01]), np.asarray(colour) * power
    return fn


def p_lines(positions, width=0.006, colour=(0.012, 0.012, 0.014), length=1.0, vertical=True, wear=0.0):
    """Thin dark lines (panel gaps, seams) at the given positions along the decal's u axis (metres from its centre)."""
    pos = np.asarray(positions, dtype=np.float64)

    def fn(u, v, c, idx):
        coord = (u - 0.5) * length if vertical else (v - 0.5) * length
        d = np.min(np.abs(coord[:, None] - pos[None, :]), axis=1)
        al = sm(width, width * 0.35, d)
        return al * (0.95 - wear), colour, None
    return fn
