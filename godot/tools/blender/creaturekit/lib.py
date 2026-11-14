"""Creature builder of the enemy roster (wave 113, enemy look v3): organic and hard-surface bodies from a bone list and a few primitives, skinned in Blender, with procedural clips,
exported as ONE skinned mesh per species (assets/models/foes/<id>.glb) that AlienCreature / RosterFoe play through an AnimationPlayer (clips: idle walk run attack hit dead jump).

Blender axes: x = the creature's right, y = forward, z = up, metres, feet at z = 0 (the exporter turns +Y into glTF -Z, the game's front).
Vertex data: COLOR_0 = paint (sRGB-looking RGB, baked ambient occlusion already multiplied in) + alpha = the GLOW MASK of assets/shaders/alien.gdshader (eyes, seams, tips, cores).
Skinning: every piece names the bones it may follow; a vertex takes the inverse-distance weights of the (at most three) nearest of them, so a tube across a joint bends smoothly and a plate stays rigid.
Clips: rotations are given about ARMATURE axes (x lateral, y forward, z up), whatever the roll of the bone, and converted to the bone's local frame here.
"""
import math
import os
import sys

import bmesh
import bpy  # noqa: F401
from mathutils import Euler, Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import helpers  # noqa: E402  (MODELS_DIR)

FPS = 30
R = math.radians


def lerp(a, b, t):
    return a + (b - a) * t


def v3(p):
    return Vector((p[0], p[1], p[2]))


