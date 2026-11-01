class_name InteriorCivilian
extends Node3D
## A non-combatant inside an interior: a civilian (stands, drifts between spots, runs for the far corner when shots are fired near), a vendor (stays behind the counter, turns toward the
## player, carries a glowing diamond) or a hostage (kneels, bound, cyan ring until freed, then runs for the door). One merged vertex-coloured mesh per person (one draw call), a
## shared marker mesh for vendors and hostages. Pooled by InteriorActors: setup once, activate / deactivate per interior, no allocation while playing.
## Movement is kinematic on the floor plane; walls and furniture are the interior's `wall_rects` (InteriorGameplay.blocks), so they never walk through a wall.

const MB := preload("res://scripts/world/mesh_builder.gd")
const WALK := 0.95
const RUN := 3.6
const TURN := 6.0
const COATS: Array[Color] = [
	Color(0.18, 0.2, 0.26), Color(0.32, 0.18, 0.16), Color(0.15, 0.26, 0.24), Color(0.28, 0.25, 0.14), Color(0.22, 0.17, 0.3), Color(0.12, 0.13, 0.15),
]

static var _marker_mesh: ArrayMesh

var role: StringName = &"civilian"           ## civilian | vendor | hostage
var state: StringName = &"idle"              ## idle | wander | flee | cower | freed
var active := false
var home := Vector3.ZERO
var spots: Array[Vector3] = []               ## places a civilian may drift to
var tag := ""                                ## "SAFE" etc. for tests
var freed := false

var _body: MeshInstance3D
var _marker: MeshInstance3D
var _t := 0.0
var _wait := 1.0
var _goal := Vector3.ZERO
var _yaw := 0.0
var _kneel := false
var _built_seed := -1
var _marker_own: StandardMaterial3D


func _ready() -> void:
	visible = false


## Build the mesh for a palette seed (once per pooled person; rebuilt only when the seed changes).
func setup(seed_value: int) -> void:
	if _built_seed == seed_value and _body != null:
		return
	_built_seed = seed_value
	if _body != null:
		_body.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 7
	var coat := COATS[rng.randi() % COATS.size()]
	var skin := Color(0.62, 0.5, 0.42).lerp(Color(0.25, 0.18, 0.14), rng.randf())
	var b := MB.new()
	var h := rng.randf_range(0.94, 1.06)
	b.box(Vector3(-0.1, 0.45 * h, 0.0), Vector3(0.16, 0.9 * h, 0.2), Color(0.08, 0.09, 0.11, 1.0))          # legs
	b.box(Vector3(0.1, 0.45 * h, 0.0), Vector3(0.16, 0.9 * h, 0.2), Color(0.08, 0.09, 0.11, 1.0))
	b.box(Vector3(0.0, 1.2 * h, 0.0), Vector3(0.46, 0.62 * h, 0.28), coat)                                    # torso / coat
	b.box(Vector3(0.0, 0.92 * h, 0.0), Vector3(0.5, 0.34 * h, 0.3), coat.darkened(0.2))                       # coat skirt
	b.box(Vector3(-0.29, 1.15 * h, 0.0), Vector3(0.1, 0.6 * h, 0.14), coat)                                   # arms
	b.box(Vector3(0.29, 1.15 * h, 0.0), Vector3(0.1, 0.6 * h, 0.14), coat)
	b.sphere(Vector3(0.0, 1.66 * h, 0.0), Vector3(0.13, 0.15, 0.14), 8, 5, skin)                               # head
	b.box(Vector3(0.0, 1.72 * h, -0.02), Vector3(0.28, 0.1, 0.3), coat.darkened(0.35))                         # hood / cap
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	_body = MeshInstance3D.new()
	_body.mesh = b.build(mat, false, true)
	_body.name = "Body"
	add_child(_body)
	if _marker == null:
		_marker = MeshInstance3D.new()
		_marker.name = "Marker"
		_marker.mesh = marker_mesh()
		_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_marker_own = StandardMaterial3D.new()
		_marker_own.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_marker.material_override = _marker_own
		add_child(_marker)
		_marker.position = Vector3(0.0, 2.35, 0.0)
		_marker.visible = false


static func marker_mesh() -> ArrayMesh:
	if _marker_mesh == null:
		var b := MB.new()
		b.sphere(Vector3.ZERO, Vector3(0.14, 0.24, 0.14), 4, 2, Color(1, 1, 1, 1))
		_marker_mesh = b.build(null, false, true)
	return _marker_mesh


