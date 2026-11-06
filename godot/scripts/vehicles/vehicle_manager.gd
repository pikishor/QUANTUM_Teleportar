class_name VehicleManager
extends Node
## Cars and traffic (Game.vehicles). Port of src/vehicles.js with the mobile budget rules of ARCHITECTURE.md ("Vehicles as implemented").
##
## Live cars (nodes) are capped per graphics tier, LOW 3 / MED 5 / HIGH 8, the starter car and a driven car included, and only cars within about 110 m of
## the player exist: every STREAM_EVERY seconds far cars go back to the pool and one new car is placed 40-105 m away (parked on a bay or driving in a
## right-hand lane) through Game.world.road_point_near. Cars are pooled per kind (no node creation while playing), the starter sport car near the spawn
## always exists. Detail by distance: wheels hidden beyond 50 m, MirrorProxy and shadows only for near cars.
## While playing the manager polls `interact` (the Player does not forward it) and calls toggle_enter_exit(); it also runs sim(dt) of every live car,
## the car-to-car bump and the running over of drones / operatives by the driven car. Lifecycle signals reset everything.
## API: list · nearest(pos, r = 4.2) · toggle_enter_exit() · enter(car) · exit_vehicle() · driven · starter · cap() · spawn_parked / spawn_traffic · stats().

var list: Array[Vehicle] = []        ## live cars (active, in play)
var driven: Vehicle                  ## the car the player drives, or null
var starter: Vehicle                 ## the starter sport car near the spawn (null while destroyed)
var respawn_time := VehicleSpecs.RESPAWN_TIME
var stream_every := VehicleSpecs.STREAM_EVERY   ## seconds between streaming passes (tests shorten it)

var radio: CarRadio                  ## the car radio (3 synthesised stations), a child node
var cops_spawned := 0                ## police interceptors sent after the hero so far (tests, stats)
var spikes: SpikeStrips              ## the spike strips the police lay at heat 3+
var _cop_t := 0.0
var _spike_t := 6.0
var patrols_spawned := 0             ## Vael patrol vehicles sent after the player so far (tests, stats)

var signal_clock := 0.0              ## s: the junction lights (VehicleSpecs.signal_state); tests may set it and freeze it
var signal_frozen := false
var lights_on := true                ## false: traffic ignores the junction lights (tests of plain lane driving)

var _patrol_t := 0.0
var _key_yaw := 0.0                  ## the cars' key light follows the camera yaw, smoothed
var _pool := {}                      ## kind -> Array[Vehicle] (inactive)
var _stream_t := 0.0
var _clock := 0.0
var _respawns: Array[Dictionary] = []  ## {t: due time, starter: bool, pos: where it stood, h: heading}
var _wrecks: Array[Dictionary] = []    ## {car: Vehicle, t: clock when the husk is cleared}: exploded cars standing as dark husks until their replacement is due
var _ram_cd := {}                    ## enemy instance id -> clock when it can be hit again
var _ram_t := 0.0


## Driving inputs the manager registers when missing (like the radio's): VIEW (B) cycles the driving camera, BACK (N, held) looks behind, HORN (H).
const EXTRA_ACTIONS := {&"veh_view": KEY_B, &"look_back": KEY_N, &"horn": KEY_H}


static func ensure_actions() -> void:
	for a: StringName in EXTRA_ACTIONS:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			var ev := InputEventKey.new()
			ev.physical_keycode = EXTRA_ACTIONS[a]
			InputMap.action_add_event(a, ev)


func _ready() -> void:
	ensure_actions()
	Game.vehicles = self
	DynamicFill.ensure_light(self)
	VehicleVisual.ensure_key_light(self)
	DynamicFill.set_quality(Game.quality)
	Game.new_game.connect(_reset_all)
	Game.respawn.connect(_reset_all)
	Game.next_sector.connect(_reset_all)
	Game.quality_changed.connect(_on_quality)
	spikes = SpikeStrips.new()
	spikes.name = "SpikeStrips"
	add_child(spikes)
	radio = CarRadio.new()
	radio.name = "Radio"
	add_child(radio)
	_spawn_starter()


func _exit_tree() -> void:
	if Game.vehicles == self:
		Game.vehicles = null


# --- API ----------------------------------------------------------------------------------------------------------------

func cap() -> int:
	return VehicleSpecs.cap_for(Game.quality)


