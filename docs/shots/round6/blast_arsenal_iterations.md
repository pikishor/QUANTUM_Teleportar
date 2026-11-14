# Blast arsenal: render-look-fix iterations (wave 113)

Tool: `tests/bot_blast_arsenal.gd` (the real game, the real camera behind the hero, a blast of the table 6 / 14 / 28 m ahead, three frames each: the flash, the fireball, the smoke;
three enemies and a parked car stand next to it) driven by `tools/bot.sh` at 1200x540, `QUALITY=0` (LOW) and `QUALITY=1` (MED), `--fixed-fps 12`. Every iteration opened the frames as sheets.

## Iteration 0: baseline, LOW, 15 types x 3 distances (frag, rocket, plasma, spark, blinder, fog, well, ember, thermo, orbital, still, depth charge, arc, gas tank, air strike)
Defects written down:
1. Orbital beam read as a glass block: a 10-sided cylinder with a flat additive material, no core, no fade (st_orbital 6 / 14 m).
2. Depth charge was a white wall: five equal puffs stacked into a rectangle (ord_depth_charge).
3. EMP pulse had no dome and no shock wave, only two thin rings (gr_spark, st_emp).
4. Well seed and collapse: the pre-phase was one thin ring on the street, nothing said "this pulls" (gr_well, mn_gravity, ult_blackhole).
5. Big strikes started with a white plate of light 20 m across on the street (ground flash disc of the pool, 0.15 s) (st_air_l, st_orbital at 14 m).
6. Smoke next to the lens: a fog can at 6 m turned the whole frame into a grey wall (the cloud puffs had no near-camera fade).
7. The first smoke puff of the pooled fireball dimmed the frame of a blast 10 m away (cover fade at 1.1 x size).
8. Bot artefacts that looked like game defects: every enemy a flat white silhouette (the bot froze their physics so the white-hot hit flash never faded), the parked car a burnt husk in every stage (pool reuse), the first stage dark (teleport fade-in), scorch of the stage before on the street.

## Iteration 1: LOW, 6 types x 2 distances after the fixes above
Frames opened: frag, fog, well, spark, orbital, depth charge. Defects:
1. Orbital beam still a box at 6 m: radius 0.55 of the blast, far too wide (now 0.26, stronger at the core).
2. First frames of the first stage still dark: the teleport fade-in (bot now waits 2.5 s before the first stage).
3. Fire field (gr_ember): round yellow balls instead of flames.
4. Well collapse not visible: the moment table caught the burst too late (moments 0.8 / 2.12 / 2.4).
5. Cars: the husk look came back from the pool (bot now resets damage look, deform and condition).
6. Marks of the stage before stayed on the street (bot clears marks and car debris per stage).

## Iteration 2: LOW, 10 types x 2 distances
Defects: flames as tongues needed (aspect 2.3, no roll, taper and sway in the shader); strike beacon column stayed through the fireball (now it goes out when the strike lands);
depth-charge water read as smoke (bluer tint, less whitening); first frame of fast moments was the frame before the trigger (moments are at least two frames now);
the bot's lane differed per run and some had a market stall in the middle (BX_SPOT: one street for all runs).

## Iteration 3: MED, 10 types x 2 distances
Frames opened: both sheets at 14 m and the 6 m sheet. Defects: flame puffs next to the lens became yellow slabs (near fade by the larger side of the puff);
flame brightness too hot (glow 0.45 -> 0.28); wheels of the stage before still on the street (car debris cleared per stage); the blinder was invisible at 14 m (pop 0.28 s -> 0.5 s, white dome added);
orbital ground ring white band across the hero at 14 m (kept, 0.2 s).

## Iteration 4: LOW, 13 other types x 2 distances (blinder, still, arc, rocket, meteor, black hole, mega, freeze, gravity mine, carpet, fire line, cluster, smoke screen)
Defects: strike markers were applied as a single blast (the bot now runs the real delivery: marker, countdown, jet, pattern of shells); fire line flames filled the right third of the frame (near fade, dimmer);
black-hole burst missed by the moment table (moments 1.6 / 5.4 / 6.4); mega blast centred on the hero hides the fireball behind the camera (kept: cover fade is the point).

## Iteration 5: LOW, 12 types x 3 distances (the contact sheet set)
Frames opened: both sheets. Defects: orbital beam at 6 m a white slab across the screen; EMP dome seen from inside a veil over the whole frame; carpet-bomb sparks streak across the lens at 6 m (kept: they are the sparks).
Fixes: beam and dome thin out within 12 m / 9 m of the camera (shaders).

## Iteration 6: LOW and MED, 12 types x 3 distances, final
See `blast_arsenal_low_*.jpg` and `blast_arsenal_med_*.jpg`.

Iteration 6 additions (HUD previews, `tests/bot_blast_hud.gd`, phone HUD at 1200x540, sheet `blast_arsenal_hud.jpg`):
1. The ring of a strike aimed 34 m away was invisible from the low camera (a flat ring is a few pixels high): every preview now has a thin glowing wall standing on its ring (blast_wall shader).
2. The label "NAME  RADIUS 6 M" sat where the card of the weapon just equipped appears (it covered the label): moved to just under the crosshair.
3. Orbital beam still a white slab at 6 m: core brightness lowered (0.5 + 1.6 core -> 0.3 + 0.95 core), thin within 12 m of the lens.
4. Flat tan squares around a carpet strike at 6 and 14 m: they are the torn body panels of the parked car (`CarDebris.tear_panel`, unlit flat paint colour): not part of the blast code; reported to the cars owner. Wall chunks (blast_marks) were darkened and made to shrink anyway.
5. Preview frames confirm: radius_shown equals the table radius for all six (6, 10, 5, 13, 13, 6 m), DANGER only for the frag at the hero's feet on NORMAL.
Final sheets: blast_arsenal_low_a/b.jpg and blast_arsenal_med_a/b.jpg (12 types at 6 / 14 / 28 m, fireball moment), blast_arsenal_sequence_med.jpg (flash, dome, smoke), blast_arsenal_more_types.jpg
(bubble, arc, meteor, black hole, mega, freeze, gravity mine, fire line), blast_arsenal_before_after.jpg, blast_arsenal_hud.jpg.
