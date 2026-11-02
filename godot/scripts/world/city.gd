class_name City
extends Node3D
## The neon-noir megacity: 8x8 blocks, rain-soaked streets, towers with procedural facades, street furniture, sky and moon.
## Contract (ARCHITECTURE.md, world): intersections, random_road_point, road_point_near, building_rects, is_inside_building,
## sun, set_quality; sets Game.world.
##
## Everything is built in code from the deterministic CityLayout (ported from src/world.js) and drawn with MultiMeshes:
## the whole city is a few dozen draw calls. Wet reflections: a mirrored copy of the city lives under the (alpha blended) ground.
## The props and the far skyline are camera-centred windows over their MultiMeshes (city_stream.gd): a MultiMesh of the whole city
## has one bounding box and cannot be frustum culled, so only the instances near the camera are submitted.

const MB := preload("res://scripts/world/mesh_builder.gd")
const BM := preload("res://scripts/world/building_meshes.gd")
const Env := preload("res://scripts/world/city_env.gd")
const Ground := preload("res://scripts/world/city_ground.gd")
const Buildings := preload("res://scripts/world/city_buildings.gd")
const Props := preload("res://scripts/world/city_props.gd")
const Skyline := preload("res://scripts/world/city_skyline.gd")
const Stream := preload("res://scripts/world/city_stream.gd")
const NEON_SPILL: Array[Color] = [Color(0.2, 0.85, 1.0), Color(1.0, 0.16, 0.62), Color(0.58, 0.36, 1.0), Color(0.2, 1.0, 0.66)]
const Misc := preload("res://scripts/world/city_misc.gd")
const Colliders := preload("res://scripts/world/city_colliders.gd")
const PROP_SHADER := preload("res://assets/shaders/prop.gdshader")
const PROP_MIRROR_SHADER := preload("res://assets/shaders/prop_mirror.gdshader")
const GLOW_SHADER := preload("res://assets/shaders/glow.gdshader")
const SHAFT_SHADER := preload("res://assets/shaders/shaft.gdshader")
const Ambient := preload("res://scripts/ambient/ambient_city.gd")
const Doors := preload("res://scripts/world/city_doors.gd")
const Districts := preload("res://scripts/world/city_districts.gd")
const KitWindow := preload("res://scripts/world/city_kit_window.gd")
const Landmarks := preload("res://scripts/world/city_landmarks.gd")
const KIT_SHADER := preload("res://assets/shaders/prop_kit.gdshader")

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
## The living city (far traffic, crowd, patrols; scripts/ambient/ambient_city.gd), a child of the world.
var ambient: Node3D
var building_data: Array = []      ## Buildings.Building per lot index
## Enterable doors (city_doors.gd): about one lot in five, see scripts/interiors_gameplay/. Each {id, type, name, wall, pos, normal, yaw, face_yaw, width}.
var doors: Array[Dictionary] = []
## Footprints (x, z) of the far-skyline towers (visual only; none reaches into the walkable square or the border walls).
var skyline_rects: Array[Rect2] = []
## When true the static prop and skyline families only draw the instances near the camera (see city_stream.gd).
var stream_enabled := true:
	set(v):
		stream_enabled = v
		if not v and _stream != null:
			_stream.show_all()

