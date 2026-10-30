class_name City
extends Node3D
## The neon-noir megacity: 8x8 blocks, rain-soaked streets, towers with procedural facades, street furniture, sky and moon.
## Contract (ARCHITECTURE.md, world): intersections, random_road_point, road_point_near, building_rects, is_inside_building,
## sun, set_quality; sets Game.world.
##
## Everything is built in code from the deterministic CityLayout (ported from src/world.js) and drawn with MultiMeshes:
## the whole city is a few dozen draw calls. Wet reflections: a mirrored copy of the city lives under the (alpha blended) ground.

const MB := preload("res://scripts/world/mesh_builder.gd")
const BM := preload("res://scripts/world/building_meshes.gd")
const Env := preload("res://scripts/world/city_env.gd")
const Ground := preload("res://scripts/world/city_ground.gd")
const Buildings := preload("res://scripts/world/city_buildings.gd")
const Props := preload("res://scripts/world/city_props.gd")
const PROP_SHADER := preload("res://assets/shaders/prop.gdshader")
const PROP_MIRROR_SHADER := preload("res://assets/shaders/prop_mirror.gdshader")
const GLOW_SHADER := preload("res://assets/shaders/glow.gdshader")
const SHAFT_SHADER := preload("res://assets/shaders/shaft.gdshader")

## Inner junctions (y = 0), 7 x 7 = 49.
var intersections: Array[Vector3] = []
## Building footprints (x, z) for the minimap.
var building_rects: Array[Rect2] = []
## The moon light.
var sun: DirectionalLight3D
var layout: CityLayout
## Current quality tier, 0 low, 1 medium, 2 high.
var quality := 1
## Every MultiMeshInstance3D of the city (real ones; mirrored copies are listed separately), for tests and stats.
var multimesh_nodes: Array[MultiMeshInstance3D] = []
var mirror_nodes: Array[MultiMeshInstance3D] = []
var collision_body: StaticBody3D
var building_data: Array = []      ## Buildings.Building per lot index

var _env := Env.new()
var _ground := Ground.new()
var _buildings := Buildings.new()
var _props := Props.new()
var _mirror_root: Node3D
var _real_root: Node3D
var _ground_node: MeshInstance3D
var _building_mat: ShaderMaterial
var _building_mirror_mat: ShaderMaterial
var _shadow_casters: Array[GeometryInstance3D] = []
var _detail_materials: Array[ShaderMaterial] = []


func _ready() -> void:
	Game.world = self
	layout = CityLayout.new()
	intersections = CityLayout.make_intersections()
	for lot in layout.lots:
		building_rects.append(lot.rect)

	_real_root = Node3D.new()
	_real_root.name = "Geometry"
	add_child(_real_root)
	_mirror_root = Node3D.new()
	_mirror_root.name = "Mirror"
	_mirror_root.scale = Vector3(1, -1, 1)               # the wet-ground reflection: the city mirrored under the plane
	add_child(_mirror_root)

	_env.build(self)
	sun = _env.sun

	_buildings.assign(layout)
	building_data = _buildings.buildings
	_buildings.build_multimeshes()
	_build_ground()
	_build_buildings()
	_build_props()
	_build_collision()
	set_quality(quality)


# --- API ---------------------------------------------------------------------------------------------------------------

func random_road_point() -> Vector3:
	return layout.random_road_point()


## A random road position whose XZ distance from `center` is within [rmin, rmax]; Vector3.INF when no road lies there.
func road_point_near(center: Vector3, rmin: float, rmax: float) -> Vector3:
	return layout.road_point_near(center, rmin, rmax)


## True when p is inside a building volume (footprint x height, following the stepped crowns).
func is_inside_building(p: Vector3) -> bool:
	if p.y < 0.0:
		return false
	var lot := layout.lot_at(p.x, p.z)
	if lot == null:
		return false
	var b: Buildings.Building = building_data[lot.index]
	return BM.contains(b.cls, p.x - lot.cx, p.y, p.z - lot.cz, lot.w, lot.d, lot.h)


## Height of the walkable surface under (x, z) (0 on streets): the topmost building part below `from_y`.
func ground_height(x: float, z: float, from_y := 1.0e9) -> float:
	var lot := layout.lot_at(x, z)
	if lot == null:
		return 0.0
	var b: Buildings.Building = building_data[lot.index]
	var best := 0.0
	for p: Array in BM.CLASSES[b.cls]:
		var top: float = p[5] * lot.h
		if top <= from_y + 0.9 and top > best and x - lot.cx > p[0] * lot.w and x - lot.cx < p[1] * lot.w \
				and z - lot.cz > p[2] * lot.d and z - lot.cz < p[3] * lot.d:
			best = top
	return best


## 0 low, 1 medium, 2 high: shadows, MSAA, render scale, shader detail and the mirrored-reflection pass.
func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)
	if not is_inside_tree():
		return
	_env.apply_quality(quality, get_viewport())
	var shadows := quality >= 1
	for n in _shadow_casters:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mirror_on := quality >= 1
	_mirror_root.visible = mirror_on
	_ground_node.material_override = _ground.material if mirror_on else _ground.material_lite
	for m: ShaderMaterial in [_ground.material, _ground.material_lite]:
		m.set_shader_parameter(&"detail", 1.0 if quality >= 1 else 0.0)
	_building_mat.set_shader_parameter(&"detail", 1.0 if quality >= 1 else 0.0)


