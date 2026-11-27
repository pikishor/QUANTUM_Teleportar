export const meta = {
  name: 'wave-runner',
  description: 'Runs ONE wave of docs/PLAN_116_150.md: two builders, an independent critic-fixer, the integrator, then CI and the Android build',
  phases: [{ title: 'Build' }, { title: 'Review' }, { title: 'Integrate' }, { title: 'CI and APK' }],
}
// args: {wave: 116, skipTags: ['touch-audit'], skipCritic: false, reports: {tag: 'pointer', critic: 'pointer'}, ciSha: '<integrator text>' (only the CI and APK step runs)}
const A = args || {}
const N = Number(A.wave || 116)
const SKIP = A.skipTags || []
const REP = A.reports || {}
const EFF = A.effort || 'low'

const COMMON = `
You work on the Godot 4.6.1 game QUANTUM TELEPORTAR in /home/user/QUANTUM_Teleportar (project in godot/). Read first: docs/ROUND7.md (the owner's words and the rule that came out of
round 7), docs/PLAN_116_150.md (this wave's line), the section "Rules for every agent of the sprint" in docs/ROUND6.md (progress log docs/sprint/progress/<your label>.md kept current
after every step so another agent can resume; small working steps; NO commits and NO pushes unless your task says so; disk above 4 GB; machine time rule) and the last 3 sections of
docs/HANDOFF.md. The owner plays on a PHONE with touch only and rated the last build 4/10: "small silly errors. Are you even checking."
HARD RULES: (1) every UI or control check you write drives the real main scene with REAL finger events (InputEventScreenTouch / InputEventScreenDrag through Input.parse_input_event,
window coordinates: root.get_final_transform() * pos; see godot/tests/test_touch_buttons_r7.gd), never the mouse and never a direct function call, with Game.force_touch = true and the
phone-only layers on (CrateReveal._quiet = 0); (2) each fix gets a check that FAILS on the old code (show it failing first); (3) never weaken a test, never raise a perf limit (one owner exception from wave 124 on: the test_integration node limit is 7000, raised by the owner)
(PERF_CHECK=1 tools/perf_report.sh 0 1 2 must stay OK on LOW, MED and HIGH: run it at most twice, at the end); (4) another agent edits the same tree at the same time: touch only
what your task needs, keep other agents' hook lines, run tools/import.sh after adding a class_name; (5) look at your own frames (tools/bot.sh renders at phone aspect 2400x1080 or
1200x540) before you call something fixed; (6) original names, only own-made or CC0 assets, no secrets in files. If you were restarted, your log says where to continue.
Your FINAL message is your report (plain text, under 350 words): what you fixed with the check that proves each, what you found and did not fix, files touched, perf lines.`

