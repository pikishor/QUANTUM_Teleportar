class_name Gadgets
extends Node
## The gadget slot of the player (a child of the Player, `player.gadgets`). Action `gadget` (K, touch GADGET) uses the equipped Gear.gadget:
##   scanner  SCANNER PULSE: a ring sweeps out; every enemy in range is marked through walls for a few seconds (one additive no-depth-test MultiMesh = one draw while shown).
##   drone    DRONE BUDDY: a turret drone follows the hero and shoots the nearest enemy it can see, for DRONE life seconds.
##   grapple  GRAPPLE HOOK: a hook along the crosshair; on an anchor in range the hero is pulled there (teleport after a short beam), costing energy.
## Each has a cooldown (Gear.GADGETS) and an energy cost scaled by HeroPower. Only ticks in the play state; counters are what tests wait on. Nodes are created on first use.

signal used(id: StringName)

const MARKS := 24
const HOOK_TIME := 0.14

var pulses := 0
var marked := 0                          ## enemies marked by the latest pulse
var drone_shots := 0
var drone_hits := 0
var hooks := 0
var drone_left := 0.0                    ## seconds the drone buddy still lives (0 = none)
var scan_left := 0.0                     ## seconds the scan marks still show
var last_denied: StringName = &""

var _p: Player
var _cd: Dictionary = {}                 ## id -> seconds left
var _was := false
var _ring: MeshInstance3D
var _ring_t := 0.0
var _marks: MultiMeshInstance3D
var _scan_pos := Vector3.ZERO
var _drone: Node3D
var _drone_t := 0.0
var _drone_fire := 0.0
var _beam: MeshInstance3D
var _hook_t := 0.0
var _hook_to := Vector3.ZERO


func _ready() -> void:
	_p = get_parent() as Player
	Game.new_game.connect(reset)
	Game.respawn.connect(reset)


func reset() -> void:
	_cd.clear()
	drone_left = 0.0
	scan_left = 0.0
	_hook_t = 0.0
	if _drone != null:
		_drone.visible = false
	if _marks != null:
		_marks.visible = false
	if _beam != null:
		_beam.visible = false


func cooldown(id: StringName) -> float:
	return float(_cd.get(id, 0.0))


func ready_frac(id: StringName) -> float:
	if not Gear.GADGETS.has(id):
		return 0.0
	return 1.0 - clampf(cooldown(id) / float(Gear.GADGETS[id]["cooldown"]), 0.0, 1.0)


func drone_alive() -> bool:
	return _drone != null and _drone.visible and drone_left > 0.0


func marks_visible() -> bool:
	return _marks != null and _marks.visible


func _physics_process(dt: float) -> void:
	if not Game.is_playing() or _p == null:
		return
	for id: StringName in _cd.keys():
		_cd[id] = maxf(0.0, float(_cd[id]) - dt)
	var want := Input.is_action_pressed(&"gadget") and not is_instance_valid(_p.vehicle)
	if want and not _was:
		use()
	_was = want
	_tick_ring(dt)
	_tick_marks(dt)
	_tick_drone(dt)
	_tick_hook(dt)


## Uses `id` (the equipped gadget by default). False when empty, cooling down, short of energy or (grapple) without an anchor.
func use(id: StringName = &"") -> bool:
	if _p == null or not Game.is_playing():
		return false
	if id == &"":
		id = Gear.gadget
	if not Gear.GADGETS.has(id) or cooldown(id) > 0.0:
		return false
	var d: Dictionary = Gear.GADGETS[id]
	var cost := HeroPower.cost(float(d["energy"]))
	if _p.energy < cost:
		last_denied = id
		return false
	var ok := false
	match id:
		&"scanner":
			ok = _scan(d)
		&"drone":
			ok = _deploy_drone(d)
		&"grapple":
			ok = _fire_hook(d)
	if not ok:
		last_denied = id
		return false
	_p.energy = maxf(0.0, _p.energy - cost)
	_cd[id] = float(d["cooldown"])
	used.emit(id)
	Game.say(Gear.title(id), 0.8)
	return true


# --- scanner --------------------------------------------------------------------------------------------------------------

func _scan(d: Dictionary) -> bool:
	pulses += 1
	_scan_pos = _p.global_position
	scan_left = float(d["show"])
	_ring_t = 0.7
	if _ring == null:
		_ring = MeshInstance3D.new()
		_ring.top_level = true
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var t := TorusMesh.new()
		t.inner_radius = 0.93
		t.outer_radius = 1.0
		t.rings = 24
		t.ring_segments = 6
		_ring.mesh = t
		_ring.material_override = Gear.fx_material(Color(Gear.GADGETS[&"scanner"]["color"], 0.8))
		add_child(_ring)
	_ring.visible = true
	_ring.global_position = _scan_pos + Vector3(0.0, 0.15, 0.0)
	_ring.scale = Vector3.ONE * 0.5
	if _marks == null:
		_marks = MultiMeshInstance3D.new()
		_marks.top_level = true
		_marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var q := QuadMesh.new()
		q.size = Vector2(1.1, 1.6)
		mm.mesh = q
		mm.instance_count = MARKS
		mm.visible_instance_count = 0
		_marks.multimesh = mm
		var m := Gear.fx_material(Color(Gear.GADGETS[&"scanner"]["color"], 0.55))
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.no_depth_test = true
		m.render_priority = 5
		_marks.material_override = m
		_marks.custom_aabb = AABB(Vector3(-400, -50, -400), Vector3(800, 200, 800))
		add_child(_marks)
	_marks.visible = true
	marked = _refresh_marks()
	FX.burst(_scan_pos + Vector3(0.0, 0.3, 0.0), Color(Gear.GADGETS[&"scanner"]["color"]), 10, 8.0, 0.4, 0.0)
	return true


