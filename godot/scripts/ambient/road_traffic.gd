class_name RoadTraffic
extends RefCounted
## Road traffic of the outskirts (owner round 6: "the long dark road is empty"): the cars of the highways and dirt tracks around the hero. They follow the real road polylines of TerrainRoads
## (RoadLanes: right-hand lane, the road's height and slope), brake for each other, for the hero's car and for the hero on foot with the same safe-distance rule as every other layer
## (TrafficField + TrafficBrain), react to gunfire, horns and crashes, and the hero can take any of them (`promote_near`: a real Vehicle that drives itself along the road with PathDriver).
## Drawing is two MultiMeshes and at most two draw calls, none while no road is near the hero: the cars within DRAW_R are small lit meshes (the same car as the near traffic: assets/shaders/prop_nearcar),
## the cars between that and the edge of the ring (150 / 200 / 250 m by tier) are paired head / tail lights (assets/shaders/prop_roadlamps). Nothing is allocated while playing.
## The density follows the road (a highway carries 1 car per 55 m per lane near the hero, a track 1 per 110 m), the tier, the hour (`density`) and what is already near; the kinds follow the road
## (commuters, trucks, vans and buses on highways, 4x4s and pickups on tracks, the odd taxi, patrol car or ambulance).

const SHADER_LAMPS := preload("res://assets/shaders/prop_roadlamps.gdshader")
const MB := preload("res://scripts/world/mesh_builder.gd")
const Traffic := preload("res://scripts/ambient/ambient_traffic.gd")

const CAP := 64                          ## cars simulated at once (the HIGH tier fills most of it on a busy highway)
const DRAWN := 36                        ## mesh cars the MultiMesh holds
const LAMPS := 80                        ## light pairs the lamp MultiMesh holds
const RADII: Array[float] = [150.0, 200.0, 250.0]
const TARGETS: Array[int] = [11, 18, 28]
const DRAW_R: Array[float] = [46.0, 52.0, 60.0]
const VIEW_COS := 0.12
const VIEW_NEAR := 14.0
const SPAWN_MIN_FRAC := 0.42
const SUBSTEP := 0.034
const LOOK_EVERY := 0.07
const ACCEL := 3.0
const BRAKE := 7.0
const HARD_BRAKE := 11.0
const STOP_GAP := 3.0
const CAR_PAD := 0.3
const PANIC_TIME := 4.0
const PANIC_SPEED := 1.4
const GUN_HEAR := 60.0
const OVERLAP_KILL := 0.6
const JAM_FORCE := 40.0
const CAM_KILL := 1.9
const FEED_RADIUS := 60.0                ## the highway only spawns a car when no car of its lane and direction is nearer than the road's `gap` x 0.9 (the density in metres)

static var instance: RoadTraffic

var drawn_cars := 0                      ## mesh cars written into the near traffic's shared MultiMesh this frame
var lamp_node: Node3D                    ## the MultiMeshInstance3D nodes of the lamp pairs (set by AmbientCity): hidden while no pair is drawn
var lamp_mirror_node: Node3D
var lamp_mm: MultiMesh                   ## the far light pairs
var lamp_material: ShaderMaterial
var lamp_mirror: ShaderMaterial
var count := 0                           ## target number of cars at this tier and hour
var radius := 200.0
var quality := 1
var density := 1.0
var rng := RandomNumberGenerator.new()
var enabled := true                      ## false (tests): the road is bare
var promoted := 0
var overlap_kills := 0
var jam_breaks := 0
var honks := 0
var spawned := 0

var _alive := PackedByteArray()
var _road := PackedInt32Array()
var _s := PackedFloat32Array()
var _dir := PackedFloat32Array()
var _spd := PackedFloat32Array()
var _cruise := PackedFloat32Array()
var _allow := PackedFloat32Array()
var _kind := PackedByteArray()
var _paint := PackedByteArray()
var _brake := PackedFloat32Array()
var _panic := PackedFloat32Array()
var _stun := PackedFloat32Array()
var _age := PackedFloat32Array()
var _look_t := PackedFloat32Array()
var _ovl := PackedFloat32Array()
var _ovl_t := PackedFloat32Array()
var _jam := PackedFloat32Array()
var _pos := PackedVector2Array()
var _yaw := PackedFloat32Array()
var _y := PackedFloat32Array()
var _pitch := PackedFloat32Array()
var _buf := PackedFloat32Array()
var _lbuf := PackedFloat32Array()
var _nw := 0
var _nl := 0
var _hero := Vector3.INF
var _hero_foot := true
var _cam_ok := false
var _cam_fwd := Vector2.ZERO
var _cam_pos := Vector2.ZERO
var _clock := 0.0
var _scratch := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _scratch2 := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _respawn_t := 0.0


