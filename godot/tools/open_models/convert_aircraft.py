#!/usr/bin/env python3
"""Open-source aircraft -> game aircraft (wave 106, airport and aircraft).

Sources (all CC0, see art_sources/open_aircraft/<pack>/LICENSE.txt + SOURCE.md; the raw .blend files are NOT committed):
    airliner  "Jet airplane" (OpenGameArt, CC0)       passengerjet_gear_down.blend -> assets/models/xv_airliner.glb
    bizjet    "Private Jet" (OpenGameArt, CC0)        private_jet_gear_down.blend  -> assets/models/xv_bizjet.glb
    cargo     "Jumbo Jet, Wide Body" (OpenGameArt, CC0) Aircraft_2.blend           -> assets/models/xv_cargo.glb
    jet       "Mig" (OpenGameArt, CC0)                Mig-15.blend                 -> assets/models/xv_jet.glb
Output: the VehicleVisual contract of convert_craft.py: one mesh "Body" (surfaces Body = the paint, Details, Trim, Glass), nose to -Z, up +Y, the wheels' plane (or the belly) at y = 0.
The textures of the sources are not packed in the .blend files: colours come from the materials; the paint surface is recoloured in game (VehicleVisual.set_paint). No texture is exported.
The airliner and the business jet keep the landing gear of their gear-down variant; the cargo plane and the fighter have none in their source, so the converter lifts the body and adds a simple gear (struts and wheels).

Run from godot/ with the tool venv (bpy 5.2):
    .venv-tools/bin/python tools/open_models/convert_aircraft.py <dir with the downloaded .blend files> [airliner bizjet cargo jet]
"""
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_craft as cc  # noqa: E402


def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    cc._mats.clear()
    with bpy.data.libraries.load(path) as (src, dst):
        dst.objects = src.objects
    for o in dst.objects:
        if o is not None:
            bpy.context.scene.collection.objects.link(o)
    bpy.context.view_layer.update()
    return {o.name: o for o in bpy.context.scene.objects if o.type == "MESH"}


def tail_sign(g, axis):
    """+1 when the tail (the fin tip, the highest point) is on the positive side of `axis` (0 = x, 1 = y), else -1."""
    a = np.array(g.v)
    i = int(np.argmax(a[:, 2]))
    c = (a[:, axis].min() + a[:, axis].max()) * 0.5
    return 1.0 if a[i, axis] > c else -1.0