## Draw-call style stats for tests and the budget report.
func stats() -> Dictionary:
	var instances := 0
	for n in multimesh_nodes:
		instances += n.multimesh.instance_count
	var shapes := 0
	if collision_body:
		for c in collision_body.get_children():
			if c is CollisionShape3D:
				shapes += 1
	return {
		"buildings": building_data.size(),
		"multimeshes": multimesh_nodes.size(),
		"mirrored": mirror_nodes.size(),
		"instances": instances,
		"colliders": shapes,
		"quality": quality,
	}


# --- construction ------------------------------------------------------------------------------------------------------

## Add a MultiMesh to the real city and, optionally, a mirrored copy (cheap material) under the ground.
func add_multimesh(node_name: String, mm: MultiMesh, material: Material, mirror_material: Material = null, casts_shadow := false) -> MultiMeshInstance3D:
	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
	mi.multimesh = mm
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-420.0, -4.0, -420.0), Vector3(840.0, 140.0, 840.0))
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_real_root.add_child(mi)
	multimesh_nodes.append(mi)
	if casts_shadow:
		_shadow_casters.append(mi)
	if mirror_material != null:
		var mr := MultiMeshInstance3D.new()
		mr.name = node_name + "_mirror"
		mr.multimesh = mm
		mr.material_override = mirror_material
		mr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mr.custom_aabb = mi.custom_aabb
		mr.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_mirror_root.add_child(mr)
		mirror_nodes.append(mr)
	return mi


func _build_ground() -> void:
	_ground.make_lot_map(layout)
	_ground.begin_light_map()
	for lamp in Props.lamp_list():
		# pool centre sits under the lamp head, a couple of metres out along the arm
		var head := Vector2(lamp.x, lamp.y) + Vector2(lamp.z, lamp.w) * 2.4
		_ground.add_pool(head.x, head.y, 17.0, Color(1.0, 0.64, 0.32), 0.9)
		_ground.add_glare(head.x, head.y, 4.0, 3.0)
	_ground.finish_light_map()
	_ground.make_material()
	_ground_node = _ground.make_node()
	add_child(_ground_node)


func _build_buildings() -> void:
	_building_mat = _buildings.make_material(false)
	_building_mirror_mat = _buildings.make_material(true)
	_detail_materials.append(_building_mat)
	for cls: StringName in BM.ORDER:
		var mm: MultiMesh = _buildings.multimeshes[cls]
		if mm.instance_count == 0:
			continue
		add_multimesh("Buildings_" + String(cls), mm, _building_mat, _building_mirror_mat, true)


func _shader_mat(shader: Shader, priority := 0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.render_priority = priority
	return m


func _build_props() -> void:
	_props.build(layout)
	var prop_mat := _shader_mat(PROP_SHADER)
	var prop_mirror := _shader_mat(PROP_MIRROR_SHADER)
	var glow_mat := _shader_mat(GLOW_SHADER)
	var glow_mirror := _shader_mat(GLOW_SHADER, -120)     # transparent copies must be in the screen copy the ground reads
	var shaft_mat := _shader_mat(SHAFT_SHADER)
	_detail_materials.append(prop_mat)
	for part in _props.parts:
		var mirror: bool = part["mirror"]
		match part["kind"]:
			&"prop":
				add_multimesh(part["name"], part["mm"], prop_mat, prop_mirror if mirror else null, part["shadow"])
			&"glow":
				add_multimesh(part["name"], part["mm"], glow_mat, glow_mirror if mirror else null, false)
			&"shaft":
				add_multimesh(part["name"], part["mm"], shaft_mat, null, false)


func _build_collision() -> void:
	collision_body = StaticBody3D.new()
	collision_body.name = "Collision"
	collision_body.collision_layer = Game.L_WORLD
	collision_body.collision_mask = 0
	add_child(collision_body)
	# ground
	_add_box(Vector3(0.0, -2.0, 0.0), Vector3(1600.0, 4.0, 1600.0), "Ground")
	# every part of every building (stepped crowns are separate boxes, so roofs and ledges are where you see them)
	for b in building_data:
		var lot: CityLayout.Lot = b.lot
		var boxes := BM.collision_boxes(b.cls, lot.cx, lot.cz, lot.w, lot.d, lot.h)
		for k in boxes.size():
			_add_box(boxes[k][0], boxes[k][1], "Building%d_%d" % [lot.index, k])
	# invisible walls just outside the border roads (HALF + 30)
	var e := CityLayout.HALF + CityLayout.BORDER
	var t := 8.0
	var len := 2.0 * (e + t)
	_add_box(Vector3(e + t * 0.5, 200.0, 0.0), Vector3(t, 400.0, len), "WallE")
	_add_box(Vector3(-e - t * 0.5, 200.0, 0.0), Vector3(t, 400.0, len), "WallW")
	_add_box(Vector3(0.0, 200.0, e + t * 0.5), Vector3(len, 400.0, t), "WallS")
	_add_box(Vector3(0.0, 200.0, -e - t * 0.5), Vector3(len, 400.0, t), "WallN")


func _add_box(center: Vector3, size: Vector3, shape_name: String) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.name = shape_name
	cs.shape = shape
	cs.position = center
	collision_body.add_child(cs)
