class_name EnemyMarks
extends Node3D
## Readability layer of the enemies, TWO MultiMesh draws for ALL enemies together (at most 2 draw calls, none when nobody is in view range) and no light:
##  * halo: a THIN, crisp hostile-colour ring around every body (dashed and dim when unaware, solid and brighter when aware, swelling and pulsing while an attack charges, a flash on hits, a shock ring on
##    death) plus a muzzle flare that swells as a shot is charged (the telegraph, 0.3-0.5 s before bolts and bursts);
##  * aim line: a thin beam from the muzzle towards the target while a shot is charged, so the player can see where it comes from and dodge;
##  * health bar: a small floating bar, only on enemies that were damaged in the last BAR_SECONDS, drawn larger with distance so it stays readable at 25 m.
## Rings are a FALLBACK now: an enemy that is on screen, within RING_RANGE and not hidden behind the world is readable by its own silhouette and emissive tell (EnemyTells, the
## shield plate, the eyes), so it gets no ring; the ring stays for off-screen, occluded (a cached world ray, one per enemy every OCC_EVERY frames) and distant (small) enemies and for death shock rings.
## The rings and the bars are ONE draw (the same MultiMesh `halos`, bars appended after the rings, shader mode 3); the aim lines are a box mesh and keep their own draw.
## The EnemyManager owns one and calls refresh() each frame. Enemies feed it through Drone.threat_charge(), Drone.mark_size(), Drone.muzzle_world(), Drone.aim_point().

const CAPACITY := 16
const HALO_SHADER := preload("res://assets/shaders/fx_threat.gdshader")
const LINE_SHADER := preload("res://assets/shaders/fx_aimline.gdshader")
const FAR := 90.0                       ## no marks beyond this distance (metres)
const RING_SQUAD := 14.0                ## an aware encounter trooper (the director's patrol) gets its ring from this far: at 15-40 m a dark thin figure is a few pixels on a phone (slice fight renders)
const RING_RANGE := 40.0                ## beyond this the body is a few pixels: the ring returns
const MARK_NEAR_K := 0.34               ## a ring / flare is at most this fraction of its distance to the camera (about 20 degrees of view)
const MARK_MIN_DIST := 3.5              ## no fallback ring on an enemy closer than this (it is right there, readable by itself)
const OCC_EVERY := 6                    ## frames between the occlusion rays of one enemy

var halos: MultiMesh                     ## rings, flares, death rings, then the health bars (one draw)
var lines: MultiMesh
var ring_count := 0                      ## rings / flares / death rings of the last refresh (the first `ring_count` instances of `halos`)
var bar_count := 0                       ## health bars of the last refresh (the next `bar_count` instances)
var _halo_node: MultiMeshInstance3D
var _line_node: MultiMeshInstance3D
var _bar_xf: Array[Transform3D] = []     ## bars of this refresh, written behind the rings once their number is known (no allocation per frame)
var _bar_col := PackedColorArray()
var _bar_hp := PackedFloat32Array()
var _pip_xf: Array[Transform3D] = []     ## alert pips of this refresh (Drone.alert_pip: 1 suspicious, 2 searching, 3 alerted)
var _pip_col := PackedFloat32Array()
var _occluded := PackedByteArray()       ## per list slot: 1 = the world is between the camera and that enemy (cached)
var _tick := 0
var _ray := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	halos = _make(quad, HALO_SHADER, CAPACITY * 5, "Halos")
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.06, 1.0)
	lines = _make(box, LINE_SHADER, CAPACITY, "AimLines")
	_bar_xf.resize(CAPACITY)
	_bar_col.resize(CAPACITY)
	_bar_hp.resize(CAPACITY)
	_pip_xf.resize(CAPACITY)
	_pip_col.resize(CAPACITY)
	_occluded.resize(CAPACITY)
	_ray.collision_mask = Game.L_WORLD
	_ray.collide_with_areas = false


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
	node.custom_aabb = AABB(Vector3(-1300.0, -10.0, -1300.0), Vector3(2600.0, 200.0, 2600.0))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return mm


