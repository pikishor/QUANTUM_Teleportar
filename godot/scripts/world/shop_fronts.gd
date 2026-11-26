class_name ShopFronts
extends Node3D
## Wave 122 (w122-shops, owner round 7: "walk into buildings", "not many details on the street"): WALK-IN STREET SHOPS. Six kinds (FOOD MARKET, CLOTHES, GUN SHOP, MOTORS,
## ELECTRONICS, PHARMACY) stand behind a real glass front on the ground floor of the buildings whose street door is a shop door (city_doors.gd). When the hero comes within NEAR m
## of one, it is built IN PLACE (no fade, no loading): the building's collider boxes (city.gd "Building<lot>_<k>") are switched off and rebuilt around a room of W x D x H metres
## behind the facade, the facade of that one building is drawn by this node with the shop front cut out (building_shop.gdshader / building_far_shop.gdshader: the city's own
## instance is collapsed through the facade uniform `shop_hide`), and the room gets its shelves, goods, counter, lights, a glass front that reflects lightly, a sign and a shopkeeper.
## Inside, beside the shopkeeper, the round context button (the wave 119 slot) reads BUY and opens the vendor's trade window (VendorScreen, VendorLogic: the existing economy).
## Cost while a shop is open: the room (one mesh), the glass (one transparent mesh), the facade copy (one draw), the sign and the shopkeeper. Nothing is built further away.
## Frame of a shop: n = the door's outward normal, t = along the facade; (s, v) = metres along t from the facade centre and metres into the building from the facade plane.
## Tower lots (TowerFloors, w122-rooms: block lots from 12 m) are never shops: the two walk-in systems never share a building.

const KINDS: Array[StringName] = [&"food", &"clothes", &"guns", &"motors", &"electronics", &"pharmacy"]
const VENDOR := {&"food": &"bodega", &"clothes": &"clothes", &"guns": &"weapons", &"motors": &"motors", &"electronics": &"tech", &"pharmacy": &"clinic"}
const TITLE := {&"food": "FOOD MARKET", &"clothes": "THREADS", &"guns": "GUN SHOP", &"motors": "MOTORS", &"electronics": "ELECTRONICS", &"pharmacy": "PHARMACY"}
const SIGN_COLOR := {&"food": Color(0.55, 1.0, 0.4), &"clothes": Color(1.0, 0.45, 0.85), &"guns": Color(1.0, 0.35, 0.25), &"motors": Color(1.0, 0.7, 0.2),
		&"electronics": Color(0.35, 0.8, 1.0), &"pharmacy": Color(0.35, 1.0, 0.6)}
const FROM_TYPE := {&"bodega": &"food", &"weapons": &"guns", &"tech": &"electronics", &"clinic": &"pharmacy"}
const OTHER_TYPES: Array[StringName] = [&"warehouse", &"cargo_bay", &"corridor_lab", &"server_room", &"control_room", &"med_bay", &"teleporter_hall"]     ## doors of these become CLOTHES or MOTORS
const Buildings := preload("res://scripts/world/city_buildings.gd")
const SHADER_CUT := preload("res://assets/shaders/building_shop.gdshader")
const SHADER_FAR_CUT := preload("res://assets/shaders/building_far_shop.gdshader")
const NEAR := 15.0
const FAR := 22.0
const H := 3.8                   ## room height (under the facade's first floor line: ground floor 4.6 / 5 m)
const DOOR_W := 1.8
const TOWER_MIN_H := 12.0        ## TowerFloors.HOUSE_MIN_H (w122-rooms): block lots from this height are walk-in towers
const REACH_BUY := 2.6
const FLOOR_Y := 0.02              ## w122-critic: the shop floor a hair over the street ground it lies on
const SIGN_OUT := 0.04             ## w1242-street: m the sign stands off the facade (was 0.5)
const SIGN_MARGIN := 0.8          ## w1242-street: m of the shop front left free beside the sign (the neighbours' signs start at the front's edge)
const NEAR_ROOMS := 45.0         ## LOW / LOW+: metres within which a window shows the room behind it (building_core.gdshaderinc near_rooms)

static var enabled := OS.get_environment("W122_SHOPS_OLD") != "1"       ## W122_SHOPS_OLD=1 in the checks: no walk-in shops and no LOW room parallax (the wave 121 street)
static var instance: ShopFronts
static var open_lot := -1
static var prompt_text := ""
static var bought_rides := 0

var shops: Array[Dictionary] = []      ## {lot, door, kind, title, n, t, base, fw, depth, s0, s1, sd, d}
var _cur: Dictionary = {}
var _scan := 0.0
var _collected := false
var _room: MeshInstance3D
var _glass: MeshInstance3D
var _facade: MultiMeshInstance3D
var _sign: Label3D
var _body: StaticBody3D
var _keeper: InteriorCivilian
var _mat_room: StandardMaterial3D
var _mat_glass: StandardMaterial3D
var _boxes_off: Array[CollisionShape3D] = []
var _st: SurfaceTool


static func near_rooms(quality: int) -> float:
	return NEAR_ROOMS if enabled and quality < 1 else 0.0


func _ready() -> void:
	instance = self
	name = "ShopFronts"
	_mat_room = StandardMaterial3D.new()
	_mat_room.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_room.vertex_color_use_as_albedo = true
	_mat_glass = StandardMaterial3D.new()
	_mat_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_glass.albedo_color = Color(0.55, 0.7, 0.78, 0.14)
	_mat_glass.metallic = 0.6
	_mat_glass.roughness = 0.04
	_mat_glass.metallic_specular = 1.0
	_mat_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_glass.rim_enabled = true
	_mat_glass.rim = 0.35
	_mat_glass.rim_tint = 0.2


func _exit_tree() -> void:
	close()
	if instance == self:
		instance = null


static func prompt() -> String:
	if not enabled or open_lot < 0 or not Game.is_playing() or InteriorGameplay.vendor_open:
		return ""
	return prompt_text


