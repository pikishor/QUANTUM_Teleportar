# w112-hero-look (builder notes; started 2026-11-13 ~15:00Z; the earlier agent with this label did nothing: it hit the usage limit at once)

GOAL: hero look v3: layered tactical suit with real armour (shoulder, forearm, shin guards), a face with structure, quantum circuit glow API
(HeroLook.set_glow(color, intensity, mode) wired to teleport / superposition / entangle / collapse / glide / flight / fire / damage), 3 LODs, 6 suit presets
with colour options, portrait render for menus and story cast, unlockable looks (gold hero, stealth, flight suit with wing mounts), fix the white rectangles on the legs
(if real). Test tests/test_hero_look_v3.gd. Skeleton + hand bones stay compatible with the animation library (wave 114 hold IK, wave 115 snake poses).

STATUS: just started (step 0: read the code).

DONE
- (nothing yet)

NEXT
1. Baseline renders of the current hero (turntable, running, 15 / 40 / 80 m) and a defect list; find the white leg rectangles.
2. Blender-made armour kit (tools/blender/hero_suit_kit.py) -> assets/models/hero_suit_*.glb, merged by HeroCharacter into the one hero surface.
3. HeroGlow API (scripts/characters/hero_glow.gd) + wiring; presets in HeroLook; customisation screen; portrait.
4. tests/test_hero_look_v3.gd, perf gate, contact sheet docs/shots/round6/hero_before_after.jpg, docs.

DECISIONS (other agents depend on these)
- (to be filled)

TESTS AND PERF
- (none yet)

OPEN PROBLEMS
- (none yet)
