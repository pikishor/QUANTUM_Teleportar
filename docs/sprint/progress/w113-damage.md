# w113-damage (builder: DAMAGE EVERYWHERE; enemies, civilians, vehicles, structures, props, ground liquid, caps per tier)

GOAL: visible, satisfying, stylised damage (12+/Teen, no gore) on people, cars, buildings and props; each weapon's blast level drives it;
StructureDamage.apply(pos, radius, level) in scripts/combat/structure_damage.gd; test tests/test_damage_everywhere.gd; render impact sequences (LOW + MED).

STATUS (2026-11-14 05:40 UTC): restart notice. The earlier agent with this label died at the usage limit before doing anything. Core systems written; tests/test_damage_everywhere.gd passes (91 checks, 25 s, real scene);
render loops started (wall facade breach looks right in the real camera; enemy plates/splatter/statuses and car holes still being tuned).
Neighbours: w113-weapons-blast owns blast_table/blast_fx/blast_preview (I consume their API and hooks only); w113-weapons-roster owns weapon_defs_v3.gd.

DESIGN (observer, no enemy script changed): DamageWorld node (main.gd, one line) listens to Player.hit_confirmed + PlayerWeapon.last_shot, Game.exploded (+ BlastTable.last one frame later) and the `died` signal of every enemy.
Pools: ONE debris pool (Breakables.fling, 96 instances, live cap by tier), the shared puff cloud (BlastFx.puff), the BlastMarks ring (new STRUCTURE pool of 24 slots), ImpactDecals ring (bullet holes), shader uniforms for car holes.
Switch QT_DMG=0 turns all new layers off (before/after frames).

DONE (files)
- scripts/damage/dmg.gd (switch, tier caps, counters, fluid colours), damage_world.gd (hub), foe_fx.gd (zones, plates, limp, splatter, statuses, deaths, fling), car_fx.gd (holes, glass, tyres, hood, wrecks, spread)
- scripts/combat/structure_damage.gd (StructureDamage.apply: windows, chunk loss, breach, crater, staged per 3 m cell, debris ring, dust)
- scripts/fx/blast_marks.gd (+ structure pool: window_broken, breach, crater, chip), assets/shaders/fx_marks.gdshader (kinds 7-10)
- assets/shaders/fx_decals.gdshader + scripts/player/impact_decals.gd (bullet holes by material: concrete, metal, glass, wood, asphalt), player_weapon._hit_world picks the material, impact_sparks wood
- scripts/world/breakables.gd (fling(), shaped debris, ground per piece, 3 new kinds: bench, planter, kiosk)
- car shaders: car_common (holes, hood pop), car_paint, car_glass (star cracks at holes), car_details (flat tyre), scripts/vehicles/car_v2.gd (add_hole, set_hood_pop, set_wheel_flat, shatter_glass), hero_body.gdshader (dmg_fx states)
- tests/bot_damage.gd (look-dev bot: DM_SCENES=enemy,car,wall,blast,burn), baseline frames in the scratchpad (docs/shots/round6 sheet at the end)

NEXT
1. Compile/run check, then render loops: wall (holes, windows, chunks, breach), car (holes, glass, tyre, hood, wreck fire), enemy (plates, splatter, statuses, deaths) at LOW and MED.
2. EnemyCover: Breakables bodies as cover + broken ones are not cover; civilians (crowd) death variants; fire spread on props.
3. tests/test_damage_everywhere.gd (real scene), update the BlastMarks bound in tests/test_blasts_liquid_damage.gd (cap_struct), run touched tests, perf gate (mid-way and at the end), ARCHITECTURE.md section, contact sheet docs/shots/round6/damage_*.jpg.

DECISIONS OTHER AGENTS DEPEND ON
- FOR THE ENEMY LOOK BUILDER (w113-enemy-look): I observe, I do not edit enemy scripts. What I need from every enemy body: `died` signal (Drone/AlienCreature have it), `hp`, `max_hp`, `center()`, `radius`, group "enemy" while alive,
  `camp` (or `faction`) for the fluid colour, `humanoid_body` (a MeshInstance3D) whose shader declares `instance uniform vec4 dmg_fx = vec4(0.0);` (x state 1 burn / 2 frozen / 3 shock / 4 dissolve, y strength 0..1):
  hero_body.gdshader has it; copy the 20 lines `dmg_emis` of its fragment() into a new body shader (foe_body) and FoeFx._shader sets it. A model child node `model` (Node3D) is scaled / hidden for dissolve and ice shatter deaths.
  Armour plates that fly off are pooled debris (Breakables.fling), so a kit with real separate plate meshes only needs to hide the plate it loses (FoeFx._plate_off is the one place: call your own hide there).
- Breakables.fling(pos, vel, color, size, aspect, life): the one pooled debris API (any system); Dmg.cap(key)/Dmg.bump(key) for caps and counters; FX.marks.window_broken/breach/crater/chip (structure pool).
- BlastTable calls StructureDamage.apply(pos, radius, level) by itself (its guarded call now finds the file). level comes from the row (`level` 0..3).
- QT_DMG=0 disables my layers.

TESTS AND PERF: test_damage_everywhere.gd PASS (91 checks), test_blasts_liquid_damage.gd PASS (old). Perf gate not run yet (plan: once now, once at the end).
OPEN PROBLEMS: tests/test_blasts_liquid_damage.gd line ~181 bound must include BlastMarks.cap_struct (my structure pool).