## The shops of a kind, nearest first is `nearest_of`; `all()` for the map.
func _collect() -> void:
	shops.clear()
	var city = Game.world
	if city == null or not is_instance_valid(city) or not (&"building_data" in city) or city.get(&"collision_body") == null:
		return
	_collected = true
	var tw := {}
	if TowerFloors.instance != null:
		for t: Dictionary in TowerFloors.instance.towers:
			tw[(t["lot"] as CityLayout.Lot).index] = true
	for d: Dictionary in city.doors:
		var type: StringName = d["type"]
		var kind: StringName = FROM_TYPE.get(type, &"")
		var lot_i := int(d["id"])
		if kind == &"" and OTHER_TYPES.has(type):
			kind = &"clothes" if Buildings.hash01(lot_i, 91) < 0.5 else &"motors"
		if kind == &"" or tw.has(lot_i) or lot_i >= city.building_data.size():
			continue
		var b = city.building_data[lot_i]
		var lot: CityLayout.Lot = b.lot
		if (b.cls == &"block" and lot.h >= TOWER_MIN_H) or lot.h < 8.0:
			continue
		if city.collision_body.get_node_or_null("Building%d_0" % lot_i) == null:
			continue                                            # the outer districts: streamed colliders, no shop
		var n: Vector3 = d["normal"]
		var t := Vector3(-n.z, 0.0, n.x)
		var xf := absf(n.x) > 0.5
		var fw := lot.d if xf else lot.w
		var depth := lot.w if xf else lot.d
		if fw < 7.0 or depth < 6.0:
			continue
		var base := Vector3(lot.cx, 0.0, lot.cz) + n * (depth * 0.5)
		var sd := (d["wall"] as Vector3 - base).dot(t)
		var w := clampf(fw - 1.8, 5.5, 9.0)
		var s0 := clampf(sd - w * 0.5, -fw * 0.5 + 0.9, fw * 0.5 - 0.9 - w)
		var s1 := s0 + w
		sd = clampf(sd, s0 + DOOR_W * 0.5 + 0.2, s1 - DOOR_W * 0.5 - 0.2)
		sd = _free_door(city, base, n, t, sd, s0, s1)
		if is_nan(sd):
			continue                                            # street furniture in front of every spot of the front: no shop here
		var dd := clampf(depth - 1.6, 4.5, 7.0)
		var title: String = "%s %s" % [InteriorData.NAME_A[lot_i % InteriorData.NAME_A.size()], TITLE[kind]]
		d["walk_in"] = true
		d["shop"] = kind
		d["shop_title"] = title
		d["name"] = title
		var door_pt := base + t * sd
		if not d.has("pos0"):
			d["pos0"] = d["pos"]                                  # w122 integrator: the USE-door spot city_doors.gd placed (tests/test_interior_gameplay.gd checks it is deterministic)
		d["pos"] = door_pt + n * 1.3
		shops.append({"lot": lot, "door": d, "kind": kind, "title": title, "n": n, "t": t, "base": base, "fw": fw, "depth": depth, "s0": s0, "s1": s1, "sd": sd, "d": dd,
				"wall": door_pt, "normal": n, "along": t})


## A door position along the front (s) whose way in from the kerb is free of street props (benches, bins, hydrants: the city's prop colliders), nearest `want`; NAN when none is.
static func _free_door(city, base: Vector3, n: Vector3, t: Vector3, want: float, s0: float, s1: float) -> float:
	var cols = city.prop_colliders() if city.has_method(&"prop_colliders") else null
	if cols == null:
		return want
	var near: Array[Vector2] = []                          # props near this front, as (s, out)
	var c0 := base + t * s0
	var c1 := base + t * s1
	var keys := {}
	for q: Vector3 in [c0, c1, (c0 + c1) * 0.5, c0 + n * 3.0, c1 + n * 3.0]:
		keys[cols._key(q.x, q.z)] = true
	for k in keys:
		for id: int in cols._grid.get(k, PackedInt32Array()):
			var o: Vector3 = (cols._xf[id] as Transform3D).origin - base
			var sv := o.dot(t)
			var out := o.dot(n)
			if out > -0.5 and out < 3.2 and sv > s0 - 1.5 and sv < s1 + 1.5:
				near.append(Vector2(sv, out))
	if near.is_empty():
		return want
	var best := NAN
	var bd := INF
	var x := s0 + DOOR_W * 0.5 + 0.2
	while x <= s1 - DOOR_W * 0.5 - 0.2 + 0.001:
		var free := true
		for pr in near:
			if absf(pr.x - x) < DOOR_W * 0.5 + 0.6:
				free = false
				break
		if free and absf(x - want) < bd:
			bd = absf(x - want)
			best = x
		x += 0.25
	return best


func all() -> Array[Dictionary]:
	if not _collected:
		_collect()
	return shops


