class_name FreedomData
extends RefCounted
## Plain data of the open-world freedom layer (scripts/freedom/): where the jobs and stunt ramps stand, what they pay, how long they last. Nothing here touches the scene tree.
## Junction coordinates (gi, gj) are 1..N-1 of the road grid (CityLayout.road_center), the core of the city is 5..11; every spot is on a junction or on the road between two of them,
## so nothing ever stands inside a building. Markers sit in the junction corner of their kind (CORNER), ramps on the road centre line between lanes.

const RACE := &"race"
const TAXI := &"taxi"
const DELIVERY := &"delivery"
const BOUNTY := &"bounty"
const STUNT := &"stunt"
const KINDS: Array[StringName] = [RACE, TAXI, DELIVERY, BOUNTY]
const NAMES := {RACE: "STREET RACE", TAXI: "TAXI FARE", DELIVERY: "DELIVERY", BOUNTY: "BOUNTY", STUNT: "STUNT JUMP"}
const COLORS := {
	RACE: Color(1.0, 0.3, 0.85), TAXI: Color(1.0, 0.78, 0.2), DELIVERY: Color(0.45, 1.0, 0.5), BOUNTY: Color(1.0, 0.3, 0.3), STUNT: Color(0.3, 0.9, 1.0),
}
## Corner of the junction a kind's marker stands in (x, z metres from the junction centre; the junction is 20 m wide).
const CORNER := {RACE: Vector2(7.0, 7.0), TAXI: Vector2(-7.0, 7.0), DELIVERY: Vector2(7.0, -7.0), BOUNTY: Vector2(-7.0, -7.0)}

## Junction coordinates of every marker (6 per kind; at least two in the core, the rest in the outer districts).
const SPOTS := {
	RACE: [Vector2i(5, 5), Vector2i(9, 9), Vector2i(3, 12), Vector2i(12, 3), Vector2i(7, 13), Vector2i(13, 7)],
	TAXI: [Vector2i(6, 6), Vector2i(10, 6), Vector2i(4, 10), Vector2i(12, 10), Vector2i(8, 2), Vector2i(2, 8)],
	DELIVERY: [Vector2i(6, 10), Vector2i(10, 10), Vector2i(8, 12), Vector2i(14, 8), Vector2i(8, 4), Vector2i(4, 4)],
	BOUNTY: [Vector2i(7, 7), Vector2i(11, 5), Vector2i(5, 11), Vector2i(13, 13), Vector2i(3, 3), Vector2i(14, 2)],
}
## Stunt ramps: junction the ramp leaves from, direction on the road (+x +z -x -z as 0..3). Ramp at 24 m from that junction centre, landing zone 32 m beyond the ramp end.
const RAMPS: Array[Array] = [
	[Vector2i(5, 7), 0], [Vector2i(11, 8), 2], [Vector2i(7, 5), 1], [Vector2i(8, 11), 3], [Vector2i(3, 6), 0], [Vector2i(13, 10), 3],
]
const DIRS: Array[Vector2] = [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]

# --- markers and jobs ---
const ENTRY_RADIUS := 4.5
const ENTRY_SPEED := 10.0           ## m/s: slow down to start a job (a car just passing does not start one)
const DWELL := 0.5                  ## s on the marker before the job starts
const GATE_RADIUS := 11.0
const ARRIVE_RADIUS := 8.0
const ARRIVE_SPEED := 13.0          ## m/s: a taxi fare ends with the car nearly stopped
const COOLDOWN := 6.0               ## s after a job before the next may start
const LEAVE_GRACE := 8.0            ## s a driving job (race, taxi) waits for the hero to be back in a vehicle before it fails
const BOUNTY_MIN := 55.0            ## the bounty target stands this far (min..max) from the marker
const BOUNTY_MAX := 100.0
const BOUNTY_HP := 3.0              ## target health multiplier
const BOUNTY_TIME := 150.0

