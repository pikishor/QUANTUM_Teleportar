class_name Ship
extends AnimatableBody3D
## One big ship (data and meshes: ShipKit). An AnimatableBody3D on the world layer: the hero walks on its deck and is carried (moving platform), boats bump into the hull. Three modes:
##   &"moored"  held at its berth (bobbing on the real waves through WaterWorld.buoyancy)
##   &"lane"    sails a closed loop at sea by the clock (scenery; the cruise liner, the tanker, the second freighter)
##   &"helm"    driven by the hero at the helm: throttle (forward / back), rudder (left / right), 12-17 m/s, runs aground at shores instead of climbing them, the horn on USE
## Turrets (the destroyer): `turret_nodes` rotate to the aim of the hero who mans one (ShipWorld). `helm_world()`, `pad_world()`, `gun_world(i)` give world positions for prompts and missions.

const SEA := TerrainHeight.SEA_LEVEL

var id: StringName
var type: StringName
var spec: Dictionary
var mode: StringName = &"moored"
var heading := 0.0
var speed := 0.0
var throttle := 0.0
var rudder := 0.0
var dock_side := 0.0                          ## +1 / -1: the ship side towards the quay (a gangway is built there), 0 none
var driver: Node3D
var built := false
var path: Array[Vector2] = []                 ## lane loop
var lane_u := 0.0
var lane_speed := 6.0
var turret_nodes: Array[Node3D] = []
var turret_yaw: Array[float] = []
var manned := -1
var water_y := SEA
var groundings := 0
var home := Vector3.ZERO
var sim_pos := Vector3.ZERO                   ## where the hull is (x, z): the node's own transform is only written (an AnimatableBody3D synced to physics)
var _pitch := 0.0
var _roll := 0.0
var _mi: MeshInstance3D
var _lane_len := 0.0
var _last_safe := Vector3.ZERO
var _snd: AudioStreamPlayer3D
var _wake_t := 0.0


func setup(ship_id: StringName, t: StringName, pos: Vector3, h: float, side := 0.0) -> void:
	id = ship_id
	type = t
	name = String(ship_id)
	spec = ShipKit.spec(t)
	heading = h
	dock_side = side
	home = pos
	position = pos                                 # (not in the tree yet: the parent sits at the origin)
	sim_pos = pos
	_last_safe = pos
	collision_layer = Game.L_WORLD
	collision_mask = 0
	sync_to_physics = true
	visible = false


func build() -> void:
	if built:
		return
	built = true
	_mi = MeshInstance3D.new()
	_mi.name = "Hull"
	_mi.mesh = ShipKit.mesh(type)
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mi.visibility_range_end = ShipWorld.SHOW_RANGE
	add_child(_mi)
	for sh: Dictionary in spec["shapes"]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sh["size"]
		cs.shape = bs
		cs.position = sh["pos"]
		add_child(cs)
	for tu: Dictionary in spec["turrets"]:
		var n := Node3D.new()
		n.name = "Turret"
		n.position = tu["pos"]
		var mi := MeshInstance3D.new()
		mi.mesh = ShipKit.turret_mesh()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = ShipWorld.SHOW_RANGE
		n.add_child(mi)
		add_child(n)
		turret_nodes.append(n)
		turret_yaw.append(0.0)
		var cs2 := CollisionShape3D.new()
		var b2 := BoxShape3D.new()
		b2.size = Vector3(4.4, 2.4, 5.0)
		cs2.shape = b2
		cs2.position = (tu["pos"] as Vector3) + Vector3(0.0, 1.2, 0.0)
		add_child(cs2)
	if dock_side != 0.0:
		_gangway()