func nearest_of(kind: StringName, from: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for s: Dictionary in all():
		if s["kind"] != kind:
			continue
		var dist := (s["wall"] as Vector3).distance_to(from)
		if dist < bd:
			bd = dist
			best = s
	return best


static func at(s: Dictionary, sv: float, v: float, y := 0.0) -> Vector3:
	return (s["base"] as Vector3) + (s["t"] as Vector3) * sv - (s["n"] as Vector3) * v + Vector3(0.0, y, 0.0)


## True while `p` is in the open shop's room (under its ceiling): no rain, the tight-room camera.
static func inside(p: Vector3) -> bool:
	if instance == null or instance._cur.is_empty():
		return false
	var s := instance._cur
	var rel := p - (s["base"] as Vector3)
	var sv := rel.dot(s["t"])
	var v := -rel.dot(s["n"])
	return p.y < H and p.y > -0.5 and v > 0.0 and v < float(s["d"]) and sv > float(s["s0"]) and sv < float(s["s1"])


## True while `p` is inside the open shop's solid parts (city.is_inside_building asks this for the open lot).
static func blocks(p: Vector3) -> bool:
	if instance == null or instance._cur.is_empty():
		return false
	var s := instance._cur
	var rel := p - (s["base"] as Vector3)
	var sv := rel.dot(s["t"])
	var v := -rel.dot(s["n"])
	if p.y < H and v > -0.1 and v < float(s["d"]) and sv > float(s["s0"]) and sv < float(s["s1"]):
		return false
	var lot: CityLayout.Lot = s["lot"]
	return v > 0.0 and p.y < lot.h


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	var p := Game.player as Node3D
	if not is_instance_valid(p) or Game.world == null:
		return
	if not _collected:
		_collect()
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.25
		var pp := p.global_position
		if not _cur.is_empty() and ((_cur["wall"] as Vector3).distance_to(Vector3(pp.x, 0.0, pp.z)) > FAR or pp.y > 30.0):
			close()
		if _cur.is_empty() and pp.y < 8.0 and not InteriorGameplay.active and p.get(&"vehicle") == null:     # w122-ci: never from a car (no one shops at the wheel; each open rebuilds the lot's colliders and meshes, a 4-90 ms hitch, under a car at chase speed)
			var best: Dictionary = {}
			var bd := NEAR
			for s: Dictionary in shops:
				var dist := (s["wall"] as Vector3).distance_to(Vector3(pp.x, 0.0, pp.z))
				if dist < bd and int((s["lot"] as CityLayout.Lot).index) != TowerFloors.open_lot:
					bd = dist
					best = s
			if not best.is_empty():
				open(best)
	if _cur.is_empty():
		prompt_text = ""
		return
	if is_instance_valid(_facade):                  # the tier changed (LOW+ lean facade or the full one): rebuild with the matching cut shader
		var bm: Variant = Game.world.get(&"_building_mat")
		var want: Shader = SHADER_FAR_CUT if bm is ShaderMaterial and (bm as ShaderMaterial).shader == Buildings.LEAN_SHADER else SHADER_CUT
		if (_facade.material_override as ShaderMaterial).shader != want:
			open(_cur)
			return
	if is_instance_valid(_keeper):
		_keeper.tick(delta)
	prompt_text = ""
	var kp := _keeper.global_position if is_instance_valid(_keeper) else Vector3.INF
	if p.get(&"vehicle") == null and kp.is_finite() and Vector2(p.global_position.x - kp.x, p.global_position.z - kp.z).length() < REACH_BUY and absf(p.global_position.y - kp.y) < 1.5:
		prompt_text = "BUY  %s" % str(_cur["title"])
	if prompt_text != "" and Input.is_action_just_pressed(&"interact") and Game.state == &"play":
		var ig := InteriorGameplay.instance
		if ig != null and is_instance_valid(ig.vendor_screen):
			if ig.vendor_screen.open(VENDOR[_cur["kind"]]):
				ig.vendor_screen.title_override = str(_cur["title"])


# --- open / close ------------------------------------------------------------------------------------------------------------

func open(s: Dictionary) -> void:
	close()
	_cur = s
	var lot: CityLayout.Lot = s["lot"]
	open_lot = lot.index
	_set_city_boxes(lot.index, true)
	_build_colliders()
	_build_facade()
	_build_room()
	_build_keeper()


func close() -> void:
	if _cur.is_empty():
		return
	var lot: CityLayout.Lot = _cur["lot"]
	_set_city_boxes(lot.index, false)
	for n in [_room, _glass, _facade, _sign, _body]:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_room = null
	_glass = null
	_facade = null
	_sign = null
	_body = null
	if is_instance_valid(_keeper):
		_keeper.deactivate()
	var bm: Variant = Game.world.get(&"_building_mat") if is_instance_valid(Game.world) else null
	if bm is ShaderMaterial:
		(bm as ShaderMaterial).set_shader_parameter(&"shop_hide", Vector2(1e9, 1e9))
	_cur = {}
	open_lot = -1
	prompt_text = ""


func _set_city_boxes(idx: int, off: bool) -> void:
	if not off:
		for cs in _boxes_off:
			if is_instance_valid(cs):
				cs.set_deferred(&"disabled", false)
		_boxes_off.clear()
		return
	var cb: Node = Game.world.get(&"collision_body")
	var k := 0
	while cb != null:
		var cs := cb.get_node_or_null("Building%d_%d" % [idx, k]) as CollisionShape3D
		if cs == null:
			break
		cs.set_deferred(&"disabled", true)
		_boxes_off.append(cs)
		k += 1


# --- colliders ---------------------------------------------------------------------------------------------------------------

## The building's boxes minus the room (and its open front), plus the glass panes beside the door.
func _build_colliders() -> void:
	_body = StaticBody3D.new()
	_body.name = "ShopBody"
	_body.collision_layer = Game.L_WORLD
	_body.collision_mask = 0
	add_child(_body)
	var s := _cur
	var a := at(s, s["s0"], -0.6, 0.0)
	var b := at(s, s["s1"], float(s["d"]), H)
	var room := AABB(Vector3(minf(a.x, b.x), 0.0 - 1.0, minf(a.z, b.z)), Vector3(absf(a.x - b.x), H + 1.0, absf(a.z - b.z)))
	for cs in _boxes_off:
		var bs := cs.shape as BoxShape3D
		if bs == null:
			continue
		var box := AABB(cs.position - bs.size * 0.5, bs.size)
		for piece in _subtract(box, room):
			_add_box(piece)
	# glass panes (left and right of the door) and a thin lintel strip are solid
	var gl := [Vector2(float(s["s0"]), float(s["sd"]) - DOOR_W * 0.5), Vector2(float(s["sd"]) + DOOR_W * 0.5, float(s["s1"]))]
	for g: Vector2 in gl:
		if g.y - g.x > 0.05:
			var p0 := at(s, g.x, -0.06, 0.0)
			var p1 := at(s, g.y, 0.06, H)
			_add_box(AABB(Vector3(minf(p0.x, p1.x), 0.0, minf(p0.z, p1.z)), Vector3(maxf(absf(p0.x - p1.x), 0.12), H, maxf(absf(p0.z - p1.z), 0.12))))
	# the counter
	var c0 := at(s, float(s["s0"]) + 0.5, float(s["d"]) - 2.3, 0.0)
	var c1 := at(s, float(s["s0"]) + 2.7, float(s["d"]) - 1.6, 1.05)
	_add_box(AABB(Vector3(minf(c0.x, c1.x), 0.0, minf(c0.z, c1.z)), Vector3(absf(c0.x - c1.x), 1.05, absf(c0.z - c1.z))))


static func _subtract(box: AABB, cut: AABB) -> Array[AABB]:
	var out: Array[AABB] = []
	if not box.intersects(cut):
		out.append(box)
		return out
	var rest := box
	for axis in 3:
		var lo := rest.position[axis]
		var hi := rest.end[axis]
		if cut.position[axis] > lo:
			var piece := rest
			piece.size[axis] = cut.position[axis] - lo
			out.append(piece)
			rest.position[axis] = cut.position[axis]
			rest.size[axis] = hi - cut.position[axis]
		if cut.end[axis] < hi:
			var piece2 := rest
			piece2.position[axis] = cut.end[axis]
			piece2.size[axis] = hi - cut.end[axis]
			out.append(piece2)
			rest.size[axis] = cut.end[axis] - rest.position[axis]
	return out


func _add_box(bx: AABB) -> void:
	if bx.size.x < 0.02 or bx.size.y < 0.02 or bx.size.z < 0.02:
		return
	var sh := BoxShape3D.new()
	sh.size = bx.size
	var cs := CollisionShape3D.new()
	cs.shape = sh
	cs.position = bx.get_center()
	_body.add_child(cs)


# --- the facade with the shop front cut out ------------------------------------------------------------------------------------

func _build_facade() -> void:
	var city = Game.world
	var bm: Variant = city.get(&"_building_mat")
	var blds: Variant = city.get(&"_buildings")
	if not (bm is ShaderMaterial) or blds == null:
		return
	var lot: CityLayout.Lot = _cur["lot"]
	var b = city.building_data[lot.index]
	var mesh: Mesh = blds.meshes.get(b.cls)
	if mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3(lot.w, lot.h, lot.d)), Vector3(lot.cx, 0.0, lot.cz)))
	mm.set_instance_color(0, b.tint)
	mm.set_instance_custom_data(0, Color(b.seed, float(lot.neon), float(b.style), float(b.flags)))
	var m := (bm as ShaderMaterial).duplicate() as ShaderMaterial
	m.shader = SHADER_FAR_CUT if (bm as ShaderMaterial).shader == Buildings.LEAN_SHADER else SHADER_CUT
	var s := _cur
	var a := at(s, float(s["s0"]) + 0.02, -0.4, -1.0)
	var c := at(s, float(s["s1"]) - 0.02, 0.4, H)
	m.set_shader_parameter(&"cut_min", Vector3(minf(a.x, c.x), -1.0, minf(a.z, c.z)))
	m.set_shader_parameter(&"cut_max", Vector3(maxf(a.x, c.x), H, maxf(a.z, c.z)))
	_facade = MultiMeshInstance3D.new()
	_facade.name = "ShopFacade"
	_facade.multimesh = mm
	_facade.material_override = m
	_facade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_facade.custom_aabb = AABB(Vector3(lot.cx - lot.w, -2.0, lot.cz - lot.d), Vector3(lot.w * 2.0, lot.h + 4.0, lot.d * 2.0))
	add_child(_facade)
	(bm as ShaderMaterial).set_shader_parameter(&"shop_hide", Vector2(lot.cx, lot.cz))


