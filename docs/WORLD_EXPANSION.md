# World expansion plan (owner request 2026-11-08, build 231b34d feedback, rating 3.5/10 "better than before, lots of work")

Owner wants: a huge world: mountains outside the city, ocean, rivers, bridges; airport with planes and helicopters (flyable), things in the
mountains too; more aliens and better enemies; more destructive weapons including Halo-style energy weapons (generic names, original designs);
a much better, more detailed UI for menus, options and weapon sections; better story plus free roam; animals in mountains and outskirts;
more detailed cars, streets, houses and buildings.

## Phone feasibility rules (non-negotiable)
Terrain = heightmap chunks streamed around the player with 3 LODs, fog and far impostors; ocean = one shader plane; rivers = flow-shader strips;
vegetation and rocks = MultiMesh by distance; animals = pooled instanced critters near the player; LOW/MED/HIGH tiers scale distance and density.
Perf gate and texture limits still apply (LOW 200 / MED 260 / HIGH 360 MB). World scale target: 4-6 km square, city 1 km inside.

## Sprint order
104 terrain, biomes, ocean, rivers, roads to outskirts | 105 bridges, harbour, boats, mountain sites, vegetation | 106 airport, planes, helicopters,
air traffic and flight controls | 107 animals and alien wildlife by biome | 108 energy weapons set, destructive weapons, enemy roster expansion
| 109 UI overhaul for menus, options, weapon sections | 110 story acts and free-roam content | 111 car, street and building detail pass | 112 director review + fixes.

## Art sources
CC0: Quaternius (Ultimate Animals, nature, vehicles, aircraft packs when available), OpenGameArt, ambientCG/Poly Haven (terrain textures, HDRIs).
Higher-detail cars/buildings may need Sketchfab (CC0/CC-BY with attribution; needs an API token from the owner) or purchased packs.
