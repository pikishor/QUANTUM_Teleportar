# Kenney Furniture Kit 1.0 (selected pieces)

- Author: Kenney (www.kenney.nl)
- Fetched from: https://opengameart.org/content/furniture-kit  (file: https://opengameart.org/sites/default/files/kenney_furniturePack.zip), because kenney.nl itself answers 403 to scripts
- Licence: CC0 1.0 (see License.txt next to this file; no attribution required, credited anyway)
- Kept here: the licence only. The 140-model OBJ / FBX / Unity archive (5.6 MB) is not committed; the game uses 38 pieces, converted and merged.
- Used by: godot/tools/open_models/convert_furniture.py (OBJ + MTL -> godot/assets/models/furn_<piece>.glb, flat-colour vertex data, 0.2 m per kit unit) and godot/scripts/interiors/interior_furniture.gd
- To rebuild: download the zip above, unzip it, run `python3 godot/tools/open_models/convert_furniture.py <unzipped>/Models`, then `godot/tools/import.sh`.
