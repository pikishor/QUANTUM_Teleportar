# w113-critic-look (independent critic and fixer, lens LOOK) - started 2026-11-14 06:57Z, DONE 10:10Z

GOAL: review wave 113 (damage, blasts, enemy looks) by phone-size frames (LOW and MED, 1200x540 = 2400x1080 aspect), write the 8 worst defects, fix them (render-look-fix),
add regression tests, perf gate. Report under 200 words.

STATUS: DONE. Nothing committed (the integrator commits). Report = the SubagentHandback message.

DEFECT LIST (evidence = frames in docs/shots/round6/critic113_look_*.jpg)
 1 FIXED  status looks: burning = tiger stripes, frozen = zebra, shocked = flat silhouette, aliens had none -> assets/shaders/dmg_status.gdshaderinc (3 shaders), FoeFx._shader sets dmg_fx on creatures
 2 FIXED  windscreen of every blasted car = black and white noise -> mip levels + blur by distance + frost (car_glass.gdshader, vehicle_visual.gd)
 3 FIXED  fire = flat paper teardrops hanging in the air -> anchored to the street, hot bed, climbing licks, red tip (blast_fx.gd, blast_cloud.gdshader)
 4 FIXED  fresh scorch = solid cream starburst on shop fronts and streets -> ring of glints (fx_marks.gdshader kind 2)
 5 FIXED  torn car panels = black planks, flung wheels = black balls -> car_debris_panel.gdshader + lit tyre on a private mesh (car_debris.gd)
 6 PARTLY radius ring unreadable on bright / orange street -> blast_wall.gdshader alpha band + dark skirt + dashes; strike ring at 34 m still thin; aim label touches the equip card for 2 s
 7 PARTLY frag, rocket, mortar, mine, C4 = one fireball -> mines and charges throw a dirt plume (blast_fx.gd _extras); grenade / rocket / mortar still one family
 8 PARTLY six contract mercenaries = one black cut-out at 15 m against the sun -> fake ambient of the paint in foe_body.gdshader (kit colours survive, still dark)
 (seen, not defects: death ring of EnemyMarks is by design; the "pale ghost" of a dying operative did not reproduce from the real camera)

FILES (mine): NEW assets/shaders/dmg_status.gdshaderinc, assets/shaders/car_debris_panel.gdshader, tests/test_critic_look_w113.gd, tests/bot_critic_{blasts,foes,crowd,animals}.gd, 8 sheets
 docs/shots/round6/critic113_look_*.jpg; EDITED hero_body / foe_body / foe_creature / car_glass / blast_cloud / blast_wall / fx_marks .gdshader, scripts/damage/foe_fx.gd,
 scripts/combat/blast_fx.gd, scripts/vehicles/car_debris.gd, scripts/vehicles/vehicle_visual.gd, godot/ARCHITECTURE.md (appended), docs/HANDOFF.md (appended).

TESTS (all PASS): test_critic_look_w113 (new, real scene, about 45 checks), test_damage_everywhere, test_blasts_liquid_damage, test_cars_v2, test_enemy_look_v3, test_blast_arsenal,
 test_blast_table, test_humanoid_variants, test_vfx, test_vehicle_paint, test_director_round3_b, test_hero_polish, test_enemy_roster2, test_weapon_ui_v3, test_weapons_v3, test_play_critic_w113;
 test_real_fight had one red on a loaded machine (longest cover 15.8 s against 12 s), PASS on the re-run (not my files).
 Compat renderer: the status shader compiles and renders (checked once; the arc width is capped because a coarse derivative made blotches there).

PERF (final run 10:08Z, after every change): LOW OK total 93 draws, 130.6 k tris, tex 110 MB, death spike 107 of 115; MED OK 129, 272.0 k, 141 MB, death 149 of 150; HIGH OK 149, 380.4 k, 207 MB, death 170 of 170.
 Earlier run (08:46Z) identical within 1 draw. No draw, triangle or texture added; APK effect: 2 shader files (about 6 KB), 8 sheets are docs only.

OPEN PROBLEMS: see "Not fixed" in docs/HANDOFF.md (strike ring at 34 m, aim label vs equip card, one fireball family, humans at 40 m are dots, a blank white rectangle above the street at (-47.6, -2.9),
 old alien.gdshader has no status look). HIGH death spike has no headroom (170 of 170): do not add draws.
