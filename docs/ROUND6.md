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

## Sprint (waves 111-122; wave 111 ran from script round6_111.js, waves 112-122 from round6b_112.js), MAX effort, every wave: 2-3 builders, integrator (full suite, perf gate, visual QA), CI watcher
111 Cars v2 (Blender-generated high-detail car set, glass/lights/interiors/paint/damage) + vehicle-vs-vehicle collision, traffic spacing, many cars outside the city.
112 Landscape (trees, forests, waterfalls, rivers, shores, rocks, grass) + outskirts settlements (houses, villages, farms, stations) and a bigger map, plus an independent second pass on the cars of wave 111; critic and fixers.
113 Weapon ROSTER (200+ weapons in all classes, distinct mechanics, attachments, ammo types) + BLAST-RADIUS ARSENAL (60+ explosive weapons and gadgets, blast table, radius rings, craters, chain reactions) + damage everywhere (enemies, cars, buildings, props, ground); critic and fixers.
114 Weapon ART and PRESENTATION (a parametric Blender weapon kit: a distinct in-hand model for every weapon, class animations, effects; rendered pictures, stat screens, sounds) + enemy roster look (16+ types); critic and fixers. Android build.
115 Hero QUANTUM SNAKES traversal (swing, zip, climb walls, fly) + snake combat (pull, grab, nets, shield, 12+ snake bombs) + hero look and suits; critic and fixers. Android build.
116 AIRCRAFT ROSTER (16+ helicopters, 24+ aeroplanes and other flyers, flight models per class, cockpits, hangars and helipads across the world, ambient air traffic, air missions, aircraft weapons from the new blast table); critic and fixers. Android build.
117 Vertical buildings (stairs, lifts, rooftops, sniper) + interiors much better (outside matches inside).
118 Casual play + hero mode (unlock everything) plus world life density (people, cars, animals, enemies find you).
119 Human + creature animation overhaul (including snake, flight and pilot poses).
120 Machine animation and vehicle/aircraft FX + street and building detail + menus polish. Android build.
121 Director review 7 (three independent harsh reviewers: art, play feel, systems and performance; merged into one list of the 24 worst defects).
122 Fixes from the review (three fix builders), final Android build.
Honest limit stays: phone GPU budget and CC0/own-made art mean "PS5 level" is a direction, not a result; each wave is judged by frames against docs/owner_shots.
