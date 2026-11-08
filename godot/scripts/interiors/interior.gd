class_name Interior
extends Node3D
## One generated interior as a node (built by InteriorGen.build, contract: docs/interiors_interface.md). Three MeshInstance3D (surface, window panes, glow: three draw calls), one
## StaticBody3D with box colliders on the world layer, at most two shadowless omni lights, no environment, no sun, no camera, no audio. Freeing it frees everything it made.
## Coordinates of the public properties are WORLD coordinates (origin + local), as the interface asks; `plan` holds the local data.

const SURFACE_SHADER := preload("res://assets/shaders/interior_surface.gdshader")
const WINDOW_SHADER := preload("res://assets/shaders/interior_window.gdshader")
const GLOW_SHADER := preload("res://assets/shaders/interior_glow.gdshader")
## Render layer of the interior's surface and of its own two lights: the surface shader adds every non-directional light that reaches it, so the street's neon, mission and
## muzzle lights (default layer 1) must not (a red neon lamp outside washed the whole room red). Only the room's own lights share this layer.
const LIGHT_LAYER := 1 << 19
const AMBIENT_FLOOR := 0.12
const POOLS_BY_TIER := [6, 7, 8]
const LIGHTS_BY_TIER := [1, 2, 2]

var type: StringName = &"bodega"
var seed := 0
var bounds := Rect2()
var door_pos := Vector3.ZERO
var door_yaw := 0.0
var exit_pos := Vector3.ZERO
var floor_rects: Array[Rect2] = []
var wall_rects: Array[Rect2] = []

var plan: InteriorPlan
var quality := 1
var origin := Vector3.ZERO
var display_name := ""

var _surface: MeshInstance3D
var _window: MeshInstance3D
var _glow: MeshInstance3D
var _body: StaticBody3D
var _lights: Array[OmniLight3D] = []
var _mat_surface: ShaderMaterial
var _mat_window: ShaderMaterial
var _mat_glow: ShaderMaterial
var _anchors_world: Dictionary = {}
var _tris := 0
var _shapes := 0
var _props_drawn := 0
var _hue_t := 0.0


## Called by InteriorGen.build: fills the node from a plan. `mesh_set` is the mesher's result (cached by the generator).
func setup(p_plan: InteriorPlan, p_origin: Vector3, p_quality: int, mesh_set: Dictionary) -> void:
	plan = p_plan
	origin = p_origin
	quality = clampi(p_quality, 0, 2)
	type = plan.type
	seed = plan.seed_value
	display_name = String(plan.spec.get("name", String(type).to_upper()))
	name = "Interior_%s_%d" % [String(type), seed]
	position = origin
	var o2 := Vector2(origin.x, origin.z)
	bounds = Rect2(plan.bounds.position + o2, plan.bounds.size)
	door_pos = origin + plan.entry
	door_yaw = plan.entry_yaw
	exit_pos = origin + plan.exit_pos
	floor_rects.clear()
	for r: Rect2 in plan.floor_rects():
		floor_rects.append(Rect2(r.position + o2, r.size))
	wall_rects.clear()
	for r: Rect2 in plan.wall_rects():
		wall_rects.append(Rect2(r.position + o2, r.size))
	_anchors_world.clear()
	for k: StringName in plan.anchors:
		var arr: Array = []
		for a: Dictionary in plan.anchors[k]:
			arr.append({"pos": origin + (a["pos"] as Vector3), "yaw": float(a["yaw"])})
		_anchors_world[k] = arr
	_make_materials()
	_apply_meshes(mesh_set)
	_make_body()
	_make_lights()
	_apply_tier()
	set_process(type == &"club")