const WAVES = {
  116: {
    title: 'Touch-first pass and a clear flight view',
    builders: [
      { tag: 'touch-audit', prompt: `TASK (label w116-touch-audit): THE TOUCH AUDIT. Build godot/tests/bot_touch_audit.gd plus a test godot/tests/test_touch_audit.gd that, in the real main scene with
touch on, find EVERY control a player can press and press each with a real finger: all HUD buttons on foot, in a car, in the air (snake flight), in an aircraft, in an interior; MORE and its
cards; the weapon wheel (both levels) and the ability wheel; pause menu and every sub-screen (loadout / Arsenal, options, map, mission board, shop, skills, suit, garage, extras, photo mode,
vendor window, fast-travel list, the TEST and DEMO menus, title screen). For each: does the press do what the label says, can the screen be LEFT again by a finger (BACK / CLOSE / X and the
phone back key), does any layer sit on top and swallow the touch, is the target at least 44 px at 844x390 and not overlapping a neighbour. The round 7 bug class: plain Godot Button nodes
are deaf to touch (now pressed by scripts/ui/touch_buttons.gd): check no screen double-fires because of it and none is still deaf (ScrollContainers, sliders, LineEdits, OptionButtons,
CheckBoxes are Controls too: emulate_mouse_from_touch is off). Write the table of findings into your log, fix every dead, wrong or trapped control, keep the audit as a permanent test.` },
      { tag: 'flight-view', prompt: `TASK (label w116-flight-view): A CLEAR VIEW AND HONEST CONTROLS IN THE AIR. Owner: "fly is working but sometimes there are many rays obscuring the view" (frames
docs/owner_shots/round7: light-blue wing bands crossing the whole screen, radial rays, big translucent buttons over the hero). (a) Find every full-screen or large overlay drawn while swinging,
zipping, flying or boosting (snake_speed_lines shader, wing snakes scripts/quantum/snake_flight.gd, snake_fx.gd, reward and hint layers, rain streaks) and make the view clear: the wings
must not cross the centre of the screen or hide the horizon and the target, speed streaks only at the far edges and faint, nothing over the crosshair; render before / after frames from the
real chase camera at 1200x540 on LOW and MED and check them by eye and by a pixel test (share of the central 60 % of the frame covered by overlay pixels under a small limit). (b) In flight
the phone shows FPS 37 to 41 with drops to 13 to 28 and the perf line says VEHICLES 4 to 6.5 ms of script time far from any car: find what the vehicle code does in the air and cut it
(measure with tools/cpu_frame.sh or the in-game perf overlay code). (c) Drive SNAKE, ZIP, FLY / LAND, BOOST and UP by real finger events and write down exactly how each misbehaves today
(the owner: "zip line is not working properly", "behaves abnormally"): fix plain bugs (a press that does nothing, a state that cannot be left, the hero stuck or flung); the rebuild of the
swing itself is wave 117: leave a precise defect list for it in docs/sprint/progress/w116-flight-view.md under "FOR WAVE 117".` },
    ],
    critic: `You are the INDEPENDENT REVIEWER of wave 116 (label w116-critic), then its fixer. You did not build it; assume it is broken until you have seen it work. Play the real main scene
ONLY through finger events with a bot of your own (do not reuse the builders' bot): title, start, walk, shoot, swap weapon by the wheel, open and LEAVE every screen, enter and leave a car,
swing, zip, fly, land, open the map and close it, demo mode on and off. Hunt the owner's class of bug: a control that does nothing under a finger, a screen you cannot leave, a layer over
the view, something that repeats or never ends. Render frames and LOOK at them. List the 10 worst defects with evidence, fix them most severe first, each with a check that fails without the fix.`,
    commit: 'Wave 116: every control answers a finger (touch audit), a clear view in flight',
  },
  117: {
    title: 'Snake swing like Spider-Man',
    builders: [
      { tag: 'swing', prompt: `TASK (label w117-swing): THE SWING ITSELF. Owner: "zip line should be just like spiderman but instead of web we have multiple snakes binding together and our hero can jump"; today
"it behaves abnormally". Read the list "FOR WAVE 117" in docs/sprint/progress/w116-flight-view.md and the open list in docs/sprint/progress/w116-critic.md first. Rebuild the swing motion
(scripts/quantum/snake_traversal.gd and the swing code it uses; you OWN the motion and the input logic, the other builder owns the rope's look and the cues): hold SNAKE = the rope bites an
anchor ahead and above (building edge, crane, tree, lamp; sensible auto-pick in the look direction, never behind a wall), a real pendulum with rope length kept, speed carried through the
arc, release at any point throws the hero along his velocity with a small upward help near the front of the arc, press SNAKE again in the air = next rope (chain of swings down a street
without touching the ground), JUMP during a swing = release with a boost, steer left / right with the stick, never through walls or the ground, never flung to huge speeds, never stuck
hanging (a still rope lets go or lowers the hero after a short time), a soft landing with a roll. Fix each of the 15 listed defects that is about motion or input, or say why not. Drive
everything by real finger events in the real main scene; a permanent test godot/tests/test_swing_w117.gd: 5 swings in a row down a street stay off the ground, release speed and direction
sane, no wall passed, no state stuck, each check failing on the old code (keep a static old-behaviour switch). Render a strip of frames of one swing and LOOK at it.` },
      { tag: 'rope', prompt: `TASK (label w117-rope): THE ROPE OF SNAKES, THE ZIP AND THE CUES. The other builder (w117-swing) owns the swing motion and input in scripts/quantum/snake_traversal.gd: do not
change motion there, add only small hook lines. You own the look and the feedback: (a) the swing and zip rope is SEVERAL SNAKES BRAIDED TOGETHER (3 or more bodies twisting round each other,
scales, heads biting the anchor, the braid tightens under load and unwinds on release), cheap enough for LOW (one mesh / one draw if possible: the perf gate has ZERO spare draws on HIGH and
one on MED, so replace the old rope, do not add to it), clear of the centre of the view (the wave 116 flight-view pixel limits in tools/flight_view.sh still hold); (b) zip defects from
docs/sprint/progress/w116-critic.md and the "FOR WAVE 117" list in w116-flight-view.md: a ZIP that ends with the hero hanging on a wall (he must climb over the edge or drop cleanly), no cue
when ZIP or SNAKE has no anchor in reach (show a short clear cue and a marker on the anchor that WOULD be used when one is in reach), flight energy ending without warning (warn before it
ends); (c) MED rain in flight covers 13 to 14 % of the centre of the frame (limit 4 %): fix it. Drive everything by real finger events; a permanent test godot/tests/test_rope_w117.gd with
checks that fail on the old code; render frames at 1200x540 on LOW and MED and LOOK at them (a contact sheet in docs/shots/round7/).` },
    ],
    critic: `You are the INDEPENDENT REVIEWER of wave 117 (label w117-critic), then its fixer. You did not build it; assume it is broken until you have seen it work. With a finger-only bot of your own
in the real main scene: swing down three different streets, chain 5 swings, release early and late, JUMP out of a swing, swing into a wall, swing with no anchor near, zip to a roof and to a
wall, take off and land. Render frame strips and LOOK: does it read as a hero swinging on a braided rope of snakes like a web-swinger, or as something abnormal? List the 8 worst defects with
evidence, fix them most severe first, each with a check that fails without the fix. Do not stop early: if you cannot fix one, write exactly why in your report.`,
    commit: 'Wave 117: snake swing like a web-swinger (braided rope of snakes, pendulum, chain swings, jump), zip and cue fixes',
  },
  118: {
    title: 'Tanks and helicopters you can find, and GTA-style on-screen controls',
    builders: [
      { tag: 'armour', prompt: `TASK (label w118-armour): TANKS AND HELICOPTERS THE PLAYER CAN FIND. Owner: "where are tanks and helicopters etc. everything is pending for such long time". Tanks, helicopters and
planes exist in the code (airport, aircraft flight, military vehicles): find out by real finger play why a player never meets them, then make them findable: (a) FIXED PLACES that always hold
them (a military base or yard with at least 2 tanks and an armoured car, helipads in the city and at the airport with helicopters standing on them, planes at the airport), present from
the first minute of free roam, never despawned while the player is near; (b) MAP ICONS for each (tank, helicopter, plane) on the big map and the minimap, with GPS to them, and a legend /
filter chip; (c) DEMO and TEST menu: a SPAWN list that puts a tank, a helicopter or a plane next to the hero; (d) a CALL-IN from the phone / MORE tray in normal play (delivered next to the
hero on a cooldown); (e) enter, drive / fly, shoot and leave each by finger. The other builder (w118-controls) owns the on-screen control layout (scripts/ui HUD button sets): do not rearrange
buttons, only make sure the actions exist as input actions and tell it in your log which actions a tank and a helicopter need. Permanent test godot/tests/test_armour_w118.gd by real fingers:
from a fresh start open the map, see the icons, spawn from the demo list, walk to a tank at its fixed place, enter, drive 30 m, fire the gun, leave; the same for a helicopter (take off, fly,
land, leave). The perf gate has ZERO spare draws on HIGH and one on MED: parked vehicles far away must cost nothing (cull / LOD), trim elsewhere if needed, never raise a limit.` },
      { tag: 'controls', prompt: `TASK (label w118-controls): GTA-STYLE ON-SCREEN CONTROLS. Owner (2026-11-21): "make sure all controls come as options on screen like gta. It should not be cluttered but like 5 circle
for driving etc." Meaning: every action the player can take in the current mode is a visible round button on screen (nothing essential hidden in a tray or behind a gesture), but each mode
shows only its own small set: about 5 circles plus the stick, in the classic mobile open-world layout (left thumb: stick or steer buttons; right thumb: a cluster of round buttons in an arc,
the main action biggest; small PAUSE / MAP / MORE at the top). Design and build one set per mode, switched automatically: ON FOOT (fire, aim, jump, snake / swing, enter vehicle when one is
near, weapon swap; crouch / reload / abilities as small secondary circles or auto), DRIVING (accelerate, brake / reverse, handbrake, fire if armed, exit; horn / camera small), TANK (move,
turret aim by drag, fire main gun, machine gun, exit), HELICOPTER and PLANE (up, down, fire, missile, exit / land; stick for direction), SNAKE FLIGHT (up, down, boost, fire, land), SWIMMING
and INTERIOR if they differ. Fix from the wave 116 / 117 lists: FLY is absent on the ground, there is no DOWN in snake flight, SNAKE on the street zips instead of swinging (make the two
actions clear and separate), 38 px ability discs and menu targets under 44 px at 844x390. Rules: every circle at least 56 px at 844x390 for main actions and 44 px for secondary, no overlap,
nothing over the crosshair or the hero, at most about 6 circles in the right cluster per mode, labels or clear icons, the same position for the same action across modes (exit always in the
same place). The other builder (w118-armour) owns tanks / helicopters themselves; read its log for the actions they need. Keep scripts/ui/touch_buttons.gd working. Extend the wave 116 touch
audit (godot/tests/test_touch_audit*.gd) and add godot/tests/test_controls_w118.gd: per mode, by real fingers in the real main scene, every listed action has a visible button that works,
the count and size limits hold, and no essential action is only in MORE. Render one frame per mode at 844x390 and 2400x1080 into docs/shots/round7/controls_w118/ and LOOK at them: it must
read as clean as a well-known mobile open-world game's HUD, not cluttered.` },
    ],
    critic: `You are the INDEPENDENT REVIEWER of wave 118 (label w118-critic), then its fixer. You did not build it; assume it is broken until you have seen it work. With a finger-only bot of your own
in the real main scene, from a fresh save: find a tank and a helicopter WITHOUT the demo menu (map icon, GPS, go there), enter each, drive / fly, shoot, leave; then with the demo SPAWN list and
the call-in. In every mode (on foot, car, tank, helicopter, plane, snake flight) render the HUD at 844x390 and LOOK: is every action a visible round button, about 5 circles, uncluttered, like
a well-known mobile open-world game? Press every circle. List the 8 worst defects with evidence, fix them most severe first, each with a check that fails without the fix. Do not stop early: if
you cannot fix one, write exactly why in your report.`,
    commit: 'Wave 118: tanks and helicopters at fixed places with map icons, spawn and call-in; GTA-style round on-screen controls per mode',
  },
  119: {
    title: 'Snake blasts, and five circles on foot',
    builders: [
      { tag: 'blasts', prompt: `TASK (label w119-blasts): SNAKE BLASTS. Owner: "different types of snakes also blasting apart from the weapons we have"; round 7: "snake bombs ... not working properly". Plan line:
"snake species that burst in their own ways (their own attacks, apart from the gun arsenal), readable looks and radius rings". First find by real finger play what snake bombs / snake attacks exist
today and exactly how they misbehave (write it in your log). Then build at least 6 snake species, each with its own look (colour, pattern, head shape, size) and its own burst: e.g. a fire snake
that explodes in flame and leaves burning ground, a frost snake that freezes enemies, a shock snake that chains lightning to 3 foes, an acid snake that eats armour and vehicles, a swarm snake
that splits into small biters, a gravity snake that pulls foes in then bursts; use BlastTable (scripts/combat/blast*.gd) for damage and BlastFx for visuals, do not duplicate them. The player
throws / sends a snake with ONE round on-screen button (SNAKE BLAST) that the controls set already has a slot for (coordinate through the other builder's log: it owns the button layout) and
picks the species on the ability wheel; a radius ring shows where it will burst while aiming; cooldown and count visible on the button. Enemies, cars and tanks react (fly, burn, freeze).
Cheap on LOW (pool the snakes, one MultiMesh per species if possible; the perf gate has ZERO spare draws on HIGH and one on MED: trim, never raise a limit). Permanent test
godot/tests/test_snake_blasts_w119.gd by real fingers: each species thrown at a group of enemies and a car, the right effect happens, the ring matches the hit area, no leak after 50 throws,
each check failing on the old code. Render a sheet of the 6 bursts at 1200x540 on LOW and MED and LOOK at it.` },
      { tag: 'hud5', prompt: `TASK (label w119-hud5): FIVE CIRCLES ON FOOT, and the wave 118 leftovers. Owner asked for controls "like gta. It should not be cluttered but like 5 circle"; wave 118 left 11 circles on foot.
The owner did not pick which to keep, so: on foot keep exactly 5 round action buttons in the right cluster (FIRE big; then JUMP, AIM, SNAKE (one button: tap = swing / zip by context near an
anchor, hold = fly; keep the wave 117 rules that swing and zip must be clearly distinct: if one button cannot do it cleanly, write why and keep SWING and ZIP and drop AIM to auto-aim instead),
and a context slot (ENTER beside a vehicle, USE beside a door / item, SNAKE BLAST otherwise: the other builder w119-blasts adds that action, read its log)); everything else (CROUCH, RELOAD
(auto-reload stays), ABILITY wheel, weapon swap) moves to small edge chips or the weapon icon tap / MORE, never lost. Other modes keep their wave 118 sets unless above 6. Then fix the wave 118
open items: the map label HELICOPTER over GLASS TOWERS (and test that no two map labels overlap), the ORACLE card cut off / over the altimeter at 2400x1080 in helicopter and plane, menu and
garage targets under 44 px at 844x390, ENTER beside a plane and plane take-off / landing by real fingers, and find whether the GPS walk to the army yard and helipad really stops 25 to 53 m short
(game bug: fix; bot bug: fix the bot). Extend godot/tests/test_controls_w118.gd (count per mode: on foot exactly 5 action circles) and keep the touch audit green. Render every mode at 844x390
and 2400x1080 into docs/shots/round7/controls_w119/ and LOOK: clean, about 5 circles, nothing over the hero or crosshair.` },
    ],
    critic: `You are the INDEPENDENT REVIEWER of wave 119 (label w119-critic), then its fixer. You did not build it; assume it is broken until you have seen it work. With a finger-only bot of your own
in the real main scene: throw every snake species at enemies, a car and a tank; check the look, the ring, the effect, the cooldown; then play on foot with only the five circles (walk, shoot,
jump, swing, zip, fly, enter a car, use a door, blast) and say whether anything a player needs is now hard to reach. Render frames and LOOK. List the 8 worst defects with evidence, fix them
most severe first, each with a check that fails without the fix. Do not stop early: if you cannot fix one, write exactly why in your report.`,
    commit: 'Wave 119: snake species with their own blasts (one SNAKE BLAST button, wheel pick, radius ring), five circles on foot, wave 118 follow-ups',
  },
  120: {
    title: 'Whole map reachable',
    builders: [
      { tag: 'reach', prompt: `TASK (label w120-reach): WHOLE MAP REACHABLE, on the ground. Owner round 7: the whole map must be reachable: mountains, river, buildings; no invisible walls. Plan line:
"no invisible walls; walk, swim, climb or fly to any mountain, river, shore or rooftop; nothing to fall through". First build a finger-only probe bot (godot/tests/dev_w120_probe.gd) that, in the
real main scene, walks / runs / jumps / snake-swings toward a grid of target points over the whole world (every district, outskirts settlement, mountain tops, river banks and bed, shores, the
airport and army yard) and records where the hero is blocked by something invisible, falls through the ground, gets stuck, or is pushed back by a world-edge wall; write the list with positions
in your log. Then fix them: remove or shrink invisible colliders that are not walls of something visible; give steep mountains a climb (snake-assisted climb or a slower scramble, your choice,
explain it); make the river and sea swimmable (swim state with its own movement, dive optional, no drowning death loop; cars sink and you get out); fill holes and seams; the world edge becomes a
visible natural boundary (sea or cliffs) with a soft turn-back, not a hard invisible wall in the middle of land. Coordinate with w120-sky (it owns flight ceilings, rooftops and the map).
Permanent test godot/tests/test_reach_w120.gd by real fingers: walk to N sample points incl. a mountain top, the river bed and a far shore; swim across the river; no fall-through at 200 random
drops; each check failing on the old code. Perf gate has zero spare draws on HIGH: trim, never raise a limit. Render frames of the swim, a climb and the boundary at 1200x540 LOW and MED and LOOK.` },
      { tag: 'sky', prompt: `TASK (label w120-sky): FLY ANYWHERE, ROOFTOPS, AND THE MAP. Owner round 7: "fly anywhere", reach buildings. First probe with a finger-only bot (godot/tests/dev_w120_sky.gd)
in the real main scene: snake flight, helicopter and plane to every corner and to the highest mountain and tallest tower; record any invisible ceiling, edge wall, forced landing, or place the
camera clips; and try to land on 20 rooftops (city towers, outskirts houses, airport, army yard) by flight and by snake zip. Write the list in your log. Fix: a flight ceiling well above the
highest peak, no invisible walls inside the map, a soft turn-back at the visible world edge (agree the edge with w120-reach, read its log), rooftops have solid tops you can stand on (no falling
through, no walking on air above them), and the map / minimap / GPS can target any reachable point (mountains, river, shore), with the wave 118 GPS short-stop bug (25 to 53 m short of the army
yard and helipad) fixed if it is still there. Permanent test godot/tests/test_sky_w120.gd by real fingers: fly to each corner and the highest peak, land on 10 rooftops, set a GPS target on a
mountain and follow it; each check failing on the old code. Keep the flight view clear (wave 116 rules). Perf gate: trim, never raise a limit. Render frames and LOOK.` },
    ],
    critic: `You are the INDEPENDENT REVIEWER of wave 120 (label w120-critic), then its fixer. You did not build it; assume it is broken until you have seen it work. With a finger-only bot of your own
in the real main scene: try to reach mountains, the river (swim across), shores, the world edge, 10 rooftops by foot, swing and flight; look for invisible walls, fall-through, stuck spots, ugly
seams and camera clipping. Render frames and LOOK. List the 8 worst defects with evidence, fix them most severe first, each with a check that fails without the fix. Do not stop early: if you
cannot fix one, write exactly why in your report.`,
    commit: 'Wave 120: whole map reachable (no invisible walls, swim, climb, fly anywhere, rooftops, map targets)',
  },
  121: {
    title: 'Buildings with floors',
    builders: [
      { tag: 'floors', prompt: `TASK (label w121-floors): BUILDINGS WITH FLOORS. Owner round 7: "building detail and interiors with stairs". Plan line: "walk in from the street, stairs, lifts, upper
floors, rooftops". First probe with a finger-only bot (godot/tests/dev_w121_probe.gd) in the real main scene: how entering a building works today (godot/scripts/interiors/*, doors, loading),
which buildings can be entered, whether interiors are one floor only, and whether the inside matches the outside size; write the findings in your log. Then build multi-floor interiors for the
city's tall buildings (towers, apartments, offices; at least 3 kinds): ground floor entered by walking in from the street door (no black loading screen if it can be avoided cheaply; if a
transition is needed keep it under 0.5 s), stairwells you walk up with real stairs (no teleport), at least 3 upper floors per tall building with rooms or offices, windows that line up with the
facade, and a roof door to the rooftop (the rooftop from wave 120 must be the same place). Generate floors on demand and free them when you leave (memory and draw budget: the perf gate has 2 spare
draws on HIGH; trim, never raise a limit). Enemies and NPCs can be on floors; missions still work. Coordinate with w121-lifts (it owns lifts, floor UI and the map), read its log.
Permanent test godot/tests/test_floors_w121.gd by real fingers: walk in from the street, climb the stairs to floor 3, walk out on the roof, come back down, leave by the street door; no fall-through,
no stuck spot, no leak after 10 entries; each check failing on the old code. Render frames (street door, stairwell, upper floor, roof door) at 1200x540 LOW and MED and LOOK.` },
      { tag: 'lifts', prompt: `TASK (label w121-lifts): LIFTS, FLOOR UI, AND THE WAVE 120 LEFTOVERS. Build lifts in the tall buildings (the other builder w121-floors makes the floors; read its log and
agree the data): a lift you walk into, a floor panel opened by one round context button (the wave 119 context slot: USE / LIFT), floors listed, doors that open and close, a short ride (under 3 s)
that really moves the cabin (no teleport cut if cheap), and the floor number shown on the HUD while inside a building; the map shows which floor you are on and the building outline. Keep the
on-foot controls at 5 circles. Then fix the wave 120 open items: the 400 m city edge walls (aircraft fly to 1000 m: make the edge consistent with the visible boundary), the floating cyan crystal
in the sea near (4300, 600), the boat turn-back damping that depends on frame rate, add finger checks for GPS to a mountain and a snake zip onto a rooftop, and test rooftops in the outskirts,
airport and army yard. Permanent test godot/tests/test_lifts_w121.gd by real fingers: call a lift, ride to the top floor and back, panel buttons all work at 844x390 and 2400x1080, every target
at least 44 px; each check failing on the old code. Perf gate: trim, never raise a limit. Render frames and LOOK.` },
    ],
    critic: `You are the INDEPENDENT REVIEWER of wave 121 (label w121-critic), then its fixer. You did not build it; assume it is broken until you have seen it work. With a finger-only bot of your own
in the real main scene: enter 5 different tall buildings from the street, climb stairs, ride lifts, reach the roof and come back, fight an enemy on an upper floor, leave; look for falling through
floors, stuck spots, windows that do not match the facade, camera clipping in stairwells, dead buttons. Render frames and LOOK. List the 8 worst defects with evidence, fix them most severe first,
each with a check that fails without the fix. Do not stop early: if you cannot fix one, write exactly why in your report.`,
    commit: 'Wave 121: buildings with floors (walk in from the street, stairs, lifts, upper floors, rooftops), wave 120 follow-ups',
  },
  122: {
    title: 'Building detail',
    builders: [
      { tag: 'rooms', prompt: `TASK (label w122-rooms): ROOMS THAT MATCH THE OUTSIDE, AND FURNITURE. Owner round 7: "buildings with interiors, stairs and detail". Plan line: "rooms that match the outside,
furniture, windows you can see through, shops". First probe with a finger-only bot (godot/tests/dev_w122_probe.gd) in the real main scene: enter 6 kinds of building (tower office, apartment, house,
outskirts house, airport hall, army building) and record whether the inside footprint, floor count, window positions and door position match the outside, and whether rooms are bare or white
(wave 121 left "white interiors on MED" unchecked); write the findings in your log. Then make every enterable kind match: inside size from the outside footprint, window holes where the facade
windows are, the street door where the facade door is. Furnish rooms by type (office desks, chairs, screens; apartment beds, sofas, kitchens; storage shelves; lobby desk and plants) using the
existing CC0 kit (Kenney furniture or the interior kit already in the repo; only CC0 or own-made assets), with MultiMesh or shared meshes so the draw budget holds (HIGH death is AT its limit 170:
trim elsewhere, never raise a limit). Fix the wave 121 leftovers: stairwell window holes that open onto the street, rain showing inside tower lobbies on MED, the gun staying visible while the hero
fades, and add enemies and NPCs on tower floors. Coordinate with w122-shops (it owns windows, glass and shops), read its log. Permanent test godot/tests/test_rooms_w122.gd by real fingers: walk
into each kind, check footprint match, windows aligned, furniture present and collidable, no white untextured room on LOW and MED; each check failing on the old code. Render frames of each kind at
1200x540 LOW and MED (and one at 2400x1080 MED if memory allows) and LOOK.` },
      { tag: 'shops', prompt: `TASK (label w122-shops): WINDOWS YOU CAN SEE THROUGH, AND SHOPS. Build see-through windows: from the street you see lit rooms behind glass (cheap: an interior-mapping
shader or a baked room card per window, not real geometry for every building), and from inside you see the real street through the window holes, with glass that reflects lightly. Then shops: at
least 6 shop kinds on the streets (food, clothes, guns, cars or bikes, electronics, pharmacy) with a glass front, shelves and goods inside, a shopkeeper, walk-in from the street, a buy prompt on the
round context button (the wave 119 context slot, on-foot controls stay at 5 circles) wired to the existing shop and economy code, and shop icons on the map. Also add parapet colliders on city roofs
so you cannot walk off by accident (snake swing and jumping off on purpose must still work). Coordinate with w122-rooms (it owns room layout and furniture), read its log. Permanent test
godot/tests/test_shops_w122.gd by real fingers at 844x390 and 2400x1080: see a lit room through a window from the street, walk into each shop kind, buy an item, see the shop on the map, roof parapet
stops a walk but not a jump; each check failing on the old code. Perf gate: trim, never raise a limit. Render frames (street windows day and night, shop fronts, shop inside) LOW and MED and LOOK.` },
    ],
    critic: `You are the INDEPENDENT REVIEWER of wave 122 (label w122-critic), then its fixer. You did not build it; assume it is broken until you have seen it work. With a finger-only bot of your own
in the real main scene: walk into 6 different buildings and 4 shops, compare inside to outside, look through windows both ways, buy something, walk on a roof edge; look for rooms that do not match,
floating or clipping furniture, white or missing textures, windows showing nothing, dead buy buttons, frame drops. Render frames and LOOK. List the 8 worst defects with evidence, fix them most
severe first, each with a check that fails without the fix. Do not stop early: if you cannot fix one, write exactly why in your report.`,
    commit: 'Wave 122: building detail (rooms match the outside, furniture, see-through windows, shops, roof parapets), wave 121 follow-ups',
  },
  123: {
    title: 'Street detail',
    builders: [
      { tag: 'clutter', prompt: `TASK (label w123-clutter): SIDEWALK CLUTTER, STOREFRONT DEPTH AND SIGNS. Owner round 7: "street detail". Plan line: "sidewalk clutter, storefront depth, signs, street
life". First probe with a finger-only bot (godot/tests/dev_w123_probe.gd) in the real main scene: walk 4 city streets and 2 outskirts streets, render frames at eye height (1200x540 LOW and MED) and
list what looks bare; write it in your log. Then add, with the existing CC0 kits only (or own-made), batched with MultiMesh or shared meshes: sidewalk clutter (lamp posts, benches, bins, hydrants,
bollards, planters, newspaper boxes, bike racks, bus stops, parking meters, street trees with grates), storefront depth (recessed doors, awnings, shop window displays, roller shutters on closed
shops), and signs (shop signs, street name signs at corners, traffic signs, a few billboards; original names only). Clutter must never block doors, the walk-in shops of wave 122, roads, or the
hero's path: keep a clear lane, and move props and parked vans away from doors (wave 122 open item). BUDGETS ARE FULL: HIGH death spike is at its limit 170 and test_integration is at 2990-2994 of
3000 nodes; you must trim elsewhere to fit, never raise a limit (MultiMesh per chunk, no per-prop nodes). Coordinate with w123-life (it owns moving street life), read its log. Permanent test
godot/tests/test_clutter_w123.gd by real fingers: walk a street with no stuck spot, every door and shop door reachable with no prop in front, props collide where they should, node and draw counts
within budget; each check failing on the old code. Render before/after frames and LOOK.` },
      { tag: 'life', prompt: `TASK (label w123-life): STREET LIFE AND WAVE 122 LEFTOVERS. Make streets feel alive: pedestrians doing things (waiting at bus stops, sitting on benches, using phones,
chatting in pairs, walking dogs, entering and leaving shops), street vendors and food carts, buses stopping at stops, delivery vans unloading, birds, puddles and steam vents; reuse the existing
NPC and traffic systems, and pool everything (node budget is 2990-2994 of 3000 and the HIGH death spike is at its limit: trim, never raise a limit). Then fix the wave 122 leftovers: JUMP at a door
frame starting a wall run that hangs or exits through the wall (make a check that reproduces it first), the CLIMB hint showing inside shops, glass in tower-floor and lobby window holes, and a test
for the snake swing over a roof parapet. Permanent test godot/tests/test_life_w123.gd by real fingers: on one street see at least 5 kinds of activity within 30 s, people use benches and bus stops,
a bus stops and leaves, the door-frame jump never hangs, no CLIMB hint in a shop, snake swing passes a parapet; each check failing on the old code. Render frames LOW and MED and LOOK.` },
    ],
    critic: `You are the INDEPENDENT REVIEWER of wave 123 (label w123-critic), then its fixer. You did not build it; assume it is broken until you have seen it work. With a finger-only bot of your own
in the real main scene: walk and drive 5 streets day and night, enter shops, run through crowds, crash a car into clutter; look for props blocking doors or paths, floating or clipping props,
pedestrians stuck or walking through things, signs with wrong text, frame drops, node growth. Render frames and LOOK. List the 8 worst defects with evidence, fix them most severe first, each with a
check that fails without the fix. Do not stop early: if you cannot fix one, write exactly why in your report.`,
    commit: 'Wave 123: street detail (sidewalk clutter, storefront depth, signs, street life), wave 122 follow-ups',
  },
  124: {
    title: 'Frame rate, finish street detail, demo god mode',
    builders: [
      { tag: 'fps', prompt: `TASK (label w124-fps): FRAME RATE. Plan line 124: "measured recovery on the phone tiers (owner: 37 to 45 FPS on LOW+, drops to 13 to 28 in flight); win back draw,
triangle and script headroom." First measure, with tools/perf_report.sh and a profiling probe of your own (godot/tests/dev_w124_probe.gd), where frame time goes on foot in the city, driving, and in
FLIGHT over the city and outskirts (draw calls, triangles, visible lights/shadows, script time per system with Performance monitors and per-system timers). Write the top costs in your log with
numbers. Then win back headroom without lowering visual quality the owner can see: fix the flight drop first (view distance / LOD / impostor use at altitude, culling of street-level detail and
interiors from the air, traffic and pedestrian sim throttled by distance, shadow distance at altitude), then on-foot: merge draws, distance-throttle script _process/_physics_process (AI, traffic,
pedestrians, props, audio), cut idle nodes and per-frame allocations. Never raise a perf limit; the goal is clear headroom under LOW 108 / MED 148 / HIGH 170 death spikes, and report the new
numbers for flight too. NODE LIMIT: the OWNER explicitly asked to raise the test_integration node limit from 3000 to 7000 (godot/tests/test_integration.gd line ~127). Do that change (update the
message text too) and nothing else about limits; draw/triangle/perf gates stay as they are, they are the real phone cost. Permanent test godot/tests/test_fps_w124.gd: flight over the city keeps
draws and triangles under a stated budget per tier, script time of throttled systems falls with distance, each check failing on the old code. Report before/after numbers for every tier, on foot
and in flight.` },
      { tag: 'street-demo', prompt: `TASK (label w124-street-demo): FINISH WAVE 123 STREET DETAIL, THEN DEMO GOD MODE. Read docs/sprint/progress/w123-*.md and docs/HANDOFF.md "Wave 123
integration" first. Part 1, the wave 123 items that were NOT done: new prop kinds (shop signs, street name signs at corners, traffic signs, a few billboards with original names, newspaper boxes,
bike racks, parking meters, street trees with grates), storefront depth (recessed doors, awnings, shop window displays, roller shutters on closed shops), outskirts street clutter; glass in tower
and lobby window holes; the parked car on the sidewalk in a bench area; the floating BLACK MARKET SHOP label overlapping the NEON and QUANTA BAR signs; buses really stopping at bus stops. CC0 kits
or own-made only, MultiMesh / shared meshes, never block doors, shops, roads or the hero's path. The node test limit is being raised to 7000 by w124-fps (owner's decision), but draw/triangle and
perf death-spike limits stay: trim elsewhere if needed, never raise them. Part 2, DEMO MODE AS GOD MODE (owner: "in demo mode we should be able to select all weapons, all missions etc like a god
mode"). Read scripts/demo/demo_mode.gd and scripts/ui/demo_panel.gd. Audit with a finger-only bot that in demo mode EVERY weapon of the full roster (200+, all classes, attachments, ammo types),
every mission (chapters, sequel, side, heists, contracts, bosses, arena, chases, stealth...), every vehicle and aircraft, every verb/ability/skill, every hero look and upgrade is selectable and
usable, with god mode, infinite ammo and max money available as toggles; add what is missing (e.g. a WEAPONS tab with every weapon, VEHICLES tab, UNLOCK ALL / ALL SKILLS toggles), keeping the
demo save separate from the real save. Permanent tests godot/tests/test_street_w124.gd and godot/tests/test_demo_god_w124.gd by real touch events: each new prop kind is present and never in front
of a door, the label overlap is gone, a bus stops at a stop; in demo mode every weapon id and every mission id can be picked from the menu and starts; each check failing on the old code. Render
frames LOW and MED and LOOK. Coordinate with w124-fps (it owns perf trims), read its log.` },
    ],
    critic: `You are the INDEPENDENT REVIEWER of wave 124 (label w124-critic), then its fixer. You did not build it; assume it is broken until you have seen it work. With a finger-only bot of
your own in the real main scene: fly over the city and outskirts at each tier and measure draws/triangles/frame time against the builder's claims; walk and drive 5 streets day and night looking for
props blocking doors, floating or clipping props, wrong sign text, label overlaps; open DEMO mode and try at least 30 random weapons, 15 random missions, 5 vehicles and 3 aircraft from its menu, and
check god mode and infinite ammo work and the real save is untouched. List the 8 worst defects with evidence, fix them most severe first, each with a check that fails without the fix. Do not stop
early: if you cannot fix one, write exactly why in your report.`,
    commit: 'Wave 124: frame rate headroom (flight and on foot), node limit 7000 by owner, wave 123 street detail finished, demo mode god mode',
  },
  1242: {
    title: 'Wave 124 part 2: frame rate and wave 123 street detail (both skipped in the first pass)',
    builders: [
      { tag: 'fps2', prompt: `TASK (label w1242-fps): FRAME RATE. The first wave 124 builder stopped after one edit and did NOTHING of this; you must do the whole job and not stop early. Read
docs/sprint/progress/w124-fps.md. Plan line 124: "measured recovery on the phone tiers (owner: 37 to 45 FPS on LOW+, drops to 13 to 28 in flight); win back draw, triangle and script headroom." Work in
this order and update your progress log after each step: (1) write godot/tests/dev_w124_probe.gd that measures draw calls, triangles, visible lights/shadows and script time per system
(Performance monitors plus your own per-system timers) on foot in the city, driving, and FLYING over the city and over the outskirts, at LOW, MED and HIGH; write the top 10 costs with numbers in your
log. (2) Fix the flight drop: at altitude cull street-level detail and interiors, use LOD/impostors, cut shadow distance, throttle traffic/pedestrian/AI sim by distance. (3) On foot: distance-throttle
_process/_physics_process of AI, traffic, pedestrians, props and audio; merge draws; cut idle nodes and per-frame allocations. No visual quality the owner can see may drop. Never raise a perf
limit (LOW 108 / MED 148 / HIGH 170 death spikes stay; node test limit is 7000 by the owner). (4) Permanent test godot/tests/test_fps_w124.gd: flight over the city keeps draws and triangles under a
stated budget per tier, throttled systems spend less script time far away; each check failing on the old code (show it). (5) Report a before/after table for every tier, on foot, driving and flying.` },
      { tag: 'street2', prompt: `TASK (label w1242-street): FINISH WAVE 123 STREET DETAIL. The wave 124 builder skipped this part entirely; you must do it all and not stop early. Read
docs/sprint/progress/w123-*.md, w124-street-demo.md and docs/HANDOFF.md "Wave 123 integration" / "Wave 124 integration". Do, updating your progress log after each item: (1) new prop kinds: shop signs,
street name signs at corners, traffic signs, a few billboards (original names only), newspaper boxes, bike racks, parking meters, street trees with grates; (2) storefront depth: recessed doors,
awnings, shop window displays, roller shutters on closed shops; (3) outskirts street clutter; (4) glass in tower and lobby window holes; (5) move the parked car off the sidewalk in the bench area;
(6) fix the floating BLACK MARKET SHOP label overlapping the NEON and QUANTA BAR signs; (7) buses really stopping at bus stops and leaving. CC0 kits or own-made only, MultiMesh / shared meshes per
chunk, never block doors, shops, roads or the hero's path. Draw/triangle/perf death-spike limits stay (trim elsewhere if needed); the node test limit is 7000 by the owner. Coordinate with w1242-fps
(it owns perf trims), read its log. Permanent test godot/tests/test_street_w124.gd by real touch events: each new prop kind present and never in front of a door, no label overlap, a bus stops at a
stop, window holes have glass; each check failing on the old code. Render before/after frames LOW and MED at eye height and LOOK at them.` },
    ],
    critic: `You are the INDEPENDENT REVIEWER of wave 124 part 2 (label w1242-critic), then its fixer. Assume it is broken until you have seen it work. The previous reviewer skipped the play review;
you must not. With a finger-only bot of your own in the real main scene: fly over the city and outskirts at LOW, MED and HIGH and measure draws/triangles/frame time against the builder's table; walk
and drive 5 streets day and night looking for props blocking doors, floating or clipping props, wrong sign text, label overlaps, missing glass, buses. Also open DEMO mode and try 30 random weapons and
15 random missions. List the 8 worst defects with evidence, fix them most severe first, each with a check that fails without the fix. If you cannot fix one, write exactly why.`,
    commit: 'Wave 124 part 2: frame rate headroom (flight and on foot), wave 123 street detail finished',
  },
  125: {
    title: 'Helicopter roster',
    builders: [
      { tag: 'helis', prompt: `TASK (label w125-helis): HELICOPTER ROSTER. Plan line 125: "HELICOPTER ROSTER (22+ kinds), cockpits, helipads." First read what exists (aircraft models, AircraftFlight, FlightHud,
helipads, air traffic, hijack; grep scripts and docs/HANDOFF.md) and count the current helicopter kinds in your log. Then reach at least 22 distinct helicopter kinds (light scout, news, police, air
ambulance, utility, tandem-rotor cargo, heavy lift, gunship, attack, stealth, coaxial, tilt-rotor, crane, firefighting, VIP, trainer, sci-fi quantum variants...), each with its own model (CC0 or
own-made in Blender, original names only, no real brands), its own flight numbers (speed, climb, turn, mass, rotor sound pitch), and an icon. Shared meshes / LODs so a parked or far heli costs
almost nothing. Each heli must be flyable by touch with the existing flight controls and be stealable/boardable. Coordinate with w125-pads (it owns cockpits and helipads), read its log. Permanent
test godot/tests/test_helis_w125.gd by real touch events: every kind spawns, boards, lifts off, flies a short route, lands; each check failing on the old code. Render a lineup of all kinds LOW and
MED and LOOK. BUDGETS: perf death-spike limits LOW 108 / MED 148 / HIGH 170 and the MED triangle budget 280k (now at 275k) must hold; trim, never raise a limit (node test limit is 7000).` },
      { tag: 'pads', prompt: `TASK (label w125-pads): HELICOPTER COCKPITS AND HELIPADS. Plan line 125. Read what exists first. (1) Cockpit view for helicopters: a first-person cockpit (seat, frame, glass, instrument panel with working gauges: altitude, speed, heading, rotor rpm, fuel/damage) that the
hero can switch to with a touch button, readable on a phone, with the flight HUD kept clear (wave 116 view rules). A few cockpit families shared across the 22+ kinds of w125-helis. (2) Helipads:
rooftop pads on tall city buildings, hospital, police, news station, airport, army base and outskirts pads, each with markings, lights at night and a spawned heli of a fitting kind; show them on the
map and minimap; landing on a pad parks the heli. Coordinate with w125-helis, read its log. Permanent test godot/tests/test_helipads_w125.gd by real touch events: cockpit toggles and gauges move,
every pad is reachable and a landing on it parks the heli, map icons exist; each check failing on the old code. Render cockpit and pad frames day and night LOW and MED and LOOK. Budgets as in the
plan: never raise a perf limit (MED triangle budget 280k is tight), trim elsewhere.` },
    ],
    critic: `You are the INDEPENDENT REVIEWER of wave 125 (label w125-critic), then its fixer. Assume it is broken until you have seen it work. With a finger-only bot of your own in the real main
scene: board and fly at least 10 different helicopter kinds, use the cockpit view, land on 5 different helipads day and night, crash one into a building, check frame time and draws in flight at LOW
and MED. Look for clipping rotors, wrong scale, unflyable kinds, unreadable cockpits, pads with no heli or blocked, HUD overlap. List the 8 worst defects with evidence, fix them most severe first,
each with a check that fails without the fix. If you cannot fix one, write exactly why.`,
    commit: 'Wave 125: helicopter roster (22+ kinds), cockpits, helipads',
  },
  126: {
    title: 'Aeroplane roster',
    builders: [
      { tag: 'planes', prompt: `TASK (label w126-planes): AEROPLANE ROSTER AND HANGARS. Plan line 126: "AEROPLANE ROSTER (30+ kinds), hangars, air traffic, air missions, aircraft weapons." Read what exists
(aircraft models, AircraftFlight, airport world, wave 125 helis) and count current plane kinds in your log. Reach at least 30 distinct aeroplane kinds (light prop, trainer, aerobatic, crop duster,
seaplane, bush plane, business jet, regional prop, narrow-body and wide-body airliners, cargo, fighter, interceptor, ground attack, bomber, stealth, tanker, AWACS, drone, glider, sci-fi quantum
craft...), each with a model (CC0 or own-made, original names, no real brands), flight numbers (stall speed, top speed, roll/pitch rates, takeoff run) and an icon; shared meshes / LODs. Every kind
flyable by touch, takes off and lands on the runway. Hangars at the airport and army base, enterable on foot, holding parked planes you can board. Permanent test godot/tests/test_planes_w126.gd by
real touch events: every kind spawns, takes off, flies, lands; hangar doors work; each check failing on the old code. Render a lineup LOW and MED and LOOK. Budgets: never raise a perf limit (MED
triangle budget 280k is tight), trim elsewhere. Coordinate with w126-air (it owns traffic, missions and weapons), read its log.` },
      { tag: 'air', prompt: `TASK (label w126-air): AIR TRAFFIC, AIR MISSIONS AND AIRCRAFT WEAPONS. Plan line 126. Read what exists first (AI air traffic, hijack, aircraft weapons, mission board, blast table).
(1) Air traffic uses the new roster of w126-planes and wave 125 helis: airliners take off and land on a schedule, light planes and helis cross the sky, all pooled and LOD'd. (2) At least 6 air missions
on the mission board (dogfight, escort an airliner, bomb run, cargo drop, rescue by heli, race through rings), each finishable by touch, with the existing mission guide and checkpoints. (3) Aircraft
weapons by class from the blast table: guns, rockets, missiles with lock-on, bombs, flares; touch buttons on the flight HUD kept clear (wave 116 view rules). Permanent test
godot/tests/test_air_w126.gd by real touch events: traffic takes off and lands, every air mission starts and can be finished by a bot, each weapon kind fires and hits; each check failing on the old
code. Render frames and LOOK. Budgets: never raise a perf limit, trim elsewhere. Coordinate with w126-planes, read its log.` },
    ],
    critic: `You are the INDEPENDENT REVIEWER of wave 126 (label w126-critic), then its fixer. Assume it is broken until you have seen it work. With a finger-only bot of your own in the real main
scene: fly at least 10 different plane kinds (take off, fly, land), enter a hangar, play 3 air missions to the end, fire every aircraft weapon kind, watch air traffic at the airport for 2 minutes, and
measure frame time and draws in flight at LOW and MED. Look for planes that cannot take off or land, clipping, wrong scale, traffic collisions, unfinishable missions, HUD overlap. List the 8 worst
defects with evidence, fix them most severe first, each with a check that fails without the fix. If you cannot fix one, write exactly why.`,
    commit: 'Wave 126: aeroplane roster (30+ kinds), hangars, air traffic, air missions, aircraft weapons',
  },
  127: {
    title: 'Tanks and military ground vehicles',
    builders: [
      { tag: 'tanks', prompt: `TASK (label w127-tanks): TANKS AND MILITARY GROUND VEHICLES ROSTER. Plan line 127: "TANKS AND MILITARY GROUND VEHICLES roster, vehicle weapons from the blast table." First read what exists
(vehicles, armour_sites.gd, army base, vehicle weapons, blast table, wave 125/126 rosters and how they stay outside the live car limit) and count current military ground vehicle kinds in your log. Reach at
least 20 distinct kinds (light tank, main battle tank, heavy tank, tank destroyer, SPG/artillery, rocket artillery, APC wheeled and tracked, IFV, scout car, MRAP, armoured jeep, military truck, fuel truck,
recovery vehicle, mobile AA, bridge layer, mine clearer, amphibious APC, sci-fi hover tank, quantum walker...), each with a model (CC0 or own-made in Blender, original names only, no real brands), its
own driving numbers (speed, turn, mass, armour), tracks or wheels that animate, a turret that turns, and an icon. Shared meshes / LODs so parked or far vehicles cost almost nothing; keep them outside the
live car limit like the aircraft lines. Parked at the army base, a vehicle depot, and a few outskirts checkpoints. Every kind drivable by touch and boardable. Coordinate with w127-arms (it owns weapons,
damage and AI tank crews), read its log. Permanent test godot/tests/test_tanks_w127.gd by real touch events (split into _b if over 100 s): every kind spawns, boards, drives a short route, turns its
turret; each check failing on the old code. Render a lineup LOW and MED and LOOK. BUDGETS: perf death-spike limits LOW 108 / MED 148 / HIGH 170 and the MED triangle budget 280k (now 275k) must hold;
trim elsewhere, never raise a limit (node test limit is 7000).` },
      { tag: 'arms', prompt: `TASK (label w127-arms): VEHICLE WEAPONS, DAMAGE AND TANK COMBAT. Plan line 127. Read what exists first (vehicle weapons, blast table, AirArms of wave 126, enemy AI, wanted levels).
(1) Vehicle weapons from the blast table per class: main cannon (AP / HE shells), coax and roof machine guns, ATGM with lock-on, artillery indirect fire with a target marker, rocket salvo, AA flak, smoke
launchers; touch buttons on the vehicle HUD kept clear and readable, a turret aim that follows the camera, reload timers. (2) Armour and damage: hit zones (front/side/rear/tracks/turret), track
damage that slows or stops, burning and wreck states using the existing damage system. (3) Enemy tank crews: military AI that drives and fights in tanks at the army base and at high wanted levels,
pooled, distance-throttled. (4) At least 3 tank missions on the mission board (tank battle, convoy escort, artillery strike), finishable by touch with the mission guide. Permanent test
godot/tests/test_tank_arms_w127.gd by real touch events: every weapon kind fires and hits, hit zones and track damage work, an enemy tank engages and can be destroyed, every tank mission starts and a
bot finishes it; each check failing on the old code. Render frames and LOOK. Budgets: never raise a perf limit (MED triangles 280k tight), trim elsewhere. Coordinate with w127-tanks, read its log.` },
    ],
    critic: `You are the INDEPENDENT REVIEWER of wave 127 (label w127-critic), then its fixer. Assume it is broken until you have seen it work. With a finger-only bot of your own in the real main
scene: drive at least 10 different tank and military vehicle kinds, fire every vehicle weapon kind, fight an enemy tank, play 2 tank missions to the end, crash into buildings and traffic, check that
city streets and bridges can be driven, and measure frame time and draws at LOW and MED with several tanks in view. Look for clipping, wrong scale, turrets that do not follow, unfinishable missions,
HUD overlap, perf drops. List the 8 worst defects with evidence, fix them most severe first, each with a check that fails without the fix. If you cannot fix one, write exactly why.`,
    commit: 'Wave 127: tanks and military ground vehicles (20+ kinds), vehicle weapons from the blast table, tank combat and missions',
  },
}
const W = WAVES[N]
if (!W) { log(`wave ${N} has no definition in this script yet: add it to WAVES`); return { wave: N, error: 'no definition' } }
const L = t => `w${N}-${t}`
log(`wave ${N}: ${W.title}`)

