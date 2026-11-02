"""Interior kit: converts the Quaternius Ultimate Modular Sci-Fi FBX set (art_sources/quaternius_modular_scifi, CC0) into lean glb pieces for the interiors.

One glb per piece: assets/models/kit_<name>.glb. Per piece: every FBX object is joined into one mesh, welded, decimated (COLLAPSE, delimited by material so
colour borders survive) down to the piece's triangle cap, and exported with ONE shared material ("KitAtlas", no texture, vertex colours). The kit has no
textures: the original material colour goes to COLOR_0 and the material id to UV0.x (UV0.y = height 0..1), which scripts/interiors/interior_kit.gd maps to the
interior shader's surface classes (so the pieces share the interiors' single draw call and get the quantum film, phase seam and flicker in the shader).
Material ids: 0 Main, 1 DarkGrey, 2 Accent, 3 DarkAccent, 4 Black, 5 Light, 6 Glass, 7 Pipes.
Orientation: glTF Y up, metres, feet at y = 0, centred on x / z.   Run:  tools/blender/build_all.sh kit
"""
import math
import os
import sys

import bpy
import mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, "..", "..", "..", "art_sources", "quaternius_modular_scifi", "FBX"))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "models"))

MAT_IDS = {"Main": 0, "DarkGrey": 1, "Accent": 2, "DarkAccent": 3, "Black": 4, "Light": 5, "Glass": 6, "Pipes": 7}

# name -> (fbx file, max triangles)
PIECES = {
    "teleporter_1": ("Props_Teleporter_1.fbx", 700),
    "teleporter_2": ("Props_Teleporter_2.fbx", 960),
    "pod": ("Props_Pod.fbx", 520),
    "computer": ("Props_Computer.fbx", 300),
    "computer_small": ("Props_ComputerSmall.fbx", 300),
    "capsule": ("Props_Capsule.fbx", 300),
    "crate": ("Props_Crate.fbx", 220),
    "crate_long": ("Props_CrateLong.fbx", 240),
    "container": ("Props_ContainerFull.fbx", 300),
    "shelf": ("Props_Shelf.fbx", 190),
    "shelf_tall": ("Props_Shelf_Tall.fbx", 270),
    "vessel_tall": ("Props_Vessel_Tall.fbx", 150),
    "laser": ("Props_Laser.fbx", 420),
    "column": ("Column_Slim.fbx", 200),
    "base": ("Props_Base.fbx", 270),
    "pipes": ("Pipes.fbx", 172),
}


def shared_material():
    mat = bpy.data.materials.new("KitAtlas")
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


def build(name, fbx, cap):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=os.path.join(SRC, fbx))
    objs = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in objs:                                   # bake world transforms (the FBX importer leaves scale / rotation on the objects)
        o.data = o.data.copy()
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    me = ob.data
    # material colours by name ("Main.001" counts as "Main")
    cols = []
    ids = []
    for slot in me.materials:
        base = slot.name.split(".")[0] if slot else "Main"
        cols.append(tuple(slot.diffuse_color[:3]) if slot else (0.4, 0.4, 0.4))
        ids.append(MAT_IDS.get(base, 0))
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.mesh.dissolve_limited(angle_limit=math.radians(4.0), delimit={"MATERIAL"})       # flat faces merge first: the shape survives, only redundant triangles go
    bpy.ops.mesh.quads_convert_to_tris()
    bpy.ops.object.mode_set(mode="OBJECT")
    tris = len(me.polygons)
    if tris > cap:
        mod = ob.modifiers.new("dec", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = max(0.05, cap / tris)
        mod.use_collapse_triangulate = True
        mod.delimit = {"MATERIAL"}
        bpy.ops.object.modifier_apply(modifier=mod.name)
        me = ob.data
    # re-centre: feet at y(up) = 0, centred on x / y (Blender Z is up)
    mn = [min(v.co[i] for v in me.vertices) for i in range(3)]
    mx = [max(v.co[i] for v in me.vertices) for i in range(3)]
    off = mathutils.Vector((-(mn[0] + mx[0]) * 0.5, -(mn[1] + mx[1]) * 0.5, -mn[2]))
    for v in me.vertices:
        v.co += off
    height = max(mx[2] - mn[2], 0.001)
    # vertex colours and ids per face corner (the polygon keeps its material index through the decimation)
    for a in list(me.color_attributes):
        me.color_attributes.remove(a)
    ca = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for uvl in list(me.uv_layers):
        me.uv_layers.remove(uvl)
    uv = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        mi = min(poly.material_index, len(cols) - 1)
        c = cols[mi]
        for li in poly.loop_indices:
            ca.data[li].color = (c[0], c[1], c[2], 1.0)
            z = me.vertices[me.loops[li].vertex_index].co[2]
            uv.data[li].uv = (float(ids[mi]), z / height)
    me.materials.clear()
    me.materials.append(shared_material())
    for poly in me.polygons:
        poly.material_index = 0
        poly.use_smooth = False
    me.update()
    ob.name = "kit_" + name
    path = os.path.join(OUT, "kit_%s.glb" % name)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True, export_texcoords=True, export_normals=True,
                              export_vertex_color="ACTIVE", export_active_vertex_color_when_no_material=True, export_cameras=False, export_lights=False)
    print("MODEL kit_%s tris=%d (from %d) size=%.2f x %.2f x %.2f" % (name, len(me.polygons), tris, mx[0] - mn[0], mx[2] - mn[2], mx[1] - mn[1]))


if __name__ == "__main__":
    only = [a for a in sys.argv[1:] if not a.startswith("-")]
    for n, (f, c) in PIECES.items():
        if not only or n in only:
            build(n, f, c)