func _make_materials() -> void:
	var pal: Dictionary = plan.pal
	_mat_surface = ShaderMaterial.new()
	_mat_surface.shader = SURFACE_SHADER
	var amb: Color = pal["amb"]
	var amb_l := amb.get_luminance()
	amb = amb.lerp(Color(amb_l * 0.95, amb_l, amb_l * 1.08), 0.45)             # a neutral-cool fill under the warm key: shadows are not tinted with the kind's accent
	var amb_v := Vector3(amb.r, amb.g, amb.b) * 1.35
	var amb_lum := amb_v.dot(Vector3(0.2126, 0.7152, 0.0722))
	if amb_lum < AMBIENT_FLOOR:
		amb_v *= AMBIENT_FLOOR / maxf(amb_lum, 0.005)               # a room never goes pitch black: walls and floor read even where no pool reaches (director review 4, #2)
	_mat_surface.set_shader_parameter(&"ambient_col", amb_v)
	var compat := 1.0 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 0.0
	_mat_surface.set_shader_parameter(&"compat", compat)
	_mat_surface.set_shader_parameter(&"floor_y", origin.y)
	_mat_surface.set_shader_parameter(&"show", 1.0 if type == &"club" else 0.0)
	_mat_surface.set_shader_parameter(&"balance", 1.0 if type == &"club" else 0.45)
	for i in 8:
		var pos := Vector4(0.0, 0.0, 0.0, 1.0)
		var col := Vector4(0.0, 0.0, 0.0, 0.0)
		if i < plan.pools.size():
			var p: Dictionary = plan.pools[i]
			var pp: Vector3 = origin + (p["pos"] as Vector3)
			pos = Vector4(pp.x, pp.y, pp.z, -float(p["radius"]) if bool(p.get("accent", false)) else float(p["radius"]))     # a negative radius marks an accent pool (keeps its colour)
			var pc: Color = p["col"]
			col = Vector4(pc.r, pc.g, pc.b, float(p["inten"]))
		_mat_surface.set_shader_parameter(StringName("pool_pos%d" % i), pos)
		_mat_surface.set_shader_parameter(StringName("pool_col%d" % i), col)
	_mat_window = ShaderMaterial.new()
	_mat_window.shader = WINDOW_SHADER
	var neon: Array = pal["neon"]
	_mat_window.set_shader_parameter(&"neon_a", neon[0])
	_mat_window.set_shader_parameter(&"neon_b", neon[1 % neon.size()])
	_mat_window.set_shader_parameter(&"neon_c", neon[2 % neon.size()])
	_mat_glow = ShaderMaterial.new()
	_mat_glow.shader = GLOW_SHADER
	_mat_glow.set_shader_parameter(&"show", 1.0 if type == &"club" else 0.5)
	_mat_glow.set_shader_parameter(&"compat", compat)


## The room's surface material for people standing in it (InteriorCivilian): same baked pools and ambient, so they are lit like the furniture instead of black cut-outs.
func actor_material() -> ShaderMaterial:
	return _mat_surface