def add_box(g, c, size, role):
    """An axis-aligned box of faces in a Group (Blender coordinates: x right, y nose, z up)."""
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    n = len(g.v)
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                g.v.append((c[0] + sx * hx, c[1] + sy * hy, c[2] + sz * hz))
    idx = lambda sx, sy, sz: n + ((sx + 1) // 2) * 4 + ((sy + 1) // 2) * 2 + (sz + 1) // 2
    quads = [((1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)), ((-1, -1, 1), (-1, 1, 1), (-1, 1, -1), (-1, -1, -1)),
             ((-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1)), ((1, -1, -1), (1, -1, 1), (-1, -1, 1), (-1, -1, -1)),
             ((-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)), ((-1, 1, -1), (1, 1, -1), (1, -1, -1), (-1, -1, -1))]
    for q in quads:
        g.f.append(tuple(idx(*p) for p in q))
        g.role.append(role)
        g.smooth.append(False)


def add_wheel(g, c, r, w, role, seg=10):
    """A wheel with its axis along X centred on c."""
    import math
    n = len(g.v)
    for sx in (-1, 1):
        for i in range(seg):
            a = 2 * math.pi * i / seg
            g.v.append((c[0] + sx * w / 2, c[1] + math.cos(a) * r, c[2] + math.sin(a) * r))
    for i in range(seg):
        j = (i + 1) % seg
        g.f.append((n + i, n + j, n + seg + j, n + seg + i))
        g.role.append(role)
        g.smooth.append(True)
    g.f.append(tuple(n + seg + i for i in range(seg)))
    g.role.append(role)
    g.smooth.append(False)
    g.f.append(tuple(n + i for i in reversed(range(seg))))
    g.role.append(role)
    g.smooth.append(False)


def add_gear(g, spec):
    """Lift the body by spec['lift'] and add a nose wheel and two main wheels with struts. Positions are fractions of the bounding box (x: -1..1 of the half span, y: 0..1 nose to tail)."""
    lo, hi = g.bbox()
    lift = spec["lift"]
    g.v = [(x, y, z + lift) for (x, y, z) in g.v]
    r, w = spec["r"], spec["w"]
    span = (hi[0] - lo[0]) * 0.5
    ln = hi[1] - lo[1]
    for (fx, fy) in spec["mains"]:
        c = (fx * span, lo[1] + fy * ln, r)
        add_wheel(g, c, r, w, "Details")
        add_box(g, (c[0], c[1], (r + lift) * 0.5 + r * 0.5), (0.14, 0.14, lift - r + r * 0.5 + 0.35), "Trim")
    nf = spec["nose"]
    c = (0.0, lo[1] + nf * ln, r * 0.8)
    add_wheel(g, c, r * 0.8, w * 0.8, "Details")
    add_box(g, (0.0, c[1], (r * 0.8 + lift) * 0.5 + 0.2), (0.12, 0.12, lift - r * 0.8 + 0.4), "Trim")


def convert(name, path, role_of, axis, length, skip=(), only=None, gear=None):
    obs = load(path)
    g = cc.Group()
    for nm, ob in obs.items():
        if nm in skip or (only is not None and nm not in only):
            continue
        g.add_object(ob, role_of)
    ts = tail_sign(g, axis)
    nose = -ts                                                        # the nose is on the other side of the tail
    # rotate about Z so that the nose points to +Y (convert_craft.fit): nose +x -> +90, -x -> -90, +y -> 0, -y -> 180
    rot = {(0, 1.0): 90.0, (0, -1.0): -90.0, (1, 1.0): 0.0, (1, -1.0): 180.0}[(axis, nose)]
    cc.fit([g], rot, length)
    if gear is not None:
        add_gear(g, gear)
    for o in list(bpy.context.scene.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    ob = cc.make_mesh_object("Body", g)
    cc.export(name, [ob])


def airliner_role(mat, col):
    if mat in ("Engine", "EngineShiny"):
        return "Trim"
    if mat in ("EngineInterior", "Misc", "Tyre", "Hub"):
        return "Details"
    return "Body"


def bizjet_role(mat, col):
    if mat == "EngineShiny":
        return "Trim"
    if mat in ("EngineInterior", "Tyre", "Hub", "Misc"):
        return "Details"
    return "Body"


def cargo_role(mat, col):
    return "Body"


def jet_role(mat, col):
    m = mat.lower()
    if m.startswith("glass"):
        return "Glass"
    if m.startswith("front"):
        return "Details"
    if m.startswith("propeller"):
        return "Trim"
    return "Body"


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    src = args[0]
    which = args[1:] or ["airliner", "bizjet", "cargo", "jet"]
    for w in which:
        if w == "airliner":
            convert("airliner", os.path.join(src, "passengerjet_gear_down.blend"), airliner_role, 0, 34.0)
        elif w == "bizjet":
            convert("bizjet", os.path.join(src, "private_jet_gear_down.blend"), bizjet_role, 1, 19.0)
        elif w == "cargo":
            convert("cargo", os.path.join(src, "Aircraft_2.blend"), cargo_role, 1, 44.0,
                    gear={"lift": 2.1, "r": 0.8, "w": 0.7, "mains": [(-0.28, 0.55), (0.28, 0.55), (-0.2, 0.6), (0.2, 0.6)], "nose": 0.14})
        elif w == "jet":
            convert("jet", os.path.join(src, "Mig-15.blend"), jet_role, 1, 14.0,
                    gear={"lift": 0.85, "r": 0.38, "w": 0.26, "mains": [(-0.2, 0.52), (0.2, 0.52)], "nose": 0.12})


if __name__ == "__main__":
    main()