func build(light_map: Texture2D) -> void:
	instance = self
	rng.seed = 60517
	_buf = MB.new_buffer(DRAWN, false, true)                 # the drawn cars are written into the near traffic's MultiMesh (NearTraffic.append_cars): no draw call of its own
	lamp_mm = Traffic._new_multimesh(Traffic._lamp_mesh(), LAMPS)
	_lbuf = PackedFloat32Array()
	_lbuf.resize(LAMPS * 20)
	for k in LAMPS:                                                           # identity basis, translation y written per car; colour a = kind flag
		_lbuf[k * 20] = 1.0
		_lbuf[k * 20 + 5] = 1.0
		_lbuf[k * 20 + 10] = 1.0
	lamp_mm.buffer = _lbuf
	lamp_mm.visible_instance_count = 0
	lamp_material = ShaderMaterial.new()
	lamp_material.shader = SHADER_LAMPS
	lamp_mirror = ShaderMaterial.new()
	lamp_mirror.shader = SHADER_LAMPS
	lamp_mirror.render_priority = -120
	for a: PackedFloat32Array in [_s, _dir, _spd, _cruise, _allow, _brake, _panic, _stun, _age, _look_t, _ovl, _ovl_t, _jam, _yaw, _y, _pitch]:
		a.resize(CAP)
	for a: PackedByteArray in [_alive, _kind, _paint]:
		a.resize(CAP)
	_road.resize(CAP)
	_pos.resize(CAP)
	set_tier(quality)


func set_time(t: float) -> void:
	lamp_material.set_shader_parameter(&"ambient_time", t)
	lamp_mirror.set_shader_parameter(&"ambient_time", t)


func set_tier(level: int, dens := 1.0) -> void:
	quality = clampi(level, 0, 2)
	density = dens
	var n := int(float(TARGETS[quality]) * dens)
	if quality == 0:
		n = LowPlus.scaled(n, LowPlus.TRAFFIC_SHARE + 0.15, 4)
	count = clampi(n, 0, CAP)
	radius = RADII[quality] * (0.85 if quality == 0 and LowPlus.on() else 1.0)
	for i in CAP:
		if _alive[i] != 0 and i >= count + 6:
			_kill(i)


func reset() -> void:
	for i in CAP:
		_alive[i] = 0
		_age[i] = 0.0
	TrafficField.clear_source(TrafficField.PATH)
	_clock = 0.0
	_nw = 0
	_nl = 0
	if lamp_mm != null:
		lamp_mm.visible_instance_count = 0
		_show_lamps()


func alive_count() -> int:
	var n := 0
	for i in CAP:
		n += _alive[i]
	return n


func car_position(i: int) -> Vector3:
	return Vector3(_pos[i].x, _y[i], _pos[i].y)


func car_speed(i: int) -> float:
	return _spd[i]


func car_alive(i: int) -> bool:
	return _alive[i] != 0


func car_kind(i: int) -> StringName:
	return NearTraffic.KINDS[_kind[i]]


func car_road(i: int) -> int:
	return _road[i]


func car_dir(i: int) -> int:
	return int(_dir[i])


func car_s(i: int) -> float:
	return _s[i]


func debug_state(i: int) -> Dictionary:
	return {"alive": _alive[i], "road": _road[i], "s": _s[i], "dir": _dir[i], "spd": _spd[i], "allow": _allow[i], "cruise": _cruise[i], "jam": _jam[i], "age": _age[i], "kind": NearTraffic.KINDS[_kind[i]]}


func _kill(i: int) -> void:
	_alive[i] = 0
	_age[i] = 0.0
	TrafficField.remove(TrafficField.PATH, i)


# --- placing a car ---------------------------------------------------------------------------------------------------------------------