# --- the room ------------------------------------------------------------------------------------------------------------------

func _build_room() -> void:
	_mat_room.vertex_color_is_srgb = TowerFloors.crit_on      # w122-critic: the palette is written as sRGB; read as linear by the unshaded material the walls, ceiling and counter burned to white
	var s := _cur
	var kind: StringName = s["kind"]
	var s0 := float(s["s0"])
	var s1 := float(s["s1"])
	var sd := float(s["sd"])
	var d := float(s["d"])
	var rng := RandomNumberGenerator.new()
	rng.seed = int((s["lot"] as CityLayout.Lot).index) * 7919 + 13
	var acc: Color = SIGN_COLOR[kind]
	var pal := _palette(kind)
	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# shell: floor tiles, walls, ceiling (inward faces), with a warm wash toward the ceiling
	var tile := 1.0
	var si := s0
	while si < s1 - 0.01:
		var vi := 0.0
		while vi < d - 0.01:
			var k := (int(floor(si)) + int(floor(vi))) % 2
			var fc: Color = pal["floor"] * (1.0 if k == 0 else 0.86)
			_quad_up(si, vi, minf(si + tile, s1), minf(vi + tile, d), FLOOR_Y if TowerFloors.crit_on else 0.0, fc)     # w122-critic: at y 0 the tiles z-fought the street's ground (black and white stripes on the shop floor)
			vi += tile
		si += tile
	_wall_v(d, s0, s1, 0.0, H, pal["wall"], true)               # back wall
	_wall_s(s0, 0.0, d, 0.0, H, pal["wall"] * 0.92, true)       # left wall
	_wall_s(s1, 0.0, d, 0.0, H, pal["wall"] * 0.92, false)      # right wall
	_box(s0, 0.0, H - 0.02, s1, d, H, pal["ceil"])               # ceiling slab (its underside faces the room)
	# skirting and a coloured band near the ceiling (the shop's colour)
	_box(s0, d - 0.06, 0.0, s1, d, 0.14, pal["wall"] * 0.5)
	_box(s0, d - 0.05, H - 0.55, s1, d, H - 0.4, acc * 0.9)
	# ceiling light strips
	var nl := maxi(2, int((s1 - s0) / 2.6))
	for i in nl:
		var x := lerpf(s0 + 1.0, s1 - 1.0, (float(i) + 0.5) / float(nl))
		_box(x - 0.08, 0.6, H - 0.08, x + 0.08, d - 0.6, H - 0.02, Color(1.0, 0.97, 0.9))
	# the counter (back left), a till on it
	_box(s0 + 0.5, d - 2.3, 0.0, s0 + 2.7, d - 1.6, 1.0, pal["counter"])
	_box(s0 + 0.45, d - 2.35, 1.0, s0 + 2.75, d - 1.55, 1.06, pal["top"])
	_box(s0 + 1.7, d - 2.0, 1.06, s0 + 2.1, d - 1.75, 1.3, Color(0.15, 0.16, 0.18))
	_box(s0 + 1.72, d - 2.02, 1.18, s0 + 2.08, d - 1.99, 1.28, acc)
	match kind:
		&"food": _fill_food(s, rng, pal)
		&"clothes": _fill_clothes(s, rng, pal)
		&"guns": _fill_guns(s, rng, pal)
		&"motors": _fill_motors(s, rng, pal)
		&"electronics": _fill_electronics(s, rng, pal)
		_: _fill_pharmacy(s, rng, pal)
	# the shop front from outside: a dark frame, mullions, a door frame, a sign board over the glass
	var fr := Color(0.08, 0.085, 0.1)
	_box(s0 - 0.12, -0.1, H - 0.02, s1 + 0.12, 0.05, H + 0.16, fr)
	_box(s0 - 0.12, -0.1, 0.0, s0 + 0.02, 0.05, H, fr)
	_box(s1 - 0.02, -0.1, 0.0, s1 + 0.12, 0.05, H, fr)
	_box(sd - DOOR_W * 0.5 - 0.08, -0.1, 0.0, sd - DOOR_W * 0.5, 0.05, H, fr)
	_box(sd + DOOR_W * 0.5, -0.1, 0.0, sd + DOOR_W * 0.5 + 0.08, 0.05, H, fr)
	_box(sd - DOOR_W * 0.5, -0.1, 2.6, sd + DOOR_W * 0.5, 0.05, 2.7, fr)
	for g: Vector2 in [Vector2(s0, sd - DOOR_W * 0.5), Vector2(sd + DOOR_W * 0.5, s1)]:
		var nm := int((g.y - g.x) / 2.2)
		for i in nm:
			var x := g.x + (g.y - g.x) * float(i + 1) / float(nm + 1)
			_box(x - 0.04, -0.08, 0.0, x + 0.04, 0.03, H, fr)
		_box(g.x, -0.08, 0.0, g.y, 0.03, 0.35, fr)                # the kick plate under the glass
	_box(s0 - 0.12, -0.45, H + 0.16, s1 + 0.12, -0.05, H + 0.95, Color(0.05, 0.05, 0.06))     # sign board
	_box(s0 - 0.12, -0.47, H + 0.16, s1 + 0.12, -0.44, H + 0.22, acc)
	_st.generate_normals()
	_room = MeshInstance3D.new()
	_room.name = "ShopRoom"
	_room.mesh = _st.commit()
	_room.material_override = _mat_room
	_room.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_room)
	# glass: the two panes beside the door, a hair outside the facade
	var gst := SurfaceTool.new()
	gst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for g: Vector2 in [Vector2(s0, sd - DOOR_W * 0.5), Vector2(sd + DOOR_W * 0.5, s1)]:
		if g.y - g.x > 0.05:
			var a := at(s, g.x, -0.02, 0.35)
			var b := at(s, g.y, -0.02, 0.35)
			var c := at(s, g.y, -0.02, H)
			var e := at(s, g.x, -0.02, H)
			for v3 in [a, c, b, a, e, c]:
				gst.set_normal(s["n"])
				gst.add_vertex(v3)
	_glass = MeshInstance3D.new()
	_glass.name = "ShopGlass"
	_glass.mesh = gst.commit()
	_glass.material_override = _mat_glass
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glass)
	# the sign
	_sign = Label3D.new()
	_sign.name = "ShopSign"
	_sign.text = str(s["title"])
	_sign.font_size = 96
	_sign.pixel_size = 0.0055
	_sign.outline_size = 10
	_sign.modulate = Color(acc.r * 1.3, acc.g * 1.3, acc.b * 1.3)
	_sign.outline_modulate = Color(0.02, 0.02, 0.03)
	_sign.shaded = false
	_sign.double_sided = false
	_sign.width = (s1 - s0) / _sign.pixel_size
	add_child(_sign)
	_sign.global_position = at(s, (s0 + s1) * 0.5, -0.5, H + 0.56)
	if StreetDetail.on:                     # w1242-street: the sign floated 0.5 m in front of the facade, so from any slant it slid over the neighbours' neon signs in the same band
		_sign.global_position = at(s, (s0 + s1) * 0.5, -SIGN_OUT, H + 0.56)      # (NEON, QUANTA BAR): now flush on the shop's own band, never wider than its front
		var fnt: Font = _sign.font if _sign.font != null else ThemeDB.fallback_font
		var tw := fnt.get_string_size(_sign.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _sign.font_size).x + 2.0 * float(_sign.outline_size)
		var maxw := (s1 - s0) - SIGN_MARGIN
		if tw * _sign.pixel_size > maxw:
			_sign.pixel_size = maxw / tw
	_sign.basis = Basis.looking_at(-(s["n"] as Vector3), Vector3.UP)
	_st = null


