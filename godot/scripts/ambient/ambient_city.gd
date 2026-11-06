extends Node3D
## The living city: far traffic, a pedestrian crowd and overhead patrols on top of the static world. A child of City (city.gd builds it and fans the
## graphics tier out), it owns three cheap systems (see ambient_traffic.gd, ambient_crowd.gd, ambient_sky.gd) and the rules they share:
## - simulation only while Game.is_playing() (paused, dead, menu: everything stands still), an ambient clock that restarts on new game / respawn / next sector;
## - tiers (Game.quality through City.set_quality): far cars LOW 80 / MED 150 / HIGH 240 (cap 300), crowd LOW 24 (nobody beyond 40 m) / MED 40 / HIGH 90 (a near and a far MultiMesh, see ambient_crowd.gd),
##   no airship searchlight on LOW; the crowd reacts to the player's gunfire (`Player.fired`);
## - budget: traffic 1 draw (+1 mirrored copy on MED / HIGH), crowd 1 draw (+1 mirrored copy on HIGH only), searchlight 1 draw while a sweep is on;
##   all nodes and buffers are created once, nothing is allocated per frame.

const Traffic := preload("res://scripts/ambient/ambient_traffic.gd")
const Crowd := preload("res://scripts/ambient/ambient_crowd.gd")
const Patrol := preload("res://scripts/ambient/ambient_sky.gd")
const Fauna := preload("res://scripts/ambient/ambient_fauna.gd")
const NpcLife := preload("res://scripts/npc/npc_life.gd")
const CitizenActors := preload("res://scripts/npc/citizen_actors.gd")

var traffic := Traffic.new()
var crowd := Crowd.new()
var sky := Patrol.new()
var fauna := Fauna.new()                 ## flocks above the roofs and street crawlers: one MultiMesh, one draw (ambient_fauna.gd)
var npc := NpcLife.new()                 ## citizen schedules / reactions / barks on top of the crowd (scripts/npc)
var citizens := CitizenActors.new()      ## the nearest promoted citizens as real skinned humanoids (HumanoidVariants), the crowd skips them
var quality := 1
var density := 1.0
## The ambient clock in seconds of game time (drives the traffic shader).
var clock := 0.0
## Master switch (tests, photo mode): false freezes the clock and hides nothing.
var simulate := true

var _city: Node3D
var _hooked: Object = null


func setup(city: Node3D, light_map: Texture2D) -> void:
	name = "Ambient"
	_city = city
	traffic.build()
	crowd.build(light_map)
	sky.build(self)
	npc.setup(crowd)
	citizens.setup(crowd, npc)
	add_child(citizens)
	fauna.build()
	city.add_multimesh("AmbientFauna", fauna.mm, fauna.material, null, false, 0, 1)
	city.add_multimesh("AmbientTraffic", traffic.mm, traffic.material, traffic.mirror_material, false, 0, 1)
	city.add_multimesh("AmbientCrowd", crowd.mm, crowd.material, crowd.mirror_material, false, 0, 2)
	city.add_multimesh("AmbientCrowdNear", crowd.mm_near, crowd.material, crowd.mirror_material, false, 0, 2)
	Game.new_game.connect(reset)
	Game.respawn.connect(reset)
	Game.next_sector.connect(reset)
	set_quality(quality)


func _exit_tree() -> void:
	for sig: Signal in [Game.new_game, Game.respawn, Game.next_sector]:
		if sig.is_connected(reset):
			sig.disconnect(reset)


## 0 low, 1 medium, 2 high (called by City.set_quality).
func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)
	traffic.set_count(_traffic_n(density))
	crowd.set_tier(quality, density)
	sky.set_enabled(quality >= 1)
	fauna.set_tier(quality)
	citizens.set_tier(quality)


func _traffic_n(f: float) -> int:
	var n := int(Traffic.COUNTS[quality] * f)
	return LowPlus.scaled(n, LowPlus.TRAFFIC_SHARE, 20) if quality == 0 else n        # LOW+ draws less than half of LOW's far cars


## Hour-of-day multiplier (DayNight): slightly fewer cars and people in the small hours, more at rush hour.
func set_density(f: float) -> void:
	density = f
	traffic.set_count(_traffic_n(f))
	crowd.set_tier(quality, f)


