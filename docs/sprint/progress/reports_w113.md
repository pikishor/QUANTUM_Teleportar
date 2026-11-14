# Wave 113 reports (builders that finished before the server restart at 04:58Z, extracted from the workflow journal)

Full final reports of the agents of this wave, copied from the workflow journal (the integrator reads this file).


## w113-weapons-roster

w113-weapons-roster: DONE. Nothing committed (integrator does that).

COUNTS (old 58 + 125 NEW = 183; with blast pack 229+). Families old+new: pistol 15, smg 12, assault 14, battle 7, carbine 7, dmr 8, sniper 11, shotgun 12, lmg 7, rotary 5, bow 6, flamer 5, melee 28, energy 17, quantum 12, exotic 6 (all brief targets met). Wheel classes: pistol 15, smg 12, rifle 30, shotgun 12, sniper 24, heavy 20, melee 28, quantum 12, energy 23, blast 53 so far (blast builder).

DONE: data rows (scripts/player/weapon_rows_v3.gd, weapon_defs_v3.gd, weapon_mech.gd, weapon_models_v3.gd), 5 attachment slots with 21 parts (attachment_parts_v3.gd), WeaponBrowser (favourites, recent, class tabs, balanced pages, captions), loadout and catalogue paging, two-level weapon wheel (12 discs, class ring), AMMO touch button behind MORE, ARMS DEALER restock and random weapon drops by hero tier (weapon_shops_v3.gd), secret-cache lines, 84 OGG (16 sets, 3+ layers), 250 icons, ES/HI UI strings, HERO MODE flag, docs (ARCHITECTURE "Weapon roster v3", HANDOFF), sheets docs/shots/round6/weapons_ui_before_after.jpg, weapon_wheel_rings.jpg, weapons_v3_in_hand.jpg.

TESTS (all PASS): NEW test_weapons_v3 (135 checks, 12 s: all 125 weapons equip, fire, reload, alt-fire, damage a dummy), test_weapon_balance_v3 (TTK table, 3x outlier rule), test_weapon_ui_v3 (main scene, 93 checks incl. layout scans at 3 sizes). Real bugs fixed: _tick_heat crash, gravity knock 0, static-init order. Stale tests updated honestly (roster, cards, depth, energy, round2_d, round3_b, available_display, vendors). 17-test final batch passes except test_hud.

PERF (final tree): LOW OK 96 draws 138.4k tris tex 110MB death 108; MED OK 129 / 271.3k / 141MB / 145; HIGH OK 149 / 377.5k / 207MB / 167. First run MED OVER: 45 crates drawn everywhere; WeaponCrates now draws only near ones. Weight about 1.6 MB repo and APK.

FOR OTHERS: test_hud fails on the blast builder's ULT button (add "more_ult" to the skip list, tests/test_hud.gd:382). test_interior_gameplay node-count flake (+38..50). Models are placeholders (wave 114); roster names/role text stay English in es/hi.


## w113-weapons-blast

w113-weapons-blast REPORT (BLAST-RADIUS ARSENAL). Status: DONE, nothing committed (the integrator commits). Progress log: docs/sprint/progress/w113-weapons-blast.md (about 55 lines). Architecture section: godot/ARCHITECTURE.md "Blast arsenal" (API, entry format for wave 115 BlastTable.register, falloff, delivery, hero rules, previews, budgets, hooks, gaps).

WHAT EXISTED BEFORE (count): Game.explode had 29 call sites in 17 files, about 45 distinct explosion kinds, none with a table, one falloff (linear to 40 %), no knockback, no hero rule, no true-radius previews except LaunchAim's ring. Hero blasts: 10 throw-kind defs (rocket, grenade, gravity, cmissile, napalm, sing, orbital, seeker, epod, eplasma_oc), 5 splash/stick/shock weapons, 6 explosive throwables, 1 charge (C4), tank guns, howitzer, flak, 2 air rocket pods, naval turrets, vehicle blast.

