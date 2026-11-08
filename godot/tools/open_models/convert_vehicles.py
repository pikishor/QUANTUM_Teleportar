#!/usr/bin/env python3
"""Open-source vehicles -> game vehicles (round 4).

Source: Kenney Car Kit 3.1 (CC0), art_sources/kenney_car_kit/glb/*.glb (colour-map textured, wheels as separate nodes).
Output: godot/assets/models/ov_<name>.glb  -- the VehicleVisual contract of the older car models:
    Body        one mesh, surfaces Body (the paint: neutral grey, re-tinted per instance), Details (vertex colours: glass, tyres, trim),
                Headlights, Taillights (emissive lamp surfaces; VehicleVisual merges them into the additive "Lamps" surface)
    Body_LOD1   the same, about 40 % of the triangles (VehicleVisual switches at 42 m)
    WheelFL/FR/RL/RR  separate nodes at the axle centres (steer / roll are applied to them), Details only
No texture is exported: every colour is baked into vertex colours, so a car costs no texture memory at all (LOW budget 200 MB untouched).
The Kenney proportions are stubby (a toy), so the body is remapped along its length with a piecewise-linear stretch: the arch zones around the
wheels keep their roundness (scaled with the wheel), the overhangs and the cabin take the extra length. Front of the model = -Z in glTF (Godot).

Run:  godot/.venv-tools/bin/python godot/tools/open_models/convert_vehicles.py [name ...]      (needs bpy 5.2, see tools/setup_python.sh)
"""
import math
import os
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.abspath(os.path.join(GODOT, "..", "art_sources", "kenney_car_kit", "glb"))
OUT = os.environ.get("QT_MODELS_DIR", os.path.join(GODOT, "assets", "models"))

# name: src file, target width / length / height (m, the VehicleSpecs dims), wheel radius, wheelbase share of the length, paint mode
#   paint "sat" = the saturated hue that covers most of the body; "white" = the light panels (police, ambulance, van); explicit (r,g,b) 0..255 = that swatch family
VEHICLES = {
    "sedan": dict(src="sedan", W=1.86, L=4.7, H=1.42, R=0.35, wb=0.6, paint="sat"),
    "sport": dict(src="sedan-sports", W=1.92, L=4.4, H=1.22, R=0.35, wb=0.6, paint="sat"),
    "hatch": dict(src="hatchback-sports", W=1.80, L=3.8, H=1.36, R=0.32, wb=0.60, paint="sat"),
    "suv": dict(src="suv", W=1.98, L=4.7, H=1.72, R=0.39, wb=0.6, paint="sat"),
    "luxury": dict(src="suv-luxury", W=2.0, L=4.85, H=1.72, R=0.40, wb=0.6, paint="sat"),
    "taxi": dict(src="taxi", W=1.86, L=4.55, H=1.55, R=0.35, wb=0.6, paint="sat"),
    "police": dict(src="police", W=1.95, L=4.6, H=1.38, R=0.35, wb=0.6, paint="white"),
    "ambulance": dict(src="ambulance", W=2.05, L=5.4, H=2.4, R=0.38, wb=0.6, paint="white"),
    "van": dict(src="van", W=2.0, L=5.0, H=2.1, R=0.37, wb=0.6, paint="white"),
    "delivery": dict(src="delivery", W=2.1, L=5.8, H=2.7, R=0.40, wb=0.6, paint="white"),
    "truck": dict(src="truck", W=2.2, L=6.4, H=2.9, R=0.44, wb=0.6, paint="sat"),
    "firetruck": dict(src="firetruck", W=2.3, L=7.0, H=3.2, R=0.46, wb=0.6, paint="sat"),
    "garbage": dict(src="garbage-truck", W=2.3, L=6.5, H=3.1, R=0.45, wb=0.6, paint="sat"),
    "race": dict(src="race", W=1.95, L=4.3, H=1.12, R=0.33, wb=0.6, paint="sat"),
}
LOD1_RATIO = 0.4
WHEEL_RATIO = 0.55
DENT_EDGE = 0.55                 # edges longer than this (m) are split once
LAMP_SHRINK = 0.62
LAMP_PUSH = 0.012                # metres the lamp faces stand off the body

CAT_BODY, CAT_DETAIL, CAT_HEAD, CAT_TAIL = 0, 1, 2, 3


def lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


