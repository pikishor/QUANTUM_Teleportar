"""City kit: converts Quaternius Downtown City MegaKit pieces (art_sources/quaternius_downtown_city_megakit, glTF, CC0) into lean glb pieces for the street kit.

One glb per piece: assets/models/kit_city_<name>.glb. Textured pieces are flattened to vertex colours (a flat colour per material where the partial kit ships no texture) (the base-colour texture is sampled once per face at its UV centroid),
welded, decimated to the piece's triangle cap and exported with one shared vertex-colour material. Road decals (flat alpha-textured quads in the source, whose texture atlas is not part of the free kit) are redrawn as vector markings (arrows, zebra bars, dashes) sized
from the source decal's footprint: a few flat triangles, no texture, no blending.
Orientation: glTF Y up, metres, pieces centred on x / z, y from 0 (decals lie at y = 0). UV0 = (0, height 0..1).   Run:  tools/blender/build_all.sh kit_city
"""
import math
import os
import sys

import bpy
import mathutils
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", "..", "art_sources", "quaternius_downtown_city_megakit"))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "models"))
DIRS = ["buildings_decals", "streets_roofs_props"]
CELL = 0.06

# name -> (gltf file, max triangles); decals are vectorised instead (DECALS)
PIECES = {
    "cornice_metal": ("Cornice_Metal_Center.gltf", 16),
    "cornice_brick": ("Cornice_Brick_Center.gltf", 56),
    "cornice_trim": ("Cornice_Trim_Center.gltf", 40),
    "pilaster": ("Brick_Column_Small.gltf", 60),
    "window_metal": ("Metal_Window_Half.gltf", 44),
    "acunit": ("Prop_ACUnit.gltf", 48),
    "bollard": ("Prop_Bollard.gltf", 28),
    "planter": ("Prop_Planter_Single.gltf", 64),
    "drain": ("Prop_Drain.gltf", 40),
    "manhole": ("Prop_ManholeCover.gltf", 20),
}
DECALS = {
    "decal_arrow": "Decal_ArrowStraight.gltf",
    "decal_arrow_left": "Decal_ArrowTurnLeft.gltf",
    "decal_arrow_right": "Decal_ArrowTurnRight.gltf",
    "decal_crosswalk": "Decal_Crosswalk.gltf",
    "decal_dash": "Decal_BrokenLine_Straight.gltf",
    "decal_double": "Decal_DoubleYellow_Straight.gltf",
}


def find(fname):
    for d in DIRS:
        p = os.path.join(ROOT, d, fname)
        if os.path.exists(p):
            return p
    raise FileNotFoundError(fname)


def shared_material():
    mat = bpy.data.materials.new("KitCity")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    col = nt.nodes.new("ShaderNodeVertexColor")
    col.layer_name = "Col"
    nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Roughness"].default_value = 0.6
    return mat


def base_image(mat):
    if mat is None or not mat.use_nodes:
        return None
    for n in mat.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            lk = n.inputs["Base Color"].links
            if lk and lk[0].from_node.type == "TEX_IMAGE":
                return lk[0].from_node.image
    return None


FALLBACK = {"RedBrick": (0.20, 0.07, 0.05), "Trim": (0.30, 0.29, 0.27), "MetalConcrete": (0.22, 0.22, 0.23)}   # linear colours for textures the partial kit does not ship


def fallback_colour(mat):
    nm = mat.name if mat else ""
    for k, c in FALLBACK.items():
        if k in nm:
            return c
    return tuple(mat.diffuse_color[:3]) if mat else (0.3, 0.3, 0.3)


def pixels(img):
    w, h = img.size
    if w == 0 or h == 0:
        return None
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    return a, w, h


def sample(a, w, h, u, v):
    x = int(min(max(u % 1.0, 0.0), 0.9999) * w)
    y = int(min(max(v % 1.0, 0.0), 0.9999) * h)
    return a[y, x]


def export(ob, name, tris):
    ob.name = "kit_city_" + name
    path = os.path.join(OUT, "kit_city_%s.glb" % name)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True, export_texcoords=True, export_normals=True,
                              export_vertex_color="ACTIVE", export_active_vertex_color_when_no_material=True, export_cameras=False, export_lights=False)
    print("MODEL kit_city_%s tris=%d" % (name, tris))


def finish_mesh(ob, me, cols_per_poly, height):
    for a in list(me.color_attributes):
        me.color_attributes.remove(a)
    ca = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for uvl in list(me.uv_layers):
        me.uv_layers.remove(uvl)
    uv = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        c = cols_per_poly[poly.index]
        for li in poly.loop_indices:
            ca.data[li].color = (c[0], c[1], c[2], 1.0)
            z = me.vertices[me.loops[li].vertex_index].co[2]
            uv.data[li].uv = (0.0, z / height)
    me.materials.clear()
    me.materials.append(shared_material())
    for poly in me.polygons:
        poly.material_index = 0
        poly.use_smooth = False
    me.update()


