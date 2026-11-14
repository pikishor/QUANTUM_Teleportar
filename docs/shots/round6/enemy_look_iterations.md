# Enemy roster look v3 (wave 113): the render-look-fix loops

Every loop: render from the real game camera at 2400x1080 (LOW and MED, `tools/bot.sh res://tests/bot_foe_look.gd`, `--fixed-fps 12`, the runway of EASTFIELD) or in the viewer (`tools/foe_view.sh`, 1600x760),
OPEN the frames, write the defects, fix, render again. Loops 1-7 were done by the second agent of this label (notes in `docs/sprint/progress/w113-enemy-look.md` and in
`godot/ARCHITECTURE.md` "Enemy look v3", "Looked at"); loops 8-10 by the third (after the second server restart). The owner's round-5 frames (`docs/owner_shots/round5`) contain no enemy at all
(cars, maps, menus), so the yardstick was the hero in the same frame (same light, same camera) and the old procedural bodies (`FOE_OLD_LOOK=1`).

## Loops 1-7 (second agent, summary)
1 first render invisible, weapons without triangles, clipboard vest plate, blocky boots, floating pips above helmets, black boonie brim, claw hands, black legs in the viewer sun, egg knees;
2 black-legged everyone (lighter palettes), far glow wash painted troopers pink (outline instead), riot shield poked through; 3 creatures: ball-jointed capsule bodies, bird beaks, sausage barrels,
lemon blob core; 4-7 flat saturated silhouettes (edge glow only), naked tan hunter (amber carapace), toy mechs (pauldrons, vents, canopy, cannons).

## Loop 8 (real game, LOW): eight defects
1. Every combat frame had wide translucent pink, cyan and yellow wedges: the 12 cm additive box of a telegraph line at arm's length. Fix: width by distance of the nearest point to the camera (0.9 degrees
   of view at most) and a fade within 2.5 m of the lens (`AlienFx._place_line`). Frames: the lines are thin stripes now.
2. Bolts were flat yellow balls. Fix: sprites faster than 18 m/s are darts along their travel.
3. Aliens and walkers showed no health. Fix: `FoePips` (five pips, one MultiMesh) for every damaged roster enemy.
4. Enemies at 45-80 m were 20 px dark dots, nothing said who shoots. Fix: threat markers (diamonds in the glow colour) for aware enemies 30-95 m away, none for a cloaked stalker.
5. The heavy mech and light walker went salmon pink during their wind-up (a full-body wash). Fix: `foe_creature.gdshader` flares the glowing parts and lights an outline.
6. The hunter's pale body of loop 6 re-checked: amber carapace, black plates: fine.
7. The brute wore white balls at shoulders, knees and fists (balloons). Fix: angular dark chitin plates with bone spikes (`angular`, `armor` in `species.py`).
8. Authority armour was black in rain and overcast light (albedo 0.03 linear, no fill). Fix: lighter palettes and a readability floor in `foe_body.gdshader`.

## Loop 9 (viewer + game, LOW and MED, hurt foes, night): eight defects
1. The pips were 5 px high at 45 m: pitch 0.14 m + 1.1 cm per metre, taller pips (0.8), markers 0.016 of the distance.
2. The first angular brute had boards the size of its thigh (box sizes multiplied by the body scale, the old balls were not): sizes without the scale, smaller. Viewer: 3/4 and side of the brute.
3. At 45 m the new dark authority figures stood out LESS than the old saturated pink blocks (before / after sheet): a distance lift of paint and saturation in `foe_body.gdshader` (`far_k`), checked on a
   zoomed crop of the 45 m row (royal blue, red, green, teal now tell the looks apart).
4. The first view of every bot run shows no markers (the foes have not noticed the hero yet): a bot artifact, noted, not a bug of the game.
5. Fight sequence A (a patrol of six closes in from 36 m and fires): bolts are streaks, markers appear when they notice the hero, lines thin; a bolt that passes the lens is a large streak (kept).
6. Fight sequence B (heavy, brute and rocketeer at 14 m, two killed in a row): flash, fall, loot gems, the brute at 8 m reads as an armoured heavy with a glowing chest.
7. Night (hour 23, LOW): the humans are dark silhouettes against the blue runway, the stalker glows magenta through its cloak, markers and pips carry the 45 m read.
8. Perf gate: the second run of the pass was HIGH OVER (death spike 171 > 170): the empty pip MultiMesh cost one draw in every tier (found by switching the kit troopers off with `FOE_NO_KIT=1`, which gave the same 171). The pip node is hidden while empty now. Final: LOW OK 96 draws, 139.0 k triangles, 110 MB, death 107; MED OK 129, 272.1 k, 141 MB, death 149; HIGH OK 149, 378.0 k, 207 MB, death 170 (of 170).

## Loop 10: self-review against the hero and the old bodies
Before / after sheet `enemy_look_before_after.jpg`: at 15 m the old bodies were pink and tan blocks with a lamp for a head, the new ones are armoured soldiers with helmets, plates, packs and weapons in their
hands; at 45 m the lifted paint and the markers keep the read. Weaker than the hero still: the bodies are the Quaternius base in a kit of boxes (no textures, no normal maps), creature faces and hands are
cones, at 40-80 m a figure is 20-45 px tall on a phone (camera, not this wave).

## Sheets
`enemy_look_lineup_humans.jpg`, `enemy_look_lineup_aliens.jpg`, `enemy_look_variants.jpg`, `enemy_look_action.jpg`, `enemy_look_creature_clips.jpg`, `enemy_look_combat_low.jpg`,
`enemy_look_combat_med.jpg`, `enemy_look_aliens_low_med.jpg`, `enemy_look_sequence.jpg`, `enemy_look_before_after.jpg` (10 files, 2.6 MB, JPEG quality 80).
