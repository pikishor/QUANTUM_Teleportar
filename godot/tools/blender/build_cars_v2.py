#!/usr/bin/env python3
"""Cars v2: build the high-detail car models (assets/models/cv2_<name>.glb) with the carv2 generator.

  .venv-tools/bin/python tools/blender/build_cars_v2.py [name ...] [--preview /tmp/sheet.png] [--out DIR] [--no-ao]

Every GLB holds: Body (LOD0, surfaces Paint / Details / Glass), Body_LOD1, Body_LOD2 (one surface "Lod"), WheelFL/FR/RL/RR (a node at the axle with a Mesh and a
Mesh_LOD1 child), and anchor empties (PlateF, PlateR, Driver, FxEngine, FxExhaust, ...). Nose = -Z in Godot (+Y here), 1 unit = 1 m, ground at y = 0.
"""
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402

from carv2 import archetypes, body, export, features, interior, kit, near, wheels  # noqa: E402
from carv2.kit import D_FABRIC, D_HEAD, D_PLASTIC, D_TAIL, D_UNDER, Mesh  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.environ.get("QT_MODELS_DIR", os.path.join(ROOT, "assets", "models"))

LABEL_STYLE = {                       # face labels of the body shell that live in the Details surface: (class, colour)
    "Under": (D_UNDER, (0.010, 0.010, 0.012)),
    "Trim": (D_PLASTIC, (0.020, 0.020, 0.022)),
}
LOD_TAG = {"Paint": 0.0, "Glass": 0.25, "Under": 0.55, "Trim": 0.55}


def surfaces_of(mesh, thr=38.0):
    """finalize() a Mesh and fold its face labels into the three car surfaces: Paint, Glass, Details."""
    g = kit.finalize(mesh, thr)
    out = {}
    for label, d in g.items():
        surf = "Details" if label in LABEL_STYLE else label
        d = {k: v.copy() for k, v in d.items()}
        if label in LABEL_STYLE:
            code, col = LABEL_STYLE[label]
            d["U"][:, 0] = code
            d["C"][:, :3] = col
        out = kit.merge_groups([out, {surf: d}])
    return out


def wheel_positions(d):
    if not d.get("arches", True):
        return {}
    tx = d["track"] * 0.5
    return {"WheelFL": (-tx, d["axle_f"], d["R"]), "WheelFR": (tx, d["axle_f"], d["R"]), "WheelRL": (-tx, d["axle_r"], d.get("R_r", d["R"])),
            "WheelRR": (tx, d["axle_r"], d.get("R_r", d["R"]))}


def lod2_single(groups, wheel_meshes):
    """One surface 'Lod' for the far LOD: uv.x = surface tag (0 paint, 0.25 glass, 0.45 tyre, 0.55 trim, 0.65 rim, 0.8 head, 1.0 tail), same scheme as the near traffic mesh."""
    parts = []
    for surf, g in groups.items():
        g = {k: v.copy() for k, v in g.items()}
        if surf == "Paint":
            g["U"][:, 0] = 0.0
        elif surf == "Glass":
            g["U"][:, 0] = 0.25
        elif surf == "Details":
            code = g["U"][:, 0].round().astype(int)
            tag = np.full(len(code), 0.55)
            tag[code == D_HEAD] = 0.8
            tag[code == D_TAIL] = 1.0
            tag[code == kit.D_IND] = 0.8
            tag[code == kit.D_CHROME] = 0.65
            g["U"][:, 0] = tag
            g["U"][:, 1] = 0.0
        g["C"][:, :3] = 1.0
        parts.append({"Lod": g})
    for wg in wheel_meshes:
        g = {k: v.copy() for k, v in wg["Wheel"].items()}
        code = g["U2"][:, 0].round().astype(int)
        g["U"] = np.column_stack([np.where(code == wheels.WC_TYRE, 0.45, 0.65), np.zeros(len(code))])
        g["C"][:, :3] = 1.0
        parts.append({"Lod": g})
    return kit.merge_groups(parts)


