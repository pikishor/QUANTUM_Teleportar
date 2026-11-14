# w113-damage (builder: DAMAGE EVERYWHERE; enemies, civilians, vehicles, structures, props, ground liquid, caps per tier)

GOAL: visible, satisfying, stylised damage (12+/Teen, no gore) on people, cars, buildings and props; each weapon's blast level drives it;
StructureDamage.apply(pos, radius, level) in scripts/combat/structure_damage.gd; test tests/test_damage_everywhere.gd; render impact sequences (LOW + MED).

STATUS (2026-11-14 04:50 UTC): DONE. The earlier agent with this label died at the usage limit before doing anything. Not committed (the integrator commits).
All systems work end to end in the real scene; 12 render-look-fix iterations at LOW and MED (phone aspect 1200x540, every frame opened, 8+ defects each time); self-review done.
Neighbours: w113-weapons-blast owns blast_table / blast_fx / blast_preview (I only consume their API and the one guarded StructureDamage call); w113-weapons-roster owns weapon_defs_v3;
w113-enemy-look already declares `dmg_fx` in foe_body.gdshader (FoeFx sets it on humanoid_body).

DESIGN (observer, no enemy / car / weapon script rewritten): DamageWorld node (one line in main.gd) listens to Player.hit_confirmed + PlayerWeapon.last_shot, Game.exploded (+ BlastTable.last one
frame later) and the `died` signal of every enemy (10 Hz hook tick). Pools: ONE debris pool (Breakables.fling, 96 instances, live cap by tier), the shared puff cloud (BlastFx.puff), the BlastMarks
ring (new 24-slot STRUCTURE pool), ImpactDecals ring, car holes as shader uniforms. These scripts create no node. Switch QT_DMG=0 turns all new layers off (before / after frames).

DONE (files)
- scripts/damage/dmg.gd (switch, tier caps, counters, fluid colours), damage_world.gd (hub, fire fields, citizens), foe_fx.gd (zones, plates, limp, splatter, statuses, deaths, fling, shields, citizen hits),
  car_fx.gd (holes, glass stages, flat tyres, hood pop, shrapnel, burning wrecks, fire spread)
- scripts/combat/structure_damage.gd (apply: windows, chunk loss, breach, crater; staged per 3 m cell; debris ring, dust)
- scripts/fx/blast_marks.gd + assets/shaders/fx_marks.gdshader (structure pool, kinds 7 window, 8 breach, 9 crater, 10 spall scar)
- assets/shaders/fx_decals.gdshader + impact_decals.gd (bullet holes by material), player_weapon._hit_world picks the material, impact_sparks wood
- scripts/world/breakables.gd (fling(), wear stages, shaped debris, bench / planter / kiosk), scripts/enemies/enemy_cover.gd (breakable cover is real, broken cover is not)
- car_v2.gd + car_common / car_paint (double sided, ribbed steel liner) / car_glass / car_details shaders, hero_body.gdshader (dmg_fx: burn, frozen, shock, dissolve)
- tests/test_damage_everywhere.gd (101 checks, real scene, 25 s), tests/bot_damage.gd (look-dev: DM_SCENES, DM_OUT, DM_SPOT), tests/test_blasts_liquid_damage.gd (marks bound)
- docs/shots/round6/damage_{wall,car,enemy}_before_after.jpg, damage_burn_states.jpg, damage_blast_street.jpg (5 jpg, quality 80), ARCHITECTURE.md "Damage everywhere"

LOOKED AT (defects fixed): bullet holes invisible (hull box not the shell: analytic body), roof counted as glass, popped hood vanished from the front, hood underside a black hole (ribbed steel liner),
instant noisy glass web (stages), pockmarks and spall scars like eyes (ragged patches with a shaded lip), window marks a beige blur (dark opening, jagged teeth), white square chunks (darker palette),
hero aura sphere tinting close free cameras (hidden in the bot), wall that took a rocket and showed nothing (staged windows, scar, breach, crater), wall splats floating, debris ring over the tier cap.

TESTS AND PERF: test_damage_everywhere PASS (101); also PASS: test_breakables, test_blast_table, test_blasts_liquid_damage, test_player_polish, test_player_robustness, test_cars_v2, test_ai_tactics2,
test_vfx, test_visual_fixes2, test_vehicle_paint, test_enemy_types, test_real_fight, test_interiors_world. test_soak_quick failed ONCE by 0.4 nodes (4680 vs limit 4679.6), PASS on the re-run (4650) and with QT_DMG=0: the growth is
far-tile and wildlife streaming (probe: no class of these scripts in the growth, layers ON and OFF within noise).
Perf gate (PERF_CHECK=1 tools/perf_report.sh 0 1 2), one run, all OK: LOW total draws 96, 139k tris, 110 MB tex, death spike 107; MED 129, 271k, 141 MB, spike 148; HIGH 149, 380k, 207 MB, spike 170.
APK: no textures or models added (shaders + scripts; the decal texture was removed): no growth.

DECISIONS OTHER AGENTS DEPEND ON
- Breakables.fling(pos, vel, color, size, aspect, life) is the one pooled debris API; Dmg.cap(key) / Dmg.bump(key) caps and counters; FX.marks.window_broken / breach / crater / chip (structure pool).
- BlastTable calls StructureDamage.apply(pos, radius, level) (level 0..3 is a column of blast_rows.gd). Enemy bodies: `died`, hp / max_hp, center(), group "enemy", camp, humanoid_body with `dmg_fx`.
- QT_DMG=0 disables my layers.

OPEN PROBLEMS: no liquid splatter on cars (hull box is not the shell); citizens react at the place of the hit (puffs) but do not stumble (crowd is one MultiMesh); fires do not spread to buildings; no ragdoll physics (one pooled
tumble integrator); nothing measured on a phone. Out of scope: test_energy_destructive_scene expects ten wheel wedges, the roster's wheel has 11 (roster builder); the hero's aura sphere tints
very close cameras (hero look); the street around the look-dev spot has overhead beams that occlude the blast frames (bot camera only).
