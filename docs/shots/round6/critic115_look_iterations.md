# Wave 115 LOOK critic (QUANTUM SNAKES): loops, defects, numbers

Method: the real game, the real camera, the phone HUD (`--touch`), 1200x540 (the 2400x1080 aspect) and 844x390, LOW and MED, `--fixed-fps 30`, the renderer only on for the frames that are saved
(`tests/bot_critic_snake.gd`). A thumb policy plays a swing run (SNAKE tapped on the ground, held in the air, forward on the ground and up a wall, the right thumb turns the camera toward waypoints
except while a wall is climbed or a zip pulls). A second probe plays the same policy headless for 60 to 90 s (`tests/dev_critic_snake_play.gd`) and measures what the stills cannot show
(camera pops, hero jumps, the vehicle plate). About 700 frames were opened: the run (LOW 204 + 225 frames, MED 100), zip / climb / mantle / ceiling / take-off / cruise / boost / dive / landing
scenes, the HUD in six states at 844x390, the weapon, verb, bomb and ability wheels, 10 verbs at LOW, 12 bombs at MED (twice: the first lane stood at an empty plaza).

## Loops
1. Baseline (run, scenes, HUD, verbs, bombs) -> 8 defects with evidence (below).
2. Hero fling + camera cut + vehicle plate: measured in the headless run, fixed, measured again (same route): hero jumps 1 -> 0 (11.3 m), camera pops 12 -> 3 (max 2.2 -> 1.2 m).
3. Wing tips through a facade: scene `fly_wall`, before / after rows in `critic115_look_wings_boots_before_after.jpg`.
4. Boots and dark gear read as black sausages from behind: a rim on the dark kinds of the suit kit shader, before / after crops in the same sheet.
5. HUD at 844x390: the vehicle plate and the label RELEASE (drawn a fifth smaller than the disc) -> `critic115_look_hud844_before_after.jpg`.
6. The suit did not answer the snakes (HeroLook has the layers `flow` and `wings` for exactly this): hooked; the first version (1.5 / 1.3) was a few grey levels on thin circuit lines at LOW, so the layers were raised (swing 2.1, zip and climb 1.7, flight 1.8); old / new close-ups in `critic115_look_pose_glow.jpg` (a switch, `SnakeTraversal.suit_glow`, shows the old suit).
7. Dive from 160 m, pull-out and barrel roll (scene `dive_roll`): the hero spun but his wings stayed level like a gyroscope -> the wings roll with him (`critic115_look_roll_before_after.jpg`, `critic115_look_dive_low.jpg`).
8. Full run again after all fixes (LOW, 225 frames): no plate, wings bend at the wall, nothing else regressed (`critic115_look_run_low_after.jpg`).

## The worst defects and their status (9; the first 8 are the ranked list, 8 is the sum of the traversal look defects)
1. FIXED  The hero is flung 6 to 12 m in ONE frame during a swing (rope reel debt: the rope reels at 40 m/s while a facade or the street holds him; the sphere then moves him the whole debt). Probe: jumps of 6.4 m, 11.3 m, 11.8 m, camera pops up to 11.3 m. `SnakeSwing._tick_hang`.
2. FIXED  The camera arm is cut from 3.7 m to 1.2 m in one frame at 31 m/s (2 to 5 m pops, 18 per 90 s, the lens in a collider 2 % of the run). During a snake state the arm is drawn in over about three frames (`CameraRig.snake_pull_in`). On foot unchanged.
3. FIXED  "ENTER VEHICLE" plate over a swinging, zipping or flying hero (5 to 14 % of the frames, 3 of 6 HUD frames at 844x390): the HUD fallback used the flat distance only. `Hud.hint_text`.
4. FIXED  The wing tips went through the facade the hero flew along. One cached ray per wing and frame. `SnakeFlight._keep_out_of_walls`.
5. FIXED  Boots, belt, carbon pack and cloth were flat black shapes in every frame seen from behind (flight, zip, swing). A thin rim in the circuit colour. `hero_body.gdshader` (suit kit branch).
6. FIXED  The suit did not react to the traversal (HeroLook layers `flow` and `wings` were never called): `SnakeTraversal._glow_tick`.
7. FIXED  The SNAKE button read RELEASE while swinging (7 letters, the label shrank to fit the disc): LET GO (same word as the climb).
8. FIXED  In a barrel roll the hero spun and the wing snakes stayed level (the pose rolls the body, `_wing_tip` ignored the roll): the wing tips and arches take the same roll basis (`SnakeFlight._wing_tip`, `tick`).
9. FIXED  With the camera squeezed against a wall (arm of 1 m) the rope or wing at the hero's hand sat 1 to 2 m from the lens and was a fat band across the screen: the tendril slims to 40 % within 0.7 m of the camera (`snake_tendril.gdshader`; subtle in stills, no new draw).
10. NOT FIXED (design, tests pin the layout)  SNAKE (r 46) and FLY sit in the gaps between RELOAD, AIM and FIRE with 6 px of air, the energy ring touches the neighbours, BOOST is clipped by the FIRE ring
   at 844x390; the ABILITY wheel has 11 discs of 0.62 scale with 7 px labels (SUPERPOSITION, COLLAPSE).

Play note (not changed, the PLAY lens owns it): the barrel roll needs a nearly pure sideways double tap (`absf(side_in) > 0.8`): with FORWARD held a stick pushed right-forward gives 0.707, so the roll never starts (the bot had to release forward to roll).

Seen and not ours (for the owner / the other waves): an empty flat teal PLAZA (a block with no lot: `ground.gdshader`) at (205, 0, 0); rooftop props (a faceted glowing orb, flat teal wedges);
near-field facades at 2 to 3 m are flat black and cream panels (the swing passes them all the time); MED facade cables look like floating wires up close; a weapon-change card draws over the hero's torso.

## Tests
`tests/test_critic_look_w115.gd` (real scene, about 60 s): every fix has an "old behaviour" trial that reproduces the defect first (rope debt 25.1 m and a 26.4 m step in one tick against 1.1 m / 1.07 m;
camera first-frame share 103 % against 50 %, on foot 104 %; the wing tip through the wall against 0.31 m short of it) and a check that the fix holds; plus the vehicle plate on the ground and 30 m up,
the suit layers (flow 0.2 -> over 0.6 while swinging, wings while flying, released afterwards) and a quarter of a barrel roll (the wing points up or down, not sideways).

## Perf (PERF_CHECK=1 tools/perf_report.sh 0 1 2, once, after the last rendering change)
LOW  draws 70, total 92, death 107, tris 128k, texture 112 MB  OK
MED  draws 97, total 129, death 149 of 150, tris 241k, texture 143 MB  OK
HIGH draws 113, total 149, death 169 to 170 of 170, tris 328k, texture 209 MB  OK  (run twice: after the rim and the glow, and at the very end: identical)