def door_meshes(mesh):
    """The front doors of the (welded) body shell as separate meshes: {part id: (hinge point, Mesh of the door skin + glass + a dark inner panel in model space)}."""
    out = {}
    P = mesh.P
    for part in (5, 6):
        sel = np.where(mesh.Fp == part)[0]
        if len(sel) < 4:
            continue
        F = mesh.F[sel]
        used = np.unique(F.ravel())
        remap = {int(v): i for i, v in enumerate(used)}
        F2 = np.array([[remap[int(v)] for v in f] for f in F])
        names = [mesh.mats[i] for i in mesh.Fm[sel]]
        Pd = P[used]
        yf = Pd[:, 1].max()
        front = Pd[Pd[:, 1] > yf - 0.02]
        hinge = np.array([front[:, 0].mean(), yf, 0.5 * (Pd[:, 2].min() + Pd[:, 2].max())])
        sgn = 1.0 if part == 6 else -1.0
        skin = Mesh().add(Pd, F2, None, fmat=names)
        inner = Mesh().add(Pd - np.array([sgn * 0.07, 0.0, 0.0]), F2[:, ::-1].copy(), "Under")
        skin.add_mesh(inner)
        out[part] = (hinge, skin)
    return out


WHEEL_ORDER = ("WheelFL", "WheelFR", "WheelRL", "WheelRR")


def merged_wheels(d, wp, wheel_lod_groups, wm_rear, lod):
    """The four wheels of LOD `lod` as ONE group in the format of the Details surface (finalize() arrays): the left wheels turned round, every vertex in model space.
    uv0 = (20 + wheel part class, tread v), uv2 = (tread u, 1 - wheel id 1 .. 4: the importer does not un-flip V), vertex colour = the albedo of the wheel part. The Details shader
    (car_details.gdshader) rolls and steers the vertices about the wheel centres, so the four tyres cost no draw call of their own."""
    out = []
    for wid, nm in enumerate(WHEEL_ORDER, start=1):
        if nm not in wp:
            continue
        x, y, z = wp[nm]
        rear = nm[5] == "R"
        g = (wm_rear[lod][1] if (rear and wm_rear) else wheel_lod_groups[lod][1])["Wheel"]
        left = x < 0
        R = kit.rot_z(math.pi) if left else np.eye(4)
        V = kit.apply(kit.trans(x, y, z) @ R, g["V"])
        N = g["N"] @ R[:3, :3].T
        cls = g["U2"][:, 0].round().astype(int)
        U = np.column_stack([20.0 + cls, g["U"][:, 1]])
        U2 = np.column_stack([g["U"][:, 0], np.full(len(V), 1.0 - wid)])
        out.append(dict(V=V, N=N, C=g["C"].copy(), U=U, U2=U2, I=g["I"].copy()))
    return kit.merge_groups([{"Details": o} for o in out]) if out else {}