var _env := Env.new()
var _ground := Ground.new()
var _buildings := Buildings.new()
var _props := Props.new()
var _skyline := Skyline.new()
var _stream := Stream.new()
var _colliders := Colliders.new()
var _tri_cache := {}               ## Mesh -> triangle count (reading mesh arrays back is slow; stats() may be polled)
var _misc := Misc.new()
var _mirror_root: Node3D
var _real_root: Node3D
var _ground_node: MeshInstance3D
var _steam_node: MultiMeshInstance3D
var _building_mat: ShaderMaterial
var _prop_mats: Array[ShaderMaterial] = []    ## the lit (non-mirror) prop materials: they carry the surface taps (SurfaceTextures)
var _building_mirror_mat: ShaderMaterial
var _shadow_casters: Array[GeometryInstance3D] = []
var _tiered: Array = []            ## [GeometryInstance3D, min quality] pairs: families that only exist from a given tier up
var _kit_window := KitWindow.new() ## the street kit: one merged mesh of the props around the camera (city_kit_window.gd)
var _landmarks := Landmarks.new()  ## the four district landmarks (city_landmarks.gd)


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
	doors = Doors.compute(layout, building_data)
	_buildings.build_multimeshes()
	_build_ground()
	_build_buildings()
	_build_props()
	_build_kit()
	_build_skyline()
	_build_misc()
	_build_ambient()
	_build_collision()
	set_quality(quality)


func _physics_process(delta: float) -> void:
	# the pooled prop colliders follow the player (or, without one, the camera) while the game runs
	if not Game.is_playing() and not Game.autostart:
		return
	var p := _follow_point()
	if p != Vector3.INF:
		_colliders.follow(p, delta)


func _follow_point() -> Vector3:
	if is_instance_valid(Game.player):
		return (Game.player as Node3D).global_position
	if is_instance_valid(Game.camera):
		return Game.camera.global_position
	return Vector3.INF


## Re-centre the pooled prop colliders on `p` now (they follow the player by themselves; this is for tests, teleports and cutscenes).
func update_colliders(p: Vector3) -> void:
	_colliders.refill(p)


## The pooled prop colliders (city_colliders.gd): bodies, constant shape count, instances in use.
func prop_colliders() -> Colliders:
	return _colliders


func _process(_delta: float) -> void:
	if not stream_enabled:
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var p := cam.global_position
		_stream.update(Vector2(p.x, p.z))
		_kit_window.update(Vector2(p.x, p.z))


# --- API ---------------------------------------------------------------------------------------------------------------

## Move the instance windows of the prop and skyline families to a camera at (x, z) now (they follow the viewport's camera by
## themselves every frame; this is for tests, cutscenes and cameras that cut).
func update_streaming(cam_xz: Vector2, force := true) -> void:
	if stream_enabled:
		_stream.update(cam_xz, force)
		_kit_window.update(cam_xz, force)


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
	_stream.set_scale([0.65, 0.85, 1.0][quality])
	_kit_window.scale = [0.65, 0.85, 1.0][quality]
	var shadows := quality >= 1
	for n in _shadow_casters:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for entry: Array in _tiered:
		(entry[0] as GeometryInstance3D).visible = quality >= int(entry[1])
	if _steam_node != null:
		var per_vent: int = [9, 16, Misc.PUFFS_PER_VENT][quality]
		_steam_node.multimesh.visible_instance_count = _props.vents.size() * per_vent
	if ambient != null:
		ambient.set_quality(quality)
	var mirror_on := quality >= 1
	_mirror_root.visible = mirror_on
	_ground_node.material_override = _ground.material if mirror_on else _ground.material_lite
	for m: ShaderMaterial in [_ground.material, _ground.material_lite]:
		m.set_shader_parameter(&"detail", 1.0 if quality >= 1 else 0.0)
	_building_mat.set_shader_parameter(&"detail", 1.0 if quality >= 1 else 0.0)
	_apply_surfaces()
	_building_mat.set_shader_parameter(&"far_fade_start", 240.0 if quality >= 1 else 110.0)
	_building_mat.set_shader_parameter(&"far_fade_end", 800.0 if quality >= 1 else 420.0)


## Tier-scaled PBR surface taps (SurfaceTextures): LOW none, MED one albedo+normal pair per surface at half size, HIGH two pairs, full size and the decal mask.
func _apply_surfaces() -> void:
	SurfaceTextures.apply(_ground.material, ["road", "walkv", "decal"], quality)
	SurfaceTextures.apply(_building_mat, ["brick", "wall", "roof", "sign"], quality)
	MaterialLib.apply_to(_ground.material, ["road", "walk"], quality)           # scanned sets win when imported; no-op otherwise
	MaterialLib.apply_to(_building_mat, ["brick", "wall"], quality)
	for m in _prop_mats:
		SurfaceTextures.apply(m, ["metal", "corr", "trim", "sign"], quality)


