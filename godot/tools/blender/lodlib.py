"""LOD1 for the vehicle bodies: a decimated copy of the baked LOD0 body mesh ("Body_LOD1").

The copy is made AFTER the atlas bake and the material assignment (export_model's finalize hook), so it shares the UV layout, the vertex colours and the materials
(Body / Details / Headlights / Taillights / Underglow) of "Body": the game shows exactly one of the two by camera distance (VehicleVisual.LOD1_DIST) and gives both the same
per-instance material overrides (paint, lamps). Collapse decimation, symmetric in X, then weighted normals again (the decimate modifier drops the custom normals).
Glow geometry (carlib.add_glow) is appended to BOTH meshes after this, so the lamp halos are full quality on the far mesh too.
"""
import bpy  # noqa: F401  (must be imported before mathutils)


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def make_lod1(body, ratio, name="Body_LOD1"):
    """Return a new object `name`: `body` decimated to about `ratio` of its triangles (linked to the scene, same transform and materials)."""
    me = body.data.copy()
    me.name = name
    obj = bpy.data.objects.new(name, me)
    obj.location = body.location
    obj.rotation_euler = body.rotation_euler
    bpy.context.scene.collection.objects.link(obj)
    for k in body.keys():
        if str(k).startswith("qt_"):
            obj[k] = body[k]
    obj["qt_no_shadow"] = 1
    mod = obj.modifiers.new("lod1", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = float(ratio)
    mod.use_collapse_triangulate = True
    mod.use_symmetry = True
    mod.symmetry_axis = "X"
    with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj]):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    wn = obj.modifiers.new("wn", "WEIGHTED_NORMAL")
    wn.mode = "FACE_AREA"
    wn.weight = 50
    wn.keep_sharp = True
    wn.thresh = 0.01
    with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj]):
        bpy.ops.object.modifier_apply(modifier=wn.name)
    return obj
