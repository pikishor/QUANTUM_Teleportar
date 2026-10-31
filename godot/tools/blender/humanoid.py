"""Procedural tactical operative (shared by model_player.py and model_operative.py), an articulated character in ONE skinned mesh.

Layout (Blender axes, model front = +Y, which becomes -Z in Godot):
  Body (mesh, 1 surface = 1 draw call) skinned to an armature whose bones are the rigid parts, every vertex 100 % on one bone:
    Hips > Torso > Head, UpperArmL/R > ForeArmL/R, Rifle ;  Hips > ThighL/R > ShinL/R > FootL/R
  Every bone is axis aligned (rest rotation = identity), its head is the pivot: the game poses the bones procedurally (scripts/characters/character_rig.gd).
  Empties at the root: Muzzle (rifle tip), WristL / WristR (where the glove cuffs meet the rifle), MagWell, MagPouch; Fill / Rim: markers that become lights at import.
All parts share ONE baked atlas material "Gear". Height 1.82 m with helmet, feet on y = 0.
"""
import math

import bpy  # noqa: F401  (must be imported before mathutils)
from mathutils import Matrix, Vector

from helpers import (Part, empty, export_model, hexc, light, make_material, new_scene, paint, ring_se, rotm,
                     scale_c, xform)
from shade import Decal, p_barcode, p_box, p_chevrons, p_glyphs, p_ring, p_stripes


def two_bone(S, W, l1, l2, pole):
    """Elbow position for a shoulder S and a wrist target W (arm lengths l1, l2); returns (elbow, wrist)."""
    S, W = Vector(S), Vector(W)
    d = W - S
    dist = min(d.length, (l1 + l2) * 0.995)
    n = d.normalized()
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    p = Vector(pole) - n * Vector(pole).dot(n)
    p.normalize()
    return S + n * a + p * h, S + n * dist


def helmet_rings(cy, cz, a, b, c, k=9, n=22, phi_front=71.0, phi_side=115.0, phi_back=130.0, top=5.0):
    """Ellipsoid dome whose rim height varies around the head (high at the brow, low at the nape)."""
    rings = []
    for j in range(k + 1):
        t = j / k
        ring = []
        for i in range(n):
            th = 2 * math.pi * i / n          # 0 = front (+Y)
            cf = math.cos(th)
            rim = phi_side - (phi_side - phi_front) * max(0.0, cf) + (phi_back - phi_side) * max(0.0, -cf)
            phi = math.radians(rim * (1 - t) + top * t)
            s = math.sin(phi)
            ring.append((a * s * -math.sin(th), cy + b * s * cf, cz + c * math.cos(phi)))
        rings.append(ring)
    return rings


def arc_rings(cx, cy, rx, ry, zs, a0, a1, n=9):
    """Open arc rings (front visor): angle measured from +Y, a0 -> a1 degrees, one ring per z."""
    rings = []
    for z in zs:
        ring = []
        for i in range(n):
            a = math.radians(a0 + (a1 - a0) * i / (n - 1))
            ring.append((cx + rx * math.sin(a), cy + ry * math.cos(a), z))
        rings.append(ring)
    return rings


class RigPart(Part):
    """A Part that becomes one bone of the armature (see rig_finalize)."""

    def __init__(self, name, origin, parent=None, seed=1):
        super().__init__(name, origin=origin, seed=seed)
        self.parent_name = parent


BONE_ORDER = ["Hips", "Torso", "Head", "UpperArmL", "ForeArmL", "UpperArmR", "ForeArmR", "Rifle",
              "ThighL", "ShinL", "FootL", "ThighR", "ShinR", "FootR"]


def rig_finalize(parts, objs, extras):
    """Join the built part meshes into ONE mesh skinned (rigid, weight 1) to an armature with a bone per part; returns the export list."""
    bpy.context.view_layer.update()
    by_name = {p.name: p for p in parts}
    for p in parts:                                              # one vertex group per bone, every vertex on it
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
    # armature: its object is rotated +90 degrees about X and the bone coordinates are the glTF ones (x, z, -y), so the exporter's Y-up
    # conversion cancels out and every bone frame is the Godot frame (x right, y up, -z forward); the bones point along local +Y with roll 0,
    # which makes every rest rotation the identity and the head the pivot
    arm = bpy.data.armatures.new("Rig")
    rig = bpy.data.objects.new("Rig", arm)
    rig.rotation_euler = (math.pi / 2, 0.0, 0.0)
    bpy.context.scene.collection.objects.link(rig)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}
    for name in BONE_ORDER:
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


