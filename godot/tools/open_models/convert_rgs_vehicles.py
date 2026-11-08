"""Convert the CC0 "Free Low Poly Vehicles Pack" by Raphael Goncalves (Rgsdev, OpenGameArt) into the game's vehicle model contract (assets/models/rv_<id>.glb).

Run from godot/ with the tool venv (bpy):
    source .venv-tools/bin/activate
    python tools/open_models/convert_rgs_vehicles.py /path/to/"Free Low Poly Vehicles Pack by Rgsdev" assets/models

Contract (same as the other car models, see VehicleVisual.build): the nose points to -Z, the origin is on the ground in the middle of the car, one mesh "Body" with the surfaces
Body (paint, the colour a car is re-tinted with), Details (black trim), Trim (the pack's accent colours), Glass (windows), Headlights, Taillights, and four nodes WheelFL / FR / RL / RR
(the pack's own wheels, origin at the axle; CarParts swaps them for the generated wheel at run time). The car is scaled to the length of its VehicleSpecs entry and its width is
slimmed to the spec width (the pack's cars are wide for their length); the wheels keep their size. Nothing is textured: every surface is a flat colour (no texture memory).
"""
import bpy, sys, os, math
from mathutils import Vector, Matrix

# id -> (pack folder / file name, target length m, target width m)   (kinds of VehicleSpecs: rv key)
MODELS = {
    "sedan": ("Sedan", 4.7, 1.86), "sport": ("Sports", 4.5, 1.92), "compact": ("Hatchback", 3.9, 1.76), "suv": ("SUV", 4.7, 1.98),
    "taxi": ("Taxi", 4.7, 1.86), "van": ("Van", 5.2, 2.0), "truck": ("Truck", 6.4, 2.2), "luxury": ("Limousine", 5.2, 1.95),
    "racer": ("Roadster", 4.2, 1.9), "police": ("Police Sedan", 4.7, 1.95), "ambulance": ("Ambulance", 5.4, 2.05), "bus": ("Bus", 9.5, 2.5),
    "firetruck": ("Firetruck", 7.0, 2.3), "muscle": ("Muscle", 5.0, 1.9), "pickup": ("Pickup", 5.0, 1.95),
}

ROLE_OF = [("window", "Glass"), ("glass", "Glass"), ("headlight", "Headlights"), ("rear light", "Taillights"), ("tail", "Taillights"), ("brake", "Taillights"),
           ("black", "Details"), ("tire", "Details"), ("bumper", "Details"), ("grill", "Details")]


def role(mat_name):
    n = mat_name.lower()
    for key, r in ROLE_OF:
        if key in n:
            return r
    return None