func _build_keeper() -> void:
	if not is_instance_valid(_keeper):
		_keeper = InteriorCivilian.new()
		_keeper.name = "ShopKeeper"
		add_child(_keeper)
	var s := _cur
	_keeper.setup(int((s["lot"] as CityLayout.Lot).index))
	var pos := at(s, float(s["s0"]) + 1.6, float(s["d"]) - 0.9, 0.0)
	var n: Vector3 = s["n"]
	_keeper.activate(&"vendor", pos, atan2(-n.x, -n.z), SIGN_COLOR[s["kind"]])
	_keeper.light_with(null)


## Where a buyer stands: in front of the counter, facing the shopkeeper.
func buy_spot() -> Vector3:
	if _cur.is_empty():
		return Vector3.INF
	return at(_cur, float(_cur["s0"]) + 1.6, float(_cur["d"]) - 3.0, 0.0)


## The open shop (empty when none).
func current() -> Dictionary:
	return _cur


## MOTORS: a bought vehicle waits at the kerb in front of the showroom (the CALL-IN rule: `called`, so ENTER prefers it).
static func deliver(kind: StringName) -> Variant:
	if instance == null or instance._cur.is_empty() or not is_instance_valid(Game.vehicles):
		return null
	var s := instance._cur
	var n: Vector3 = s["n"]
	var pos := at(s, float(s["sd"]), -3.4, 0.0)
	var heading := atan2(-(s["t"] as Vector3).x, -(s["t"] as Vector3).z)
	var vm = Game.vehicles
	if vm.list.size() >= vm.cap():
		vm._release_farthest(pos + n * 50.0)
	var v: Variant = vm.spawn_parked(kind, pos, heading)
	if v is Vehicle:
		(v as Vehicle).set_meta(&"called", true)
		bought_rides += 1
		Game.say("%s AT THE KERB" % str(kind).to_upper(), 1.6)
	return v


# --- mesh helpers (frame coordinates: s along the facade, v into the building, y up) --------------------------------------------

func _p(sv: float, v: float, y: float) -> Vector3:
	return at(_cur, sv, v, y)


func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for p in [a, b, c]:
		_st.set_color(col)
		_st.add_vertex(p)


## A quad a-b-c-d (counter-clockwise seen from the side it faces, Godot front = clockwise in screen: emit both windings consistently via `flip`).
func _quad(a: Vector3, b: Vector3, c: Vector3, e: Vector3, col: Color) -> void:
	_tri(a, b, c, col)
	_tri(a, c, e, col)


func _quad_up(sa: float, va: float, sb: float, vb: float, y: float, col: Color) -> void:
	_face(_p(sa, va, y), _p(sb, va, y), _p(sb, vb, y), _p(sa, vb, y), col, Vector3.UP)


func _face(a: Vector3, b: Vector3, c: Vector3, e: Vector3, col: Color, toward: Vector3) -> void:
	var nn := (b - a).cross(c - a)
	if nn.dot(toward) > 0.0:
		_quad(a, e, c, b, col)        # Godot: clockwise front faces
	else:
		_quad(a, b, c, e, col)


func _wall_v(v: float, sa: float, sb: float, y0: float, y1: float, col: Color, face_front: bool) -> void:
	var toward: Vector3 = (_cur["n"] as Vector3) * (1.0 if face_front else -1.0)
	_shade_face(_p(sa, v, y0), _p(sb, v, y0), _p(sb, v, y1), _p(sa, v, y1), col, toward, y0, y1)


func _wall_s(sv: float, va: float, vb: float, y0: float, y1: float, col: Color, face_plus: bool) -> void:
	var toward: Vector3 = (_cur["t"] as Vector3) * (1.0 if face_plus else -1.0)
	_shade_face(_p(sv, va, y0), _p(sv, vb, y0), _p(sv, vb, y1), _p(sv, va, y1), col, toward, y0, y1)


## A wall split in two bands so it brightens toward the ceiling lights.
func _shade_face(a: Vector3, b: Vector3, c: Vector3, e: Vector3, col: Color, toward: Vector3, y0: float, y1: float) -> void:
	var ym := lerpf(y0, y1, 0.55)
	var k := (ym - y0) / (y1 - y0)
	var am := a.lerp(e, k)
	var bm := b.lerp(c, k)
	_face(a, b, bm, am, col * 0.78, toward)
	_face(am, bm, c, e, col * 1.05, toward)


