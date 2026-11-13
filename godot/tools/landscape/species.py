"""Tree species generators for the landscape (wave 112): oak, birch, poplar, pine, fir, palm, acacia, dead tree and alien tree, each at three levels of detail.

A species function takes (rng, q) with q = a LOD config and returns a MeshBuilder: tubes for trunk and branches (bark texture in the shader), cards for the foliage
(atlas sprites from foliage.py, bent normals, ambient-occlusion tints). Everything is deterministic (the caller seeds `rng`).
"""
import math

import numpy as np

import foliage as fo
from mb import MeshBuilder, _norm, perp, rot_about

UP = np.array([0.0, 1.0, 0.0])
GOLD = 2.399963229728653


class LOD:
    def __init__(self, name, sides, steps, card_mul, size_mul, subs=True, leaves=True):
        self.name = name
        self.sides = sides            # radial segments of trunk and limbs
        self.steps = steps            # rings per tube
        self.card_mul = card_mul      # share of the foliage cards kept
        self.size_mul = size_mul      # the kept cards grow so the crown keeps its volume
        self.subs = subs
        self.leaves = leaves


FULL = LOD("full", 7, 6, 1.0, 1.0)
LITE = LOD("lite", 5, 4, 0.6, 1.2)
MID = LOD("mid", 4, 3, 0.17, 2.1, subs=False)
LODS = {"0": FULL, "0l": LITE, "1": MID}


def lerp(a, b, t):
    return a + (b - a) * t


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def path(rng, start, d0, length, steps, bend_to=None, bend=0.0, wobble=0.0):
    """Polyline from `start` along d0, drifting towards `bend_to` by `bend` (0..1 over the whole length) with random wobble."""
    p = np.asarray(start, dtype=np.float64).copy()
    d = _norm(d0)
    pts = [p.copy()]
    for _ in range(steps):
        if bend_to is not None and bend > 0:
            d = _norm(d + (_norm(bend_to) - d) * (bend / steps) * 1.6)
        if wobble > 0:
            d = _norm(d + rng.normal(0, wobble, 3))
        p = p + d * length / steps
        pts.append(p.copy())
    return np.array(pts)


def taper(r0, r1, k, power=1.0):
    return np.array([r1 + (r0 - r1) * (1.0 - i / (k - 1)) ** power for i in range(k)])


def flare(pts, radii, f=1.6, h=0.8):
    out = radii.copy()
    for i, p in enumerate(pts):
        if p[1] < h:
            out[i] *= 1.0 + (f - 1.0) * (1.0 - max(0.0, p[1]) / h) ** 2
    return out


def at(pts, t):
    """Point and direction on a polyline at fraction t."""
    k = len(pts) - 1
    x = clamp(t) * k
    i = min(int(x), k - 1)
    f = x - i
    return pts[i] * (1 - f) + pts[i + 1] * f, _norm(pts[i + 1] - pts[i])


def card_frame(d, roll=0.0):
    """Half-extent unit vectors (right, up) of a card whose plane normal is d."""
    d = _norm(d)
    r = np.cross(d, UP)
    if np.linalg.norm(r) < 0.15:
        r = np.array([1.0, 0.0, 0.0])
    r = _norm(r)
    u = _norm(np.cross(r, d))
    if roll:
        r, u = rot_about(r, d, roll), rot_about(u, d, roll)
    return r, u


def crown_tint(p, cc, R, floor=0.58):
    q = (np.asarray(p) - cc) / R
    d = clamp(np.linalg.norm(q))
    t = lerp(floor, 1.0, d ** 0.85) * (0.80 + 0.20 * clamp(q[1] * 0.5 + 0.5))
    return (t, t, t)


def bent(p, cc, R, up_bias=0.35):
    q = (np.asarray(p) - cc) / R
    n = _norm(q if np.linalg.norm(q) > 1e-6 else UP)
    return _norm(n + UP * up_bias)


