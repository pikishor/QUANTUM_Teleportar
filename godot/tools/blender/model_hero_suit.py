"""The hero's suit kit (wave 112, hero look v3): layered tactical armour fitted to the Quaternius base body, exported as assets/models/hero_suit.glb with one mesh node per part and
the part data in the glTF extras (bone, kind, zone, sets: see herosuit/kitlib.py). HeroCharacter (scripts/characters/hero_character.gd, HeroSuit) merges the parts of the chosen
suit set into the hero's single skinned surface, so the armour costs no draw call.

Run:  tools/blender/build_all.sh hero_suit            (bakes ONE 1K atlas: hero_suit_albedo / _orm / _normal in assets/textures, about 1-2 minutes)
      QT_HERO_QUICK=1 tools/blender/build_all.sh hero_suit   (no bake: geometry only, for shape iterations)
      QT_HERO_BODY=female  fits the kit to the female body (shape check)
Blender axes: x right, y forward, z up, metres, feet at z = 0 (the exporter turns +Y into glTF -Z).
"""
import os
import sys
import time

os.environ.setdefault("QT_ATLAS_SCALE", "1")            # ONE 1K atlas (the hero kit is small): the 2x scale of the other models is not wanted here
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "herosuit"))
import bpy  # noqa: E402
import helpers  # noqa: E402
from helpers import export_model, new_scene  # noqa: E402
from herosuit import fit, parts  # noqa: E402
from herosuit.body import Body  # noqa: E402
from herosuit.kitlib import Kit  # noqa: E402

NAME = "hero_suit"
t0 = time.time()
new_scene()
body = Body(os.environ.get("QT_HERO_BODY", "male"))
kit = Kit()
parts.build(kit, body)
print("KIT parts=%d tris=%d (fit %.1fs) ray misses=%d %s" % (len(kit.parts), kit.tri_count(), time.time() - t0, len(fit.MISSES), fit.MISSES[:6]))
for sets in ("vanguard", "stealth", "assault", "flight"):
    print("KIT   %-9s tris=%d" % (sets, kit.tri_count(sets)))

if os.environ.get("QT_HERO_QUICK"):
    objs = [p.build() for p in kit.parts]
    out = os.path.join(helpers.MODELS_DIR, NAME + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True, export_yup=True, export_materials="NONE", export_extras=True,
                              export_cameras=False, export_lights=False, export_animations=False, export_skins=False, export_morph=False)
    print("MODEL %s QUICK (no atlas) parts=%d -> %s (%.1fs)" % (NAME, len(objs), out, time.time() - t0))
else:
    export_model(NAME, kit.parts, size=int(os.environ.get("QT_HERO_ATLAS", "1024")), ao_dist=0.22, ao_strength=0.72, max_ppm=520.0, seed=7, emit_strength=1.0,
                 groups={"atlas": dict(base=NAME, material="Gear")})
    print("MODEL %s baked in %.1fs" % (NAME, time.time() - t0))
