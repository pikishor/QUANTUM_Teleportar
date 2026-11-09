Stylized Nature MegaKit (Standard, the free version: 68 of the 116 models) by Quaternius, CC0 1.0 (License.txt, copied from the archive).
Source page: https://opengameart.org/content/stylized-nature-megakit (also https://quaternius.com/packs/stylizednaturemegakit.html)
Fetched with plain curl and a descriptive user agent from https://opengameart.org/sites/default/files/stylized_nature_megakitstandard.zip (104 MB; NOT committed).
Used: 16 pieces (3 + 3 pines, broadleaf trees, 2 dead trees, bush, fern, 2 grasses, 3 rocks, pebble) and the leaf sprite sheets. godot/tools/open_models/convert_nature.py (bpy) decimates the trunks, thins the
leaf cards, bakes the bark and rock colours into vertex colours and packs the five leaf / grass sprites into one 1024 x 512 alpha atlas:
  godot/assets/models/nature_kit.glb (1.1 MB), godot/assets/textures/nature_atlas.webp (28 KB).
The generated mid and far LODs of the trees (cones and blobs) are code (godot/scripts/terrain/veg_kit.gd).