def mass_cards(mb, rng, tips, count, cc, R, names, size, size_jit=0.18, spread=1.0, outward=0.6, flutter=0.8):
    """Leaf-mass cards (pivot = the card centre) scattered round the branch tips, facing mostly outwards and upwards."""
    if not tips:
        return
    n = max(1, count)
    for i in range(n):
        tip = tips[i % len(tips)]
        off = rng.normal(0, 1, 3) * spread
        off[1] *= 0.7
        p = tip + off
        out = _norm(p - cc) if np.linalg.norm(p - cc) > 1e-6 else UP
        d = _norm(rng.normal(0, 1, 3) * (1.0 - outward) + out * outward * 2.0 + UP * 0.25)
        r, u = card_frame(d, rng.uniform(0, math.tau))
        s = size * rng.uniform(1.0 - size_jit, 1.0 + size_jit) * 0.5
        name = names[int(rng.randint(0, len(names)))]
        mb.card(p, r * s, u * s, fo.cell_rect(name), bent(p, cc, R), crown_tint(p, cc, R), flutter, 0.0, name, flip_u=bool(rng.randint(0, 2)))


def limb(mb, rng, start, d0, length, r0, r1, q, bend_to=UP, bend=0.5, wobble=0.1, steps=None, uv_len=1.6):
    steps = 1 if q is MID else (steps or q.steps)
    pts = path(rng, start, d0, length, steps, bend_to, bend, wobble)
    sides = q.sides if r0 >= (0.16 if q is not LITE else 0.12) else 3          # thin branches are three-sided prisms: they read as lines, a round tube costs 3x the triangles
    mb.tube(pts, taper(r0, r1, len(pts), 1.15), sides, uv_len=uv_len, rng=rng, noise=0.05 if sides > 3 else 0.0)
    return pts


# --- the species -----------------------------------------------------------------------------------------------------------------------------------

def oak(rng, q):
    mb = MeshBuilder()
    ht = rng.uniform(3.6, 4.4)
    lean = _norm(np.array([rng.normal(), 0.0, rng.normal()])) * rng.uniform(0.05, 0.22)
    trunk = path(rng, (0, 0, 0), UP + lean, ht, q.steps + 2, wobble=0.045)
    rad = flare(trunk, taper(0.40, 0.22, len(trunk), 0.9), 1.55, 0.8)
    mb.tube(trunk, rad, q.sides + 1, uv_len=2.4, u_rep=1.0, rng=rng, noise=0.05)
    top = trunk[-1]
    tips = []
    n_limb = 5 if q.subs else 3
    az0 = rng.uniform(0, math.tau)
    for i in range(n_limb):
        az = az0 + i * GOLD * 1.2 + rng.normal(0, 0.18)
        el = math.radians(rng.uniform(30, 58))
        d = np.array([math.sin(el) * math.cos(az), math.cos(el), math.sin(el) * math.sin(az)])
        st, _ = at(trunk, rng.uniform(0.80, 1.0))
        L = rng.uniform(3.4, 4.8)
        pts = limb(mb, rng, st, d, L, 0.20, 0.05, q, bend=0.55, wobble=0.10)
        tips.append(pts[-1])
        tips.append(at(pts, 0.7)[0])
        if q is FULL:
            for s in range(3):
                o, dd = at(pts, rng.uniform(0.35, 0.92))
                d2 = _norm(dd + rng.normal(0, 0.8, 3) + UP * 0.35)
                p2 = limb(mb, rng, o, d2, rng.uniform(1.4, 2.4), 0.07, 0.02, q, bend=0.4, wobble=0.12, steps=3)
                tips.append(p2[-1])
    cc = top + np.array([0.0, 3.3, 0.0])
    R = np.array([5.3, 3.9, 5.3])
    mass_cards(mb, rng, tips, int(120 * q.card_mul), cc, R, ["oak_a", "oak_b"], 2.4 * q.size_mul, spread=1.15)
    return mb


