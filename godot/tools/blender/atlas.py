"""Bake one texture atlas per model (bpy + numpy): unique UVs, per-texel ambient occlusion, edge wear and grime, decals, normal map.

Why: every tiling-texture material costs a draw call and a flat tint cannot show wear. Here all opaque surfaces of a model share
ONE material whose textures are baked on the model itself, so the model costs a handful of draw calls and shows real wear: paint
chipped along bevelled edges, grime in cavities and near the ground, scratches, stencils.

Pipeline (see bake()):
  1. cull_hidden()     delete faces buried inside other geometry (saves triangles and texture space)
  2. extract()         triangles, normals, tint colours, crease edges of the built parts
  3. unwrap_pack()     planar islands per near-flat patch, one uniform texel density, shelf packing
  4. rasterize()       which triangle / barycentric coordinate every texel shows
  5. ao + creases      ray-traced occlusion on a coarse grid, distance to convex/concave creases
  6. shade.KINDS       every surface kind turns (position, tint, wear masks) into albedo, roughness, metal, emission, height
  7. decals, normal map from the height field, padding, PNG/JPEG output
Surface groups: "atlas" (the shared material), "paint" (a second atlas for the car body whose albedo stays neutral so it can be tinted
by the material colour), "flat" faces keep their own constant materials (emissive lights) and get no UVs.
"""
import json
import math
import os
import struct
import sys
import time
import zlib

import numpy as np

import bpy  # noqa: F401  (must be imported before mathutils)
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import shade  # noqa: E402

PAD = 4                      # texels of padding around every island (mip bleeding, filtering)
CREASE_DEG = 24.0            # dihedral angle above which an edge counts as a crease (wear / panel line)
ISLAND_COS_SEED = 0.70       # a face joins an island when its normal is within 45 deg of the island's first face
ISLAND_COS_MEAN = 0.78


# ------------------------------------------------------------------ PNG / JPEG writers
def write_png(path, arr):
    """8-bit grayscale / RGB / RGBA PNG (no dependencies); tries filters None/Sub/Up and keeps the smallest."""
    arr = np.ascontiguousarray(np.clip(arr, 0, 255).astype(np.uint8))
    h, w = arr.shape[:2]
    ch = 1 if arr.ndim == 2 else arr.shape[2]
    flat = arr.reshape(h, w * ch)
    best = None
    for ftype in (0, 1, 2):
        if ftype == 0:
            filt = flat
        elif ftype == 1:
            filt = flat.copy()
            filt[:, ch:] = (flat[:, ch:].astype(np.int16) - flat[:, :-ch].astype(np.int16)).astype(np.uint8)
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


