extends RefCounted
## Enterable doors of the city (interior gameplay, scripts/interiors_gameplay/). Pure data derived from the existing lots and building data, so nothing else moves:
## EVERY lot gets ONE door on a street-facing ground-floor wall (the same two faces the awnings and blade signs use, scripts/world/city_roofs.gd).
## A door is a Dictionary {id (lot index, also the interior seed), type (InteriorData.TYPES), name, wall: Vector3 (on the facade, y 0), pos: Vector3 (the sidewalk point in front,
## where the USE prompt shows), normal: Vector3 (outward), yaw (mesh yaw of the facade, Roofs.wall_point convention), face_yaw (rotation.y that looks away from the wall), width}.
## Deterministic (own hashes, never the layout's random stream), at least one door within SPAWN_NEAR of the spawn, and every interior type appears at least once.

const Roofs := preload("res://scripts/world/city_roofs.gd")
const Buildings := preload("res://scripts/world/city_buildings.gd")

const CHANCE := 1.0           ## RULE: every building (lot) has exactly one door; towers get a lobby
const TOWER_H := 45.0
const SPAWN_NEAR := 80.0
const FRONT := 1.3            ## metres in front of the facade (the sidewalk strip is 2 m wide)
const WIDTH := 2.4


static func compute(layout: CityLayout, buildings: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var chosen := {}
	for i in layout.lots.size():
		if Buildings.hash01(i, 21) < CHANCE:
			chosen[i] = true
	# a door near the spawn, so the first walk through the neon already shows one
	var near_ok := false
	var best := -1
	var best_d := INF
	for i in layout.lots.size():
		var lot: CityLayout.Lot = layout.lots[i]
		var d := Vector2(lot.cx, lot.cz).distance_to(Vector2(Game.SPAWN.x, Game.SPAWN.z))
		if chosen.has(i) and d < SPAWN_NEAR + 20.0:
			near_ok = true
		if d < best_d and lot.h >= 12.0:
			best_d = d
			best = i
	if not near_ok and best >= 0:
		chosen[best] = true
	var ids: Array = chosen.keys()
	ids.sort()
	for i: int in ids:
		out.append(_make(layout.lots[i], i))
	# every interior type appears: reassign doors deterministically for the missing ones
	var seen := {}
	for dd in out:
		seen[dd["type"]] = true
	var k := 1
	for t: StringName in InteriorData.TYPES:
		if not seen.has(t) and not out.is_empty():
			var idx := (k * 3) % out.size()
			k += 1
			out[idx]["type"] = t
			out[idx]["name"] = InteriorData.door_name(t, int(out[idx]["id"]))
	return out


static func _make(lot: CityLayout.Lot, i: int) -> Dictionary:
	var bx := -CityLayout.HALF + (lot.block_i + 0.5) * CityLayout.PITCH
	var bz := -CityLayout.HALF + (lot.block_j + 0.5) * CityLayout.PITCH
	var sx := 1 if lot.cx > bx else -1
	var sz := 1 if lot.cz > bz else -1
	var faces: Array[int] = [0 if sx > 0 else 1, 2 if sz > 0 else 3]
	var face := faces[0 if Buildings.hash01(i, 22) < 0.5 else 1]
	var fw := Roofs.wall_width(lot, face)
	var u := fw * (0.28 + 0.44 * Buildings.hash01(i, 23))
	var wp: Array = Roofs.wall_point(lot, face, u)
	var p2: Vector2 = wp[0]
	var yaw: float = float(wp[1])
	var n := Basis(Vector3.UP, yaw) * Vector3.BACK
	var wall := Vector3(lot.cx + p2.x, 0.0, lot.cz + p2.y)
	var r := Buildings.hash01(i, 24)
	var acc := 0.0
	var type: StringName = InteriorData.TYPES[0]
	for k in InteriorData.TYPES.size():
		acc += InteriorData.WEIGHTS[k]
		if r < acc:
			type = InteriorData.TYPES[k]
			break
	if lot.h >= TOWER_H:
		type = &"lobby"
	return {
		"id": i, "type": type, "name": InteriorData.door_name(type, i), "wall": wall, "pos": wall + n * FRONT, "normal": n, "yaw": yaw,
		"face_yaw": atan2(-n.x, -n.z), "width": WIDTH,
	}
