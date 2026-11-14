class_name AlienFx
extends Node3D
## The pooled effects of the alien world (wave 107b): telegraph RINGS on the ground (a bright circle that fills as the attack comes: slam, eruption, cloud, strike), telegraph LINES (a dive, a
## lance, a turret's aim), projectile SPRITES (acid globs, spore bolts, shock bolts) and the small dust / splash / spark bursts. Everything is pooled: nothing is allocated while playing, a
## ring is one flat mesh with an additive unshaded material, a line is one stretched box (FX.make_beam), the bursts reuse FX.burst's emitters.

const RINGS := 10
const LINES := 6
const SPRITES := 30                          ## 22 projectile slots of AlienWorld plus 8 of RosterFire (roster-2 rockets, grenades, shells)
const STREAK_SPEED := 18.0                   ## sprites that move faster than this (m/s) are drawn as streaks along their travel
const LINE_W := 0.12                         ## the box of a telegraph line is this wide (metres) at its widest ...
const LINE_MAX_DEG := 0.9                    ## ... and never wider than this many degrees of view from the camera: an aimed shot or a beam that runs on past the hero passes the lens, and a 12 cm box
                                             ## at arm's length was a screen-wide translucent sheet (owner round 2, enemy look wave 113). It also fades out when it comes within 2.5 m of the camera.

var _rings: Array[MeshInstance3D] = []
var _ring_t := PackedFloat32Array()
var _ring_life := PackedFloat32Array()
var _ring_col: Array[Color] = []
var _lines: Array[MeshInstance3D] = []
var _line_t := PackedFloat32Array()
var _line_life := PackedFloat32Array()
var _line_a: Array[Vector3] = []
var _line_b: Array[Vector3] = []
var _line_col: Array[Color] = []
var _line_k := PackedFloat32Array()         ## per line: the fade of the part that passes close to the camera 0..1
var pips: FoePips                           ## the floating health pips of the damaged roster enemies (scripts/roster/foe_pips.gd, one MultiMesh draw)
var _sprites: Array[MeshInstance3D] = []
var _sprite_on := PackedByteArray()
var _sprite_prev: Array[Vector3] = []       ## where each sprite was last frame: a fast sprite is stretched along its travel (a bolt, a rocket), a slow one stays a ball
var _next_ring := 0
var _next_line := 0
var rings_shown := 0                        ## tests: rings started
var lines_shown := 0
static var _ring_mesh: ArrayMesh = null


func _ready() -> void:
	top_level = true
	for i in RINGS:
		var m := MeshInstance3D.new()
		m.mesh = _make_ring_mesh()
		m.material_override = _mat()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		_rings.append(m)
		_ring_t.append(0.0)
		_ring_life.append(0.0)
		_ring_col.append(Color.WHITE)
	for i in LINES:
		var l := FX.make_beam(Color(1, 1, 1, 0.8), 0.12)
		l.top_level = true
		add_child(l)
		_lines.append(l)
		_line_t.append(0.0)
		_line_life.append(0.0)
		_line_a.append(Vector3.ZERO)
		_line_b.append(Vector3.ZERO)
		_line_col.append(Color.WHITE)
		_line_k.append(1.0)
	pips = FoePips.new()
	pips.name = "Pips"
	add_child(pips)
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	for i in SPRITES:
		var s := MeshInstance3D.new()
		s.mesh = sm
		var sm_mat := _mat()
		sm_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX            # a solid bright bolt (additive washed the colour out into a pale disc)
		sm_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		s.material_override = sm_mat
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.visible = false
		add_child(s)
		_sprites.append(s)
		_sprite_on.append(0)
		_sprite_prev.append(Vector3.INF)


static func _mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	m.no_depth_test = false
	return m