## An axis box in frame coordinates (s0..s1, v0..v1, y0..y1), lit by a fixed fake light (tops brightest).
func _box(sa: float, va: float, ya: float, sb: float, vb: float, yb: float, col: Color) -> void:
	var c000 := _p(sa, va, ya)
	var c100 := _p(sb, va, ya)
	var c110 := _p(sb, vb, ya)
	var c010 := _p(sa, vb, ya)
	var c001 := _p(sa, va, yb)
	var c101 := _p(sb, va, yb)
	var c111 := _p(sb, vb, yb)
	var c011 := _p(sa, vb, yb)
	var n: Vector3 = _cur["n"]
	var t: Vector3 = _cur["t"]
	_face(c001, c101, c111, c011, col * 1.08, Vector3.UP)
	_face(c000, c100, c110, c010, col * 0.55, Vector3.DOWN)
	_face(c000, c100, c101, c001, col * 0.92, n)           # toward the street
	_face(c010, c110, c111, c011, col * 0.8, -n)
	_face(c000, c010, c011, c001, col * 0.72, -t)
	_face(c100, c110, c111, c101, col * 0.84, t)


func _palette(kind: StringName) -> Dictionary:
	var pal := _palette_raw(kind)
	if TowerFloors.crit_on:              # w122-critic: shells a step darker (no near-white room on LOW / MED; the lights and goods keep their colour)
		for k in pal:
			pal[k] = (pal[k] as Color) * 0.85
	return pal


func _palette_raw(kind: StringName) -> Dictionary:
	match kind:
		&"food": return {"floor": Color(0.62, 0.6, 0.55), "wall": Color(0.78, 0.76, 0.68), "ceil": Color(0.75, 0.75, 0.72), "counter": Color(0.2, 0.45, 0.25), "top": Color(0.8, 0.8, 0.75), "shelf": Color(0.7, 0.7, 0.68)}
		&"clothes": return {"floor": Color(0.45, 0.32, 0.24), "wall": Color(0.8, 0.72, 0.72), "ceil": Color(0.78, 0.76, 0.76), "counter": Color(0.18, 0.16, 0.18), "top": Color(0.85, 0.85, 0.85), "shelf": Color(0.32, 0.25, 0.2)}
		&"guns": return {"floor": Color(0.26, 0.26, 0.28), "wall": Color(0.45, 0.42, 0.38), "ceil": Color(0.5, 0.5, 0.5), "counter": Color(0.16, 0.16, 0.18), "top": Color(0.5, 0.58, 0.6), "shelf": Color(0.2, 0.18, 0.16)}
		&"motors": return {"floor": Color(0.55, 0.57, 0.6), "wall": Color(0.7, 0.72, 0.78), "ceil": Color(0.78, 0.78, 0.8), "counter": Color(0.12, 0.12, 0.14), "top": Color(0.9, 0.55, 0.1), "shelf": Color(0.28, 0.28, 0.3)}
		&"electronics": return {"floor": Color(0.3, 0.32, 0.38), "wall": Color(0.55, 0.58, 0.66), "ceil": Color(0.66, 0.68, 0.74), "counter": Color(0.08, 0.1, 0.16), "top": Color(0.75, 0.78, 0.86), "shelf": Color(0.7, 0.72, 0.78)}
	return {"floor": Color(0.74, 0.77, 0.77), "wall": Color(0.8, 0.83, 0.83), "ceil": Color(0.84, 0.85, 0.85), "counter": Color(0.82, 0.85, 0.85), "top": Color(0.3, 0.75, 0.48), "shelf": Color(0.86, 0.88, 0.88)}


## Shelving along the back wall right of the counter and along the right wall, with rows of goods (colours from `goods`).
func _shelves(s: Dictionary, rng: RandomNumberGenerator, pal: Dictionary, goods: Array, tiers := 4, hgt := 2.1, skip_back := false) -> void:
	var s1 := float(s["s1"])
	var s0 := float(s["s0"])
	var d := float(s["d"])
	if not skip_back:
		_shelf_run(true, d - 0.55, s0 + 3.1, s1 - 0.1, rng, pal, goods, tiers, hgt)
	_shelf_run(false, s1 - 0.55, 1.0, d - 0.7, rng, pal, goods, tiers, hgt)


func _shelf_run(along_s: bool, at_c: float, a: float, b: float, rng: RandomNumberGenerator, pal: Dictionary, goods: Array, tiers: int, hgt: float) -> void:
	if b - a < 0.8:
		return
	var sc: Color = pal["shelf"]
	for k in tiers + 1:
		var y := 0.12 + (hgt - 0.12) * float(k) / float(tiers)
		if along_s:
			_box(a, at_c, y, b, at_c + 0.5, y + 0.04, sc)
		else:
			_box(at_c, a, y, at_c + 0.5, b, y + 0.04, sc)
		if k == tiers:
			break
		var x := a + 0.05
		while x < b - 0.2:
			var w := rng.randf_range(0.12, 0.3)
			var h := rng.randf_range(0.14, (hgt - 0.12) / float(tiers) - 0.06)
			var col: Color = goods[rng.randi() % goods.size()]
			if along_s:
				_box(x, at_c + 0.08, y + 0.04, minf(x + w, b - 0.05), at_c + 0.42, y + 0.04 + h, col)
			else:
				_box(at_c + 0.08, x, y + 0.04, at_c + 0.42, minf(x + w, b - 0.05), y + 0.04 + h, col)
			x += w + rng.randf_range(0.02, 0.08)
	if along_s:
		_box(a, at_c + 0.46, 0.0, b, at_c + 0.5, hgt, sc * 0.7)
	else:
		_box(at_c + 0.46, a, 0.0, at_c + 0.5, b, hgt, sc * 0.7)


## A free-standing island in the middle, clear of the walk from the door to the counter. Returns false when there is no room.
func _island_span(s: Dictionary) -> Vector2:
	var s0 := float(s["s0"]) + 3.2
	var s1 := float(s["s1"]) - 1.7
	var sd := float(s["sd"])
	var lo := maxf(s0, sd + 1.3)
	if s1 - lo >= 1.0:
		return Vector2(lo, minf(s1, lo + 1.2))
	return Vector2.ZERO


