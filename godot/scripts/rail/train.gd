class_name Train
extends Node3D
## One train of a line: a consist of cars (TrainKit), a place on the timetable (RailSchedule.at) and, while the hero is within range, real bodies. Cars are pooled: built once, hidden and
## without collision while far away. Each car is an AnimatableBody3D (the hero stands on it and is carried: CharacterBody3D moving platform) with the shared car mesh and shared shapes.
##   state            {u, dir, v, stop, dwell_left, next, leg} from the timetable (or frozen by a derailment)
##   active           near the hero: visible, solid, simulated
##   car_xf(i)        world transform of car i; `centre()` the middle of the consist
##   horn()           plays the horn from the front of the train
## Hits: a vehicle or the hero on the track in front of or beside a moving car is hit (damage and a shove); `derail()` ends a train where it stands (cars tilt, burning).

const HIT_SPEED := 5.0
const SHOW_RANGE := 900.0

signal horned
signal derailed_signal
signal arrived(station: String)

var route: Dictionary
var kind: StringName
var phase := 0.0
var sched: RailSchedule
var lay: Array[Dictionary] = []
var cars: Array[Dictionary] = []                # {root, mesh, type, off, len, flip, spec}
var state := {"u": 0.0, "dir": 1, "v": 0.0, "stop": 0, "dwell_left": 0.0}
var active := false
var derailed := false
var hits := 0
var length := 0.0
var _last_stop := -2
var _horn_cd := 0.0
var _hit_cd := 0.0
var _snd: AudioStreamPlayer3D
var _smoke: Array[Node3D] = []
var _tilt: Array[Vector3] = []
var _derail_t := 0.0


