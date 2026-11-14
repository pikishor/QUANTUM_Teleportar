# w113-weapons-blast (builder: BLAST-RADIUS ARSENAL; BlastTable, BlastFx, BlastOps, BlastPreview, weapon_defs_blast.gd)

GOAL: 60+ explosive and area weapons and gadgets, each with a real, visible and measurable blast radius, all through one BlastTable
that Game.explode consults; radius ring previews; blast visuals with strict per-tier budgets; tests/test_blast_arsenal.gd in the real scene.

STATUS (2026-11-14 03:25 UTC): DONE. The earlier agent with this label died at the usage limit before doing anything. 65 entries + 15 migrated legacy entries, 46 hero weapons, delivery,
looks, previews, world blasters, ULT key and button, tests (62 + 107 checks) green, 6 render-look-fix iterations at LOW and MED, perf gate OK on all three tiers, ARCHITECTURE.md section written.
Not committed (the integrator commits). Parallel builders: w113-weapons-roster (finished).

EXISTING BEFORE THIS WAVE (count): Game.explode had 29 call sites in 17 files; hero weapons with a blast: rocket, grenade, gravity, cmissile, napalm, sing, orbital, seeker, epod (+ eplasma_oc)
= 10 throw-kind defs; splash / stick / shock weapons railgun, chaingun, eplasma, espike, emaul; 6 explosive-ish throwables, 1 charge (C4); tank guns, howitzer, flak, 2 air rocket pods,
naval turrets, vehicle blast. About 45 distinct explosion kinds, none with a table, no knockback, one falloff (linear to 40 %), no hero rule, no true-radius previews except LaunchAim's ring.

FILES (mine): scripts/combat/{blast_table,blast_rows,blast_fx,blast_ops,blast_preview,blast_card,world_blasters}.gd, scripts/player/{weapon_defs_blast,weapon_models_blast}.gd,
assets/shaders/{blast_cloud,blast_dome,blast_column,blast_wall}.gdshader, assets/icons/w_*.png + wl_*.png (46 weapons, about 190 KB), tests/{test_blast_table,test_blast_arsenal,bot_blast_arsenal,bot_blast_hud}.gd,
docs/shots/round6/blast_arsenal_*.jpg (8) + blast_arsenal_iterations.md.
HOOKS in other files: game.gd (explode, ultimate key O), fx.gd, weapon_defs.gd (PACKS), player_weapon.gd, launch_aim.gd, charges.gd, throwables.gd, vehicle.gd, vehicle_weapons.gd, wildlife_world.gd,
weapon_models.gd, weapon_stats.gd, minimap.gd, touch_controls.gd (ULT in MORE), weapons_screen.gd (core ring in the blast diagram), tests/test_hud.gd (more_ult in the outer MORE column list),
explosion_pool.gd + fx_ground.gdshader + blast_marks.gd (tuning: smoke cover fade, ground flash gain and tightness for big blasts, debris and chunk shrink).

DONE: see ARCHITECTURE.md "Blast arsenal" (API, entry format, falloff, delivery, hero rules, previews, budgets, hooks, gaps).
Render-look-fix iterations (docs/shots/round6/blast_arsenal_iterations.md): 0 baseline 15 types, 1-3 LOW and MED, 4 other families, 5 the 12-type set, 6 final + phone HUD frames; every one opened
the frames and wrote 5 or more defects; fixed: glass-block beam, white-wall water column, EMP without dome, invisible well pre-phase, white ground plate, grey wall at the lens, round flame balls,
beacon through the fireball, boxy beam at 6 m, rings unreadable at 30 m (wall), label under the equip card; bot artefacts (white hit flash, husk car, dark first frame, stale first frame).

DECISIONS OTHER AGENTS DEPEND ON
- `BlastTable.get` cannot exist in GDScript (Object.get): the getter is `BlastTable.entry(id)`.
- Entry format: header of scripts/combat/blast_table.gd; BlastTable.register(id, {cat, name, radius, core, enemy, vehicle, element, ...}) then BlastTable.apply(id, pos, source, opts)
  or Game.explode(pos, r, {"blast": id, "source": node}). Wave 115 snake bombs and wave 116 aircraft use these.
- Aircraft ordnance: BlastOps.shared().drop(&"ord_bomb_dumb", from, vel, source); tank shells: BlastOps.shared().shell_blast(car, at) (BlastOps.cycle_shell()).
- Weapon ids gr_* / la_* / mn_* / st_*, families grenade / launcher / mine / strike, every def has `bid`; weapons with `utility: true` do no damage (show UTILITY, not damage).
- Ultimates: key O (action `ultimate`) and the ULT button of the MORE panel; hero mode or skill level 5 x n. BlastCard.draw_into(canvas, rect, entry, font) draws the radius card.

TESTS AND PERF: test_blast_table PASS (62), test_blast_arsenal PASS (107, 49 s). Re-run green: blasts_liquid_damage, breakables, combat_feel, energy_destructive_weapons, tanks, vehicle_weapons, vfx,
vfx_pass2, balance2, weapons, weapon_cards, weapons_depth, weapons_v3, hud, hud_declutter, touch, phone_readiness, world_hud. Perf gate (PERF_CHECK=1 tools/perf_report.sh 0 1 2) all OK:
LOW draws 63 total 100 tex 106 MB, MED 63 / 100 / 106 MB, HIGH 68 / 105 / 141 MB; a second LOW-only run (world blasters off, A/B) gave total 96 (the scene moves between runs: others landed code).
OPEN PROBLEMS (not mine): test_energy_destructive_scene expects ten wheel wedges, the roster's two-level wheel has 11 (classes + RECENT); test_audio_budget2: audio folder 24.5 MB over 24 MB (roster files);
CarDebris panels are unlit flat-colour boxes (tan squares at close range); the pooled car models keep the burnt look of their last life (VehicleVisual.repair, v2 branch).