func _gangway() -> void:
	var gw: Vector3 = spec["gangway"]
	var hw: float = float(spec["beam"]) * 0.5
	var deck: float = gw.y
	var quay := Harbour.QUAY_Y - SEA
	var length := 12.5 if deck < 8.0 else 15.0
	var rise := deck - quay
	var ang := atan2(rise, length)
	var side := dock_side
	var cx := side * (hw - 0.3 + length * 0.5)
	var cy := (deck + quay) * 0.5 - 0.12
	var plank_len := sqrt(length * length + rise * rise)
	var xf := Transform3D(Basis(Vector3.BACK, -ang * side), Vector3(cx, cy, gw.z))
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(plank_len, 0.3, 2.8)
	cs.shape = bs
	cs.transform = xf
	add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(plank_len, 0.25, 2.8)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.52, 0.55)
	m.metallic = 0.4
	m.roughness = 0.55
	mi.material_override = m
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = ShipWorld.SHOW_RANGE
	add_child(mi)
	for sz in [-1.0, 1.0]:                                                  # hand rails
		var r := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(plank_len, 0.08, 0.08)
		r.mesh = rb
		r.material_override = m
		r.transform = Transform3D(xf.basis, xf.origin + xf.basis * Vector3(0.0, 1.0, float(sz) * 1.35))
		r.visibility_range_end = ShipWorld.SHOW_RANGE
		add_child(r)


# --- positions ----------------------------------------------------------------------------------------------------------------------

## Put the hull at (x, z) now.
func teleport(p: Vector3) -> void:
	sim_pos = Vector3(p.x, 0.0, p.z)
	place(0.0)


func fwd() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


func right() -> Vector3:
	return Vector3(cos(heading), 0.0, -sin(heading))


func local_to_world(p: Vector3) -> Vector3:
	return global_transform * p


func helm_world() -> Vector3:
	return local_to_world(spec["helm"])


func pad_world() -> Vector3:
	var p: Vector3 = spec["pad"]
	return local_to_world(p) if p.is_finite() else Vector3.INF


func gun_world(i: int) -> Vector3:
	return local_to_world((spec["turrets"][i] as Dictionary)["pos"])


func muzzle_world(i: int) -> Vector3:
	return turret_nodes[i].global_transform * Vector3(0.0, 1.5, -9.8)


# --- movement -----------------------------------------------------------------------------------------------------------------------

## Sets the transform from position, heading and the waves.
func place(dt: float) -> void:
	var pos := sim_pos
	var bu := WaterWorld.buoyancy(Vector3(pos.x, 0.0, pos.z), heading, float(spec["len"]) * 0.4, float(spec["beam"]) * 0.45)
	var y := float(bu["y"]) if bu["water"] else SEA
	water_y = lerpf(water_y, y, 1.0 - exp(-3.0 * dt)) if dt > 0.0 else y
	_pitch = lerpf(_pitch, float(bu["pitch"]) * 0.35, 1.0 - exp(-2.0 * dt)) if dt > 0.0 else float(bu["pitch"]) * 0.35
	_roll = lerpf(_roll, float(bu["roll"]) * 0.35, 1.0 - exp(-2.0 * dt)) if dt > 0.0 else float(bu["roll"]) * 0.35
	var b := Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, _pitch) * Basis(Vector3.FORWARD, -_roll)
	global_transform = Transform3D(b, Vector3(pos.x, water_y, pos.z))


func lane_length() -> float:
	if _lane_len > 0.0 or path.is_empty():
		return _lane_len
	for i in path.size():
		_lane_len += path[i].distance_to(path[(i + 1) % path.size()])
	return _lane_len


func lane_at(u: float) -> Array:
	var total := lane_length()
	u = fposmod(u, total)
	for i in path.size():
		var a := path[i]
		var b := path[(i + 1) % path.size()]
		var l := a.distance_to(b)
		if u <= l:
			var d := (b - a) / maxf(l, 0.01)
			return [a.lerp(b, u / maxf(l, 0.01)), atan2(-d.x, -d.y)]
		u -= l
	return [path[0], 0.0]


func step_lane(clock: float, dt: float) -> void:
	var la := lane_at(lane_u + lane_speed * clock)
	var p2: Vector2 = la[0]
	heading = lerp_angle(heading, float(la[1]), 1.0 - exp(-1.5 * dt)) if dt > 0.0 else float(la[1])
	sim_pos = Vector3(p2.x, 0.0, p2.y)
	speed = lane_speed
	place(dt)