func _refresh_marks() -> int:
	var mm := _marks.multimesh
	var n := 0
	var radius := float(Gear.GADGETS[&"scanner"]["radius"])
	for e in Gear.living_enemies(get_tree()):
		if n >= MARKS:
			break
		if e.global_position.distance_to(_scan_pos) > radius:
			continue
		mm.set_instance_transform(n, Transform3D(Basis(), e.global_position + Vector3(0.0, 1.0, 0.0)))
		n += 1
	mm.visible_instance_count = n
	return n


func _tick_marks(dt: float) -> void:
	if scan_left <= 0.0:
		if _marks != null and _marks.visible:
			_marks.visible = false
		return
	scan_left -= dt
	if _marks != null:
		_refresh_marks()


func _tick_ring(dt: float) -> void:
	if _ring == null or not _ring.visible:
		return
	_ring_t -= dt
	if _ring_t <= 0.0:
		_ring.visible = false
		return
	var k := 1.0 - _ring_t / 0.7
	_ring.scale = Vector3.ONE * lerpf(0.5, float(Gear.GADGETS[&"scanner"]["radius"]), k)


# --- drone buddy ----------------------------------------------------------------------------------------------------------

func _deploy_drone(d: Dictionary) -> bool:
	if _drone == null:
		_drone = Node3D.new()
		_drone.top_level = true
		var body := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.22
		s.height = 0.44
		s.radial_segments = 10
		s.rings = 5
		body.mesh = s
		body.material_override = Gear.fx_material(Color(Gear.GADGETS[&"drone"]["color"], 0.95), false)
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_drone.add_child(body)
		add_child(_drone)
	_drone.visible = true
	_drone.global_position = _p.global_position + Vector3(0.6, 1.8, 0.0)
	drone_left = float(d["life"])
	_drone_fire = 0.5
	return true


func _tick_drone(dt: float) -> void:
	if _drone == null or not _drone.visible:
		return
	drone_left -= dt
	if drone_left <= 0.0:
		_drone.visible = false
		drone_left = 0.0
		FX.burst(_drone.global_position, Color(1.0, 0.85, 0.3), 8, 4.0, 0.4, 1.0)
		return
	_drone_t += dt
	var home := _p.global_position + Vector3(cos(_drone_t * 0.9) * 1.4, 2.0 + sin(_drone_t * 2.0) * 0.15, sin(_drone_t * 0.9) * 1.4)
	_drone.global_position = _drone.global_position.lerp(home, 1.0 - exp(-4.0 * dt))
	_drone_fire -= dt
	if _drone_fire > 0.0:
		return
	var d: Dictionary = Gear.GADGETS[&"drone"]
	var best: Node3D
	var best_d := float(d["range"])
	for e in Gear.living_enemies(get_tree()):
		var dist := e.global_position.distance_to(_drone.global_position)
		if dist < best_d and _clear(_drone.global_position, e.global_position + Vector3(0.0, 1.0, 0.0)):
			best = e
			best_d = dist
	if best == null:
		_drone_fire = 0.15
		return
	_drone_fire = float(d["interval"])
	drone_shots += 1
	var tgt := best.global_position + Vector3(0.0, 1.0, 0.0)
	FX.tracer(_drone.global_position, tgt, Color(1.0, 0.85, 0.3))
	if best.has_method(&"damage"):
		best.call(&"damage", TestMode.damage(float(d["damage"]) * HeroPower.f("dmg")), false)
		drone_hits += 1


func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, Game.L_WORLD)
	return _p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# --- grapple-teleport hook ------------------------------------------------------------------------------------------------

func _fire_hook(d: Dictionary) -> bool:
	var aim: Dictionary = _p.get_aim()
	var origin: Vector3 = aim["origin"]
	var dir: Vector3 = aim["dir"]
	var reach := float(d["range"])
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * (reach + origin.distance_to(_p.global_position)), Game.L_WORLD | Game.L_VEHICLE | Game.L_ENEMY)
	var hit := _p.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var at: Vector3 = hit["position"]
	if at.distance_to(_p.global_position) > reach:
		return false
	var n: Vector3 = hit["normal"]
	var dest := at + n * 0.9
	if absf(n.y) < 0.5:
		dest.y = at.y - 0.9 if at.y > _p.global_position.y + 2.4 else at.y                     # a wall: stand at the anchor height (a ledge) rather than hang
	_hook_to = dest
	_hook_t = HOOK_TIME
	if _beam == null:
		_beam = FX.make_beam(Color(Gear.GADGETS[&"grapple"]["color"], 0.9), 0.07)
		_beam.top_level = true
		add_child(_beam)
	FX.place_beam(_beam, _p.global_position + Vector3(0.0, 1.3, 0.0), at)
	return true


func _tick_hook(dt: float) -> void:
	if _hook_t <= 0.0:
		if _beam != null and _beam.visible:
			_beam.visible = false
		return
	_hook_t -= dt
	if _beam != null:
		FX.place_beam(_beam, _p.global_position + Vector3(0.0, 1.3, 0.0), _hook_to)
	if _hook_t <= 0.0:
		hooks += 1
		_p.teleport_to(_hook_to)
		if _beam != null:
			_beam.visible = false
