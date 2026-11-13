# w112-hero-look (builder notes; the earlier agent with this label did nothing: it hit the usage limit at once)

GOAL: hero look v3: layered tactical suit (armour kit fitted to the Quaternius body), face/eyes, HeroGlow API wired to the abilities, 3 LODs, 6 suit presets + colour options in the
customisation screen, portrait render, unlockable looks (gold, stealth, flight suit with wing mounts), fix the white leg rectangles. Test tests/test_hero_look_v3.gd. Skeleton / hand bones unchanged.

STATUS (updated 2026-11-13 16:55Z): kit pipeline + glow + presets done and in the game; the SUIT screen is rebuilt (live 3D showcase, suit cards, scheme chips, accent swatches, person row) and passes
the existing UI tests; now: portraits baked from the showcase, StoryCast hook, kit polish loops (palette done once: plates were lavender, now gunmetal), tests v3, perf gate, contact sheet, docs.

WHITE LEG RECTANGLES: real defect. They were the procedural box gear (HeroCharacter._gear_boxes: pale bevelled boxes on calf / thigh bones that floated off the legs when running). Replaced by the kit.

DONE (files)
- scripts/characters/hero_glow.gd   HeroGlow: layers (base steady pulse charge flow wings burst flicker alarm), zones (core arms hands legs wings head), sense(player) wires teleport aim (charge) + arrival
  flash, superposition (pulse), entangle (steady magenta), collapse (flash + flicker), glide / flying (wings), low health (alarm); hurt() / fired() from PlayerBody.flinch / fire_flash.
  Public API: HeroLook.set_glow(color, intensity, mode) / HeroLook.pulse_glow(color, intensity, secs) (static, live hero).
- scripts/characters/hero_suit.gd   HeroSuit: loads assets/models/hero_suit.glb (extras: bone kind zone sets), pieces(set, bones) -> comps for HeroCharacter; hardpoint(name); path_coord.
- scripts/characters/hero_character.gd   suit option (kit set), kit pieces instead of boxes, gloves, body surgery (feet cut under boots, hands decimated), UV2.x circuit path, COLOR.a glow zone.
- assets/shaders/hero_body.gdshader   hero_style (1 = the player's hero, 0 = NPC / enemy legacy path UNCHANGED), gear kinds 6..13, atlas sampling, glow zones + travelling wave, eye iris glow.
- scripts/player/hero_look.gd   6 suit presets (standard=VANGUARD, stealth, assault, flight, gilded, phase), palette(), apply_material(), kit_set(), HERO MODE flag, unlock rules, tags; Economy.SUIT_PRICE one line.
- scripts/player/player_body.gd   glow object + registration (HeroGlow.primary), update_glow(dt), palette uniforms, event hooks (flinch, fire_flash).
- scripts/ui/hero_showcase.gd (NEW)   SubViewport with its own studio: the real hero model on a turntable, own HeroGlow, capture(look, frame, yaw) -> Image; freed after 12 idle seconds.
- scripts/ui/look_screen.gd (REWRITTEN)   hero plate left; right: 3x2 suit cards (picture, name, state, unlock hint), 8 scheme chips, 12 swatches, person row, ACCENT BUY, BACK. Button ids unchanged.
  hud.gd: three one-line hooks (tap, _pv_turn, end_drag route a drag on the hero plate to HeroShowcase).
- scripts/characters/hero_portrait.gd (NEW)   committed portraits (assets/ui/hero_portrait.webp, hero_suit_<id>.webp), live capture + cache for other looks, compose() backdrop.
- tools/blender/herosuit/*.py + model_hero_suit.py   conformal armour kit (rays at the real body mesh), ~5k triangles per set.
- tools/hero/{stage.sh,loop.sh,patch_hero_imports.py,bake_suit_mask.py,bake_portraits.sh}, tests/hero_stage.{gd,tscn}, tests/hero_portrait_bake.{gd,tscn}   look-dev stage + portrait bake.
- Hero textures re-imported VRAM compressed with mipmaps: hero texture memory 47.7 MB -> 18.4 MB (incl. the new 1K atlas) at MED.

NEXT
1. bake portraits (tools/hero/bake_portraits.sh) + StoryCast hero hook; kit polish loops (cape, boots, breastplate gloss, stealth / assault / flight variants), female fit, LOD checks.
2. tests/test_hero_look_v3.gd; perf gate PERF_CHECK=1 tools/perf_report.sh 0 1 2; contact sheet docs/shots/round6/hero_before_after.jpg; ARCHITECTURE.md + HANDOFF.md.

DECISIONS (other agents depend on these)
- Glow API: HeroLook.set_glow(color, intensity, mode) / HeroLook.pulse_glow(color, intensity, seconds); modes &"steady" &"pulse" &"charge" &"flow" &"wings" &"flicker" &"burst"; intensity <= 0 releases.
  Wave 115: swing = set_glow(c, 1.4, &"flow") (energy runs core -> hands), flight = set_glow(c, 1.3, &"wings"), snake bomb throw = pulse_glow(c, 1.8, 0.4).
- Hardpoints for wave 115: HeroSuit.hardpoint(&"emit_l"/&"emit_r"/&"wing_l"/&"wing_r"/&"core"/&"pack"/&"head") (model space).
- HeroLook.hero_mode (static bool) unlocks every suit / scheme / accent (wave 117 sets it).
- Kit sets (geometry): vanguard (standard, gilded, phase), stealth, assault, flight. A different SET rebuilds the hero; a different suit of the same set only changes palette uniforms.
- NPC / enemy shader path is untouched (hero_style = 0). CharacterRig.find must run BEFORE the wrist empties are removed (showcase learned it the hard way).

TESTS AND PERF
- existing: test_hero_look2, test_visual_followups, test_ui_debt, test_hero_customisation, test_superhero_hero pass with the new screen. Hero MED: 16.2k triangles, 1 surface, 1 draw.

OPEN PROBLEMS / DEFECTS OUTSIDE MY SCOPE
- (none yet)