## Driven: throttle -1..1, rudder -1..1 (+ = turn left). Returns true when it ran aground this tick.
func step_helm(dt: float, thr: float, rud: float) -> bool:
	var vmax: float = spec["max_speed"]
	throttle = thr
	var target := thr * vmax if thr >= 0.0 else thr * vmax * 0.3
	var acc := 1.6 if absf(target) > absf(speed) else 1.2
	speed = move_toward(speed, target, acc * dt)
	var turn := 0.34 * clampf(absf(speed) / 6.0, 0.15, 1.0) * (1.0 if speed >= 0.0 else -1.0)
	heading += rud * turn * dt
	var move := fwd() * speed * dt
	var np := sim_pos + move
	var grounded := false
	var hl: float = float(spec["len"]) * 0.5 - 8.0
	var hb: float = float(spec["beam"]) * 0.5 - 2.0
	var f := Vector3(-sin(heading), 0.0, -cos(heading))
	var r := Vector3(cos(heading), 0.0, -sin(heading))
	for probe: Vector3 in [f * hl, -f * hl, r * hb + f * hl * 0.5, -r * hb + f * hl * 0.5, r * hb - f * hl * 0.5, -r * hb - f * hl * 0.5]:
		var q := np + probe
		if TerrainHeight.depth_at(q.x, q.z) < float(spec["draft"]) + 0.5:
			grounded = true
	if grounded:
		speed *= -0.25
		groundings += 1
	else:
		sim_pos = np
		_last_safe = np
	place(dt)
	_wake(dt)
	return grounded


func _wake(dt: float) -> void:
	_wake_t -= dt
	if _wake_t > 0.0 or absf(speed) < 2.0:
		return
	_wake_t = 0.25
	var bow := sim_pos + fwd() * float(spec["len"]) * 0.45
	FX.burst(Vector3(bow.x, SEA + 0.4, bow.z), Color(0.92, 0.97, 1.0, 0.7), 3, 3.0, 1.2, 3.0, 2.5)
	var stern := sim_pos - fwd() * float(spec["len"]) * 0.45
	FX.burst(Vector3(stern.x, SEA + 0.3, stern.z), Color(0.92, 0.97, 1.0, 0.6), 2, 2.0, 1.6, 2.0, 3.0)


func horn() -> void:
	Sfx.play_at(&"ship_horn", sim_pos + Vector3(0.0, 12.0, 0.0), 4.0)


func engine_audio(hero: Vector3) -> void:
	if Sfx.muted or not hero.is_finite():
		return
	var d := sim_pos.distance_to(Vector3(hero.x, 0.0, hero.z))
	if d > 400.0 or absf(speed) < 0.3:
		if _snd != null and _snd.playing:
			_snd.stop()
		return
	if _snd == null:
		var st := Sfx.variants_of(&"ship_engine")
		if st.is_empty():
			return
		if st[0] is AudioStreamOggVorbis:
			(st[0] as AudioStreamOggVorbis).loop = true
		_snd = AudioStreamPlayer3D.new()
		_snd.stream = st[0]
		_snd.unit_size = 40.0
		_snd.max_distance = 500.0
		add_child(_snd)
	_snd.global_position = sim_pos + Vector3(0.0, 4.0, 0.0)
	_snd.volume_db = lerpf(-24.0, -4.0, clampf(absf(speed) / float(spec["max_speed"]), 0.0, 1.0))
	_snd.pitch_scale = lerpf(0.7, 1.3, clampf(absf(speed) / float(spec["max_speed"]), 0.0, 1.0))
	if not _snd.playing:
		_snd.play()


func aim_turret(i: int, yaw_world: float, dt: float) -> void:
	# the house turns on the deck: local yaw = world aim minus the ship's heading
	var local := wrapf(yaw_world - heading, -PI, PI)
	turret_yaw[i] = lerp_angle(turret_yaw[i], local, 1.0 - exp(-4.0 * dt))
	turret_nodes[i].rotation.y = turret_yaw[i]