class Creature:
    def __init__(self, name):
        self.name = name
        self.bones = {}                    # name -> {head, tail, parent}
        self.order = []
        self.pieces = []                   # {verts: [Vector], faces: [(i..)], colors: [(r,g,b,a)], bones: [names], smooth: bool}
        self.clips = {}

    # ---- skeleton --------------------------------------------------------------------------------------------------------------
    def bone(self, name, head, tail, parent=None):
        h, t = v3(head), v3(tail)
        if (t - h).length < 0.03:
            t = h + Vector((0.0, 0.0, 0.03))
        self.bones[name] = {"head": h, "tail": t, "parent": parent}
        self.order.append(name)

    # ---- pieces ------------------------------------------------------------------------------------------------------------------
    def _add(self, verts, faces, color, bones, smooth=True, glow=0.0, vcolors=None):
        cols = []
        for i in range(len(verts)):
            c = vcolors[i] if vcolors is not None else color
            cols.append((c[0], c[1], c[2], glow if len(c) < 4 else c[3] + glow))
        self.pieces.append({"verts": [v3(v) for v in verts], "faces": faces, "colors": cols, "bones": list(bones), "smooth": smooth})

    def ellipsoid(self, c, r, color, bones, rot=(0, 0, 0), segs=10, rings=6, glow=0.0, smooth=True, tint=None):
        """r = (rx, ry, rz). rot in degrees about x, y, z (applied about the centre). `tint`: (top, bottom) colour multipliers (a cheap light-from-above baked into the paint)."""
        verts, faces, cols = [], [], []
        m = Euler((R(rot[0]), R(rot[1]), R(rot[2])), "XYZ").to_matrix()
        cx, cy, cz = c
        for k in range(rings + 1):
            th = math.pi * k / rings
            for j in range(segs):
                ph = 2.0 * math.pi * j / segs
                p = Vector((r[0] * math.sin(th) * math.cos(ph), r[1] * math.sin(th) * math.sin(ph), r[2] * math.cos(th)))
                p = m @ p
                verts.append((cx + p.x, cy + p.y, cz + p.z))
                if tint is not None:
                    t = 0.5 + 0.5 * math.cos(th)
                    k2 = lerp(tint[1], tint[0], t)
                    cols.append((color[0] * k2, color[1] * k2, color[2] * k2))
        for k in range(rings):
            for j in range(segs):
                a, b = k * segs + j, k * segs + (j + 1) % segs
                faces.append((a, a + segs, b + segs, b))
        self._add(verts, faces, color, bones, smooth, glow, cols if tint is not None else None)

    def tube(self, pts, radii, color, bones, segs=8, glow=0.0, color_end=None, caps=True, smooth=True, flat=0.0, glow_end=None):
        """A lofted tube through `pts` (at least two points) with the radius per point. color_end blends the paint to the tip; glow_end the glow mask. flat squashes the cross section (0..0.9) in x."""
        pts = [v3(p) for p in pts]
        n = len(pts)
        verts, faces, cols = [], [], []
        for i in range(n):
            if i == 0:
                d = pts[1] - pts[0]
            elif i == n - 1:
                d = pts[i] - pts[i - 1]
            else:
                d = pts[i + 1] - pts[i - 1]
            d.normalize()
            ref = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((0, 1, 0))
            u = d.cross(ref).normalized()
            w = d.cross(u).normalized()
            t = i / max(n - 1, 1)
            for j in range(segs):
                a = 2.0 * math.pi * j / segs
                p = pts[i] + u * (math.cos(a) * radii[i] * (1.0 - flat)) + w * (math.sin(a) * radii[i])
                verts.append(p)
                cc = color if color_end is None else tuple(lerp(color[k], color_end[k], t) for k in range(3))
                g = glow if glow_end is None else lerp(glow, glow_end, t)
                cols.append((cc[0], cc[1], cc[2], g))
        for i in range(n - 1):
            for j in range(segs):
                a, b = i * segs + j, i * segs + (j + 1) % segs
                faces.append((a, b, b + segs, a + segs))
        if caps:
            for end, ring in ((0, 0), (1, n - 1)):
                ci = len(verts)
                verts.append(pts[ring])
                cols.append(cols[ring * segs])
                for j in range(segs):
                    a, b = ring * segs + j, ring * segs + (j + 1) % segs
                    faces.append((a, b, ci) if end == 0 else (b, a, ci))
        self.pieces.append({"verts": verts, "faces": faces, "colors": cols, "bones": list(bones), "smooth": smooth})

    def cone(self, base, tip, r, color, bones, segs=5, glow=0.0, tip_glow=None, color_tip=None):
        self.tube([base, tip], [r, 0.004], color, bones, segs=segs, glow=glow, glow_end=tip_glow, color_end=color_tip, caps=True, smooth=False)

    def box(self, c, size, color, bones, rot=(0, 0, 0), glow=0.0, taper=(1.0, 1.0)):
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        m = Euler((R(rot[0]), R(rot[1]), R(rot[2])), "XYZ").to_matrix()
        loc = [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
               (-hx * taper[0], -hy * taper[1], hz), (hx * taper[0], -hy * taper[1], hz), (hx * taper[0], hy * taper[1], hz), (-hx * taper[0], hy * taper[1], hz)]
        verts = []
        for p in loc:
            q = m @ Vector(p)
            verts.append((c[0] + q.x, c[1] + q.y, c[2] + q.z))
        faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        # duplicate the vertices per face so every face is flat shaded
        v2, f2, c2 = [], [], []
        for f in faces:
            base = len(v2)
            for i in f:
                v2.append(verts[i])
            f2.append((base, base + 1, base + 2, base + 3))
        self._add(v2, f2, color, bones, False, glow)

    # ---- clips -------------------------------------------------------------------------------------------------------------------
    def clip(self, name, frames, fn, loop=True):
        """fn(t01, pose) is called for frames+1 samples (t01 = 0..1, the last sample equals the first for a loop); `pose` collects rot(bone, x, y, z) in degrees and move(bone, x, y, z) in metres."""
        self.clips[name] = (frames, fn, loop)

    # ---- build -------------------------------------------------------------------------------------------------------------------
    def build(self, ao=True):
        scene_objs = []
        arm = bpy.data.armatures.new(self.name + "_arm")
        arm_obj = bpy.data.objects.new(self.name, arm)
        bpy.context.scene.collection.objects.link(arm_obj)
        bpy.context.view_layer.objects.active = arm_obj
        bpy.ops.object.mode_set(mode="EDIT")
        for n in self.order:
            b = self.bones[n]
            eb = arm.edit_bones.new(n)
            eb.head, eb.tail = b["head"], b["tail"]
            eb.roll = 0.0
        for n in self.order:
            p = self.bones[n]["parent"]
            if p:
                arm.edit_bones[n].parent = arm.edit_bones[p]
        bpy.ops.object.mode_set(mode="OBJECT")
        # mesh
        bm = bmesh.new()
        col = bm.loops.layers.float_color.new("Col")
        weights = []                      # per vertex [(bone, w)]
        seg = {n: (self.bones[n]["head"], self.bones[n]["tail"]) for n in self.bones}
        for pc in self.pieces:
            vs = [bm.verts.new(p) for p in pc["verts"]]
            local = {v: i for i, v in enumerate(vs)}
            for i, p in enumerate(pc["verts"]):
                cand = []
                for bn in pc["bones"]:
                    h, t = seg[bn]
                    d = t - h
                    s = max(0.0, min(1.0, (p - h).dot(d) / max(d.length_squared, 1e-9)))
                    dist = (h + d * s - p).length
                    cand.append((dist, bn))
                cand.sort()
                cand = cand[:3]
                if len(cand) == 1:
                    weights.append([(cand[0][1], 1.0)])
                else:
                    ws = [(bn, 1.0 / (d + 0.02) ** 3) for d, bn in cand]
                    tot = sum(w for _, w in ws)
                    weights.append([(bn, w / tot) for bn, w in ws if w / tot > 0.05])
            for f in pc["faces"]:
                try:
                    face = bm.faces.new([vs[i] for i in f])
                except ValueError:
                    continue
                face.smooth = pc["smooth"]
                for lo in face.loops:
                    lo[col] = pc["colors"][local[lo.vert]]
        bm.verts.index_update()
        bm.verts.ensure_lookup_table()
        bm.normal_update()
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        if ao:
            self._ao(bm, col)
        me = bpy.data.meshes.new(self.name)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(self.name + "_mesh", me)
        bpy.context.scene.collection.objects.link(ob)
        for n in self.order:
            ob.vertex_groups.new(name=n)
        for vi, ws in enumerate(weights):
            for bn, w in ws:
                ob.vertex_groups[bn].add([vi], w, "REPLACE")
        ob.parent = arm_obj
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = arm_obj
        # clips
        self._clips(arm_obj, arm)
        return arm_obj, ob

    def _ao(self, bm, col):
        tree = BVHTree.FromBMesh(bm)
        dirs = []
        ga = math.pi * (3.0 - math.sqrt(5.0))
        for i in range(12):
            u = (i + 0.5) / 12
            rr = math.sqrt(u)
            dirs.append((rr * math.cos(ga * i), rr * math.sin(ga * i), math.sqrt(1.0 - u)))
        ao = {}
        for v in bm.verts:
            n = v.normal.copy()
            if n.length < 1e-6:
                n = Vector((0, 0, 1))
            n.normalize()
            o = v.co + n * 0.01
            t1 = n.cross(Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((1, 0, 0))).normalized()
            t2 = n.cross(t1)
            occ = 0.0
            for d in dirs:
                dv = t1 * d[0] + t2 * d[1] + n * d[2]
                h = tree.ray_cast(o, dv, 0.25)
                if h[0] is not None:
                    occ += 1.0 - h[3] / 0.25
            ao[v.index] = 1.0 - 0.8 * occ / len(dirs)
        for f in bm.faces:
            for lo in f.loops:
                a = ao[lo.vert.index]
                c = lo[col]
                k = 0.5 + 0.5 * a
                lo[col] = (c[0] * k, c[1] * k, c[2] * k, c[3])

    def _clips(self, arm_obj, arm):
        bpy.context.view_layer.objects.active = arm_obj
        bpy.ops.object.mode_set(mode="POSE")
        arm_obj.animation_data_create()
        rest = {n: arm.bones[n].matrix_local.to_3x3() for n in self.order}
        for pb in arm_obj.pose.bones:
            pb.rotation_mode = "XYZ"

        class Pose:
            def __init__(s):
                s.r = {}
                s.m = {}
                s.s = {}

            def scale(s, bone, x=1.0, y=1.0, z=1.0):
                if bone in rest:
                    s.s[bone] = (x, y, z)

            def rot(s, bone, x=0.0, y=0.0, z=0.0):
                if bone in rest:
                    prev = s.r.get(bone, (0.0, 0.0, 0.0))
                    s.r[bone] = (prev[0] + x, prev[1] + y, prev[2] + z)

            def move(s, bone, x=0.0, y=0.0, z=0.0):
                if bone in rest:
                    prev = s.m.get(bone, (0.0, 0.0, 0.0))
                    s.m[bone] = (prev[0] + x, prev[1] + y, prev[2] + z)

        for name, (frames, fn, loop) in self.clips.items():
            act = bpy.data.actions.new(name)
            act.use_fake_user = True
            arm_obj.animation_data.action = act
            for f in range(frames + 1):
                t = f / frames
                p = Pose()
                fn(t, p)
                for pb in arm_obj.pose.bones:
                    n = pb.name
                    rb = rest[n]
                    if n in p.r:
                        a = Euler((R(p.r[n][0]), R(p.r[n][1]), R(p.r[n][2])), "XYZ").to_matrix()
                        loc = rb.inverted() @ a @ rb
                        pb.rotation_euler = loc.to_euler("XYZ")
                    else:
                        pb.rotation_euler = (0.0, 0.0, 0.0)
                    if n in p.m:
                        pb.location = rb.inverted() @ Vector(p.m[n])
                    else:
                        pb.location = (0.0, 0.0, 0.0)
                    pb.scale = p.s.get(n, (1.0, 1.0, 1.0))
                    pb.keyframe_insert("rotation_euler", frame=f + 1)
                    pb.keyframe_insert("location", frame=f + 1)
                    pb.keyframe_insert("scale", frame=f + 1)
        for pb in arm_obj.pose.bones:
            pb.rotation_euler = (0.0, 0.0, 0.0)
            pb.location = (0.0, 0.0, 0.0)
            pb.scale = (1.0, 1.0, 1.0)
        bpy.ops.object.mode_set(mode="OBJECT")
        arm_obj.animation_data.action = None