## The kind of car a road carries (index into NearTraffic.KINDS).
func _pick_kind(road: Dictionary) -> int:
	var track: bool = String(road["kind"]) == "track"
	var mix: Array = NearTraffic.KIND_MIX_TRACK if track else NearTraffic.KIND_MIX_HIGHWAY
	var r := rng.randf()
	var acc := 0.0
	for k in mix.size():
		acc += float(mix[k])
		if r < acc:
			return k
	return 0


func place(i: int, road_i: int, s: float, dir: int, kind: int, cruise: float, paint: int, speed: float) -> void:
	_road[i] = road_i
	_s[i] = s
	_dir[i] = float(dir)
	_kind[i] = kind
	_paint[i] = paint
	_cruise[i] = cruise
	_spd[i] = speed
	_allow[i] = 99.0
	_brake[i] = 0.0
	_panic[i] = 0.0
	_stun[i] = 0.0
	_age[i] = 0.0
	_jam[i] = 0.0
	_ovl[i] = 0.0
	_ovl_t[i] = 0.4 + float(i % 5) * 0.04
	_look_t[i] = float(i % 4) * 0.017
	_alive[i] = 1
	_place_at(i)
	TrafficField.put_yaw(TrafficField.PATH, i, _pos[i].x, _pos[i].y, _yaw[i], NearTraffic.KIND_HALF[kind], NearTraffic.KIND_HW[kind], speed, TrafficField.F_AI)


## Position, heading, height and slope of car `i` from its road, distance and direction.
func _place_at(i: int) -> void:
	var road: Dictionary = RoadLanes.roads[_road[i]]
	var sm := RoadLanes.sample(_road[i], _s[i], _scratch)
	var f := Vector2(sm[2], sm[3]) * _dir[i]
	var right := Vector2(-f.y, f.x)
	_pos[i] = Vector2(sm[0], sm[1]) + right * float(road["lane"])
	_yaw[i] = atan2(-f.x, -f.y)
	_y[i] = sm[4]
	var ahead := RoadLanes.sample(_road[i], _s[i] + _dir[i] * 4.0, _scratch2)
	_pitch[i] = clampf(atan2(ahead[4] - sm[4], 4.0), -0.5, 0.5) * _dir[i] * (1.0 if _dir[i] > 0.0 else 1.0)


func _spawn(i: int, c: Vector3, rmin: float, rmax: float) -> bool:
	for attempt in 8:
		var pick := RoadLanes.random_near(Vector2(c.x, c.z), rmin, rmax, rng)
		if pick.x < 0:
			return false
		var road: Dictionary = RoadLanes.roads[pick.x]
		var cum: PackedFloat32Array = road["cum"]
		var s := cum[pick.y]
		if s < 12.0 or s > float(road["len"]) - 12.0:
			continue
		var sm := RoadLanes.sample(pick.x, s, _scratch)
		if absf(sm[0]) < CityLayout.HALF + 12.0 and absf(sm[1]) < CityLayout.HALF + 12.0:
			continue                                                              # inside the city: those lanes are the near traffic's
		var dir := 1 if rng.randf() < 0.5 else -1
		var gap := float(road["gap"])
		var crowded := false
		var near_n := 0
		for j in CAP:
			if _alive[j] != 0 and _road[j] == pick.x and int(_dir[j]) == dir:
				var ds := absf(_s[j] - s)
				if ds < gap * 0.9:
					crowded = true
					break
				if ds < gap * 3.0:
					near_n += 1
		if crowded or near_n >= 3:
			continue
		var kind := _pick_kind(road)
		var cruise := rng.randf_range(float(road["cmin"]), float(road["cmax"])) * NearTraffic.KIND_SPEED[kind]
		var lp := RoadLanes.lane_point(pick.x, s, dir)
		var pos: Vector2 = lp[0]
		var f: Vector2 = lp[1]
		var khl: float = NearTraffic.KIND_HALF[kind]
		var khw: float = NearTraffic.KIND_HW[kind]
		if not TrafficField.clear(pos.x, pos.y, f.x, f.y, khl, khw, 4.0, TrafficField.PATH, i):
			continue
		var ahead := TrafficField.lead(pos.x, pos.y, f.x, f.y, khl, khw, 80.0, TrafficField.PATH, i, CAR_PAD)
		var v0 := cruise * rng.randf_range(0.8, 1.0)
		if ahead.x < INF:
			var vs := TrafficBrain.safe_speed(ahead.x, ahead.y, BRAKE * 0.7, 0.5, STOP_GAP + 1.0, HARD_BRAKE)
			if vs < 3.0 and ahead.x < 30.0:
				continue
			v0 = minf(v0, vs * 0.85)
		var behind := TrafficField.lead(pos.x, pos.y, -f.x, -f.y, khl, khw, 70.0, TrafficField.PATH, i, CAR_PAD)
		if behind.x < INF:
			var vb := maxf(-behind.y, 0.0)
			if behind.x < vb * vb / (2.0 * BRAKE * 0.7) + vb * 0.6 + 8.0:
				continue
		place(i, pick.x, s, dir, kind, cruise, rng.randi() % 8, v0)
		spawned += 1
		return true
	return false


