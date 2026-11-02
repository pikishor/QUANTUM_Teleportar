"""Offline prep of a third-party rigged character (glb / fbx) for scripts/characters/character_import.gd.

    $BLENDER_PY tools/blender/import_character.py assets_incoming/characters/hero/Hero.fbx --role hero [--out assets_incoming/characters/hero/hero_prepped.glb]

Steps: import, rename bones to the CharacterRig contract (same alias table as character_import.gd: Mixamo, Quaternius / Unreal style, Rigify DEF-),
add a Rifle bone under the right hand, zero the bone rolls (bone frames then follow the armature axes, which is what CharacterRig expects), apply transforms,
decimate every mesh to the role's triangle budget (hard limit; the game then adds LODs), join to one mesh named Body, export glb (y up, skinned, no cameras / lights).
The game runs without this step (character_import.gd does the same retarget and a softer limit at run time); this one gives the hard decimation and the roll fix.
"""
import argparse
import os
import re
import sys

import bpy  # noqa: F401

BUDGET = {"hero": 18000, "enemy": 12000, "citizen": 4000}
ALIASES = {
    "Hips": ["hips", "pelvis", "hip"],
    "Torso": ["spine2", "chest", "upperchest", "spine003", "spine03", "spine1", "spine02", "spine"],
    "Head": ["head", "spine006"],
    "UpperArm": ["upperarm", "uparm", "arm"],
    "ForeArm": ["forearm", "lowerarm", "lowarm"],
    "Thigh": ["upleg", "upperleg", "thigh"],
    "Shin": ["lowerleg", "shin", "calf", "leg"],
    "Foot": ["foot", "ankle"],
    "Hand": ["hand", "wrist"],
}


def normalize(name):
    s = name.lower()
    s = re.sub(r"^(mixamorig\d*|def|org|mch|armature)[:_\-.]", "", s)
    side = ""
    for tok, v in (("left", "L"), ("right", "R")):
        if tok in s:
            side = v
            s = s.replace(tok, "")
    m = re.search(r"[._\-]([lr])$", s)
    if m:
        side = m.group(1).upper()
        s = s[: m.start()]
    return re.sub(r"[^a-z0-9]", "", s), side


def map_bones(names):
    norm = [normalize(n) for n in names]
    out = {}
    for key, cands in ALIASES.items():
        for side in ([""] if key in ("Hips", "Torso", "Head") else ["L", "R"]):
            for c in cands:
                hit = next((i for i, (b, s) in enumerate(norm) if b == c and s == side), None)
                if hit is not None:
                    out[key + side] = names[hit]
                    break
    return out


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("--role", required=True)
    ap.add_argument("--out")
    a = ap.parse_args(argv)
    cls = next((k for k in BUDGET if a.role == k or a.role.startswith(k + "_")), None)
    if cls is None:
        sys.exit("role must be hero, enemy_* or citizen_*")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if a.src.lower().endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=a.src)
    else:
        bpy.ops.import_scene.gltf(filepath=a.src)
    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if arm is None:
        sys.exit("no armature in " + a.src)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    mapping = map_bones([b.name for b in eb])
    need = ["Hips", "Torso", "Head", "UpperArmL", "ForeArmL", "UpperArmR", "ForeArmR", "ThighL", "ShinL", "FootL", "ThighR", "ShinR", "FootR"]
    missing = [n for n in need if n not in mapping]
    if missing:
        sys.exit("cannot map bones: " + ", ".join(missing))
    for b in eb:
        b.roll = 0.0
    hand = mapping.get("HandR", mapping["ForeArmR"])
    renames = {}
    for new, old in mapping.items():
        if new.startswith("Hand"):
            continue
        clash = eb.get(new)
        if clash is not None and clash.name != old:
            clash.name = new + "_src"
        eb[old].name = new
        renames[old] = new
    rifle = eb.new("Rifle")
    h = eb[renames.get(hand, hand)]
    rifle.head = h.tail
    rifle.tail = h.tail + (h.tail - h.head).normalized() * 0.2
    rifle.parent = h
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = "Body"
    n0 = tri_count(body)
    if n0 > BUDGET[cls]:
        mod = body.modifiers.new("budget", "DECIMATE")
        mod.ratio = BUDGET[cls] / n0
        bpy.ops.object.modifier_apply(modifier=mod.name)
    print("character %s: %d -> %d triangles, %d bones renamed" % (a.role, n0, tri_count(body), len(renames)))
    out = a.out or os.path.splitext(a.src)[0] + "_prepped.glb"
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True, export_skins=True, export_cameras=False, export_lights=False)
    print("wrote", out)


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
