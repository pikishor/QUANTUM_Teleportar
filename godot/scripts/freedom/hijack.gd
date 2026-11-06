class_name Hijack
extends Node
## Taking a vehicle in the open world (GTA style): the hero's entry ghost slides to the door, a driver who was at the wheel is thrown out on the kerb side, tumbles, gets up and runs.
## Visual only (two pooled driver bodies, one pooled entry ghost, a few FX bursts): nothing here blocks the entry itself, VehicleManager.enter() has already put the hero in the car.
## `Hijack.current` is read by the VehicleManager; without it (no Freedom node, a bare test) entering simply works as before.

const BODY_COLORS: Array[Color] = [Color(0.55, 0.42, 0.3), Color(0.3, 0.38, 0.5), Color(0.5, 0.3, 0.34), Color(0.36, 0.46, 0.36)]
const POOL := 2
const GHOST_TIME := 0.26
const THROW_SIDE := 4.2
const THROW_UP := 4.6
const GRAVITY := 18.0
const DOWN_TIME := 0.9               ## s lying on the street
const RUN_TIME := 4.0                ## s running away, then the body shrinks into the street (released)
const RUN_SPEED := 5.0

## Names the prompt and the toast use.
const NAMES := {
	&"sedan": "SEDAN", &"sport": "SPORT CAR", &"suv": "SUV", &"bike": "BIKE", &"hover": "HOVER CAR", &"hoverbike": "HOVER-BIKE", &"taxi": "TAXI", &"wagon": "WAGON", &"van": "VAN",
	&"truck": "TRUCK", &"rover": "ROVER", &"skiff": "SKIFF", &"bus": "BUS", &"interceptor": "PATROL CAR", &"ambulance": "AMBULANCE", &"qbike": "QUANTUM BIKE", &"vael_patrol": "VAEL PATROL",
}

static var current: Hijack

var hijacks := 0                     ## drivers thrown out so far (tests wait on this)
var entries := 0                     ## entry animations played (hijacks and plain entries)
var last_kind: StringName = &""
var _drivers: Array[Dictionary] = [] ## {node: Node3D, state: fly|down|run, t, vel, dir}
var _free: Array[Node3D] = []
var _ghost: MeshInstance3D
var _ghost_t := -1.0
var _ghost_from := Vector3.ZERO
var _ghost_to := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


static func vehicle_name(kind: StringName) -> String:
	return str(NAMES.get(kind, "VEHICLE"))


func _ready() -> void:
	name = "Hijack"
	current = self
	_rng.seed = 41
	Game.respawn.connect(reset)
	Game.new_game.connect(reset)


func _exit_tree() -> void:
	if current == self:
		current = null


func reset() -> void:
	for d in _drivers:
		_park(d["node"] as Node3D)
	_drivers.clear()
	_ghost_t = -1.0
	if _ghost != null:
		_ghost.visible = false


## Live ejected drivers (still on screen).
func ejected_live() -> int:
	return _drivers.size()


## The hero took `car` from `from` (his position before the entry). `driver`: somebody was at the wheel (traffic, a chasing patrol): he is thrown out.
func on_enter(car: Vehicle, from: Vector3, driver: bool) -> void:
	if car == null or not is_instance_valid(car):
		return
	last_kind = car.kind
	entries += 1
	var side := 1.0 if (from - car.global_position).dot(car.right()) >= 0.0 else -1.0
	var door := car.global_position + car.right() * side * (float(car.spec["wid"]) * 0.5 + 0.25) + Vector3(0.0, 0.0, 0.0)
	_ghost_from = from + Vector3(0.0, 0.9, 0.0)
	_ghost_to = door + Vector3(0.0, 0.9, 0.0)
	_ghost_t = 0.0
	_ensure_ghost()
	_ghost.visible = true
	_ghost.global_position = _ghost_from
	var cyan := Color(0.35, 0.95, 1.0)
	FX.burst(door + Vector3(0.0, 1.0, 0.0), cyan, 8, 3.0, 0.35, 0.0)
	if not driver:
		return
	hijacks += 1
	FX.burst(door + Vector3(0.0, 1.1, 0.0), Color(1.0, 0.8, 0.45), 12, 5.0, 0.4, 6.0)
	FX.shake(0.22)
	Sfx.play_at(&"hit", door, -4.0)
	var n := _take()
	if n == null:
		return
	var vel := car.right() * side * THROW_SIDE + car.forward() * car.speed * 0.35 + Vector3(0.0, THROW_UP, 0.0)
	n.global_position = door + Vector3(0.0, 0.5, 0.0)
	n.rotation = Vector3(0.0, car.heading, 0.0)
	n.scale = Vector3.ONE
	n.visible = true
	var col := BODY_COLORS[_rng.randi() % BODY_COLORS.size()]
	_tint(n, Color(0.75, 1.0, 0.45) if car.patrol else col)
	_drivers.append({"node": n, "state": &"fly", "t": 0.0, "vel": vel, "dir": car.right() * side + car.forward() * 0.4})


