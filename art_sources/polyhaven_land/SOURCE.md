# Poly Haven bark textures of the landscape trees (CC0)

Source: Poly Haven (https://polyhaven.com), files via https://api.polyhaven.com/files/<slug> and https://dl.polyhaven.org. CC0 1.0, see LICENSE.txt (same licence text as art_sources/polyhaven_pbr).
Fetched with plain urllib / curl and the user agent `QuantumTeleportar-asset-fetch/1.0` by `godot/tools/landscape/pack_bark.py` (1K JPG diffuse only), graded per species (brightness, saturation, tint) and packed as
`godot/assets/textures/land_bark_<species>.webp` (512 px, lossy WebP, VRAM compressed with mipmaps at import). The birch bark (painted lenticels) and the alien tree's glowing bark are procedural.
Raw downloads are not committed (`godot/assets_incoming/land_raw/`, git-ignored).

| Species | Slug | Title | URL |
|---|---|---|---|
| oak | bark_brown_01 | Bark Brown 01 | https://polyhaven.com/a/bark_brown_01 |
| pine | pine_bark | Pine Bark | https://polyhaven.com/a/pine_bark |
| fir | chinese_cedar_bark | Chinese Cedar Bark | https://polyhaven.com/a/chinese_cedar_bark |
| birch (base of the painted bark) | tree_bark_03 | Tree Bark 03 | https://polyhaven.com/a/tree_bark_03 |
| poplar, dead and driftwood | bark_brown_02 | Bark Brown 02 | https://polyhaven.com/a/bark_brown_02 |
| palm | palm_tree_bark | Palm Tree Bark | https://polyhaven.com/a/palm_tree_bark |
| acacia | bark_willow | Bark Willow | https://polyhaven.com/a/bark_willow |

The foliage atlas (leaves, needles, fronds, grass, ferns, flowers), the impostors, all tree and rock meshes and the props (turbines, pylons, masts, cranes, hangar, windsock) are our own, generated
with fixed seeds by `godot/tools/landscape/*.py` (no downloaded geometry).