def write_jpg(path, arr, quality=92):
    """RGB JPEG through Blender's image API (4:4:4 is not selectable, so keep quality high)."""
    h, w = arr.shape[:2]
    img = bpy.data.images.new("tmp_jpg", w, h, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "Non-Color"
    rgba = np.ones((h, w, 4), np.float32)
    rgba[..., :3] = np.clip(arr, 0, 255).astype(np.float32) / 255.0
    img.pixels.foreach_set(np.flipud(rgba).reshape(-1))      # Blender images are stored bottom-up
    img.update()
    scn = bpy.context.scene
    old = (scn.render.image_settings.file_format, scn.render.image_settings.quality, scn.render.image_settings.color_mode)
    scn.render.image_settings.file_format = "JPEG"
    scn.render.image_settings.quality = quality
    scn.render.image_settings.color_mode = "RGB"
    img.save_render(path, scene=scn)
    scn.render.image_settings.file_format, scn.render.image_settings.quality, scn.render.image_settings.color_mode = old
    bpy.data.images.remove(img)


# ------------------------------------------------------------------ hidden face culling (works on Part.bm, before build)
def cull_hidden(parts, probe=0.004, reach=0.6):
    """Delete faces that sit inside other geometry: from a point just above the face, rays along the normal and along four tilted
    directions all hit BACK faces (we are inside a solid). Hits on the face itself are skipped (warped quads triangulate away from
    their mean plane). Returns the number of faces removed."""
    verts, polys, owner = [], [], []
    for pi, p in enumerate(parts):
        p.bm.verts.ensure_lookup_table()
        p.bm.verts.index_update()
        p.bm.faces.ensure_lookup_table()
        p.bm.faces.index_update()
        base = len(verts)
        verts.extend([v.co.copy() for v in p.bm.verts])
        for f in p.bm.faces:
            vs = [base + v.index for v in f.verts]
            for k in range(1, len(vs) - 1):
                polys.append((vs[0], vs[k], vs[k + 1]))
                owner.append((pi, f.index))
    tree = BVHTree.FromPolygons(verts, polys, epsilon=0.0)
    removed = 0
    for pi, p in enumerate(parts):
        bm = p.bm
        bm.normal_update()
        kill = []
        for f in bm.faces:
            n = f.normal
            if n.length < 0.5:
                continue
            me = (pi, f.index)
            c0 = f.calc_center_median() + n * probe
            t = n.cross(Vector((0, 0, 1)))
            if t.length < 0.2:
                t = n.cross(Vector((1, 0, 0)))
            t.normalize()
            b = n.cross(t)
            inside = 0
            dirs = [n] + [(n * math.cos(0.9) + (t * math.cos(a) + b * math.sin(a)) * math.sin(0.9)).normalized() for a in (0.4, 1.97, 3.54, 5.11)]
            for d in dirs:
                c = c0
                hit = tree.ray_cast(c, d, reach)
                guard = 0
                while hit[0] is not None and owner[hit[2]] == me and guard < 3:      # our own (warped) face: look past it
                    c = hit[0] + d * 0.0005
                    hit = tree.ray_cast(c, d, reach)
                    guard += 1
                if hit[0] is not None and hit[1].dot(d) > 0.0:
                    inside += 1
            if inside == len(dirs):
                kill.append(f)
        if kill:
            if os.environ.get("QT_DEBUG_CULL"):
                names = {}
                for f in kill:
                    nm = p.slots[f.material_index].name
                    names.setdefault(nm, []).append(tuple(round(x, 2) for x in f.calc_center_median()))
                for nm, cs in names.items():
                    print("  [cull] %s/%s: %d faces, e.g. %s" % (p.name, nm, len(cs), cs[:4]))
                    if os.environ.get("QT_DEBUG_CULL") == "all":
                        for c in cs:
                            print("       ", c)
            bmesh.ops.delete(bm, geom=kill, context="FACES")
            removed += len(kill)
        bm.faces.ensure_lookup_table()
    return removed


# ------------------------------------------------------------------ geometry extraction from the built meshes
class Geo:
    """Triangles of all parts in model space plus the per-face data the baker needs."""


def extract(parts, kind_of_slot):
    g = Geo()
    tp, tn, tc, tf, tl = [], [], [], [], []
    face_part, face_kind, face_group, face_n, face_area = [], [], [], [], []
    seg_a, seg_b, seg_cv, seg_f1, seg_f2 = [], [], [], [], []
    adj = []
    loop_base = 0
    face_base = 0
    part_loops = []
    for pi, part in enumerate(parts):
        obj = part.obj
        me = obj.data
        me.calc_loop_triangles()
        off = np.array(obj.location, dtype=np.float64)
        nv, nl, npoly, ne = len(me.vertices), len(me.loops), len(me.polygons), len(me.edges)
        co = np.empty(nv * 3, np.float64)
        me.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3) + off
        lv = np.empty(nl, np.int32)
        me.loops.foreach_get("vertex_index", lv)
        le = np.empty(nl, np.int32)
        me.loops.foreach_get("edge_index", le)
        ln = np.empty(nl * 3, np.float64)
        me.corner_normals.foreach_get("vector", ln)
        ln = ln.reshape(-1, 3)
        lc = np.empty(nl * 4, np.float32)
        me.color_attributes["Col"].data.foreach_get("color", lc)
        lc = lc.reshape(-1, 4)[:, :3]
        ls = np.empty(npoly, np.int32)
        me.polygons.foreach_get("loop_start", ls)
        lt = np.empty(npoly, np.int32)
        me.polygons.foreach_get("loop_total", lt)
        mi = np.empty(npoly, np.int32)
        me.polygons.foreach_get("material_index", mi)
        pn = np.empty(npoly * 3, np.float64)
        me.polygons.foreach_get("normal", pn)
        pn = pn.reshape(-1, 3)
        pa = np.empty(npoly, np.float64)
        me.polygons.foreach_get("area", pa)
        nt = len(me.loop_triangles)
        tri_l = np.empty(nt * 3, np.int32)
        me.loop_triangles.foreach_get("loops", tri_l)
        tri_l = tri_l.reshape(-1, 3)
        tri_p = np.empty(nt, np.int32)
        me.loop_triangles.foreach_get("polygon_index", tri_p)
        tp.append(co[lv[tri_l]])
        tn.append(ln[tri_l])
        tc.append(lc[tri_l])
        tf.append(tri_p + face_base)
        tl.append(tri_l + loop_base)
        fk = [kind_of_slot(part, int(m)) for m in mi]
        face_part.extend([pi] * npoly)
        face_kind.extend([k[0] for k in fk])
        face_group.extend([k[1] for k in fk])
        face_n.append(pn)
        face_area.append(pa)
        part_loops.append((loop_base, nl))
        # edge adjacency: two loops per interior edge
        poly_of_loop = np.repeat(np.arange(npoly), lt)
        order = np.argsort(le, kind="stable")
        es, ps = le[order], poly_of_loop[order]
        same = np.nonzero(es[1:] == es[:-1])[0]
        pair = {}
        for k in same:
            e = int(es[k])
            if e not in pair:
                pair[e] = (int(ps[k]), int(ps[k + 1]))
        cnt = np.bincount(le, minlength=ne)
        ev = np.empty(ne * 2, np.int32)
        me.edges.foreach_get("vertices", ev)
        ev = ev.reshape(-1, 2)
        ngb = [[] for _ in range(npoly)]
        cos_c = math.cos(math.radians(CREASE_DEG))
        fcen = np.empty(npoly * 3, np.float64)
        me.polygons.foreach_get("center", fcen)
        fcen = fcen.reshape(-1, 3) + off
        for e in range(ne):
            a, b = co[ev[e, 0]], co[ev[e, 1]]
            if cnt[e] == 1:
                f1 = int(ps[np.searchsorted(es, e)])
                seg_a.append(a)
                seg_b.append(b)
                seg_cv.append(1)
                seg_f1.append(f1 + face_base)
                seg_f2.append(-1)
            elif e in pair and cnt[e] == 2:
                f1, f2 = pair[e]
                ngb[f1].append(f2 + face_base)
                ngb[f2].append(f1 + face_base)
                if float(np.dot(pn[f1], pn[f2])) < cos_c:
                    mid = (a + b) * 0.5
                    convex = 1 if float(np.dot(pn[f1], fcen[f2] - mid)) < 0.0 else 0
                    seg_a.append(a)
                    seg_b.append(b)
                    seg_cv.append(convex)
                    seg_f1.append(f1 + face_base)
                    seg_f2.append(f2 + face_base)
        adj.extend(ngb)
        loop_base += nl
        face_base += npoly
    g.tri_p = np.concatenate(tp)
    g.tri_n = np.concatenate(tn)
    g.tri_c = np.concatenate(tc)
    g.tri_f = np.concatenate(tf)
    g.tri_l = np.concatenate(tl)
    g.face_part = np.array(face_part, np.int32)
    g.face_kind = np.array(face_kind, np.int32)
    g.face_group = np.array(face_group, np.int32)
    g.face_n = np.concatenate(face_n)
    g.face_area = np.concatenate(face_area)
    g.adj = adj
    g.seg_a = np.array(seg_a).reshape(-1, 3)
    g.seg_b = np.array(seg_b).reshape(-1, 3)
    g.seg_cv = np.array(seg_cv, np.int8)
    g.seg_f1 = np.array(seg_f1, np.int32)
    g.seg_f2 = np.array(seg_f2, np.int32)
    g.part_loops = part_loops
    g.n_loops = loop_base
    g.n_faces = face_base
    return g


