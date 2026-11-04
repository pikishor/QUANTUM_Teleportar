class_name Melee
extends Node
## Melee system of the player (a child of the Player, `player.melee`). Action `melee` (N, middle mouse, touch MELEE): tap = LIGHT, hold = HEAVY. Three taps inside COMBO_WINDOW
## chain light, light, FINISHER (the finisher launches). Every swing hits enemies in a cone in front of the hero (soft-locking the nearest one), staggers them, and heavy / finisher
## also LAUNCH them (a short ballistic hop; bosses only stagger). The QUANTUM BLADE is one pooled additive arc mesh shown for a fraction of a second per swing (no draw while hidden).
## Numbers are in Gear.MELEE. Runs only in the play state, so a pause freezes it. Tests wait on the counters (swings, hits, launches ...), never on frames.

signal swung(kind: StringName)
signal struck(kind: StringName, count: int)

const LAUNCH_GRAVITY := 24.0
const LAUNCH_TIME := 0.55
const BLADE_TIME := 0.2

var swings := 0
var hits := 0                        ## enemies struck in total
var launches := 0
var finishers := 0
var combo := 0                       ## 0..2: the next light swing is light, light, finisher
var last_kind: StringName = &""
var last_hits := 0                   ## enemies struck by the latest swing
var busy := 0.0                      ## seconds before the next swing is accepted

var _p: Player
var _chain := 0.0
var _down := false
var _hold := 0.0
var _heavy_fired := false
var _blade: MeshInstance3D
var _blade_mat: StandardMaterial3D
var _blade_t := 0.0
var _blade_kind := 0
var _air: Array[Dictionary] = []     ## {n: Node3D, vel: Vector3, t: float, y0: float}
static var _arc_mesh: ArrayMesh


static func tune(key: String) -> Variant:
	return Gear.MELEE[key]


func _ready() -> void:
	_p = get_parent() as Player


func _physics_process(dt: float) -> void:
	if not Game.is_playing() or _p == null:
		return
	busy = maxf(0.0, busy - dt)
	if _chain > 0.0:
		_chain -= dt
		if _chain <= 0.0:
			combo = 0
	_tick_air(dt)
	_tick_blade(dt)
	if is_instance_valid(_p.vehicle):
		return
	var want := Input.is_action_pressed(&"melee")
	if want and not _down:
		_down = true
		_hold = 0.0
		_heavy_fired = false
	elif want and _down:
		_hold += dt
		if _hold >= float(tune("heavy_hold")) and not _heavy_fired:
			_heavy_fired = true
			heavy()
	elif not want and _down:
		_down = false
		if not _heavy_fired:
			light()


## One light swing of the chain (the third in a row is the finisher). Returns false while the previous swing is still going.
func light() -> bool:
	if busy > 0.0:
		return false
	var kind: StringName = &"finisher" if combo >= 2 else &"light"
	combo = 0 if kind == &"finisher" else combo + 1
	_chain = float(tune("combo_window"))
	return _swing(kind)


func heavy() -> bool:
	if busy > 0.0:
		return false
	combo = 0
	_chain = 0.0
	return _swing(&"heavy")


func _swing(kind: StringName) -> bool:
	if _p == null or not Game.is_playing():
		return false
	var k := Gear.KINDS.find(kind)
	busy = float(tune("%s_time" % kind))
	swings += 1
	last_kind = kind
	if kind == &"finisher":
		finishers += 1
	_p.energy = maxf(0.0, _p.energy - HeroPower.cost(float((tune("energy") as Array)[k])))
	if _p.cover != null:
		_p.cover.strike = 1.0
	var target := _soft_lock(kind)
	if target != null:
		var to := target.global_position - _p.global_position
		_p.yaw = PlayerUtil.yaw_of(Vector3(to.x, 0.0, to.z).normalized())
	_blade_show(k)
	swung.emit(kind)
	Sfx.play(&"hit")
	last_hits = _resolve(kind, k)
	hits += last_hits
	if last_hits > 0:
		FX.shake(0.12 + 0.12 * k)
		struck.emit(kind, last_hits)
	return true


func _forward() -> Vector3:
	return Vector3(-sin(_p.yaw), 0.0, -cos(_p.yaw))


func _reach(kind: StringName) -> float:
	return float(tune("heavy_reach" if kind != &"light" else "reach"))


func _living() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group(&"enemy"):
		var e := n as Node3D
		if e != null and is_instance_valid(e) and e.is_inside_tree() and not bool(e.get(&"dead")):
			out.append(e)
	return out


## The nearest enemy in reach on the front half: the swing turns to it.
func _soft_lock(kind: StringName) -> Node3D:
	var best: Node3D
	var best_d := _reach(kind) + 0.6
	var f := _forward()
	for e in _living():
		var to := e.global_position - _p.global_position
		var flat := Vector3(to.x, 0.0, to.z)
		var d := flat.length()
		if d < best_d and absf(to.y) < 2.2 and (d < 0.4 or f.dot(flat / d) > 0.2):
			best = e
			best_d = d
	return best


