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
phone-only layers on (CrateReveal._quiet = 0); (2) each fix gets a check that FAILS on the old code (show it failing first); (3) never weaken a test, never raise a perf limit
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
docs/sprint/progress/auto_*.md or AUTO_INDEX.md) with the message "${W.commit}" and the trailers "Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>" and
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
