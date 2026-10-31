"""Shared pieces of the alien characters (model_player.py "Kestrel", model_operative.py "Vael trooper").

Same skeleton contract as the old humanoid (bones Hips > Torso > Head, UpperArmL/R > ForeArmL/R, Rifle ; Hips > ThighL/R > ShinL/R > FootL/R,
rest rotation identity, head = pivot, model front = +Y in Blender = -Z in Godot), plus an optional secondary chain Sec1 > Sec2 > Sec3 (the hero's
phase cloak hangs from the Torso, the trooper's tail from the Hips) that CharacterRig sways procedurally. ONE skinned mesh, ONE baked atlas material "Gear".
"""
import math

import bpy  # noqa: F401  (must be imported before mathutils)
from mathutils import Vector

from helpers import ring_se

CORE = ["Hips", "Torso", "Head", "UpperArmL", "ForeArmL", "UpperArmR", "ForeArmR", "Rifle",
        "ThighL", "ShinL", "FootL", "ThighR", "ShinR", "FootR"]


def make_finalize(extra_bones):
    """finalize hook for export_model: join the parts into ONE mesh skinned (rigid, weight 1) to an armature with a bone per part."""
    order = CORE + list(extra_bones)

    def finalize(parts, objs, extras):
        bpy.context.view_layer.update()
        by_name = {p.name: p for p in parts}
        for p in parts:
            vg = p.obj.vertex_groups.new(name=p.name)
            vg.add(list(range(len(p.obj.data.vertices))), 1.0, "REPLACE")
        me = bpy.data.meshes.new("Body")
        target = bpy.data.objects.new("Body", me)
        bpy.context.scene.collection.objects.link(target)
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        target.select_set(True)
        bpy.context.view_layer.objects.active = target
        bpy.ops.object.join()
        arm = bpy.data.armatures.new("Rig")
        rig = bpy.data.objects.new("Rig", arm)
        rig.rotation_euler = (math.pi / 2, 0.0, 0.0)
        bpy.context.scene.collection.objects.link(rig)
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = rig
        rig.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        eb = {}
        for name in order:
            p = by_name[name]
            b = arm.edit_bones.new(name)
            b.head = Vector((p.origin.x, p.origin.z, -p.origin.y))
            b.tail = b.head + Vector((0.0, 0.06, 0.0))
            b.roll = 0.0
            if p.parent_name:
                b.parent = eb[p.parent_name]
                b.use_connect = False
            eb[name] = b
        bpy.ops.object.mode_set(mode="OBJECT")
        mod = target.modifiers.new("Armature", "ARMATURE")
        mod.object = rig
        return [target, rig] + list(extras)
    return finalize


def lerp_ring(spec, z):
    """spec: [(z, cy, rx, ry), ...] ascending z -> interpolated (cy, rx, ry) at height z."""
    if z <= spec[0][0]:
        return spec[0][1:]
    for a, b in zip(spec, spec[1:]):
        if z <= b[0]:
            t = (z - a[0]) / (b[0] - a[0])
            return tuple(a[k] * (1 - t) + b[k] * t for k in (1, 2, 3))
    return spec[-1][1:]


def surf_y(spec, z, x=0.0, back=False, exp=2.4):
    """y of the loft surface at height z and lateral offset x (front, or the back when back=True)."""
    cy, rx, ry = lerp_ring(spec, z)
    u = min(abs(x) / rx, 0.999)
    h = ry * (1.0 - u ** exp) ** (1.0 / exp)
    return cy - h if back else cy + h


def xy_rings(spec, n=14, exp=2.4, dx=0.0):
    return [ring_se(dx, cy, z, rx, ry, n, exp, plane="xy") for z, cy, rx, ry in spec]


def two_bone(S, W, l1, l2, pole):
    S, W = Vector(S), Vector(W)
    d = W - S
    dist = min(d.length, (l1 + l2) * 0.995)
    n = d.normalized()
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    p = Vector(pole) - n * Vector(pole).dot(n)
    p.normalize()
    return S + n * a + p * h, S + n * dist