# --- stepping ------------------------------------------------------------------------------------------------------------------------------

func step(delta: float, center: Vector3) -> void:
	if not enabled:
		if alive_count() > 0:
			reset()
		return
	if RoadLanes.roads.is_empty():
		RoadLanes.ensure()
		if RoadLanes.roads.is_empty():
			return
	_clock += delta
	_hero = center
	_cam_ok = false
	if is_instance_valid(Game.camera):
		var cf := -Game.camera.global_transform.basis.z
		var cp3 := Game.camera.global_position
		var fl := Vector2(cf.x, cf.z)
		if fl.length_squared() > 0.04:
			_cam_ok = true
			_cam_fwd = fl.normalized()
			_cam_pos = Vector2(cp3.x, cp3.z)
	var pl := Game.player
	_hero_foot = not is_instance_valid(pl) or pl.get(&"vehicle") == null
	# the ring is only simulated where a road lies near the hero (a city street or an open field has none: nothing runs, nothing is drawn)
	var near_road := _road_near(center)
	var n_sub := clampi(ceili(delta / SUBSTEP), 1, 6)
	var dt := delta / float(n_sub)
	if near_road:
		for k in n_sub:
			for i in CAP:
				if _alive[i] != 0:
					_sim_car(i, dt, center, pl)
		_respawn_t -= delta
		if _respawn_t <= 0.0:
			_respawn_t = 0.12
			var alive := alive_count()
			if alive < count:
				var tries := 2
				for i in CAP:
					if tries <= 0:
						break
					if _alive[i] == 0 and _spawn(i, center, radius * SPAWN_MIN_FRAC, radius):
						tries -= 1
						break
	else:
		for i in CAP:
			if _alive[i] != 0:
				_kill(i)
	_write_all()


var _road_chk_t := 0.0
var _road_chk_pos := Vector3.INF
var _road_near_cache := false

## True when a road lies within the ring of the hero (cached for half a second or 25 m of walking).
func _road_near(c: Vector3) -> bool:
	if _road_chk_pos.is_finite() and _road_chk_pos.distance_to(c) < 25.0 and _clock - _road_chk_t < 0.5:
		return _road_near_cache
	_road_chk_t = _clock
	_road_chk_pos = c
	var r := RoadLanes.nearest(c.x, c.z)
	_road_near_cache = float(r[2]) < radius + 40.0
	return _road_near_cache


func _sim_car(i: int, dt: float, center: Vector3, pl: Node) -> void:
	_age[i] += dt
	_panic[i] = maxf(_panic[i] - dt, 0.0)
	_stun[i] = maxf(_stun[i] - dt, 0.0)
	_look_t[i] -= dt
	if _look_t[i] <= 0.0:
		_look_t[i] = LOOK_EVERY
		_look(i)
	var want := minf(_cruise[i] * (PANIC_SPEED if _panic[i] > 0.0 else 1.0), _allow[i])
	if _stun[i] > 0.0:
		want = 0.0
	var v := _spd[i]
	if want < 0.7:
		want = 0.0
	v = move_toward(v, want, (ACCEL if want > v else (HARD_BRAKE if want < v - 5.0 else BRAKE)) * dt)
	_spd[i] = v
	_brake[i] = move_toward(_brake[i], 1.0 if (want < v - 0.2 or v < 0.4) else 0.0, dt * 8.0)
	_s[i] += _dir[i] * v * dt
	var len_r := float(RoadLanes.roads[_road[i]]["len"])
	if _s[i] < 6.0 or _s[i] > len_r - 6.0:
		_kill(i)
		return
	_place_at(i)
	var d := _pos[i] - Vector2(center.x, center.z)
	if d.length_squared() > radius * radius * 1.1:
		_kill(i)
		return
	if _hero_foot and _cam_ok and (_pos[i] - _cam_pos).length_squared() < CAM_KILL * CAM_KILL:
		_kill(i)
		return
	TrafficField.put_yaw(TrafficField.PATH, i, _pos[i].x, _pos[i].y, _yaw[i], NearTraffic.KIND_HALF[_kind[i]], NearTraffic.KIND_HW[_kind[i]], v, TrafficField.F_AI)
	_overlap_check(i, dt)
	if _hero_foot and v > 3.0 and is_instance_valid(pl):
		_run_over(i, pl)