class Palette:
    def __init__(self, path):
        img = bpy.data.images.load(path)
        img.colorspace_settings.name = "Non-Color"            # raw sRGB bytes / 255, no linearisation
        self.w, self.h = img.size
        self.px = np.array(img.pixels[:], dtype=np.float32).reshape(self.h, self.w, 4)   # linear in Blender, we want the sRGB bytes back

    def srgb(self, u, v):
        x = min(self.w - 1, max(0, int(u * self.w)))
        y = min(self.h - 1, max(0, int(v * self.h)))        # Blender images are bottom-up: v = 0 is the bottom row
        r = self.px[y, x]
        return tuple(float(np.clip(c, 0, 1)) for c in r[:3])


def hsv_of(c):
    r, g, b = c
    mx, mn = max(c), min(c)
    d = mx - mn
    if d < 1e-6:
        return 0.0, 0.0, mx
    if mx == r:
        h = ((g - b) / d) % 6
    elif mx == g:
        h = (b - r) / d + 2
    else:
        h = (r - g) / d + 4
    return h * 60.0, d / mx, mx


def hue_dist(a, b):
    d = abs(a - b) % 360
    return min(d, 360 - d)


def detail_rgb(c, k=0.62, desat=0.55):
    """The kit's pastel greys become charcoal trim: desaturated, darker, linear."""
    g = 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]
    return tuple(lin((x + (g - x) * desat) * k) for x in c)


def is_glass(c):
    r, g, b = c
    return b >= g - 0.01 and g >= r + 0.02 and (r + g + b) / 3 > 0.78


def is_head(c):
    r, g, b = c
    return r > 0.9 and g > 0.74 and b < 0.36


def is_tail(c):
    r, g, b = c
    return r > 0.78 and g < 0.30 and b < 0.30


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def world_mesh(ob):
    """(vertices world coords as np (n,3), polygon list is kept on the mesh) without touching ob."""
    m = ob.matrix_world
    return np.array([tuple(m @ v.co) for v in ob.data.vertices], dtype=np.float64)


def make_material(name, rgb, rough, metal=0.0, emit=None, strength=1.0, vcol=False):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.use_backface_culling = True                              # glTF doubleSided false: no double fill cost
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if vcol:                                                   # the glTF exporter writes COLOR_0 from a Color Attribute node that feeds the base colour
        node = m.node_tree.nodes.new("ShaderNodeVertexColor")
        node.layer_name = "Col"
        m.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    if emit is not None:
        bsdf.inputs["Base Color"].default_value = (0, 0, 0, 1)
        bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    return m


def stretch_map(y, ymin, ymax, yf, yr, a, sw, target_len, wheelbase):
    """Piecewise-linear remap of the length axis. The arch zones [yf-a, yf+a] and [yr-a, yr+a] scale by sw (the wheel keeps its round arch), the middle is stretched so the wheel
    centres end up `wheelbase` apart, the overhangs take the rest of `target_len`. Returns (mapped y, middle scale, overhang scale, control points out, in)."""
    over_f = (yf - a) - ymin
    over_r = ymax - (yr + a)
    mid = (yr - a) - (yf + a)
    sm = max((wheelbase - 2 * a * sw) / mid, sw)
    so = max((target_len - wheelbase - 2 * a * sw) / (over_f + over_r), sw * 0.9)
    ctrl_in = [ymin, yf - a, yf + a, yr - a, yr + a, ymax]
    ctrl_out = [0.0]
    ctrl_out.append(ctrl_out[-1] + over_f * so)
    ctrl_out.append(ctrl_out[-1] + 2 * a * sw)
    ctrl_out.append(ctrl_out[-1] + mid * sm)
    ctrl_out.append(ctrl_out[-1] + 2 * a * sw)
    ctrl_out.append(ctrl_out[-1] + over_r * so)
    return np.interp(y, ctrl_in, ctrl_out), sm, so, ctrl_out, ctrl_in


