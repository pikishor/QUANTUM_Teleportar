"""Build assets/models/rv_near.glb: the low-triangle car of the near traffic (NearTraffic, one MultiMesh, shader prop_nearcar.gdshader) from the converted Rgsdev sedan.

Run from godot/ after convert_rgs_vehicles.py:  source .venv-tools/bin/activate; python tools/open_models/convert_near_car.py assets/models

One mesh, one surface. The surface tag the shader reads is UV.x (0 paint, 0.25 glass, 0.45 tyre, 0.55 dark trim, 0.65 rim, 0.8 headlamp, 1.0 tail lamp), UV.y of a wheel
vertex is the z of the wheel centre (the shader keeps the wheels' size when it stretches the body per kind). The body is decimated to about 300 triangles; the wheels are
8-sided prisms with a rim disc.
"""
import bpy, bmesh, sys, os, math
from mathutils import Vector, Matrix

out_dir = sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(out_dir, "rv_sedan.glb"))
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
body = next(o for o in objs if o.name.startswith("Body"))
wheels = [o for o in objs if o.name.startswith("Wheel")]
TAG = {"Body": 0.0, "Glass": 0.25, "Details": 0.55, "Headlights": 0.8, "Taillights": 1.0}

# decimate the body
bpy.context.view_layer.objects.active = body
bm = bmesh.new()
bm.from_mesh(body.data)
bmesh.ops.triangulate(bm, faces=bm.faces)
bm.to_mesh(body.data)
bm.free()
mod = body.modifiers.new("dec", "DECIMATE")
mod.ratio = 0.3
bpy.ops.object.modifier_apply(modifier="dec")
me = body.data
uv = me.uv_layers.new(name="UVMap") if not me.uv_layers else me.uv_layers[0]
for p in me.polygons:
    mname = me.materials[p.material_index].name if me.materials[p.material_index] else "Body"
    tag = 0.0
    for k, v in TAG.items():
        if mname.startswith(k):
            tag = v
    if mname.startswith("Trim"):
        tag = 0.0
    for li in p.loop_indices:
        uv.data[li].uv = (tag, 1.0)
body.data.materials.clear()
mat = bpy.data.materials.new("Near")
body.data.materials.append(mat)
for p in me.polygons:
    p.material_index = 0
    p.use_smooth = False
print("NEAR body tris", len(me.polygons))

# wheels: replace by simple prisms at the same centres
parts = [body]
for w in wheels:
    c = sum((w.matrix_world @ v.co for v in w.data.vertices), Vector()) / len(w.data.vertices)
    zc_gltf = -c.y
    sx = 1.0 if c.x >= 0.0 else -1.0
    for name, tag in (("tyre", 0.45), ("rim", 0.65)):
        bm = bmesh.new()
        if name == "tyre":
            bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=10, radius1=0.36, radius2=0.36, depth=0.26, matrix=Matrix.Rotation(math.pi / 2, 4, "Y"))
        else:                                              # one disc on the outer face (a flat dark-grey rim, the shader paints it)
            bmesh.ops.create_circle(bm, cap_ends=True, cap_tris=False, segments=10, radius=0.2, matrix=Matrix.Translation(Vector((sx * 0.14, 0.0, 0.0))) @ Matrix.Rotation(sx * math.pi / 2, 4, "Y"))
        m = bpy.data.meshes.new("w")
        bm.to_mesh(m)
        bm.free()
        o = bpy.data.objects.new("w", m)
        bpy.context.scene.collection.objects.link(o)
        o.location = c
        uvl = m.uv_layers.new(name="UVMap")
        for p in m.polygons:
            for li in p.loop_indices:
                uvl.data[li].uv = (tag, 1.0 - zc_gltf)
            p.use_smooth = False
        m.materials.append(mat)
        parts.append(o)
for w in wheels:
    bpy.data.objects.remove(w)
bpy.ops.object.select_all(action="DESELECT")
for o in parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
body.name = "NearCar"
tot = len(body.data.polygons)
print("NEAR total tris", sum(len(p.vertices) - 2 for p in body.data.polygons))
bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, "rv_near.glb"), export_format="GLB", export_yup=True, export_apply=True, export_materials="EXPORT")