def birch(rng, q):
    mb = MeshBuilder()
    H0 = rng.uniform(7.4, 9.0)
    trunk = path(rng, (0, 0, 0), UP + np.array([rng.normal(0, 0.06), 0, rng.normal(0, 0.06)]), H0, q.steps + 3, wobble=0.07)
    rad = flare(trunk, taper(0.15, 0.035, len(trunk), 0.8), 1.35, 0.5)
    mb.tube(trunk, rad, max(5, q.sides - 1), uv_len=1.2, rng=rng, noise=0.03)
    tips = [trunk[-1]]
    az0 = rng.uniform(0, math.tau)
    n_br = 9 if q.subs else 4
    for i in range(n_br):
        h = lerp(3.0, H0 * 0.94, (i + rng.uniform(0, 0.6)) / n_br)
        st, _ = at(trunk, h / H0)
        az = az0 + i * GOLD * 1.3
        el = math.radians(lerp(62, 28, h / H0) + rng.normal(0, 6))
        d = np.array([math.sin(el) * math.cos(az), math.cos(el), math.sin(el) * math.sin(az)])
        L = lerp(2.4, 1.3, h / H0) * rng.uniform(0.85, 1.15)
        pts = limb(mb, rng, st, d, L, 0.045, 0.008, q, bend_to=UP * 0.2, bend=0.2, wobble=0.12, steps=3)
        tips.append(pts[-1])
        tips.append(at(pts, 0.55)[0])
    cc = np.array([0.0, H0 * 0.70, 0.0])
    R = np.array([2.5, 3.7, 2.5])
    mass_cards(mb, rng, tips, int(104 * q.card_mul), cc, R, ["birch_a", "birch_b"], 1.75 * q.size_mul, spread=0.9, outward=0.5)
    return mb


def poplar(rng, q):
    mb = MeshBuilder()
    H = rng.uniform(15.0, 17.5)
    trunk = path(rng, (0, 0, 0), UP, H, q.steps + 4, wobble=0.02)
    rad = flare(trunk, taper(0.26, 0.035, len(trunk), 0.9), 1.4, 0.6)
    mb.tube(trunk, rad, q.sides, uv_len=1.8, rng=rng, noise=0.03)
    n = 20 if q.subs else 7
    az0 = rng.uniform(0, math.tau)
    for i in range(n):
        f = lerp(0.17, 0.97, (i + 0.4) / n)
        st, _ = at(trunk, f)
        az = az0 + i * GOLD * 1.1
        el = math.radians(rng.uniform(16, 32))
        d = np.array([math.sin(el) * math.cos(az), math.cos(el), math.sin(el) * math.sin(az)])
        L = (0.7 + 1.1 * math.sin(math.pi * (0.1 + 0.9 * f)) ** 0.7) * rng.uniform(0.9, 1.1)
        limb(mb, rng, st, d, L, 0.04, 0.01, q, bend=0.5, wobble=0.05, steps=2)
    cc = np.array([0.0, H * 0.58, 0.0])
    R = np.array([2.0, H * 0.45, 2.0])
    # a flame-shaped column of overlapping leaf-mass cards: the width follows sin(), the cards sit on a spiral round the axis so every height has leaves on all sides
    n_c = max(8, int(46 * q.card_mul)) if q is not MID else 9
    for i in range(n_c):
        f = lerp(0.2, 1.0, (i + 0.5) / n_c)
        wdt = 0.55 + 1.35 * math.sin(math.pi * (0.06 + 0.94 * f)) ** 0.6 if f < 0.97 else 0.2
        ang = az0 + i * GOLD * 1.7
        p = np.array([math.cos(ang) * wdt * 0.55, H * f, math.sin(ang) * wdt * 0.55])
        out = _norm(np.array([p[0], 0.15, p[2]]))
        d = _norm(out + rng.normal(0, 0.35, 3))
        r, u = card_frame(d, rng.uniform(0, math.tau))
        sz = (1.2 + 1.0 * wdt) * 1.05 * q.size_mul ** 0.8 * rng.uniform(0.9, 1.1)
        name = ["poplar_a", "birch_a"][int(rng.randint(0, 2))]
        mb.card(p, r * sz * 0.5, u * sz * 0.5, fo.cell_rect(name), bent(p, cc, R, 0.3), crown_tint(p, cc, R, 0.6), 0.8, 0.0, name, flip_u=bool(rng.randint(0, 2)))
    return mb


