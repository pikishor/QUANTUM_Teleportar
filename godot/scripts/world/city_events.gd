extends Node
## City events (F7): dynamic world events near the player, spawned by a scheduler with cooldowns. Data-driven and draw-free: an event is a record
## (kind, position, time left, state) that the minimap reads through markers(); gameplay hooks call resolve() / the proximity rules below.
## Kinds: ambush (patrol convoy ambush), race (street race), rescue (civilian rescue), drop (black-market drop), rift (dimensional rift zone, low gravity).
## Simulation only while Game.is_playing(). Wiring (orchestrator): add as a child of the world, minimap iterates markers(), player gravity uses gravity_scale_at().

const Actors := preload("res://scripts/world/city_event_actors.gd")
signal spawned(e: Dictionary)
signal ended(e: Dictionary, success: bool)
static var current: Node          ## the live instance (player gravity and the minimap read it)
var spawn_actors := true          ## false: records only (headless unit test)

const KINDS: Array[StringName] = [&"ambush", &"race", &"rescue", &"drop", &"rift"]
const DEF := {
	&"ambush": {"ttl": 60.0, "credits": Economy.EVENT_REWARD[&"ambush"], "heat": 1.0, "radius": 18.0, "label": "CONVOY AMBUSH"},
	&"race": {"ttl": 75.0, "credits": Economy.EVENT_REWARD[&"race"], "heat": 0.5, "radius": 14.0, "label": "STREET RACE"},
	&"rescue": {"ttl": 50.0, "credits": Economy.EVENT_REWARD[&"rescue"], "heat": -0.5, "radius": 4.0, "label": "RESCUE"},
	&"drop": {"ttl": 45.0, "credits": Economy.EVENT_REWARD[&"drop"], "heat": 0.8, "radius": 4.0, "label": "BLACK MARKET DROP"},
	&"rift": {"ttl": 40.0, "credits": Economy.EVENT_REWARD[&"rift"], "heat": 0.0, "radius": 22.0, "label": "DIMENSIONAL RIFT"},
}
const MIN_DIST := 45.0
const MAX_DIST := 140.0
const MAX_ACTIVE := 2
const SPAWN_INTERVAL := 25.0        ## seconds between scheduler attempts
const KIND_COOLDOWN := 90.0         ## the same kind does not repeat inside this window
const RIFT_GRAVITY := 0.35

var events: Array[Dictionary] = []
var clock := 0.0
var next_spawn := 8.0
var completed := 0
var failed := 0
var _cool := {}                     ## kind -> clock when it may spawn again
var _next_id := 1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	current = self
	add_to_group(&"city_events")
	for sig: Signal in [Game.new_game, Game.respawn, Game.next_sector]:
		sig.connect(reset)


func reset() -> void:
	for e in events:
		Actors.finish(e, false)
	events.clear()
	_cool.clear()
	clock = 0.0
	next_spawn = 8.0


func _process(delta: float) -> void:
	var t0 := PerfTimers.start()
	_process_body(delta)
	PerfTimers.stop(PerfTimers.MISSIONS, t0)


func _process_body(delta: float) -> void:
	if not Game.is_playing():
		return
	tick(delta, Game.player.global_position if is_instance_valid(Game.player) else Vector3.INF)


## Advance by dt. player_pos == Vector3.INF means no player (nothing spawns, nothing completes).
func tick(dt: float, player_pos: Vector3) -> void:
	clock += dt
	for i in range(events.size() - 1, -1, -1):
		var e := events[i]
		e["ttl"] = float(e["ttl"]) - dt
		var inside := player_pos != Vector3.INF and _flat(player_pos, e["pos"]) <= float(DEF[e["kind"]]["radius"])
		var k: StringName = e["kind"]
		var st := Actors.step(e, dt, player_pos) if spawn_actors and player_pos != Vector3.INF else -1
		if st >= 0:
			resolve(int(e["id"]), st == 1)
		elif inside and (k == &"rescue" or k == &"drop"):
			resolve(int(e["id"]), true)
		elif float(e["ttl"]) <= 0.0:
			resolve(int(e["id"]), k == &"rift")     # a rift simply closes; the rest expire as failures
	if player_pos != Vector3.INF and clock >= next_spawn:
		next_spawn = clock + SPAWN_INTERVAL
		spawn_near(player_pos)


## Scheduler step: pick a kind that is off cooldown and place it MIN_DIST..MAX_DIST from the player. Returns the event or {}.
func spawn_near(player_pos: Vector3, kind: StringName = &"") -> Dictionary:
	if events.size() >= MAX_ACTIVE:
		return {}
	var pool: Array[StringName] = []
	for k in KINDS:
		if (kind == &"" or k == kind) and clock >= float(_cool.get(k, -1.0)) and not _active(k):
			pool.append(k)
	if pool.is_empty():
		return {}
	var k: StringName = pool[_rng.randi() % pool.size()]
	var ang := _rng.randf() * TAU
	var dist := _rng.randf_range(MIN_DIST, MAX_DIST)
	var pos := player_pos + Vector3(cos(ang), 0.0, sin(ang)) * dist
	var lim := float(Game.HALF) - 10.0
	pos.x = clampf(pos.x, -lim, lim)
	pos.z = clampf(pos.z, -lim, lim)
	pos.y = 0.0
	var axis := _rng.randi() % 2                     ## snap onto a street so the actors stand on asphalt (axis 0 = a road along X)
	var road := clampi(roundi(((pos.z if axis == 0 else pos.x) + Game.HALF) / CityLayout.PITCH), 0, CityLayout.N)
	var rc := clampf(CityLayout.road_center(road), -lim, lim)
	if axis == 0:
		pos.z = rc
	else:
		pos.x = rc
	var e := {"axis": axis, "road": road, "id": _next_id, "kind": k, "pos": pos, "ttl": float(DEF[k]["ttl"])}
	_next_id += 1
	_cool[k] = clock + KIND_COOLDOWN
	events.append(e)
	Game.say(String(DEF[k]["label"]))
	if spawn_actors:
		Actors.build(self, e)
	spawned.emit(e)
	return e


## End an event: success pays credits and applies heat, failure only counts. Returns false for an unknown id.
func resolve(id: int, success: bool) -> bool:
	for i in events.size():
		if int(events[i]["id"]) == id:
			var d: Dictionary = DEF[events[i]["kind"]]
			var ev := events[i]
			events.remove_at(i)
			Actors.finish(ev, success)
			ended.emit(ev, success)
			if success:
				completed += 1
				if is_instance_valid(Game.progress):
					Game.progress.add_credits(int(d["credits"]))
				if float(d["heat"]) != 0.0:
					Game.add_heat(float(d["heat"]))
			else:
				failed += 1
			return true
	return false


## Minimap markers: [{kind, pos, radius, ttl}] (no allocation beyond the small result array; at most MAX_ACTIVE entries).
func markers() -> Array:
	var out: Array = []
	for e in events:
		out.append({"kind": e["kind"], "pos": e["pos"], "radius": DEF[e["kind"]]["radius"], "ttl": e["ttl"]})
	return out


## Gravity multiplier at a world position: RIFT_GRAVITY inside an active rift, else 1.
func gravity_scale_at(p: Vector3) -> float:
	for e in events:
		if e["kind"] == &"rift" and _flat(p, e["pos"]) <= float(DEF[&"rift"]["radius"]):
			return RIFT_GRAVITY
	return 1.0


func _active(k: StringName) -> bool:
	for e in events:
		if e["kind"] == k:
			return true
	return false


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