# ------------------------------------------------------------------ unwrap: islands, projection, packing
def make_islands(g, group_ids):
    """Cluster the faces of the given groups into near-planar islands (region growing on the face adjacency)."""
    isl = np.full(g.n_faces, -1, np.int32)
    islands = []
    want = np.isin(g.face_group, group_ids)
    for seed in range(g.n_faces):
        if isl[seed] >= 0 or not want[seed]:
            continue
        k = len(islands)
        isl[seed] = k
        members = [seed]
        n0 = g.face_n[seed]
        mean = n0 * g.face_area[seed]
        stack = [seed]
        while stack:
            f = stack.pop()
            for nb in g.adj[f]:
                if isl[nb] >= 0 or not want[nb] or g.face_group[nb] != g.face_group[seed]:
                    continue
                nn = g.face_n[nb]
                m = mean / (np.linalg.norm(mean) + 1e-12)
                if float(np.dot(nn, n0)) >= ISLAND_COS_SEED and float(np.dot(nn, m)) >= ISLAND_COS_MEAN:
                    isl[nb] = k
                    members.append(nb)
                    mean = mean + nn * g.face_area[nb]
                    stack.append(nb)
        islands.append(members)
    return isl, islands


def project_islands(g, isl, islands):
    """Planar projection of every island along its mean normal, rotated to the principal axis. Returns per-loop 2D coordinates
    (metres, minimum corner at the origin) and the island rectangles (width, height)."""
    loop_xy = np.zeros((g.n_loops, 2), np.float64)
    loop_isl = np.full(g.n_loops, -1, np.int32)
    tri_by_face = {}
    order = np.argsort(g.tri_f, kind="stable")
    tf_sorted = g.tri_f[order]
    starts = np.searchsorted(tf_sorted, np.arange(g.n_faces))
    ends = np.searchsorted(tf_sorted, np.arange(g.n_faces), side="right")
    rects = []
    for k, members in enumerate(islands):
        tris = np.concatenate([order[starts[f]:ends[f]] for f in members])
        pos = g.tri_p[tris].reshape(-1, 3)
        loops = g.tri_l[tris].reshape(-1)
        nrm = (g.face_n[members] * g.face_area[members][:, None]).sum(axis=0)
        nrm /= np.linalg.norm(nrm) + 1e-12
        helper = np.array([0.0, 0.0, 1.0]) if abs(nrm[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
        t0 = np.cross(helper, nrm)
        t0 /= np.linalg.norm(t0)
        b0 = np.cross(nrm, t0)
        xy = np.stack([pos @ t0, pos @ b0], axis=1)
        ctr = xy.mean(axis=0)
        d = xy - ctr
        cov = d.T @ d
        ang = 0.5 * math.atan2(2 * cov[0, 1], cov[0, 0] - cov[1, 1])
        ca, sa = math.cos(ang), math.sin(ang)
        rx = d[:, 0] * ca + d[:, 1] * sa
        ry = -d[:, 0] * sa + d[:, 1] * ca
        x0, y0 = rx.min(), ry.min()
        rx -= x0
        ry -= y0
        loop_xy[loops, 0] = rx
        loop_xy[loops, 1] = ry
        loop_isl[loops] = k
        rects.append((float(rx.max()), float(ry.max())))
    return loop_xy, loop_isl, rects


def shelf_pack(sizes, n):
    """First-fit-decreasing-height shelf packing of (w, h) pixel rectangles (already padded) into an n x n square.
    Rectangles may be rotated by 90 degrees (the result says which). Returns [(x, y, rotated)] or None when they do not fit."""
    items = []
    for i, (w, h) in enumerate(sizes):
        rot = h > w
        items.append((max(w, h), min(w, h), i, rot))        # landscape
    items.sort(key=lambda t: (-t[1], -t[0], t[2]))
    shelves = []            # [y, height, x_used]
    out = [None] * len(sizes)
    ytop = 0
    for w, h, i, rot in items:
        if w > n or h > n:
            return None
        placed = False
        for sh in shelves:
            if h <= sh[1] and sh[2] + w <= n:
                out[i] = (sh[2], sh[0], rot)
                sh[2] += w
                placed = True
                break
        if not placed:
            if ytop + h > n:
                return None
            shelves.append([ytop, h, w])
            out[i] = (0, ytop, rot)
            ytop += h
    return out


def pack(rects, n, max_ppm):
    """Largest uniform texel density (pixels per metre, at most max_ppm) at which all island rectangles fit the n x n atlas."""
    def sizes_at(d):
        return [(int(math.ceil(w * d)) + 1 + 2 * PAD, int(math.ceil(h * d)) + 1 + 2 * PAD) for (w, h) in rects]

    lo, hi = 20.0, float(max_ppm)
    best = None
    if shelf_pack(sizes_at(hi), n) is not None:
        return hi, shelf_pack(sizes_at(hi), n), sizes_at(hi)
    for _ in range(16):
        mid = (lo + hi) * 0.5
        r = shelf_pack(sizes_at(mid), n)
        if r is None:
            hi = mid
        else:
            lo, best = mid, r
    if best is None:
        raise RuntimeError("atlas too small even at %.0f px/m" % lo)
    return lo, best, sizes_at(lo)


def assign_uvs(g, loop_xy, loop_isl, rects, placement, ppm):
    """Pixel coordinates (x right, y down) of every loop of the packed islands. Island coordinates are (a right, b up); a rotated
    island (the packer turns portrait rectangles to landscape) is rotated by 90 degrees, never mirrored."""
    px = np.zeros((g.n_loops, 2), np.float64)
    has = loop_isl >= 0
    k = loop_isl[has]
    a = loop_xy[has, 0]
    b = loop_xy[has, 1]
    wm = np.array([r[0] for r in rects])[k]
    hm = np.array([r[1] for r in rects])[k]
    ox = np.array([p[0] for p in placement], np.float64)[k]
    oy = np.array([p[1] for p in placement], np.float64)[k]
    rot = np.array([p[2] for p in placement], bool)[k]
    x = np.where(rot, ox + PAD + (hm - b) * ppm, ox + PAD + a * ppm)
    y = np.where(rot, oy + PAD + (wm - a) * ppm, oy + PAD + (hm - b) * ppm)
    px[has, 0] = x
    px[has, 1] = y
    return px


# ------------------------------------------------------------------ rasterisation
def rasterize(g, loop_px, tri_mask, n):
    tri_id = np.full((n, n), -1, np.int32)
    bary = np.zeros((n, n, 3), np.float32)
    for t in np.nonzero(tri_mask)[0]:
        uv = loop_px[g.tri_l[t]]
        x0 = max(int(math.floor(uv[:, 0].min())), 0)
        x1 = min(int(math.ceil(uv[:, 0].max())), n - 1)
        y0 = max(int(math.floor(uv[:, 1].min())), 0)
        y1 = min(int(math.ceil(uv[:, 1].max())), n - 1)
        xs = np.arange(x0, x1 + 1) + 0.5
        ys = np.arange(y0, y1 + 1) + 0.5
        X, Y = np.meshgrid(xs, ys)
        (ax, ay), (bx, by), (cx, cy) = uv
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-9:
            continue
        w0 = ((by - cy) * (X - cx) + (cx - bx) * (Y - cy)) / den
        w1 = ((cy - ay) * (X - cx) + (ax - cx) * (Y - cy)) / den
        w2 = 1.0 - w0 - w1
        m = (w0 >= -0.02) & (w1 >= -0.02) & (w2 >= -0.02)
        if not m.any():
            # sub-texel triangle: claim the texel that holds its centre
            cxp = int(min(max((ax + bx + cx) / 3.0, 0), n - 1))
            cyp = int(min(max((ay + by + cy) / 3.0, 0), n - 1))
            tri_id[cyp, cxp] = t
            bary[cyp, cxp] = (1 / 3, 1 / 3, 1 / 3)
            continue
        yy, xx = np.nonzero(m)
        tri_id[yy + y0, xx + x0] = t
        bary[yy + y0, xx + x0, 0] = w0[yy, xx]
        bary[yy + y0, xx + x0, 1] = w1[yy, xx]
        bary[yy + y0, xx + x0, 2] = w2[yy, xx]
    return tri_id, bary


def tri_tangents(g, loop_px, n):
    """Per-triangle tangent (direction of increasing u, image x) and handedness, from positions and pixel coordinates."""
    p = g.tri_p
    uv = loop_px[g.tri_l]
    e1, e2 = p[:, 1] - p[:, 0], p[:, 2] - p[:, 0]
    du1, dv1 = uv[:, 1, 0] - uv[:, 0, 0], -(uv[:, 1, 1] - uv[:, 0, 1])      # v up = image y down inverted
    du2, dv2 = uv[:, 2, 0] - uv[:, 0, 0], -(uv[:, 2, 1] - uv[:, 0, 1])
    det = du1 * dv2 - du2 * dv1
    det = np.where(np.abs(det) < 1e-12, 1e-12, det)
    r = 1.0 / det
    T = (e1 * dv2[:, None] - e2 * dv1[:, None]) * r[:, None]
    B = (e2 * du1[:, None] - e1 * du2[:, None]) * r[:, None]
    return T, B


# ------------------------------------------------------------------ occlusion and crease distances
def texel_ao(P, N, T, tree, isl, ys, xs, n, samples, dist, strength, block=4):
    """Ambient occlusion by ray casting on a coarse grid (one sample per block x block texels and island), smoothed per island."""
    m = len(P)
    bid = ((ys // block) * (n // block + 1) + (xs // block)).astype(np.int64)
    key = bid * 4096 + (isl % 4096)
    _, first, inverse = np.unique(key, return_index=True, return_inverse=True)
    reps = first
    dirs = []
    golden = math.pi * (3.0 - math.sqrt(5.0))
    for i in range(samples):
        z = math.sqrt((i + 0.5) / samples)
        r = math.sqrt(max(0.0, 1.0 - z * z))
        dirs.append((r * math.cos(i * golden), r * math.sin(i * golden), z))
    ao_rep = np.ones(len(reps), np.float32)
    for ri, ti in enumerate(reps):
        nn = N[ti]
        tt = T[ti] - nn * float(np.dot(T[ti], nn))
        ln = float(np.linalg.norm(tt))
        if ln < 1e-6:
            tt = np.cross(nn, (0.0, 0.0, 1.0) if abs(nn[2]) < 0.9 else (1.0, 0.0, 0.0))
            ln = float(np.linalg.norm(tt))
        tt = tt / ln
        bb = np.cross(nn, tt)
        org = Vector(P[ti] + nn * 0.004)
        hit = 0.0
        for dx, dy, dz in dirs:
            w = tt * dx + bb * dy + nn * dz
            res = tree.ray_cast(org, Vector(w), dist)
            if res[0] is not None:
                hit += math.sqrt(max(0.0, 1.0 - res[3] / dist))
        ao_rep[ri] = 1.0 - strength * hit / samples
    ao = ao_rep[inverse].astype(np.float32)
    return ao


def smooth_by_island(img, isl_img, valid, passes=2, radius=3):
    """Masked box blur that never mixes texels of different islands."""
    out = img.copy()
    for _ in range(passes):
        acc = np.zeros_like(out)
        wsum = np.zeros(out.shape[:2] if out.ndim == 2 else out.shape[:2], np.float32)
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                sh = np.roll(np.roll(out, dy, 0), dx, 1)
                si = np.roll(np.roll(isl_img, dy, 0), dx, 1)
                w = (si == isl_img) & valid
                acc += np.where(w[..., None], sh, 0.0) if out.ndim == 3 else np.where(w, sh, 0.0)
                wsum += w
        wsum = np.maximum(wsum, 1.0)
        out = np.where(valid[..., None], acc / wsum[..., None], out) if out.ndim == 3 else np.where(valid, acc / wsum, out)
    return out


def crease_distances(g, tri_of_texel, P):
    """Distance from each texel to the nearest convex and concave crease edge of its own face (metres, 9 = none)."""
    m = len(P)
    cx = np.full(m, 9.0, np.float32)
    cc = np.full(m, 9.0, np.float32)
    face = g.tri_f[tri_of_texel]
    order = np.argsort(face, kind="stable")
    fs = face[order]
    per_face = {}
    for k in range(len(g.seg_a)):
        per_face.setdefault(int(g.seg_f1[k]), []).append(k)
        if g.seg_f2[k] >= 0:
            per_face.setdefault(int(g.seg_f2[k]), []).append(k)
    for f, segs in per_face.items():
        lo = np.searchsorted(fs, f)
        hi = np.searchsorted(fs, f, side="right")
        if hi <= lo:
            continue
        ti = order[lo:hi]
        pp = P[ti]
        for k in segs:
            a, b = g.seg_a[k], g.seg_b[k]
            ab = b - a
            t = np.clip(((pp - a) @ ab) / (ab @ ab + 1e-12), 0.0, 1.0)
            d = np.linalg.norm(pp - (a + t[:, None] * ab), axis=1)
            if g.seg_cv[k]:
                cx[ti] = np.minimum(cx[ti], d)
            else:
                cc[ti] = np.minimum(cc[ti], d)
    return cx, cc


# ------------------------------------------------------------------ output helpers
def dilate(imgs, valid, iters):
    """Copy the nearest valid texel outwards (padding), one texel per iteration. imgs: list of (H, W, C) float arrays, modified in place."""
    valid = valid.copy()
    dirs = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)]
    for _ in range(iters):
        grown = valid.copy()
        for dy, dx in dirs:
            take = (~grown) & np.roll(np.roll(valid, dy, 0), dx, 1)
            if not take.any():
                continue
            for im in imgs:
                im[take] = np.roll(np.roll(im, dy, 0), dx, 1)[take]
            grown |= take
        valid = grown
    return valid


def normal_from_height(h, isl_img, valid, texel_m):
    """Tangent-space normal map (OpenGL: +Y up in the image) from a height field in metres. Gradients never cross islands."""
    def nb(dy, dx):
        sh = np.roll(np.roll(h, dy, 0), dx, 1)
        ok = (np.roll(np.roll(isl_img, dy, 0), dx, 1) == isl_img) & valid
        return np.where(ok, sh, h)

    dhdx = (nb(0, -1) - nb(0, 1)) / (2.0 * texel_m)       # roll(-1) brings the right neighbour in
    dhdy = (nb(-1, 0) - nb(1, 0)) / (2.0 * texel_m)       # image y grows downward
    nx = -dhdx
    ny = dhdy
    nz = np.ones_like(nx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / ln, ny / ln, nz / ln], axis=-1)


# ------------------------------------------------------------------ the baker
class BakeResult:
    pass


def bake(name, parts, groups, out_dir, size=1024, decals=(), seed=1, ao_dist=0.3, ao_strength=0.75, ao_samples=20, max_ppm=900.0,
         emit_gain=1.0, jpeg=True, normal_scale=1.0, log=True):
    """Bake the atlas of one surface group set.

    groups: dict group name -> dict(kinds=[...surface kinds baked into it...], base=file prefix of its textures)
    parts:  built helpers.Part objects (their .obj meshes carry slots -> Mat with .kind and .group)
    Returns {group: BakeResult(base, files, ppm, fill)} and writes the UVs into every part's mesh ("UVMap").
    """
    t0 = time.time()
    scale = float(os.environ.get("QT_ATLAS_SCALE", "1"))
    kind_ids = shade.KIND_IDS
    gnames = list(groups.keys())

    def kind_of_slot(part, m):
        mat = part.slots[m]
        gi = gnames.index(mat.group) if mat.group in gnames else -1
        return kind_ids.get(mat.kind, -1), gi

    g = extract(parts, kind_of_slot)
    uv_all = np.zeros((g.n_loops, 2), np.float64)
    results = {}
    for gi, gname in enumerate(gnames):
        gsel = np.nonzero(g.face_group == gi)[0]
        if not len(gsel):
            continue
        n = int(groups[gname].get("size", size) * scale)
        isl, islands = make_islands(g, [gi])
        loop_xy, loop_isl, rects = project_islands(g, isl, islands)
        ppm, placement, sizes = pack(rects, n, max_ppm)
        loop_px = assign_uvs(g, loop_xy, loop_isl, rects, placement, ppm)
        tri_mask = g.face_group[g.tri_f] == gi
        tri_id, bary = rasterize(g, loop_px, tri_mask, n)
        valid = tri_id >= 0
        fill = float(valid.mean())
        ys, xs = np.nonzero(valid)
        tid = tri_id[ys, xs]
        bw = bary[ys, xs].astype(np.float64)
        P = np.einsum("tk,tkc->tc", bw, g.tri_p[tid])
        N = np.einsum("tk,tkc->tc", bw, g.tri_n[tid])
        N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-12
        C = np.einsum("tk,tkc->tc", bw, g.tri_c[tid].astype(np.float64))
        UVp = np.stack([xs + 0.5, ys + 0.5], axis=1)
        Tt, Bt = tri_tangents(g, loop_px, n)
        T = Tt[tid]
        T /= np.linalg.norm(T, axis=1, keepdims=True) + 1e-12
        tri_isl = isl[g.tri_f]
        isl_img = np.full((n, n), -1, np.int32)
        isl_img[ys, xs] = tri_isl[tid]
        kind_img_ids = g.face_kind[g.tri_f[tid]]
        # occlusion against ALL geometry (the other group and the flat parts included)
        verts = g.tri_p.reshape(-1, 3)
        tree = BVHTree.FromPolygons([tuple(v) for v in verts], [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(g.tri_p))], epsilon=0.0)
        ao = texel_ao(P, N, T, tree, tri_isl[tid], ys, xs, n, ao_samples, ao_dist, ao_strength)
        ao_img = np.ones((n, n), np.float32)
        ao_img[ys, xs] = ao
        ao_img = smooth_by_island(ao_img, isl_img, valid, 2, 3)
        ao = ao_img[ys, xs]
        cx, cc = crease_distances(g, tid, P)
        c = shade.Ctx(shade.Noise(seed), P, N, C, ao, cx, cc, UVp, T, ppm)
        for kname, kid in kind_ids.items():
            sel = np.nonzero(kind_img_ids == kid)[0]
            if len(sel):
                shade.KINDS[kname](c, sel)
        shade.apply_decals(c, decals, kind_img_ids)
        # assemble images
        alb = np.zeros((n, n, 3), np.float32)
        orm = np.zeros((n, n, 3), np.float32)
        emi = np.zeros((n, n, 3), np.float32)
        hgt = np.zeros((n, n), np.float32)
        alb[ys, xs] = c.alb
        orm[ys, xs, 0] = 0.25 + 0.75 * ao
        orm[ys, xs, 1] = c.rough
        orm[ys, xs, 2] = c.metal
        emi[ys, xs] = c.emit * emit_gain
        hgt[ys, xs] = c.height * normal_scale
        nrm = normal_from_height(hgt, isl_img, valid, 1.0 / ppm)
        # tangent-space normal: perturbation only (the baked surface normal is the mesh normal), so it is (nx, ny, nz) directly
        nrm_img = (nrm * 0.5 + 0.5)
        neutral_n = np.array([0.5, 0.5, 1.0], np.float32)
        v2 = dilate([alb, orm, emi, nrm_img], valid, PAD + 1)
        alb[~v2] = 0.1
        orm[~v2] = (1.0, 0.8, 0.0)
        nrm_img[~v2] = neutral_n
        base = groups[gname]["base"]
        files = {}
        os.makedirs(out_dir, exist_ok=True)
        a8 = shade.to_srgb(alb) * 255.0
        o8 = orm * 255.0
        n8 = nrm_img * 255.0
        e8 = shade.to_srgb(emi) * 255.0
        ext = "jpg" if jpeg else "png"
        for suffix, arr, kind_ext in (("albedo", a8, ext), ("orm", o8, ext), ("normal", n8, "png")):
            path = os.path.join(out_dir, "%s_%s.%s" % (base, suffix, kind_ext))
            if kind_ext == "jpg":
                write_jpg(path, arr)
            else:
                write_png(path, arr)
            files[suffix] = path
        other = "png" if ext == "jpg" else "jpg"
        for suffix in ("albedo", "orm"):               # never leave a stale file of the other format next to the new one
            stale = os.path.join(out_dir, "%s_%s.%s" % (base, suffix, other))
            if os.path.isfile(stale):
                os.remove(stale)
        has_emit = bool((emi > 0.0005).any())
        path = os.path.join(out_dir, "%s_emit.png" % base)
        if has_emit:
            write_png(path, e8)
            files["emit"] = path
        elif os.path.isfile(path):
            os.remove(path)
        res = BakeResult()
        res.base, res.files, res.ppm, res.fill, res.n = base, files, ppm, fill, n
        res.has_emit, res.ext = has_emit, ext
        res.valid, res.ao = valid, ao_img
        results[gname] = res
        sel_loops = loop_isl >= 0                  # Blender UV space: u right, v up
        uv_all[sel_loops, 0] = loop_px[sel_loops, 0] / n
        uv_all[sel_loops, 1] = 1.0 - loop_px[sel_loops, 1] / n
        if log:
            print("  atlas %-8s %-22s %dx%d  %5.1f px/m (%.1f mm/px)  fill %.0f%%  islands %d  tris %d  (%.1fs)" % (
                gname, base, n, n, ppm, 1000.0 / ppm, fill * 100.0, len(islands), int(tri_mask.sum()), time.time() - t0))
    for pi, part in enumerate(parts):                  # faces of the flat group have no texture: their UVs stay at the origin
        base_l, nl = g.part_loops[pi]
        part.obj.data.uv_layers["UVMap"].data.foreach_set("uv", uv_all[base_l:base_l + nl].reshape(-1))
    return results


