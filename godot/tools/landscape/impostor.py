"""Orthographic bake of a tree (MeshBuilder with its foliage cards and tubes) into an RGBA picture: the cross-billboard impostors of the far LOD and the preview sheets.

No GPU, no Blender: every card is a parallelogram under orthographic projection, so it is pasted with an affine transform of its atlas sprite (tinted by its ambient-occlusion
tint), far to near; branches are flat-shaded quads in the bark colour. The result is albedo only (no sun): the game shader lights the impostor quads with bent normals like the
real foliage cards.
"""
import math

import numpy as np
from PIL import Image, ImageDraw

UP = np.array([0.0, 1.0, 0.0])


def _crop(atlas, rect, flip_u):
    W, H = atlas.size
    u0, v0, u1, v1 = rect
    box = (int(round(u0 * W - 1.5)), int(round(v0 * H - 1.5)), int(round(u1 * W + 1.5)), int(round(v1 * H + 1.5)))
    box = (max(0, box[0]), max(0, box[1]), min(W, box[2]), min(H, box[3]))
    t = atlas.crop(box)
    if flip_u:
        t = t.transpose(Image.FLIP_LEFT_RIGHT)
    return t


def _tint(tex, tint):
    a = np.asarray(tex, dtype=np.float32)
    a[..., 0] *= tint[0]
    a[..., 1] *= tint[1]
    a[..., 2] *= tint[2]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def _paste(canvas, tex, tl, tr, bl):
    w, h = tex.size
    ux, uy = tr[0] - tl[0], tr[1] - tl[1]
    vx, vy = bl[0] - tl[0], bl[1] - tl[1]
    lu, lv = math.hypot(ux, uy), math.hypot(vx, vy)
    if lu < 0.5 or lv < 0.5 or abs(ux * vy - uy * vx) < 0.5:
        return
    tw, th = max(2, int(round(min(w, lu * 1.3)))), max(2, int(round(min(h, lv * 1.3))))
    if (tw, th) != (w, h):
        tex = tex.resize((tw, th), Image.LANCZOS)
        w, h = tw, th
    A = np.array([[ux / w, vx / h], [uy / w, vy / h]])
    Ai = np.linalg.inv(A)
    xs = [tl[0], tr[0], bl[0], tr[0] + vx, ]
    ys = [tl[1], tr[1], bl[1], tr[1] + vy]
    x0, x1 = int(max(0, math.floor(min(xs)) - 1)), int(min(canvas.width, math.ceil(max(xs)) + 1))
    y0, y1 = int(max(0, math.floor(min(ys)) - 1)), int(min(canvas.height, math.ceil(max(ys)) + 1))
    if x1 <= x0 or y1 <= y0:
        return
    a, b = Ai[0]
    d, e = Ai[1]
    # input = Ai @ (S - tl), S = (x0 + X, y0 + Y)
    c = a * (x0 - tl[0]) + b * (y0 - tl[1])
    f = d * (x0 - tl[0]) + e * (y0 - tl[1])
    layer = tex.transform((x1 - x0, y1 - y0), Image.AFFINE, (a, b, c, d, e, f), resample=Image.BILINEAR)
    canvas.alpha_composite(layer, dest=(x0, y0))