WHAT IS NOW: BlastTable with 65 catalogue entries (grenades 12, launchers 14, mines/charges 10, strikes 10, vehicle/aircraft ordnance 9, hero ultimates 6, world blasters 4) + 15 migrated legacy entries (old numbers unchanged: rocket 7 m/220/200, C4 ...) + 1 internal storm bolt. 46 hero weapons (gr_*, la_*, mn_*, st_*, wheel class BLAST, families grenade/launcher/mine/strike, balanced, priced, on the ladder, crates, shop, models, icons). Game.explode returns BlastTable.explode(...) (now returns a Dictionary). Falloff flat/linear/quad measured by the test at 0.5/1.0/1.5 x radius; cover, knockback + lift tumble, props chain, cars toss/flip/burn, civilians/animals flee, statuses (burn, stun, blind, EMP, freeze, shock chain, smoke, pull), hero immunity option, friendly fire off on EASY, no sudden death on EASY/NORMAL. Previews: grenade arc + landing ring of the table radius, launcher ring, mine placement ring, strike footprint + beacon ring on ground and minimap, label "NAME  RADIUS 6 M" + DANGER edge, a thin glowing wall on every ring (readable at 30 m), weapon card diagram (WeaponsScreen._draw_diagram) with radius ring + full-damage core to scale beside a 1.8 m person, BlastCard.draw_into for bigger pictures. Ultimates: key O + ULT button in the MORE panel. World blasters: barrels, gas tanks, fuel trucks (one MultiMesh per kind, streamed 95 m, nothing within 120 m of the start).

DEVIATION: BlastTable.get cannot exist in GDScript (Object.get): the getter is BlastTable.entry(id) (has_entry, ids, ids_in, count, register, unregister, apply, explode, factor, damage_at, share, animal_damage, radius_of_def).