func reset() -> void:
	clock = 0.0
	traffic.set_time(0.0)
	crowd.reset()
	citizens.reset()
	npc.reset()
	sky.reset()
	fauna.reset()


func _process(delta: float) -> void:
	if not simulate or not Game.is_playing():
		sky.pause_siren()
		return
	delta = minf(delta, 0.1)
	clock += delta
	traffic.set_time(clock)
	var p := _center()
	if p != Vector3.INF:
		var t0 := PerfTimers.start()
		crowd.step(delta, p)
		PerfTimers.stop(PerfTimers.CROWD, t0)
		t0 = PerfTimers.start()
		npc.step(delta, p)
		PerfTimers.stop(PerfTimers.NPC, t0)
		t0 = PerfTimers.start()
		citizens.step(delta, p)
		PerfTimers.stop(PerfTimers.CITIZENS, t0)
		t0 = PerfTimers.start()
		fauna.step(delta, p, _night())
		PerfTimers.stop(PerfTimers.FAUNA, t0)
		t0 = PerfTimers.start()
		sky.step(delta, p, traffic, clock, quality)
		PerfTimers.stop(PerfTimers.SKY, t0)
	_hook_player()


func _night() -> float:
	return clampf(DayNight.night_now, 0.0, 1.0)                 # not RenderingServer.global_shader_parameter_get: editor only, an error per call on a device


func _center() -> Vector3:
	if is_instance_valid(Game.player):
		return (Game.player as Node3D).global_position
	if is_instance_valid(Game.camera):
		return Game.camera.global_position
	return Vector3.INF


## Connect to the player's `fired` signal once per player instance (the crowd runs from gunfire).
func _hook_player() -> void:
	var pl := Game.player
	if pl == _hooked or not is_instance_valid(pl):
		return
	_hooked = pl
	if pl.has_signal(&"fired"):
		pl.connect(&"fired", _on_player_fired)


func _on_player_fired() -> void:
	if Game.is_playing() and is_instance_valid(Game.player):
		var pp := (Game.player as Node3D).global_position
		npc.on_shot(pp, pp)
		fauna.on_shot(pp)


## --- the people can be shot (crowd.gd has the bodies, npc_life.gd the consequences) ---------------------------------------------------------

## A ray against the people of the street: {i, t, head} or an empty dictionary (also when civilian casualties are off: shots pass through them).
func civilian_ray(origin: Vector3, dir: Vector3, max_t: float) -> Dictionary:
	if not Game.civilian_casualties or crowd.count == 0:
		return {}
	var r := crowd.ray(origin, dir, max_t)
	if r.x < 0.0:
		return {}
	return {"i": int(r.x), "t": r.y, "head": r.z > 0.5}


## The hero's shot hits person `i`. Returns true when it killed.
func hurt_civilian(i: int, amount: float, from: Vector3, head: bool) -> bool:
	var pos: Vector3 = crowd.person_position(i)
	var killed: bool = crowd.damage_person(i, amount * (2.0 if head else 1.0), from)
	if killed:
		npc.on_civilian_down(i, pos, true, &"gun")
	else:
		npc.on_civilian_hurt(i, pos, true)
	return killed


## A blast, a swing or a car hurts everybody within `r`; `by_player` = the hero's doing (heat, drops). Returns the killed.
func blast_civilians(pos: Vector3, r: float, by_player: bool, amount := 200.0, cause := &"blast") -> int:
	if not Game.civilian_casualties or crowd.count == 0:
		return 0
	var before := PackedInt32Array()
	for i in crowd.count:
		if crowd.is_alive(i) and Vector2(crowd.person_position(i).x - pos.x, crowd.person_position(i).z - pos.z).length() < r:
			before.append(i)
	var killed: int = crowd.damage_in_radius(pos, r, amount)
	for i in before:
		if crowd.is_dying(i):
			npc.on_civilian_down(i, crowd.person_position(i), by_player, cause)
	return killed


## Counts for tests and the budget report.
func stats() -> Dictionary:
	return {
		"traffic": traffic.count,
		"traffic_cap": Traffic.CAP,
		"crowd": crowd.count,
		"crowd_alive": crowd.alive_count(),
		"crowd_radius": crowd.radius,
		"sweeping": sky.active,
		"clock": clock,
		"npc": npc.stats(),
		"citizen_actors": citizens.active_count(),
		"fauna": fauna.count,
		"fauna_alive": fauna.alive_count(),
	}
