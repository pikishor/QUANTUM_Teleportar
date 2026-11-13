# w112-hero-look (builder notes; the earlier agent with this label did nothing: it hit the usage limit at once)

GOAL: hero look v3: layered tactical suit (armour kit fitted to the Quaternius body), face/eyes, HeroGlow API wired to the abilities, 3 LODs, 6 suit presets + colour options in the
customisation screen, portrait render, unlockable looks (gold, stealth, flight suit with wing mounts), fix the white leg rectangles. Test tests/test_hero_look_v3.gd. Skeleton / hand bones unchanged.

STATUS (updated 2026-11-13 19:35Z): DONE and verified, nothing committed (working tree only). 17 render-look-fix loops (docs/shots/round6/hero_iterations.md), 10 contact sheets in
docs/shots/round6/hero_*.jpg, docs written (ARCHITECTURE.md "Hero look v3", HANDOFF.md "Wave 112: hero look v3"), scratch deleted. Left for the integrator: commit, full suite, one more gate.

WHITE LEG RECTANGLES: real defect. They were the procedural box gear (HeroCharacter._gear_boxes: pale bevelled boxes on calf / thigh bones that floated off the legs when running). Replaced by the kit.

DONE (files)
- scripts/characters/hero_glow.gd   HeroGlow: layers (base steady pulse charge flow wings burst flicker alarm), zones (core arms hands legs wings head); sense(player) wires teleport aim + arrival, SUPERPOSITION,
  ENTANGLE, COLLAPSE, glide / flight, low health; hurt() / fired() from PlayerBody.flinch / fire_flash. API: HeroLook.set_glow(color, intensity, mode) / HeroLook.pulse_glow(color, intensity, secs).
  A layer set through the API is HELD (the sensor does not overwrite it) until released with intensity 0.
- scripts/characters/hero_suit.gd (kit loader, hardpoints), hero_character.gd (kit pieces, gloves, body surgery, UV2 circuit path, zone alpha, LOD sizes scheduled like the old hero's),
  hero_portrait.gd (committed + live portraits), assets/shaders/hero_body.gdshader (hero_style gate: NPC / enemy path untouched; kit kinds 6..13, atlas, glow zones).
- scripts/player/hero_look.gd (6 suits, palette, apply_material, unlocks, HERO MODE), player_body.gd (glow, events, look re-applied on tier change), economy.gd (one line).
- scripts/ui/hero_showcase.gd (live 3D preview, own studio + glow, capture()), look_screen.gd (rewritten, ids unchanged), hud.gd (3 one-line routes), story_cast.gd (hero = render),
  common/strings_hero.gd + 3 lines in strings.gd (ES / HI), demo_mode.gd (grants achievement rewards).
- tools/blender/herosuit/*.py + model_hero_suit.py (+ build_all.sh entry), tools/hero/{stage,loop,bake_portraits}.sh + patch_hero_imports.py + bake_suit_mask.py, tests/hero_stage, hero_portrait_bake,
  bot_superhero (phases 12-15), tests/test_hero_look_v3.gd (220 checks).
- assets: hero_suit.glb (346 KB) + 3 atlas textures (830 KB), 7 webp portraits (60 KB), hero textures re-imported VRAM compressed + mips (skin ETC2/DXT1, body normals 1K).

PERF: shared tree, final gate: LOW OK (96 total draws, 139.7k prims, tex 110 MB), MED OK (129, 272.2k, 141 MB), HIGH OK (149, 377.8k, 207 MB). HEAD + only my files: MED 274.4k (HEAD 276.9k), tex -34 MB.
The merged hero's LOD edge lengths had kept fine LODs (+19.8k MED prims) until LOD_SCHEDULE gave the generated LODs the old hero's switch sizes. APK about +7.5 MB (estimated, not exported).

TESTS: test_hero_look_v3 PASS; hero, UI, localisation, demo, story, character and perf tests PASS (list in HANDOFF.md). Fixed two tests whose old assumptions changed (sampler count, gear pieces)
and demo_mode (achievement reward suit).

DECISIONS (other agents depend on these)
- Glow API as above. Wave 115: swing = set_glow(c, 1.4, &"flow"), flight = set_glow(c, 1.3, &"wings"), snake bomb throw = pulse_glow(c, 1.8, 0.4). Hardpoints: HeroSuit.hardpoint(&"emit_l" / &"emit_r" /
  &"wing_l" / &"wing_r" / &"core" / &"pack" / &"head") (model space). HeroLook.hero_mode unlocks every suit / scheme / accent (wave 117).
- Kit sets (geometry): vanguard (standard, gilded, phase), stealth, assault, flight. A different SET rebuilds the hero; the same set only changes palette uniforms.
- CharacterRig.find must run BEFORE the wrist empties are removed. The hero body is hidden while driving (Player._apply_vehicle_state), so there is no driving close-up of the hero.

OPEN PROBLEMS / DEFECTS OUTSIDE MY SCOPE
- test_director_fixes_b ("zoomed in more is drawn, but never more than the zoom's cap") fails in the shared tree, passes on HEAD: the outskirts-map builder's uncommitted map_screen.gd / map_icons.gd.
- Female body wears the male-fitted kit (rigid per bone): acceptable, bust plates sit a little proud. Glow modes differ mostly in the thin circuit lines.