def pine(rng, q):
    mb = MeshBuilder()
    H = rng.uniform(12.0, 14.5)
    lean = np.array([rng.normal(0, 0.07), 0.0, rng.normal(0, 0.07)])
    trunk = path(rng, (0, 0, 0), UP + lean, H, q.steps + 4, wobble=0.025)
    rad = flare(trunk, taper(0.30, 0.05, len(trunk), 0.85), 1.45, 0.9)
    mb.tube(trunk, rad, q.sides + 1, uv_len=2.0, rng=rng, noise=0.04)
    top = trunk[-1]
    h0 = H * 0.5
    cc = np.array([0.0, (h0 + H) * 0.5, 0.0])
    R = np.array([3.4, (H - h0) * 0.55, 3.4])
    h = h0
    wh = 0
    names = ["pine_a", "pine_b"]
    tuft = 2.5 * q.size_mul
    step = 0.95 if q is FULL else (1.4 if q is LITE else 1.9)
    while h < H - 0.4:
        frac = (h - h0) / (H - h0)
        n_in = 4 if frac < 0.45 else 3
        if q is MID:
            n_in = 3
        az0 = rng.uniform(0, math.tau)
        for k in range(n_in):
            az = az0 + math.tau * k / n_in + rng.normal(0, 0.25)
            el = math.radians(rng.uniform(70, 82))
            d = np.array([math.sin(el) * math.cos(az), math.cos(el), math.sin(el) * math.sin(az)])
            L = (3.4 * (1.0 - frac) ** 0.7 + 1.0) * rng.uniform(0.85, 1.12)
            st, _ = at(trunk, h / H)
            pts = limb(mb, rng, st, d, L, 0.065, 0.016, q, bend=0.5, wobble=0.07, steps=3)
            tip = pts[-1]
            dd = _norm(pts[-1] - pts[-2])
            out = _norm(tip - np.array([0, tip[1], 0]))
            for ci in range(3 if q is FULL else (2 if q is LITE else 1)):
                # a tuft of three needle fans on a branch tip: one pointing up, two spread to the sides and a little down, so the tuft has volume from every side
                if ci == 0:
                    dirc = _norm(dd + UP * 0.9)
                    right = _norm(np.cross(dirc, out))
                else:
                    sgn = 1.0 if ci == 1 else -1.0
                    side = _norm(np.cross(UP, out))
                    dirc = _norm(dd * 0.8 + side * sgn * 0.6 + UP * 0.25)
                    right = _norm(np.cross(dirc, UP))
                if np.linalg.norm(right) < 0.1:
                    right = perp(dirc)
                s = tuft * rng.uniform(0.9, 1.15) * (1.0 - 0.18 * frac) * (1.0 if ci == 0 else 0.82)
                base = tip - dirc * 0.12
                name = names[int(rng.randint(0, 2))]
                tintv = crown_tint(base + dirc * s * 0.4, cc, R, 0.62)
                mb.card(base + dirc * s * 0.5, right * s * 0.5, dirc * s * 0.5, fo.cell_rect(name), bent(base + dirc * s * 0.4, cc, R, 0.5), tintv, 0.9, 0.0, name)
            if q is FULL and rng.rand() < 0.7:
                o, dd2 = at(pts, 0.5)
                p2 = limb(mb, rng, o, _norm(dd2 + rng.normal(0, 0.5, 3) + UP * 0.3), L * 0.45, 0.03, 0.01, q, steps=2)
                dirc = _norm(p2[-1] - p2[-2] + UP * 0.8)
                right = _norm(np.cross(dirc, out))
                s = tuft * 0.7
                name = names[int(rng.randint(0, 2))]
                mb.card(p2[-1] + dirc * s * 0.5, right * s * 0.5, dirc * s * 0.5, fo.cell_rect(name), bent(p2[-1], cc, R, 0.5), crown_tint(p2[-1], cc, R, 0.62), 0.9, 0.0, name)
        h += step * rng.uniform(0.85, 1.15)
        wh += 1
    # leader tuft
    for rot in (0.0, math.pi / 2):
        right = np.array([math.cos(rot), 0.0, math.sin(rot)])
        s = tuft * 0.9
        mb.card(top + UP * s * 0.45, right * s * 0.5, UP * s * 0.5, fo.cell_rect("pine_a"), bent(top, cc, R, 0.6), (1, 1, 1), 0.9, 0.0, "pine_a")
        if q is not FULL:
            break
    return mb


