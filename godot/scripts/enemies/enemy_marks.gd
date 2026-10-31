class_name EnemyMarks
extends Node3D
## Readability layer of the enemies, TWO MultiMesh draws for ALL enemies together (at most 2 draw calls, none when nobody is in view range) and no light:
##  * halo: a hostile-colour rim ring and glow around every body (brighter when aware, swelling and pulsing while an attack charges, a flash on hits, a shock ring on
##    death) plus a muzzle flare that swells as a shot is charged (the telegraph, 0.3-0.5 s before bolts and bursts);
##  * aim line: a thin beam from the muzzle towards the target while a shot is charged, so the player can see where it comes from and dodge;
##  * health bar: a small floating bar, only on enemies that were damaged in the last BAR_SECONDS, drawn larger with distance so it stays readable at 25 m.
## The rings and the bars are ONE draw (the same MultiMesh `halos`, bars appended after the rings, shader mode 3); the aim lines are a box mesh and keep their own draw.
## The EnemyManager owns one and calls refresh() each frame. Enemies feed it through Drone.threat_charge(), Drone.mark_size(), Drone.muzzle_world(), Drone.aim_point().

const CAPACITY := 16
const HALO_SHADER := preload("res://assets/shaders/fx_threat.gdshader")
const LINE_SHADER := preload("res://assets/shaders/fx_aimline.gdshader")
const FAR := 90.0                       ## no marks beyond this distance (metres)

var halos: MultiMesh                     ## rings, flares, death rings, then the health bars (one draw)
var lines: MultiMesh
var ring_count := 0                      ## rings / flares / death rings of the last refresh (the first `ring_count` instances of `halos`)
var bar_count := 0                       ## health bars of the last refresh (the next `bar_count` instances)
var _halo_node: MultiMeshInstance3D
var _line_node: MultiMeshInstance3D
var _bar_xf: Array[Transform3D] = []     ## bars of this refresh, written behind the rings once their number is known (no allocation per frame)
var _bar_col := PackedColorArray()
var _bar_hp := PackedFloat32Array()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	halos = _make(quad, HALO_SHADER, CAPACITY * 4, "Halos")
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.06, 1.0)
	lines = _make(box, LINE_SHADER, CAPACITY, "AimLines")
	_bar_xf.resize(CAPACITY)
	_bar_col.resize(CAPACITY)
	_bar_hp.resize(CAPACITY)


func _make(mesh: Mesh, shader: Shader, count: int, node_name: String) -> MultiMesh:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	node.material_override = mat
	node.custom_aabb = AABB(Vector3(-600.0, -10.0, -600.0), Vector3(1200.0, 200.0, 1200.0))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return mm


## Draw the marks of every active enemy in `list` (EnemyManager.list). Cheap: at most CAPACITY enemies, a handful of instance writes each.
func refresh(list: Array[Drone]) -> void:
	var cam := Game.camera
	if not is_instance_valid(cam) or halos == null:
		return
	var cpos := cam.global_position
	var hn := 0
	var ln := 0
	var bn := 0
	var n := 0
	for d in list:
		if not d.active or not d.visible:
			continue
		n += 1
		if n > CAPACITY:
			break
		var c := d.center()
		var to_cam := cpos - c
		var dist := to_cam.length()
		if dist > FAR or dist < 0.5:
			continue
		var col := d.mark_color()
		var size := d.mark_size()
		var toward := to_cam / dist
		if d.dead:
			var t := d.death_progress()
			if t >= 1.0:
				continue
			halos.set_instance_transform(hn, Transform3D(Basis.from_scale(Vector3.ONE * size * (1.0 + 0.8 * t)), c + toward * minf(size * 0.3, dist * 0.5)))
			halos.set_instance_color(hn, col)
			halos.set_instance_custom_data(hn, Color(0.0, 1.0, t, 2.0))
			hn += 1
			continue
		var charge := d.threat_charge()
		# the ring floats a little in front of the body (towards the camera) so the quad never sinks into the body or the street
		var at := c + toward * minf(size * 0.28, dist * 0.5)
		halos.set_instance_transform(hn, Transform3D(Basis.from_scale(Vector3.ONE * size), at))
		halos.set_instance_color(hn, col)
		halos.set_instance_custom_data(hn, Color(charge, 1.0 if d.aware else 0.0, d.hit_flash(), 0.0))
		hn += 1
		if charge > 0.02:
			var m := d.muzzle_world()
			var fs := (0.7 + 1.5 * charge) * (1.0 + dist * 0.025)
			halos.set_instance_transform(hn, Transform3D(Basis.from_scale(Vector3.ONE * fs), m + (cpos - m).normalized() * 0.15))
			halos.set_instance_color(hn, col)
			halos.set_instance_custom_data(hn, Color(charge, 1.0, 0.0, 1.0))
			hn += 1
			if d.shows_aim_line() and ln < lines.instance_count:
				var tgt := d.aim_point()
				var dir := tgt - m
				var len := dir.length()
				if len > 1.0:
					dir /= len
					var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
					var width := 0.55 + dist * 0.02                     # a thin line stays readable at 25 m
					var b := Basis.looking_at(dir, up) * Basis.from_scale(Vector3(width, width, minf(len, 60.0)))
					lines.set_instance_transform(ln, Transform3D(b, m + dir * minf(len, 60.0) * 0.5))
					lines.set_instance_color(ln, col)
					lines.set_instance_custom_data(ln, Color(charge, 0.0, 0.0, 0.0))
					ln += 1
		var bt := d.bar_time()
		if bt > 0.0 and bn < CAPACITY:
			var w := clampf(0.5 + dist * 0.11, 1.5, 3.4) * (1.0 if d.max_hp < 150.0 else 1.25)
			var top := d.global_position + Vector3(0.0, d.center_y + d.radius * (1.0 if d.type != &"operative" else 1.25) + 0.45 + dist * 0.012, 0.0)
			_bar_xf[bn] = Transform3D(Basis.from_scale(Vector3(w, w * 0.125, w)), top)         # the unit quad stretched to the 8:1 plate
			_bar_col[bn] = col
			_bar_hp[bn] = clampf(d.hp / d.max_hp, 0.0, 1.0)
			bn += 1
	ring_count = hn
	bar_count = bn
	for i in bn:                                                       # the bars follow the rings in the same MultiMesh (shader mode 3)
		halos.set_instance_transform(hn + i, _bar_xf[i])
		halos.set_instance_color(hn + i, _bar_col[i])
		halos.set_instance_custom_data(hn + i, Color(_bar_hp[i], 0.0, 0.0, 3.0))
	halos.visible_instance_count = hn + bn
	lines.visible_instance_count = ln


func clear() -> void:
	ring_count = 0
	bar_count = 0
	if halos != null:
		halos.visible_instance_count = 0
		lines.visible_instance_count = 0