func setup(r: Dictionary, k: StringName, ph: float, schedule: RailSchedule) -> void:
	route = r
	kind = k
	phase = ph
	sched = schedule
	name = "%s_%s" % [String(r["id"]), String(k)]
	lay = TrainKit.layout(k)
	length = TrainKit.consist_length(k)
	visible = false
	for l in lay:
		var cd := TrainKit.car(l["type"], k)
		var root := AnimatableBody3D.new()
		root.name = "Car"
		root.collision_layer = 0
		root.collision_mask = 0
		root.sync_to_physics = true
		var spec: Dictionary = cd["spec"]
		var shapes: Array = spec["shapes"]
		if not spec.has("shape_res"):
			var res: Array = []
			for sh: Dictionary in shapes:
				var bs := BoxShape3D.new()
				bs.size = sh["size"]
				res.append(bs)
			spec["shape_res"] = res
		var sres: Array = spec["shape_res"]
		for i in shapes.size():
			var cs := CollisionShape3D.new()
			cs.shape = sres[i]
			cs.position = (shapes[i] as Dictionary)["pos"]
			root.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = cd["mesh"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		root.add_child(mi)
		add_child(root)
		cars.append({"root": root, "mesh": mi, "type": l["type"], "off": l["off"], "len": l["len"], "flip": l["flip"], "spec": spec})
		_tilt.append(Vector3.ZERO)
	evaluate(0.0)


func _exit_tree() -> void:
	pass


## Take the position the timetable gives at clock time t (no-op for a derailed train).
func evaluate(t: float) -> void:
	if derailed:
		return
	state = sched.at(t, phase)
	if int(state["stop"]) != _last_stop:
		_last_stop = int(state["stop"])
		if _last_stop >= 0:
			arrived.emit(sched.names[_last_stop])


func u() -> float:
	return float(state["u"])


func speed() -> float:
	return float(state["v"])


func lane_dir() -> int:
	return int(state["dir"])


func centre() -> Vector3:
	var lp := RailNet.lane_point(route, u(), lane_dir())
	return lp[0]


func front() -> Vector3:
	var lp := RailNet.lane_point(route, u() + float(lane_dir()) * length * 0.5, lane_dir())
	return lp[0]


## Where car i stands: the middle of the two bogie points, the heading along them.
func car_xf(i: int) -> Transform3D:
	var c: Dictionary = cars[i]
	var uc := u() + float(c["off"])
	var half := float(c["len"]) * 0.5 - 3.2
	var d := lane_dir()
	var pf := RailNet.lane_point(route, uc + half, d)
	var pb := RailNet.lane_point(route, uc - half, d)
	var a: Vector3 = pf[0]
	var b: Vector3 = pb[0]
	var fwd := (a - b).normalized()
	var up := Vector3.UP
	var basis := Basis.looking_at(fwd if bool(c["flip"]) else -fwd, up)
	var o := (a + b) * 0.5 + Vector3(0.0, RailNet.RAIL_TOP, 0.0)
	if derailed:
		var tl: Vector3 = _tilt[i]
		basis = basis * Basis(Vector3.FORWARD, tl.z * minf(_derail_t, 1.5) / 1.5) * Basis(Vector3.RIGHT, tl.x * minf(_derail_t, 1.5) / 1.5)
		o += Vector3(tl.y * minf(_derail_t, 1.5) / 1.5, 0.0, 0.0).rotated(Vector3.UP, 0.0)
	return Transform3D(basis, o)


## Show / hide, switch the colliders. `hero` is the player position (INF = nobody).
func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	visible = on
	for c in cars:
		(c["root"] as AnimatableBody3D).collision_layer = Game.L_WORLD if on else 0
	if not on and _snd != null:
		_snd.stop()
	if on:
		place()


func place() -> void:
	for i in cars.size():
		(cars[i]["root"] as AnimatableBody3D).global_transform = car_xf(i)


func step(delta: float, clock: float, hero: Vector3) -> void:
	_horn_cd = maxf(0.0, _horn_cd - delta)
	_hit_cd = maxf(0.0, _hit_cd - delta)
	evaluate(clock)
	if derailed:
		_derail_t += delta
	var near := hero.is_finite() and centre().distance_to(hero) < SHOW_RANGE + length
	set_active(near)
	if not active:
		return
	place()
	_audio(hero)
	if speed() > 3.0 or derailed:
		_wake_fx(delta)
	if speed() > HIT_SPEED and _hit_cd <= 0.0 and not derailed:
		_hit_check()
	# the horn: a blast as it pulls out of a station and one when it comes into the hero's sight at speed
	if int(state["stop"]) >= 0 and float(state["dwell_left"]) < 3.0 and float(state["dwell_left"]) > 0.0 and _horn_cd <= 0.0:
		horn()
	var leg_t := float(state["dwell_left"])


func horn() -> void:
	if _horn_cd > 0.0:
		return
	_horn_cd = 9.0
	var fp := front() + Vector3(0.0, 3.0, 0.0)
	Sfx.play_at(&"train_horn" if kind != &"maglev" else &"maglev_chime", fp, 2.0)
	horned.emit()


func _audio(hero: Vector3) -> void:
	if not hero.is_finite():
		return
	var d := centre().distance_to(hero)
	if d > 260.0 or Sfx.muted:
		if _snd != null and _snd.playing:
			_snd.stop()
		return
	if _snd == null:
		_snd = AudioStreamPlayer3D.new()
		_snd.name = "Rumble"
		_snd.unit_size = 22.0
		_snd.max_distance = 300.0
		_snd.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
		var st := Sfx.variants_of(&"maglev_hum" if kind == &"maglev" else &"train_clatter")
		if st.is_empty():
			return
		if st[0] is AudioStreamOggVorbis:
			(st[0] as AudioStreamOggVorbis).loop = true
		_snd.stream = st[0]
		add_child(_snd)
	var v := speed()
	_snd.global_position = centre() + Vector3(0.0, 2.0, 0.0)
	_snd.volume_db = lerpf(-30.0, -3.0, clampf(v / 22.0, 0.0, 1.0)) + (4.0 if kind == &"maglev" else 0.0)
	_snd.pitch_scale = lerpf(0.75, 1.25, clampf(v / maxf(float(route["speed"]), 1.0), 0.0, 1.0))
	if not _snd.playing and v > 0.5:
		_snd.play()
	elif _snd.playing and v < 0.2:
		_snd.stop()


var _fx_t := 0.0


func _wake_fx(delta: float) -> void:
	_fx_t -= delta
	if _fx_t > 0.0:
		return
	_fx_t = 0.4 if not derailed else 0.25
	if kind == &"maglev" or not Game.is_playing():
		return
	var lead := 0 if lane_dir() < 0 else cars.size() - 1
	var c: Dictionary = cars[lead]
	var xf := (c["root"] as Node3D).global_transform
	FX.burst(xf.origin + xf.basis.y * 4.6, Color(0.55, 0.55, 0.58, 0.5) if not derailed else Color(0.2, 0.2, 0.22, 0.8), 2, 2.5, 3.0, 3.5, 2.0)


## A vehicle or the hero close to a moving car is hit.
func _hit_check() -> void:
	var fwd := Vector3.ZERO
	var vs: Array = []
	if is_instance_valid(Game.vehicles) and Game.vehicles.get("list") != null:
		vs = Game.vehicles.get("list")
	var hero := Game.player as Node3D
	for i in cars.size():
		var xf := (cars[i]["root"] as Node3D).global_transform
		var inv := xf.affine_inverse()
		var half_l := float(cars[i]["len"]) * 0.5 + 0.8
		for v in vs:
			if not is_instance_valid(v) or not (v as Vehicle).active or (v as Vehicle).dead or (v as Vehicle).is_aloft():
				continue
			var lp := inv * (v as Node3D).global_position
			if absf(lp.x) < 2.6 and absf(lp.z) < half_l and lp.y > -1.0 and lp.y < 3.5:
				hits += 1
				_hit_cd = 0.8
				fwd = (xf.basis.z * (-1.0 if bool(cars[i]["flip"]) else 1.0))
				(v as Vehicle).damage((v as Vehicle).max_hp * 1.4)
				(v as Vehicle).vel = Vector3(fwd.x, 0.0, fwd.z) * speed() * 0.5 * float(lane_dir())
				FX.shake(0.4)
				return
		if is_instance_valid(hero) and not (hero.get("vehicle") != null):
			var lp2 := inv * hero.global_position
			var on_train := lp2.y > TrainKit.FLOOR - 0.5
			if not on_train and absf(lp2.x) < 2.2 and absf(lp2.z) < half_l and lp2.y > -1.2 and lp2.y < 2.0:
				hits += 1
				_hit_cd = 1.2
				if hero.has_method(&"damage"):
					hero.call(&"damage", 35.0, xf.origin)
				if hero is CharacterBody3D:
					var sideways := xf.basis.x * signf(lp2.x if absf(lp2.x) > 0.1 else 1.0)
					(hero as CharacterBody3D).velocity += sideways * 9.0 + Vector3.UP * 5.0
				return


## The train stops where it is, the cars tilt and burn.
func derail() -> void:
	if derailed:
		return
	derailed = true
	state["v"] = 0.0
	state["stop"] = -1
	_derail_t = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + cars.size()
	for i in cars.size():
		_tilt[i] = Vector3(rng.randf_range(-0.06, 0.06), rng.randf_range(-0.8, 0.8), rng.randf_range(-0.55, 0.55) * (1.0 if i % 2 == 0 else -1.0))
	for i in cars.size():
		if i % 3 == 0:
			Game.explode((cars[i]["root"] as Node3D).global_position + Vector3(0.0, 2.0, 0.0), 6.0, {"enemy_dmg": 20.0, "car_dmg": 40.0, "player_dmg": 8.0, "burn": 14.0})
	derailed_signal.emit()
	place()
