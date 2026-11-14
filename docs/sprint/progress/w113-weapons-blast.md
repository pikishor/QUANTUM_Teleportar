# w113-weapons-blast (builder: BLAST-RADIUS ARSENAL; BlastTable, BlastFx, BlastOps, BlastPreview, weapon_defs_blast.gd)

GOAL: 60+ explosive and area weapons and gadgets, each with a real, visible and measurable blast radius, all through one BlastTable
that Game.explode consults; radius ring previews; blast visuals with strict per-tier budgets; tests/test_blast_arsenal.gd in the real scene.

STATUS (2026-11-14 01:55 UTC): the earlier agent with this label died at the usage limit before doing anything. Core, delivery, 46 weapons, models, icons, world blasters,
previews, tests written; test_blast_table.gd (62 checks) and tests/test_blast_arsenal.gd (107 checks, real scene) PASS; legacy tests re-run green except the weapon wheel check of
test_energy_destructive_scene (11 wedges: the roster agent's new wheel, not mine). Now in the render-look-fix loops (tests/bot_blast_arsenal.gd, LOW then MED), then ULT button check,
perf gate (once at the end), ARCHITECTURE.md section, contact sheet.
Parallel builders: w113-weapons-roster (PACKS hook, weapon_defs_v3.gd, two agents, one does wheel/catalogue UI).

EXISTING BEFORE THIS WAVE (count): Game.explode had 29 call sites in 17 files; hero weapons with a blast: rocket, grenade, gravity, cmissile, napalm, sing, orbital, seeker, epod (+ eplasma_oc)
= 10 throw-kind defs; splash / stick / shock weapons railgun, chaingun, eplasma, espike, emaul; 6 explosive-ish throwables, 1 charge (C4); tank guns, howitzer, flak, 2 air rocket pods,
naval turrets, vehicle blast. About 45 distinct explosion kinds, none with a table, no knockback, one falloff (linear to 40 %), no hero rule, no true-radius previews except LaunchAim's ring.

FILES (mine): scripts/combat/{blast_table,blast_rows,blast_fx,blast_ops,blast_preview,blast_card,world_blasters}.gd, scripts/player/{weapon_defs_blast,weapon_models_blast}.gd,
assets/shaders/{blast_cloud,blast_dome,blast_column}.gdshader, assets/icons/w_*.png + wl_*.png (46 weapons), tests/{test_blast_table,test_blast_arsenal,bot_blast_arsenal}.gd.
HOOKS in other files (one or few lines each): autoload/game.gd explode -> BlastTable.explode + ACTION_KEYS ultimate (O); autoload/fx.gd WorldBlasters; weapon_defs.gd PACKS; player_weapon.gd _throw
(bid) and _collapse (blast id + dmg_mult); launch_aim.gd; charges.gd; throwables.gd; vehicle.gd (wb_car); vehicle_weapons.gd (tank shells); wildlife_world.gd; weapon_models.gd; weapon_stats.gd;
minimap.gd (beacons); touch_controls.gd (ULT button in MORE); explosion_pool.gd (two tuning numbers: smoke cover fade, ground flash gain for big blasts).

DONE
- BlastTable (entry/has_entry/ids/ids_in/count/register/unregister/apply/explode/factor/damage_at/share/animal_damage/radius_of_def, legacy migration, falloff flat/linear/quad, cover, hero rule,
  civilians by curve, knockback and lift, statuses, deferred pre-phase) + 65 rows in BlastRows (12 grenades, 14 launchers, 10 mines, 10 strikes, 9 ordnance, 6 ultimates, 4 world) + 15 legacy entries.
- WeaponDefsBlast 46 weapons in the BLAST wheel class; BlastOps (projectiles, mines, markers, strikes, drops, ultimates, zones, bodies); BlastFx (cloud pool, domes, columns, jet, meteor, flash);
  BlastPreview, BlastCard (radius to scale beside a person), WorldBlasters (barrel, gas tank, fuel truck), tank shells HE / AP / CLUSTER.
- Render-look-fix iteration 0 (baseline LOW, 15 types x 3 distances) and iteration 1 (6 types x 2 distances) done; defects found and fixed so far: cloud puffs filled the screen next to the lens (near
  fade in blast_cloud), big ground flash plate, orbital beam looked like a glass block (new blast_column shader, narrower), depth-charge water was a white wall (narrow column with a head), EMP had no
  dome, well pre-phase had no visible bubble (shrinking dome), bot artefacts (stuck white hit flash because the bot froze enemy physics, husk car reuse, first frames dark from the teleport fade).

NEXT
1. Iterations 2..6 at LOW and MED (12-15 types x 3 distances), contact sheet docs/shots/round6/blast_arsenal_*.jpg (<=12 jpg, q80), delete scratch frames.
2. test_touch / test_hud_declutter with the ULT button, perf gate once, ARCHITECTURE.md section "Blast arsenal", re-run my tests and affected legacy tests, final report.

DECISIONS OTHER AGENTS DEPEND ON
- `BlastTable.get` cannot exist in GDScript (Object.get): the getter is `BlastTable.entry(id)`.
- Entry format: see the header of scripts/combat/blast_table.gd; register a bomb with BlastTable.register(id, {cat, name, radius, core, enemy, vehicle, element, ...}) then
  `BlastTable.apply(id, pos, source, opts)` (or Game.explode(pos, r, {"blast": id, "source": node})). Wave 115 snake bombs and wave 116 aircraft use these.
- Aircraft ordnance: `BlastOps.shared().drop(&"ord_bomb_dumb", from, vel, source)`; tank shells: `BlastOps.shared().shell_blast(car, at)` (selected with BlastOps.cycle_shell()).
- Weapon ids: gr_* (grenades), la_* (launchers), mn_* (mines), st_* (strikes); families grenade / launcher / mine / strike (names WeaponDefsBlast.FAMILY_NAMES); every def has `bid`.
- Roster/UI agents: weapons with `utility: true` do no damage (flash, smoke, EMP, freeze): show "UTILITY" instead of damage on cards. BlastCard.draw_into(canvas, rect, entry, font) draws the radius card.
- Ultimates: key O (action `ultimate`) and the ULT button of the MORE panel; unlocked by hero mode or skill level 5 x n.

TESTS AND PERF: test_blast_table.gd PASS (62), test_blast_arsenal.gd PASS (107). Perf gate not yet run (one run at the very end).
OPEN PROBLEMS (not mine): roster agent's weapon wheel wedge count in test_energy_destructive_scene; audio folder over test_audio_budget2's 24 MB limit from the roster's files.