func activate(r: StringName, at: Vector3, yaw: float, marker_color := Color.WHITE) -> void:
	role = r
	active = true
	visible = true
	home = at
	global_position = at
	_yaw = yaw
	rotation.y = yaw
	state = &"idle"
	freed = false
	_t = 0.0
	_wait = randf_range(0.5, 3.0)
	_goal = at
	_kneel = r == &"hostage"
	if _marker != null:
		_marker.visible = r != &"civilian"
		_marker_own.albedo_color = Color(marker_color.r * 1.5, marker_color.g * 1.5, marker_color.b * 1.5)
	if _body != null:
		_body.scale = Vector3(1.0, 0.62 if _kneel else 1.0, 1.0)
		_body.position = Vector3.ZERO


func deactivate() -> void:
	active = false
	visible = false
	spots.clear()
	state = &"idle"


## Gunfire or an explosion near: civilians run for the spot farthest from it and crouch there. Vendors duck behind the counter (stay), hostages stay bound.
func flee_from(pos: Vector3) -> void:
	if not active or role != &"civilian" or state == &"freed":
		return
	var best := global_position
	var far := -1.0
	for s in spots:
		var d := s.distance_to(pos)
		if d > far:
			far = d
			best = s
	_goal = best
	state = &"flee"
	_t = 0.0


## Free a hostage (the mission calls this): it stands up and runs for the exit point.
func free_up(exit_point: Vector3) -> void:
	if role != &"hostage" or freed:
		return
	freed = true
	_kneel = false
	state = &"freed"
	_goal = exit_point
	if _body != null:
		_body.scale = Vector3.ONE
	if _marker != null:
		_marker.visible = false


func tick(delta: float) -> void:
	if not active:
		return
	_t += delta
	if _marker != null and _marker.visible:
		_marker.position.y = 2.35 + sin(_t * 3.0) * 0.08
		_marker.rotation.y += delta * 1.8
	var p := global_position
	match state:
		&"idle":
			_wait -= delta
			if role == &"civilian" and _wait <= 0.0 and not spots.is_empty():
				_wait = randf_range(4.0, 9.0)
				if randf() < 0.5:
					_goal = spots[randi() % spots.size()]
					state = &"wander"
			if role == &"vendor":
				_face_player(delta)
			elif role == &"civilian":
				_yaw += sin(_t * 0.4 + home.x) * delta * 0.15
		&"wander":
			if _walk_to(delta, WALK):
				state = &"idle"
				_wait = randf_range(3.0, 8.0)
		&"flee":
			if _walk_to(delta, RUN):
				state = &"cower"
				_wait = 5.0
				if _body != null:
					_body.scale = Vector3(1.0, 0.7, 1.0)
		&"cower":
			_wait -= delta
			if _wait <= 0.0:
				state = &"idle"
				_wait = 2.0
				if _body != null:
					_body.scale = Vector3.ONE
		&"freed":
			if _walk_to(delta, RUN * 0.8) and p.distance_to(_goal) < 0.8:
				state = &"idle"
	rotation.y = lerp_angle(rotation.y, _yaw, minf(1.0, TURN * delta))
	if _body != null and state in [&"wander", &"flee", &"freed"]:
		_body.position.y = absf(sin(_t * (14.0 if state != &"wander" else 7.0))) * 0.035
		_body.rotation.z = sin(_t * (14.0 if state != &"wander" else 7.0)) * 0.05
	elif _body != null:
		_body.rotation.z = 0.0
		_body.position.y = sin(_t * 1.6) * 0.008 if not _kneel else 0.0


func _face_player(delta: float) -> void:
	var pl := Game.player
	if not is_instance_valid(pl):
		return
	var d := pl.global_position - global_position
	if d.length() < 9.0:
		_yaw = atan2(-d.x, -d.z)


## One kinematic step toward the goal; true on arrival. A blocked step slides per axis and the person gives up (arrives) when stuck.
func _walk_to(delta: float, speed: float) -> bool:
	var p := global_position
	var d := Vector3(_goal.x - p.x, 0.0, _goal.z - p.z)
	var dist := d.length()
	if dist < 0.25:
		return true
	var dir := d / dist
	var step := minf(speed * delta, dist)
	var nx := p.x + dir.x * step
	var nz := p.z + dir.z * step
	var radius := 0.3
	var blocked_x := InteriorGameplay.blocks(Vector3(nx + signf(dir.x) * radius, 1.0, p.z))
	var blocked_z := InteriorGameplay.blocks(Vector3(p.x, 1.0, nz + signf(dir.z) * radius))
	if blocked_x:
		nx = p.x
	if blocked_z:
		nz = p.z
	if blocked_x and blocked_z or (nx == p.x and nz == p.z):
		return true
	_yaw = atan2(-dir.x, -dir.z)
	global_position = Vector3(nx, p.y, nz)
	return false