func _physics_process(dt: float) -> void:
	if _ghost_t >= 0.0:
		_ghost_t += dt
		var k := clampf(_ghost_t / GHOST_TIME, 0.0, 1.0)
		_ghost.global_position = _ghost_from.lerp(_ghost_to, k) + Vector3(0.0, sin(k * PI) * 0.35, 0.0)
		_ghost.scale = Vector3.ONE * (1.0 - 0.7 * k)
		if k >= 1.0:
			_ghost_t = -1.0
			_ghost.visible = false
	if not Game.is_playing():
		return
	var i := _drivers.size() - 1
	while i >= 0:
		var d: Dictionary = _drivers[i]
		if _step_driver(d, dt):
			_park(d["node"] as Node3D)
			_drivers.remove_at(i)
		i -= 1


func _step_driver(d: Dictionary, dt: float) -> bool:
	var n := d["node"] as Node3D
	d["t"] = float(d["t"]) + dt
	var t: float = d["t"]
	match d["state"]:
		&"fly":
			var vel: Vector3 = d["vel"]
			vel.y -= GRAVITY * dt
			n.global_position += vel * dt
			n.rotation.z += 5.0 * dt * signf(vel.x + 0.001)
			d["vel"] = vel
			if n.global_position.y <= 0.35 and vel.y < 0.0:
				n.global_position.y = 0.35
				n.rotation = Vector3(0.0, n.rotation.y, 1.45)       # lying on the street
				d["state"] = &"down"
				d["t"] = 0.0
				FX.burst(n.global_position, Color(0.55, 0.55, 0.58), 5, 2.0, 0.35, 2.0)
		&"down":
			if t >= DOWN_TIME:
				n.rotation = Vector3(0.0, atan2(-(d["dir"] as Vector3).x, -(d["dir"] as Vector3).z), 0.0)
				n.global_position.y = 0.9
				d["state"] = &"run"
				d["t"] = 0.0
		&"run":
			var dir: Vector3 = d["dir"]
			dir.y = 0.0
			n.global_position += dir.normalized() * RUN_SPEED * dt
			n.global_position.y = 0.9 + absf(sin(t * 12.0)) * 0.08
			if t >= RUN_TIME:
				return true
	return false


# --- pooled visuals ---------------------------------------------------------------------------------------------------------

func _ensure_ghost() -> void:
	if _ghost != null:
		return
	var c := CapsuleMesh.new()
	c.radius = 0.32
	c.height = 1.8
	c.radial_segments = 8
	c.rings = 2
	_ghost = MeshInstance3D.new()
	_ghost.name = "EntryGhost"
	_ghost.mesh = c
	_ghost.top_level = true
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.material_override = Gear.fx_material(Color(0.35, 0.95, 1.0, 0.55), true)
	_ghost.visible = false
	add_child(_ghost)


func _take() -> Node3D:
	if not _free.is_empty():
		return _free.pop_back()
	if _drivers.size() >= POOL:                            # all bodies busy: the oldest one is recycled
		var old: Dictionary = _drivers.pop_front()
		return old["node"] as Node3D
	var root := Node3D.new()
	root.top_level = true
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.27
	cap.height = 1.35
	cap.radial_segments = 8
	cap.rings = 2
	body.mesh = cap
	body.position = Vector3(0.0, 0.0, 0.0)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.name = "Body"
	root.add_child(body)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.16
	sph.height = 0.32
	sph.radial_segments = 8
	sph.rings = 4
	head.mesh = sph
	head.position = Vector3(0.0, 0.85, 0.0)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.name = "Head"
	root.add_child(head)
	root.visible = false
	add_child(root)
	return root


func _tint(n: Node3D, col: Color) -> void:
	for c in n.get_children():
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		var m := mi.material_override as StandardMaterial3D
		if m == null:
			m = StandardMaterial3D.new()
			m.roughness = 0.9
			mi.material_override = m
		var tint := col if mi.name == &"Body" else Color(0.78, 0.62, 0.5)
		m.albedo_color = tint
		m.emission_enabled = true                              # lit at night like the citizens (the street's fill is dim): a part of the colour glows
		m.emission = tint * 0.45


func _park(n: Node3D) -> void:
	if n == null or not is_instance_valid(n):
		return
	n.visible = false
	if not _free.has(n):
		_free.append(n)