## The node that holds the mirrored copy of the city under the wet ground (scale (1, -1, 1), hidden on the LOW tier). Dynamic objects (the player,
## enemies, vehicles) add their own unshaded, mirrored meshes there to get a reflection: see MirrorProxy. Never hide, reparent or transform it.
func get_mirror_root() -> Node3D:
	return _mirror_root


## The windowed families (city_stream.gd Family objects): name, mm, total, shown, radius, cells ... for tests and the budget report.
func stream_families() -> Array:
	return _stream.families


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
	# what the camera pass submits: every real family's drawn instances x its triangles; the mirrored copies draw the same instances again
	var shown := 0
	var tris := 0
	var tris_mirror := 0
	var mirrored := {}
	for m in mirror_nodes:
		if m.is_visible_in_tree():
			mirrored[m.multimesh] = true
	for n in multimesh_nodes:
		if not n.is_visible_in_tree():
			continue
		var mm := n.multimesh
		var drawn := mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
		if not _tri_cache.has(mm.mesh):
			_tri_cache[mm.mesh] = Stream.mesh_triangles(mm.mesh)
		var t: int = int(_tri_cache[mm.mesh]) * drawn
		shown += drawn
		tris += t
		if mirrored.has(mm):
			tris_mirror += t
	return {
		"buildings": building_data.size(),
		"multimeshes": multimesh_nodes.size(),
		"mirrored": mirror_nodes.size(),
		"instances": instances,
		"instances_drawn": shown,
		"triangles_drawn": tris,
		"triangles_drawn_mirror": tris_mirror,
		"colliders": shapes,
		"quality": quality,
	}


# --- construction ------------------------------------------------------------------------------------------------------

## Add a MultiMesh to the real city and, optionally, a mirrored copy (cheap material) under the ground.
func add_multimesh(node_name: String, mm: MultiMesh, material: Material, mirror_material: Material = null, casts_shadow := false,
		min_quality := 0, mirror_min_quality := 1) -> MultiMeshInstance3D:
	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
	mi.multimesh = mm
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-420.0, -4.0, -420.0), Vector3(840.0, 140.0, 840.0))
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_real_root.add_child(mi)
	multimesh_nodes.append(mi)
	if min_quality > 0:
		_tiered.append([mi, min_quality])
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
		if mirror_min_quality > 1 or min_quality > 1:
			_tiered.append([mr, maxi(mirror_min_quality, min_quality)])
	return mi