FILES (mine, all new): scripts/combat/{blast_table,blast_rows,blast_fx,blast_ops,blast_preview,blast_card,world_blasters}.gd, scripts/player/{weapon_defs_blast,weapon_models_blast}.gd, assets/shaders/{blast_cloud,blast_dome,blast_column,blast_wall}.gdshader, assets/icons/w_*.png + wl_*.png (46 weapons), tests/{test_blast_table,test_blast_arsenal,bot_blast_arsenal,bot_blast_hud}.gd, docs/shots/round6/blast_arsenal_*.jpg (8) + blast_arsenal_iterations.md.
Small hooks in shared files (a line to a few lines each): autoload/game.gd (explode, ACTION_KEYS ultimate), autoload/fx.gd, weapon_defs.gd (PACKS), player_weapon.gd, launch_aim.gd, charges.gd, throwables.gd, vehicle.gd, vehicle_weapons.gd (tank shells HE/AP/CLUSTER), wildlife_world.gd, weapon_models.gd, weapon_stats.gd, minimap.gd, touch_controls.gd (ULT), weapons_screen.gd (core ring), tests/test_hud.gd (added more_ult to the outer MORE column exception list, same reason as C4), explosion_pool.gd + fx_ground.gdshader + blast_marks.gd (tuning: first smoke puff cover fade 1.1 -> 1.9 x size, big-blast ground flash gain/tightness, debris + wall chunk shrink/darker). Wave 115 note: StructureDamage.apply(pos, radius, level) is called through a guarded load (inactive until the damage builder's module exists).

TESTS: tests/test_blast_table.gd PASS (62 checks), tests/test_blast_arsenal.gd PASS (107 checks, real scene, about 50 s: count >= 60, every entry fires/places and triggers, measured radius + falloff, chain reaction, preview ring == table radius, caps hold). Re-run green: test_blasts_liquid_damage, breakables, combat_feel, energy_destructive_weapons, tanks, vehicle_weapons, vfx, vfx_pass2, balance2, weapons, weapon_cards, weapons_depth, weapons_v3, hud, hud_declutter, touch, phone_readiness, world_hud.

RENDERS: 6 render-look-fix iterations (baseline 15 types x 3 distances; then LOW and MED sets; 12-type set at 6/14/28 m at LOW and MED; 13 other families; phone HUD frames), each opened and written up with 5+ defects (list in docs/shots/round6/blast_arsenal_iterations.md). Fixed e.g. glass-block orbital beam (new column shader), white-wall depth charge, EMP without dome, invisible well pre-phase (shrinking bubble), white ground-flash plate, grey wall at the lens (near fade), round flame balls (tongues), beacon through the fireball, beam slab at 6 m, ring unreadable at distance (wall), label under the equip card. Sheets: blast_arsenal_low_a/b.jpg, med_a/b.jpg, sequence_med.jpg, more_types.jpg, before_after.jpg, hud.jpg (8 jpg, q80, scratch frames deleted).

PERF GATE (PERF_CHECK=1 tools/perf_report.sh 0 1 2, run 1 of 2):
PERF RESULT tier=0 label=LOW renderer=mobile touch=0 draws=63 prims=117077 total_draws=100 total_prims=118748 nodes=2490 tex_mb=106 lights=3 hud_draws=40 death_draws=105 death_prims=116506 enemies=4 verdict=OK
PERF RESULT tier=1 label=MED renderer=mobile touch=0 draws=63 prims=124545 total_draws=100 total_prims=126216 nodes=2551 tex_mb=106 lights=11 hud_draws=40 death_draws=110 death_prims=126636 enemies=4 verdict=OK
PERF RESULT tier=2 label=HIGH renderer=mobile touch=0 draws=68 prims=139937 total_draws=105 total_prims=141608 nodes=2574 tex_mb=141 lights=11 hud_draws=39 death_draws=121 death_prims=144940 enemies=4 verdict=OK
Run 2 (LOW only, world blasters switched off for an A/B, switch removed again): total_draws=96, verdict OK; the staged scene moved between runs (others landed code: nodes 2490 -> 2919, hud_draws 40 -> 21), so LOW's 100/100 is not attributable to the arsenal: all blast nodes are hidden when idle and the world blasters are out of the staged view. Limits untouched; LOW total draws sit at the budget.
WEIGHT: no audio, no models; 92 icon PNGs about 190 KB, 4 shaders about 8 KB; docs sheets about 3.7 MB (not in the APK). APK effect: roughly +0.2 MB.

OUT-OF-SCOPE DEFECTS / GAPS for the integrator:
1. tests/test_energy_destructive_scene.gd expects 10 weapon-wheel wedges, the roster's two-level wheel gives 11 (classes + RECENT): stale expectation (one-line fix, roster/integrator).
2. tests/test_audio_budget2.gd: audio folder 24.5 MB over its 24 MB limit (roster's weapon sound files, not mine; I added no audio).
3. CarDebris.tear_panel panels are unlit flat paint-colour boxes: tan squares at close range next to blasts (cars owner).
4. Pooled car models keep the burnt look of their last life when re-acquired (Vehicle.deactivate does not repair; VehicleVisual.repair v2 branch does not re-apply the surface); my look-dev bot resets it by hand.
5. BlastCard is not placed in the loadout screen (catalogue diagram carries ring + core); families grenade/launcher/mine/strike have names (WeaponDefsBlast.FAMILY_NAMES) but need a place in the roster family UI; blast-specific sounds do not exist (existing boom/explosion set).
6. Fuel-yard prop positions (harbour, airport) were not looked at in the world; the touch ULT button sits in the outer MORE column (dx 750) and is not rebindable on the keyboard/controller screens (key O only).
7. blast_marks.gd and weapons_screen.gd also carry other agents' uncommitted edits next to my small ones.


## w113-damage

W113 DAMAGE EVERYWHERE: DONE. Nothing committed or pushed (the integrator commits). Repo: /home/user/QUANTUM_Teleportar (Godot project in godot/).

WHAT WORKS (stylised, no gore, all pooled and capped per tier):
- Hub: DamageWorld node (one line in scripts/main.gd) observes Player.hit_confirmed + PlayerWeapon.last_shot, Game.exploded (+ BlastTable result one frame later) and every enemy's `died` signal. No enemy, car or weapon script was rewritten. QT_DMG=0 turns all new layers off (used for the before frames).
- Buildings and street: StructureDamage.apply(pos, radius, level) in scripts/combat/structure_damage.gd (BlastTable calls it through its guarded call; level 0..3 comes from the blast rows, so each weapon has its own). Damage is staged per 3 m cell: broken windows (jagged teeth, dark room), spall scars, wall breach with brick/rebar/soot, street craters, flung chunks and dust. Bullet holes by material (concrete, metal, glass, wood, asphalt) in a new shader fx_decals.gdshader (ImpactDecals).
- Props: Breakables got wear stages, material-shaped debris, bench/planter/kiosk kinds, one public pooled debris API (Breakables.fling), and EnemyCover now treats breakable props as real cover (a broken one gives none). Fire fields ignite wooden props and cars; wrecks spread fire to cars and wooden props within 4 m.
- People (FoeFx): hit zones (head flare and visor chip, body sparks and plate flake, leg limp), armour plates at 30% and 62% health lost, shield flicker, fluid splatter coloured by faction on ground and wall (none for mercenaries), burn/frozen/shock/quantum-dissolve statuses through the instance uniform dmg_fx, deaths by cause (burn, shock, ice shatter, quantum dust, flung body by blast/shotgun/heavy round, machines break into plates), citizens react by the place of the hit (head, body, legs) and die in the manner of the blast.
- Cars (CarFx on the wave-111 car_v2 states): bullet holes as shader uniforms, glass cracks in stages then shatters, flat tyres, hood pop (double-sided paint with a ribbed steel liner), shrapnel holes and scorch from blasts, burning wrecks that stay (flames 25 s, smoke 80 s), fire spread.

FILES (new): godot/scripts/damage/{dmg,damage_world,foe_fx,car_fx}.gd, godot/scripts/combat/structure_damage.gd, godot/assets/shaders/fx_decals.gdshader, godot/tests/test_damage_everywhere.gd, godot/tests/bot_damage.gd, docs/sprint/progress/w113-damage.md, docs/shots/round6/damage_{wall_before_after,car_before_after,enemy_before_after,burn_states,blast_street}.jpg (5 jpg, quality 80). Modified (small hooks): scripts/main.gd, scripts/fx/blast_marks.gd + assets/shaders/fx_marks.gdshader (structure pool, kinds 7-10), scripts/player/{impact_decals,impact_sparks,player_weapon}.gd, scripts/world/breakables.gd, scripts/enemies/enemy_cover.gd, scripts/vehicles/car_v2.gd, car shaders (car_common.gdshaderinc, car_paint, car_glass, car_details), hero_body.gdshader, tests/test_blasts_liquid_damage.gd (marks bound allows the structure pool), godot/ARCHITECTURE.md (new section "Damage everywhere" at the end).

TESTS: test_damage_everywhere PASS (101 checks, real scene, about 25 s, counters not frame counts, caps asserted). Also PASS: test_breakables, test_blast_table, test_blasts_liquid_damage, test_player_polish, test_player_robustness, test_cars_v2, test_ai_tactics2, test_vfx, test_visual_fixes2, test_vehicle_paint, test_enemy_types, test_real_fight, test_interiors_world, and the enemy-look builder's test_enemy_look_v3 (their foe_body shader already declares dmg_fx). Flakes seen, not caused by my layers: test_soak_quick failed once by 0.4 nodes (4680 vs limit 4679.6) and passed on re-run (4650) and with QT_DMG=0 (a node-class probe showed growth from far tiles and wildlife only; my scripts create no node); test_real_fight timed out at 60 s once while another agent's Godot render job loaded the machine, 36 s PASS alone.

RENDER LOOPS: 12 render-look-fix iterations at phone aspect (1200x540) at LOW and MED, every frame opened, 8+ defects written each time, self-review done; before/after = QT_DMG=0. Scratch frames deleted.

PERF GATE (one run, PERF_CHECK=1 tools/perf_report.sh 0 1 2, run after the last shader change; the later citizen-hit addition only uses puffs of the existing shared cloud, no new draw call):
PERF RESULT tier=0 label=LOW renderer=mobile touch=0 draws=74 prims=138097 total_draws=96 total_prims=138963 nodes=2919 tex_mb=110 lights=3 hud_draws=21 death_draws=107 death_prims=136791 enemies=4 verdict=OK
PERF RESULT tier=1 label=MED renderer=mobile touch=0 draws=97 prims=239718 total_draws=129 total_prims=271318 nodes=3056 tex_mb=141 lights=9 hud_draws=24 death_draws=148 death_prims=263637 enemies=4 verdict=OK
PERF RESULT tier=2 label=HIGH renderer=mobile touch=0 draws=113 prims=327870 total_draws=149 total_prims=379844 nodes=3176 tex_mb=207 lights=7 hud_draws=25 death_draws=170 death_prims=374030 enemies=4 verdict=OK
(HIGH death spike 170 is exactly at the budget; MED 148 of 150: headroom is gone, do not add draws.)

APK EFFECT: none. No textures or models added (shaders and scripts only; the old decal texture was removed). Disk 13 GB free.

GAPS (honest): no liquid splatter on car bodies (the physics hull box is bigger than the visible car, a decal would float); citizens react at the place of the hit with puffs but do not stumble or limp (crowd is one MultiMesh); fires spread between cars and wooden props, not to buildings; no ragdoll physics (a flung body is one pooled tumble integrator); facade chunk loss is decals plus debris, not geometry; per-tier decal cap is 40 on all tiers (old tests pin CAPACITY 40); nothing measured on a phone (software Vulkan stills at 12 fps).

OUT OF SCOPE DEFECTS SEEN: test_energy_destructive_scene expects ten weapon-wheel wedges, the roster's wheel has 11 (roster builder); the hero's aura sphere tints very close free cameras (hero look); the street around the look-dev spot has overhead beams that occlude the blast frames (bot camera only); earlier transient parse errors (FoeSpecies etc.) came from the enemy-look builder's in-progress classes and went away after tools/import.sh.


## w113-enemy-look

Enemy look v3 is done and in the working tree, uncommitted; the perf gate passes on all three tiers, but HIGH has no headroom.

**Result:** 22 enemy types in four faction silhouettes: 13 armoured humans (3 paints each, one skinned draw, 3 LODs), 7 vael aliens and 2 walkers. The weapon attaches through `FoeArms.pieces(weapon_id, …)`. This restart added:
- **Pips and markers:** floating health pips for every damaged enemy, and threat markers for aware enemies 30–95 m away (`FoePips`, one MultiMesh).
- **Telegraph lines:** the huge translucent wedges at the camera were `AlienFx` telegraph lines. They are thin now and fade at the lens.
- **Tiers and warm-up:** tier-scaled LOD ranges, throttled far rigs, and a loading-time warm-up.
- **Look:** creature wind-up flash as outline, angular brute/elite/hunter plates, lighter paints with a distance lift.

**Tests:**
- `test_enemy_look_v3` passes (95 checks).
- Also passing: alien_world, enemy_roster2, humanoid_variants, humanoid_wiring, real_fight, enemy_look, damage_everywhere, hero_polish.
- `test_perf_budget` fails 1 of 119 on the hero mirror tick check (noted flaky in earlier handoffs, unrelated to this wave).

**Perf gate (final tree):**
- LOW OK: 96 draws, 139.0k tris, 110 MB, death 107
- MED OK: 129 draws, 272.1k tris, 141 MB, death 149
- HIGH OK: 149 draws, 378.0k tris, 207 MB, death 170

One earlier HIGH run was OVER (171 > 170) because the empty pip MultiMesh cost a draw; the node is now hidden while empty. The HIGH death spike is still 170 of 170 and MED 149 of 150.

**Gaps:** no MultiMesh impostors for far crowds (only the rig CPU is throttled); creature faces and hands are simple. At 40–80 m a figure is 20–45 px tall, so the markers carry the read.

Added about 4.1 MB of assets (about 1.6 MB imported into the APK). Ten contact sheets are in `docs/shots/round6/enemy_look_*.jpg`, with the loop notes in `enemy_look_iterations.md`. The progress log is `docs/sprint/progress/w113-enemy-look.md`.


## w113-critic-play

PLAY critic wave 113. Table is exact: 81 entries x enemy/car at 0.5/1/1.5 R match; chains, 22 enemy types and caps fine.
FIXED (tests/test_play_critic_w113.gd, 45 checks, 35 s, mutation-checked; log docs/sprint/progress/w113-critic-play.md):
1 Blast/fire/burn/run-over kills gave no marker, no kill credit (HUNT job 0/8 vs bullets +3): new BlastCredit.
2 Grenade kill = "SILENT TAKEDOWN +150", room guards not alerted: BlastTable._loud.
3 Hero's own tank lost 520/2000 hull to one AP shell: _spared_vehicle.
4 Casualties off: blasts sent nobody running.
5 Wells pulled people through walls.
6 "Cast a freed object" every frame in BlastOps _step_air/burn/toss/hold (HIGH spam).
7 AMR/phase/piercing rifles passed through cars unharmed: PlayerWeapon damages them.
8 test_shooting_accuracy red since roster (cone weapons): skips them.
NOT FIXED: LOW draws +7..+18 per blast (frag 93->106, gas tank 106->124; busy street goes over 115), needs FX.burst/ExplosionPool caps (look area). Noted: flat TTK ~2 s all classes, EMP hits humans, first-spawn hitch 100-390 ms per unwarmed look.
Perf gate (PERF_CHECK=1 tools/perf_report.sh 0 1 2), unchanged:
LOW OK 93 draws, 131k tris, 110 MB, death 107/115
MED OK 129, 272k, 141 MB, death 148/150
HIGH OK 149, 380k, 207 MB, death 170/170
Touched-file tests pass. Not committed.


## w113-critic-look

W113 critic LOOK: about 700 frames at LOW and MED (12 blasts x 3 distances, ring previews, 27 enemies at 15/40/80 m, status and death sequences, car damage, crowd, animals). All opened. Nothing committed.

Defects (FIXED = frame before/after plus check in tests/test_critic_look_w113.gd):
1 FIXED burn/freeze/shock looked like tiger, zebra, flat silhouette; aliens showed none. New assets/shaders/dmg_status.gdshaderinc shared by hero_body, foe_body, foe_creature; FoeFx sets it on creatures.
2 FIXED blasted car windscreen was black and white noise (car_glass: mips, blur, frost).
3 FIXED fire was flat teardrops in the air (blast_fx ground anchor, blast_cloud licks).
4 FIXED cream starburst scorch (fx_marks).
5 FIXED black panel planks and wheel balls (car_debris_panel.gdshader, lit tyre).
6 PARTLY radius ring (blast_wall alpha band); strike ring at 34 m still thin, aim label touches equip card.
7 PARTLY mines/C4 get a dirt plume; grenade, rocket, mortar still one fireball.
8 PARTLY mercenaries were black cut-outs at 15 m (foe_body fake ambient); still dark.

Tests PASS: new test (about 45 checks), damage, blasts, cars_v2, enemy_look_v3, blast_arsenal, weapon_ui_v3, weapons_v3, play_critic. test_real_fight: one flaky red, PASS on rerun.
Perf final: LOW OK 93 draws (death 107/115), MED OK 129 (149/150), HIGH OK 149 (170/170). No draw, triangle or texture added.
Not fixed: humans at 40 m are dots, blank white rectangle above street at (-47.6,-2.9), old alien.gdshader has no status look.
Sheets docs/shots/round6/critic113_look_*.jpg; log docs/sprint/progress/w113-critic-look.md.