def convert(pack, key, out_dir):
    folder, length, width = MODELS[key]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=os.path.join(pack, folder, folder + ".fbx"))
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    body = max((o for o in objs if "wheel" not in o.name.lower()), key=lambda o: len(o.data.polygons))
    wheels = [o for o in objs if "wheel" in o.name.lower()]
    # ---- scale: everything in world space; the body keeps its place, the wheels are re-centred on their own axle
    bpy.context.view_layer.update()
    for v in body.data.vertices:
        v.co = body.matrix_world @ v.co
    body.matrix_world = Matrix.Identity(4)
    # ---- orient: nose to +Y in Blender (= -Z in glTF). Found from the headlight faces in WORLD space (the FBX import rotates the objects).
    head_y = 0.0
    n_head = 0
    for pg in body.data.polygons:
        m = body.data.materials[pg.material_index]
        if m is not None and "headlight" in m.name.lower():
            head_y += sum(body.data.vertices[i].co.y for i in pg.vertices) / len(pg.vertices)
            n_head += 1
    flip = n_head > 0 and head_y / n_head < 0.0
    xs = [v.co.x for v in body.data.vertices]
    ys = [v.co.y for v in body.data.vertices]
    zs = [v.co.z for v in body.data.vertices]
    s = length / (max(ys) - min(ys))
    kx = width / ((max(xs) - min(xs)) * s)                # spec width = overall width, mirrors included
    zmin = min([min(zs)] + [min((w.matrix_world @ v.co).z for v in w.data.vertices) for w in wheels])
    for v in body.data.vertices:
        v.co = Vector((v.co.x * s * kx, v.co.y * s, (v.co.z - zmin) * s))
    for w in wheels:
        ctr = Vector((sum(v.co.x for v in w.data.vertices), sum(v.co.y for v in w.data.vertices), sum(v.co.z for v in w.data.vertices))) / len(w.data.vertices)
        wc = w.matrix_world @ ctr
        for v in w.data.vertices:
            v.co = (v.co - ctr) * s
        w.matrix_world = Matrix.Translation(Vector((wc.x * s * kx, wc.y * s, (wc.z - zmin) * s)))
    # the pack's wheels sit half inside the body: push each one out until its outer face stands just beyond the flank of the body at that height (mirrors and roof racks do not count)
    for w in wheels:
        t = w.matrix_world.translation
        wr = max(v.co.z for v in w.data.vertices)
        ww = max(v.co.x for v in w.data.vertices) - min(v.co.x for v in w.data.vertices)
        flank = max([abs(v.co.x) for v in body.data.vertices if abs(v.co.y - t.y) < wr and wr * 0.4 < v.co.z < t.z + wr * 0.6] or [abs(t.x)])
        sx = 1.0 if t.x >= 0.0 else -1.0
        w.matrix_world = Matrix.Translation(Vector((sx * (flank - ww * 0.5 + 0.07), t.y, t.z)))
    # a sane wheelbase (0.58 of the length at least): the pack's sports cars have long overhangs
    wb = max(w.matrix_world.translation.y for w in wheels) - min(w.matrix_world.translation.y for w in wheels)
    if wb < 0.58 * length:
        k = 0.58 * length / wb
        for w in wheels:
            t = w.matrix_world.translation
            w.matrix_world = Matrix.Translation(Vector((t.x, t.y * k, t.z)))
    bpy.context.view_layer.update()
    if flip:                                              # a half turn about the vertical axis (x, y -> -x, -y): a proper rotation, normals stay right
        for v in body.data.vertices:
            v.co = Vector((-v.co.x, -v.co.y, v.co.z))
        for w in wheels:
            t = w.matrix_world.translation
            for v in w.data.vertices:
                v.co = Vector((-v.co.x, -v.co.y, v.co.z))
            w.matrix_world = Matrix.Translation(Vector((-t.x, -t.y, t.z)))
        body.data.update()
    # ---- materials -> roles
    roles = {}
    face_role = []
    counts = {}
    for p in body.data.polygons:
        m = body.data.materials[p.material_index]
        r = role(m.name) if m is not None else "Details"
        if r is None:
            counts[p.material_index] = counts.get(p.material_index, 0) + 1
    paint_idx = max(counts, key=counts.get) if counts else 0
    mats = {}
    def mat(name, color, emit=None):
        if name in mats:
            return mats[name]
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
        bsdf.inputs["Roughness"].default_value = 0.5
        if emit is not None:
            bsdf.inputs["Emission Color"].default_value = (emit[0], emit[1], emit[2], 1.0)
            bsdf.inputs["Emission Strength"].default_value = 1.0
        mats[name] = m
        return m
    old = list(body.data.materials)
    slots = {}
    new_index = []
    for p in body.data.polygons:
        m = old[p.material_index] if p.material_index < len(old) else None
        r = role(m.name) if m is not None else "Details"
        col = tuple(m.diffuse_color)[:3] if m is not None else (0.3, 0.3, 0.3)
        if r is None:
            r = "Body" if p.material_index == paint_idx else "Trim"
        if r == "Body":
            new_index.append(("Body", col))
        elif r == "Trim":
            new_index.append(("Trim:" + "%.2f_%.2f_%.2f" % col, col))
        elif r == "Glass":
            new_index.append(("Glass", (0.03, 0.04, 0.06)))
        elif r == "Headlights":
            new_index.append(("Headlights", (1.0, 1.0, 1.0)))
        elif r == "Taillights":
            new_index.append(("Taillights", (1.0, 1.0, 1.0)))
        else:
            new_index.append(("Details", (0.03, 0.03, 0.035)))
    body.data.materials.clear()
    order = []
    for name, col in new_index:
        if name not in order:
            order.append(name)
    for name in order:
        col = next(c for n2, c in new_index if n2 == name)
        emit = (1.0, 0.95, 0.8) if name == "Headlights" else ((1.0, 0.08, 0.05) if name == "Taillights" else None)
        gname = "Trim" if name.startswith("Trim:") else name
        m = mat(name if name.startswith("Trim:") else gname, col, emit)
        m.name = gname if not name.startswith("Trim:") else "Trim" + str(order.index(name))
        body.data.materials.append(m)
    for p, (name, col) in zip(body.data.polygons, new_index):
        p.material_index = order.index(name)
    for w in wheels:
        w.data.materials.clear()
        w.data.materials.append(mat("Details", (0.03, 0.03, 0.035)))
        for p in w.data.polygons:
            p.material_index = 0
    # ---- names
    body.name = "Body"
    body.data.name = "Body"
    bpy.context.view_layer.update()
    for w in wheels:
        front = w.location.y > 0.0
        left = w.location.x < 0.0
        w.name = "Wheel" + ("F" if front else "R") + ("L" if left else "R")
        w.data.name = w.name
    for o in objs:
        o.parent = None
    bpy.ops.object.select_all(action="SELECT")
    # the pack is smooth-shaded per face colour: keep flat shading (low poly look with crisp panel edges)
    for o in objs:
        for p in o.data.polygons:
            p.use_smooth = False
    bbf = [body.matrix_world @ Vector(c) for c in body.bound_box]
    out = os.path.join(out_dir, "rv_%s.glb" % key)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True, export_apply=True, export_materials="EXPORT")
    size = (max(v.x for v in bbf) - min(v.x for v in bbf), max(v.z for v in bbf) - min(v.z for v in bbf), max(v.y for v in bbf) - min(v.y for v in bbf))
    wr = max((max(v.co.z for v in w.data.vertices) - min(v.co.z for v in w.data.vertices)) * 0.5 for w in wheels) if wheels else 0.0
    print("RGS %-10s len %.2f wid %.2f hgt %.2f wheel r %.3f paint %s flip %s tris %d" % (key, size[2], size[0], size[1], wr, old[paint_idx].name, flip, sum(len(p.vertices) - 2 for p in body.data.polygons)))


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[-2:]
    pack, out_dir = args[0], args[1]
    os.makedirs(out_dir, exist_ok=True)
    only = os.environ.get("ONLY", "").split(",") if os.environ.get("ONLY") else list(MODELS)
    for k in only:
        convert(pack, k, out_dir)