func _look(i: int) -> void:
	var p := _pos[i]
	var f := Vector2(-sin(_yaw[i]), -cos(_yaw[i]))
	var half: float = NearTraffic.KIND_HALF[_kind[i]]
	var hw: float = NearTraffic.KIND_HW[_kind[i]]
	var allow := 99.0
	var ld := TrafficField.lead(p.x, p.y, f.x, f.y, half, hw, TrafficBrain.look_for(_spd[i]) + 6.0, TrafficField.PATH, i, CAR_PAD)
	if ld.x < INF:
		allow = TrafficBrain.safe_speed(ld.x, ld.y, BRAKE * 0.7, 0.5, STOP_GAP, HARD_BRAKE)
	if _hero.is_finite() and _hero_foot:                                           # the hero on foot in the lane
		var h2 := Vector2(_hero.x - p.x, _hero.z - p.y)
		var ahead := h2.dot(f)
		if ahead > 0.0 and ahead < TrafficBrain.look_for(_spd[i]) + half and absf(h2.dot(Vector2(-f.y, f.x))) < hw + 0.8:
			allow = minf(allow, TrafficBrain.safe_speed(ahead - half - 0.5, 0.0, BRAKE * 0.7, 0.5, STOP_GAP, HARD_BRAKE))
	_allow[i] = allow
	if _spd[i] < 0.3 and allow < TrafficBrain.CREEP and _stun[i] <= 0.0:
		_jam[i] += LOOK_EVERY
		if _jam[i] > JAM_FORCE:
			_kill(i)
			jam_breaks += 1
	else:
		_jam[i] = 0.0


func _overlap_check(i: int, dt: float) -> void:
	_ovl_t[i] -= dt
	if _ovl_t[i] > 0.0:
		return
	_ovl_t[i] = 0.2
	var f := Vector2(-sin(_yaw[i]), -cos(_yaw[i]))
	var k := TrafficField.first_overlap(_pos[i].x, _pos[i].y, f.x, f.y, NearTraffic.KIND_HALF[_kind[i]], NearTraffic.KIND_HW[_kind[i]], -0.12, TrafficField.PATH, i)
	if k < 0:
		_ovl[i] = 0.0
		return
	_ovl[i] += 0.2
	if _ovl[i] >= OVERLAP_KILL:
		_kill(i)
		overlap_kills += 1


func _run_over(i: int, pl: Node) -> void:
	if not pl.has_method(&"damage"):
		return
	var q := Vector2(pl.global_position.x, pl.global_position.z) - _pos[i]
	var f := Vector2(-sin(_yaw[i]), -cos(_yaw[i]))
	var along := q.dot(f)
	var lat := absf(q.x * f.y - q.y * f.x)
	if along > -NearTraffic.KIND_HALF[_kind[i]] and along < NearTraffic.KIND_HALF[_kind[i]] + 0.3 and lat < 1.25 and absf(pl.global_position.y - _y[i]) < 2.0:
		_spd[i] *= 0.3
		_stun[i] = 0.9
		pl.call(&"damage", 8.0 + _spd[i] * 2.0, car_position(i))


# --- reactions ----------------------------------------------------------------------------------------------------------------------------

func hear(pos: Vector3, what: StringName) -> int:
	var n := 0
	for i in CAP:
		if _alive[i] == 0:
			continue
		var d := _pos[i] - Vector2(pos.x, pos.z)
		match what:
			&"gun":
				if d.length() < GUN_HEAR:
					_panic[i] = PANIC_TIME
					n += 1
			&"horn":
				var f := Vector2(-sin(_yaw[i]), -cos(_yaw[i]))
				if d.length() < 18.0 and d.dot(f) > 0.0:
					_panic[i] = maxf(_panic[i], 1.5)
					n += 1
			&"crash":
				if d.length() < 24.0:
					_stun[i] = 1.6
					n += 1
	return n


