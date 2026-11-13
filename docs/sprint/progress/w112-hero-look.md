# w112-hero-look (builder notes; the earlier agent with this label did nothing: it hit the usage limit at once)

GOAL: hero look v3: layered tactical suit (armour kit fitted to the Quaternius body), face/eyes, HeroGlow API wired to the abilities, 3 LODs, 6 suit presets + colour options in the
customisation screen, portrait render, unlockable looks (gold, stealth, flight suit with wing mounts), fix the white leg rectangles. Test tests/test_hero_look_v3.gd. Skeleton / hand bones unchanged.

STATUS (updated 2026-11-13 18:20Z): everything is in the working tree and tested; left: docs (ARCHITECTURE, HANDOFF), final test sweep, final perf gate on the shared tree, cleanup of scratch, report.
Iterations done: 12 render-look-fix loops (kit shapes x5, pauldrons, cape chain, suit mask, palette x2 lavender -> gunmetal, lacquer paint, dark metal tint, boots, plate blotches), see docs/shots/round6/hero_iterations.md.

WHITE LEG RECTANGLES: real defect. They were the procedural box gear (HeroCharacter._gear_boxes: pale bevelled boxes on calf / thigh bones that floated off the legs when running). Replaced by the kit.

DONE (files)
- scripts/characters/hero_glow.gd   HeroGlow: layers (base steady pulse charge flow wings burst flicker alarm), zones (core arms hands legs wings head); sense(player) wires teleport aim + arrival, SUPERPOSITION,
  ENTANGLE, COLLAPSE, glide / flight, low health; hurt() / fired() from PlayerBody.flinch / fire_flash. API: HeroLook.set_glow(color, intensity, mode) / HeroLook.pulse_glow(color, intensity, secs).
  A layer set through the API is HELD (the sensor does not overwrite it) until released with intensity 0.
- scripts/characters/hero_suit.gd (kit loader, hardpoints), hero_character.gd (kit pieces, gloves, body surgery, UV2 circuit path, zone alpha, LOD sizes scheduled like the old hero's),
  hero_portrait.gd (committed + live portraits), assets/shaders/hero_body.gdshader (hero_style gate: NPC / enemy path untouched; kits kinds 6..13, atlas, glow zones).
- scripts/player/hero_look.gd (6 suits, palette, apply_material, unlocks, HERO MODE), player_body.gd (glow, events, look re-applied on tier change), economy.gd (one line).
- scripts/ui/hero_showcase.gd (live 3D preview, own studio + glow, capture()), look_screen.gd (rewritten, ids unchanged), hud.gd (3 one-line routes), story_cast.gd (hero = render),
  common/strings_hero.gd + 3 lines in strings.gd (ES / HI).
- tools/blender/herosuit/*.py + model_hero_suit.py (+ build_all.sh entry), tools/hero/{stage,loop,bake_portraits}.sh, tests/hero_stage, hero_portrait_bake, bot_superhero (phases 12-15).
- assets: hero_suit.glb (346 KB) + 3 atlas textures (830 KB), 7 webp portraits (60 KB), hero textures re-imported VRAM compressed + mips.

PERF (MED was the problem): the merged hero's LOD edge lengths were larger than the old hero's, so the engine kept finer LODs: +19.8k MED prims (hero, shadow proxy, mirror). Fixed by giving the
generated LODs the old hero's switch sizes (HeroCharacter.LOD_SCHEDULE): HEAD + hero changes only: LOW OK (96 draws, 139k prims, 115 MB), MED OK (130 draws, 274,440 prims vs HEAD 276,878, 146 MB vs 175),
HIGH OK (149 draws, 368,888 prims, 207 MB). Hero texture memory -29 MB. APK: +1.2 MB of assets (glb 346 KB, atlas 830 KB, webp 60 KB).

TESTS: tests/test_hero_look_v3.gd (220 checks) PASS; test_hero_look, look2, superhero_hero, hero_customisation, hero_backlight, visual_followups, ui_debt, localisation_* PASS.

DECISIONS (other agents depend on these)
- Glow API as above. Wave 115: swing = set_glow(c, 1.4, &"flow"), flight = set_glow(c, 1.3, &"wings"), snake bomb throw = pulse_glow(c, 1.8, 0.4). Hardpoints: HeroSuit.hardpoint(&"emit_l" / &"emit_r" /
  &"wing_l" / &"wing_r" / &"core" / &"pack" / &"head") (model space). HeroLook.hero_mode unlocks every suit / scheme / accent (wave 117).
- Kit sets (geometry): vanguard (standard, gilded, phase), stealth, assault, flight. A different SET rebuilds the hero; the same set only changes palette uniforms.
- CharacterRig.find must run BEFORE the wrist empties are removed. The hero body is hidden while driving (Player._apply_vehicle_state), so there is no driving close-up of the hero.

OPEN PROBLEMS / DEFECTS OUTSIDE MY SCOPE
- The shared working tree (others' uncommitted changes) was OVER on MED (294,476 prims) before the LOD schedule fix; a final gate run is in the report.
- Female body wears the male-fitted kit (rigid per bone): acceptable, bust plates sit a little proud.