def export(arm_obj, mesh_obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    arm_obj.select_set(True)
    mesh_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False, export_yup=True, export_materials="NONE", export_extras=False,
                              export_cameras=False, export_lights=False, export_animations=True, export_animation_mode="ACTIONS", export_skins=True, export_morph=False,
                              export_texcoords=False, export_vertex_color="ACTIVE", export_force_sampling=True, export_optimize_animation_size=False)


# ------------------------------------------------------------------------------------------------------------------------------------------------
# organic bodies from a stick figure: the Skin modifier gives one continuous, variable-thickness surface (no ball joints), subdivided and decimated to a triangle target
# ------------------------------------------------------------------------------------------------------------------------------------------------

def skin_mesh(nodes, edges, subdiv=2, target_tris=1800):
    """nodes: [(pos, (rx, ry))], edges: [(i, j)]. Returns (verts [Vector], faces [tuple], normals [Vector]) of the evaluated, decimated mesh."""
    me = bpy.data.meshes.new("skin_tmp")
    me.from_pydata([tuple(n[0]) for n in nodes], [tuple(e) for e in edges], [])
    ob = bpy.data.objects.new("skin_tmp", me)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    with bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob]):
        bpy.ops.object.modifier_add(type="SKIN")
    layer = me.skin_vertices[0].data
    for i, n in enumerate(nodes):
        layer[i].radius = (n[1][0], n[1][1])
    layer[0].use_root = True
    skin = ob.modifiers["Skin"]
    skin.branch_smoothing = 0.9
    sub = ob.modifiers.new("Sub", "SUBSURF")
    sub.levels = subdiv
    sub.render_levels = subdiv
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    tmp = ev.to_mesh()
    tris = sum(len(p.vertices) - 2 for p in tmp.polygons)
    ev.to_mesh_clear()
    dec = ob.modifiers.new("Dec", "DECIMATE")
    dec.ratio = max(0.05, min(1.0, target_tris / max(tris, 1)))
    dec.use_collapse_triangulate = False
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    m2 = ev.to_mesh()
    m2.calc_loop_triangles()
    m2.calc_normals_split() if hasattr(m2, "calc_normals_split") else None
    verts = [v.co.copy() for v in m2.vertices]
    normals = [v.normal.copy() for v in m2.vertices]
    faces = [tuple(p.vertices) for p in m2.polygons]
    ev.to_mesh_clear()
    bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.meshes.remove(me)
    return verts, faces, normals


def add_skin_piece(c, nodes, edges, color_fn, bones, subdiv=2, target_tris=1800, glow_fn=None):
    """Adds the evaluated skin mesh to the creature as one piece; color_fn(pos, normal) -> (r, g, b) paint, glow_fn(pos, normal) -> 0..1 mask."""
    verts, faces, normals = skin_mesh(nodes, edges, subdiv, target_tris)
    cols = []
    for p, n in zip(verts, normals):
        rgb = color_fn(p, n)
        g = glow_fn(p, n) if glow_fn else 0.0
        cols.append((rgb[0], rgb[1], rgb[2], g))
    c.pieces.append({"verts": verts, "faces": faces, "colors": cols, "bones": list(bones), "smooth": True})
