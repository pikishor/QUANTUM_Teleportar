"""The cars of the near traffic (round 6, second pass): one HI mesh and one LO mesh, both ONE surface for the MultiMesh of scripts/ambient/near_traffic.gd.

HI  (about 1.3k triangles, drawn within about 22 m of the camera by at most a handful of instances) holds two bodies, the sedan shell (kind family C: sedan, hatch, SUV, taxi,
    sports, pickup, patrol) and the box truck shell (family B: van, box truck, bus, ambulance, delivery), one set of four wheels and a few extras (taxi sign, light bars, spoiler).
    The shader (assets/shaders/prop_nearcar_hi.gdshader) keeps the body the kind needs, hides the rest and re-proportions it with piecewise linear maps of length and height
    (anchors per kind: assets/shaders/prop_nearcar_tables.gdshaderinc, written by this file) so that a hatch, an SUV, a sports car, a pickup, a van, a bus ... have their own wheelbase,
    roof and belt line, and the four wheels are placed by the same tables (rigid, so they stay round).
LO  (about 400 triangles) is the sedan shell alone (assets/shaders/prop_nearcar.gdshader scales it the old way, beyond the HI range).

Both uv sets are exported with V flipped and imported as they are, so every V written here is 1 - the value the shader reads.
Vertex attributes: uv0 = (surface tag, aux): aux = region (0 cab, 1 box) on a body of family B, wheel id + 1 (1 FL, 2 FR, 3 RL, 4 RR) on a wheel vertex;
                   uv2 = (baked ambient occlusion, 1 - part id; the importer flips only the first uv set's V, so the shader reads the part id as is): part 0 sedan shell, 1 box truck shell, 2 taxi sign, 3 light bar (patrol), 4 spoiler, 5 light bar (ambulance), 6 wheel, 7 bed liner.
Surface tags (a float in uv0.x, decoded by thresholds in the shader): 0 paint | 0.25 glass | 0.30 window band (glass on a bus, paint elsewhere) | 0.45 tyre | 0.52 plate |
0.55 dark trim | 0.65 chrome / rim | 0.72 head lamp | 0.78 indicator | 0.84 white lamp | 0.90 siren blue | 0.95 siren red | 1.0 tail lamp.
"""
import math
import os

import numpy as np

from . import archetypes, body, features, kit, wheels
from .kit import (D_BLUE, D_CHROME, D_FABRIC, D_GLOW, D_HEAD, D_IND, D_LEATHER, D_PAINTED, D_PLASTIC, D_PLATE, D_RED, D_REV, D_RUBBER, D_SCREEN, D_SIGN, D_TAIL, D_UNDER,
                  D_WHITE_LAMP, Mesh)

T_PAINT, T_GLASS, T_BAND, T_TYRE, T_PLATE, T_TRIM, T_CHROME, T_HEAD, T_IND, T_WHITE, T_SIREN_B, T_SIREN_R, T_TAIL = 0.0, 0.25, 0.30, 0.45, 0.52, 0.55, 0.65, 0.72, 0.78, 0.84, 0.90, 0.95, 1.0
P_C, P_B, P_SIGN, P_BAR, P_SPOILER, P_BAR_B, P_WHEEL, P_BED = range(8)

CODE_TAG = {D_PLASTIC: T_TRIM, D_CHROME: T_CHROME, D_FABRIC: T_TRIM, D_LEATHER: T_TRIM, D_HEAD: T_HEAD, D_TAIL: T_TAIL, D_IND: T_IND, D_REV: T_WHITE, D_BLUE: T_SIREN_B,
            D_RED: T_SIREN_R, D_UNDER: T_TRIM, D_PAINTED: T_PAINT, D_PLATE: T_PLATE, D_SCREEN: T_TRIM, D_SIGN: T_WHITE, D_RUBBER: T_TRIM, D_GLOW: T_WHITE, D_WHITE_LAMP: T_WHITE}

HI_LOD_C = dict(th=[90, 60, 28, 0], tl=[1.0], step=0.75, arch=[-90, 0, 90], win=(1, 3), glass_top=1, cap=2, under=False)           # the sedan shell of the HI mesh (about 450 triangles)
HI_LOD_B = dict(th=[90, 78, 42, 0], tl=[1.0], step=1.2, arch=[-90, 0, 90], win=(1, 3), glass_top=1, cap=1, under=False)                # the box truck shell (about 250)
LO_LOD = dict(th=[90, 52, 0], tl=[1.0], step=1.3, arch=[], win=(1, 2), glass_top=1, cap=1, under=False)
body.LODS[4] = HI_LOD_C
body.LODS[5] = LO_LOD
body.LODS[6] = HI_LOD_B

