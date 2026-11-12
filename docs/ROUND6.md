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

## Sprint (waves 111-120, script round6_111.js), highest effort, every wave: 2-3 builders, integrator (full suite, perf gate, visual QA), CI watcher
111 Cars v2 (Blender-generated high-detail car set, glass/lights/interiors/paint/damage) + vehicle-vs-vehicle collision, traffic spacing, many cars outside the city.
112 Landscape (trees, forests, waterfalls, rivers, shores, rocks, grass) + outskirts settlements (houses, villages, farms, stations) and a bigger map.
113 Weapons (many more, real in-hand models, animations, effects, auto-rendered pictures) + damage everywhere (enemies, cars, buildings, props, ground).
114 Hero QUANTUM SNAKES traversal (swing, pull, zip, fly) + snake bombs + hero look and enemy look overhaul. Android build for the owner after this wave.
115 Vertical buildings (stairs, lifts, rooftops, sniper) + interiors much better (outside matches inside).
116 Casual play + hero mode (unlock everything) + blast table, plus world life density (people, cars, animals, enemies find you).
117 Human + creature animation overhaul.
118 Machine animation and vehicle FX + street and building detail + menus/weapon screens polish. Android build.
119 Director review 7 (independent, harsh).
120 Fixes from the review, final Android build.
Honest limit stays: phone GPU budget and CC0/own-made art mean "PS5 level" is a direction, not a result; each wave is judged by frames against docs/owner_shots.