def fir(rng, q):
    mb = MeshBuilder()
    H = rng.uniform(12.5, 15.0)
    trunk = path(rng, (0, 0, 0), UP + np.array([rng.normal(0, 0.03), 0, rng.normal(0, 0.03)]), H, q.steps + 3, wobble=0.012)
    rad = flare(trunk, taper(0.28, 0.025, len(trunk), 0.95), 1.35, 0.8)
    mb.tube(trunk, rad, q.sides, uv_len=2.2, rng=rng, noise=0.03)
    h_lo = 1.5
    cc = np.array([0.0, (h_lo + H) * 0.5, 0.0])
    R = np.array([2.8, (H - h_lo) * 0.55, 2.8])
    step = 0.82 if q is FULL else (1.05 if q is LITE else 1.6)
    h = h_lo
    names = ["fir_a", "fir_b"]
    while h < H - 0.5:
        frac = (h - h_lo) / (H - h_lo)
        L = 3.2 * (1.0 - frac) ** 0.88 + 0.35
        n_in = 6 if frac < 0.35 else (5 if frac < 0.65 else 4)
        if q is LITE:
            n_in = max(4, n_in - 1)
        if q is MID:
            n_in = 5 if frac < 0.6 else 4
        az0 = rng.uniform(0, math.tau)
        for k in range(n_in):
            az = az0 + math.tau * k / n_in + rng.normal(0, 0.12)
            el = math.radians(lerp(-18, 12, frac) + rng.normal(0, 4))
            horiz = np.array([math.cos(az), 0.0, math.sin(az)])
            d = _norm(horiz * math.cos(el) + UP * math.sin(el))
            st, _ = at(trunk, h / H)
            tip = st + d * L
            side = _norm(np.cross(d, UP))
            n_cards = 2 if q is FULL else 1
            for ci in range(n_cards):
                roll = (ci * 2 - 1) * math.radians(34) if n_cards == 2 else math.radians(38 if (k % 2) else -38)
                sd = rot_about(side, d, roll)
                length = L * 1.12 * (q.size_mul ** 0.5 if q is not MID else 1.45)
                half_w = length * 0.5
                half_h = half_w * 0.5
                center = st + d * (length * 0.5 - 0.1) - UP * (0.12 + 0.18 * (1 - frac))
                p_mid = center
                name = names[int(rng.randint(0, 2))]
                mb.card(center, d * half_w, sd * half_h * 1.05, fo.cell_rect(name), bent(p_mid, cc, R, 0.55), crown_tint(p_mid, cc, R, 0.7), 0.7, 0.0, name)
        h += step * rng.uniform(0.9, 1.1)
    # leader
    for rot in (0.0, math.pi / 2):
        dr = np.array([math.cos(rot), 0.0, math.sin(rot)])
        sd = UP
        mb.card(np.array([0, H - 0.5, 0]) + dr * 0.0, UP * 0.9, dr * 0.5, fo.cell_rect("fir_a"), UP, (1, 1, 1), 0.5, 0.0, "fir_a")
        if q is not FULL:
            break
    return mb


