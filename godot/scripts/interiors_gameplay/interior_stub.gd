class_name InteriorStub
extends Node3D
## A plain box room that implements docs/interiors_interface.md, so the gameplay layer (doors, vendors, actors, missions, minimap, save) works and is tested before and without the
## real generator (scripts/interiors/). InteriorGameplay uses `InteriorGen.build` when `res://scripts/interiors/interior_gen.gd` exists and this stub otherwise.
## Two draw calls (walls/floor/props merged with vertex colours, one emissive trim strip), three shadowless lights, one box collider per wall segment, counter and crate.

const MB := preload("res://scripts/world/mesh_builder.gd")
const SIZES := {
	&"weapons": Vector2(14, 12), &"clinic": Vector2(14, 12), &"tech": Vector2(16, 14), &"bar": Vector2(18, 14), &"club": Vector2(30, 26),
	&"lobby": Vector2(22, 18), &"apartment": Vector2(18, 14), &"checkpoint": Vector2(24, 20),
}
const WALL_H := 3.4
const WALL_T := 0.3
const DOOR_W := 1.8

var type: StringName = &"bar"
var seed := 0
var origin := Vector3.ZERO
var bounds := Rect2()
var door_pos := Vector3.ZERO
var door_yaw := 0.0
var exit_pos := Vector3.ZERO
var floor_rects: Array[Rect2] = []
var wall_rects: Array[Rect2] = []

var _anchors := {}
var _lights: Array[OmniLight3D] = []
var _body: StaticBody3D
var _mb := MB.new()
var _trim := MB.new()


static func build(t: StringName, s: int, org: Vector3, quality: int) -> InteriorStub:
	var r := InteriorStub.new()
	r.type = t
	r.seed = s
	r.origin = org
	r._make()
	r.set_quality(quality)
	return r


func anchors(kind: StringName) -> Array:
	return _anchors.get(kind, [])


func set_quality(level: int) -> void:
	for i in _lights.size():
		_lights[i].visible = i < (1 if level == 0 else 3)


func _box(center: Vector3, size: Vector3, col: Color, solid := true) -> void:
	_mb.box(center, size, col)
	if solid:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = center
		_body.add_child(cs)
		wall_rects.append(Rect2(origin.x + center.x - size.x * 0.5, origin.z + center.z - size.z * 0.5, size.x, size.z))


func _anchor(kind: StringName, local: Vector3, yaw := 0.0) -> void:
	var arr: Array = _anchors.get(kind, [])
	arr.append({"pos": origin + Vector3(local.x, 0.0, local.z), "yaw": yaw})
	_anchors[kind] = arr


