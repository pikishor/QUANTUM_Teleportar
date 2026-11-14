"""Quick numpy previews of kit meshes (no GPU, no Godot): orthographic z-buffer, smooth shading from the vertex normals, tint, baked AO and glow. For modelling iterations and the lineup sheets
of docs/shots; the real look (PBR textures) is judged in Godot.

    from weapon_preview import sheet
    sheet([("name", mesh_dict), ...], "out.png", views=("side", "q34"), cell=(360, 190))
"""
import math

import numpy as np

import weaponlib as wl


def _basis(view):
    # returns (right, up, toward-viewer) in the K frame (x right, y forward, z up)
    if view == "side":                       # seen from the weapon's right side, muzzle to the right
        r, u, w = (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0)
    elif view == "top":
        r, u, w = (0.0, 1.0, 0.0), (-1.0, 0.0, 0.0), (0.0, 0.0, 1.0)
    elif view == "front":
        r, u, w = (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0)
    else:                                    # q34: from the right, a little from the front and above
        yaw, pit = math.radians(-32.0), math.radians(22.0)
        w = np.array([math.cos(pit) * math.cos(yaw), -math.cos(pit) * math.sin(yaw) * -1.0, math.sin(pit)])
        w = np.array([math.cos(pit) * math.cos(math.radians(30.0)), math.cos(pit) * math.sin(math.radians(30.0)), math.sin(pit)])
        r = np.cross((0, 0, 1.0), w)
        r = r / np.linalg.norm(r)
        u = np.cross(w, r)
        return np.array(r), np.array(u), np.array(w)
    return np.array(r), np.array(u), np.array(w)


def render(m, view="side", size=(360, 190), ss=2, bg=(26, 28, 34), frame=None):
    P, N, F = m["P"], m["N"], m["F"]
    r, u, w = _basis(view)
    sx, sy, sz = P @ r, P @ u, P @ w
    if frame is None:
        frame = (sx.min(), sx.max(), sy.min(), sy.max())
    x0, x1, y0, y1 = frame
    W, H = size[0] * ss, size[1] * ss
    sc = min((W * 0.92) / max(x1 - x0, 1e-4), (H * 0.88) / max(y1 - y0, 1e-4))
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    px = (sx - cx) * sc + W / 2.0
    py = H / 2.0 - (sy - cy) * sc
    zb = np.full((H, W), -1e9)
    img = np.zeros((H, W, 3), dtype=np.float64)
    img[:] = np.array(bg, dtype=np.float64) / 255.0
    light = wl.unit(np.array([0.35, 0.45, 0.85]))
    light = wl.unit(r * -0.45 + u * 0.75 + w * 0.5)
    fill = wl.unit(r * 0.7 + u * -0.1 + w * 0.3)
    tint = m["tint"]
    metal = np.array([0.0] * 64)
    for i in (2, 3, 4, 5, 6, 17, 25, 26):
        metal[i] = 1.0
    ml = metal[np.clip(m["layer"], 0, 63)]
    for t in F:
        a, b, c = t
        xs = (px[a], px[b], px[c])
        ys = (py[a], py[b], py[c])
        minx = max(int(math.floor(min(xs))), 0)
        maxx = min(int(math.ceil(max(xs))), W - 1)
        miny = max(int(math.floor(min(ys))), 0)
        maxy = min(int(math.ceil(max(ys))), H - 1)
        if maxx < minx or maxy < miny:
            continue
        den = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
        if abs(den) < 1e-9:
            continue
        gx, gy = np.meshgrid(np.arange(minx, maxx + 1) + 0.5, np.arange(miny, maxy + 1) + 0.5)
        l0 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / den
        l1 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / den
        l2 = 1.0 - l0 - l1
        mask = (l0 >= -1e-6) & (l1 >= -1e-6) & (l2 >= -1e-6)
        if not mask.any():
            continue
        z = l0 * sz[a] + l1 * sz[b] + l2 * sz[c]
        sub = zb[miny:maxy + 1, minx:maxx + 1]
        vis = mask & (z > sub)
        if not vis.any():
            continue
        sub[vis] = z[vis]
        nn = (l0[..., None] * N[a] + l1[..., None] * N[b] + l2[..., None] * N[c])
        nn = nn / np.maximum(np.linalg.norm(nn, axis=-1, keepdims=True), 1e-9)
        nl = np.clip(nn @ light, 0.0, 1.0)
        nf = np.clip(nn @ fill, 0.0, 1.0)
        up = 0.5 + 0.5 * (nn @ u)
        base = (l0[..., None] * tint[a] + l1[..., None] * tint[b] + l2[..., None] * tint[c])
        ao = (l0 * m["ao"][a] + l1 * m["ao"][b] + l2 * m["ao"][c])[..., None]
        mt = (l0 * ml[a] + l1 * ml[b] + l2 * ml[c])[..., None]
        gl = (l0 * m["glow"][a] + l1 * m["glow"][b] + l2 * m["glow"][c])[..., None]
        refl = nn @ wl.unit(light + w)
        spec = np.clip(refl, 0, 1) ** (14.0 + 40.0 * mt[..., 0])
        diff = 0.25 + 0.95 * nl[..., None] + 0.28 * nf[..., None] + 0.22 * up[..., None]
        col = base * diff * (0.35 + 0.65 * ao) * (1.0 - 0.45 * mt) + spec[..., None] * (0.12 + 0.55 * mt) * (0.4 + 0.6 * ao)
        col = col + gl * base * 1.6
        col = np.clip(col, 0, 1)
        col = col ** (1.0 / 2.2)
        reg = img[miny:maxy + 1, minx:maxx + 1]
        reg[vis] = col[vis]
    img = img.reshape(H // ss, ss, W // ss, ss, 3).mean(axis=(1, 3))
    return (np.clip(img, 0, 1) * 255).astype(np.uint8)


def sheet(items, path, views=("side", "q34"), cell=(360, 190), cols=2, label=True):
    from PIL import Image, ImageDraw
    rows = (len(items) + cols - 1) // cols
    W = cell[0] * len(views) * cols
    H = cell[1] * rows
    out = Image.new("RGB", (W, H), (20, 22, 28))
    d = ImageDraw.Draw(out)
    for k, (name, m) in enumerate(items):
        # a common frame per item so the views have the same scale
        for j, v in enumerate(views):
            im = Image.fromarray(render(m, v, cell))
            x = ((k % cols) * len(views) + j) * cell[0]
            y = (k // cols) * cell[1]
            out.paste(im, (x, y))
        if label:
            d.text(((k % cols) * len(views) * cell[0] + 6, (k // cols) * cell[1] + 4), name, fill=(255, 220, 120))
    out.save(path)
    return path