def palm(rng, q):
    mb = MeshBuilder()
    H = rng.uniform(7.5, 9.5)
    az = rng.uniform(0, math.tau)
    lean_dir = np.array([math.cos(az), 0.0, math.sin(az)])
    lean = rng.uniform(0.9, 1.9)
    k = q.steps + 4
    pts = []
    for i in range(k):
        t = i / (k - 1)
        pts.append(np.array([0, H * t, 0]) + lean_dir * lean * t * t)
    pts = np.array(pts)
    rad = flare(pts, taper(0.25, 0.15, len(pts), 0.6), 1.45, 0.7)
    mb.tube(pts, rad, q.sides + 1, uv_len=1.3, u_rep=1.0, rng=rng, noise=0.02)
    top = pts[-1]
    n = 16 if q is FULL else (11 if q is LITE else 7)
    cc = top + np.array([0.0, 0.6, 0.0])
    R = np.array([3.4, 2.8, 3.4])
    az0 = rng.uniform(0, math.tau)
    for i in range(n):
        a = az0 + math.tau * i / n + rng.normal(0, 0.12)
        e0 = math.radians([62, 40, 18, -2, -22][i % 5] + rng.normal(0, 5))
        Lf = rng.uniform(4.3, 5.2)
        steps = 7 if q is FULL else (5 if q is LITE else 3)
        horiz = np.array([math.cos(a), 0.0, math.sin(a)])
        p = top.copy()
        e = e0
        fpts = [p.copy()]
        for s in range(steps):
            e -= math.radians(88.0 / steps) * (0.55 + 0.9 * s / steps)
            p = p + (horiz * math.cos(e) + UP * math.sin(e)) * Lf / steps
            fpts.append(p.copy())
        widths = [0.14 + 1.25 * math.sin(math.pi * (0.10 + 0.90 * j / steps)) ** 0.75 for j in range(steps + 1)]
        widths = [w * q.size_mul ** 0.35 for w in widths]
        side = _norm(np.cross(horiz, UP))
        name = "palm_a" if i % 2 == 0 else "palm_b"
        mb.strip(fpts, widths, fo.cell_rect(name), bent(fpts[len(fpts) // 2], cc, R, 0.5), crown_tint(fpts[len(fpts) // 2], cc, R, 0.7), 0.8, 0.0, side, name)
    if q is FULL:
        for i in range(3):
            a = rng.uniform(0, math.tau)
            mb.blob(top + np.array([math.cos(a) * 0.22, -0.18 - 0.05 * i, math.sin(a) * 0.22]), 0.11, (0.5, 0.5), 6, 2, (0.55, 0.42, 0.22))
    return mb


def acacia(rng, q):
    mb = MeshBuilder()
    ht = rng.uniform(3.4, 4.4)
    lean = np.array([rng.normal(0, 0.12), 0.0, rng.normal(0, 0.12)])
    trunk = path(rng, (0, 0, 0), UP + lean, ht, q.steps, wobble=0.06)
    rad = flare(trunk, taper(0.28, 0.2, len(trunk), 0.8), 1.5, 0.8)
    mb.tube(trunk, rad, q.sides + 1, uv_len=2.0, rng=rng, noise=0.06)
    top = trunk[-1]
    tips = []
    n_l = 3 if q.subs else 3
    az0 = rng.uniform(0, math.tau)
    for i in range(n_l):
        az = az0 + math.tau * i / n_l + rng.normal(0, 0.2)
        el = math.radians(rng.uniform(40, 58))
        d = np.array([math.sin(el) * math.cos(az), math.cos(el), math.sin(el) * math.sin(az)])
        pts = limb(mb, rng, top - UP * 0.2, d, rng.uniform(3.0, 3.8), 0.17, 0.05, q, bend_to=np.array([math.cos(az), 0.45, math.sin(az)]), bend=0.7, wobble=0.1)
        tips.append(pts[-1])
        if q is FULL:
            for s in range(2):
                o, dd = at(pts, rng.uniform(0.5, 0.9))
                p2 = limb(mb, rng, o, _norm(dd + rng.normal(0, 0.5, 3)), rng.uniform(1.5, 2.2), 0.06, 0.02, q, bend_to=UP, bend=0.35, steps=3)
                tips.append(p2[-1])
    cc = np.array([0.0, tips[0][1] + 0.3, 0.0])
    R = np.array([5.0, 1.6, 5.0])
    n_c = 12 if q is FULL else (8 if q is LITE else 5)
    base_y = max(t[1] for t in tips) - 0.2
    for i in range(n_c):
        if i == 0:
            p = np.array([0.0, base_y + 0.7, 0.0])
        else:
            ang = i * GOLD * 1.3 + rng.normal(0, 0.2)
            rr = (1.7 + 1.5 * ((i - 1) % 3) / 2.0) * rng.uniform(0.85, 1.1)
            p = np.array([math.cos(ang) * rr, base_y + 0.15 + 0.5 * ((i - 1) % 2) + rng.normal(0, 0.15), math.sin(ang) * rr])
        rim = _norm(np.array([p[0], 0.0, p[2]])) if (p[0] * p[0] + p[2] * p[2]) > 1e-4 else np.array([1.0, 0.0, 0.0])
        rr_ = math.hypot(p[0], p[2])
        tilt = _norm(UP + rng.normal(0, 0.30, 3) - rim * 0.10 * rr_ + rim * 0.0)
        r, u = card_frame(tilt, rng.uniform(0, math.tau))
        s_ = 5.2 * q.size_mul ** 0.8 * rng.uniform(0.9, 1.1) * 0.5
        name = "acacia_a" if i % 2 == 0 else "acacia_b"
        mb.card(p, r * s_, u * s_, fo.cell_rect(name), _norm(UP + (p - cc) * 0.08), crown_tint(p, cc, R, 0.72), 0.5, 0.0, name)
    return mb


def dead(rng, q):
    mb = MeshBuilder()
    H = rng.uniform(4.6, 7.0)
    lean = np.array([rng.normal(0, 0.18), 0.0, rng.normal(0, 0.18)])
    trunk = path(rng, (0, 0, 0), UP + lean, H, q.steps + 2, wobble=0.12)
    rad = flare(trunk, taper(0.26, 0.05, len(trunk), 0.9), 1.5, 0.8)
    mb.tube(trunk, rad, q.sides, uv_len=1.8, rng=rng, noise=0.08)
    tips = []
    n = 11 if q.subs else 5
    az0 = rng.uniform(0, math.tau)
    for i in range(n):
        f = lerp(0.35, 0.97, (i + rng.uniform(0, 0.6)) / n)
        st, _ = at(trunk, f)
        az = az0 + i * GOLD * 1.4
        el = math.radians(rng.uniform(30, 78))
        d = np.array([math.sin(el) * math.cos(az), math.cos(el), math.sin(el) * math.sin(az)])
        L = lerp(2.8, 0.9, f) * rng.uniform(0.8, 1.2)
        pts = limb(mb, rng, st, d, L, 0.075 * (1 - 0.4 * f), 0.012, q, bend=0.25, wobble=0.18, steps=3)
        tips.append(pts[-1])
        if q is FULL and rng.rand() < 0.6:
            o, dd = at(pts, 0.6)
            p2 = limb(mb, rng, o, _norm(dd + rng.normal(0, 0.8, 3)), L * 0.5, 0.03, 0.006, q, wobble=0.2, steps=2)
            tips.append(p2[-1])
    if q is FULL:
        cc = np.array([0.0, H * 0.7, 0.0])
        R = np.array([2.0, 2.5, 2.0])
        mass_cards(mb, rng, tips[:6], 6, cc, R, ["dead_a"], 1.5, spread=0.3, flutter=0.5)
    return mb


def alien(rng, q):
    mb = MeshBuilder()
    H = rng.uniform(6.8, 9.2)
    k = q.steps + 4
    pts = []
    for i in range(k):
        t = i / (k - 1)
        a = t * math.tau * 1.4
        pts.append(np.array([0.45 * math.sin(a) * t, H * t, 0.45 * math.cos(a) * t]))
    pts = np.array(pts)
    rad = flare(pts, taper(0.30, 0.09, len(pts), 0.7), 1.9, 1.1)
    mb.tube(pts, rad, q.sides + 1, uv_len=1.5, rng=rng, noise=0.07, tint=(0.8, 0.7, 1.0))
    top = pts[-1]
    n = 6 if q.subs else 4
    tips = []
    az0 = rng.uniform(0, math.tau)
    for i in range(n):
        f = lerp(0.5, 1.0, i / max(1, n - 1))
        st, _ = at(pts, f)
        az = az0 + i * GOLD
        el = math.radians(rng.uniform(40, 80))
        d = np.array([math.sin(el) * math.cos(az), math.cos(el), math.sin(el) * math.sin(az)])
        ap = path(rng, st, d, rng.uniform(2.4, 3.6), q.steps, bend_to=UP, bend=0.9, wobble=0.12)
        mb.tube(ap, taper(0.10, 0.02, len(ap)), max(4, q.sides - 1), uv_len=1.2, rng=rng, noise=0.05, tint=(0.8, 0.7, 1.0))
        tips.append((ap[-1], _norm(ap[-1] - ap[-2])))
    cc = top + np.array([0.0, 0.8, 0.0])
    R = np.array([3.2, 3.0, 3.2])
    for i, (tip, dirc) in enumerate(tips):
        for ci in range(3 if q is FULL else (2 if q is LITE else 1)):
            rollv = ci * math.tau / 3.0 + i
            right = rot_about(_norm(np.cross(dirc, np.array([0.0, 0.0, 1.0])) if abs(dirc[2]) < 0.9 else np.array([1.0, 0, 0])), dirc, rollv)
            s = 2.6 * q.size_mul * rng.uniform(0.9, 1.15)
            name = "alien_a" if (i + ci) % 2 == 0 else "alien_b"
            mb.card(tip + dirc * s * 0.45, right * s * 0.5, dirc * s * 0.5, fo.cell_rect(name), bent(tip, cc, R, 0.6), (1, 1, 1), 0.9, 0.95, name)
    return mb


def drift(rng, q):
    """A bleached log washed up on a beach (wave 112): lying along +x half sunk in the sand, a root ball with a few stubs at the thick end, a branch stub or two. No foliage."""
    mb = MeshBuilder()
    L = rng.uniform(3.4, 5.2)
    r0 = rng.uniform(0.2, 0.3)
    n = q.steps + 2
    pts = []
    for i in range(n + 1):
        t = i / n
        pts.append(np.array([lerp(-L * 0.5, L * 0.5, t), r0 * 0.62 + 0.05 * math.sin(t * 4.0 + 1.0), 0.16 * math.sin(t * 3.1 + 0.6)]))
    rad = np.array([r0 * (1.0 - 0.5 * (i / n)) * (1.45 if i == 0 else (1.15 if i == 1 else 1.0)) for i in range(n + 1)])
    mb.tube(pts, rad, q.sides, uv_len=1.4, rng=rng, noise=0.07, tint=(1.12, 1.10, 1.04))
    stubs = 5 if q.subs else 2
    for k in range(stubs):
        az = (k + rng.uniform(0, 0.8)) * math.tau / stubs
        d = np.array([-0.45, 0.55 * math.sin(az) + 0.35, 0.8 * math.cos(az)])
        limb(mb, rng, pts[0] + np.array([0.0, 0.05, 0.0]), d, rng.uniform(0.7, 1.5), 0.07, 0.02, q, bend_to=np.array([0.0, -0.4, 0.0]), bend=0.25, wobble=0.12, steps=2)
    for k in range(2 if q.subs else 1):
        f = rng.uniform(0.35, 0.85)
        st, _ = at(np.array(pts), f)
        az = rng.uniform(0.3, math.pi - 0.3) * (1.0 if rng.rand() < 0.5 else -1.0)
        d = np.array([0.35, 0.7, math.sin(az)])
        limb(mb, rng, st, d, rng.uniform(0.5, 1.1), 0.05, 0.015, q, bend=0.2, wobble=0.1, steps=2)
    return mb


SPECIES = {"oak": oak, "birch": birch, "poplar": poplar, "pine": pine, "fir": fir, "palm": palm, "acacia": acacia, "dead": dead, "alien": alien, "drift": drift}
SEEDS = {"oak": 101, "birch": 202, "poplar": 303, "pine": 404, "fir": 505, "palm": 606, "acacia": 707, "dead": 808, "alien": 909, "drift": 1010}


def build(species, lod_key, variant=0):
    rng = np.random.RandomState(SEEDS[species] + variant * 97)
    return SPECIES[species](rng, LODS[lod_key])