def build(S):
    new_scene()
    bulk = S.get("bulk", 1.0)
    heavy = S.get("heavy", False)
    fab = make_material("Fabric", tex="fabric")
    armor = make_material("Armor", tex="plating")
    gun = make_material("Gunmetal", tex="steel")
    visor = make_material("Visor", tex="glass", color=(0.014, 0.028, 0.036))
    glow = make_material("Glow", tex="glow", color=S["accent"])

    bright = S.get("bright", 1.0)                 # lifts every tint: the baked wear and AO darken, a character must stay readable at night

    def P(tex, h):
        return scale_c(paint(tex, h), bright)

    uni = P("fabric", S["uniform"])
    pants = P("fabric", S["pants"])
    carr = P("fabric", S["carrier"])
    carr2 = P("fabric", S["carrier2"])
    glove = P("fabric", S["glove"])
    boot = P("fabric", S["boot"])
    pl = P("plating", S["plate"])
    hel = P("plating", S["helmet"])
    trim = scale_c(paint("plating", S["trim"]), min(bright, 1.2))
    mask = P("plating", S.get("mask", S["trim"]))
    gm = P("steel", S["metal"])
    gm2 = P("steel", S["metal2"])
    sole = P("fabric", S.get("sole", "#26292c"))

    # joints (Blender axes: x right, y front, z up)
    HIP = (0.0, 0.0, 0.93)
    WAIST = (0.0, 0.012, 1.06)
    NECK = (0.0, 0.012, 1.52)
    RIFLE_O = (0.118, 0.14, 1.365)
    hips = RigPart("Hips", HIP, None, seed=3)
    torso = RigPart("Torso", WAIST, "Hips", seed=5)
    head = RigPart("Head", NECK, "Torso", seed=9)
    rifle = RigPart("Rifle", RIFLE_O, "Torso", seed=11)
    thigh, shin, foot, uarm, farm = {}, {}, {}, {}, {}
    for s, side in ((-1, "L"), (1, "R")):
        x0 = 0.098 * s * (1.0 + (bulk - 1.0) * 0.4)
        thigh[s] = RigPart("Thigh" + side, (x0, 0.0, 0.93), "Hips", seed=7 + s)
        shin[s] = RigPart("Shin" + side, (x0 + 0.003 * s, 0.03, 0.50), "Thigh" + side, seed=21 + s)
        foot[s] = RigPart("Foot" + side, (x0 + 0.008 * s, -0.004, 0.10), "Shin" + side, seed=31 + s)

    # ------------------------------------------------------------------ legs
    for s in (-1, 1):
        x0 = 0.098 * s * (1.0 + (bulk - 1.0) * 0.4)
        p, q, f = thigh[s], shin[s], foot[s]
        # thigh: pants, cargo pocket, knee-joint ball, hip-side gear
        p.tube([(x0, 0.0, 0.95), (x0 + 0.004 * s, 0.012, 0.76), (x0 + 0.006 * s, 0.022, 0.62), (x0 + 0.003 * s, 0.03, 0.51)],
               [(0.108 * bulk, 0.116 * bulk), (0.100 * bulk, 0.108 * bulk), (0.083 * bulk, 0.089 * bulk), (0.066, 0.07)], mat=fab, tint=pants, n=12, exp=2.2, sub=3, jitter=0.02)
        p.sphere(0.066, (x0 + 0.003 * s, 0.03, 0.50), mat=fab, tint=pants, segs=10, rings=7)
        p.box((0.036, 0.12, 0.16), (x0 + s * 0.108 * bulk, 0.02, 0.72), mat=fab, tint=carr, bevel=0.007, bsegs=1, jitter=0.06)
        p.box((0.038, 0.12, 0.03), (x0 + s * 0.109 * bulk, 0.02, 0.795), mat=fab, tint=carr2, bevel=0.005, jitter=0.04)
        p.box((0.01, 0.1, 0.012), (x0 + s * 0.128 * bulk, 0.02, 0.775), mat=armor, tint=trim)
        p.box((0.115, 0.075, 0.022), (x0, 0.046, 0.555), mat=fab, tint=carr2, bevel=0.006)                # knee strap
        if S.get("light_glow"):
            p.box((0.008, 0.012, 0.2), (x0 + s * 0.118 * bulk, 0.065, 0.66), mat=glow)                  # thigh light strip
        if s == 1:                                                                   # drop-leg holster on the right
            p.box((0.05, 0.1, 0.2), (x0 + s * 0.108 * bulk, 0.045, 0.60), mat=fab, tint=carr2, bevel=0.01, bsegs=1, jitter=0.05)
            p.box((0.046, 0.075, 0.09), (x0 + s * 0.108 * bulk, 0.05, 0.68), mat=armor, tint=trim, bevel=0.007)
            p.box((0.118, 0.03, 0.03), (x0 + s * 0.012, 0.02, 0.78), mat=fab, tint=carr2, bevel=0.005)
        else:                                                                        # medical pouch on the left
            p.box((0.05, 0.095, 0.11), (x0 + s * 0.108 * bulk, 0.02, 0.58), mat=fab, tint=carr, bevel=0.009, jitter=0.05)
            p.box((0.012, 0.03, 0.04), (x0 + s * 0.136 * bulk, 0.02, 0.6), mat=armor, tint=trim)
        if heavy:                                                                    # armoured thigh plate
            p.box((0.034, 0.15, 0.26), (x0 + s * 0.112 * bulk, 0.042, 0.70), mat=armor, tint=pl, bevel=0.012, bsegs=2, top=(0.86, 1.0), jitter=0.04)
            p.box((0.012, 0.14, 0.03), (x0 + s * 0.132 * bulk, 0.042, 0.80), mat=armor, tint=trim, bevel=0.004)
        # shin: trouser, shin guard, knee pad (cap + wings), boot shaft
        q.tube([(x0 + 0.003 * s, 0.03, 0.52), (x0 + 0.004 * s, 0.018, 0.40), (x0 + 0.006 * s, 0.002, 0.30), (x0 + 0.008 * s, -0.004, 0.17)],
               [(0.066, 0.07), (0.064, 0.078), (0.057, 0.066), (0.052, 0.056)], mat=fab, tint=pants, n=12, exp=2.2, sub=2)
        q.sphere(0.064, (x0 + 0.003 * s, 0.03, 0.50), mat=fab, tint=pants, segs=10, rings=7)
        q.box((0.112, 0.07, 0.15), (x0 + 0.003 * s, 0.092, 0.50), mat=armor, tint=pl, bevel=0.016, bsegs=2, top=(0.92, 0.9), jitter=0.05)       # knee pad
        q.box((0.066, 0.02, 0.07), (x0 + 0.003 * s, 0.128, 0.50), mat=armor, tint=trim, bevel=0.006, bsegs=1)
        q.box((0.08, 0.03, 0.2), (x0 + 0.006 * s, 0.066, 0.31), mat=armor, tint=pl, bevel=0.01, bsegs=1, top=(0.9, 1.0), jitter=0.05)       # shin guard
        if heavy:
            q.box((0.084, 0.012, 0.05), (x0 + 0.006 * s, 0.083, 0.37), mat=armor, tint=trim, bevel=0.004)
        q.tube([(x0 + 0.006 * s, -0.005, 0.24), (x0 + 0.006 * s, -0.005, 0.12)], [(0.060, 0.064), (0.062, 0.068)], mat=fab, tint=boot, n=12, exp=2.4, sub=0)
        q.box((0.1, 0.012, 0.03), (x0 + 0.006 * s, 0.062, 0.19), mat=fab, tint=carr2, bevel=0.004)                 # boot strap
        # foot: lofted boot + sole + heel
        rings = [ring_se(x0 + 0.008 * s, y, zc, rx, rz, 12, 2.6, plane="xz") for y, rx, rz, zc in
                 [(-0.100, 0.046, 0.050, 0.083), (-0.050, 0.058, 0.054, 0.080), (0.040, 0.059, 0.045, 0.067),
                  (0.130, 0.054, 0.036, 0.056), (0.205, 0.042, 0.029, 0.048)]]
        f.loft(rings, mat=fab, tint=boot, caps=(True, True), jitter=0.03)
        f.box((0.12, 0.31, 0.03), (x0 + 0.008 * s, 0.047, 0.015), mat=fab, tint=sole, bevel=0.01, bsegs=2)
        f.box((0.122, 0.07, 0.03), (x0 + 0.008 * s, -0.07, 0.015), mat=fab, tint=sole, bevel=0.008)
        f.box((0.075, 0.1, 0.022), (x0 + 0.008 * s, 0.17, 0.059), mat=armor, tint=pl, bevel=0.008, top=(0.9, 0.8))   # toe cap

    # ------------------------------------------------------------------ pelvis and belt (Hips)
    hp = hips
    pr = [ring_se(0, 0.0, z, rx * bulk, ry * bulk, 14, 2.4) for z, rx, ry in
          [(0.83, 0.172, 0.115), (0.90, 0.200, 0.128), (1.00, 0.190, 0.122), (1.08, 0.176, 0.116)]]
    hp.loft(pr, mat=fab, tint=pants, jitter=0.0)
    br = [ring_se(0, 0.0, z, rx * bulk, ry * bulk, 18, 3.0) for z, rx, ry in [(0.975, 0.198, 0.134), (1.03, 0.2, 0.136)]]
    hp.loft(br, mat=fab, tint=boot)
    hp.box((0.05, 0.016, 0.045), (0, 0.137 * bulk, 1.0), mat=gun, tint=gm, bevel=0.004)
    hp.box((0.052, 0.09, 0.17), (0.215 * bulk, 0.02, 0.9), mat=fab, tint=carr2, bevel=0.008, bsegs=1, jitter=0.05)
    hp.box((0.046, 0.075, 0.075), (0.215 * bulk, 0.02, 0.985), mat=gun, tint=gm2, bevel=0.006)
    hp.box((0.05, 0.07, 0.11), (-0.205 * bulk, -0.05, 0.99), mat=fab, tint=carr, bevel=0.007, jitter=0.07)
    hp.box((0.15, 0.04, 0.05), (0, -0.138 * bulk, 0.99), mat=fab, tint=carr2, bevel=0.006)                    # rear belt pouch
    if heavy:
        hp.box((0.15, 0.045, 0.17), (0, 0.145 * bulk, 0.865), mat=armor, tint=pl, bevel=0.012, bsegs=2, top=(0.8, 1.0), jitter=0.04)   # groin guard
        hp.box((0.04, 0.12, 0.15), (0.228 * bulk, 0.0, 0.85), mat=armor, tint=pl, bevel=0.01, bsegs=1, mirror=True, jitter=0.04)

    # ------------------------------------------------------------------ torso: shirt, plate carrier, plates, pouches, pack
    t = torso
    tr = [ring_se(0, 0.012, z, rx * bulk, ry * bulk, 16, 2.3) for z, rx, ry in
          [(1.06, 0.172, 0.116), (1.18, 0.178, 0.121), (1.32, 0.190, 0.131), (1.44, 0.206, 0.126), (1.505, 0.176, 0.104)]]
    t.loft(tr, mat=fab, tint=uni)
    vr = [ring_se(0, 0.012, z, rx * bulk, ry * bulk, 18, 3.2) for z, rx, ry in
          [(1.135, 0.198, 0.146), (1.22, 0.205, 0.153), (1.36, 0.215, 0.160), (1.45, 0.220, 0.150), (1.485, 0.200, 0.126)]]
    t.loft(vr, mat=fab, tint=carr)
    cr = [ring_se(0, 0.012, z, rx * bulk, ry * bulk, 18, 3.0) for z, rx, ry in
          [(1.075, 0.196, 0.142), (1.105, 0.208, 0.152), (1.20, 0.210, 0.156), (1.235, 0.200, 0.148)]]
    t.loft(cr, mat=fab, tint=carr2)
    t.box((0.285 * bulk, 0.034, 0.325), (0, 0.18 * bulk, 1.335), mat=armor, tint=pl, bevel=0.012, bsegs=2, top=(0.9, 1.0), jitter=0.04)
    t.box((0.285 * bulk, 0.032, 0.325), (0, -0.154 * bulk, 1.335), mat=armor, tint=pl, bevel=0.012, bsegs=2, top=(0.9, 1.0), jitter=0.04)
    for z in (1.205, 1.245, 1.425, 1.465):                                                        # MOLLE webbing
        t.box((0.30 * bulk, 0.008, 0.016), (0, 0.178 * bulk + 0.01, z), mat=fab, tint=carr2, jitter=0.05)
    for x in (-0.085, 0.0, 0.085):                                                                 # magazine pouches with flaps
        t.box((0.074, 0.05, 0.125), (x, 0.176 * bulk, 1.105), mat=fab, tint=carr, bevel=0.007, bsegs=1, jitter=0.08)
        t.box((0.077, 0.014, 0.055), (x, 0.205 * bulk, 1.145), mat=fab, tint=carr2, bevel=0.005, jitter=0.05)
        t.box((0.016, 0.01, 0.025), (x, 0.213 * bulk, 1.12), mat=gun, tint=gm2)
    t.box((0.058, 0.042, 0.10), (-0.105, 0.207 * bulk, 1.395), mat=fab, tint=carr2, bevel=0.007, jitter=0.06)       # radio pouch
    t.box((0.095, 0.03, 0.065), (0.085, 0.204 * bulk, 1.415), mat=fab, tint=carr, bevel=0.006, jitter=0.06)
    t.box((0.012, 0.01, 0.012), (-0.105, 0.233 * bulk, 1.43), mat=glow)
    t.box((0.05, 0.075, 0.115), (0.215 * bulk, 0.045, 1.14), mat=fab, tint=carr, bevel=0.008, mirror=True, jitter=0.07)  # side pouches
    t.tube([(0.115, 0.13, 1.455), (0.125, 0.0, 1.522), (0.115, -0.12, 1.455)], [(0.013, 0.034), (0.013, 0.034), (0.013, 0.034)],
           mat=fab, tint=carr2, n=8, exp=4.0, sub=3, mirror=True)                                  # shoulder straps
    if S.get("light_glow"):                                                                        # chest status light bar
        t.box((0.1, 0.01, 0.01), (0, 0.2 * bulk + 0.012, 1.215), mat=glow)
    if heavy:                                                                                      # crimson sash across the plate carrier
        t.bar((-0.17 * bulk, 0.198 * bulk + 0.012, 1.46), (0.15 * bulk, 0.2 * bulk + 0.012, 1.15), 0.05, 0.012, mat=armor, tint=trim, up=(0, 1, 0), bevel=0.003)
    t.tube([(0, 0.01, 1.50), (0, 0.012, 1.525)], [(0.15, 0.115), (0.105, 0.098)], mat=fab, tint=carr, n=16, exp=2.2, sub=0)      # trapezius slope
    t.tube([(0, 0.01, 1.50), (0, 0.014, 1.56)], [(0.1, 0.106), (0.084, 0.092)], mat=fab, tint=carr2, n=14, exp=2.4, sub=0)       # collar
    for sx in (-1, 1):                                                                             # yoke pads on the shoulders
        t.box((0.11, 0.2, 0.03), (sx * 0.14, 0.0, 1.505), mat=fab, tint=carr, bevel=0.012, bsegs=2, rot=(0, sx * -14, 0), jitter=0.04)
    if S.get("backpack") == "core":                                                                # the quantum rig on the back
        t.box((0.27, 0.105, 0.35), (0, -0.215 * bulk - 0.01, 1.31), mat=armor, tint=trim, bevel=0.016, bsegs=2, top=(0.94, 1.0), jitter=0.03)
        t.box((0.21, 0.04, 0.2), (0, -0.285 * bulk - 0.008, 1.27), mat=armor, tint=pl, bevel=0.012, bsegs=1)
        for z in (1.17, 1.195, 1.22, 1.245):
            t.box((0.18, 0.012, 0.007), (0, -0.307 * bulk - 0.008, z), mat=gun, tint=gm2)
        for x in (-0.105, 0.105):
            t.box((0.008, 0.008, 0.25), (x, -0.272 * bulk - 0.01, 1.325), mat=glow)
        t.box((0.07, 0.02, 0.025), (0, -0.25 * bulk - 0.01, 1.505), mat=armor, tint=pl, bevel=0.005)
        t.rod((0.1, -0.24, 1.48), (0.13, -0.27, 1.72), 0.0045, mat=gun, tint=gm2, segs=5)
        t.cyl(0.032, 0.14, (-0.0, -0.31 * bulk, 1.385), axis="x", mat=gun, tint=gm, segs=10)       # emitter coil
        t.cyl(0.036, 0.012, (0.075, -0.31 * bulk, 1.385), axis="x", mat=glow, segs=10)
        t.cyl(0.036, 0.012, (-0.075, -0.31 * bulk, 1.385), axis="x", mat=glow, segs=10)
    else:
        t.box((0.30, 0.12, 0.38), (0, -0.226 * bulk, 1.30), mat=fab, tint=carr, bevel=0.025, bsegs=2, top=(0.9, 0.9), jitter=0.04)
        for z in (1.18, 1.26, 1.34, 1.42):
            t.box((0.31, 0.012, 0.014), (0, -0.292 * bulk, z), mat=fab, tint=carr2, jitter=0.04)
        t.box((0.12, 0.05, 0.16), (0, -0.30 * bulk, 1.30), mat=fab, tint=carr2, bevel=0.01)
        t.rod((-0.1, -0.24, 1.48), (-0.12, -0.28, 1.78), 0.0045, mat=gun, tint=gm2, segs=5)                 # radio whip antenna
    if heavy:
        t.box((0.17, 0.09, 0.07), (0, 0.0, 1.575), mat=armor, tint=pl, bevel=0.012, bsegs=1, top=(0.9, 0.9))   # high neck guard (behind the helmet)

    # ------------------------------------------------------------------ head: neck, face, helmet
    h = head
    h.tube([(0, 0.012, 1.495), (0, 0.016, 1.60)], [(0.072, 0.074), (0.064, 0.068)], mat=fab, tint=uni, n=12, exp=2.2, sub=0)
    h.tube([(0, 0.01, 1.52), (0, 0.014, 1.575)], [(0.092, 0.098), (0.078, 0.086)], mat=fab, tint=carr2, n=14, exp=2.4, sub=0)       # gaiter
    h.sphere((0.084, 0.098, 0.108), (0, 0.016, 1.672), mat=fab, tint=scale_c(boot, 1.6), segs=14, rings=9)                           # head
    hcz = 1.69
    shell = helmet_rings(0.012, hcz, 0.113, 0.136, 0.142, k=9, n=22)
    h.loft(shell, mat=armor, tint=hel, caps=(False, True), closed=False, sharp=80.0, jitter=0.0)
    h.box((0.012, 0.11, 0.025), (0.118, 0.012, 1.69), mat=gun, tint=gm, bevel=0.003, mirror=True)                 # side rails
    h.box((0.03, 0.08, 0.075), (0.108, -0.018, 1.655), mat=armor, tint=trim, bevel=0.01, bsegs=1, mirror=True, jitter=0.04)   # ear covers
    h.box((0.12, 0.05, 0.07), (0, -0.138, 1.665), mat=fab, tint=carr, bevel=0.01, bsegs=1, jitter=0.03)           # rear counterweight
    h.box((0.065, 0.045, 0.045), (0, 0.128, 1.775), mat=gun, tint=gm, bevel=0.006)                               # NVG shroud
    h.cyl(0.017, 0.04, (0, 0.158, 1.775), axis="y", mat=gun, tint=gm2, segs=10)
    h.box((0.012, 0.012, 0.012), (0.045, 0.16, 1.80), mat=glow)
    h.bar((0.1, 0.03, 1.64), (0.065, 0.1, 1.575), 0.012, 0.006, mat=fab, tint=boot, mirror=True)                 # chin strap
    h.box((0.045, 0.012, 0.006), (0, 0.13, 1.84), mat=armor, tint=trim, bevel=0.002)                            # helmet crest plate
    if S["helmet_type"] == "visor":
        zs = [1.742, 1.715, 1.68, 1.645, 1.612]
        vr_ = arc_rings(0, 0.014, 0.103, 0.130, zs, 74, -74, n=11)
        h.loft(vr_, mat=visor, caps=(False, False), closed=False, sharp=80.0)
        rim = arc_rings(0, 0.014, 0.1045, 0.1315, [1.608], 74, -74, n=11)[0]
        for i in range(len(rim) - 1):
            h.rod(rim[i], rim[i + 1], 0.0034, mat=glow, segs=4)
        top = arc_rings(0, 0.014, 0.106, 0.1335, [1.745], 70, -70, n=11)[0]
        for i in range(len(top) - 1):
            h.rod(top[i], top[i + 1], 0.0055, mat=gun, tint=gm2, segs=4)
        h.box((0.10, 0.06, 0.06), (0, 0.098, 1.575), mat=gun, tint=gm2, bevel=0.01, bsegs=1, top=(0.9, 0.85))     # face guard / mouth piece
        h.cyl(0.02, 0.045, (0.062, 0.095, 1.58), axis="y", mat=gun, tint=gm, segs=10, mirror=True, bevel=0.003)
        h.box((0.12, 0.05, 0.035), (0, 0.082, 1.543), mat=armor, tint=pl, bevel=0.008, bsegs=1, top=(0.9, 0.8))    # chin cup
        h.box((0.008, 0.006, 0.05), (0.118, 0.045, 1.70), mat=glow, mirror=True)                                 # temple light strip
        h.rod((-0.1, 0.06, 1.62), (-0.062, 0.135, 1.585), 0.004, mat=gun, tint=gm2, segs=5)                        # mic boom
        h.sphere(0.009, (-0.062, 0.137, 1.584), mat=glow, segs=6, rings=4)
    else:
        zs = [1.735, 1.71, 1.665, 1.62, 1.575]
        mk = arc_rings(0, 0.014, 0.102, 0.128, zs, 76, -76, n=11)
        h.loft(mk, mat=armor, tint=mask, caps=(False, False), closed=False, sharp=80.0)
        sl = arc_rings(0, 0.014, 0.1045, 0.1305, [1.708, 1.69], 56, -56, n=9)
        h.loft(sl, mat=visor, caps=(False, False), closed=False)
        sg = arc_rings(0, 0.014, 0.1055, 0.1318, [1.704, 1.694], 50, -50, n=9)
        h.loft(sg, mat=glow, caps=(False, False), closed=False)
        h.box((0.07, 0.05, 0.07), (0, 0.1, 1.592), mat=gun, tint=gm2, bevel=0.008)                                   # breather
        h.cyl(0.021, 0.05, (0.056, 0.1, 1.598), axis="y", mat=gun, tint=gm, segs=10, mirror=True)
        h.box((0.02, 0.012, 0.15), (0, 0.133, 1.665), mat=armor, tint=trim, bevel=0.003)                            # crimson brow-to-chin stripe
        h.box((0.11, 0.06, 0.04), (0, 0.082, 1.552), mat=armor, tint=pl, bevel=0.008, bsegs=1, top=(0.9, 0.8))       # jaw guard
        h.box((0.03, 0.2, 0.05), (0, 0.0, 1.835), mat=armor, tint=trim, bevel=0.006, bsegs=1, top=(0.9, 1.0))        # helmet ridge

    # ------------------------------------------------------------------ rifle (shouldered, butt in the right shoulder pocket)
    RR = rotm(1.2, 0, 0)
    R = Matrix.Translation(Vector((0.118, 0.14, 1.365))) @ RR

    def rp(v):
        return R @ Vector(v)

    def rbox(size, pos, mat, tint=(1, 1, 1), **kw):
        rifle.box(size, rp(pos), mat=mat, tint=tint, frame=RR, **kw)

    def rcyl(r, ln, pos, mat, tint=(1, 1, 1), **kw):
        rifle.cyl(r, ln, rp(pos), mat=mat, tint=tint, frame=RR @ rotm(-90, 0, 0), **kw)

    rbox((0.042, 0.03, 0.115), (0, 0.015, -0.035), gun, gm2, bevel=0.005)
    rbox((0.04, 0.17, 0.06), (0, 0.11, -0.03), gun, gm, bevel=0.006, top=(0.9, 0.7))
    rbox((0.034, 0.12, 0.025), (0, 0.1, 0.012), gun, gm2, bevel=0.004)
    rbox((0.05, 0.21, 0.065), (0, 0.295, -0.032), gun, gm, bevel=0.006)
    rbox((0.052, 0.27, 0.056), (0, 0.325, 0.012), gun, gm2, bevel=0.005)
    rbox((0.022, 0.47, 0.014), (0, 0.425, 0.048), gun, gm, bevel=0.002)
    for yy in (0.22, 0.27, 0.32, 0.37, 0.42, 0.47, 0.52, 0.57, 0.62):
        rbox((0.026, 0.011, 0.01), (0, yy, 0.056), gun, gm2)
    rifle.box((0.034, 0.075, 0.2), rp((0, 0.33, -0.145)), mat=gun, tint=gm, frame=RR @ rotm(-9, 0, 0), bevel=0.006)
    rifle.box((0.036, 0.05, 0.11), rp((0, 0.235, -0.115)), mat=fab, tint=boot, frame=RR @ rotm(18, 0, 0), bevel=0.008)
    rbox((0.03, 0.07, 0.014), (0, 0.28, -0.075), gun, gm, bevel=0.003)
    rbox((0.058, 0.30, 0.06), (0, 0.51, 0.0), gun, gm, bevel=0.008)
    for yy in (0.43, 0.49, 0.55, 0.61):
        rbox((0.06, 0.026, 0.02), (0, yy, 0.0), gun, gm2)
    rbox((0.07, 0.1, 0.05), (0, 0.36, 0.075), gun, gm2, bevel=0.007)
    rcyl(0.021, 0.04, (0, 0.425, 0.075), gun, gm2, segs=10)
    rbox((0.052, 0.012, 0.03), (0, 0.307, 0.083), gun, gm2)
    rbox((0.008, 0.006, 0.008), (0, 0.31, 0.086), glow)
    rcyl(0.0105, 0.14, (0, 0.71, 0.0), gun, gm, segs=8)
    rcyl(0.027, 0.2, (0, 0.80, 0.0), gun, gm2, segs=12, bevel=0.003)
    rcyl(0.029, 0.014, (0, 0.905, 0.0), gun, gm, segs=12)
    rbox((0.02, 0.07, 0.02), (0.04, 0.55, -0.005), gun, gm2, bevel=0.003)
    rbox((0.012, 0.012, 0.012), (0.04, 0.59, -0.005), glow if S.get("light_glow") else gun, gm)
    rbox((0.008, 0.07, 0.008), (0.027, 0.2, -0.01), glow)
    muzzle = rp((0, 0.915, 0))

    # ------------------------------------------------------------------ arms: upper arm and forearm are separate bones, the glove is on the forearm
    hands = {1: rp((0.0, 0.235, -0.115)), -1: rp((0.0, 0.41, -0.012))}
    wrists = {1: rp((0.012, 0.19, -0.068)), -1: rp((0.045, 0.325, 0.01))}
    wrist_pos = {}
    for s, side in ((1, "R"), (-1, "L")):
        Sv = Vector((0.226 * s * bulk, 0.0, 1.43))
        E, W = two_bone(Sv, wrists[s], 0.31, 0.28, (0.5 * s, -0.5, -1.0))
        wrist_pos[s] = W
        ua = RigPart("UpperArm" + side, Sv, "Torso", seed=41 + s)
        fa_ = RigPart("ForeArm" + side, E, "UpperArm" + side, seed=51 + s)
        uarm[s], farm[s] = ua, fa_
        ua.sphere(0.07 * bulk, Sv + Vector((0.0, 0.0, -0.005)), mat=fab, tint=uni, scale=(1.0, 1.0, 0.92), segs=12, rings=8)
        ua.tube([Sv, E], [(0.061 * bulk, 0.061 * bulk), (0.051 * bulk, 0.051 * bulk)], mat=fab, tint=uni, n=10, exp=2.2, sub=1)
        ua.bar(Sv + (E - Sv) * 0.30, Sv + (E - Sv) * 0.78, 0.085, 0.082, mat=fab, tint=carr2, bevel=0.012, bsegs=1, jitter=0.04)     # sleeve pad
        if S.get("pauldrons") or heavy:
            ua.box((0.14, 0.18, 0.05), Sv + Vector((s * 0.04, 0.0, 0.058)), mat=armor, tint=pl, rot=(0, s * -14, 0), bevel=0.014, bsegs=2, top=(0.82, 0.8), jitter=0.04)
            ua.box((0.13, 0.15, 0.04), Sv + Vector((s * 0.052, 0.0, 0.022)), mat=armor, tint=trim, rot=(0, s * -26, 0), bevel=0.01, bsegs=1)
            ua.box((0.06, 0.15, 0.03), Sv + Vector((s * 0.03, 0.0, 0.082)), mat=armor, tint=hel, rot=(0, s * -8, 0), bevel=0.008, bsegs=1)
        else:                                                                                      # lighter layered shoulder armour with a light line
            ua.box((0.1, 0.14, 0.036), Sv + Vector((s * 0.026, 0.0, 0.054)), mat=armor, tint=pl, rot=(0, s * -12, 0), bevel=0.012, bsegs=2, top=(0.9, 0.9), jitter=0.04)
            ua.box((0.09, 0.12, 0.03), Sv + Vector((s * 0.044, 0.0, 0.026)), mat=armor, tint=trim, rot=(0, s * -24, 0), bevel=0.01, bsegs=1)
            ua.box((0.012, 0.11, 0.006), Sv + Vector((s * 0.034, 0.0, 0.076)), mat=glow, rot=(0, s * -10, 0))
        fa_.sphere(0.052, E, mat=fab, tint=uni, segs=10, rings=7)
        fa_.tube([E, W], [(0.051, 0.051), (0.04, 0.04)], mat=fab, tint=uni, n=10, exp=2.2, sub=1)
        fa_.box((0.075, 0.075, 0.075), E + Vector((s * 0.034, -0.012, 0.0)), mat=armor, tint=pl, bevel=0.014, bsegs=2, jitter=0.04)    # elbow pad
        fv = W - E
        fa_.bar(E + fv * 0.38, E + fv * 0.88, 0.076, 0.074, mat=armor, tint=trim, bevel=0.012, bsegs=1, taper=(0.86, 0.86), jitter=0.04)     # bracer
        fa_.bar(E + fv * 0.42 + Vector((s * 0.037, 0.0, 0.0)), E + fv * 0.84 + Vector((s * 0.037, 0.0, 0.0)), 0.008, 0.008, mat=glow)
        # glove: cuff, palm, curled fingers and thumb around the grip
        fa_.tube([W - fv.normalized() * 0.03, hands[s]], [(0.042, 0.042), (0.048, 0.042)], mat=fab, tint=glove, n=8, exp=2.5, sub=0)
        fa_.box((0.06, 0.078, 0.082), hands[s], mat=fab, tint=glove, frame=RR, bevel=0.012, bsegs=1, jitter=0.04)
        for k in range(3):
            fa_.box((0.056, 0.018, 0.026), hands[s] + R.to_3x3() @ Vector((0.0, 0.048, 0.024 - k * 0.026)), mat=fab, tint=glove, frame=RR, bevel=0.006, jitter=0.03)
        fa_.box((0.022, 0.05, 0.03), hands[s] + Vector((-s * 0.03, 0.0, 0.03)), mat=fab, tint=glove, frame=RR, bevel=0.006)
        fa_.box((0.05, 0.03, 0.03), hands[s] + R.to_3x3() @ Vector((0.0, -0.01, 0.052)), mat=armor, tint=pl, frame=RR, bevel=0.007)   # knuckle guard

    # ------------------------------------------------------------------ export (one skinned mesh) + rig markers
    parts = [hips, torso, head, uarm[-1], farm[-1], uarm[1], farm[1], rifle]
    for s in (-1, 1):
        parts += [thigh[s], shin[s], foot[s]]
    rig = [empty("Muzzle", muzzle), empty("WristL", wrist_pos[-1]), empty("WristR", wrist_pos[1]),
           empty("MagWell", rp((0, 0.33, -0.2))), empty("MagPouch", (-0.085, 0.215 * bulk, 1.13))]
    rig.append(light("Fill", (0.0, 0.8, 1.55), "omni", S["fill_color"], S["fill_energy"], 3.6, mask="own", attenuation=1.2, fade=(30, 12)))
    rig.append(light("Rim", (0.25, -0.8, 2.15), "omni", S["rim_color"], S["rim_energy"], 3.8, mask="own", attenuation=1.2, fade=(30, 12)))
    tot = 0
    for p in parts:
        tot += p.tri_count()
    print("  parts=%d tris(before culling)=%d" % (len(parts), tot))
    return export_model(S["name"], parts, extras=rig, size=S.get("atlas", 1024), decals=decals(S), ao_dist=0.2, ao_strength=S.get("ao", 0.6),
                        emit_strength=S.get("emit", 1.6), finalize=rig_finalize)


