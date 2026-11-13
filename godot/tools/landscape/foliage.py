"""Procedural foliage sprites for the landscape trees and plants (wave 112, landscape): leaf clusters, needle sprays, palm fronds, feathery acacia, alien glow-leaves,
grass blades, ferns and flowers, drawn with PIL at 3x supersampling and packed into ONE atlas (assets/textures/land_foliage.webp, 2048 x 1024 = 8 x 4 cells of 256 px).

Every sprite is an RGBA cell: colour already shaded (dark inside, light on top, a lighter vein, a darker contact shadow under each leaf), alpha = coverage (alpha-tested in the
shader). Cells that stand for long things (fir sprays 2:1, palm fronds 4:1, grass 1:2) are drawn at their real aspect and squashed into the square cell; the card that carries the
cell has the real aspect, so the squash cancels.  No external art: everything here is drawn from code with fixed seeds, so the atlas is reproducible.
"""
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SS = 3                                   # supersampling
CELL = 256

# --- helpers -------------------------------------------------------------------------------------------------------------------------------------


def _lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(len(a)))


def _col(c, mul=1.0, add=0.0):
    return tuple(int(max(0, min(255, c[i] * mul + add))) for i in range(3))


def _canvas(w, h):
    return Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))


def _finish(im, w, h, out_w=None, out_h=None, blur=0.0):
    """Downsample a supersampled RGBA canvas in premultiplied space (no dark fringe), optionally squashing to out_w x out_h."""
    out_w = out_w or w
    out_h = out_h or h
    a = np.asarray(im, dtype=np.float32) / 255.0
    pre = a[..., :3] * a[..., 3:4]
    pm = np.concatenate([pre, a[..., 3:4]], axis=2)
    img = Image.fromarray((pm * 255.0 + 0.5).astype(np.uint8), "RGBA")
    if blur > 0:
        img = img.filter(ImageFilter.GaussianBlur(blur * SS))
    img = img.resize((out_w, out_h), Image.LANCZOS)
    b = np.asarray(img, dtype=np.float32) / 255.0
    al = b[..., 3:4]
    rgb = np.where(al > 1e-3, b[..., :3] / np.maximum(al, 1e-3), 0.0)
    out = np.concatenate([np.clip(rgb, 0, 1), al], axis=2)
    return Image.fromarray((out * 255.0 + 0.5).astype(np.uint8), "RGBA")


def texturize(img, seed, amount=0.10, scale=14.0):
    """Multiply the colour by two octaves of smooth noise (breaks the vector look); alpha untouched."""
    rng = np.random.RandomState(seed)
    w, h = img.size
    a = np.asarray(img, dtype=np.float32) / 255.0
    n = np.zeros((h, w), dtype=np.float32)
    for oct_, wgt in ((scale, 0.65), (scale * 2.7, 0.35)):
        gw, gh = max(2, int(w / oct_) + 2), max(2, int(h / oct_) + 2)
        g = rng.rand(gh, gw).astype(np.float32)
        im = Image.fromarray((g * 255).astype(np.uint8), "L").resize((w, h), Image.BICUBIC)
        n += wgt * (np.asarray(im, dtype=np.float32) / 255.0 - 0.5)
    m = 1.0 + n * amount * 2.0
    a[..., :3] = np.clip(a[..., :3] * m[..., None], 0, 1)
    return Image.fromarray((a * 255.0 + 0.5).astype(np.uint8), "RGBA")


def _poly_leaf(kind, length, width, rng):
    """Outline of a leaf in local space: x along the axis 0..length, y across. Returns a list of (x, y)."""
    n = 28
    pts_top = []
    pts_bot = []
    for i in range(n + 1):
        t = i / n
        if kind == "oak":
            base = math.sin(math.pi * (t ** 0.85)) ** 0.9
            lobes = 1.0 + 0.30 * math.sin(t * math.pi * 7.0 + 0.6) * (1.0 - 0.4 * t)
            w = 0.5 * width * base * lobes
        elif kind == "birch":
            base = math.sin(math.pi * (t ** 0.78)) ** 0.85
            saw = 1.0 + 0.09 * (((t * 13.0) % 1.0) - 0.5) * 2.0
            w = 0.5 * width * base * saw * (1.0 - 0.25 * (1 - t) ** 3)
        elif kind == "round":
            w = 0.5 * width * math.sin(math.pi * (t ** 0.7)) ** 0.7
        elif kind == "lance":
            w = 0.5 * width * math.sin(math.pi * (t ** 0.9)) ** 1.2
        elif kind == "needle":
            w = 0.5 * width * (1.0 - t) ** 0.5
        elif kind == "diamond":
            w = 0.5 * width * (1.0 - abs(2.0 * t - 0.8) / 1.2 if t < 0.8 else (1.0 - t) / 0.2) if t > 0.05 else 0.0
            w = max(w, 0.0)
        else:
            w = 0.5 * width * math.sin(math.pi * t)
        pts_top.append((t * length, w))
        pts_bot.append((t * length, -w))
    return pts_top + pts_bot[::-1]


def _xf(pts, x, y, ang, sx=1.0, sy=1.0):
    ca, sa = math.cos(ang), math.sin(ang)
    return [(x + (px * sx) * ca - (py * sy) * sa, y + (px * sx) * sa + (py * sy) * ca) for px, py in pts]


