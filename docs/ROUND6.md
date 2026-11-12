# Owner round 6 (build 236b05e, wave 110; owner rating 4/10) and the sprint that answers it

Owner words: "good progress but not great. make it much much better. cars should be better. also much much more weapons. also damage.
also better outside inside as well as bigger map. trees waterfalls. many cars on the outside, even houses; right now it is blank. also better
enemies as well as hero look. cars are going inside other cars etc. also look even worse than before. also weapons looks and other things in
the app should be better. it should be like playing GTA and Call of Duty, like PS5 but on mobile. also the hero's much more capability to
jump and to fly like Spider-Man but it will be through QUANTUM SNAKES. also bombs of quantum snakes. first make all these changes then I will
give more outputs. make full quality; highest-level subagents are allowed today; I do not want cars that look low quality."
Frames: docs/owner_shots/round5 (r5_01..r5_24).

## What the frames show (defects to fix, not a wish list)
1. Cars are toy-like: faceted wedge bodies, flat black windscreens, no glass reflection, no lights detail, box truck is a plain box with an empty black cabin.
2. Traffic and parked cars intersect each other (no vehicle-vs-vehicle separation, spawn overlap, no following distance).
3. Outskirts are blank: long dark road, cuboid hedges, flat lilac beach and sea with no shoreline detail, almost no cars, houses, people, animals.
4. Weapon menus have many entries but the pictures are tiny stubs; weapons in hand look like grey blocks; damage is not visible enough.
5. Hero looks bare; enemies are not readable or varied enough.
6. The hero has jump/glide but no signature traversal. New verb set: QUANTUM SNAKES (tendrils): swing from any building like Spider-Man, pull, zip, fly; and quantum snake bombs.

## Owner follow-up (same day, after the sprint launched)
"remember many more weapons and many more helicopters aeroplanes. as well as abilities like spiderman with quantum snakes and blast radius
weapons etc. i have also turned on max effort for you too. so ensure you and subagents work on max effort."
Consequences: (1) an AIRCRAFT ROSTER wave (many more helicopters and aeroplanes, not the 8 kinds of wave 106); (2) the weapon roster target rises to
200+ with a dedicated BLAST-RADIUS ARSENAL (60+ explosives, launchers, mines, strikes) and a radius ring preview; (3) the QUANTUM SNAKES wave is split
into traversal (swing, zip, climb walls, fly) and combat (pull, grab, nets, shield, snake bombs); (4) every agent of the sprint runs at MAX effort,
including integrators and CI watchers, and four waves get an independent critic plus fixers before integration.

## Sprint (waves 111-121; wave 111 ran from script round6_111.js, waves 112-121 run from round6c_112.js), MAX effort for every agent
This machine has 4 CPUs, so a workflow runs at most 2 agents at the same time. Waves therefore have 2 or 4 builders (never 3, which would leave a slot idle),
the per-wave critics run as a pair of critic-fixers (one LOOK, one PLAY lens; each reviews, then fixes what it found), and every wave ends with an integrator
(full suite, perf gate on LOW, MED and HIGH, visual QA, commit and push) and a CI watcher. Honest time estimate at max effort: about 7 to 11 hours per wave
with four builders or critic-fixers, 5 to 8 hours with two, in all roughly 3 days for waves 112 to 121.
111 DONE (146c20d). Cars v2 (Blender-generated high-detail car set, glass/lights/interiors/paint/damage) + vehicle-vs-vehicle collision, traffic spacing, many cars outside the city. Android build.
112 Cars second pass (independent; the near-traffic cars still look faceted) + landscape (trees, forests, waterfalls, rivers, shores, rocks, grass) + outskirts settlements and a bigger map + hero look and suits. Critic-fixers.
113 Weapon ROSTER (200+ weapons in all classes, distinct mechanics, attachments, ammo types) + BLAST-RADIUS ARSENAL (60+ explosives, launchers, mines, strikes; BlastTable, radius rings, craters, chain reactions) + damage everywhere + enemy roster look (16+ types). Critic-fixers. Android build.
114 Weapon ART and PRESENTATION (a parametric Blender weapon kit: a distinct in-hand model for every weapon, class animations, effects; rendered pictures, stat screens, sounds). Critic-fixers.
115 Hero QUANTUM SNAKES: traversal (swing, zip, climb walls, fly) + combat (pull, grab, nets, shield, 12+ snake bombs). Critic-fixers. Android build.
116 AIRCRAFT ROSTER (22+ helicopters, 30+ aeroplanes and other flyers, flight models per class, cockpits, hangars and helipads across the world, ambient air traffic, air missions, aircraft weapons from the new blast table) + interiors much better (outside matches inside). Critic-fixers. Android build.
117 Vertical buildings (stairs, lifts, rooftops, sniper) + casual play, HERO MODE (unlock everything) and a real TEST AREA (shooting range, explosive range, vehicle track, air course, snake course).
118 Human and creature animation (incl. snake, flight and pilot poses) + machine and aircraft animation and FX + world life density (people, cars, animals, enemies find you).
119 Street and building detail + menu polish + PERFORMANCE BUDGET RECOVERY (win back draw, triangle and texture headroom). Android build.
120 Director review 7 (three independent harsh reviewers: art, play feel, systems and performance; merged into one list of the 24 worst defects).
121 Fixes from the review (three fix builders), final Android build.
Honest limit stays: phone GPU budget and CC0/own-made art mean "PS5 level" is a direction, not a result; each wave is judged by frames against docs/owner_shots.