const RACE_BASE := 180
const RACE_PAR_PER_GATE := 17.0     ## s of par time per gate (4 gates + the finish)
const RACE_BONUS := 6               ## credits per second under par
const TAXI_BASE := 80
const TAXI_PER_100M := 26
const TAXI_SPEED := 9.0             ## m/s assumed for the time limit
const TAXI_BONUS := 5               ## credits per second left
const DELIVERY_BASE := 120
const DELIVERY_PER_100M := 38
const DELIVERY_SPEED := 7.0         ## m/s on foot is faster than that only with sprint: vehicles make it easy
const BOUNTY_PAY := 320
const STUNT_PAY := 140              ## first time
const STUNT_REPEAT := 35

# --- stunt ramps ---
const RAMP_LEN := 8.0
const RAMP_WID := 6.0
const RAMP_H := 1.8
const RAMP_OFFSET := 24.0           ## from the junction centre
const STUNT_MIN_SPEED := 14.0       ## m/s: slower and the car only drives over it
const JUMP_DIST := 32.0             ## the car clears this many metres whatever its speed (time = dist / speed)
const JUMP_APEX := 5.0
const LAND_RADIUS := 17.0
const HERO_LAUNCH := 21.0           ## hero on foot: forward speed and lift at the ramp end
const HERO_LIFT := 13.0
const HERO_LAND_RADIUS := 20.0


static func junction(g: Vector2i) -> Vector3:
	return Vector3(CityLayout.road_center(g.x), 0.0, CityLayout.road_center(g.y))


## Marker position of job `k` of `kind` (ground).
static func marker_pos(kind: StringName, k: int) -> Vector3:
	var g: Vector2i = (SPOTS[kind] as Array)[k]
	var c: Vector2 = CORNER[kind]
	return junction(g) + Vector3(c.x, 0.0, c.y)


## The four gates of a street race that starts at spot k: a square loop of two blocks around the start junction, finishing where it started.
static func race_gates(k: int) -> Array[Vector3]:
	var g: Vector2i = (SPOTS[RACE] as Array)[k]
	var out: Array[Vector3] = []
	for d: Vector2i in [Vector2i(2, 0), Vector2i(2, 2), Vector2i(0, 2), Vector2i(0, 0)]:
		var q := Vector2i(clampi(g.x + d.x, 1, CityLayout.N - 1), clampi(g.y + d.y, 1, CityLayout.N - 1))
		out.append(junction(q))
	return out


## Where a taxi fare or a delivery from spot k goes: a junction 4..6 blocks away, deterministic, always inside the map.
static func destination(kind: StringName, k: int) -> Vector3:
	var g: Vector2i = (SPOTS[kind] as Array)[k]
	var n := CityLayout.N - 1
	var dx := 4 + (k % 3)
	var dz := 3 + ((k + 1) % 3)
	var sx := 1 if g.x + dx <= n else -1
	var sz := 1 if kind == TAXI else -1
	if g.y + sz * dz > n or g.y + sz * dz < 1:
		sz = -sz
	return junction(Vector2i(clampi(g.x + sx * dx, 1, n), clampi(g.y + sz * dz, 1, n)))


## Ramp i: {pos (low end on the road centre line), dir (unit xz), yaw, land (centre of the landing zone)}.
static func ramp(i: int) -> Dictionary:
	var r: Array = RAMPS[i]
	var d: Vector2 = DIRS[int(r[1])]
	var dir := Vector3(d.x, 0.0, d.y)
	var base := junction(r[0] as Vector2i) + dir * RAMP_OFFSET
	return {"pos": base, "dir": dir, "yaw": atan2(-dir.x, -dir.z), "land": base + dir * (RAMP_LEN + JUMP_DIST)}


static func reward_race(elapsed: float, gates: int) -> int:
	var par := RACE_PAR_PER_GATE * float(gates + 1)
	return RACE_BASE + int(maxf(par - elapsed, 0.0)) * RACE_BONUS


static func time_limit(kind: StringName, dist: float) -> float:
	match kind:
		TAXI:
			return 25.0 + dist / TAXI_SPEED
		DELIVERY:
			return 20.0 + dist / DELIVERY_SPEED
		RACE:
			return RACE_PAR_PER_GATE * 5.0 * 1.6
	return BOUNTY_TIME