# the near kinds (scripts/ambient/near_traffic.gd KINDS order) and the archetype each one is built from
KINDS = ["sedan", "compact", "suv", "van", "taxi", "sport", "pickup", "truck", "bus", "interceptor", "ambulance", "delivery"]
ARCH = {"sedan": "sedan", "compact": "hatch", "suv": "suv", "van": "van", "taxi": "taxi", "sport": "sports", "pickup": "pickup", "truck": "boxtruck", "bus": "bus", "interceptor": "patrol",
        "ambulance": "ambulance", "delivery": "delivery"}
FAMILY_B = ("van", "truck", "bus", "ambulance", "delivery")
STEP_Y = {"truck": 1.40, "delivery": 1.20, "van": None, "ambulance": 0.20, "bus": None}           # where the cab ends (Blender y of the step in the roof line)
CAB_LEN = {"van": 1.9, "bus": 2.0}                                                              # a variant with no step: the length of its front section


# ------------------------------------------------------------------------------------------------------------------------------ tables
def _belt_at(d, y):
    b = d["belt"]
    if isinstance(b, (list, tuple)):
        ks = sorted(b)
        return float(np.interp(y, [k[0] for k in ks], [k[1] for k in ks]))
    return float(b)


def _ground_to_belt(d):
    ws = d.get("ws", (0.5, 0.0))
    return _belt_at(d, 0.5 * (ws[0] + ws[1]) - 0.1) if isinstance(d["belt"], (list, tuple)) else float(d["belt"])


def table_c(kind):
    """Anchors of a family C kind: nose z, front axle z, rear axle z, tail z (Godot axes, nose negative), belt height, roof height, width scale, wheel radius, half track."""
    d = archetypes.get(ARCH[kind])
    roof = max(k[1] for k in d["top"])
    return [-d["L"] * 0.5, -d["axle_f"], -d["axle_r"], d["L"] * 0.5, _ground_to_belt(d), roof, d["W"] / 1.85, d["R"], d["track"] * 0.5]


def table_b(kind):
    """Anchors of a family B kind: nose z, front axle z, step z (the cab ends), rear axle z, tail z, belt, cab roof, box roof, width scale (to 2.2 m), wheel radius, half track."""
    d = archetypes.get(ARCH[kind])
    L = d["L"]
    roof_b = max(k[1] for k in d["top"])
    if kind in STEP_Y and STEP_Y[kind] is not None:
        step = -STEP_Y[kind]
        cab_roof = max(k[1] for k in d["top"] if k[0] > STEP_Y[kind] + 0.05)
        if kind == "ambulance":
            cab_roof = 2.1
    else:
        step = -L * 0.5 + CAB_LEN[kind]
        cab_roof = roof_b
    return [-L * 0.5, -d["axle_f"], step, -d["axle_r"], L * 0.5, _belt_at(d, 0.0) if isinstance(d["belt"], (list, tuple)) else float(d["belt"]), cab_roof, roof_b, d["W"] / 2.2, d["R"], d["track"] * 0.5]


def glsl_tables():
    base_c = table_c("sedan")
    base_b = table_b("truck")
    lines = ["// Written by tools/blender/carv2/near.py (python -I tools/blender/build_cars_v2.py --near): the anchors of the near traffic bodies. Do not edit by hand.",
             "// Family C row: nose z, front axle z, rear axle z, tail z | belt height, roof height, width scale, wheel radius, half track.",
             "// Family B row: nose z, front axle z, step z, rear axle z, tail z | belt height, cab roof, box roof, width scale, wheel radius, half track.", ""]

    def f(v):
        return "%.4f" % v
    lines.append("const float C_BASE[9] = float[9](%s);" % ", ".join(f(v) for v in base_c))
    lines.append("const float B_BASE[11] = float[11](%s);" % ", ".join(f(v) for v in base_b))
    rows = []
    for i, k in enumerate(KINDS):
        rows.append(table_c(k) if k not in FAMILY_B else table_c("sedan"))
    lines.append("const float C_TAB[%d] = float[%d](" % (9 * len(KINDS), 9 * len(KINDS)))
    lines.append(",\n".join("\t" + ", ".join(f(v) for v in r) + "  /* %s */" % KINDS[i] for i, r in enumerate(rows)).replace("/* %s */" % KINDS[-1], "/* %s */" % KINDS[-1]))
    lines.append(");")
    rowsb = []
    for i, k in enumerate(KINDS):
        rowsb.append(table_b(k) if k in FAMILY_B else table_b("truck"))
    lines.append("const float B_TAB[%d] = float[%d](" % (11 * len(KINDS), 11 * len(KINDS)))
    lines.append(",\n".join("\t" + ", ".join(f(v) for v in r) + "  /* %s */" % KINDS[i] for i, r in enumerate(rowsb)))
    lines.append(");")
    lines.append("const int FAMILY_B_MASK = %d;           // bit k set = kind k is built on the box truck body" % sum(1 << i for i, k in enumerate(KINDS) if k in FAMILY_B))
    wc = [(sx * base_c[8], base_c[7], z) for sx, z in ((-1, base_c[1]), (1, base_c[1]), (-1, base_c[2]), (1, base_c[2]))]
    lines.append("const vec3 WHEEL_BASE[4] = vec3[4](%s);   // FL FR RL RR of the base wheels (Godot axes)" % ", ".join("vec3(%s, %s, %s)" % (f(a), f(b), f(c)) for a, b, c in wc))
    lines.append("const float WHEEL_R_BASE = %s;" % f(base_c[7]))
    return "\n".join(lines) + "\n"