func _fill_food(s: Dictionary, rng: RandomNumberGenerator, pal: Dictionary) -> void:
	var goods := [Color(0.95, 0.2, 0.15), Color(1.0, 0.8, 0.1), Color(0.2, 0.6, 0.95), Color(0.95, 0.5, 0.1), Color(0.3, 0.8, 0.3), Color(0.9, 0.9, 0.85), Color(0.6, 0.25, 0.6)]
	var d := float(s["d"])
	var s0 := float(s["s0"])
	var s1 := float(s["s1"])
	# fridges along the back wall: lit glass doors with bottles
	var x := s0 + 3.1
	while x < s1 - 1.0:
		_box(x, d - 0.75, 0.0, x + 0.9, d, 2.2, Color(0.85, 0.87, 0.9))
		_box(x + 0.06, d - 0.77, 0.1, x + 0.84, d - 0.74, 2.05, Color(0.75, 0.92, 1.0))
		for row in 4:
			var y := 0.25 + row * 0.47
			var bx := x + 0.1
			while bx < x + 0.78:
				_box(bx, d - 0.7, y, bx + 0.07, d - 0.6, y + 0.26, goods[rng.randi() % goods.size()])
				bx += 0.11
		x += 0.95
	_shelf_run(false, s1 - 0.55, 1.0, d - 1.0, rng, pal, goods, 4, 1.9)
	var isl := _island_span(s)
	if isl != Vector2.ZERO:
		_box(isl.x, 1.6, 0.0, isl.y, d - 2.0, 0.7, Color(0.45, 0.32, 0.2))      # produce crates
		var vy := 1.7
		while vy < d - 2.1:
			var col: Color = [Color(0.9, 0.15, 0.1), Color(1.0, 0.75, 0.1), Color(0.35, 0.8, 0.2), Color(1.0, 0.5, 0.05)][rng.randi() % 4]
			_box(isl.x + 0.03, vy, 0.7, isl.y - 0.03, vy + 0.5, 0.74, Color(0.35, 0.24, 0.15))       # the crate's slats
			var fx := isl.x + 0.08
			while fx < isl.y - 0.16:                                                                  # fruit, a heap of small pieces
				var fz := vy + 0.04
				while fz < vy + 0.42:
					var hh := 0.08 + 0.05 * rng.randf()
					_box(fx, fz, 0.74, fx + 0.11, fz + 0.11, 0.74 + hh, col * (0.8 + 0.3 * rng.randf()))
					fz += 0.14
				fx += 0.14
			vy += 0.55


func _fill_clothes(s: Dictionary, rng: RandomNumberGenerator, pal: Dictionary) -> void:
	var cols := [Color(0.9, 0.2, 0.3), Color(0.15, 0.2, 0.45), Color(0.95, 0.9, 0.85), Color(0.2, 0.2, 0.22), Color(0.3, 0.6, 0.85), Color(0.85, 0.65, 0.2), Color(0.6, 0.3, 0.7)]
	var d := float(s["d"])
	var s0 := float(s["s0"])
	var s1 := float(s["s1"])
	# folded clothes on the back wall
	_shelf_run(true, d - 0.55, s0 + 3.1, s1 - 0.1, rng, pal, cols, 5, 2.2)
	# a hanging rail along the right wall
	_rail(true, s1 - 0.45, 1.0, d - 0.9, rng, cols)
	var isl := _island_span(s)
	if isl != Vector2.ZERO:
		_rail(true, (isl.x + isl.y) * 0.5, 1.8, d - 2.2, rng, cols)
	# two mannequins behind the glass
	for k in 2:
		var mx := lerpf(s0 + 0.8, s1 - 0.8, 0.15 + 0.7 * float(k))
		if absf(mx - float(s["sd"])) < 1.4:
			continue
		var c: Color = cols[rng.randi() % cols.size()]
		_box(mx - 0.25, 0.8, 0.0, mx + 0.25, 1.3, 0.08, Color(0.2, 0.2, 0.2))
		_box(mx - 0.08, 0.95, 0.08, mx + 0.08, 1.15, 0.9, Color(0.15, 0.15, 0.18))
		_box(mx - 0.22, 0.93, 0.9, mx + 0.22, 1.17, 1.5, c)
		_box(mx - 0.1, 0.98, 1.5, mx + 0.1, 1.12, 1.75, Color(0.92, 0.9, 0.88))


func _rail(perp: bool, at_c: float, a: float, b: float, rng: RandomNumberGenerator, cols: Array) -> void:
	var metal := Color(0.7, 0.7, 0.72)
	if perp:
		_box(at_c - 0.03, a, 0.0, at_c + 0.03, a + 0.06, 1.6, metal)
		_box(at_c - 0.03, b - 0.06, 0.0, at_c + 0.03, b, 1.6, metal)
		_box(at_c - 0.03, a, 1.55, at_c + 0.03, b, 1.6, metal)
		var v := a + 0.1
		while v < b - 0.15:
			var c: Color = cols[rng.randi() % cols.size()]
			_box(at_c - 0.24, v, 0.75 + rng.randf_range(0.0, 0.2), at_c + 0.24, v + 0.06, 1.5, c)
			v += 0.1


func _fill_guns(s: Dictionary, rng: RandomNumberGenerator, pal: Dictionary) -> void:
	var d := float(s["d"])
	var s0 := float(s["s0"])
	var s1 := float(s["s1"])
	# pegboard on the back wall with rifles and pistols
	_box(s0 + 3.0, d - 0.08, 0.9, s1 - 0.2, d - 0.02, 3.2, Color(0.3, 0.27, 0.22))
	var y := 1.1
	while y < 3.0:
		var x := s0 + 3.2
		while x < s1 - 1.4:
			var gun := Color(0.1, 0.1, 0.11)
			_box(x, d - 0.14, y, x + 1.1, d - 0.08, y + 0.09, gun)            # barrel and body
			_box(x + 0.75, d - 0.14, y - 0.18, x + 0.85, d - 0.08, y, gun)     # grip
			_box(x - 0.25, d - 0.14, y - 0.06, x, d - 0.08, y + 0.08, Color(0.3, 0.2, 0.12))       # stock
			x += 1.6
		y += 0.5
	# rifles upright in a rack along the right wall
	var v := 1.2
	while v < d - 1.0:
		_box(s1 - 0.35, v, 0.0, s1 - 0.25, v + 0.05, 1.25, Color(0.12, 0.12, 0.13))
		v += 0.32
	_box(s1 - 0.5, 1.0, 0.0, s1 - 0.1, d - 0.8, 0.12, Color(0.25, 0.2, 0.15))
	# a glass display case in the middle with ammunition boxes
	var isl := _island_span(s)
	if isl != Vector2.ZERO:
		_box(isl.x, 1.8, 0.0, isl.y, d - 2.4, 0.85, Color(0.16, 0.16, 0.18))
		_box(isl.x + 0.05, 1.85, 0.85, isl.y - 0.05, d - 2.45, 0.88, Color(0.55, 0.68, 0.72))
		var vv := 1.95
		while vv < d - 2.6:
			_box(isl.x + 0.15, vv, 0.88, isl.y - 0.15, vv + 0.2, 1.0, [Color(0.7, 0.55, 0.2), Color(0.25, 0.4, 0.2), Color(0.6, 0.15, 0.1)][rng.randi() % 3])
			vv += 0.3
	# a target poster
	_box(s0 + 0.1, 1.2, 1.3, s0 + 0.14, 2.2, 2.4, Color(0.95, 0.92, 0.85))
	_box(s0 + 0.14, 1.5, 1.6, s0 + 0.16, 1.9, 2.1, Color(0.85, 0.15, 0.1))