# --- the hero takes a car, drives into one -------------------------------------------------------------------------------------------

func car_near(pos: Vector3, reach: float) -> int:
	var best := -1
	var best_d := INF
	for i in CAP:
		if _alive[i] == 0 or absf(_y[i] - pos.y) > 6.0:
			continue
		var q := Vector2(pos.x, pos.z) - _pos[i]
		var f := Vector2(-sin(_yaw[i]), -cos(_yaw[i]))
		var along := absf(q.dot(f)) - NearTraffic.KIND_HALF[_kind[i]]
		var lat := absf(q.x * f.y - q.y * f.x) - NearTraffic.KIND_HW[_kind[i]]
		var d := Vector2(maxf(along, 0.0), maxf(lat, 0.0)).length()
		if d <= reach and d < best_d:
			best_d = d
			best = i
	return best


## Swap car `i` for a real Vehicle at the same place, heading and speed that keeps driving the road by itself (PathDriver). Null when the manager has no room.
func promote(i: int) -> Vehicle:
	var mgr := Game.vehicles as VehicleManager
	if mgr == null or _alive[i] == 0:
		return null
	var v := mgr.spawn_promoted_path(NearTraffic.KINDS[_kind[i]], Vector3(_pos[i].x, _y[i], _pos[i].y), _yaw[i], _road[i], _s[i], int(_dir[i]), _spd[i], _cruise[i], int(_paint[i]))
	if v == null:
		return null
	_kill(i)
	promoted += 1
	return v


func promote_near(pos: Vector3, reach: float) -> Vehicle:
	var i := car_near(pos, reach)
	return null if i < 0 else promote(i)


func promote_around(pos: Vector3, r: float) -> int:
	var n := 0
	for i in CAP:
		if _alive[i] != 0 and (_pos[i] - Vector2(pos.x, pos.z)).length() < r:
			if promote(i) != null:
				n += 1
			else:
				break
	return n


## The cars that could not be promoted are still solid (see NearTraffic.collide_vehicle): the real vehicle gets a real crash, the road car is shoved clear and stunned.
func collide_vehicle(v: Vehicle) -> int:
	var hits := 0
	var vp := Vector2(v.global_position.x, v.global_position.z)
	var vf3 := v.forward()
	var vf := Vector2(vf3.x, vf3.z)
	var vhl := float(v.spec["len"]) * 0.5
	var vhw := float(v.spec["wid"]) * 0.5
	for i in CAP:
		if _alive[i] == 0:
			continue
		var dp := _pos[i] - vp
		if absf(dp.x) > 10.0 or absf(dp.y) > 10.0:
			continue
		var f := Vector2(-sin(_yaw[i]), -cos(_yaw[i]))
		var depth := TrafficField.obb_depth(vp.x, vp.y, vf.x, vf.y, vhl, vhw, _pos[i].x, _pos[i].y, f.x, f.y, NearTraffic.KIND_HALF[_kind[i]], NearTraffic.KIND_HW[_kind[i]])
		if depth <= 0.03:
			continue
		hits += 1
		var n2 := vp - _pos[i]
		if n2.length_squared() < 1e-6:
			n2 = vf
		n2 = n2.normalized()
		var n := Vector3(n2.x, 0.0, n2.y)
		var at := Vector3((vp.x + _pos[i].x) * 0.5, v.global_position.y, (vp.y + _pos[i].y) * 0.5)
		var near_v := f * _spd[i]
		var vrel := (v.point_velocity(at) - Vector3(near_v.x, 0.0, near_v.y)).dot(n)
		var back := n2 * (depth + 0.08)
		_s[i] += -_dir[i] * 0.0                                                      # the shove is sideways and backwards along the car's own line (kept on the road)
		_pos[i] -= back
		_stun[i] = maxf(_stun[i], 1.8)
		_spd[i] *= 0.25
		v.global_position += Vector3(n2.x, 0.0, n2.y) * depth * 0.25
		if vrel < 0.0:
			var inv := v.inverse_mass_at(n, at) + 1.0 / NearTraffic.NEAR_MASS
			var j := -(1.0 + VehicleSpecs.RESTITUTION) * vrel / inv
			v.apply_impulse(n * j, at)
			var closing := -vrel
			if closing > VehicleSpecs.CAR_HIT_SPEED:
				var mgr := Game.vehicles as VehicleManager
				if mgr != null:
					mgr.hear(Vector3(_pos[i].x, 0.0, _pos[i].y), &"crash")
				if v.driver_is_player:
					FX.shake(clampf(closing / 22.0, 0.15, 0.9))
				FX.burst(Vector3(at.x, at.y + 0.7, at.z), Color(1.0, 0.75, 0.38), 6, 4.0, 0.3, 7.0, 0.3)
				Sfx.play_at(&"hit", at, -3.0)
				honks += 1
				v.crash(closing, at, n, NearTraffic.NEAR_MASS)
			v.lane_lost(closing)
	return hits