def build(name, out_dir=OUT_DIR, preview=None, ao=True, lods=(0, 1, 2)):
    t0 = time.time()
    d = archetypes.get(name)
    export.reset()
    root = None                      # no root empty: the importer's own root (named after the file) holds Body, the wheels and the anchors directly
    objs = []
    wp = wheel_positions(d)
    wd = d.get("wheel", {})
    wr = dict(design=wd.get("design", "five"), rim_col=wd.get("rim_col", (0.62, 0.64, 0.68)))
    stats = {}
    wheel_lod_groups = {}
    for lod in (0, 1, 2):
        wm = wheels.wheel_mesh(d["R"], d["tyre_w"], lod=lod, **wr)
        wheel_lod_groups[lod] = (wm, kit.finalize(wm, 50.0))
    wm_rear = None
    if "R_r" in d or "tyre_w_r" in d:
        R2 = d.get("R_r", d["R"])
        W2 = d.get("tyre_w_r", d["tyre_w"])
        wm_rear = {lod: (wheels.wheel_mesh(R2, W2, lod=lod, **wr),) for lod in (0, 1, 2)}
        wm_rear = {lod: (m[0], kit.finalize(m[0], 50.0)) for lod, m in wm_rear.items()}
    # wheel nodes: empty transform nodes at the axles (the wheels themselves are part of the Details surface of Body and Body_LOD1, one draw call fewer per tyre; see merged_wheels)
    for nm, (x, y, z) in wp.items():
        objs.append(export.empty(nm, (x, y, z), parent=root))
    # wheel meshes in model space for the occlusion bake and the far LOD
    def placed_wheels(lod):
        out = []
        for nm, (x, y, z) in wp.items():
            end = "front" if nm[5] == "F" else "rear"
            wm = (wm_rear or {}).get(lod, wheel_lod_groups[lod])[0] if end == "rear" and wm_rear else wheel_lod_groups[lod][0]
            xf = kit.trans(x, y, z) @ (kit.rot_z(math.pi) if x < 0 else np.eye(4))
            out.append(wm.xformed(xf))
        return out
    # body LODs
    anchors = {}
    for lod in lods:
        mesh, info = body.build_body(d, lod)
        mesh = mesh.weld()
        surf = kit.Surface(mesh)
        det = features.Detailer(d, surf, lod)
        d["detail"](det)
        if lod == 0:
            anchors = det.anchors
        parts = [surfaces_of(mesh, 38.0)]
        if lod == 0 and d.get("fx", {}).get("doors"):
            for part, (hinge, dmesh) in door_meshes(mesh).items():
                dg = surfaces_of(dmesh, 38.0)
                if "Paint" in dg and ao:
                    kit.bake_vertex_ao({"Paint": dg["Paint"]}, [mesh] + placed_wheels(0), rays=14, dist=0.9, strength=0.9)
                for g in dg.values():
                    g["V"] = g["V"] - hinge
                side = "R" if part == 6 else "L"
                node = export.empty("Door" + side, tuple(hinge), parent=None)
                objs.append(node)
                objs.append(export.mesh_object("Door%s_Mesh" % side, dg, ["Paint", "Details", "Glass"], parent=node))
        dm = det.mesh
        if lod < 2 and len(dm.F):
            parts.append(surfaces_of(dm, 38.0))
        if lod == 0 and not d.get("no_cabin"):                # the interior is only seen through the glass of the near car
            cab = d.get("cabin_fn", interior.cabin)(d, lod)
            parts.append(surfaces_of(cab, 60.0))
            lin = interior.liner(d, info, lod)
            if len(lin.F):
                parts.append(surfaces_of(lin, 60.0))
        if lod == 1 and not d.get("no_cabin"):                # the middle LOD has no cabin, but its glass needs something dark behind it (it showed the street through the windows, a flat grey pane)
            lin = interior.liner(d, info, lod)
            if len(lin.F):
                parts.append(surfaces_of(lin, 60.0))
        if lod == 2:
            parts.append(surfaces_of(dm, 38.0))
        if os.environ.get("QT_CAR_STATS"):
            print("   lod%d parts:" % lod, [(k, kit.group_tris(p_)) for k, p_ in zip(["shell", "details", "cabin", "liner", "?"], parts)])
        groups = kit.merge_groups(parts)
        # paint ambient occlusion (against the shell and the wheels)
        if "Paint" in groups:
            gp = {"Paint": groups["Paint"]}
            if ao and lod < 2:
                occ = [mesh] + placed_wheels(lod)
                kit.bake_vertex_ao(gp, occ, rays=18 if lod == 0 else 10, dist=0.9, strength=0.9)
            else:
                groups["Paint"]["C"][:, 0] = 1.0
        if lod < 2:
            wgrp = merged_wheels(d, wp, wheel_lod_groups, wm_rear, lod)
            if wgrp:
                groups = kit.merge_groups([groups, wgrp])
        if lod == 2:
            groups = lod2_single(groups, [kit.finalize(w, 50.0) for w in placed_wheels(2)])
        order = ["Paint", "Details", "Glass"] if lod < 2 else ["Lod"]
        ob = export.mesh_object("Body" if lod == 0 else "Body_LOD%d" % lod, groups, order, parent=root)
        objs.append(ob)
        stats[lod] = kit.group_tris(groups)
    # anchors
    for nm, (pos, rot) in anchors.items():
        objs.append(export.empty(nm, pos, parent=root, rot=rot))
    path = os.path.join(out_dir, "cv2_%s.glb" % name)
    if preview:
        for o in objs:
            if o.name.startswith("Body_LOD") or o.name == "Mesh_LOD1":
                o.hide_render = True
        export.preview([o for o in objs if o.type == "MESH"], preview, views=("front3q", "side", "rear3q", "top", "front", "rear"), center=(0, 0, 0.7), dist=d["L"] * 1.55)
        for o in objs:
            o.hide_render = False
    js = export.export_glb(path, objs)
    tris, size, lo, hi, js = export.report(path)
    print("CAR %-9s tris LOD0 %5d LOD1 %5d LOD2 %5d | glb tris(all) %6d size %6.1f KB | bounds x[%.2f,%.2f] y[%.2f,%.2f] z[%.2f,%.2f] (glTF, nose -Z) | %.1fs" % (
        name, stats.get(0, 0), stats.get(1, 0), stats.get(2, 0), tris, size / 1024.0,
        lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], time.time() - t0))
    return path


NEAR_SMOOTH = 22.0