func _make() -> void:
	position = origin
	name = "InteriorStub"
	var sz: Vector2 = SIZES.get(type, Vector2(14, 12))
	var w := sz.x
	var d := sz.y
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + 17
	var hue := InteriorData.color(type)
	_body = StaticBody3D.new()
	_body.collision_layer = Game.L_WORLD
	_body.collision_mask = 0
	add_child(_body)
	var floor_c := Color(0.075, 0.085, 0.1, 1.0)
	var wall_c := Color(0.17, 0.2, 0.23, 1.0)
	# floor and ceiling (walkable floor top at y = 0)
	_mb.box(Vector3(0.0, -0.1, 0.0), Vector3(w + 2.0 * WALL_T, 0.2, d + 2.0 * WALL_T), floor_c)
	_add_shape(Vector3(0.0, -0.25, 0.0), Vector3(w + 2.0 * WALL_T, 0.5, d + 2.0 * WALL_T))
	_mb.box(Vector3(0.0, WALL_H + 0.1, 0.0), Vector3(w + 2.0 * WALL_T, 0.2, d + 2.0 * WALL_T), Color(0.1, 0.11, 0.13, 1.0))
	_add_shape(Vector3(0.0, WALL_H + 0.25, 0.0), Vector3(w + 2.0 * WALL_T, 0.5, d + 2.0 * WALL_T))
	# walls: north, east, west full; south has the door gap in the middle
	var hy := WALL_H * 0.5
	_box(Vector3(0.0, hy, -d * 0.5 - WALL_T * 0.5), Vector3(w + 2.0 * WALL_T, WALL_H, WALL_T), wall_c)
	_box(Vector3(w * 0.5 + WALL_T * 0.5, hy, 0.0), Vector3(WALL_T, WALL_H, d), wall_c)
	_box(Vector3(-w * 0.5 - WALL_T * 0.5, hy, 0.0), Vector3(WALL_T, WALL_H, d), wall_c)
	var seg := (w - DOOR_W) * 0.5
	_box(Vector3(-DOOR_W * 0.5 - seg * 0.5, hy, d * 0.5 + WALL_T * 0.5), Vector3(seg, WALL_H, WALL_T), wall_c)
	_box(Vector3(DOOR_W * 0.5 + seg * 0.5, hy, d * 0.5 + WALL_T * 0.5), Vector3(seg, WALL_H, WALL_T), wall_c)
	_mb.box(Vector3(0.0, WALL_H - 0.3, d * 0.5 + WALL_T * 0.5), Vector3(DOOR_W, 0.6, WALL_T), wall_c)     # lintel over the doorway (visual; the gap stays 2.8 m tall)
	_box(Vector3(0.0, 1.4, d * 0.5 + 0.1), Vector3(DOOR_W, 2.8, 0.12), Color(0.06, 0.07, 0.08, 1.0))                      # the door itself (closed: the way out is USE)
	_trim.box(Vector3(0.0, 1.4, d * 0.5 - 0.02), Vector3(0.9, 2.2, 0.03), hue * 0.5)
	# glow trim: the door frame and a strip along the north wall
	_trim.box(Vector3(0.0, WALL_H - 0.62, d * 0.5 - 0.02), Vector3(DOOR_W + 0.3, 0.06, 0.06), hue)
	_trim.box(Vector3(0.0, WALL_H - 0.08, -d * 0.5 + 0.03), Vector3(w - 1.0, 0.07, 0.05), hue)
	# furniture: a counter at the back for vendors, crates as cover
	_box(Vector3(0.0, 0.5, -d * 0.5 + 3.0), Vector3(minf(5.0, w * 0.4), 1.0, 0.8), Color(0.22, 0.17, 0.12, 1.0))
	for i in 3:
		var cx := rng.randf_range(-w * 0.35, w * 0.35)
		var cz := rng.randf_range(-d * 0.1, d * 0.25)
		if absf(cx) < 2.0 and cz > d * 0.2:
			cx += 3.0
		_box(Vector3(cx, 0.4, cz), Vector3(1.0, 0.8, 1.0), Color(0.2, 0.22, 0.2, 1.0))
		_anchor(&"cover", Vector3(cx, 0.0, cz))
	_finish_meshes()
	# bounds, floors, door
	bounds = Rect2(origin.x - w * 0.5 - WALL_T, origin.z - d * 0.5 - WALL_T, w + 2.0 * WALL_T, d + 2.0 * WALL_T)
	floor_rects.append(Rect2(origin.x - w * 0.5, origin.z - d * 0.5, w, d))
	door_pos = origin + Vector3(0.0, 0.0, d * 0.5 - 1.6)
	exit_pos = origin + Vector3(0.0, 0.0, d * 0.5 - 0.7)
	door_yaw = 0.0
	# anchors (all kinds in every stub room; the real generator only the ones of its type)
	_anchor(&"vendor", Vector3(0.0, 0.0, -d * 0.5 + 2.0), PI)
	for p: Vector2 in [Vector2(-w * 0.3, -d * 0.1), Vector2(w * 0.3, -d * 0.15), Vector2(-w * 0.35, d * 0.2), Vector2(w * 0.32, d * 0.2), Vector2(0.0, d * 0.05)]:
		_anchor(&"civilian", Vector3(p.x, 0.0, p.y), rng.randf() * TAU)
	for p: Vector2 in [Vector2(-w * 0.25, -d * 0.3), Vector2(w * 0.3, -d * 0.3), Vector2(-w * 0.3, d * 0.05), Vector2(w * 0.25, d * 0.05), Vector2(0.0, -d * 0.2)]:
		_anchor(&"guard", Vector3(p.x, 0.0, p.y), 0.0)
	_anchor(&"safe", Vector3(-w * 0.5 + 1.0, 0.0, -d * 0.5 + 1.2), 0.0)
	_anchor(&"hostage", Vector3(w * 0.5 - 1.8, 0.0, -d * 0.5 + 1.8), PI)
	_anchor(&"terminal", Vector3(w * 0.5 - 1.2, 0.0, -d * 0.5 + 1.0), 0.0)
	_anchor(&"officer", Vector3(-w * 0.5 + 2.0, 0.0, -d * 0.5 + 2.0), 0.0)
	# lights
	for p: Vector3 in [Vector3(0.0, WALL_H - 0.5, -d * 0.2), Vector3(-w * 0.3, WALL_H - 0.5, d * 0.2), Vector3(w * 0.3, WALL_H - 0.5, d * 0.2)]:
		var l := OmniLight3D.new()
		l.position = p
		l.omni_range = maxf(w, d) * 0.7
		l.light_energy = 1.4
		l.light_color = hue.lerp(Color.WHITE, 0.55)
		l.shadow_enabled = false
		add_child(l)
		_lights.append(l)


func _add_shape(center: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = center
	_body.add_child(cs)


func _finish_meshes() -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	var mi := MeshInstance3D.new()
	mi.mesh = _mb.build(mat, false, true)
	mi.name = "Shell"
	add_child(mi)
	var em := StandardMaterial3D.new()
	em.vertex_color_use_as_albedo = true
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = Color(1.6, 1.6, 1.6)
	var ti := MeshInstance3D.new()
	ti.mesh = _trim.build(em, false, true)
	ti.name = "Trim"
	ti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ti)
