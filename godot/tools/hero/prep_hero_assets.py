#!/usr/bin/env python3
"""Copies the Quaternius Universal Base Characters (CC0) from art_sources/ into godot/assets_incoming/characters/hero/ for HeroCharacter (scripts/characters/hero_character.gd).
  * body maps: skin colour dark / light 2048 px, normal 2048 px (the Godot / Y+ set from normals_godot/), roughness 1024 px grey (the G channel of the source)
  * hair maps 1024 px (hair 1 and 2 colour + normal, Godot normals), eye maps 256 px
  * glTF: Superhero_{Male,Female}_FullBody.gltf (+ .bin) with the image uris pointed at the files above, and the rigged-to-head hair / beard / eyebrow modules in hair/
Idempotent. Usage (from godot/): python3 -I tools/hero/prep_hero_assets.py"""
import json, os, shutil
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "..", "art_sources", "quaternius_universal_base_characters")
DST = os.path.join(HERE, "..", "..", "assets_incoming", "characters", "hero")


def save(src, name, size, mode=None):
    im = Image.open(os.path.join(SRC, src))
    if mode == "L":
        im = im.convert("RGB").split()[1]            # glTF metallicRoughness: roughness is the G channel
    else:
        im = im.convert("RGBA" if "normal" in name and im.mode == "RGBA" else "RGB")
    if im.size[0] != size:
        im = im.resize((size, size), Image.LANCZOS)
    im.save(os.path.join(DST, name), optimize=True)


def main():
    os.makedirs(os.path.join(DST, "hair"), exist_ok=True)
    save("T_Superhero_Male_Dark.png", "hero_male_dark.png", 2048)
    save("textures_part3/T_Superhero_Male_Ligh.png", "hero_male_light.png", 2048)
    save("normals_godot/T_Superhero_Male_Normal.png", "hero_male_normal.png", 2048)
    save("T_Superhero_Male_Roughness.png", "hero_male_rough.png", 1024, "L")
    save("T_Superhero_Female_Dark_BaseColor.png", "hero_female_dark.png", 2048)
    save("textures_part3/T_Superhero_Female_Light_BaseColor.png", "hero_female_light.png", 2048)
    save("normals_godot/T_Superhero_Female_Normal.png", "hero_female_normal.png", 2048)
    save("T_Superhero_Female_Roughness.png", "hero_female_rough.png", 1024, "L")
    save("hair_modules/T_Hair_1_BaseColor.png", "hero_hair1_albedo.png", 1024)
    save("normals_godot/T_Hair_1_Normal.png", "hero_hair1_normal.png", 1024)
    save("hair_modules/T_Hair_2_BaseColor.png", "hero_hair2_albedo.png", 1024)
    save("normals_godot/T_Hair_2_Normal.png", "hero_hair2_normal.png", 1024)
    save("T_Eye_Brown.png", "hero_eye_albedo.png", 256)
    save("normals_godot/T_Eye_Normal.png", "hero_eye_normal.png", 256)

    def remap(uri, gender, prefix):
        u = uri.lower()
        if "hair_1" in u:
            return prefix + ("hero_hair1_normal.png" if "normal" in u else "hero_hair1_albedo.png")
        if "hair_2" in u:
            return prefix + ("hero_hair2_normal.png" if "normal" in u else "hero_hair2_albedo.png")
        if "eye" in u:
            return prefix + ("hero_eye_normal.png" if "normal" in u else "hero_eye_albedo.png")
        if "normal" in u:
            return prefix + "hero_%s_normal.png" % gender
        if "rough" in u:
            return prefix + "hero_%s_rough.png" % gender
        return prefix + "hero_%s_dark.png" % gender

    for g in ("Male", "Female"):
        name = "Superhero_%s_FullBody" % g
        d = json.load(open(os.path.join(SRC, name + ".gltf")))
        for im in d["images"]:
            im["uri"] = remap(im["uri"], g.lower(), "")
        json.dump(d, open(os.path.join(DST, name + ".gltf"), "w"), indent=1)
        shutil.copy(os.path.join(SRC, name + ".bin"), os.path.join(DST, name + ".bin"))
    for f in sorted(os.listdir(os.path.join(SRC, "hair_rigged_to_head"))):
        p = os.path.join(SRC, "hair_rigged_to_head", f)
        if f.endswith(".gltf"):
            d = json.load(open(p))
            for im in d["images"]:
                im["uri"] = remap(im["uri"], "", "../")
            json.dump(d, open(os.path.join(DST, "hair", f), "w"), indent=1)
        elif f.endswith(".bin"):
            shutil.copy(p, os.path.join(DST, "hair", f))
    shutil.copy(os.path.join(SRC, "License.txt"), os.path.join(DST, "License.txt"))
    print("hero assets ready in", os.path.normpath(DST))


main()