def render(mb, atlas, az, scale, size, bark=(104, 80, 56), origin_x=0.0, ss=2):
    """Render one view. scale = pixels per metre (at 1x), size = (w, h) in pixels at 1x, the ground line at the bottom, x centred on `origin_x`."""
    W, H = size[0] * ss, size[1] * ss
    sc = scale * ss
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    rv = np.array([math.cos(az), 0.0, -math.sin(az)])
    fw = np.array([math.sin(az), 0.0, math.cos(az)])

    def proj(p):
        return (W * 0.5 + (float(np.dot(p, rv)) - origin_x) * sc, H - 2 - float(p[1]) * sc)

    items = []
    for c in mb.cards:
        if isinstance(c[0], str):
            items.append(("strip", float(np.dot(np.mean(c[1], axis=0), fw)), c))
        else:
            items.append(("card", float(np.dot(c[0], fw)), c))
    for pts, radii in mb.tubes:
        for i in range(len(pts) - 1):
            items.append(("tube", float(np.dot((pts[i] + pts[i + 1]) * 0.5, fw)), (pts[i], pts[i + 1], radii[i], radii[i + 1])))
    items.sort(key=lambda it: -it[1])
    dr = ImageDraw.Draw(canvas)
    for kind, depth, c in items:
        if kind == "tube":
            p0, p1, r0, r1 = c
            a, b = proj(p0), proj(p1)
            dx, dy = b[0] - a[0], b[1] - a[1]
            ln = math.hypot(dx, dy)
            if ln < 1e-6:
                continue
            nx, ny = -dy / ln, dx / ln
            w0, w1 = max(1.0, r0 * sc), max(1.0, r1 * sc)
            shade = 0.82 + 0.18 * min(1.0, max(0.0, (p0[1] + p1[1]) * 0.05))
            col = tuple(int(min(255, v * shade)) for v in bark) + (255,)
            dr.polygon([(a[0] + nx * w0, a[1] + ny * w0), (b[0] + nx * w1, b[1] + ny * w1), (b[0] - nx * w1, b[1] - ny * w1), (a[0] - nx * w0, a[1] - ny * w0)], fill=col)
        elif kind == "card":
            cc, r, u, rect, tint, cell, flip = c
            tex = _tint(_crop(atlas, rect, flip), tint)
            tl, tr, bl = proj(cc - r + u), proj(cc + r + u), proj(cc - r - u)
            _paste(canvas, tex, tl, tr, bl)
            dr = ImageDraw.Draw(canvas)
        else:
            _, pts, widths, rect, tint, cell, side = c
            k = len(pts)
            for i in range(k - 1):
                f0, f1 = i / (k - 1), (i + 1) / (k - 1)
                sub = (rect[0] + (rect[2] - rect[0]) * f0, rect[1], rect[0] + (rect[2] - rect[0]) * f1, rect[3])
                tex = _tint(_crop(atlas, sub, False), tint)
                s = np.asarray(side) if side is not None else np.cross(pts[i + 1] - pts[i], UP)
                s = s / max(np.linalg.norm(s), 1e-6)
                w0, w1 = widths[i], widths[i + 1]
                p0, p1 = pts[i], pts[i + 1]
                # tex u runs along the strip, v across: left = -side (v1 = bottom row), right = +side (v0 = top row)
                tl_ = proj(p0 + s * w0)
                tr_ = proj(p1 + s * w1)
                bl_ = proj(p0 - s * w0)
                _paste(canvas, tex, tl_, tr_, bl_)
            dr = ImageDraw.Draw(canvas)
    # downsample in premultiplied space
    a = np.asarray(canvas, dtype=np.float32) / 255.0
    pm = np.concatenate([a[..., :3] * a[..., 3:4], a[..., 3:4]], axis=2)
    im = Image.fromarray((pm * 255 + 0.5).astype(np.uint8), "RGBA").resize(size, Image.LANCZOS)
    b = np.asarray(im, dtype=np.float32) / 255.0
    al = b[..., 3:4]
    rgb = np.where(al > 1e-3, b[..., :3] / np.maximum(al, 1e-3), 0.0)
    return Image.fromarray((np.concatenate([np.clip(rgb, 0, 1), al], axis=2) * 255 + 0.5).astype(np.uint8), "RGBA")


def extents(mb):
    """(height, max horizontal radius) of the geometry including card corners."""
    pts = []
    for c in mb.cards:
        if isinstance(c[0], str):
            _, p, w, *_ = c
            for q, ww in zip(p, w):
                pts.append(q)
                pts.append(q + np.array([ww, 0, ww]))
                pts.append(q - np.array([ww, 0, ww]))
        else:
            cc, r, u = c[0], c[1], c[2]
            for sx in (-1, 1):
                for sy in (-1, 1):
                    pts.append(cc + r * sx + u * sy)
    for p, rr in mb.tubes:
        for q, r in zip(p, rr):
            pts.append(q)
    pts = np.array(pts)
    return float(pts[:, 1].max()), float(np.max(np.hypot(pts[:, 0], pts[:, 2])))