def draw_leaf(dr, x, y, ang, length, width, kind, cols, rng, vein=True, bend=0.0):
    """One shaded leaf at (x, y) (base), pointing along `ang` (radians, image space). cols = (dark, mid, light) RGB."""
    dark, mid, light = cols
    outline = _poly_leaf(kind, length, width, rng)
    if bend != 0.0:                                          # curve the leaf sideways along its length
        outline = [(px, py + bend * (px / max(length, 1e-3)) ** 2 * width) for px, py in outline]
    # contact shadow (slightly offset, darker) so overlapping leaves read as layers
    sh = _xf(outline, x + 0.07 * width, y + 0.10 * width, ang)
    dr.polygon(sh, fill=_col(dark, 0.55) + (150,))
    dr.polygon(_xf(outline, x, y, ang), fill=_col(dark) + (255,))
    mid_o = [(px * 0.90 + length * 0.07, py * 0.80) for px, py in outline]
    dr.polygon(_xf(mid_o, x, y, ang), fill=_col(_lerp(dark, mid, 0.8)) + (255,))
    hi_o = [(px * 0.66 + length * 0.30, py * 0.52) for px, py in outline]
    dr.polygon(_xf(hi_o, x, y, ang), fill=_col(_lerp(mid, light, 0.55)) + (255,))
    if vein:
        v0 = _xf([(length * 0.04, 0.0)], x, y, ang)[0]
        v1 = _xf([(length * 0.92, 0.0)], x, y, ang)[0]
        dr.line([v0, v1], fill=_col(_lerp(mid, light, 0.9), 1.0, 4) + (255,), width=max(1, int(width * 0.045)))


def _shade(cols, k):
    """Leaf colour triple for a depth k in 0 (deep inside, dark) .. 1 (outer, lit)."""
    dark, mid, light = cols
    m = 0.55 + 0.55 * k
    return (_col(dark, m), _col(mid, m), _col(light, 0.7 + 0.5 * k))


# --- broadleaf cluster ("leaf mass" and "twig spray") ---------------------------------------------------------------------------------------------


def leaf_mass(seed, kind, cols, n=46, leaf_len=0.19, leaf_w=0.12, spread=0.43, size=CELL, jitter_hue=0.08, droop=0.0, hole=0.0):
    """A rounded mass of overlapping leaves filling the cell (pivot = centre). Back leaves are darker."""
    rng = np.random.RandomState(seed)
    W = size
    im = _canvas(W, W)
    dr = ImageDraw.Draw(im)
    pts = []
    core_r = spread * 0.78                                      # a dark core under the leaves: the interior of a crown is shadow, and the coverage stays high at distance
    dr.polygon([(W * SS * (0.5 + core_r * math.cos(t) * (0.92 + 0.12 * math.sin(t * 5 + seed))), W * SS * (0.5 + core_r * math.sin(t) * 0.86 + droop * core_r * core_r))
                for t in [i / 40.0 * math.tau for i in range(40)]], fill=_col(cols[0], 0.72) + (255,))
    for i in range(n):
        r = spread * math.sqrt(rng.rand())
        a = rng.rand() * math.tau
        cx = 0.5 + r * math.cos(a) * 1.0
        cy = 0.5 + r * math.sin(a) * 0.92 + droop * r * r
        depth = 1.0 - min(1.0, r / spread)                    # 1 in the centre (inside the crown: dark)
        pts.append((depth, cx, cy))
    pts.sort(key=lambda p: -p[0])                              # centre (dark, back) first, rim (lit, front) last
    for depth, cx, cy in pts:
        k = 1.0 - depth * 0.75
        k = max(0.0, min(1.0, k + (rng.rand() - 0.5) * 0.3))
        c = _shade(cols, k)
        if jitter_hue > 0:
            hs = 1.0 + (rng.rand() - 0.5) * jitter_hue * 2.0
            c = tuple(tuple(int(max(0, min(255, v * (hs if j == 1 else 1.0 + (rng.rand() - 0.5) * 0.04)))) for j, v in enumerate(cc)) for cc in c)
        L = leaf_len * W * SS * (0.75 + 0.5 * rng.rand())
        Wd = leaf_w * W * SS * (0.8 + 0.4 * rng.rand())
        ang = rng.rand() * math.tau
        # leaves on the rim point outward, which makes the ragged edge read as leaves, not as a disc
        if depth < 0.4:
            ang = math.atan2(cy - 0.5, cx - 0.5) + (rng.rand() - 0.5) * 1.3
        draw_leaf(dr, cx * W * SS - math.cos(ang) * L * 0.5, cy * W * SS - math.sin(ang) * L * 0.5, ang, L, Wd, kind, c, rng, bend=(rng.rand() - 0.5) * 0.25)
    return _finish(im, W, W)