def decals(S):
    """Stencils, stripes and insignia projected onto the finished surfaces (object space, front +Y)."""
    mark = S["mark"]
    acc = S["accent"]
    d = []
    up = (0, 0, 1)
    d.append(Decal((0.0, 0.21, 1.405), (0, 1, 0), up, (0.20, 0.05), p_glyphs(mark, cells=7, seed=11), depth=0.06))                  # chest stencil
    d.append(Decal((0.0, 0.21, 1.245), (0, 1, 0), up, (0.24, 0.028), p_barcode(mark, bars=18, seed=5), depth=0.06))
    d.append(Decal((0.0, -0.25, 1.37), (0, -1, 0), up, (0.26, 0.15), p_box(mark, border=0.05, wear=0.4), depth=0.1))               # back panel frame
    d.append(Decal((0.0, -0.25, 1.38), (0, -1, 0), up, (0.2, 0.06), p_glyphs(mark, cells=6, seed=23, rows=1), depth=0.1))
    d.append(Decal((0.0, -0.25, 1.25), (0, -1, 0), up, (0.26, 0.05), p_stripes(5, 0.5, 45.0, S["stripe"]), depth=0.1))              # hazard stripe
    for sx in (-1, 1):                                                                                                               # shoulder patches
        d.append(Decal((sx * 0.30, 0.01, 1.40), (sx, 0, 0), up, (0.11, 0.11), p_ring(S["patch"], 0.18, 0.4, cross=True), depth=0.06))
        d.append(Decal((sx * 0.245, 0.0, 1.50), (0, 0, 1), (0, 1, 0), (0.07, 0.13), p_stripes(2, 0.5, 90.0, S["stripe"]), depth=0.05))
    d.append(Decal((0.0, 0.01, 1.835), (0, 0, 1), (0, 1, 0), (0.05, 0.22), p_stripes(2, 0.55, 90.0, S["stripe"]), depth=0.05))       # helmet crest
    d.append(Decal((0.0, 0.014, 1.65), (0, 1, 0), (0, 0, 1), (0.2, 0.17), p_visor_sheen(acc), depth=0.07, kinds=("glass",), min_dot=0.2))
    return d


def p_visor_sheen(accent):
    """A faint diagonal reflection band plus a dim HUD glow along the lower rim, so the visor never reads as a flat black hole."""
    import numpy as np
    from shade import sm

    def fn(u, v, c, idx):
        band = sm(0.05, 0.0, np.abs((u - 0.35) * 0.8 + (v - 0.5) * 0.9 - 0.12)) * 0.8
        rim = sm(0.22, 0.0, v) * 0.35
        col = np.array([0.09, 0.13, 0.15])
        emit = np.asarray(accent) * (rim[:, None] * 0.35)
        return np.clip(band + rim * 0.5, 0, 1), col, emit
    return fn
