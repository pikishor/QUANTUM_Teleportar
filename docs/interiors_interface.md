# Interiors interface (contract between the generator and the gameplay layer)

Two owners, one seam. **Generator** = `godot/scripts/interiors/**` (rooms, props, lights, colliders, minimap rects, anchors).
**Gameplay** = `godot/scripts/interiors_gameplay/**` (doors in the city, enter/exit, fades, vendors, actors, missions, radio, minimap hook, save, tests).
The gameplay layer never reaches into generator internals: it only uses what is written here. It runs today against its own stub
(`interiors_gameplay/interior_stub.gd`, a plain box room that implements this interface), so neither side blocks the other.

## Where interiors live
One interior exists at a time, built at **street level in the strip east of the city grid**, where no building lot, prop or road collider exists.
`origin` = the **centre of the floor** of the build volume; gameplay passes `Vector3(327.5, 0.0, 0.0)` (`InteriorGameplay.ORIGIN`). The build volume is
**x in [origin.x - 17, origin.x + 17] = [310.5, 344.5], z in [-20, 20], y in [0, 12]**: stay inside it (enemies clamp at |x| = 345, the player rescue at 351).
The floor top surface is exactly `origin.y` (= 0). While an interior is active gameplay hides the city (`Game.world.visible = false`, so the ground, sky props, traffic and
the wet-street mirror cost nothing), freezes and hides the cars, and removes the rain; it restores all of it on exit. Footprints are therefore 34 m x 40 m at most
(a shop is typically 14 x 12, a club 30 x 26), ceiling 3.0-4.5 m (a club hall may be 6 m).

## Entry point (generator provides)
`res://scripts/interiors/interior_gen.gd` with `class_name InteriorGen`:

```gdscript
const TYPES: Array[StringName] = [&"weapons", &"clinic", &"tech", &"bar", &"club", &"lobby", &"apartment", &"checkpoint"]
static func build(type: StringName, seed: int, origin: Vector3, quality: int) -> Node3D   # returns an Interior (below), NOT yet in the tree
```
Gameplay calls `add_child(interior)` itself and `queue_free()`s it on exit (free must release everything: no leaked lights, textures,
physics bodies, global state). Same `(type, seed)` must give the identical room (the door id is the seed, so the player always meets the same shop).

## The Interior node (class_name `Interior`, extends Node3D, generator provides)
Properties (set in `_init`/`build`, read-only for gameplay):

| name | type | meaning |
|---|---|---|
| `type` | StringName | one of TYPES |
| `seed` | int | build seed |
| `bounds` | Rect2 | world x/z rectangle of the whole interior (walls included) |
| `door_pos` | Vector3 | world floor point just inside the door where the player arrives (>= 0.8 m from any wall) |
| `door_yaw` | float | `rotation.y` the player faces on arrival (into the room; forward is -Z) |
| `exit_pos` | Vector3 | world floor point of the door threshold: pressing USE within 2.2 m leaves; within 2.5 m of `door_pos` |
| `floor_rects` | Array[Rect2] | world x/z rects of walkable floor (rooms, corridors), for the minimap |
| `wall_rects` | Array[Rect2] | world x/z rects of walls and big furniture (solid), for the minimap AND enemy movement: enemies cannot step into one (`City.is_inside_building` consults it while an interior is active), so doorways must NOT be covered by any wall rect and every wall rect should be as tight as the collider |

Methods:
- `anchors(kind: StringName) -> Array` of `Dictionary {pos: Vector3, yaw: float}` (world floor points; yaw = facing, `rotation.y`). Empty array when absent.
- `set_quality(level: int)` (0 low, 1 med, 2 high): scale lights/props; safe to call any time.
- optional `wall_segments() -> PackedVector2Array` pairs (a, b) of world x/z for a line-drawn minimap; gameplay falls back to `wall_rects`.

### Anchor kinds (minimum counts the generator guarantees per type)
| kind | meaning | guaranteed in |
|---|---|---|
| `vendor` | where the vendor NPC stands; a counter/barrier stands between it and `door_pos` side; player interacts within 3.2 m | weapons, clinic, tech, bar (>=1) |
| `civilian` | standing/sitting/wandering spots for 3-5 civilians | all except checkpoint (>=4) |
| `guard` | Vael patrol / guard spots (also patrol waypoints) | lobby, checkpoint, club, apartment, tech (>=4) |
| `safe` | a wall/floor safe (interaction point); gameplay adds the glowing marker | lobby, apartment (>=1) |
| `hostage` | where a captive kneels | apartment (>=1) |
| `terminal` | a console to hack (gameplay adds the marker) | checkpoint, tech (>=1) |
| `officer` | a hidden Vael officer's spot (VIP booth, back room) | club (>=1) |
| `cover` | low-cover points for fights | any (optional) |
The generator may add more kinds (gameplay ignores unknown ones). When a kind is missing gameplay falls back to points on `floor_rects`.

## Collision, layers, lights, budget
- Static colliders on physics layer 1 (`Game.L_WORLD`): floor, walls, ceiling, counters, furniture. Doorway >= 1.2 m wide, 2.2 m tall. Player cylinder 0.35 m.
- No `WorldEnvironment`, no `DirectionalLight3D`, no `Camera3D`, no audio. Lights are your own `OmniLight3D`/`SpotLight3D`, at most 6 shadowless omni lights on MED (3 on LOW).
- Total interior cost on MED: **<= 60 draw calls, <= 120k triangles** (the whole frame must stay <= 150 draws / 300k incl. HUD, player, <= 5 actors).
  Merge static props (MultiMesh/ArrayMesh), reuse materials. Interiors are lit by emissive trim and neon, not by the city moon.
- Layer 20 is the player; layer 1 is everything else for visuals. Do not use the `Mirror` node or `MirrorProxy` (there is no wet street inside).

## What gameplay does (so the generator can rely on it)
- Door markers, USE prompt, fades, teleport; hides the city and the cars, sets rain to 0 inside and restores all of it on exit. The street's enemies are stored and removed while inside.
- Spawns vendors, civilians, guards from anchors via the existing NPC and `Game.enemies.spawn` types; draws the minimap layout from `floor_rects`/`wall_rects`.
- Adds mission props at `safe`, `hostage`, `terminal`, `officer` anchors (a glowing marker disc + simple primitive meshes), never relies on generator props for them.
- Tests that touch the generator use `InteriorGen.build(type, seed, origin, quality)` only through this document.