# ------------------------------------------------------------------------------------------------------------------------------ parts
def near_wheel(R, W, seg=12, hi=True, rim_ratio=0.64):
    """A light wheel on the X axis, outer face +X: a tyre band with a sloped outer sidewall and a lid; the spokes are painted by the shader from the radial uv2 (HI) or not at all (LO)."""
    r_rim = R * rim_ratio
    hw = W * 0.5
    if hi:
        prof = [(hw * 0.72, r_rim), (hw * 0.93, R * 0.975), (-hw * 0.93, R * 0.975)]
    else:
        prof = [(hw * 0.95, R * 0.96), (-hw * 0.95, R * 0.96)]
    tyre = kit.revolve(prof, seg=seg, axis="x", mat="Wheel", col=(1, 1, 1, 1), seam=False)
    tyre = wheels._orient_radial(tyre, outward=True, check_radius=R * 0.96)
    tyre.style(code=T_TYRE)
    m = Mesh()
    m.add_mesh(tyre)
    x_face = hw * 0.72 if hi else hw * 0.95
    r_lid = r_rim * 0.98 if hi else R * 0.62
    lid = kit.poly_fan([(x_face, r_lid * math.cos(2 * math.pi * k / seg), r_lid * math.sin(2 * math.pi * k / seg)) for k in range(seg)], "Wheel", col=(1, 1, 1, 1))
    lid = wheels._orient_axis(lid, +1.0)
    lid.style(code=T_CHROME)
    m.add_mesh(lid)
    return m


def _plate_patches(det, d):
    f = d["fx"]
    for plane, key, zf in (("rear", "plate_r", det.fz("rear", f.get("plate_r", 0.38))), ("front", "plate_f", det.fz("front", f.get("plate_f", 0.26)))):
        if key not in f:
            continue
        det.patch([(-0.30, zf - 0.09), (0.30, zf - 0.09), (0.30, zf + 0.09), (-0.30, zf + 0.09)], plane, D_PLATE, (0.82, 0.82, 0.78), offset=0.004, rings=1)


def _near_fx(d):
    keep = ("head", "grille", "tail", "rev", "plate_r", "plate_f", "rect_lamps", "sweep", "tsweep", "chrome")
    d2 = dict(d)
    d2["fx"] = {k: v for k, v in d["fx"].items() if k in keep}
    return d2


def _detail(d, mesh, lod=1):
    surf = kit.Surface(mesh)
    d2 = _near_fx(d)
    det = features.Detailer(d2, surf, lod)
    # plates are their own class here; the lamps, the grille and the mirrors come from the archetype's table
    f2 = dict(d2["fx"])
    plate_keys = {k: f2.pop(k) for k in ("plate_r", "plate_f") if k in f2}
    d2["fx"] = f2
    archetypes.car_details(det)
    d2["fx"] = dict(f2, **plate_keys)
    _plate_patches(det, d2)
    if "mirror" in d["fx"]:                                            # two plain boxes: the rounded housings of the full car are 216 triangles
        y, z, off = d["fx"]["mirror"]
        a = d["W"] * 0.5
        for sgn in (1.0, -1.0):
            hou = kit.box((sgn * (a + off * 0.6), y, z), (0.10, 0.17, 0.10), "Details")
            hou.style(D_PAINTED, (0.5, 0.5, 0.5))
            det.mesh.add_mesh(hou)
    return det