def build_near(name="sedan", out_dir=OUT_DIR):
    """assets/models/cv2_near.glb: the car of the near traffic (scripts/ambient/near_traffic.gd, ONE MultiMesh, shader prop_nearcar.gdshader). One mesh, one surface:
    uv.x = surface tag (0 paint, 0.25 glass, 0.45 tyre, 0.55 trim, 0.65 rim, 0.8 head lamp, 1.0 tail lamp), uv.y of a wheel vertex = z of the wheel centre (Godot axes: nose -Z)."""
    d = archetypes.get(name)
    export.reset()
    wr = dict(design="five", rim_col=(0.62, 0.64, 0.68))
    mesh, info = body.build_body(d, 3, with_glass=True)
    mesh = mesh.weld()
    surf = kit.Surface(mesh)
    det = features.Detailer(d, surf, 2)
    d["detail"](det)
    groups = kit.merge_groups([surfaces_of(mesh, NEAR_SMOOTH), surfaces_of(det.mesh, NEAR_SMOOTH)])      # a crisper shading than the near LODs: the shader adds a blue rim light that a smooth 430 triangle car turns into a glow
    wp = wheel_positions(d)
    wheel_groups = []
    for nm, (x, y, z) in wp.items():
        wm = wheels.wheel_mesh(d["R"], d["tyre_w"], lod=2, **wr)
        xf = kit.trans(x, y, z) @ (kit.rot_z(math.pi) if x < 0 else np.eye(4))
        wg = kit.finalize(wm.xformed(xf), 50.0)
        wheel_groups.append((wg, -y))
    g = lod2_single(groups, [w for w, _ in wheel_groups])
    # wheel vertices: uv.y = the z of the wheel centre in Godot axes (-Y here)
    one = g["Lod"]
    raked = (np.abs(one["U"][:, 0] - 0.25) < 0.01) & (one["N"][:, 1] > 0.12)       # a raked windscreen / rear window seen at a grazing angle would take the shader's blue rim light and look like a pale ghost: dark trim instead
    one["U"][raked, 0] = 0.55
    n_body = sum(len(v["V"]) for k, v in groups.items())
    off = n_body
    for (wg, zc) in wheel_groups:
        cnt = len(wg["Wheel"]["V"])
        one["U"][off:off + cnt, 1] = zc
        off += cnt
    for i in range(len(one["U"])):
        if abs(one["U"][i, 0] - 0.65) < 0.01 and i < n_body:
            one["U"][i, 0] = 0.55                                  # chrome of the body is plain trim here: only wheel verts keep the rim tag
    ob = export.mesh_object("NearCar", g, ["Lod"])
    path = os.path.join(out_dir, "cv2_near.glb")
    export.export_glb(path, [ob])
    tris, size, lo, hi, _js = export.report(path)
    print("NEAR cv2_near tris %d size %.1f KB bounds x[%.2f,%.2f] y[%.2f,%.2f] z[%.2f,%.2f]" % (tris, size / 1024.0, lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))
    return path


def build_near_v2(out_dir=OUT_DIR):
    """Second pass: assets/models/cv2_near_hi.glb (the near car of the first 22 m, two bodies + wheels + extras, about 1.3k triangles) and assets/models/cv2_near.glb (the far near car, about 400),
    plus assets/shaders/prop_nearcar_tables.gdshaderinc (the anchors the shaders re-proportion them with). See carv2/near.py."""
    paths = []
    for name, fn in (("cv2_near_hi", near.build_hi), ("cv2_near", near.build_lo)):
        g = fn()
        g["C"] = np.ones((len(g["V"]), 4))
        export.reset()
        ob = export.mesh_object("NearCar", {"Near": g}, ["Near"])
        path = os.path.join(out_dir, name + ".glb")
        export.export_glb(path, [ob])
        tris, size, lo, hi, _js = export.report(path)
        print("NEAR %-12s tris %d size %.1f KB bounds x[%.2f,%.2f] y[%.2f,%.2f] z[%.2f,%.2f]" % (name, tris, size / 1024.0, lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))
        paths.append(path)
    inc = os.path.join(ROOT, "assets", "shaders", "prop_nearcar_tables.gdshaderinc")
    with open(inc, "w") as f:
        f.write(near.glsl_tables())
    print("tables ->", inc)
    return paths


def main(argv):
    names = []
    preview = None
    out = OUT_DIR
    ao = True
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--preview":
            preview = argv[i + 1]
            i += 1
        elif a == "--out":
            out = argv[i + 1]
            i += 1
        elif a == "--no-ao":
            ao = False
        elif a == "--near":
            build_near_v2(out)
            return
        elif a == "--near-old":
            build_near("sedan", out)
            return
        else:
            names.append(a)
        i += 1
    if not names:
        names = list(archetypes.ARCHETYPES.keys())
    for n in names:
        pv = preview.replace("%s", n) if preview else None
        build(n, out, pv, ao)


if __name__ == "__main__":
    main(sys.argv[1:])