def leaf_spray(seed, kind, cols, leaves=26, leaf_len=0.15, leaf_w=0.10, size=CELL, curve=0.12, twigs=3, hang=0.0):
    """A twig with leaves (base at the bottom centre, tip up): the card for ends of branches."""
    rng = np.random.RandomState(seed)
    W = size
    im = _canvas(W, W)
    dr = ImageDraw.Draw(im)
    twig_col = (74, 56, 38)

    def twig(x0, y0, ang0, length, n_leaves, scale, depth_k):
        pts = []
        x, y, a = x0, y0, ang0
        steps = 16
        for s in range(steps + 1):
            pts.append((x, y))
            x += math.cos(a) * length / steps
            y += math.sin(a) * length / steps
            a += (curve * (rng.rand() - 0.35)) / steps * 3.0 + hang * 0.02
        dr.line(pts, fill=twig_col + (255,), width=max(2, int(W * 0.012 * SS * scale)))
        for i in range(n_leaves):
            t = (i + 0.5) / n_leaves
            idx = min(steps, int(t * steps))
            px, py = pts[idx]
            side = 1 if i % 2 == 0 else -1
            la = ang0 + side * (0.55 + 0.5 * rng.rand()) + (a - ang0) * t
            L = leaf_len * W * SS * scale * (1.0 - 0.45 * t) * (0.85 + 0.3 * rng.rand())
            Wd = leaf_w * W * SS * scale * (1.0 - 0.35 * t) * (0.85 + 0.3 * rng.rand())
            k = max(0.0, min(1.0, depth_k + 0.5 * t + (rng.rand() - 0.5) * 0.25))
            draw_leaf(dr, px, py, la, L, Wd, kind, _shade(cols, k), rng, bend=(rng.rand() - 0.5) * 0.3)
        # terminal leaf
        px, py = pts[-1]
        draw_leaf(dr, px, py, a, leaf_len * W * SS * scale * 0.8, leaf_w * W * SS * scale * 0.85, kind, _shade(cols, depth_k + 0.5), rng)

    # back twigs (dark), then the main twig and the front ones
    main_len = W * SS * 0.78
    for j in range(twigs):
        sd = (j - (twigs - 1) / 2.0) * 0.55 + (rng.rand() - 0.5) * 0.2
        twig(W * SS * 0.5, W * SS * 0.96, -math.pi / 2 + sd, main_len * (0.55 + 0.2 * rng.rand()), leaves // 2, 0.9, 0.0)
    twig(W * SS * 0.5, W * SS * 0.97, -math.pi / 2 + (rng.rand() - 0.5) * 0.3, main_len, leaves, 1.0, 0.25)
    return _finish(im, W, W)


# --- conifers --------------------------------------------------------------------------------------------------------------------------------------


def _needle(dr, x, y, ang, length, width, col_base, col_tip):
    """One needle: a thin tapered quad, darker at the base."""
    ca, sa = math.cos(ang), math.sin(ang)
    px, py = -sa * width * 0.5, ca * width * 0.5
    mx, my = x + ca * length * 0.55, y + sa * length * 0.55
    tx, ty = x + ca * length, y + sa * length
    dr.polygon([(x + px, y + py), (mx + px * 0.8, my + py * 0.8), (tx, ty), (mx - px * 0.8, my - py * 0.8), (x - px, y - py)], fill=col_base + (255,))
    dr.polygon([(mx + px * 0.5, my + py * 0.5), (tx, ty), (mx - px * 0.5, my - py * 0.5)], fill=col_tip + (255,))


def pine_tuft(seed, cols, size=CELL, fascicles=52, length=0.44, spread=1.30):
    """Needle tuft of a pine (long needle pairs radiating from the bottom centre in a fan): the card for the ends of pine branches. A dense dark core keeps the coverage up at distance."""
    rng = np.random.RandomState(seed)
    W = size
    im = _canvas(W, W)
    dr = ImageDraw.Draw(im)
    dark, mid, light = cols
    ox, oy = W * SS * 0.5, W * SS * 0.93
    dr.line([(ox, W * SS), (ox, oy)], fill=(70, 52, 36, 255), width=int(W * SS * 0.022))
    # core: a rounded fan polygon in the dark colour (the needles' shadow)
    core = [(ox, oy)]
    for i in range(25):
        a = -math.pi / 2 - spread * 0.8 + (i / 24.0) * spread * 1.6
        r = W * SS * (0.20 + 0.10 * math.cos((a + math.pi / 2) * 1.2)) * (0.9 + 0.2 * rng.rand())
        core.append((ox + math.cos(a) * r * 1.15, oy + math.sin(a) * r * 1.0))
    dr.polygon(core, fill=_col(dark, 1.0) + (255,))
    items = []
    for i in range(fascicles):
        a = -math.pi / 2 + (rng.rand() - 0.5) * spread * 2.0 * (0.35 + 0.65 * rng.rand())
        items.append((abs(a + math.pi / 2), a))
    items.sort(key=lambda t: -t[0])
    for outer, a in items:
        L = W * SS * length * (0.62 + 0.5 * rng.rand()) * (1.0 - 0.30 * outer / spread)
        k = 0.25 + 0.75 * (1.0 - outer / spread) * (0.6 + 0.4 * rng.rand())
        base = _col(mid, 0.62 + 0.5 * k)
        tip = _col(_lerp(mid, light, 0.8), 0.8 + 0.5 * k)
        x = ox + (rng.rand() - 0.5) * W * SS * 0.05
        y = oy - rng.rand() * W * SS * 0.08
        for d in (-0.09, 0.09):
            _needle(dr, x, y, a + d + (rng.rand() - 0.5) * 0.05, L, W * SS * 0.020, base, tip)
    for i in range(20):                                                       # bunch at the tip for volume
        a = -math.pi / 2 + (rng.rand() - 0.5) * 2.2
        L = W * SS * 0.24 * (0.7 + 0.5 * rng.rand())
        _needle(dr, ox + (rng.rand() - 0.5) * W * SS * 0.08, oy - W * SS * 0.28 - rng.rand() * W * SS * 0.1, a, L, W * SS * 0.018, _col(dark, 0.95), _col(mid, 1.05))
    return texturize(_finish(im, W, W), seed, 0.08)


def fir_spray(seed, cols, aspect=2.0, size=CELL, snowy=0.0, drooping=0.35):
    """A flat fir / spruce branchlet: the rib runs from the left edge (the branch) to the right; side shoots carry needle rows; a dark filled outline under them keeps the coverage
    up at distance. Returns an image of size (size * aspect) x size (the atlas has a wide cell for it)."""
    rng = np.random.RandomState(seed)
    Wc = int(size * aspect)
    Hc = size
    im = _canvas(Wc, Hc)
    dr = ImageDraw.Draw(im)
    dark, mid, light = cols
    rib_y = Hc * 0.5 * SS
    x0 = Wc * 0.02 * SS
    x1 = Wc * 0.99 * SS

    def rib_at(t):
        return (x0 + (x1 - x0) * t, rib_y + math.sin(t * 2.4) * Hc * 0.04 * SS + drooping * Hc * 0.1 * SS * t * t)
    rib = [rib_at(i / 40) for i in range(41)]
    # filled outline: a long triangle (wide at the branch end, pointed at the tip), a little ragged
    top, bot = [], []
    for i in range(41):
        t = i / 40
        bx, by = rib[i]
        wd = Hc * SS * 0.50 * (1.0 - t ** 1.15) * (0.9 + 0.2 * rng.rand())
        top.append((bx, by - wd * 0.95))
        bot.append((bx, by + wd * 0.95))
    dr.polygon(top + bot[::-1], fill=_col(dark, 0.95) + (255,))
    dr.line(rib, fill=(86, 62, 42, 255), width=max(2, int(Hc * 0.025 * SS)))
    shoots = 26
    for side_pass in (1, 2):
        for i in range(shoots):
            t = (i + 0.3 + 0.4 * rng.rand()) / shoots
            idx = int(t * 40)
            bx, by = rib[idx]
            for side in (-1, 1):
                if side_pass == 1 and side == 1 or side_pass == 2 and side == -1:
                    continue
                reach = Hc * (0.50 * (1.0 - 0.80 * t ** 1.2)) * SS * (0.80 + 0.34 * rng.rand())
                ang = side * (math.radians(60) - 0.35 * t) + (rng.rand() - 0.5) * 0.18 + 0.12
                ex, ey = bx + math.cos(ang) * reach * 0.62, by + math.sin(ang) * reach * 1.0
                dr.line([(bx, by), (ex, ey)], fill=(80, 58, 40, 255), width=max(1, int(Hc * 0.012 * SS)))
                nn = 10
                for j in range(nn):
                    u = (j + 0.5) / nn
                    nx, ny = bx + (ex - bx) * u, by + (ey - by) * u
                    for ns in (-1, 1):
                        na = ang + ns * math.radians(55) + (rng.rand() - 0.5) * 0.3
                        nl = Hc * SS * (0.075 - 0.030 * u) * (0.85 + 0.3 * rng.rand())
                        k = max(0.0, min(1.0, 0.25 + 0.55 * u + (rng.rand() - 0.5) * 0.35 + (0.25 if side_pass == 2 else 0.0)))
                        _needle(dr, nx, ny, na, nl, Hc * SS * 0.017, _col(mid, 0.7 + 0.6 * k), _col(_lerp(mid, light, 0.7), 0.85 + 0.5 * k))
    if snowy > 0:
        for i in range(int(140 * snowy)):
            t = rng.rand()
            x = x0 + (x1 - x0) * t
            y = rib_y + (rng.rand() - 0.62) * Hc * 0.46 * SS * (1.0 - 0.75 * t)
            r = Hc * SS * (0.010 + 0.016 * rng.rand())
            dr.ellipse([x - r * 1.5, y - r, x + r * 1.5, y + r], fill=(238, 242, 248, 240))
    return texturize(_finish(im, Wc, Hc), seed, 0.08)


def palm_frond(seed, cols, aspect=4.0, size=CELL, leaflets=30):
    """A pinnate palm frond along the x axis (base at the left), leaflets hanging forward and down. Returns an image of size (size * aspect / 2) x (size / 2): the atlas has a 512 x 128 slot."""
    rng = np.random.RandomState(seed)
    Wc = int(size * aspect / 2)
    Hc = int(size / 2)
    im = _canvas(Wc, Hc)
    dr = ImageDraw.Draw(im)
    dark, mid, light = cols
    rib = []
    for i in range(61):
        t = i / 60
        rib.append((Wc * SS * (0.02 + 0.96 * t), Hc * SS * (0.42 - 0.04 * math.sin(t * math.pi) + 0.06 * t * t)))
    dr.line(rib, fill=(120, 104, 56, 255), width=max(2, int(Hc * 0.035 * SS)))
    for i in range(leaflets):
        t = 0.08 + 0.90 * (i + rng.rand() * 0.5) / leaflets
        idx = int(t * 60)
        bx, by = rib[idx]
        for side in (-1, 1):
            L = Hc * SS * 0.50 * math.sin(math.pi * (0.10 + 0.90 * t)) ** 0.6 * (0.85 + 0.25 * rng.rand()) + Hc * SS * 0.08
            ang = side * math.radians(46 + 12 * t) + (rng.rand() - 0.5) * 0.1
            ca, sa = math.cos(ang), math.sin(ang)
            wdt = Hc * SS * 0.062
            tipx = bx + ca * L * 0.80
            tipy = by + sa * L * 0.95 + (L * 0.10 if side > 0 else L * 0.0)
            midx = bx + (tipx - bx) * 0.5
            midy = by + (tipy - by) * 0.45
            k = 0.35 + 0.55 * rng.rand() + (0.1 if side < 0 else 0.0)
            c0 = _col(dark, 0.7 + 0.5 * k)
            c1 = _col(_lerp(dark, mid, 0.8), 0.8 + 0.5 * k)
            dr.polygon([(bx, by - wdt * 0.55), (midx, midy - wdt), (tipx, tipy), (midx, midy + wdt * 0.8), (bx, by + wdt * 0.55)], fill=c0 + (255,))
            dr.polygon([(bx + (midx - bx) * 0.15, by + (midy - by) * 0.15 - wdt * 0.2), (midx, midy - wdt * 0.55), (tipx, tipy), (midx, midy + wdt * 0.25)], fill=c1 + (255,))
            dr.line([(bx, by), (tipx, tipy)], fill=_col(_lerp(mid, light, 0.7), 0.9 + 0.2 * k) + (255,), width=max(1, int(Hc * 0.010 * SS)))
    return texturize(_finish(im, Wc, Hc), seed, 0.07)


def acacia_sprig(seed, cols, size=CELL):
    """Acacia canopy card: a flat ellipse of tiny feathery leaflets (pivot = the middle), lighter on top."""
    rng = np.random.RandomState(seed)
    W = size
    im = _canvas(W, W)
    dr = ImageDraw.Draw(im)
    pts = []
    dr.ellipse([W * SS * 0.05, W * SS * 0.30, W * SS * 0.95, W * SS * 0.72], fill=_col(cols[0], 0.85) + (255,))
    for i in range(900):
        r = math.sqrt(rng.rand())
        a = rng.rand() * math.tau
        x = 0.5 + 0.47 * r * math.cos(a)
        y = 0.5 + 0.24 * r * math.sin(a) + 0.05 * (r * r)
        pts.append((y, x, r))
    pts.sort(key=lambda p: p[0] * -1.0 + (1.0 - p[2]) * 0.4)         # lower / inner first
    for y, x, r in pts:
        k = max(0.0, min(1.0, 0.25 + 0.55 * (1.0 - y) + (rng.rand() - 0.5) * 0.3))
        ang = (rng.rand() - 0.5) * 0.9 + (0.0 if rng.rand() < 0.5 else math.pi)
        draw_leaf(dr, x * W * SS, y * W * SS, ang, W * SS * (0.045 + 0.03 * rng.rand()), W * SS * (0.022 + 0.012 * rng.rand()), "lance", _shade(cols, k), rng, vein=False)
    for i in range(34):                                                  # a few thin twigs peeking out at the rim
        a = rng.rand() * math.tau
        x = 0.5 + 0.40 * math.cos(a)
        y = 0.5 + 0.20 * math.sin(a)
        dr.line([(W * SS * 0.5, W * SS * 0.5), (x * W * SS, y * W * SS)], fill=(78, 60, 40, 60), width=1)
    return texturize(_finish(im, W, W), seed, 0.09)


def alien_leaf(seed, cols, size=CELL, glow=(120, 230, 255), n=9):
    """Glow leaves of the alien trees: broad crystalline blades fanning out from the bottom centre, a bright cyan edge and vein, dark violet body."""
    rng = np.random.RandomState(seed)
    W = size
    im = _canvas(W, W)
    dr = ImageDraw.Draw(im)
    dark, mid, light = cols
    ox, oy = W * SS * 0.5, W * SS * 0.96
    for i in range(n):
        a = -math.pi / 2 + (i - (n - 1) / 2.0) * 0.36 + (rng.rand() - 0.5) * 0.18
        L = W * SS * (0.55 + 0.35 * rng.rand()) * (1.0 - 0.1 * abs(i - n / 2) / n)
        Wd = W * SS * (0.20 + 0.08 * rng.rand())
        outline = _poly_leaf("lance", L, Wd, rng)
        o = _xf(outline, ox, oy, a)
        dr.polygon(o, fill=_col(dark, 0.9) + (255,))
        dr.polygon(_xf([(px * 0.9 + L * 0.05, py * 0.7) for px, py in outline], ox, oy, a), fill=_col(mid) + (255,))
        dr.polygon(_xf([(px * 0.7 + L * 0.2, py * 0.35) for px, py in outline], ox, oy, a), fill=_col(light) + (255,))
        dr.line(_xf([(L * 0.04, 0), (L * 0.95, 0)], ox, oy, a), fill=glow + (255,), width=max(2, int(W * SS * 0.012)))
        dr.line(o + [o[0]], fill=_col(glow, 0.85) + (255,), width=max(1, int(W * SS * 0.006)))
        for j in range(3):                                      # side veins
            t = 0.25 + 0.2 * j
            vx, vy = _xf([(L * t, 0)], ox, oy, a)[0]
            for sd in (-1, 1):
                ex, ey = _xf([(L * (t + 0.18), sd * Wd * 0.34)], ox, oy, a)[0]
                dr.line([(vx, vy), (ex, ey)], fill=_col(glow, 0.7) + (255,), width=max(1, int(W * SS * 0.004)))
    for i in range(7):                                          # glow spores
        a = rng.rand() * math.tau
        r = W * SS * (0.1 + 0.3 * rng.rand())
        sx, sy = ox + math.cos(a) * r * 0.9, oy - W * SS * 0.45 + math.sin(a) * r * 0.9
        rr = W * SS * (0.012 + 0.012 * rng.rand())
        dr.ellipse([sx - rr, sy - rr, sx + rr, sy + rr], fill=(210, 250, 255, 255))
    return _finish(im, W, W)


def dead_twig(seed, size=CELL):
    """Dry twigs with a few brown leaves: the card for dead trees and burnt shrubs."""
    rng = np.random.RandomState(seed)
    W = size
    im = _canvas(W, W)
    dr = ImageDraw.Draw(im)

    def branch(x, y, a, L, depth):
        pts = [(x, y)]
        for i in range(8):
            x += math.cos(a) * L / 8
            y += math.sin(a) * L / 8
            a += (rng.rand() - 0.5) * 0.35
            pts.append((x, y))
        dr.line(pts, fill=(96, 82, 66, 255), width=max(1, int(W * SS * 0.012 / (depth + 1))))
        if depth < 3:
            for k in range(2 + (depth == 0)):
                idx = 2 + int(rng.rand() * 5)
                bx, by = pts[idx]
                branch(bx, by, a + (rng.rand() - 0.5) * 1.8, L * 0.55, depth + 1)
        else:
            for k in range(2):
                draw_leaf(dr, x, y, a + (rng.rand() - 0.5) * 2.0, W * SS * 0.05, W * SS * 0.03, "round", ((88, 66, 40), (122, 92, 54), (150, 118, 70)), rng, vein=False)
    branch(W * SS * 0.5, W * SS * 0.97, -math.pi / 2, W * SS * 0.5, 0)
    return _finish(im, W, W)


# --- ground cover ---------------------------------------------------------------------------------------------------------------------------------


def grass_clump(seed, cols, blades=34, aspect=0.5, size=CELL, height=0.95, lean=0.28, dry=0.0, seedheads=0.0):
    """A tuft of grass blades growing from the bottom centre (cell content is drawn tall at 1:aspect and squashed into the square cell)."""
    rng = np.random.RandomState(seed)
    Wc = int(size * aspect * 2)
    Hc = size
    im = _canvas(Wc, Hc)
    dr = ImageDraw.Draw(im)
    dark, mid, light = cols
    items = []
    for i in range(blades):
        items.append((rng.rand(), i))
    for z, i in sorted(items):
        x0 = Wc * SS * (0.5 + (rng.rand() - 0.5) * 0.30)
        h = Hc * SS * height * (0.45 + 0.55 * rng.rand())
        a0 = (rng.rand() - 0.5) * lean * 2.0
        bend = (rng.rand() - 0.5) * 0.9
        wdt = Wc * SS * (0.020 + 0.02 * rng.rand())
        k = 0.25 + 0.75 * z
        c0 = _col(dark, 0.7 + 0.5 * k)
        c1 = _col(mid, 0.75 + 0.5 * k)
        c2 = _col(light, 0.8 + 0.4 * k)
        if dry > 0 and rng.rand() < dry:
            c0, c1, c2 = _col((120, 100, 50), 0.8 + 0.4 * k), _col((170, 148, 80), 0.8 + 0.4 * k), _col((205, 184, 110), 0.8 + 0.3 * k)
        left, right = [], []
        steps = 14
        for s in range(steps + 1):
            t = s / steps
            a = a0 + bend * t * t
            px = x0 + math.sin(a) * h * t
            py = Hc * SS - math.cos(a) * h * t
            w = wdt * (1.0 - t) ** 0.8 * (0.35 + 0.65 * min(1.0, t * 6.0) if t < 0.18 else 1.0)
            left.append((px - w, py))
            right.append((px + w, py))
        dr.polygon(left + right[::-1], fill=c0 + (255,))
        mid_l = [(left[s][0] * 0.35 + right[s][0] * 0.65, left[s][1]) for s in range(steps + 1)]
        mid_r = [(left[s][0] * 0.1 + right[s][0] * 0.9, left[s][1]) for s in range(steps + 1)]
        dr.polygon(mid_l + mid_r[::-1], fill=c2 + (255,))
        if seedheads > 0 and rng.rand() < seedheads and h > Hc * SS * 0.55:
            ex, ey = left[-1]
            for q in range(6):
                dr.ellipse([ex - wdt * 0.5, ey + q * wdt * 1.3 - wdt, ex + wdt * 0.6, ey + q * wdt * 1.3], fill=_col(light, 1.05) + (255,))
    return _finish(im, Wc, Hc, size, size)


def fern_frond(seed, cols, size=CELL, fronds=5):
    """Ferns: arched fronds with paired leaflets from the bottom centre."""
    rng = np.random.RandomState(seed)
    W = size
    im = _canvas(W, W)
    dr = ImageDraw.Draw(im)
    dark, mid, light = cols
    ox, oy = W * SS * 0.5, W * SS * 0.97
    order = sorted(range(fronds), key=lambda i: rng.rand())
    for fi, i in enumerate(order):
        a0 = -math.pi / 2 + (i - (fronds - 1) / 2.0) * 0.52 + (rng.rand() - 0.5) * 0.15
        L = W * SS * (0.62 + 0.3 * rng.rand())
        pts = []
        a = a0
        x, y = ox, oy
        steps = 30
        for s in range(steps + 1):
            pts.append((x, y, a))
            x += math.cos(a) * L / steps
            y += math.sin(a) * L / steps
            a += (0.020 if math.cos(a0) >= 0 else -0.020) + (rng.rand() - 0.5) * 0.01
        k0 = 0.3 + 0.6 * (fi / max(1, fronds - 1))
        dr.line([(p[0], p[1]) for p in pts], fill=_col(dark, 0.7 + 0.4 * k0) + (255,), width=max(2, int(W * SS * 0.008)))
        for s in range(2, steps + 1):
            px, py, pa = pts[s]
            t = s / steps
            ll = W * SS * 0.20 * math.sin(math.pi * min(1.0, 0.1 + 0.9 * t)) ** 0.8 * (0.8 + 0.3 * rng.rand())
            for side in (-1, 1):
                la = pa + side * (math.radians(62) - 0.5 * t) + 0.12 * t
                k = max(0.0, min(1.0, k0 + (rng.rand() - 0.5) * 0.3))
                draw_leaf(dr, px, py, la, ll, W * SS * 0.028 * (1.0 - 0.3 * t), "lance", _shade(cols, k), rng, vein=False, bend=0.1 * side)
    return _finish(im, W, W)


def flower_patch(seed, petal, centre, stem=(70, 120, 50), n=9, size=CELL, kind="daisy"):
    """Wild flowers on thin stems (bottom centre = the root), drawn tall and squashed into the cell."""
    rng = np.random.RandomState(seed)
    Wc = size
    Hc = size
    im = _canvas(Wc, Hc)
    dr = ImageDraw.Draw(im)
    heads = []
    for i in range(n):
        x = Wc * SS * (0.12 + 0.76 * rng.rand())
        h = Hc * SS * (0.35 + 0.5 * rng.rand())
        lean = (rng.rand() - 0.5) * 0.35
        top = (x + math.sin(lean) * h, Hc * SS - math.cos(lean) * h)
        heads.append((top[1], x, top, lean))
    for _, x, top, lean in sorted(heads):
        dr.line([(x, Hc * SS), (x * 0.5 + top[0] * 0.5 + 4, (Hc * SS + top[1]) * 0.5), top], fill=stem + (255,), width=max(2, int(Wc * SS * 0.012)))
        for lv in range(2):                                       # leaves on the stem
            t = 0.2 + 0.25 * lv
            lx = x + (top[0] - x) * t
            ly = Hc * SS + (top[1] - Hc * SS) * t
            draw_leaf(dr, lx, ly, -math.pi / 2 + (1 if lv % 2 else -1) * 0.9, Wc * SS * 0.10, Wc * SS * 0.035, "lance", ((50, 90, 38), (72, 124, 52), (100, 150, 70)), rng, vein=False)
        r = Wc * SS * (0.06 + 0.03 * rng.rand())
        if kind == "daisy":
            for p in range(11):
                a = p / 11 * math.tau + rng.rand() * 0.2
                pl = _xf(_poly_leaf("lance", r * 1.25, r * 0.52, rng), top[0], top[1], a)
                dr.polygon(pl, fill=petal + (255,))
            dr.ellipse([top[0] - r * 0.42, top[1] - r * 0.42, top[0] + r * 0.42, top[1] + r * 0.42], fill=centre + (255,))
        elif kind == "poppy":
            for p in range(4):
                a = p / 4 * math.tau + 0.4
                cx2, cy2 = top[0] + math.cos(a) * r * 0.55, top[1] + math.sin(a) * r * 0.55
                dr.ellipse([cx2 - r * 0.75, cy2 - r * 0.7, cx2 + r * 0.75, cy2 + r * 0.7], fill=petal + (255,))
            dr.ellipse([top[0] - r * 0.28, top[1] - r * 0.28, top[0] + r * 0.28, top[1] + r * 0.28], fill=centre + (255,))
        else:                                                       # lavender / spike
            for p in range(7):
                yy = top[1] + p * r * 0.55
                for sd in (-1, 1):
                    dr.ellipse([top[0] + sd * r * 0.35 - r * 0.28, yy - r * 0.28, top[0] + sd * r * 0.35 + r * 0.28, yy + r * 0.28], fill=_col(petal, 0.85 + 0.25 * (p % 2)) + (255,))
    return _finish(im, Wc, Hc)


def reed_clump(seed, cols, size=CELL):
    """Reeds and bulrushes: tall narrow blades and brown seed heads."""
    rng = np.random.RandomState(seed)
    W = size
    im = _canvas(W, W)
    dr = ImageDraw.Draw(im)
    dark, mid, light = cols
    for i in range(22):
        x0 = W * SS * (0.5 + (rng.rand() - 0.5) * 0.46)
        h = W * SS * (0.55 + 0.42 * rng.rand())
        a0 = (rng.rand() - 0.5) * 0.28
        bend = (rng.rand() - 0.5) * 0.55
        wdt = W * SS * (0.011 + 0.008 * rng.rand())
        k = rng.rand()
        left, right = [], []
        for s in range(13):
            t = s / 12
            a = a0 + bend * t * t
            px = x0 + math.sin(a) * h * t
            py = W * SS - math.cos(a) * h * t
            w = wdt * (1.0 - t) ** 0.6
            left.append((px - w, py))
            right.append((px + w, py))
        dr.polygon(left + right[::-1], fill=_col(mid, 0.7 + 0.5 * k) + (255,))
        if rng.rand() < 0.22:
            ex, ey = left[-1]
            hl = W * SS * 0.07
            dr.ellipse([ex - W * SS * 0.012, ey - hl * 0.4, ex + W * SS * 0.012, ey + hl], fill=(96, 62, 38, 255))
    return _finish(im, W, W)


def solid_cell(col, size=CELL):
    return Image.new("RGBA", (size, size), col + (255,))


# --- palette ---------------------------------------------------------------------------------------------------------------------------------------

GREENS = {
    "oak": ((38, 70, 24), (72, 112, 36), (128, 164, 62)),
    "oak2": ((44, 72, 22), (88, 118, 34), (150, 168, 58)),
    "birch": ((70, 104, 34), (122, 152, 52), (186, 202, 92)),
    "poplar": ((50, 86, 30), (96, 134, 44), (158, 184, 74)),
    "pine": ((30, 68, 38), (58, 104, 56), (108, 148, 80)),
    "fir": ((24, 62, 44), (44, 98, 62), (92, 150, 100)),
    "fir2": ((28, 66, 48), (50, 102, 70), (100, 150, 108)),
    "palm": ((36, 78, 28), (70, 124, 44), (132, 172, 70)),
    "acacia": ((84, 100, 36), (132, 142, 52), (186, 184, 86)),
    "alien": ((34, 16, 78), (86, 48, 160), (160, 110, 230)),
    "alien2": ((14, 44, 78), (30, 100, 150), (90, 190, 220)),
    "grass": ((46, 86, 30), (92, 136, 44), (150, 180, 70)),
    "grass_dry": ((120, 104, 52), (172, 150, 80), (210, 188, 116)),
    "fern": ((28, 74, 30), (56, 116, 44), (110, 164, 76)),
    "reed": ((70, 100, 40), (116, 146, 62), (164, 186, 98)),
    "shrub": ((34, 64, 26), (68, 104, 38), (122, 150, 60)),
}

# atlas layout: name -> (x, y, w, h) in pixels of the 2048 x 1024 atlas
ATLAS_W, ATLAS_H = 2048, 1024
LAYOUT = {
    # row 0 and 1: 256 x 256 cells
    "oak_a": (0, 0, 256, 256), "oak_b": (256, 0, 256, 256), "oak_c": (512, 0, 256, 256), "birch_a": (768, 0, 256, 256), "birch_b": (1024, 0, 256, 256),
    "poplar_a": (1280, 0, 256, 256), "acacia_a": (1536, 0, 256, 256), "acacia_b": (1792, 0, 256, 256),
    "pine_a": (0, 256, 256, 256), "pine_b": (256, 256, 256, 256), "dead_a": (512, 256, 256, 256), "alien_a": (768, 256, 256, 256), "alien_b": (1024, 256, 256, 256),
    "shrub_a": (1280, 256, 256, 256), "shrub_b": (1536, 256, 256, 256), "opaque": (1792, 256, 256, 256),
    # row 2: wide cells (fir sprays 2:1, palm fronds 4:1)
    "fir_a": (0, 512, 512, 256), "fir_b": (512, 512, 512, 256), "fir_snow": (1024, 512, 512, 256), "palm_a": (1536, 512, 512, 128), "palm_b": (1536, 640, 512, 128),
    # row 3: ground cover, 128 x 256 tall cells (fern and reed two wide)
    "grass_a": (0, 768, 128, 256), "grass_b": (128, 768, 128, 256), "grass_dry": (256, 768, 128, 256), "grass_tall": (384, 768, 128, 256),
    "fern_a": (512, 768, 256, 256), "fern_b": (768, 768, 256, 256), "reed_a": (1024, 768, 256, 256),
    "daisy": (1280, 768, 256, 256), "poppy": (1536, 768, 128, 256), "lavender": (1664, 768, 128, 256), "clover": (1792, 768, 256, 256),
}


def build_cells():
    g = GREENS
    cells = {}
    cells["oak_a"] = texturize(leaf_mass(11, "oak", g["oak"], n=84, leaf_len=0.135, leaf_w=0.095), 11)
    cells["oak_b"] = texturize(leaf_mass(12, "oak", g["oak2"], n=90, leaf_len=0.13, leaf_w=0.09), 12)
    cells["oak_c"] = texturize(leaf_spray(13, "oak", g["oak"], leaves=26, leaf_len=0.16, leaf_w=0.11), 13)
    cells["birch_a"] = texturize(leaf_mass(21, "birch", g["birch"], n=130, leaf_len=0.10, leaf_w=0.07, droop=0.5), 21)
    cells["birch_b"] = texturize(leaf_spray(22, "birch", g["birch"], leaves=34, leaf_len=0.12, leaf_w=0.085, hang=1.0), 22)
    cells["poplar_a"] = texturize(leaf_mass(23, "round", g["poplar"], n=120, leaf_len=0.10, leaf_w=0.085, droop=0.2), 23)
    cells["acacia_a"] = acacia_sprig(31, g["acacia"])
    cells["acacia_b"] = acacia_sprig(32, g["acacia"])
    cells["pine_a"] = pine_tuft(41, g["pine"])
    cells["pine_b"] = pine_tuft(42, g["pine"], fascicles=60, length=0.40)
    cells["fir_a"] = fir_spray(51, g["fir"])
    cells["fir_b"] = fir_spray(52, g["fir2"], drooping=0.5)
    cells["fir_snow"] = fir_spray(53, g["fir"], snowy=1.0)
    cells["palm_a"] = palm_frond(61, g["palm"])
    cells["palm_b"] = palm_frond(62, g["palm"], leaflets=26)
    cells["dead_a"] = dead_twig(71)
    cells["alien_a"] = alien_leaf(81, g["alien"])
    cells["alien_b"] = alien_leaf(82, g["alien2"], glow=(150, 255, 210))
    cells["shrub_a"] = texturize(leaf_mass(91, "oak", g["shrub"], n=90, leaf_len=0.13, leaf_w=0.085), 91)
    cells["shrub_b"] = texturize(leaf_mass(92, "round", g["shrub"], n=100, leaf_len=0.10, leaf_w=0.08), 92)
    cells["fern_a"] = fern_frond(101, g["fern"])
    cells["fern_b"] = fern_frond(102, g["fern"], fronds=7)
    cells["reed_a"] = reed_clump(111, g["reed"])
    cells["opaque"] = solid_cell((255, 255, 255))
    cells["grass_a"] = grass_clump(121, g["grass"], blades=30, aspect=0.5).resize((128, 256), Image.LANCZOS)
    cells["grass_b"] = grass_clump(122, g["grass"], blades=24, lean=0.45, aspect=0.5).resize((128, 256), Image.LANCZOS)
    cells["grass_dry"] = grass_clump(123, g["grass_dry"], blades=28, dry=0.6, seedheads=0.35, aspect=0.5).resize((128, 256), Image.LANCZOS)
    cells["grass_tall"] = grass_clump(124, g["grass"], blades=20, height=1.0, aspect=0.5, seedheads=0.25).resize((128, 256), Image.LANCZOS)
    cells["daisy"] = flower_patch(131, (246, 246, 240), (240, 200, 40), kind="daisy")
    cells["poppy"] = flower_patch(132, (214, 40, 36), (36, 28, 24), kind="poppy", n=8).resize((128, 256), Image.LANCZOS)
    cells["lavender"] = flower_patch(133, (126, 96, 190), (0, 0, 0), kind="spike", n=8).resize((128, 256), Image.LANCZOS)
    cells["clover"] = flower_patch(134, (232, 150, 190), (255, 230, 120), kind="daisy", n=10)
    return cells


def build_atlas():
    cells = build_cells()
    atlas = Image.new("RGBA", (ATLAS_W, ATLAS_H), (0, 0, 0, 0))
    for name, (x, y, w, h) in LAYOUT.items():
        c = cells[name]
        if c.size != (w, h):
            c = c.resize((w, h), Image.LANCZOS)
        atlas.paste(c, (x, y))
    return atlas, cells


def cell_rect(name, inset=2.0):
    """UV rectangle (u0, v0, u1, v1) of an atlas cell, inset by `inset` texels against bleeding."""
    x, y, w, h = LAYOUT[name]
    return ((x + inset) / ATLAS_W, (y + inset) / ATLAS_H, (x + w - inset) / ATLAS_W, (y + h - inset) / ATLAS_H)


if __name__ == "__main__":
    import sys
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/land_foliage_preview.png"
    atlas, _ = build_atlas()
    bg = Image.new("RGBA", atlas.size, (150, 170, 200, 255))
    bg.alpha_composite(atlas)
    bg.convert("RGB").save(out)
    print(out)