func _build_ground() -> void:
	_ground.make_lot_map(layout)
	_ground.begin_light_map()
	for lamp in Props.lamp_list():
		# pool centre sits under the lamp head, a couple of metres out along the arm
		var head := Vector2(lamp.x, lamp.y) + Vector2(lamp.z, lamp.w) * 2.4
		_ground.add_pool(head.x, head.y, 17.0, Color(1.0, 0.64, 0.32), 0.9)
		_ground.add_glare(head.x, head.y, 4.0, 3.0)
	# recessed LED kerb strips around some blocks spill coloured light onto the road
	for bi in CityLayout.N:
		for bj in CityLayout.N:
			if Ground.has_curb_strip(bi, bj):
				var bx := -CityLayout.HALF + (bi + 0.5) * CityLayout.PITCH
				var bz := -CityLayout.HALF + (bj + 0.5) * CityLayout.PITCH
				var e := CityLayout.BLOCK * 0.5 - 0.2
				var col: Color = NEON_SPILL[(bi + bj) % NEON_SPILL.size()]
				for k in 2:
					var s := -e if k == 0 else e
					_ground.add_strip(Vector2(bx - e, bz + s), Vector2(bx + e, bz + s), 4.5, col, 0.55)
					_ground.add_strip(Vector2(bx + s, bz - e), Vector2(bx + s, bz + e), 4.5, col, 0.55)
	# neon and shop-window light spilling onto the sidewalk in front of every street-facing wall
	for b in building_data:
		var lot: CityLayout.Lot = b.lot
		var bx := -CityLayout.HALF + (lot.block_i + 0.5) * CityLayout.PITCH
		var bz := -CityLayout.HALF + (lot.block_j + 0.5) * CityLayout.PITCH
		var sxs := 1.0 if lot.cx > bx else -1.0
		var szs := 1.0 if lot.cz > bz else -1.0
		var neon: Color = NEON_SPILL[lot.neon % NEON_SPILL.size()]
		var zf := lot.cz + szs * (lot.d * 0.5 + 1.6)
		var xf := lot.cx + sxs * (lot.w * 0.5 + 1.6)
		_ground.add_strip(Vector2(lot.cx - lot.w * 0.5, zf), Vector2(lot.cx + lot.w * 0.5, zf), 6.0, neon, 0.32)
		_ground.add_strip(Vector2(xf, lot.cz - lot.d * 0.5), Vector2(xf, lot.cz + lot.d * 0.5), 6.0, Color(1.0, 0.72, 0.45), 0.3)
		# contact pools: shop windows (warm tungsten) and the sign band (neon) cast a tighter, brighter patch right at the wall foot
		var zc := lot.cz + szs * (lot.d * 0.5 + 0.9)
		var xc := lot.cx + sxs * (lot.w * 0.5 + 0.9)
		_ground.add_strip(Vector2(lot.cx - lot.w * 0.5, zc), Vector2(lot.cx + lot.w * 0.5, zc), 3.2, Color(1.0, 0.62, 0.30), 0.38)
		_ground.add_strip(Vector2(xc, lot.cz - lot.d * 0.5), Vector2(xc, lot.cz + lot.d * 0.5), 3.2, Color(0.9, 0.6, 0.35), 0.30)
		_ground.add_strip(Vector2(lot.cx - lot.w * 0.5, zf + szs * 0.8), Vector2(lot.cx + lot.w * 0.5, zf + szs * 0.8), 2.6, neon, 0.22)
	_ground.finish_light_map()
	_ground.make_material()
	_ground_node = _ground.make_node()
	add_child(_ground_node)


func _build_buildings() -> void:
	_building_mat = _buildings.make_material(false)
	_building_mirror_mat = _buildings.make_material(true)
	_building_mat.set_shader_parameter(&"light_map", _ground.light_texture)
	for cls: StringName in BM.ORDER:
		var mm: MultiMesh = _buildings.multimeshes[cls]
		if mm.instance_count == 0:
			continue
		add_multimesh("Buildings_" + String(cls), mm, _building_mat, _building_mirror_mat, true)


func _build_misc() -> void:
	_misc.build(layout, building_data, _props.vents, _props.rng)
	if _misc.cable_mesh != null:
		var mi := MeshInstance3D.new()
		mi.name = "Cables"
		mi.mesh = _misc.cable_mesh
		mi.material_override = Misc.make_material(Misc.CABLE_SHADER)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-420.0, -2.0, -420.0), Vector3(840.0, 24.0, 840.0))
		_real_root.add_child(mi)
	if _misc.steam_mm != null:
		_steam_node = add_multimesh("Steam", _misc.steam_mm, Misc.make_material(Misc.STEAM_SHADER), null, false)
	if _misc.hologram_mm != null:
		add_multimesh("Holograms", _misc.hologram_mm, Misc.make_material(Misc.HOLO_SHADER), Misc.make_material(Misc.HOLO_SHADER, -120), false, 1, 2)