if (!A.ciSha) {
  phase('Build')
  const built = await parallel(W.builders.map(b => () => {
    if (SKIP.includes(b.tag)) return Promise.resolve(REP[b.tag] || `finished before the restart: its report is in docs/sprint/progress/${L(b.tag)}.md`)
    const restart = A.restarted ? `\nRESTART NOTICE: this task was started before and interrupted. Read docs/sprint/progress/${L(b.tag)}.md and git status first and continue from there; do not redo finished steps.` : ''
    return agent(COMMON + '\n' + b.prompt + restart, { label: L(b.tag), phase: 'Build', effort: EFF })
  }))
  const reports = W.builders.map((b, i) => `--- ${L(b.tag)} ---\n${built[i] || 'NO REPORT (the agent died): read docs/sprint/progress/' + L(b.tag) + '.md'}`).join('\n')

  phase('Review')
  const critic = A.skipCritic ? (REP.critic || `finished before the restart: docs/sprint/progress/${L('critic')}.md`)
    : await agent(COMMON + '\nTASK: ' + W.critic + (A.restarted ? `\nRESTART NOTICE: read docs/sprint/progress/${L('critic')}.md first and continue.` : '') + '\nThe builders reported:\n' + reports,
        { label: L('critic'), phase: 'Review', effort: EFF })

  phase('Integrate')
  var integ = await agent(COMMON + `\nTASK (label ${L('integrator')}): YOU ARE THE INTEGRATOR of wave ${N}. The builders and the reviewer left their work uncommitted in the tree. (1) tools/import.sh, then the FULL suite
(godot/tools/test_all.sh logic, 3 jobs, a clean XDG_DATA_HOME per test, one retry; a tool call is limited to 10 minutes, so run it in resumable slices in the background and poll); look at
every FAIL against a copy of HEAD to tell this wave from old flakes; fix real bugs, move stale tests with a reason, weaken nothing. (2) PERF_CHECK=1 tools/perf_report.sh 0 1 2: all three OK,
no limit raised (trim instead). (3) tools/visual_qa.sh and LOOK at docs/shots/latest.png. (4) Run every touch test of this wave again on the final tree. (5) Tidy (no scratch files, disk),
add a section "Wave ${N} integration" to docs/HANDOFF.md (what the wave holds, suite result, perf lines, open follow-ups), then commit everything that belongs to the wave (never
docs/sprint/progress/auto_*.md or AUTO_INDEX.md) with the message "${W.commit}" and the trailers "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" and
"Claude-Session: https://claude.ai/code/session_01WbKrgUpExX7TuSc4cdY35F", and git push origin main (fetch and rebase first if main moved: the main session pushes notes with [skip ci]).
Never push with a perf verdict OVER. FINAL message: the commit sha on the first line, then the summary.\nReports:\n` + reports + '\n--- reviewer ---\n' + (critic || 'NO REPORT'),
    { label: L('integrator'), phase: 'Integrate', effort: EFF })
} else {
  var integ = String(A.ciSha)
}