# ------------------------------------------------------------------ Blender materials for the baked textures
_GLTF_GROUP = None


def _gltf_output_group():
    global _GLTF_GROUP
    if _GLTF_GROUP is None or _GLTF_GROUP.name not in bpy.data.node_groups:
        grp = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        grp.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
        _GLTF_GROUP = grp
    return _GLTF_GROUP


def reset():
    global _GLTF_GROUP
    _GLTF_GROUP = None


def make_baked_material(name, base, ext, has_emit, emit_strength=2.0, color=(1.0, 1.0, 1.0)):
    """Principled material wired to the baked <base>_albedo/_orm/_normal(/_emit) images the way the glTF exporter expects.
    The images are 4x4 stand-ins: glbtool.externalize_images swaps them for relative URIs of the real files in assets/textures."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    m.use_backface_culling = True

    def img(suffix, cs):
        im = bpy.data.images.new("%s_%s" % (base, suffix), 4, 4)
        im.colorspace_settings.name = cs
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = im
        return node

    ta = img("albedo", "sRGB")
    if tuple(color) != (1.0, 1.0, 1.0):
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs["B"].default_value = (color[0], color[1], color[2], 1.0)
        nt.links.new(ta.outputs["Color"], mix.inputs["A"])
        nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    else:
        nt.links.new(ta.outputs["Color"], bsdf.inputs["Base Color"])
    to = img("orm", "Non-Color")
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(to.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    grp = nt.nodes.new("ShaderNodeGroup")
    grp.node_tree = _gltf_output_group()
    nt.links.new(sep.outputs["Red"], grp.inputs["Occlusion"])
    tn = img("normal", "Non-Color")
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if has_emit:
        te = img("emit", "sRGB")
        nt.links.new(te.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    else:
        bsdf.inputs["Emission Strength"].default_value = 0.0
    return m