func _fill_motors(s: Dictionary, rng: RandomNumberGenerator, pal: Dictionary) -> void:
	var d := float(s["d"])
	var s0 := float(s["s0"])
	var s1 := float(s["s1"])
	# a turntable with a bike, behind the glass
	var cx := lerpf(s0, s1, 0.3) if absf(lerpf(s0, s1, 0.3) - float(s["sd"])) > 1.6 else lerpf(s0, s1, 0.72)
	_box(cx - 1.2, 0.9, 0.0, cx + 1.2, 3.1, 0.12, Color(0.2, 0.2, 0.22))
	_box(cx - 1.15, 0.95, 0.12, cx + 1.15, 3.05, 0.14, Color(1.0, 0.7, 0.2))
	_bike(cx, 2.0, Color(0.9, 0.15, 0.1))
	# a second bike along the right wall and a tyre stack
	_bike(s1 - 1.0, d - 2.2, Color(0.1, 0.4, 0.9), true)
	for k in 4:
		_box(s0 + 3.2, d - 1.0, 0.25 * k, s0 + 3.9, d - 0.3, 0.25 * k + 0.22, Color(0.06, 0.06, 0.07))
	# posters (lit)
	_box(s0 + 4.3, d - 0.05, 1.3, minf(s0 + 6.3, s1 - 0.3), d - 0.02, 2.8, Color(1.0, 0.75, 0.3))
	_box(s0 + 4.5, d - 0.06, 1.6, minf(s0 + 6.1, s1 - 0.5), d - 0.05, 2.5, Color(0.15, 0.15, 0.2))
	_shelf_run(false, s1 - 0.55, 1.0, d - 3.4, rng, pal, [Color(0.15, 0.15, 0.17), Color(0.9, 0.6, 0.1), Color(0.6, 0.6, 0.62)], 3, 1.6)


func _bike(cs: float, cv: float, col: Color, along_v := false) -> void:
	var tyre := Color(0.05, 0.05, 0.06)
	if not along_v:
		_box(cs - 0.95, cv - 0.06, 0.14, cs - 0.35, cv + 0.06, 0.74, tyre)
		_box(cs + 0.35, cv - 0.06, 0.14, cs + 0.95, cv + 0.06, 0.74, tyre)
		_box(cs - 0.6, cv - 0.15, 0.55, cs + 0.55, cv + 0.15, 0.95, col)
		_box(cs - 0.5, cv - 0.14, 0.95, cs + 0.0, cv + 0.14, 1.05, Color(0.1, 0.1, 0.1))
		_box(cs + 0.5, cv - 0.35, 1.0, cs + 0.58, cv + 0.35, 1.06, Color(0.6, 0.6, 0.62))
	else:
		_box(cs - 0.06, cv - 0.95, 0.0, cs + 0.06, cv - 0.35, 0.6, tyre)
		_box(cs - 0.06, cv + 0.35, 0.0, cs + 0.06, cv + 0.95, 0.6, tyre)
		_box(cs - 0.15, cv - 0.6, 0.41, cs + 0.15, cv + 0.55, 0.81, col)
		_box(cs - 0.14, cv - 0.5, 0.81, cs + 0.14, cv + 0.0, 0.91, Color(0.1, 0.1, 0.1))


func _fill_electronics(s: Dictionary, rng: RandomNumberGenerator, pal: Dictionary) -> void:
	var d := float(s["d"])
	var s0 := float(s["s0"])
	var s1 := float(s["s1"])
	# a wall of screens over the back shelving
	var scr := [Color(0.05, 0.55, 1.0), Color(1.0, 0.12, 0.55), Color(0.1, 0.95, 0.4), Color(1.0, 0.65, 0.05), Color(0.45, 0.25, 1.0)]
	var x := s0 + 3.1
	while x < s1 - 1.0:
		for row in 2:
			var y := 1.75 + row * 0.85
			_box(x, d - 0.1, y, x + 1.05, d - 0.02, y + 0.7, Color(0.05, 0.05, 0.06))
			var c: Color = scr[rng.randi() % scr.size()]
			_box(x + 0.05, d - 0.11, y + 0.05, x + 1.0, d - 0.1, y + 0.65, c)
			_box(x + 0.05, d - 0.115, y + 0.05, x + 0.5, d - 0.11, y + 0.35, c.lerp(Color.WHITE, 0.3))
		x += 1.15
	_shelf_run(true, d - 0.55, s0 + 3.1, s1 - 0.1, rng, pal, [Color(0.1, 0.1, 0.12), Color(0.85, 0.85, 0.9), Color(0.2, 0.4, 0.8), Color(0.9, 0.3, 0.2)], 2, 1.4)
	_shelf_run(false, s1 - 0.55, 1.0, d - 0.7, rng, pal, [Color(0.1, 0.1, 0.12), Color(0.85, 0.85, 0.9), Color(0.2, 0.4, 0.8), Color(0.95, 0.95, 0.95)], 4, 2.0)
	var isl := _island_span(s)
	if isl != Vector2.ZERO:
		_box(isl.x, 1.8, 0.0, isl.y, d - 2.3, 0.9, Color(0.9, 0.9, 0.92))
		var vv := 1.95
		while vv < d - 2.5:
			_box(isl.x + 0.2, vv, 0.9, isl.y - 0.2, vv + 0.15, 0.93, Color(0.08, 0.08, 0.1))      # phones / tablets lying on the table
			_box(isl.x + 0.24, vv + 0.02, 0.93, isl.y - 0.24, vv + 0.13, 0.94, scr[rng.randi() % scr.size()])
			vv += 0.4


func _fill_pharmacy(s: Dictionary, rng: RandomNumberGenerator, pal: Dictionary) -> void:
	var d := float(s["d"])
	var s0 := float(s["s0"])
	var s1 := float(s["s1"])
	var goods := [Color(0.95, 0.95, 0.97), Color(0.3, 0.55, 0.95), Color(0.3, 0.85, 0.5), Color(0.95, 0.4, 0.4), Color(0.95, 0.8, 0.3)]
	_shelves(s, rng, pal, goods, 5, 2.3)
	# a green cross over the counter
	var cx := float(s["s0"]) + 1.6
	_box(cx - 0.45, d - 0.06, 2.5, cx + 0.45, d - 0.02, 2.8, Color(0.2, 1.0, 0.45))
	_box(cx - 0.15, d - 0.06, 2.2, cx + 0.15, d - 0.02, 3.1, Color(0.2, 1.0, 0.45))
	var isl := _island_span(s)
	if isl != Vector2.ZERO:
		_shelf_run(false, isl.x, 1.8, d - 2.4, rng, pal, goods, 3, 1.3)