def build(name, fname, cap):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=find(fname))
    objs = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in objs:
        o.data = o.data.copy()
    # flatten the texture to a colour per polygon BEFORE any merge (UVs are still there)
    for o in objs:
        me = o.data
        img = base_image(me.materials[0] if me.materials else None)
        px = pixels(img) if img is not None else None
        if px is None and img is not None:
            img = None
        uvl = me.uv_layers.active
        fallback = fallback_colour(me.materials[0] if me.materials else None)
        ca = me.color_attributes.new("Flat", "FLOAT_COLOR", "CORNER")
        for poly in me.polygons:
            if px is not None and uvl is not None:
                us = [uvl.data[li].uv for li in poly.loop_indices]
                c = sample(px[0], px[1], px[2], sum(u[0] for u in us) / len(us), 1.0 - sum(u[1] for u in us) / len(us))[:3]
            else:
                c = fallback
            for li in poly.loop_indices:
                ca.data[li].color = (float(c[0]), float(c[1]), float(c[2]), 1.0)
        me.color_attributes.active_color = ca
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    me = ob.data
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.mesh.dissolve_limited(angle_limit=math.radians(5.0))
    bpy.ops.mesh.quads_convert_to_tris()
    bpy.ops.object.mode_set(mode="OBJECT")
    tris = len(me.polygons)
    if tris > cap:
        mod = ob.modifiers.new("dec", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = max(0.05, cap / tris)
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
        me = ob.data
    mn = [min(v.co[i] for v in me.vertices) for i in range(3)]
    mx = [max(v.co[i] for v in me.vertices) for i in range(3)]
    # glTF -> Blender is Y-up -> Z-up already handled by the importer: Blender Z is up; centre on x / y, feet on z = 0
    off = mathutils.Vector((-(mn[0] + mx[0]) * 0.5, -(mn[1] + mx[1]) * 0.5, -mn[2]))
    for v in me.vertices:
        v.co += off
    height = max(mx[2] - mn[2], 0.001)
    flat = me.color_attributes.get("Flat")
    cols = []
    for poly in me.polygons:
        li = poly.loop_indices[0]
        c = flat.data[li].color if flat is not None else (0.4, 0.4, 0.4, 1.0)
        cols.append((c[0], c[1], c[2]))
    finish_mesh(ob, me, cols, height)
    export(ob, name, len(me.polygons))
    print("  size %.2f x %.2f x %.2f" % (mx[0] - mn[0], mx[2] - mn[2], mx[1] - mn[1]))


WHITE = (0.80, 0.80, 0.76)
YELLOW = (0.80, 0.52, 0.04)


def shape(name, w, l):
    """Markings as (kind, points, colour) in plane coords centred on 0: 'r' = rect (x0, y0, x1, y1), 't' = triangle. +y is the direction of travel."""
    out = []
    hw, hl = w * 0.5, l * 0.5
    if name == "decal_arrow":
        sw = w * 0.16
        out.append(("r", (-sw, -hl, sw, hl * 0.25), WHITE))
        out.append(("t", ((-hw, hl * 0.25), (hw, hl * 0.25), (0.0, hl)), WHITE))
    elif name in ("decal_arrow_left", "decal_arrow_right"):
        sgn = -1.0 if name.endswith("left") else 1.0
        sw = w * 0.13
        out.append(("r", (-sw, -hl, sw, hl * 0.30), WHITE))
        x_end = sgn * hw * 0.55
        out.append(("r", (min(-sw, x_end), hl * 0.30 - sw * 2.0, max(sw, x_end), hl * 0.30 + sw * 0.0 + sw * 0.0), WHITE))
        out.append(("t", ((sgn * hw * 0.55, hl * 0.30 + sw * 2.4), (sgn * hw * 0.55, hl * 0.30 - sw * 4.4), (sgn * hw, hl * 0.30 - sw)), WHITE))
    elif name == "decal_crosswalk":
        n = int(w / 0.8)
        bw = w / (n * 2 - 1)
        for k in range(n):
            x0 = -hw + k * 2 * bw
            out.append(("r", (x0, -hl, x0 + bw, hl), WHITE))
    elif name == "decal_dash":
        out.append(("r", (-hw * 0.5, -0.07, hw * 0.5, 0.07), WHITE))             # the source decal is 6 m along x: one 3 m dash and a 3 m gap
    elif name == "decal_double":
        for sx in (-0.14, 0.14):
            out.append(("r", (-hw, sx - 0.06, hw, sx + 0.06), YELLOW))
    return out


def build_decal(name, fname):
    """The kit ships no textures, so the marking is drawn as flat vector shapes sized from the source decal's footprint."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=find(fname))
    ob = [o for o in bpy.data.objects if o.type == "MESH"][0]
    mw = ob.matrix_world
    pts = [mw @ v.co for v in ob.data.vertices]
    w = max(p.x for p in pts) - min(p.x for p in pts)
    l = max(p.y for p in pts) - min(p.y for p in pts)
    vs, fs, cols = [], [], []
    for kind, g, c in shape(name, w, l):
        k = len(vs)
        if kind == "r":
            x0, y0, x1, y1 = g
            vs += [(x0, y0, 0.0), (x1, y0, 0.0), (x1, y1, 0.0), (x0, y1, 0.0)]
            fs += [(k, k + 1, k + 2), (k, k + 2, k + 3)]
            cols += [c, c]
        else:
            a, b, d = g
            cross = (b[0] - a[0]) * (d[1] - a[1]) - (b[1] - a[1]) * (d[0] - a[0])
            vs += [(a[0], a[1], 0.0), (b[0], b[1], 0.0), (d[0], d[1], 0.0)]
            fs += [(k, k + 1, k + 2) if cross > 0 else (k, k + 2, k + 1)]
            cols += [c]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    nm = bpy.data.meshes.new(name)
    nm.from_pydata(vs, [], fs)
    nm.update()
    o2 = bpy.data.objects.new(name, nm)
    bpy.context.collection.objects.link(o2)
    bpy.context.view_layer.objects.active = o2
    finish_mesh(o2, nm, cols, 1.0)
    export(o2, name, len(fs))
    print("  size %.2f x %.2f" % (w, l))


if __name__ == "__main__":
    only = [a for a in sys.argv[1:] if not a.startswith("-")]
    for n, (f, c) in PIECES.items():
        if not only or n in only:
            build(n, f, c)
    for n, f in DECALS.items():
        if not only or n in only:
            build_decal(n, f)