# --- the buffers ---------------------------------------------------------------------------------------------------------------------------

func _write_all() -> void:
	_nw = 0
	_nl = 0
	var dr := DRAW_R[quality]
	for i in CAP:
		if _alive[i] == 0:
			continue
		var dx := _pos[i].x - _cam_pos.x
		var dz := _pos[i].y - _cam_pos.y
		var d2 := dx * dx + dz * dz if _cam_ok else 0.0
		var drawn := not _cam_ok or d2 <= dr * dr
		if drawn and _cam_ok and d2 > VIEW_NEAR * VIEW_NEAR and (dx * _cam_fwd.x + dz * _cam_fwd.y) < VIEW_COS * sqrt(d2):
			drawn = false
		if drawn and _nw < DRAWN:
			_write_mesh(i)
		elif not drawn and d2 > dr * dr * 0.8 and _nl < LAMPS and (dx * _cam_fwd.x + dz * _cam_fwd.y) > -0.35 * sqrt(d2):
			_write_lamp(i)
	if _nw > 0 and NearTraffic.instance != null:
		drawn_cars = NearTraffic.instance.append_cars(_buf, _nw)
	else:
		drawn_cars = 0
	lamp_mm.visible_instance_count = _nl
	if _nl > 0:
		lamp_mm.buffer = _lbuf
	_show_lamps()


## The lamp MultiMesh nodes are drawn only while a lamp pair is written (an empty MultiMesh node still costs a draw call on the phone: the street of the city has no highway lamps).
func _show_lamps() -> void:
	if lamp_node != null and is_instance_valid(lamp_node):
		lamp_node.visible = _nl > 0
	if lamp_mirror_node != null and is_instance_valid(lamp_mirror_node):
		lamp_mirror_node.visible = _nl > 0 and quality >= 1


func _write_mesh(i: int) -> void:
	var o := _nw * 16
	_nw += 1
	var fade := minf(1.0, _age[i] * 1.2 + 0.05)
	var b := Basis(Vector3.UP, _yaw[i]) * Basis(Vector3.RIGHT, _pitch[i])
	_buf[o] = b.x.x * fade
	_buf[o + 1] = b.y.x
	_buf[o + 2] = b.z.x * fade
	_buf[o + 3] = _pos[i].x
	_buf[o + 4] = b.x.y * fade
	_buf[o + 5] = b.y.y * fade
	_buf[o + 6] = b.z.y * fade
	_buf[o + 7] = _y[i]
	_buf[o + 8] = b.x.z * fade
	_buf[o + 9] = b.y.z
	_buf[o + 10] = b.z.z * fade
	_buf[o + 11] = _pos[i].y
	_buf[o + 12] = float(_paint[i])
	_buf[o + 13] = float(NearTraffic.KIND_VARIANT[_kind[i]])
	_buf[o + 14] = _brake[i]
	_buf[o + 15] = 1.0


func _write_lamp(i: int) -> void:
	var o := _nl * 20
	_nl += 1
	var f := Vector2(-sin(_yaw[i]), -cos(_yaw[i]))
	_lbuf[o + 7] = _y[i]
	var tint := Color(1.0, 0.92, 0.78).lerp(Color(0.80, 0.90, 1.0), float(_paint[i]) / 7.0)
	_lbuf[o + 12] = tint.r
	_lbuf[o + 13] = tint.g
	_lbuf[o + 14] = tint.b
	_lbuf[o + 15] = NearTraffic.KIND_LAMP[_kind[i]]
	_lbuf[o + 16] = _pos[i].x
	_lbuf[o + 17] = _pos[i].y
	_lbuf[o + 18] = f.x
	_lbuf[o + 19] = f.y