def _to_near(groups, tag_of_code=True, part=P_C, region=0.0):
    """finalize() groups of Paint / Details / Glass -> one dict of arrays with the near tags (uv0.x), the region (uv0.y) and the part (uv2.y)."""
    V, N, U, U2, I = [], [], [], [], []
    off = 0
    for surf in ("Paint", "Details", "Glass", "Wheel"):
        g = groups.get(surf)
        if g is None or len(g["I"]) == 0:
            continue
        u = g["U"].copy()
        if surf == "Paint":
            u[:, 0] = T_PAINT
        elif surf == "Glass":
            u[:, 0] = T_GLASS
        elif surf == "Details":
            code = u[:, 0].round().astype(int)
            u[:, 0] = [CODE_TAG.get(int(c), T_TRIM) for c in code]
        u[:, 1] = 1.0 - region                                                              # the importer does not un-flip V (neither set): the stored value is 1 - value
        u2 = np.zeros((len(u), 2))
        u2[:, 0] = np.clip(g["C"][:, 0], 0.0, 1.0) if surf == "Paint" else 1.0            # only the paint carries the baked occlusion (the other surfaces' colour is their albedo)
        u2[:, 1] = 1.0 - part                                                              # TEXCOORD_1 is not un-flipped by the Godot importer (TEXCOORD_0 is): 1 - part in, part out
        V.append(g["V"])
        N.append(g["N"])
        U.append(u)
        U2.append(u2)
        I.append(g["I"] + off)
        off += len(g["V"])
    return dict(V=np.concatenate(V), N=np.concatenate(N), U=np.concatenate(U), U2=np.concatenate(U2), I=np.concatenate(I))


def _direct(g, tag, part, region=0.0):
    """One finalize() surface that is already one tag (an extra part): uv0 = (tag, region), uv2 = (1, part)."""
    n = len(g["V"])
    return dict(V=g["V"], N=g["N"], U=np.column_stack([np.full(n, tag), np.full(n, 1.0 - region)]), U2=np.column_stack([np.ones(n), np.full(n, 1.0 - float(part))]), I=g["I"])


def _merge(parts):
    out = None
    for p in parts:
        if out is None:
            out = {k: v.copy() for k, v in p.items()}
        else:
            off = len(out["V"])
            for k in ("V", "N", "U", "U2"):
                out[k] = np.concatenate([out[k], p[k]])
            out["I"] = np.concatenate([out["I"], p["I"] + off])
    return out


def _body_part(name, lod, smooth, region_fn=None, extra_fn=None, part=P_C, ao=True, wheel_meshes=()):
    d = archetypes.get(name)
    mesh, info = body.build_body(d, lod, with_glass=True)
    mesh = mesh.weld()
    det = _detail(d, mesh, 1 if lod in (4, 6) else 2)
    groups = kit.merge_groups([_surfaces(mesh, smooth), _surfaces(det.mesh, smooth)])
    if ao:
        occ = [mesh] + list(wheel_meshes)
        kit.bake_vertex_ao({k: v for k, v in groups.items() if k == "Paint"}, occ, rays=12, dist=0.9, strength=0.9)
    near = _to_near(groups, part=part)
    return d, mesh, near


def _surfaces(mesh, thr):
    g = kit.finalize(mesh, thr)
    out = {}
    for label, dd in g.items():
        surf = "Details" if label in ("Under", "Trim") else label
        dd = {k: v.copy() for k, v in dd.items()}
        if label == "Under":
            dd["U"][:, 0] = D_UNDER
            dd["C"][:, :3] = (0.01, 0.01, 0.012)
        elif label == "Trim":
            dd["U"][:, 0] = D_PLASTIC
            dd["C"][:, :3] = (0.02, 0.02, 0.022)
        out = kit.merge_groups([out, {surf: dd}])
    return out


def _box_part(center, size, tag, part, region=0.0, rad=0.0):
    m = kit.box(center, size, "Details")                                # plain boxes (12 triangles): the rounded ones are 100 and more
    return _direct(kit.finalize(m, 80.0)["Details"], tag, part, region)