func _make_instance(nm: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if mat == _mat_surface:
		mi.layers = LIGHT_LAYER
	add_child(mi)
	return mi


func _apply_meshes(ms: Dictionary) -> void:
	_tris = int(ms["tris"])
	_props_drawn = int(ms["props_drawn"])
	if _surface == null:
		_surface = _make_instance("Surface", ms["surface"], _mat_surface)
	else:
		_surface.mesh = ms["surface"]
	if ms["window"] != null:
		if _window == null:
			_window = _make_instance("Windows", ms["window"], _mat_window)
		else:
			_window.mesh = ms["window"]
	elif _window != null:
		_window.mesh = null
	if ms["glow"] != null:
		if _glow == null:
			_glow = _make_instance("Glow", ms["glow"], _mat_glow)
		else:
			_glow.mesh = ms["glow"]
	elif _glow != null:
		_glow.mesh = null


func _make_body() -> void:
	_body = StaticBody3D.new()
	_body.name = "Colliders"
	_body.collision_layer = 1                  # Game.L_WORLD
	_body.collision_mask = 0
	add_child(_body)
	for b: AABB in plan.colliders:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = b.size
		cs.shape = box
		cs.position = b.position + b.size * 0.5
		_body.add_child(cs)
		_shapes += 1


func _make_lights() -> void:
	for i in mini(2, plan.lights.size()):
		var d: Dictionary = plan.lights[i]
		var l := OmniLight3D.new()
		l.name = "Light%d" % i
		l.position = d["pos"]
		l.light_color = d["col"]
		l.light_energy = float(d["energy"])
		l.omni_range = float(d["range"])
		l.omni_attenuation = 1.3
		l.light_specular = 0.5
		l.shadow_enabled = false
		l.light_cull_mask = LIGHT_LAYER
		add_child(l)
		_lights.append(l)


func _apply_tier() -> void:
	_mat_surface.set_shader_parameter(&"detail", float(quality))
	SurfaceTextures.apply_interior(_mat_surface, quality)
	_mat_surface.set_shader_parameter(&"pool_n", float(mini(POOLS_BY_TIER[quality], plan.pools.size())))
	_mat_window.set_shader_parameter(&"detail", float(quality))
	var n: int = LIGHTS_BY_TIER[quality]
	for i in _lights.size():
		_lights[i].visible = i < n


func _enter_tree() -> void:
	if plan != null:
		_register_space()
	# an interior never outlives a new game, a respawn or the next sector (the street is where those put the hero)
	for sig: Signal in [Game.new_game, Game.respawn, Game.next_sector]:
		if not sig.is_connected(_on_lifecycle):
			sig.connect(_on_lifecycle)


func _exit_tree() -> void:
	InteriorSpace.unregister(self)
	for sig: Signal in [Game.new_game, Game.respawn, Game.next_sector]:
		if sig.is_connected(_on_lifecycle):
			sig.disconnect(_on_lifecycle)


func _on_lifecycle() -> void:
	InteriorSpace.unregister(self)
	queue_free()


func _register_space() -> void:
	var rects := PackedFloat32Array()
	var off := global_position if is_inside_tree() else origin
	for b: AABB in plan.colliders:
		if b.end.y <= 0.15 or b.position.y > 1.4:
			continue
		rects.append(b.position.x + off.x)
		rects.append(b.position.z + off.z)
		rects.append(b.end.x + off.x)
		rects.append(b.end.z + off.z)
	var covers := PackedFloat32Array()
	for c: Dictionary in plan.covers:
		var cp: Vector3 = c["pos"]
		covers.append(cp.x + off.x)
		covers.append(cp.z + off.z)
		covers.append(float(c["r"]))
		covers.append(float(c["h"]))
	var top := 3.0
	for r: Dictionary in plan.rooms:
		top = maxf(top, float(r["h"]))
	InteriorSpace.register(self, Rect2(plan.bounds.position + Vector2(off.x, off.z), plan.bounds.size), off.y, top, rects, covers)


## Lights and props scale with the tier; safe at any time (rebuilds only the surface mesh).
func set_quality(level: int) -> void:
	level = clampi(level, 0, 2)
	if plan == null or level == quality:
		return
	quality = level
	_apply_meshes(InteriorGen.mesh_set(plan, quality))
	_apply_tier()


func anchors(kind: StringName) -> Array:
	return _anchors_world.get(kind, [])


func anchor_kinds() -> Array:
	return _anchors_world.keys()


func wall_segments() -> PackedVector2Array:
	var out := plan.wall_segments()
	var o2 := Vector2(origin.x, origin.z)
	for i in out.size():
		out[i] += o2
	return out


## Audio hook (data only, see InteriorKinds.AMBIENCE): the Sfx names to loop, the one-shots and how far the street ambience closes while inside.
func ambience() -> Dictionary:
	return InteriorKinds.ambience(type)


func is_hostile() -> bool:
	return bool(plan.spec.get("hostile", false))


## {draws, tris, lights, shapes, props_drawn, props_total, rooms}: what this interior costs.
func stats() -> Dictionary:
	var draws := 0
	for mi: MeshInstance3D in [_surface, _window, _glow]:
		if mi != null and mi.mesh != null and mi.visible:
			draws += mi.mesh.get_surface_count()
	var lights := 0
	for l in _lights:
		if l.visible:
			lights += 1
	return {"draws": draws, "tris": _tris, "lights": lights, "shapes": _shapes, "props_drawn": _props_drawn, "props_total": plan.props.size(), "rooms": plan.rooms.size()}


func collider_body() -> StaticBody3D:
	return _body


## The club's light show: the two real lights drift through the neon colours (the pools and beams animate in their shaders).
func _process(delta: float) -> void:
	if not Game.is_playing() or _lights.is_empty():
		return
	_hue_t += delta
	var neon: Array = plan.pal["neon"]
	for i in _lights.size():
		var a: Color = neon[i % neon.size()]
		var b: Color = neon[(i + 1) % neon.size()]
		_lights[i].light_color = a.lerp(b, 0.5 + 0.5 * sin(_hue_t * (0.8 + 0.3 * float(i)) + float(i) * 2.0))