def convert(name, cfg, pal):
    clear_scene()
    src = os.path.join(SRC, cfg["src"] + ".glb")
    bpy.ops.import_scene.gltf(filepath=src)
    objs = [o for o in bpy.data.objects if o.type == "MESH"]
    wheels = [o for o in objs if "wheel" in o.name]
    bodies = [o for o in objs if "wheel" not in o.name]
    if len(wheels) > 4:                                    # a spare wheel on the tailgate (suv): it is part of the body, the four lowest wheels roll
        wheels.sort(key=lambda o: float(world_mesh(o)[:, 2].mean()))
        bodies += wheels[4:]
        wheels = wheels[:4]
    if len(wheels) != 4 or not bodies:
        raise SystemExit("%s: expected 4 wheels and a body, got %d / %d" % (name, len(wheels), len(bodies)))

    # ---- body: join, bake palette colours per face into categories, in the Kenney frame (front = -Y, z up, units as authored)
    bpy.ops.object.select_all(action="DESELECT")
    for o in bodies:
        o.select_set(True)
    bpy.context.view_layer.objects.active = bodies[0]
    for o in bodies:                                       # apply the object transform so every vertex is in model space
        mw = o.matrix_world.copy()
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = "Body"
    for ca in list(body.data.color_attributes):                # the kit's own white vertex colours would be COLOR_0, ours must be it
        body.data.color_attributes.remove(ca)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    uvl = bm.loops.layers.uv.active
    cols = {}
    for f in bm.faces:
        u = sum(l[uvl].uv[0] for l in f.loops) / len(f.loops)
        v = sum(l[uvl].uv[1] for l in f.loops) / len(f.loops)
        cols[f.index] = pal.srgb(u, v)
    ys = [v.co.y for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    ymin, ymax = min(ys), max(ys)
    zmin, zmax = min(zs), max(zs)
    halfL = (ymax - ymin) / 2
    # the paint swatch family
    area = {}
    for f in bm.faces:
        c = cols[f.index]
        h, s, v = hsv_of(c)
        if is_glass(c) or is_head(c) or is_tail(c) or v < 0.45:
            continue
        key = None
        if cfg["paint"] == "sat" and s > 0.4:
            key = round(h / 12)
        elif cfg["paint"] == "white" and s < 0.2 and v > 0.72 and not is_glass(c):
            key = 0
        if key is not None:
            area[key] = area.get(key, 0.0) + f.calc_area()
    paint_key = max(area, key=area.get) if area else None
    paint_hue = None
    if paint_key is not None and cfg["paint"] == "sat":
        paint_hue = paint_key * 12

    band_lo, band_hi = zmin + 0.18, zmin + 0.85 * (zmax - zmin)
    bys = [f.calc_center_median().y for f in bm.faces if band_lo < f.calc_center_median().z < band_hi]
    fy, ry = min(bys), max(bys)                              # the ends of the car at lamp height (a grill or a bumper may reach further at other heights)

    def classify(f):
        c = cols[f.index]
        h, s, v = hsv_of(c)
        ctr = f.calc_center_median()
        near_front = ctr.y < fy + 0.16
        near_rear = ctr.y > ry - 0.16
        if (near_front or near_rear) and band_lo < ctr.z < band_hi:
            if near_front and is_head(c):
                return CAT_HEAD
            if near_rear and is_tail(c):
                return CAT_TAIL
        if is_glass(c):
            return CAT_DETAIL
        if cfg["paint"] == "sat" and paint_hue is not None and s > 0.4 and v > 0.45 and hue_dist(h, paint_hue) < 30:
            return CAT_BODY
        if cfg["paint"] == "white" and s < 0.2 and v > 0.72:
            return CAT_BODY
        return CAT_DETAIL

    cats = {f.index: classify(f) for f in bm.faces}
    for f in bm.faces:
        f.material_index = cats[f.index]

    # ---- the stretch: positions of the wheel centres in Kenney units
    wc = []
    for w in wheels:
        vs = world_mesh(w)
        lo, hi = vs.min(0), vs.max(0)
        wc.append(dict(obj=w, c=(lo + hi) / 2, r=(hi[2] - lo[2]) / 2, wid=hi[0] - lo[0]))
    for w in wc:
        w["front"] = w["c"][1] < 0
        w["right"] = w["c"][0] < 0                         # Kenney: front = -Y, so the right-hand side (looking forward) is +X
        w["right"] = w["c"][0] > 0
    yf = float(np.mean([w["c"][1] for w in wc if w["front"]]))
    yr = float(np.mean([w["c"][1] for w in wc if not w["front"]]))
    rk = float(np.mean([w["r"] for w in wc]))
    xk = float(np.mean([abs(w["c"][0]) for w in wc]))
    bw = max(v.co.x for v in bm.verts) - min(v.co.x for v in bm.verts)
    sw = cfg["R"] / rk
    sx = cfg["W"] / bw
    sz = cfg["H"] / (zmax - 0.0)
    a = rk * 1.08
    target_len = cfg["L"]
    wheelbase = cfg["wb"] * target_len
    # model Y' = along the car, 0 at the rear end -> shift to centre later; Kenney front (-Y) goes to Godot -Z, which is +Y' in Blender's game frame (+Y = front)
    # work in the Kenney direction first (ymin = front) then mirror
    ymap = lambda y: stretch_map(y, ymin, ymax, yf, yr, a, sw, target_len, wheelbase)[0]
    _, sm, so, co, ci = stretch_map(0.0, ymin, ymax, yf, yr, a, sw, target_len, wheelbase)
    print("  %-9s mid stretch %.2f  (wheel %.2f, overhang %.2f, sx %.2f, sz %.2f)  wheelbase %.2f m" % (name, sm, sw, so, sx, sz, wheelbase))
    # map the vertices
    for v in bm.verts:
        v.co.y = float(ymap(v.co.y))
        v.co.x = v.co.x * sx
        v.co.z = v.co.z * sz
    newlen = max(v.co.y for v in bm.verts)
    yc = newlen / 2
    for v in bm.verts:                                   # centre, then turn 180 deg about Z: the Kenney front (-Y) becomes +Y (Blender game front)
        v.co.y = -(v.co.y - yc)
        v.co.x = -v.co.x
    # wheel centres in the new frame
    wy = {}
    for w in wc:
        ny = float(ymap(w["c"][1])) - yc
        outer = 0.5 * cfg["W"] - 0.5 * w["wid"] * sw * 0.6 - 0.01            # the wheel's outer face sits just inside the body side: a real track, not the kit's recessed wheels
        w["new"] = Vector((-math.copysign(outer, w["c"][0]), -ny, cfg["R"]))
    # ---- duplicate the lamp faces pushed out, recolour the originals dark; build the loop colours
    ao_h = zmax * sz
    col_layer = bm.loops.layers.float_color.new("Col") if hasattr(bm.loops.layers, "float_color") else bm.loops.layers.color.new("Col")
    paint_grey = lin(0.80)
    lamp_faces = []
    for f in list(bm.faces):
        cat = cats[f.index]
        ctr = f.calc_center_median()
        k = 0.62 + 0.38 * min(1.0, max(0.0, ctr.z / (0.55 * ao_h)))        # cheap contact shadow: low panels darker
        c = cols[f.index]
        if cat == CAT_BODY:
            rgb = (paint_grey * k,) * 3
        elif cat in (CAT_HEAD, CAT_TAIL):
            lamp_faces.append((f, cat))
            rgb = tuple(lin(x) * 0.12 for x in (0.5, 0.5, 0.55))
        elif is_glass(c):
            rgb = (lin(0.035), lin(0.05), lin(0.07))
        else:
            rgb = tuple(x * (0.7 + 0.3 * k) for x in detail_rgb(c))
        for l in f.loops:
            l[col_layer] = (*rgb, 1.0)
    have = {cat for _, cat in lamp_faces}
    for cat, sgn, yend in ((CAT_HEAD, 1.0, fy), (CAT_TAIL, -1.0, ry)):         # no lamp faces in the kit model: stand two lamp quads on the end of the body
        if cat in have:
            continue
        zc = zmin + 0.52 * (zmax - zmin) if cat == CAT_TAIL else zmin + 0.45 * (zmax - zmin)
        for side in (-1.0, 1.0):
            xt = side * 0.62 * (max(v.co.x for v in bm.verts) - min(v.co.x for v in bm.verts)) * 0.5
            near_v = [v.co.y for v in bm.verts if abs(v.co.x - xt) < 0.2 and abs(v.co.z - zc) < 0.12]
            if not near_v:
                continue
            ye = max(near_v) if sgn > 0 else min(near_v)
            hw, hh = 0.17, 0.055
            quad = [bm.verts.new((xt + dx, ye + sgn * LAMP_PUSH * 1.5, zc + dz)) for dx, dz in ((-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh))]
            nf = bm.faces.new(quad)
            nf.normal_update()
            if nf.normal.y * sgn < 0:
                nf.normal_flip()
            nf.material_index = 2 if cat == CAT_HEAD else 3
            for l in nf.loops:
                l[col_layer] = (1, 1, 1, 1)
    for f, cat in lamp_faces:
        n = f.normal.copy()
        nf = bmesh.ops.duplicate(bm, geom=[f])["geom"]
        ctr_l = f.calc_center_median()
        for g in nf:
            if isinstance(g, bmesh.types.BMVert):
                g.co = ctr_l + (g.co - ctr_l) * LAMP_SHRINK + n * LAMP_PUSH        # the kit's lamp faces are big wedges: smaller lenses read as lamps
        for g in nf:
            if isinstance(g, bmesh.types.BMFace):
                g.material_index = 2 if cat == CAT_HEAD else 3
                for l in g.loops:
                    l[col_layer] = (1, 1, 1, 1)
        f.material_index = 1                                # the original keeps the body closed behind the lamp, as dark trim
    # one subdivision of the long edges: the crash dents push vertices in, a 700 triangle body would only get a handful of them (VehicleVisual dents, test_vehicle_realism)
    long_edges = {e for f in bm.faces if f.material_index in (CAT_BODY, CAT_DETAIL) for e in f.edges if e.calc_length() > DENT_EDGE}
    bmesh.ops.subdivide_edges(bm, edges=list(long_edges), cuts=1, use_grid_fill=True)
    # remove the uv layer (no texture is exported)
    while bm.loops.layers.uv:
        bm.loops.layers.uv.remove(bm.loops.layers.uv[0])
    body.data.materials.clear()                              # the slots first (clearing later would reset every face to slot 0)
    mats = [
        make_material("Body", (0.8, 0.8, 0.8), 0.45, 0.0),
        make_material("Details", (1.0, 1.0, 1.0), 0.55, 0.0),
        make_material("Headlights", (0, 0, 0), 0.5, 0.0, emit=(1.0, 0.88, 0.63), strength=3.0),
        make_material("Taillights", (0, 0, 0), 0.5, 0.0, emit=(1.0, 0.03, 0.04), strength=2.6),
    ]
    for m in mats:
        body.data.materials.append(m)
    bm.to_mesh(body.data)
    bm.free()
    # the 'Body' surface of a lamp-less model keeps all four slots (an unused slot is dropped by the exporter)

    # ---- wheels: centred meshes, nodes at the axle, scaled by sw, the right-hand wheels are the Kenney left ones mirrored by the 180 turn
    wnodes = []
    for w in wc:
        o = w["obj"]
        mw = o.matrix_world.copy()
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
        me = o.data
        centre = Vector(w["c"])
        for v in me.vertices:
            v.co = (v.co - centre)
            v.co = Vector((-v.co.x * sw, -v.co.y * sw, v.co.z * sw))
        if True:                                            # a 180 degree turn about Z keeps handedness: no normal flip needed, but keep winding sane
            me.update()
        # colours
        for ca in list(me.color_attributes):
            me.color_attributes.remove(ca)
        bmw = bmesh.new()
        bmw.from_mesh(me)
        uv = bmw.loops.layers.uv.active
        cl = bmw.loops.layers.float_color.new("Col") if hasattr(bmw.loops.layers, "float_color") else bmw.loops.layers.color.new("Col")
        for f in bmw.faces:
            u = sum(l[uv].uv[0] for l in f.loops) / len(f.loops)
            v = sum(l[uv].uv[1] for l in f.loops) / len(f.loops)
            c = pal.srgb(u, v)
            rgb = detail_rgb(c, 0.3, 0.6)
            for l in f.loops:
                l[cl] = (*rgb, 1.0)
            f.material_index = 0
        while bmw.loops.layers.uv:
            bmw.loops.layers.uv.remove(bmw.loops.layers.uv[0])
        bmw.to_mesh(me)
        bmw.free()
        me.materials.clear()
        me.materials.append(mats[1])
        nm = ("WheelF" if w["front"] else "WheelR") + ("R" if w["right"] else "L")
        # the 180 turn swaps left and right: Kenney right (+X) wheel ends up at -X = the model's LEFT
        nm = ("WheelF" if w["front"] else "WheelR") + ("L" if w["right"] else "R")
        o.name = nm
        o.location = w["new"]
        wnodes.append(o)
        # decimate the wheel (332 triangles each in the kit)
        mod = o.modifiers.new("dec", "DECIMATE")
        mod.ratio = WHEEL_RATIO
        mod.use_collapse_triangulate = True
    # ---- LOD1 of the body
    lod = body.copy()
    lod.data = body.data.copy()
    lod.name = "Body_LOD1"
    bpy.context.collection.objects.link(lod)
    # decimate everything except the lamp surfaces: do it on a copy that has the lamp faces removed, then add them back by joining the lamp-only mesh
    lamp_only = body.copy()
    lamp_only.data = body.data.copy()
    bpy.context.collection.objects.link(lamp_only)
    for ob, keep_lamps in ((lod, False), (lamp_only, True)):
        bmx = bmesh.new()
        bmx.from_mesh(ob.data)
        kill = [f for f in bmx.faces if (f.material_index in (2, 3)) != keep_lamps]
        bmesh.ops.delete(bmx, geom=kill, context="FACES")
        bmx.to_mesh(ob.data)
        bmx.free()
    mod = lod.modifiers.new("dec", "DECIMATE")
    mod.ratio = LOD1_RATIO
    mod.use_collapse_triangulate = True
    bpy.ops.object.select_all(action="DESELECT")
    for ob in (lod, lamp_only):
        ob.select_set(True)
    bpy.context.view_layer.objects.active = lod
    # apply the modifier before the join
    dg = bpy.context.evaluated_depsgraph_get()
    ev = lod.evaluated_get(dg)
    mesh_new = bpy.data.meshes.new_from_object(ev)
    lod.modifiers.clear()
    lod.data = mesh_new
    bpy.ops.object.join()
    lod = bpy.context.view_layer.objects.active
    lod.name = "Body_LOD1"

    # ---- smooth by angle, export
    for ob in [body, lod] + wnodes:
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        try:
            bpy.ops.object.shade_smooth_by_angle(angle=math.radians(42))
        except Exception:
            bpy.ops.object.shade_smooth()
    # wheels: apply the decimate now
    for ob in wnodes:
        dg = bpy.context.evaluated_depsgraph_get()
        ev = ob.evaluated_get(dg)
        m2 = bpy.data.meshes.new_from_object(ev)
        ob.modifiers.clear()
        ob.data = m2
        ob.data.materials.clear()
        ob.data.materials.append(mats[1])
    for ob in bpy.data.objects:
        if ob.type == "MESH":
            print("   attrs", ob.name, [a.name for a in ob.data.color_attributes], [a.name for a in ob.data.attributes if a.domain in ("CORNER","POINT") and a.data_type in ("FLOAT_COLOR","BYTE_COLOR")])
    bpy.ops.object.select_all(action="SELECT")
    out = os.path.join(OUT, "ov_%s.glb" % name)
    kw = dict(filepath=out, export_format="GLB", use_selection=True, export_yup=True, export_apply=False, export_texcoords=False,
              export_normals=True, export_materials="EXPORT", export_cameras=False, export_lights=False, export_animations=False,
              export_extras=False, export_image_format="NONE")
    for k, v in (("export_vertex_color", "ACTIVE"), ("export_active_vertex_color_when_no_material", True), ("export_attributes", False)):
        kw[k] = v
    try:
        bpy.ops.export_scene.gltf(**kw)
    except TypeError:
        kw.pop("export_vertex_color", None)
        kw.pop("export_active_vertex_color_when_no_material", None)
        bpy.ops.export_scene.gltf(**kw)
    fix_colors(out)
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    print("  wrote %s  body tris %d  lod1 %d  wheels %d each" % (out, tris, sum(len(p.vertices) - 2 for p in lod.data.polygons),
                                                                  sum(len(p.vertices) - 2 for p in wnodes[0].data.polygons)))


def fix_colors(path):
    """The Blender exporter writes a white COLOR_0 and our colours as COLOR_1; Godot reads COLOR_0 only: swap them in the glTF JSON."""
    import json
    import struct
    d = open(path, "rb").read()
    jl = struct.unpack("<I", d[12:16])[0]
    j = json.loads(d[20:20 + jl])
    n = 0
    for m in j["meshes"]:
        for p in m["primitives"]:
            at = p["attributes"]
            if "COLOR_1" in at:
                at["COLOR_0"] = at.pop("COLOR_1")
                n += 1
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    rest = d[20 + jl:]
    total = 12 + 8 + len(js) + len(rest)
    open(path, "wb").write(d[:8] + struct.pack("<I", total) + struct.pack("<I", len(js)) + d[16:20] + js + rest)
    return n


def main():
    names = [a for a in sys.argv[sys.argv.index("--") + 1:] if not a.startswith("-")] if "--" in sys.argv else sys.argv[1:]
    names = names or list(VEHICLES)
    pal_img = os.path.join(SRC, "Textures", "colormap.png")
    clear_scene()
    pal = Palette(pal_img)
    for n in names:
        print("==", n)
        convert(n, VEHICLES[n], pal)
        pal = Palette(pal_img)


if __name__ == "__main__":
    main()