def _extras_c():
    """Taxi sign, patrol light bar and sports spoiler on the sedan shell (Blender axes: nose +Y)."""
    parts = []
    roof = 1.46
    parts.append(_box_part((0.0, -0.10, roof + 0.085), (0.52, 0.17, 0.15), T_WHITE, P_SIGN, rad=0.03))
    parts.append(_box_part((-0.24, -0.10, roof + 0.045), (0.46, 0.24, 0.085), T_SIREN_B, P_BAR, rad=0.02))
    parts.append(_box_part((0.24, -0.10, roof + 0.045), (0.46, 0.24, 0.085), T_SIREN_R, P_BAR, rad=0.02))
    parts.append(_box_part((0.0, -2.05, 1.07), (1.46, 0.27, 0.045), T_PAINT, P_SPOILER))
    for sx in (-0.5, 0.5):
        parts.append(_box_part((sx, -2.03, 0.97), (0.05, 0.12, 0.19), T_TRIM, P_SPOILER))
    return parts


def _extras_b(d_b):
    parts = []
    parts.append(_box_part((-0.30, 2.05, 2.6 + 0.045), (0.5, 0.24, 0.085), T_SIREN_B, P_BAR_B, region=0.0, rad=0.02))
    parts.append(_box_part((0.30, 2.05, 2.6 + 0.045), (0.5, 0.24, 0.085), T_SIREN_R, P_BAR_B, region=0.0, rad=0.02))
    return parts


def _under_plate(width, y0, y1, z=0.02, part=P_C, region=0.0):
    """A dark plate on the ground under the car (the shells have no floor): the poor man's contact shadow, seen through the gaps under the sills and between the wheels."""
    q = kit.quad((-width * 0.5, y1, z), (width * 0.5, y1, z), (width * 0.5, y0, z), (-width * 0.5, y0, z), "Details")
    return _direct(kit.finalize(q, 80.0)["Details"], T_TRIM, part, region)


def _band_strip():
    """A window band along both sides of the cargo box (a bus window row, painted over by the shader on every other box kind): two quads on the side walls of the box truck."""
    parts = []
    for sx in (-1.0, 1.0):
        x = sx * 1.108
        y0, y1 = -2.7, 1.2                                           # Blender y of the box region of the base truck (cab ends at y 1.4, the box runs back to -3.2)
        z0, z1 = 1.52, 2.42
        q = kit.quad((x, y1, z0), (x, y0, z0), (x, y0, z1), (x, y1, z1), "Details")
        if sx > 0:
            q = q.flipped()
        parts.append(_direct(kit.finalize(q, 38.0)["Details"], T_BAND, P_B, 1.0))
    return parts


def _wheel_group(base, hi):
    R, W = base["R"], base["tyre_w"]
    seg = 12 if hi else 8
    wm = near_wheel(R, W, seg=seg, hi=hi)
    out = []
    meshes = []
    wid = 0
    for sx, ay in ((-1, base["axle_f"]), (1, base["axle_f"]), (-1, base["axle_r"]), (1, base["axle_r"])):
        wid += 1
        x = sx * base["track"] * 0.5
        xf = kit.trans(x, ay, R) @ (kit.rot_z(math.pi) if sx < 0 else np.eye(4))
        w = wm.xformed(xf)
        meshes.append(w)
        g = kit.finalize(w, 50.0)["Wheel"]
        u = g["U"].copy()
        u[:, 1] = 1.0 - wid
        u2 = np.zeros((len(u), 2))
        u2[:, 0] = 1.0
        u2[:, 1] = 1.0 - P_WHEEL
        out.append(dict(V=g["V"], N=g["N"], U=u, U2=u2, I=g["I"]))
    return _merge(out), meshes


def build_hi():
    base = archetypes.get("sedan")
    wg, wmeshes = _wheel_group(base, True)
    _dc, _mc, near_c = _body_part("sedan", 4, 40.0, part=P_C, wheel_meshes=wmeshes)
    _db, _mb, near_b = _body_part("boxtruck", 6, 40.0, part=P_B)
    sel = near_b["V"][:, 1] < 1.4                                      # the cab / box region of the box truck shell: the box starts behind the step (Blender y 1.4; V is in Blender axes here)
    near_b["U"][sel, 1] = 0.0                                          # stored 1 - region: the box region is 1
    parts = [near_c, near_b, wg, _under_plate(1.52, -1.95, 1.95), _under_plate(1.8, -2.9, 2.9, part=P_B)] + _extras_c() + _extras_b(_db) + _band_strip()
    out = _merge(parts)
    return out


def build_lo():
    base = archetypes.get("sedan")
    wg, wmeshes = _wheel_group(base, False)
    _dc, _mc, near_c = _body_part("sedan", 5, 38.0, part=P_C, wheel_meshes=wmeshes)
    return _merge([near_c, wg, _under_plate(1.52, -1.95, 1.95)])


def count_tris(g):
    return len(g["I"])