## The nearest live car within `r` metres (horizontal), or null. The driven car counts.
func nearest(pos: Vector3, r := 4.2) -> Vehicle:
	var best: Vehicle = null
	var best_d := r
	for c in list:
		if c.dead or not c.active:
			continue
		var d := Vector2(c.global_position.x - pos.x, c.global_position.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = c
	return best


## The car the hero can take from `pos`: the nearest within the old 4.2 m (middle to middle) or whose hull edge is within VehicleSpecs.ENTER_REACH (a long bus or truck is
## taken at its flank), a moving car adds ENTER_MOVING per m/s so a hijack on the run works. Null when none.
func reach_car(pos: Vector3) -> Vehicle:
	var best: Vehicle = null
	var best_d := INF
	for c in list:
		if c.dead or not c.active or c.wreck:
			continue
		var flat := Vector2(c.global_position.x - pos.x, c.global_position.z - pos.z).length()
		var edge := c.edge_distance(pos)
		var reach := VehicleSpecs.ENTER_REACH + minf(absf(c.speed) * VehicleSpecs.ENTER_MOVING, VehicleSpecs.ENTER_MOVING_MAX)
		if edge <= reach or flat <= 4.2:
			var score := minf(edge, flat - 2.0)
			if score < best_d:
				best_d = score
				best = c
	return best


## Enter the nearest car within reach, or leave the one being driven. Called when `interact` is pressed. Returns true when something happened.
func toggle_enter_exit() -> bool:
	var p := Game.player
	if not is_instance_valid(p) or not Game.is_playing():
		return false
	if driven != null or p.get(&"vehicle") != null:
		exit_vehicle()
		return true
	if p.has_method(&"is_dead") and p.call(&"is_dead"):
		return false
	if p.global_position.y >= 2.0:
		return false
	var car := reach_car(p.global_position)
	if car == null:
		return false
	enter(car)
	return true


## The player takes the wheel. Taking a traffic car is a carjacking (heat +0.2).
func enter(car: Vehicle) -> void:
	var p := Game.player
	if not is_instance_valid(p) or car == null or car.dead or not car.active:
		return
	var had_driver := car.ai or car.chasing
	if had_driver:
		car.ai = false
		car.chasing = false
		Game.add_heat(VehicleSpecs.CARJACK_HEAT)
		Game.say("HIJACKED  " + Hijack.vehicle_name(car.kind), 1.4)
	if Hijack.current != null:                             # open world freedom: the entry ghost and the driver thrown out on the kerb side
		Hijack.current.on_enter(car, p.global_position, had_driver)
	car.driver_is_player = true
	driven = car
	p.set(&"vehicle", car)
	car.on_enter()
	Sfx.play(&"pickup")


## The player gets out beside the car (right side first, then left, behind, ahead; never inside a building) and the car rolls to a stop.
func exit_vehicle() -> void:
	var p := Game.player
	var car := driven
	if car == null and is_instance_valid(p):
		car = p.get(&"vehicle") as Vehicle
	if car == null:
		return
	driven = null
	var exit_speed := absf(car.speed)
	car.driver_is_player = false
	car.steer_in = 0.0
	car.braking = false
	car.on_exit()
	if is_instance_valid(p):
		var pos := _exit_point(car)
		p.call(&"teleport_to", pos)
		p.set(&"vehicle", null)
		if exit_speed > 4.0 and p is CharacterBody3D:                  # bailing out on the move: the hero keeps part of the car's speed (a roll off the car)
			(p as CharacterBody3D).velocity = car.forward() * signf(car.speed) * minf(exit_speed * 0.5, 9.0)
		if not car.dead and exit_speed > VehicleSpecs.EXIT_SAFE_SPEED and p.has_method(&"damage"):
			p.call(&"damage", (exit_speed - VehicleSpecs.EXIT_SAFE_SPEED) * VehicleSpecs.EXIT_HURT)      # bailing out of a fast car hurts


## A horn (`&"horn"`), gunshot (`&"gun"`) or crash (`&"crash"`) at `pos`: traffic reacts (Vehicle.hear). Returns how many cars reacted.
func hear(pos: Vector3, what: StringName) -> int:
	var n := 0
	for v in list:
		var before := v.reactions
		v.hear(pos, what)
		if v.reactions != before:
			n += 1
	return n


func spawn_parked(kind: StringName, pos: Vector3, heading: float) -> Vehicle:
	if list.size() >= cap():
		return null
	var v := _acquire(kind)
	v.activate(pos, heading)
	list.append(v)
	return v


## A traffic car on road `road_i` (0..N) along `axis` (0 = X, 1 = Z) heading `dir` (+1 / -1), at coordinate `along` of that road.
func spawn_traffic(kind: StringName, axis: int, road_i: int, dir: int, along: float) -> Vehicle:
	if list.size() >= cap():
		return null
	var line := VehicleSpecs.road_center(road_i) + VehicleSpecs.lane_offset(axis, dir, Game.LANE)
	var pos := Vector3(along, 0.0, line) if axis == 0 else Vector3(line, 0.0, along)
	var v := _acquire(kind)
	v.activate(pos, VehicleSpecs.heading_for(axis, dir))
	v.set_traffic(axis, dir, line, randf_range(VehicleSpecs.AI_CRUISE_MIN, VehicleSpecs.AI_CRUISE_MAX))
	list.append(v)
	return v


func traffic_count() -> int:
	var n := 0
	for v in list:
		if v.ai:
			n += 1
	return n


func parked_count() -> int:
	var n := 0
	for v in list:
		if not v.ai and not v.driver_is_player and v != starter:
			n += 1
	return n


func pending_respawns() -> int:
	return _respawns.size()


## Husks standing right now (exploded cars that have not been replaced yet).
func wreck_count() -> int:
	return _wrecks.size()


## Cars created so far (live and pooled), for the node-count tests.
func total_nodes() -> int:
	var n := list.size() + _wrecks.size()
	for k: StringName in _pool:
		n += (_pool[k] as Array).size()
	return n


# --- lifecycle ------------------------------------------------------------------------------------------------------------

func _reset_all() -> void:
	var p := Game.player
	if is_instance_valid(p) and p.get(&"vehicle") is Vehicle:
		p.set(&"vehicle", null)
	driven = null
	for v in list.duplicate():
		_release(v)
	_clear_wrecks()
	if spikes != null:
		spikes.clear()
	_cop_t = 0.0
	_spike_t = 6.0
	_respawns.clear()
	_ram_cd.clear()
	_clock = 0.0
	_summon_ready = 0.0
	_stream_t = 0.0
	_patrol_t = 0.0
	starter = null
	_spawn_starter()


func _on_quality(_level: int) -> void:
	DynamicFill.set_quality(Game.quality)
	_trim_to_cap()
	_lod_pass(_player_pos())


func _spawn_starter() -> void:
	var v := _acquire(&"sport")
	v.activate(VehicleSpecs.starter_pos(), VehicleSpecs.STARTER_HEADING)
	v.visual.set_paint(VehicleSpecs.COLORS[VehicleSpecs.STARTER_COLOR])
	v.paint_i = VehicleSpecs.STARTER_COLOR
	v.is_starter = true
	starter = v
	list.append(v)
	v.update_lod(0.0)


## A car that blew up: out of play at once, back as a parked car after `respawn_time` (the starter car back at its place).
func on_destroyed(v: Vehicle) -> void:
	var was_starter := v.is_starter
	var where := v.global_position
	var h := v.heading
	if v == driven:
		driven = null
	if v == starter:
		starter = null
	list.erase(v)
	v.is_starter = false
	v.become_wreck()
	hear(where, &"crash")
	_wrecks.append({"car": v, "t": _clock + respawn_time})
	while _wrecks.size() > VehicleSpecs.MAX_WRECKS:
		_release_wreck(0)
	_respawns.append({"t": _clock + respawn_time, "starter": was_starter, "pos": where, "h": h})


func _release_wreck(i: int) -> void:
	var v := _wrecks[i]["car"] as Vehicle
	_wrecks.remove_at(i)
	if is_instance_valid(v):
		_release(v)


func _clear_wrecks() -> void:
	while not _wrecks.is_empty():
		_release_wreck(_wrecks.size() - 1)


func _tick_wrecks(ppos: Vector3, far_only: bool) -> void:
	var i := _wrecks.size() - 1
	while i >= 0:
		var v := _wrecks[i]["car"] as Vehicle
		var gone := not is_instance_valid(v) or (not far_only and _clock >= float(_wrecks[i]["t"]))
		if not gone and far_only and ppos.is_finite() and _dist(v, ppos) > VehicleSpecs.DESPAWN_RADIUS:
			gone = true
		if gone:
			_release_wreck(i)
		i -= 1


## A car that left the map, or whose position broke (NaN), is put back inside the borders; the driven one keeps its camera and the player is never stranded.
func _sanity() -> void:
	var lim := Game.HALF + 30.0
	for v in list:
		var p := v.global_position
		if not p.is_finite():
			p = VehicleSpecs.starter_pos()
		if absf(p.x) > lim or absf(p.z) > lim or absf(p.y) > 5.0:
			p = Vector3(clampf(p.x, -lim + 5.0, lim - 5.0), 0.0, clampf(p.z, -lim + 5.0, lim - 5.0))
		else:
			continue
		v.global_position = p
		v.vel = Vector3.ZERO
		v.speed = 0.0


func _release(v: Vehicle) -> void:
	list.erase(v)
	v.deactivate()
	v.is_starter = false
	var arr: Array = _pool.get(v.kind, [])
	if not arr.has(v):
		arr.append(v)
	_pool[v.kind] = arr


## Pre-warm (ShaderWarmup, under the loading overlay): one parked car of every kind at `at` (loads the models and their textures, draws their materials once).
## Hand the returned cars back with warm_end().
func warm_begin(at: Vector3) -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	for k: StringName in [&"vael_patrol", &"hover", &"bike", &"sedan", &"suv"]:
		var v := spawn_parked(k, at, 0.0)
		if v != null:
			out.append(v)
	return out


func warm_end(cars: Array[Vehicle]) -> void:
	for v in cars:
		if is_instance_valid(v) and v != starter and not v.driver_is_player:
			_release(v)


func _acquire(kind: StringName) -> Vehicle:
	var arr: Array = _pool.get(kind, [])
	if not arr.is_empty():
		return arr.pop_back() as Vehicle
	if total_nodes() > VehicleSpecs.CAPS[2]:             # bound the node count: a car of another kind makes room
		for k: StringName in _pool:
			var other: Array = _pool[k]
			if not other.is_empty():
				(other.pop_back() as Vehicle).queue_free()
				break
	var v := Vehicle.new()
	add_child(v)
	v.setup(kind, self)
	return v


# --- garage (E3 / E6) ---------------------------------------------------------------------------------------------------

var _garage_local: Garage             ## used when there is no Progress node (tests)
var _summon_ready := 0.0              ## clock when CALL CAR works again
var _bike_ready := 0.0                ## clock when CALL CAR may bring a hover-bike again
const HOVERBIKE_COOLDOWN := 8.0


## The garage of the player's save (Progress), or a local one without it.
func get_garage() -> Garage:
	if Game.progress != null and Game.progress.get(&"garage") is Garage:
		return Game.progress.get(&"garage") as Garage
	if _garage_local == null:
		_garage_local = Garage.new()
	return _garage_local


## The live garage car, or null.
func garage_car() -> Vehicle:
	for v in list:
		if v.garage_car:
			return v
	return null


## Keeps the car being driven in the garage (the phone GARAGE button). Returns true when it was kept.
func save_driven() -> bool:
	var g := get_garage()
	if driven == null or not g.save_car(driven):
		return false
	var old := garage_car()
	if old != null and old != driven:
		_release(old)
	driven.apply_garage(g)                                # the saved car wears the garage tuning from now on
	Game.say("CAR SAVED TO GARAGE", 1.6)
	Cinematics.first_time(&"garage_reveal")
	return true


## Phone button CALL CAR: the garage car arrives beside the player. Only outdoors, on foot, while playing, and not more often than SUMMON_COOLDOWN.
## Returns the car, or null (a message says why).
func summon_garage() -> Vehicle:
	var p := Game.player
	var g := get_garage()
	if not is_instance_valid(p) or not Game.is_playing() or not g.has_car() or driven != null or p.get(&"vehicle") != null:
		return null
	if InteriorGameplay.active or p.global_position.y >= 2.0:
		Game.say("CALL CAR NEEDS OPEN STREET", 1.4)
		return null
	if _clock < _summon_ready:
		Game.say("GARAGE CAR RECHARGING", 1.2)
		return null
	var yaw := float(p.get(&"yaw")) if p.get(&"yaw") != null else 0.0
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var pos := p.global_position + fwd * 7.0
	if is_instance_valid(Game.world) and Game.world.has_method(&"is_inside_building") and Game.world.call(&"is_inside_building", Vector3(pos.x, 1.0, pos.z)):
		if Game.world.has_method(&"road_point_near"):
			pos = Game.world.call(&"road_point_near", p.global_position, 6.0, 30.0)
	var car := garage_car()
	if car == null:
		if list.size() >= cap():
			_release_farthest(p.global_position)
		car = _acquire(g.kind)
		car.activate(pos, yaw)
		car.apply_garage(g)
		list.append(car)
	else:
		car.global_position = Vector3(pos.x, 0.0, pos.z)
		car.rotation = Vector3(0.0, yaw, 0.0)
		car.heading = yaw
		car._heading_set = yaw
		car.vel = Vector3.ZERO
		car.speed = 0.0
		car.yaw_rate = 0.0
		car.repair()                                          # the garage sends it back in good shape
	car.update_lod(0.0)
	_summon_ready = _clock + Garage.SUMMON_COOLDOWN
	Game.say("GARAGE CAR INBOUND", 1.4)
	return car


## CALL CAR: the garage car when there is one, else a free quantum HOVER-BIKE (own cooldown). The hover-bike stays in the world until it is streamed away.
func summon_any() -> Vehicle:
	if get_garage().has_car():
		return summon_garage()
	return summon_hoverbike()


func summon_hoverbike() -> Vehicle:
	var p := Game.player
	if not is_instance_valid(p) or not Game.is_playing() or driven != null or p.get(&"vehicle") != null:
		return null
	if InteriorGameplay.active or p.global_position.y >= 2.0:
		Game.say("HOVER-BIKE NEEDS OPEN STREET", 1.4)
		return null
	if _clock < _bike_ready:
		Game.say("HOVER-BIKE RECHARGING", 1.2)
		return null
	var yaw := float(p.get(&"yaw")) if p.get(&"yaw") != null else 0.0
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var pos := p.global_position + fwd * 4.5
	if is_instance_valid(Game.world) and Game.world.has_method(&"is_inside_building") and Game.world.call(&"is_inside_building", Vector3(pos.x, 1.0, pos.z)):
		var alt: Variant = Game.world.call(&"road_point_near", p.global_position, 4.0, 30.0) if Game.world.has_method(&"road_point_near") else Vector3.INF
		if alt is Vector3 and alt != Vector3.INF:
			pos = alt
	var car: Vehicle = null
	for v in list:
		if v.kind == &"hoverbike" and not v.driver_is_player:
			car = v
			break
	if car == null:
		if list.size() >= cap():
			_release_farthest(p.global_position)
		car = _acquire(&"hoverbike")
		car.activate(Vector3(pos.x, 0.0, pos.z), yaw)
		list.append(car)
	else:
		car.global_position = Vector3(pos.x, 0.0, pos.z)
		car.rotation = Vector3(0.0, yaw, 0.0)
		car.heading = yaw
		car._heading_set = yaw
		car.vel = Vector3.ZERO
		car.speed = 0.0
		car.ai = false
	car.update_lod(0.0)
	FX.burst(Vector3(pos.x, 0.8, pos.z), Color(0.35, 0.95, 1.0), 14, 4.0, 0.5, 0.0)
	Sfx.play_at(&"blink", pos, -6.0)
	_bike_ready = _clock + HOVERBIKE_COOLDOWN
	Game.say("HOVER-BIKE INBOUND", 1.4)
	return car


func _release_farthest(from: Vector3) -> void:
	var far: Vehicle = null
	var best := -1.0
	for v in list:
		if v == driven or v.driver_is_player or v.garage_car:
			continue
		var d := _dist(v, from)
		if d > best:
			best = d
			far = v
	if far != null:
		_release(far)


# --- simulation -----------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var t0 := PerfTimers.start()
	_physics_process_body(delta)
	PerfTimers.stop(PerfTimers.VEHICLES, t0)


func _physics_process_body(delta: float) -> void:
	if not Game.is_playing():
		return
	_clock += delta
	if not signal_frozen:
		signal_clock += delta
	if Input.is_action_just_pressed(&"interact"):
		toggle_enter_exit()
	if radio != null:
		radio.poll_input()
	_sync_driver()
	if is_instance_valid(Game.camera):
		_key_yaw = lerp_angle(_key_yaw, Game.camera.global_rotation.y, 1.0 - exp(-3.0 * delta))
		VehicleVisual.aim_key(_key_yaw)
	var i := 0
	while i < list.size():
		var v := list[i]
		v.sim(delta)
		if i < list.size() and list[i] == v:
			i += 1
	if driven != null and not is_instance_valid(driven):
		driven = null
	_collide_all()                                          # a hard bump can wreck the driven car, and the wreck ejects the driver: `driven` is null again after this call
	if driven != null:
		_ram_t -= delta
		if _ram_t <= 0.0:
			_ram_t = 0.05
			if driven != null:                              # (found by the 20 minute soak: _ram(null) read `speed` of Nil)
				_ram(driven)
	_sanity()
	_stream_t -= delta
	if _stream_t <= 0.0:
		_stream_t = stream_every
		_stream()
		_tick_wrecks(_player_pos(), true)
	_tick_wrecks(Vector3.INF, false)
	_tick_respawns()
	_tick_patrols(delta)
	_tick_cops(delta)


## The player's own state is the truth: a car he sits in (set from outside too) is the driven one, and one he left is not.
func _sync_driver() -> void:
	var p := Game.player
	var pv: Object = p.get(&"vehicle") if is_instance_valid(p) else null
	if driven != null and pv != driven:
		driven.driver_is_player = false
		driven.steer_in = 0.0
		driven = null
	if driven == null and pv is Vehicle and (pv as Vehicle).active:
		var v := pv as Vehicle
		if v.ai:
			v.ai = false
			Game.add_heat(VehicleSpecs.CARJACK_HEAT)
		v.driver_is_player = true
		driven = v


## Hull-to-hull contacts between the live cars (oriented boxes of the real sizes, separating-axis test) wherever at least one car is not following its lane: the driven car, a knocked
## or parked car, a patrol. Rigid impulses with the masses and the points of contact (a hit off the centre line spins both cars), positions pushed apart, damage by the closing speed
## and the mass ratio (Vehicle.crash). Lane traffic keeps clear of each other by braking (Vehicle._blocked) and is not tested against itself.
func _collide_all() -> void:
	var ppos := _player_pos()
	var cars := list.duplicate()
	for i in cars.size():
		var a: Vehicle = cars[i]
		if not is_instance_valid(a) or a.dead or not a.active:
			continue
		if ppos.is_finite() and _dist(a, ppos) > 90.0 and not a.driver_is_player:
			continue
		for j in range(i + 1, cars.size()):
			var b: Vehicle = cars[j]
			if not is_instance_valid(b) or b.dead or not b.active or b.dead or a.dead or not a.active:
				continue
			if a.ai and b.ai and a.ai_panic <= 1.0 and b.ai_panic <= 1.0:        # lane traffic brakes for each other; cars in flight after gunfire really hit
				continue
			var reach := (float(a.spec["len"]) + float(b.spec["len"])) * 0.5 + 0.4
			var dx := a.global_position.x - b.global_position.x
			var dz := a.global_position.z - b.global_position.z
			if dx * dx + dz * dz > reach * reach:
				continue
			collide_cars(a, b)


## One pair: SAT on the four hull axes. Returns the closing speed (m/s) when the cars hit, 0 when they only touch or are apart.
func collide_cars(a: Vehicle, b: Vehicle) -> float:
	var pa := a.global_position
	var pb := b.global_position
	var axes: Array[Vector3] = [a.right(), a.forward(), b.right(), b.forward()]
	var ha := Vector2(float(a.spec["wid"]) * 0.5, float(a.spec["len"]) * 0.5)
	var hb := Vector2(float(b.spec["wid"]) * 0.5, float(b.spec["len"]) * 0.5)
	var best := INF
	var n := Vector3.ZERO
	var dvec := Vector3(pa.x - pb.x, 0.0, pa.z - pb.z)
	for ax in axes:
		var ra := absf(ha.x * ax.dot(a.right())) + absf(ha.y * ax.dot(a.forward()))
		var rb := absf(hb.x * ax.dot(b.right())) + absf(hb.y * ax.dot(b.forward()))
		var dist := dvec.dot(ax)
		var overlap := ra + rb - absf(dist)
		if overlap <= 0.0:
			return 0.0
		if overlap < best:
			best = overlap
			n = ax if dist >= 0.0 else -ax                       # from b towards a: pointing into a
	n.y = 0.0
	if n.length_squared() < 1e-6:
		return 0.0
	n = n.normalized()
	var p := _contact_point(a, b)
	var ma := VehicleSpecs.mass_of(a.kind)
	var mb := VehicleSpecs.mass_of(b.kind)
	a.global_position += n * (best * mb / (ma + mb) * 1.03)      # the lighter car is pushed out further
	b.global_position -= n * (best * ma / (ma + mb) * 1.03)
	var vrel := (a.point_velocity(p) - b.point_velocity(p)).dot(n)
	if vrel >= 0.0:
		return 0.0
	var inv := a.inverse_mass_at(n, p) + b.inverse_mass_at(-n, p)
	var j := -(1.0 + VehicleSpecs.RESTITUTION) * vrel / inv
	a.apply_impulse(n * j, p)
	b.apply_impulse(-n * j, p)
	if a.ai:
		a.ai = false
	if b.ai:
		b.ai = false
	var closing := -vrel
	if closing > VehicleSpecs.CAR_HIT_SPEED:
		hear(pb, &"crash")
		if a.driver_is_player or b.driver_is_player:
			FX.shake(clampf(closing / 22.0, 0.15, 0.9))
		FX.burst(Vector3(p.x, 0.7, p.z), Color(1.0, 0.75, 0.38), 6, 4.0, 0.3, 7.0, 0.3)
		Sfx.play_at(&"hit", p, -3.0)
		a.crash(closing, p, n, mb)
		b.crash(closing, p, -n, ma)
	return closing


## The point where two hulls meet: the middle of the two nearest points (each hull's box clamped to the other's centre).
func _contact_point(a: Vehicle, b: Vehicle) -> Vector3:
	var qa := _clamp_to_hull(a, b.global_position)
	var qb := _clamp_to_hull(b, a.global_position)
	return (qa + qb) * 0.5


static func _clamp_to_hull(c: Vehicle, pt: Vector3) -> Vector3:
	var d := pt - c.global_position
	var lx := clampf(d.dot(c.right()), -float(c.spec["wid"]) * 0.5, float(c.spec["wid"]) * 0.5)
	var lz := clampf(d.dot(c.forward()), -float(c.spec["len"]) * 0.5, float(c.spec["len"]) * 0.5)
	var q := c.global_position + c.right() * lx + c.forward() * lz
	return Vector3(q.x, 0.0, q.z)


## Running over drones and operatives: above 8 m/s everything within 2.4 m takes speed x 3.5 (a crit), once per 0.6 s per enemy.
func _ram(car: Vehicle) -> void:
	if absf(car.speed) <= VehicleSpecs.RAM_SPEED or car.dead:
		return
	var em := Game.enemies
	var cp := car.global_position
	if is_instance_valid(em) and em.get(&"list") != null:
		for e: Object in em.get(&"list"):
			_ram_one(car, cp, e)
	else:
		for e: Object in get_tree().get_nodes_in_group(&"enemy"):
			_ram_one(car, cp, e)


func _ram_one(car: Vehicle, cp: Vector3, e: Object) -> void:
	if not is_instance_valid(e) or not (e is Node3D):
		return
	var n := e as Node3D
	if n.get(&"dead") == true or n.get(&"active") == false:
		return
	var id := n.get_instance_id()
	if float(_ram_cd.get(id, -1.0)) > _clock:
		return
	var d := Vector2(n.global_position.x - cp.x, n.global_position.z - cp.z).length()
	if d >= VehicleSpecs.RAM_RADIUS:
		return
	_ram_cd[id] = _clock + VehicleSpecs.RAM_COOLDOWN
	n.call(&"damage", absf(car.speed) * VehicleSpecs.RAM_FACTOR, true)
	Game.add_heat(0.05)


func _tick_respawns() -> void:
	var i := _respawns.size() - 1
	while i >= 0:
		var r := _respawns[i]
		if _clock >= float(r["t"]):
			if bool(r["starter"]):
				if starter == null:
					_spawn_starter()
				_respawns.remove_at(i)
			elif list.size() >= cap():
				r["t"] = _clock + 2.0                           # no room: wait for a free slot
			else:
				var ppos := _player_pos()
				var spot: Vector3 = r["pos"]
				if _spawn_streamed(true) != null:
					_respawns.remove_at(i)
				elif not is_instance_valid(Game.world) and ppos.is_finite() and _spot_free(spot, 7.0) \
						and Vector2(spot.x - ppos.x, spot.z - ppos.z).length() > 25.0:
					spawn_parked(VehicleSpecs.pick_kind(randf()), spot, float(r["h"]))        # no world to stream from: back where it stood
					_respawns.remove_at(i)
				else:
					r["t"] = _clock + 2.0
		i -= 1


# --- streaming ------------------------------------------------------------------------------------------------------------

func _player_pos() -> Vector3:
	var p := Game.player
	return p.global_position if is_instance_valid(p) else Vector3.INF


## One pass: release far cars, trim to the tier cap, set the detail of the rest, then place at most one new car.
func _stream() -> void:
	var ppos := _player_pos()
	if not ppos.is_finite():
		return
	var i := list.size() - 1
	while i >= 0:
		var v := list[i]
		if v != starter and not v.driver_is_player and not v.has_meta(&"hold") and not (v.patrol and v.chasing) and _dist(v, ppos) > VehicleSpecs.DESPAWN_RADIUS:
			_release(v)
		i -= 1
	_trim_to_cap()
	_lod_pass(ppos)
	if list.size() < cap():
		var parked_now := parked_count()
		var total := parked_now + traffic_count()
		_spawn_streamed(float(parked_now) < VehicleSpecs.PARKED_SHARE * float(total + 1))


# --- Vael patrols ----------------------------------------------------------------------------------------------------------

func patrol_cap() -> int:
	return VehicleSpecs.PATROL_CAPS[clampi(Game.quality, 0, 2)]


func patrol_count(chasing_only := false) -> int:
	var n := 0
	for v in list:
		if v.patrol and not v.cop and not v.driver_is_player and (v.chasing or not chasing_only):
			n += 1
	return n


## From heat 3 Vael patrol vehicles (hover chassis, spec `vael_patrol`) are sent after the player: one per tier (two on HIGH), one new attempt every PATROL_EVERY seconds,
## 55-100 m away in a lane, using a free car slot or the slot of the farthest ordinary car. Below heat 2 they stand down and are released once 45 m away.
func _tick_patrols(delta: float) -> void:
	var ppos := _player_pos()
	if not ppos.is_finite():
		return
	if Game.heat < VehicleSpecs.PATROL_STAND_DOWN:
		for v in list.duplicate():
			if v.patrol and not v.cop and not v.driver_is_player:
				v.chasing = false
				if _dist(v, ppos) > 45.0:
					_release(v)
		return
	for v in list:
		if v.patrol and not v.cop and v.active and not v.dead and not v.driver_is_player and not v.chasing and not v.ai and Game.heat >= VehicleSpecs.PATROL_HEAT:
			v.chasing = true                                  # a standing-down patrol picks the chase up again
	if Game.heat < VehicleSpecs.PATROL_HEAT:
		return
	_patrol_t -= delta
	if _patrol_t > 0.0 or patrol_count(true) >= patrol_cap():
		return
	_patrol_t = VehicleSpecs.PATROL_EVERY
	spawn_patrol()


# --- police pursuit ladder ---------------------------------------------------------------------------------------------------

func cop_count(chasing_only := false) -> int:
	var n := 0
	for v in list:
		if v.cop and not v.driver_is_player and (v.chasing or not chasing_only):
			n += 1
	return n


## Interceptors wanted at a heat: 1 from COP_HEAT, 2 from heat 2, 3 from heat 4 (capped by the tier).
func cop_want(heat: float) -> int:
	if heat < VehicleSpecs.COP_HEAT:
		return 0
	return mini(1 + int(heat >= 2.0) + int(heat >= 4.0), VehicleSpecs.COP_CAPS[clampi(Game.quality, 0, 2)])


## The ladder: heat 0.5 an interceptor tails the hero (siren, no contact), 2 they ram, 3 they box him in / block and lay SPIKE STRIPS across the road ahead of a driving hero, 4+ more cars.
## Below COP_STAND_DOWN they stop chasing and are released once 45 m away. Interceptors are patrol-style chasers (patrol + cop) on pooled cars.
func _tick_cops(delta: float) -> void:
	var ppos := _player_pos()
	if not ppos.is_finite():
		return
	if Game.heat < VehicleSpecs.COP_STAND_DOWN:
		for v in list.duplicate():
			if v.cop and not v.driver_is_player:
				v.chasing = false
				if _dist(v, ppos) > 45.0:
					_release(v)
		return
	for v in list:
		if v.cop and v.active and not v.dead and not v.driver_is_player and not v.chasing:
			v.chasing = true
	if Game.heat < VehicleSpecs.COP_HEAT:
		return
	for v in list:
		if v.cop and v.chasing and Game.heat >= 3.0 and v.tactic == &"ram" and cops_spawned % 2 == 0:
			v.tactic = &"boxin"
	_cop_t -= delta
	if _cop_t <= 0.0 and cop_count(true) < cop_want(Game.heat):
		_cop_t = VehicleSpecs.COP_EVERY
		spawn_cop()
	if spikes != null and Game.heat >= VehicleSpecs.COP_SPIKE_HEAT and driven != null:
		_spike_t -= delta
		if _spike_t <= 0.0 and driven.speed > 8.0 and cop_count(true) > 0:
			_spike_t = VehicleSpecs.SPIKE_EVERY
			lay_spikes_ahead()


## One strip across the road `SPIKE_AHEAD` m ahead of the driven car's motion, on the nearest road line. Returns the bar or null.
func lay_spikes_ahead() -> Node3D:
	if spikes == null or driven == null:
		return null
	var f := driven.forward()
	f.y = 0.0
	var at := driven.global_position + f.normalized() * VehicleSpecs.SPIKE_AHEAD
	var axis := 0 if absf(f.x) > absf(f.z) else 1                      # travelling along x: the road centre line is z = road_center(...)
	if axis == 0:
		at.z = VehicleSpecs.road_center(VehicleSpecs.road_index(at.z))
	else:
		at.x = VehicleSpecs.road_center(VehicleSpecs.road_index(at.x))
	return spikes.lay(at, Vector3(f.x, 0.0, f.z).normalized())


## Place one chasing police interceptor on a road 50-95 m away (null when no spot or no slot).
func spawn_cop() -> Vehicle:
	var ppos := _player_pos()
	if not ppos.is_finite():
		return null
	var spot := _find_spot(ppos, false, VehicleSpecs.COP_MIN, VehicleSpecs.COP_MAX)
	if spot.is_empty():
		return null
	if list.size() >= cap() and not _free_slot():
		return null
	var v := _acquire(&"interceptor")
	v.activate(spot[0], spot[4])
	v.patrol = true
	v.cop = true
	v.chasing = true
	v.tactic = VehicleSpecs.TACTICS[cops_spawned % VehicleSpecs.TACTICS.size()] if Game.heat >= VehicleSpecs.COP_RAM_HEAT else &"ram"
	list.append(v)
	cops_spawned += 1
	v.update_lod(_dist(v, ppos))
	return v


## Place one chasing patrol vehicle (null when no free road spot or no slot could be made).
func spawn_patrol() -> Vehicle:
	var ppos := _player_pos()
	if not ppos.is_finite():
		return null
	var spot := _find_spot(ppos, false, VehicleSpecs.PATROL_MIN, VehicleSpecs.PATROL_MAX)
	if spot.is_empty():
		return null
	if list.size() >= cap() and not _free_slot():
		return null
	var v := _acquire(&"vael_patrol")
	v.activate(spot[0], spot[4])
	v.chasing = true
	v.tactic = VehicleSpecs.TACTICS[patrols_spawned % VehicleSpecs.TACTICS.size()]
	list.append(v)
	patrols_spawned += 1
	v.update_lod(_dist(v, ppos))
	return v


## Make room for one car: the farthest car that is not the starter, driven, held by a mission or a patrol goes back to the pool.
func _free_slot() -> bool:
	var ppos := _player_pos()
	var far: Vehicle = null
	var far_d := -1.0
	for v in list:
		if v == starter or v.driver_is_player or v.patrol or v.has_meta(&"hold"):
			continue
		var d := _dist(v, ppos) if ppos.is_finite() else 0.0
		if d > far_d:
			far_d = d
			far = v
	if far == null:
		return false
	_release(far)
	return true


func _trim_to_cap() -> void:
	var ppos := _player_pos()
	while list.size() > cap():
		var far: Vehicle = null
		var far_d := -1.0
		for v in list:
			if v == starter or v.driver_is_player or v.has_meta(&"hold") or (v.patrol and v.chasing):       # a mission's target car (Contracts) is never recycled, nor a chasing patrol
				continue
			var d := _dist(v, ppos) if ppos.is_finite() else 0.0
			if d > far_d:
				far_d = d
				far = v
		if far == null:
			break
		_release(far)


func _lod_pass(ppos: Vector3) -> void:
	if not ppos.is_finite():
		return
	for v in list:
		v.update_lod(_dist(v, ppos))
	if is_instance_valid(Game.camera):
		VehicleVisual.aim_key(Game.camera.global_rotation.y)
		if Game.enemies == null:
			DynamicFill.aim_light(Game.camera.global_rotation.y)


static func _dist(v: Node3D, pos: Vector3) -> float:
	return Vector2(v.global_position.x - pos.x, v.global_position.z - pos.z).length()


## Place a new car 40-105 m from the player: parked on a bay beside a road, or driving in a lane. Returns null when no free spot was found.
func _spawn_streamed(parked: bool) -> Vehicle:
	var ppos := _player_pos()
	if not ppos.is_finite():
		return null
	var spot := _find_spot(ppos, parked)
	if spot.is_empty():
		return null
	var v := _acquire(VehicleSpecs.pick_kind(randf()))
	v.activate(spot[0], spot[4])
	if not parked:
		v.set_traffic(spot[1], spot[2], spot[3], randf_range(VehicleSpecs.AI_CRUISE_MIN, VehicleSpecs.AI_CRUISE_MAX))
	list.append(v)
	v.update_lod(_dist(v, ppos))
	return v


## [position, axis, dir, lane line, heading] of a free spot, or [].
func _find_spot(center: Vector3, parked: bool, rmin := VehicleSpecs.SPAWN_MIN, rmax := VehicleSpecs.SPAWN_MAX) -> Array:
	var w := Game.world
	if not is_instance_valid(w) or not w.has_method(&"road_point_near"):
		return []
	for attempt in 6:
		var pt: Vector3 = w.call(&"road_point_near", center, rmin, rmax)
		if not pt.is_finite():
			continue
		var ix := VehicleSpecs.road_index(pt.x)
		var iz := VehicleSpecs.road_index(pt.z)
		var offx := pt.x - VehicleSpecs.road_center(ix)
		var offz := pt.z - VehicleSpecs.road_center(iz)
		var axis := 0 if absf(offz) <= absf(offx) else 1      # axis 0: the road runs along X, its centre line is z = road_center(iz)
		var c := VehicleSpecs.road_center(iz if axis == 0 else ix)
		var u := pt.x if axis == 0 else pt.z
		if absf(u) > Game.HALF - 30.0:
			continue
		var dir := 1 if randf() < 0.5 else -1
		var across: float
		if parked:
			if absf(u - VehicleSpecs.road_center(VehicleSpecs.road_index(u))) < Game.ROAD * 0.5 + 5.0:
				continue                                        # not on a junction
			across = c + VehicleSpecs.lane_offset(axis, dir, VehicleSpecs.BAY)
		else:
			across = c + VehicleSpecs.lane_offset(axis, dir, Game.LANE)
		var pos := Vector3(u, 0.0, across) if axis == 0 else Vector3(across, 0.0, u)
		if Vector2(pos.x - center.x, pos.z - center.z).length() < 30.0:
			continue
		if not _spot_free(pos, 7.0 if parked else 10.0):
			continue
		return [pos, axis, dir, across, VehicleSpecs.heading_for(axis, dir)]
	return []


func _spot_free(pos: Vector3, d: float) -> bool:
	for v in list:
		if Vector2(v.global_position.x - pos.x, v.global_position.z - pos.z).length() < d:
			return false
	return true


## Where the player stands after getting out: the first free side of the car (right, left, behind, ahead).
func _exit_point(car: Vehicle) -> Vector3:
	var base := car.global_position
	var r := car.right()
	var f := car.forward()
	var w := Game.world
	var side := 1.5 if car.cls == &"bike" else (2.6 if car.cls == &"hover" else 2.8)      # a bike has no doors: step off right beside it
	var best := base + r * side
	for off: Vector3 in [r * side, -r * side, -f * 3.6, f * 3.6]:
		var p := base + off
		if absf(p.x) > Game.HALF + 25.0 or absf(p.z) > Game.HALF + 25.0:
			continue
		if is_instance_valid(w) and w.has_method(&"is_inside_building") and w.call(&"is_inside_building", Vector3(p.x, 1.0, p.z)):
			continue
		best = p
		break
	return Vector3(best.x, 0.1, best.z)


func stats() -> Dictionary:
	return {"live": list.size(), "traffic": traffic_count(), "parked": parked_count(), "pooled": total_nodes() - list.size(), "cap": cap(),
		"driven": driven != null, "respawns": _respawns.size(), "patrols": patrol_count(), "chasing": patrol_count(true), "radio": radio.station if radio != null and radio.on else -1}
