"""Blender side of the Cars v2 generator: turn finalize() buffers into bpy meshes, build the node tree (LOD meshes, wheels, anchors), export the GLB and
render Workbench previews. Needs the bpy interpreter (godot/.venv-tools)."""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import glbtool  # noqa: E402

SURFACE_VIEW = {            # Workbench preview colours (linear-ish), by surface name
    "Paint": (0.16, 0.30, 0.62, 1.0), "Details": (0.05, 0.05, 0.055, 1.0), "Glass": (0.10, 0.17, 0.24, 1.0), "Wheel": (0.06, 0.06, 0.065, 1.0),
    "Lod": (0.16, 0.30, 0.62, 1.0), "Lamps": (1.0, 0.8, 0.5, 1.0),
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)


def material(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        if bsdf is not None:
            c = SURFACE_VIEW.get(name, (0.5, 0.5, 0.5, 1.0))
            bsdf.inputs["Base Color"].default_value = c
        m.diffuse_color = SURFACE_VIEW.get(name, (0.5, 0.5, 0.5, 1.0))
        m.use_backface_culling = name != "Wheel"
    return m


def mesh_data(name, groups, order=None):
    """A bpy mesh holding every surface of `groups` ({surface: dict(V, N, C, U, U2, I)}) as its own material slot (in `order`). Returns (mesh, order used)."""
    order = [k for k in (order or list(groups.keys())) if k in groups and len(groups[k]["I"]) > 0]
    V, N, C, U, U2, I, MI = [], [], [], [], [], [], []
    off = 0
    for si, sname in enumerate(order):
        g = groups[sname]
        V.append(g["V"])
        N.append(g["N"])
        C.append(g["C"])
        U.append(g["U"])
        U2.append(g["U2"])
        I.append(g["I"] + off)
        MI.append(np.full(len(g["I"]), si, dtype=np.int32))
        off += len(g["V"])
    V, N, C, U, U2, I, MI = [np.concatenate(a) for a in (V, N, C, U, U2, I, MI)]
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in V], [], [tuple(int(i) for i in f) for f in I])
    me.update()
    for sname in order:
        me.materials.append(material(sname))
    me.polygons.foreach_set("material_index", MI)
    me.polygons.foreach_set("use_smooth", np.ones(len(I), dtype=bool))
    try:
        me.normals_split_custom_set_from_vertices([tuple(n) for n in N])
    except Exception as e:  # noqa: BLE001
        print("custom normals failed:", e)
    col = me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
    col.data.foreach_set("color", C.astype(np.float32).ravel())
    me.color_attributes.active_color = col
    me.color_attributes.render_color_index = 0
    loop_v = np.empty(len(me.loops), dtype=np.int32)
    me.loops.foreach_get("vertex_index", loop_v)
    uv0 = me.uv_layers.new(name="UVMap")
    uv0.data.foreach_set("uv", U[loop_v].astype(np.float32).ravel())
    uv1 = me.uv_layers.new(name="UV2")
    uv1.data.foreach_set("uv", U2[loop_v].astype(np.float32).ravel())
    return me, order


def mesh_object(name, groups=None, order=None, parent=None, loc=(0, 0, 0), rot=(0, 0, 0), data=None):
    """An object holding the mesh of `groups` (built here) or the existing `data` (shared between objects, e.g. the four wheels)."""
    me = data if data is not None else mesh_data(name, groups, order)[0]
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = rot
    if parent is not None:
        ob.parent = parent
    return ob


def empty(name, loc=(0, 0, 0), parent=None, rot=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = "PLAIN_AXES"
    e.empty_display_size = 0.05
    e.location = loc
    e.rotation_euler = rot
    bpy.context.scene.collection.objects.link(e)
    if parent is not None:
        e.parent = parent
    return e


def export_glb(path, objs):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False, export_yup=True, export_image_format="NONE",
                              export_materials="EXPORT", export_vertex_color="ACTIVE", export_active_vertex_color_when_no_material=True, export_cameras=False,
                              export_lights=False, export_animations=False, export_skins=False, export_extras=True, export_tangents=False,
                              export_texcoords=True, export_normals=True)
    js, _ = glbtool.read_glb(path)
    return js


def report(path):
    js, _ = glbtool.read_glb(path)
    lo, hi = glbtool.bounds(js)
    return glbtool.triangle_count(js), os.path.getsize(path), lo, hi, js


# ------------------------------------------------------------------------------------------------------------------------------ previews
def preview(objs, out_png, views=("front3q", "side", "rear3q", "top"), size=(640, 360), center=(0, 0, 0.6), dist=7.5, color_by=None):
    """Workbench renders of the objects from several views, tiled into one PNG. Blender axes: +Y is the nose."""
    from PIL import Image
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.render.film_transparent = False
    sc.world = bpy.data.worlds.new("w") if sc.world is None else sc.world
    sc.world.color = (0.05, 0.06, 0.08)
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_specular_highlight = True
    sh.studio_light = "studio.sl" if "studio.sl" in [s.name for s in bpy.context.preferences.studio_lights] else sh.studio_light
    cam_d = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam_d.lens = 50
    tiles = []
    for v in views:
        if v == "front3q":
            pos = Vector((-dist * 0.62, dist * 0.7, 2.0))
        elif v == "rear3q":
            pos = Vector((dist * 0.62, -dist * 0.7, 2.0))
        elif v == "side":
            pos = Vector((dist * 1.05, 0.0, 0.9))
        elif v == "front":
            pos = Vector((0.0, dist * 1.0, 1.0))
        elif v == "rear":
            pos = Vector((0.0, -dist * 1.0, 1.0))
        elif v == "top":
            pos = Vector((0.0, -0.01, dist * 1.35))
        elif v == "low":
            pos = Vector((-dist * 0.55, dist * 0.55, 0.45))
        else:
            pos = Vector((dist, dist, dist * 0.5))
        cam.location = pos
        look = Vector(center) - pos
        cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
        path = out_png + "_%s.png" % v
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        tiles.append(Image.open(path).convert("RGB"))
        os.remove(path)
    cols = 2
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * size[0], rows * size[1]))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % cols) * size[0], (i // cols) * size[1]))
    sheet.save(out_png)
    bpy.data.objects.remove(cam)
    return out_png
