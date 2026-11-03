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
const NpcLife := preload("res://scripts/npc/npc_life.gd")

var traffic := Traffic.new()
var crowd := Crowd.new()
var sky := Patrol.new()
var npc := NpcLife.new()                 ## citizen schedules / reactions / barks on top of the crowd (scripts/npc)
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
	traffic.set_count(int(Traffic.COUNTS[quality] * density))
	crowd.set_tier(quality, density)
	sky.set_enabled(quality >= 1)


## Hour-of-day multiplier (DayNight): slightly fewer cars and people in the small hours, more at rush hour.
func set_density(f: float) -> void:
	density = f
	traffic.set_count(int(Traffic.COUNTS[quality] * f))
	crowd.set_tier(quality, f)


func reset() -> void:
	clock = 0.0
	traffic.set_time(0.0)
	crowd.reset()
	npc.reset()
	sky.reset()


func _process(delta: float) -> void:
	if not simulate or not Game.is_playing():
		sky.pause_siren()
		return
	delta = minf(delta, 0.1)
	clock += delta
	traffic.set_time(clock)
	var p := _center()
	if p != Vector3.INF:
		crowd.step(delta, p)
		npc.step(delta, p)
		sky.step(delta, p, traffic, clock, quality)
	_hook_player()


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
	}