phase('CI and APK')
const ci = await agent(`You watch the CI of wave ${N} of the game in /home/user/QUANTUM_Teleportar (repo pikishor/QUANTUM_Teleportar, branch main) and then build the phone APK (label ${L('ci-apk')}).
The integrator reported: ${String(integ).slice(0, 600)}
(1) Find the CI run of that commit (gh run list -w ci.yml -L 5) and wait for it WITHOUT burning turns: one background shell loop that sleeps and exits when the run completes (a tool call
is limited to 10 minutes; a shard takes up to 45). (2) If it is red: read which tests failed (the check-run annotations name them: docs/HANDOFF.md "Wave 114 CI fixes"), reproduce locally
(the runner's font is DejaVu: the FONTCONFIG_FILE trick is in that section), fix the REAL cause (never skip, weaken or retry-loop a test), commit only your own paths with the same
trailers as the last commit on main, push, wait again. Keep notes in docs/sprint/progress/${L('ci-apk')}.md and a section "Wave ${N} CI fixes" in docs/HANDOFF.md. (3) When CI is green:
gh workflow run android.yml --ref main, wait for it, and read the artifact (gh api repos/pikishor/QUANTUM_Teleportar/actions/runs/<id>/artifacts).
FINAL message, first line: GREEN <sha> APK <run url> ARTIFACT <artifact id> <bytes>; then what was red and how it was fixed, and tests that only passed on a retry.`,
  { label: L('ci-apk'), phase: 'CI and APK', effort: EFF })
return { wave: N, integrator: integ, ci }
