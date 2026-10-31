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

var _pool := {}                      ## kind -> Array[Vehicle] (inactive)
var _stream_t := 0.0
var _clock := 0.0
var _respawns: Array[Dictionary] = []  ## {t: due time, starter: bool, pos: where it stood, h: heading}
var _wrecks: Array[Dictionary] = []    ## {car: Vehicle, t: clock when the husk is cleared}: exploded cars standing as dark husks until their replacement is due
var _ram_cd := {}                    ## enemy instance id -> clock when it can be hit again
var _ram_t := 0.0


func _ready() -> void:
	Game.vehicles = self
	DynamicFill.ensure_light(self)
	DynamicFill.set_quality(Game.quality)
	Game.new_game.connect(_reset_all)
	Game.respawn.connect(_reset_all)
	Game.next_sector.connect(_reset_all)
	Game.quality_changed.connect(_on_quality)
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
	var car := nearest(p.global_position)
	if car == null:
		return false
	enter(car)
	return true


## The player takes the wheel. Taking a traffic car is a carjacking (heat +0.2).
func enter(car: Vehicle) -> void:
	var p := Game.player
	if not is_instance_valid(p) or car == null or car.dead or not car.active:
		return
	if car.ai:
		car.ai = false
		Game.add_heat(VehicleSpecs.CARJACK_HEAT)
		Game.say("VEHICLE COMMANDEERED", 1.4)
	car.driver_is_player = true
	driven = car
	p.set(&"vehicle", car)
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
	car.driver_is_player = false
	car.steer_in = 0.0
	car.braking = false
	if is_instance_valid(p):
		var pos := _exit_point(car)
		p.call(&"teleport_to", pos)
		p.set(&"vehicle", null)


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
	_respawns.clear()
	_ram_cd.clear()
	_clock = 0.0
	_stream_t = 0.0
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


# --- simulation -----------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not Game.is_playing():
		return
	_clock += delta
	if Input.is_action_just_pressed(&"interact"):
		toggle_enter_exit()
	_sync_driver()
	var i := 0
	while i < list.size():
		var v := list[i]
		v.sim(delta)
		if i < list.size() and list[i] == v:
			i += 1
	if driven != null:
		_bump_others(driven)
		_ram_t -= delta
		if _ram_t <= 0.0:
			_ram_t = 0.05
			_ram(driven)
	_sanity()
	_stream_t -= delta
	if _stream_t <= 0.0:
		_stream_t = stream_every
		_stream()
		_tick_wrecks(_player_pos(), true)
	_tick_wrecks(Vector3.INF, false)
	_tick_respawns()


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


## The driven car shoves the cars it touches (src/vehicles.js): positions pushed apart, the other car loses its AI and slides away, hard hits hurt both.
func _bump_others(car: Vehicle) -> void:
	var cp := car.global_position
	for o in list:
		if o == car or o.dead or not o.active:
			continue
		var op := o.global_position
		var dx := cp.x - op.x
		var dz := cp.z - op.z
		var d := sqrt(dx * dx + dz * dz)
		if d >= VehicleSpecs.CAR_SEPARATION or d <= 1e-3:
			continue
		var n := Vector3(dx / d, 0.0, dz / d)
		var imp := absf((car.vel.x - o.vel.x) * n.x + (car.vel.z - o.vel.z) * n.z)
		var push := VehicleSpecs.CAR_SEPARATION - d
		car.global_position += n * push * 0.6
		o.global_position -= n * push * 0.4
		car.vel *= 0.8
		o.vel = -n * imp * 0.8
		o.ai = false
		if imp > VehicleSpecs.CAR_HIT_SPEED:
			car.hits += 1
			car.damage(imp * 1.2)
			o.damage(imp * 2.0)
			FX.shake(0.4)
			Sfx.play_at(&"hit", op, -3.0)
		cp = car.global_position


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
		if v != starter and not v.driver_is_player and not v.has_meta(&"hold") and _dist(v, ppos) > VehicleSpecs.DESPAWN_RADIUS:
			_release(v)
		i -= 1
	_trim_to_cap()
	_lod_pass(ppos)
	if list.size() < cap():
		var parked_now := parked_count()
		var total := parked_now + traffic_count()
		_spawn_streamed(float(parked_now) < VehicleSpecs.PARKED_SHARE * float(total + 1))


func _trim_to_cap() -> void:
	var ppos := _player_pos()
	while list.size() > cap():
		var far: Vehicle = null
		var far_d := -1.0
		for v in list:
			if v == starter or v.driver_is_player or v.has_meta(&"hold"):       # a mission's target car (Contracts) is never recycled
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
	if Game.enemies == null and is_instance_valid(Game.camera):
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
func _find_spot(center: Vector3, parked: bool) -> Array:
	var w := Game.world
	if not is_instance_valid(w) or not w.has_method(&"road_point_near"):
		return []
	for attempt in 6:
		var pt: Vector3 = w.call(&"road_point_near", center, VehicleSpecs.SPAWN_MIN, VehicleSpecs.SPAWN_MAX)
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
	var best := base + r * 2.8
	for off: Vector3 in [r * 2.8, -r * 2.8, -f * 3.6, f * 3.6]:
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
		"driven": driven != null, "respawns": _respawns.size()}