## Draw the marks of every active enemy in `list` (EnemyManager.list). Cheap: at most CAPACITY enemies, a handful of instance writes each.
func refresh(list: Array[Drone]) -> void:
	var cam := Game.camera
	if not is_instance_valid(cam) or halos == null:
		return
	var cpos := cam.global_position
	_tick += 1
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	var hn := 0
	var ln := 0
	var bn := 0
	var pn := 0
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
		var size := minf(d.mark_size(), dist * MARK_NEAR_K)     # a ring around an enemy at arm's length is a screen-wide arc: it never grows past a third of the distance to the lens
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
		if (_tick + n) % OCC_EVERY == 0 and space != null:                 # the cached occlusion test (staggered per enemy)
			_ray.from = cpos
			_ray.to = c
			_occluded[n - 1] = 0 if space.intersect_ray(_ray).is_empty() else 1
		var needs_ring := (dist > (RING_SQUAD if d.reinforce and d.aware else RING_RANGE) or _occluded[n - 1] == 1 or not cam.is_position_in_frustum(c)) and dist > MARK_MIN_DIST
		# the ring floats a little in front of the body (towards the camera) so the quad never sinks into the body or the street
		if needs_ring:
			var at := c + toward * minf(size * 0.28, dist * 0.5)
			halos.set_instance_transform(hn, Transform3D(Basis.from_scale(Vector3.ONE * size), at))
			halos.set_instance_color(hn, col)
			halos.set_instance_custom_data(hn, Color(charge, 1.0 if d.aware else 0.0, d.hit_flash(), 0.0))
			hn += 1
		if charge > 0.02:
			var m := d.muzzle_world()
			var fs := (0.7 + 1.5 * charge) * (1.0 + dist * 0.025)
			fs = minf(fs, maxf(0.12, cpos.distance_to(m) * MARK_NEAR_K))       # a muzzle flare next to the lens must not flash the whole screen
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
		var pip := d.alert_pip()
		if pip > 0.0 and pn < CAPACITY and dist < FAR * 0.7:
			var ps := clampf(0.7 + dist * 0.045, 0.9, 2.6)
			_pip_xf[pn] = Transform3D(Basis.from_scale(Vector3.ONE * ps), d.global_position + Vector3(0.0, d.center_y + d.radius * (1.0 if d.type != &"operative" else 1.25) + 0.6 + ps * 0.5, 0.0))
			_pip_col[pn] = float(pip)
			pn += 1
		var bt := d.bar_time()
		if bt > 0.0 and bn < CAPACITY:
			var w := clampf(0.4 + dist * 0.045, 0.9, 2.2) * (1.0 if d.max_hp < 150.0 else 1.2)       # about a body wide near, a little wider far (a plate wider than two bodies read as a floating pink rectangle)
			var top := d.global_position + Vector3(0.0, d.center_y + d.radius * (1.0 if d.type != &"operative" else 1.25) + 0.45 + dist * 0.012, 0.0)
			_bar_xf[bn] = Transform3D(Basis.from_scale(Vector3(w, w * 0.125, w)), top)         # the unit quad stretched to the 8:1 plate
			_bar_col[bn] = col
			_bar_hp[bn] = clampf(d.hp / d.max_hp, 0.0, 1.0)
			bn += 1
	ring_count = hn
	bar_count = bn
	for i in pn:                                                       # the alert pips (stealth, shader mode 4) follow the bars in the same MultiMesh
		halos.set_instance_transform(hn + bn + i, _pip_xf[i])
		halos.set_instance_color(hn + bn + i, Color.WHITE)
		halos.set_instance_custom_data(hn + bn + i, Color(_pip_col[i], 0.0, 0.0, 4.0))
	for i in bn:                                                       # the bars follow the rings in the same MultiMesh (shader mode 3)
		halos.set_instance_transform(hn + i, _bar_xf[i])
		halos.set_instance_color(hn + i, _bar_col[i])
		halos.set_instance_custom_data(hn + i, Color(_bar_hp[i], 0.0, 0.0, 3.0))
	halos.visible_instance_count = hn + bn + pn
	lines.visible_instance_count = ln


func clear() -> void:
	ring_count = 0
	bar_count = 0
	if halos != null:
		halos.visible_instance_count = 0
		lines.visible_instance_count = 0