func _resolve(kind: StringName, k: int) -> int:
	var f := _forward()
	var n := 0
	var dmg := float(tune(String(kind))) * HeroPower.f("dmg")
	var power := float((tune("stagger") as Array)[k])
	var lift := float((tune("launch") as Array)[k])
	var reach := _reach(kind)
	for e in _living():
		var to := e.global_position - _p.global_position
		var flat := Vector3(to.x, 0.0, to.z)
		var d := flat.length()
		if d > reach + 0.4 or absf(to.y) > 2.2:
			continue
		if d > 0.4 and f.dot(flat / d) < float(tune("cone")):
			continue
		var dir := f if d < 0.4 else flat / d
		n += 1
		if e.has_method(&"damage"):
			e.call(&"damage", TestMode.damage(dmg), kind != &"light")
		if bool(e.get(&"dead")):
			continue
		if e.has_method(&"stagger"):
			e.call(&"stagger", power)
		if lift > 0.0:
			launch(e, dir, lift)
		FX.burst(e.global_position + Vector3(0.0, 1.1, 0.0), Color(0.55, 0.9, 1.0) if kind != &"finisher" else Color(0.95, 0.5, 1.0), 5 + 3 * k, 5.0, 0.3, 3.0)
	return n


## Throws an enemy away from the hero: a short ballistic hop; it cannot think meanwhile (disable). Bosses are only staggered.
func launch(e: Node3D, dir: Vector3, speed: float) -> bool:
	if EnemyTypes.TYPES.has(e.get(&"type")) and bool((EnemyTypes.TYPES[e.get(&"type")] as Dictionary).get("boss", false)):
		return false
	for a in _air:
		if a["n"] == e:
			return false
	if e.has_method(&"disable"):
		e.call(&"disable", LAUNCH_TIME + 0.25)
	_air.append({"n": e, "vel": dir * speed + Vector3.UP * speed * 0.45, "t": LAUNCH_TIME, "y0": e.global_position.y})
	launches += 1
	return true


func launched_count() -> int:
	return _air.size()


func _tick_air(dt: float) -> void:
	var i := _air.size() - 1
	while i >= 0:
		var a: Dictionary = _air[i]
		var e := a["n"] as Node3D
		a["t"] = float(a["t"]) - dt
		if e == null or not is_instance_valid(e) or not e.is_inside_tree() or float(a["t"]) <= 0.0:
			_air.remove_at(i)
			i -= 1
			continue
		var v: Vector3 = a["vel"]
		v.y -= LAUNCH_GRAVITY * dt
		a["vel"] = v
		var step := v * dt
		var from := e.global_position + Vector3(0.0, 1.0, 0.0)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(step.x, 0.0, step.z).normalized() * (Vector3(step.x, 0.0, step.z).length() + 0.5), Game.L_WORLD)
		if not e.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			v.x = 0.0
			v.z = 0.0
			a["vel"] = v
			step.x = 0.0
			step.z = 0.0
		var np := e.global_position + step
		np.y = maxf(np.y, float(a["y0"]))
		e.global_position = np
		i -= 1


# --- quantum blade --------------------------------------------------------------------------------------------------

static func arc_mesh() -> ArrayMesh:
	if _arc_mesh != null:
		return _arc_mesh
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var steps := 14
	for i in steps + 1:
		var u := float(i) / float(steps)
		var a := lerpf(-1.15, 1.15, u)
		var fade := sin(u * PI)
		var dir := Vector3(sin(a), 0.0, -cos(a))
		verts.append(dir * 0.7)
		cols.append(Color(1, 1, 1, 0.0))
		verts.append(dir * 2.0)
		cols.append(Color(1, 1, 1, 0.85 * fade))
	for i in steps:
		var b := i * 2
		idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	_arc_mesh = ArrayMesh.new()
	_arc_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _arc_mesh


func _blade_show(k: int) -> void:
	if _blade == null:
		_blade = MeshInstance3D.new()
		_blade.name = "QuantumBlade"
		_blade.mesh = arc_mesh()
		_blade.top_level = true
		_blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_blade_mat = StandardMaterial3D.new()
		_blade_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blade_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_blade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blade_mat.vertex_color_use_as_albedo = true
		_blade_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_blade_mat.disable_receive_shadows = true
		_blade.material_override = _blade_mat
		_blade.visible = false
		add_child(_blade)
	_blade_kind = k
	_blade_t = BLADE_TIME
	_blade_mat.albedo_color = [Color(0.4, 0.95, 1.0), Color(0.6, 0.7, 1.0), Color(1.0, 0.5, 1.0)][k]
	_blade.visible = true
	_blade_place(0.0)


func _blade_place(u: float) -> void:
	var sweep := lerpf(0.9, -0.9, u)                  ## the arc swings across the front
	var tilt: float = [0.0, 0.7, 0.25][_blade_kind]
	var s: float = [1.0, 1.25, 1.6][_blade_kind]
	var b := Basis(Vector3.UP, _p.yaw + sweep) * Basis(Vector3.FORWARD, tilt) * Basis.from_scale(Vector3(s, s, s))
	_blade.global_transform = Transform3D(b, _p.global_position + Vector3(0.0, 1.15, 0.0))


func _tick_blade(dt: float) -> void:
	if _blade == null or not _blade.visible:
		return
	_blade_t -= dt
	if _blade_t <= 0.0:
		_blade.visible = false
		return
	_blade_place(1.0 - _blade_t / BLADE_TIME)
	_blade_mat.albedo_color.a = clampf(_blade_t / BLADE_TIME * 1.6, 0.0, 1.0)


func blade_visible() -> bool:
	return _blade != null and _blade.visible
