# Hero look v3 (wave 112): render-look-fix iterations and self-review

Seventeen loops in all (the pictures of the first nine were the stage at 900 x 720, the later ones 2400 x 1080 and the real game). Tools: `godot/tools/hero/stage.sh` (the look-dev stage at phone aspect, software Vulkan), `tools/hero/loop.sh` (Blender bake, import, render), `tests/bot_superhero.gd` (the real city),
`tools/hero/bake_portraits.sh`. Every number below is from the renders in this folder (`hero_*.jpg`); the old hero was rendered from a clean checkout of HEAD 2b4c37b (same stage, same bot).

## The loops (each one: render, look, fix)
1. First kit on the real body (rays at the Quaternius mesh): plates floated and the boots climbed the leg (rays hit the shin) -> analytic lofted boots, conformal shaft ring, yoke extents; ray misses 0.
2. Triangle explosion (40k from interior bevels) -> bevel only the rim, one segment, shells without inner sheets, resolution factor: 5-7k per set.
3. Gear looked pale and blotchy: `fwidth` inside a branch gave garbage mips -> derivatives once at the top, clamped, `textureGrad`.
4. Flat 0.1 albedo on the new kinds (kind ids were missing from the atlas bake table) and carbon twill aliased into light diamonds -> own kinds `hplate` / `hdark`.
5. Pauldrons: stacked lames read as a pile of boxes -> three calm lames per side, dome shells on top; antenna rods -> swept fins; cloak became a 3-bone chain (it moves with the run).
6. Suit mask (panels, accent stripes, seams) baked into the roughness slot of the body texture, registered by UV rasterisation of the real triangles.
7. Palette: lavender-grey plates with big bright teal areas (looked like painted plastic, 4 frames) -> gunmetal plates (0.24 -> 0.17), accent paint 0.5 -> 0.4.
8. Mirror reflections: the flat core pack reflected the sky's sun disc as a white rectangle (the same defect family as the old white leg boxes) -> metal capped (plates 0.5, dark metal 0.3), accent plates are lacquer (metal 0.12).
9. Boots looked like beige ice skates (canvas kind) -> dark fabric kind; dark metal / carbon tint 0.30 -> 0.11: the pack slab is graphite now.
10. Plate blotches (baked wear at full contrast read as dirt on a phone screen) -> contrast 0.62; fins shorter and wider; gold palette richer.
11. Showcase: the arms were folded across the chest (the wrist empties were removed BEFORE `CharacterRig.find` read them) and the studio sky made every plate teal -> order fixed, darker studio.
12. SUIT screen: six buttons overflowed the right edge and the hero hid behind the panel -> hero plate + 3x2 suit cards + chips + swatches + person row, checked at 844x390 and 1280x720 (tests) and 1600x720 / 2400x1080 (bot).
13. Perf (not a picture): MED went from 276,878 to 296,720 total prims with the new hero although its triangles are the same -> LOD switch sizes scheduled like the old hero's: 274,440.
14. The cast shadow of the hero was a hard parallelogram (a rectangular cloak plus the pack; noted by the landscape builder on dirt) -> the hem of the cloak is slanted, 0.07 m narrower; the shadow now reads as a cloak.
15. Flight set: the two wing mounts hung down the back like rods (0.6 m, 14 mm thick) -> folded wing panels, 0.4 m long, 118 mm broad, with glowing edges; GILDED read as flat yellow -> a desaturated gold with a lower roughness.
16. Texture weight: the 2K skin colour maps in BPTC / ASTC cost +26 MB of APK -> DXT1 / ETC2 for skin colour and 1K body normals (a 4x zoom of the face shows no visible loss; mean difference 0.09 / 255): +7.5 MB, hero GPU memory -7 MB more.
17. Compatibility renderer check (OpenGL, LOW): the kit, the glow and the atlas render (no black or white patches).

## Self-review against docs/owner_shots/round5
- Round 5 hero (r5_02, r5_23): a pale grey-blue mannequin with speckled white boxes, no face detail at phone size, lost against the pale beach. Now: dark silhouette with a cape, a core pack with a glowing ring, a tall gorget and layered shoulders; cyan circuits on legs, bracers and back; the face has eyes with catchlights, brows, jaw and hair. Reads from behind (the gameplay view), in motion (cape chain) and at 15 m (`hero_lod_distance.jpg`); at 40 m a clear dark figure with a light ring, at 80 m a 15 px figure (expected).
- White / black patches: none found in 6 suits x 2 views, the test samples the atlas under every kit vertex (no UV off the island, no pure black or white texel under the lit kinds).
- Still weaker than the references of other games: the breastplate is a smooth dome (a paint plate, not a panelled one), the female body wears the male-fitted kit (plates a little proud), the flight set's wing mounts are two thin blades (the SNAKE wave adds the energy wings), the glow modes differ mostly in the thin circuit lines, the hero is hidden while driving (by design, `Player._apply_vehicle_state`), there is no driving close-up.

## Sheets
hero_before_after.jpg (real game: game camera, firing, SUIT screen), hero_before_after_turntable.jpg, hero_turntable.jpg (5 views, 2400 x 1080 crops), hero_suits_six.jpg, hero_action.jpg,
hero_customisation.jpg, hero_lod_distance.jpg (15 / 40 / 80 m and magnified), hero_glow_modes.jpg, hero_portraits.jpg (committed pictures and the story cast), hero_variants.jpg (persons, female body).
