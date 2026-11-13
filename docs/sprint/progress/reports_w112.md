# Wave 112 reports (builders and critics, extracted from the workflow journal at the switch)

Full final reports of the agents of this wave, copied from the workflow journal (the integrator reads this file).


## w112-landscape

REPORT w112-landscape (builder, restarted session finished; nothing committed or pushed)

WHAT IS DONE
- Trees: 9 species by biome (oak, birch, poplar, pine, fir, palm, acacia, dead, alien) x 3 LODs (full/lite, mid, shared cross impostor) in MultiMesh chunks (one per species and LOD, at most 36 draws in a forest, zero per-tree nodes), ancient groves (35-42 m pines/firs), fallen trunks, flowers, ferns, reeds, bushes, boulder fields, dune grass, pebbles + driftwood. Wind from Weather.current via LandClimate (global shader param `wind`), rain-wet in every new shader.
- Ground: 11 terrain layers (Poly Haven CC0 sand + forest ground), tan dry sand with ragged edge, wet band, foam line, warped strata, scree, earth/scree dirt tracks, asphalt detail, sine-wave rivers/lakes. Sea is no longer flat lilac.
- LandscapeSites: 6 waterfalls + 7 flat drivable grass airstrips FOUND by search (hints + full fallback), carved at the end of height_at. FallWorld (animated sheet, wet band, swimmable pool, streams, mist, spray, roar), StripWorld (hangar, windsock, edge markers, StripWorld.hooks() for the aircraft wave), AnchorSites/AnchorWorld (14 turbines, 3 pylon lines, 3 masts, 2 quarry cranes, 3 rock arches, falls' lips, harbour cranes, ancient trees); static AnchorWorld.anchors_at(pos, radius) needs no node.
- This last session: LAZY + STAGED wake (landscape and vegetation sleep until the hero is >470 m from the city centre: city start pays 0 draws, 0 triangles, no textures, 0 nodes; this also fixed test_ambient). Wake = 22 steps, longest 27 ms (desktop, headless); a fall is built on approach in 26 ms (was 100: sheet normals from the grid, sounds made once); AnchorSites.ensure split in 5 parts + hints for masts (73 ms -> 0.5 ms) and arches; AnchorWorld.build_step 11 stages; StripWorld one strip per step; avenue trees validated per cell (warm 650 -> 11 ms). LandscapeSites.carve/near_feature/pool_level now leave through a 128 m grid (the carve had added 20-50% to every height_at call; now noise, heights identical on 5,800 checked points). Grass verge thins out near roads (no hedge of tufts at the edge line).

FILES
New: godot/scripts/landscape/{land_kit,land_climate,landscape,landscape_sites,fall_world,strip_world,anchor_sites,anchor_world}.gd; shaders land_tree, land_impostor, land_rock, land_prop, land_common.gdshaderinc, fall_water, airstrip; models land_trees.glb, land_props.glb; textures land_foliage, land_impostor, land_bark_* (.webp); godot/tools/landscape/*.py; tests/test_landscape_dressing.gd, tests/bot_landscape.gd, tests/landscape_viewer.{gd,tscn}; art_sources/polyhaven_land/{LICENSE.txt,SOURCE.md}; sheets docs/shots/round6/landscape_before_after.jpg and landscape_times_of_day.jpg (q80, coast / forest road / mountain pass (SUMMIT ROAD switchbacks) / waterfall at 06:00, 12:00, 19:00).
Changed (shared): scripts/terrain/{veg_scatter,vegetation_world,veg_kit,terrain_base,terrain_textures}.gd, shaders terrain, terrain_road, water_inland, textures terrain_beach/terrain_dirt.webp, tools/materials/pack_terrain_textures.py, .gitignore (land_raw), art_sources/polyhaven_terrain/SOURCE.md, docs/THIRD_PARTY.md. HOOK LINES in others' files (keep when rewritten): city.gd (landscape node, Landscape.attach, set_quality), terrain_height.gd (LandscapeSites.ensure in warm, carve at end of height_at, pool_level in water_level_for, height_pre). Docs: godot/ARCHITECTURE.md "Landscape dressing", docs/HANDOFF.md "Wave 112: landscape dressing", docs/sprint/progress/w112-landscape.md (45 lines).

TESTS
- tests/test_landscape_dressing.gd: RESULT PASS, 203 checks, about 60 s, real scene (new: staged-wake steps, mast/arch hint checks).
- Also PASS now: test_ambient, test_animals_biomes, test_water_world, test_outskirts_sites (prints its own 60 s watchdog line when the machine is loaded; towns' settle takes the time).
- Failing, NOT mine: test_terrain_world "all 80 far tiles are built by the worker threads" (51 of 80 in 45 s on a loaded machine; was 42 before my grid early-out); test_outskirts_settlements "SALT QUAY has parked cars (6), folk (22) and street props (17)" (1 of 388); test_free_roam_world "the raid runs while they live" failed once in 4 runs (an automatic event can join the raid), passes on rerun.

PERF GATE (run by me, PERF_CHECK=1 tools/perf_report.sh, one tier per call, stale user://roam_world.cfg removed first, final tree)
PERF RESULT tier=0 label=LOW renderer=mobile touch=0 draws=73 prims=137055 total_draws=95 total_prims=137921 nodes=2891 tex_mb=146 lights=3 hud_draws=19 death_draws=108 death_prims=135941 enemies=4 verdict=OK
PERF RESULT tier=1 label=MED renderer=mobile touch=0 draws=97 prims=245310 total_draws=129 total_prims=277194 nodes=3030 tex_mb=177 lights=9 hud_draws=24 death_draws=144 death_prims=273070 enemies=4 verdict=OK
PERF RESULT tier=2 label=HIGH renderer=mobile touch=0 draws=113 prims=340232 total_draws=149 total_prims=386298 nodes=3149 tex_mb=242 lights=12 hud_draws=25 death_draws=167 death_prims=379160 enemies=4 verdict=OK
Attribution: earlier runs of the same landscape code (stale profile file present, before others' last changes) were MED OVER 288,454 triangles and HIGH OVER death spike 171; both were IDENTICAL with QT_NO_LANDSCAPE=1 QT_NO_VEGETATION=1 (288,454 / 136 draws / 177 MB and 171 / 155 / 242 MB), so not this wave's. Texture limits (200/260/360 MB) untouched; the landscape adds about 4 / 9 / 12 MB only when awake (outskirts), none at the city start.
APK size effect: +4.1 MB in the repo (models 2.1 MB, textures 1.6 MB incl. two swapped terrain layers, shaders 27 KB), about +6.5 MB in an APK (VRAM-compressed: foliage ASTC 2.8 MB, impostors 1.4 MB, 9 barks ~0.17 MB each, models 0.45 MB). Under the 30 MB cap; no raw archive committed; CC0 licence text in art_sources/polyhaven_land and polyhaven_terrain, credits in docs/THIRD_PARTY.md.

RENDER LOOPS / SELF-REVIEW: 8+ look-fix iterations at phone aspect with frames opened and defects listed (it1-it8, i1-i5, r1-r3, f0-f4), scratch frames and the 2.9 GB frozen A/B tree deleted (disk now 11 GB free). Against owner round5 (r5_21..23: flat lilac sea/sand, black road, blocky trees, dark-blue wall for the falls): coast now tan sand with wet band, foam, pebbles, driftwood and a shallow-to-deep teal sea; forest road has grey asphalt, mixed tall conifers/broadleaf, sparse verge; mountain pass is an earth switchback with rails; waterfall has an animated sheet, mist and turquoise pool.

HONEST GAPS: no trails or road tunnels (tunnels/roads are the roads builder's); no tree shadows on LOW/MED; sea foam is the old shader's; no map pins for falls/strips (LandscapeSites.hooks() is the entry); fall sheet is streaky blue-white not white water and the carved cliff reads as smooth clay; the aircraft wave still has to place planes on the strips; wake-step and fall-build timings measured on a desktop only, not on a phone.

DEFECTS OUTSIDE MY SCOPE: sky at dawn/dusk shows blocky cloud shapes over the sea (sky system); hero shadow is a hard dark parallelogram on dirt and the hero ShadowProxy is 16 k triangles; settlement_kit.gd:33/:100 and settlement_world.gd:306 "Invalid access" script errors in render logs; wide mint-green creature blob on PASS ROAD s=900 and an observatory light cone on SUMMIT ROAD; PASS ROAD ends at the cut bank (flat brown slab); bots/tests leave user://roam_world.cfg which adds draws and ~8 MB to the next perf gate (remove before gating); docs/shots/round6 already holds 15+ jpg from the cars builder (plan says 12; I added 2 small sheets).


## w112-outskirts-map

Files: scripts/settlements/* (plan, kit, ONE shader, world, data, folk, seven styles), scripts/interiors/interior_country.gd (19 interiors), world_extent.gd (9 km world, 7 roads), hook lines in city, interior_*, parked_cars, crowd, anchors, roam pads, map; sheets docs/shots/round6/outskirts_*.jpg (6) + iterations.md; ARCHITECTURE, HANDOFF, progress log.
Tests: new test_outskirts_settlements (390 checks) passes; about 60 regression tests pass; six old tests moved because the coast moved (reasons in HANDOFF). Fixed on the way: far-terrain tile grid (MED was 286.7k, over budget), officer-scale race in Drone (set_size).
Gaps: land x1.88 (area x2.25); towns have a wide street profile; folk and pets stand still; no harbour pier; towns are not world-mission targets. Outside my scope: test_ambient fails from the landscape builder's nodes; test_vehicle_roster prints a process_mode error; the hero builder's files intermittently break compile (re-run tools/import.sh).

PERF RESULT tier=0 label=LOW renderer=mobile touch=0 draws=72 prims=134495 total_draws=94 total_prims=135361 nodes=2890 tex_mb=146 lights=3 hud_draws=19 death_draws=108 death_prims=135941 enemies=4 verdict=OK
PERF RESULT tier=1 label=MED renderer=mobile touch=0 draws=97 prims=245310 total_draws=129 total_prims=277194 nodes=3030 tex_mb=177 lights=9 hud_draws=24 death_draws=145 death_prims=272748 enemies=4 verdict=OK
PERF RESULT tier=2 label=HIGH renderer=mobile touch=0 draws=113 prims=340232 total_draws=149 total_prims=386298 nodes=3148 tex_mb=242 lights=12 hud_draws=25 death_draws=166 death_prims=379332 enemies=4 verdict=OK

APK size effect: +0.24 MB (scripts and one shader; no model, texture or sound; the 3.9 MB of sheets are docs, not exported).


## w112-hero-look

REPORT w112-hero-look (hero look v3, Round 6 wave 112). Working tree only, NOTHING committed or pushed. Progress log: /home/user/QUANTUM_Teleportar/docs/sprint/progress/w112-hero-look.md

VERDICT: done and verified (software renderer only, nothing run on a phone). Perf gate is OK on all three tiers.

PERF GATE (PERF_CHECK=1 tools/perf_report.sh 0 1 2, run by me last on the shared working tree that includes every builder's uncommitted changes):
PERF RESULT tier=0 label=LOW renderer=mobile touch=0 draws=74 prims=138801 total_draws=96 total_prims=139667 nodes=2892 tex_mb=110 lights=3 hud_draws=21 death_draws=108 death_prims=134393 enemies=4 verdict=OK
PERF RESULT tier=1 label=MED renderer=mobile touch=0 draws=97 prims=240518 total_draws=129 total_prims=272186 nodes=3030 tex_mb=141 lights=9 hud_draws=24 death_draws=144 death_prims=268140 enemies=4 verdict=OK
PERF RESULT tier=2 label=HIGH renderer=mobile touch=0 draws=113 prims=326420 total_draws=149 total_prims=377842 nodes=3148 tex_mb=207 lights=12 hud_draws=25 death_draws=166 death_prims=371530 enemies=4 verdict=OK
Attribution (A/B in a clean checkout of HEAD 2b4c37b plus ONLY my files, scratch worktree removed afterwards): HEAD alone MED = 130 total draws / 276,878 prims / tex 175 MB; HEAD + hero = MED 130 / 274,440 / 146 MB, LOW 96 / 139,473 / 115 MB, HIGH 149 / 368,888 / 207 MB, all OK. Hero LOD0 is 16,143 triangles against 16,023 before (one surface, one draw). Hero texture memory fell about 34 MB (tex limits untouched). My FIRST MED run was OVER (296,720 prims) although the triangle count was the same: the merged hero's LOD edge lengths (flat plates) made the engine keep fine LODs far too long (hero + shadow proxy + mirror). Fixed in HeroCharacter.LOD_SCHEDULE: the generated LODs get the old hero's switch sizes by triangle share (LODs: 16143, 8071, 3929, 959, 452, 192 triangles). Later runs differ only by other builders' concurrent changes (HIGH prims 369.5k -> 377.8k between my two last runs, limit 430k).
APK effect (estimate from the import cache, no Android export here): repo +2.4 MB (hero_suit.glb 0.35, atlas albedo/normal/orm 0.83, 7 webp portraits 0.06, RGBA suit masks in the two rough maps ~+1) plus 3.9 MB of contact sheets (not in the APK). In an APK about +7.5 MB: hero textures re-imported VRAM compressed with mipmaps (skin colour ETC2/DXT1, 2K body normals limited to 1K, rest ASTC/BPTC) = 25 MB for the whole hero set vs ~18 MB lossless before (ASTC 4x4 everywhere would have been +26 MB; a 4x zoom of the face shows no visible loss, mean difference 0.09/255).

WHITE RECTANGLES ON THE LEGS: a REAL defect. They were the procedural box gear (HeroCharacter._gear_boxes: pale bevelled boxes bound to calf/thigh bones that floated off the legs when running, visible in owner round 5 and in my BEFORE renders). Replaced by the suit kit; _gear_piece stays only as fallback when hero_suit.glb is absent. Test checks the atlas under every kit vertex for black/white texels (none).

WHAT WAS BUILT
- Kit (tools/blender/herosuit/*.py + model_hero_suit.py, in build_all.sh): armour ray-cast at the REAL Quaternius body: layered pauldrons, gorget, breastplate with core ring, abdomen lames, belt, thigh/knee/shin guards, forearm bracers with emitters, boots, core pack with fins and glow ring, slanted cloak on a 3-bone chain (Sec1-3, driven by CharacterRig). Four geometry sets: vanguard, stealth, assault, flight (folded wing panels). ~5k tris per set, one glb + one 1K atlas, merged into the hero's ONE skinned surface. Skeleton, rig contract and standard hand bones unchanged. Shader: hero_body.gdshader takes the new path only with hero_style=1 (player's hero); NPC/enemy path untouched. 12 samplers (9 + 3 atlas).
- Glow: scripts/characters/hero_glow.gd. API (static, targets the live hero, false when none): HeroLook.set_glow(color, intensity, mode) and HeroLook.pulse_glow(color, intensity, secs). Modes steady pulse charge flow wings flicker (layers), burst (one-shot). A layer set through the API is HELD (sensor never overwrites it) until released with intensity 0. Wired now: QUANTUM TELEPORT aim (charge) + arrival (burst), SUPERPOSITION, ENTANGLE, COLLAPSE, glide/flight (wings), low health (alarm), PlayerBody.flinch (hurt), fire_flash (fired).
- Presets: 6 suits in HeroLook.SUITS (standard=VANGUARD, stealth, assault, flight, gilded, phase) with palette, kit set, unlock rule (price, ach:<id> achievement, cosmetic), tag; 8 schemes + 12 accents kept; HeroLook.hero_mode (static) unlocks all. Economy.SUIT_PRICE one line.
- SUIT screen (scripts/ui/look_screen.gd rewritten, all button ids unchanged, buttons >=64 px, captions() API kept): live 3D hero on a turntable (scripts/ui/hero_showcase.gd: own SubViewport studio, real model+material, own HeroGlow, drag turns / tap resets, freed after 12 idle s), 6 suit cards with pictures + unlock hints, 8 scheme chips, 12 swatches, person row, ACCENT BUY, BACK. ES/HI strings (scripts/common/strings_hero.gd).
- Portraits: scripts/characters/hero_portrait.gd; committed assets/ui/hero_portrait.webp (384x480) and hero_suit_<id>.webp (192x240) baked by tools/hero/bake_portraits.sh through the showcase; StoryCast.draw_portrait shows the hero (KESTREL) as that render (live render + cache for other looks, requested only in menu states; drawn bust is fallback).
- LODs: 6 levels (full + 5). PlayerBody re-applies the look on tier change; unused HERO_GLOW_GAIN removed.
- Look-dev: tools/hero/{stage,loop,bake_portraits}.sh, patch_hero_imports.py, bake_suit_mask.py; tests/hero_stage.{gd,tscn}, hero_portrait_bake.{gd,tscn}; tests/bot_superhero.gd phases 12-15 (15/40/80 m, flight suit).

SHARED FILES I TOUCHED (minimal): hud.gd (3 one-line routes of a drag on the hero plate to HeroShowcase), strings.gd (+3 lines: preload and merge of strings_hero), economy.gd (1 line), story_cast.gd (hero portrait hook), demo_mode.gd (demo now grants achievement rewards, needed because the flight suit is an ach: reward), build_all.sh (hero_suit entry), bot_superhero.gd (phases), hero_character.gd/hero_look.gd/player_body.gd/hero_body.gdshader (my scope), docs ARCHITECTURE.md ("Hero look v3" section) and HANDOFF.md ("Wave 112: hero look v3"). Two older tests whose assumptions legitimately changed were updated, not weakened: test_hero_look2 (samplers 9 -> 12) and test_director_round2_a (gear adds the kit's pieces: 63 vs 1).

TESTS: new tests/test_hero_look_v3.gd = 220 checks PASS (~25 s; kit/hardpoints, per-set build in budget, >=3 shrinking LODs with budgets, no black/white patches via atlas sampling, glow events and API, presets/unlocks/showcase rebuild counts, portraits exist, SUIT screen 32 buttons fit 844x390 and 1280x720 without overlap, VRAM import settings, live game: set_glow reaches the live material, flinch flashes, set change rebuilds). PASS also: test_hero_look, look2, superhero_hero, hero_customisation, hero_backlight, hero_polish, hero_animation_polish, hero_presentation, hero_verbs, hero_power, humanoid_variants, citizen_models, assets, character_motion, visual_followups, ui_debt, ui_kit_screens, menu_cut, menu_declutter, hud_declutter, title_buttons, visual_fixes4, localisation_complete/depth, campaign_runner, safehouses, demo_mode, story_acts, economy, perf_budget, low_plus, tier_switch_memory, npc_life, director_round2_a/d, round3_b, round5_b, menus_map_quality, save_robustness, weapon_crafting, weapons_available_display. Compatibility renderer (LOW) renders the hero correctly.

RENDERS / SELF-REVIEW (docs/shots/round6/, 10 jpg q80 + hero_iterations.md; scratch deleted): hero_before_after.jpg (real game: game camera, firing, SUIT screen, old HEAD vs new), hero_before_after_turntable.jpg, hero_turntable.jpg (front/side/back/3-4 at 2400x1080), hero_suits_six.jpg, hero_action.jpg (running, shooting, flight suit wing glow, flight suit from behind), hero_customisation.jpg, hero_lod_distance.jpg (15/40/80 m, plain + magnified), hero_glow_modes.jpg, hero_portraits.jpg, hero_variants.jpg (persons, female). 17 render-look-fix loops are listed in hero_iterations.md with the round-5 self-review: round 5 hero was a pale mannequin with speckled white boxes lost against the beach; now a dark silhouette with cloak, glowing pack, gorget, layered shoulders and cyan circuits that reads from behind, in motion and at 15 m (80 m is a ~15 px figure).

CONTRACTS FOR OTHER WAVES
- Wave 115: swing = HeroLook.set_glow(c, 1.4, &"flow"), flight = set_glow(c, 1.3, &"wings"), bomb throw = pulse_glow(c, 1.8, 0.4). Mount points: HeroSuit.hardpoint(&"emit_l"/&"emit_r"/&"wing_l"/&"wing_r"/&"core"/&"pack"/&"head") (model space). Release a layer with intensity 0.
- Wave 114/115 hold IK / snake poses: rig contract and hand bones unchanged; CharacterRig.find must run BEFORE the WristL/WristR empties are removed (my showcase hit this).
- Wave 117: HeroLook.hero_mode = true unlocks every suit/scheme/accent.
- The hero body is hidden while driving (Player._apply_vehicle_state sets body.visible=false), so there is no driving close-up of the hero (not a defect of this wave).

DEFECTS / GAPS OUTSIDE MY SCOPE
- test_director_fixes_b "zoomed in more is drawn, but never more than the zoom's cap (round 2 part D)" FAILS in the shared tree and PASSES on HEAD: caused by another builder's uncommitted scripts/ui/map_screen.gd / map_icons.gd (outskirts-map). Not touched by me.
- The landscape builder noted the hero's shadow was a hard dark parallelogram: it was the rectangular cloak plus pack; the cloak hem is now slanted and narrower (my scope, fixed).
- Known gaps: the female body wears the male-fitted kit rigidly per bone (plates sit a little proud over the bust); the breastplate is a smooth paint dome; glow modes differ mostly in the thin circuit lines (a bloom halo would sell them); wing mounts are folded panels (energy wings are the SNAKE wave's job); APK size is an estimate, not an export; nothing viewed on a real phone.
- Heads-up for the integrator: one more full suite and gate run after everyone's changes are merged; new class_name scripts need tools/import.sh (done in this tree; .uid files exist next to the new scripts).


## w112-critic-look

w112 LOOK critic report. About 60 phone-aspect frames (LOW and MED), all opened. Defects, status:
1 FIXED every bridge deck was a back face (road black since wave 105): bridge_kit.gd.
2 FIXED hero cape was a flat near-black board in every rear view (owner round 2 "black rectangle"): folded 14x12 cloth in the suit palette (parts.py, hero_suit.glb rebuilt, hero_body.gdshader).
3 FIXED sky showed pasted building rectangles at dawn/dusk (HDRI probes read sharp): sky.gdshader.
4 FIXED waterfall sheet/pool too grey and glary: fall_water.gdshader. The cliff beside it is still smooth clay.
5 FIXED branch road began as a hard dirt patch across the highway, z-fight of overlapping decks: terrain_roads.gd, terrain_road.gdshader, terrain_world.gd. A brown wedge still sits on the PASS ROAD deck end (needs the other critic or the roads owner).
6 FIXED LOW terrain strata ripples: terrain.gdshader (weaker, not gone).
7 NOT FIXED: old villages PINE HOLLOW and DUST WELLS are plain boxes; rivers in the mountains end in hard water slabs; palm fronds go black from below; tree LOD dither net; faceted kerb cars at LOW.
8 NOT FIXED: two orange wedges on the beach at 19:00 (once, not reproducible); BLACK MARKET DROP label sits on the compass (HUD).
Tests: test_critic_look_fixes (13) and the sky, hero, bridge, landscape, water, outskirts tests pass. test_terrain_world fails only the load-dependent far-tile check.
Perf gate: LOW OK 74/96 draws, 139.6k, 110 MB, death 108. MED OK 97/129, 272.5k, 141 MB, death 145. HIGH OK 113/149, 379.0k, 207 MB, death 166.
Sheets: docs/shots/round6/critic_look_*.jpg. Log: docs/sprint/progress/w112-critic-look.md. Not committed.


## w112-critic-play

Wave 112 critic, PLAY lens. 8 defects found with bots and audits and FIXED (working tree, nothing committed):
1. HARBOUR QUAY pad stood inside the harbour shed: a teleport dropped the hero through the world (roam_data.gd).
2. Every fast travel froze 0.8-1.25 s (phone 3-5 s); now 23-150 ms (terrain_world.gd settle_ground).
3. PASS ROAD had a 3.8-5 m wall where the RING ROAD crosses (8 crashes, wreck): crossings levelled (terrain_roads.gd).
4. DESERT ROAD 1-2.6 m bank in the lane at the OUTPOST junction: branch takes the parent's profile.
5. SUMMIT ROAD began on the PASS bridge with a second deck, car stuck at 7 m: shared widened deck (bridges.gd).
6. Viaduct piers in road lanes (rail_kit.gd).
7. Poplar trunk in the DESERT ROAD lane (veg_scatter.gd).
8. Map overview showed 26 pins, test_director_fixes_b red (map_screen.gd).
NOT fixed: outskirts LOW 61-171 draws vs 100 (city-only gate; wave 119); airport has no road; test_vehicle_roster has been cut off by a script error since wave 111 (tail fails 4 checks); PASS ROAD end lies under the SUMMIT embankment; test_terrain_world far-tile count is load-sensitive.
Tests: new test_play_critic_w112 (15), test_interior_reach_country (57 rooms clean); audits tools/drive_audit.sh, road_audit.sh, tests/bot_play_sweep.gd.
Perf: LOW OK 96 draws/139.8k/110 MB; MED OK 129/272.6k/141 MB; HIGH OK 149/378.8k/207 MB.