## A unit-radius flat ring (outer radius 1, a bright band 0.88 to 1.0) over a faint fill: scaled to the attack's radius.
static func _make_ring_mesh() -> ArrayMesh:
	if _ring_mesh != null:
		return _ring_mesh
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	var seg := 40
	v.append(Vector3.ZERO)
	c.append(Color(1, 1, 1, 0.0))
	for k in seg:
		var a := TAU * float(k) / float(seg)
		v.append(Vector3(cos(a), 0.0, sin(a)) * 0.88)
		c.append(Color(1, 1, 1, 0.26))
	for k in seg:
		var a := TAU * float(k) / float(seg)
		v.append(Vector3(cos(a), 0.0, sin(a)) * 0.88)
		c.append(Color(1, 1, 1, 0.9))
		v.append(Vector3(cos(a), 0.0, sin(a)))
		c.append(Color(1, 1, 1, 0.9))
	for k in seg:
		var k2 := (k + 1) % seg
		idx.append_array([0, 1 + k2, 1 + k])
	var base := 1 + seg
	for k in seg:
		var k2 := (k + 1) % seg
		var a0 := base + k * 2
		var a1 := base + k * 2 + 1
		var b0 := base + k2 * 2
		var b1 := base + k2 * 2 + 1
		idx.append_array([a0, b0, a1, a1, b0, b1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_ring_mesh = m
	return m


## A telegraph ring on the ground at `pos`: it brightens as `secs` run out, then goes.
func ring(pos: Vector3, radius: float, secs: float, color: Color) -> void:
	var i := _next_ring
	_next_ring = (_next_ring + 1) % RINGS
	var m := _rings[i]
	m.global_position = pos
	m.scale = Vector3(radius, 1.0, radius)
	_ring_t[i] = 0.0
	_ring_life[i] = maxf(secs, 0.1)
	_ring_col[i] = color
	(m.material_override as StandardMaterial3D).albedo_color = Color(color.r, color.g, color.b, 0.3)
	m.visible = true
	rings_shown += 1


func line(a: Vector3, b: Vector3, secs: float, color: Color) -> void:
	var i := _next_line
	_next_line = (_next_line + 1) % LINES
	_line_t[i] = 0.0
	_line_life[i] = maxf(secs, 0.1)
	_line_a[i] = a
	_line_b[i] = b
	_line_col[i] = color
	(_lines[i].material_override as StandardMaterial3D).albedo_color = Color(color.r, color.g, color.b, 0.3)
	_place_line(i, _cam_pos())
	lines_shown += 1


func _cam_pos() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_position if cam != null else Vector3.INF


## Stretches line `i` between its two points; the width follows the distance of the nearest point to the camera (a thin stripe in the view, never a sheet) and `_line_k[i]` fades the line out near the lens.
func _place_line(i: int, cam_pos: Vector3) -> void:
	var a := _line_a[i]
	var d := _line_b[i] - a
	var length := d.length()
	var l := _lines[i]
	if length < 0.001:
		l.visible = false
		return
	var wk := 1.0
	var fade := 1.0
	if cam_pos.is_finite():
		var cd := cam_pos.distance_to(Geometry3D.get_closest_point_to_segment(cam_pos, a, _line_b[i]))
		wk = clampf(cd * tan(deg_to_rad(LINE_MAX_DEG)) / LINE_W, 0.05, 1.0)
		fade = smoothstep(0.6, 2.5, cd)
	var dir := d / length
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	l.global_transform = Transform3D(Basis.looking_at(dir, up) * Basis.from_scale(Vector3(wk, wk, length)), a + d * 0.5)
	l.visible = true
	_line_k[i] = fade


## Width of line `i` in metres as placed now (tests).
func line_width(i: int) -> float:
	return LINE_W * (_lines[i].global_transform.basis.x.length())


func dust(pos: Vector3, color: Color) -> void:
	FX.burst(pos + Vector3(0.0, 0.3, 0.0), Color(color.r, color.g, color.b, 0.55), 9, 4.0, 0.9, -1.5, 5.0)


func spark(pos: Vector3, color: Color) -> void:
	FX.burst(pos, color, 6, 5.0, 0.3, 4.0, 1.3)


func splash(pos: Vector3, radius: float) -> void:
	FX.burst(pos + Vector3(0.0, 0.4, 0.0), Color(0.75, 0.92, 1.0, 0.7), 12, 6.0 * radius * 0.5, 0.8, 8.0, 3.0)


## Shows projectile sprite `i` (0 .. SPRITES - 1) at `pos`; `i` is the projectile's own slot.
func sprite(i: int, pos: Vector3, size: float, color: Color) -> void:
	if i < 0 or i >= SPRITES:
		return
	var s := _sprites[i]
	var r := size * 0.5
	var prev := _sprite_prev[i]
	var streak := false
	if prev.is_finite() and _sprite_on[i] == 1:
		var d := pos - prev
		var step := d.length()
		var speed := step * float(Engine.get_physics_ticks_per_second())
		if speed > STREAK_SPEED and step > 0.001:                # a bolt or a rocket: a bright dart along its path with the head a little ahead of the position
			var len := clampf(speed * 0.04, 0.7, 3.0)
			var dir := d / step
			var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
			s.global_transform = Transform3D(Basis.looking_at(dir, up) * Basis.from_scale(Vector3(r * 0.5, r * 0.5, len)), pos - dir * len * 0.3)
			streak = true
	if not streak:
		s.global_position = pos
		s.scale = Vector3.ONE * r                                 # `size` is the diameter in metres of the glow ball
	_sprite_prev[i] = pos
	(s.material_override as StandardMaterial3D).albedo_color = Color(color.r, color.g, color.b, 1.0).lerp(Color.WHITE, 0.3 if streak else 0.0)
	if _sprite_on[i] == 0:
		_sprite_on[i] = 1
		s.visible = true


func sprite_off(i: int) -> void:
	if i >= 0 and i < SPRITES and _sprite_on[i] == 1:
		_sprite_on[i] = 0
		_sprite_prev[i] = Vector3.INF
		_sprites[i].visible = false


func active_rings() -> int:
	var n := 0
	for m in _rings:
		if m.visible:
			n += 1
	return n


func tick(dt: float) -> void:
	if pips != null and AlienWorld.instance != null:
		pips.refresh(AlienWorld.instance.creatures)
	for i in RINGS:
		var m := _rings[i]
		if not m.visible:
			continue
		_ring_t[i] += dt
		var k := _ring_t[i] / _ring_life[i]
		if k >= 1.15:
			m.visible = false
			continue
		var col := _ring_col[i]
		var a := lerpf(0.25, 1.0, clampf(k, 0.0, 1.0)) * (1.0 - clampf((k - 1.0) / 0.15, 0.0, 1.0))
		(m.material_override as StandardMaterial3D).albedo_color = Color(col.r, col.g, col.b, a)
	var cam_pos := _cam_pos()
	for i in LINES:
		var l := _lines[i]
		if not l.visible:
			continue
		_line_t[i] += dt
		var k2 := _line_t[i] / _line_life[i]
		if k2 >= 1.0:
			l.visible = false
			continue
		_place_line(i, cam_pos)
		var col2 := _line_col[i]
		(l.material_override as StandardMaterial3D).albedo_color = Color(col2.r, col2.g, col2.b, lerpf(0.25, 1.0, k2) * _line_k[i])