func _build_ambient() -> void:
	ambient = Ambient.new()
	add_child(ambient)
	ambient.setup(self, _ground.light_texture)


func _build_skyline() -> void:
	_skyline.build()
	skyline_rects = _skyline.rects
	var mat := Skyline.make_material(false)
	var mirror := Skyline.make_material(true)
	var mats: Array[ShaderMaterial] = [mat, mirror]
	for cls: StringName in Skyline.CLASSES:
		var mm: MultiMesh = _skyline.multimeshes[cls]
		if mm.instance_count > 0:
			add_multimesh("Skyline_" + String(cls), mm, mat, mirror, false, 0, 2)       # the far reflections are a HIGH-tier luxury
			_stream.add("Skyline_" + String(cls), mm, Skyline.RADIUS, Stream.mesh_triangles(mm.mesh), mats, -760.0, 80.0, 19)


func _shader_mat(shader: Shader, priority := 0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.render_priority = priority
	return m


func _build_props() -> void:
	_props.build(layout, building_data)
	_colliders.build(self, _props.parts, _props.kit.collider_sources())
	var prop_mat := _shader_mat(PROP_SHADER)
	_prop_mats.append(prop_mat)
	var prop_mirror := _shader_mat(PROP_MIRROR_SHADER)
	var glow_mat := _shader_mat(GLOW_SHADER)
	var glow_mirror := _shader_mat(GLOW_SHADER, -120)     # transparent copies must be in the screen copy the ground reads
	var shaft_mat := _shader_mat(SHAFT_SHADER)
	for part in _props.parts:
		var mirror: bool = part["mirror"]
		var radius: float = part.get("radius", 0.0)
		var mm: MultiMesh = part["mm"]
		match part["kind"]:
			&"prop":
				# windowed families own their materials: the distance LOD range is a per-family uniform
				var mat := _shader_mat(PROP_SHADER) if radius > 0.0 else prop_mat
				if radius > 0.0:
					_prop_mats.append(mat)
				var mmat := _shader_mat(PROP_MIRROR_SHADER) if radius > 0.0 else prop_mirror
				add_multimesh(part["name"], mm, mat, mmat if mirror else null, part["shadow"], part.get("min", 0))
				if radius > 0.0:
					var mats: Array[ShaderMaterial] = [mat]
					if mirror:
						mats.append(mmat)
					_stream.add(part["name"], mm, radius, Stream.mesh_triangles(mm.mesh), mats)
			&"glow":
				add_multimesh(part["name"], mm, glow_mat, glow_mirror if mirror else null, false)
			&"shaft":
				add_multimesh(part["name"], mm, shaft_mat, null, false, part.get("min", 0))
				if radius > 0.0:
					var mats: Array[ShaderMaterial] = [shaft_mat]
					_stream.add(part["name"], mm, radius, Stream.mesh_triangles(mm.mesh), mats)


## The street kit window and the district landmarks (city_kit.gd, city_landmarks.gd): ONE mesh, ONE draw call, merged around the camera.
func _build_kit() -> void:
	var mat := _shader_mat(KIT_SHADER)
	_prop_mats.append(mat)
	_kit_window.setup(_real_root, _props.kit, mat)
	_landmarks.build(layout)
	_kit_window.landmarks = _landmarks.items


## The street kit builder (placements per kind and district, geometry cache): for tests and gameplay queries.
func street_kit() -> RefCounted:
	return _props.kit


## The camera-centred window mesh of the street kit (city_kit_window.gd).
func kit_window() -> RefCounted:
	return _kit_window


## The four district landmarks (city_landmarks.gd).
func landmarks() -> RefCounted:
	return _landmarks


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
	# the district landmarks: a solid core column each (the crowns are overhead)
	for box: Array in _landmarks.collision_boxes():
		_add_box(box[0], box[1], box[2])
	# invisible walls just outside the border roads (HALF + 30)
	var e := CityLayout.WALK
	var t := CityLayout.WALL_T
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
