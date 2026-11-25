extends RefCounted
## WAVE 122 SHOPS (w122-shops; owner round 7: "walk into buildings", "not many details on the street", "small silly errors. Are you even checking"). The real main scene, the phone HUD,
## REAL FINGERS (tests/w116_fingers.gd: InputEventScreenTouch / Drag through Input.parse_input_event in window coordinates), reward cards on (CrateReveal._quiet = 0), on the owner's
## phone (844 x 390) and on 2400 x 1080. Start points are set by teleport (setup only); every move is the left thumb on the stick, every action a finger on a drawn button.
##   windows  the LOW / LOW+ facade draws the room behind a window near the street (near_rooms); from the street the lit room of a shop is seen through its glass
##   shops    the hero walks by the stick from the sidewalk through the door into a shop of each of the six kinds (FOOD, CLOTHES, GUNS, MOTORS, ELECTRONICS, PHARMACY)
##   buy      beside the shopkeeper the round context button reads BUY; a finger on it opens the trade window and a finger on BUY buys (a drink, a suit, a scooter at the kerb)
##   map      a finger on the minimap opens the map: the shop is there as a SHOP icon with its name
##   roof     on a roof the stick walks him into the parapet and he stops; a finger on JUMP while walking takes him over it
## W122_SHOPS_OLD=1 switches the wave 122 parts off (ShopFronts.enabled, RoofParapets.enabled): every check marked [old fails] fails.
## Run: tools/test.sh tests/test_shops_w122.gd   (W122_SIZES=844x390 picks one screen)

const TIMEOUT_SECONDS := 280
const Lib := preload("res://tests/w120_reach_lib.gd")

var L: Lib
var host: Node


func run(h: Node) -> void:
	host = h
	var old := OS.get_environment("W122_SHOPS_OLD") == "1"
	var sizes := (OS.get_environment("W122_SIZES") if OS.get_environment("W122_SIZES") != "" else "844x390,2400x1080").split(",")
	for sz in sizes:
		var wh := sz.split("x")
		h.get_tree().root.size = Vector2i(int(wh[0]), int(wh[1]))
		ShopFronts.enabled = not old
		RoofParapets.enabled = not old
		L = Lib.new()
		await L.start(h)
		L.fast(true)
		var prog := Game.progress as Progress
		if prog != null:
			prog.credits = 20000
		print("--- screen %s" % sz)
		await _windows(sz)
		await _shops(sz, sz == sizes[0])
		await _map(sz)
		await _roof(sz)
		await L.finish()
	ShopFronts.enabled = true
	RoofParapets.enabled = true


# --- helpers ---------------------------------------------------------------------------------------------------------------

func _sf() -> ShopFronts:
	return ShopFronts.instance


## The shop of `kind` nearest the spawn: from ShopFronts, or (old code) the same door rule so the walk has a target.
func _shop(kind: StringName) -> Dictionary:
	var sf := _sf()
	if sf == null:
		return {}
	return sf.nearest_of(kind, Game.SPAWN)


func _tap(pos: Vector2) -> void:
	L.fg.down(8, pos)
	await L.f(3)
	L.fg.up(8)
	await L.f(3)


## The left thumb walks him to `q` (the right thumb turns the view toward it); no jump. True when he got within `arrive` m.
func _go(q: Vector3, limit: float, arrive := 0.6) -> bool:
	var t := 0.0
	var still := 0.0
	var last := L.p.global_position
	var pushing := false
	while t < limit:
		var gp := L.p.global_position
		if Lib.flat(gp, q) < arrive:
			break
		var err := wrapf(Lib.yaw_to(gp, q) - L.p.camera_rig.yaw, -PI, PI)
		if absf(err) > 0.4:
			if pushing:
				L.fg.stick(Vector2.ZERO)
				pushing = false
			L.fg.look(-err * 160.0, 0.0, 4)
			await L.f(3)
			t += 0.1
			continue
		if not pushing:
			L.fg.stick(Vector2(0.0, -0.7))
			pushing = true
		await L.secs(0.1)
		t += 0.1
		if absf(err) > 0.15:
			L.fg.look(-err * 160.0, 0.0, 3)
		var mv := Lib.flat(L.p.global_position, last)
		last = L.p.global_position
		still = still + 0.1 if mv < 0.02 else 0.0
		if still > 1.5:
			break
	L.fg.stick(Vector2.ZERO)
	await L.f(3)
	return Lib.flat(L.p.global_position, q) < arrive


# --- windows ---------------------------------------------------------------------------------------------------------------

func _windows(sz: String) -> void:
	var city = Game.world
	Game.set_quality(0)
	await L.f(4)
	var bm: ShaderMaterial = city.get(&"_building_mat")
	var nr := float(bm.get_shader_parameter(&"near_rooms")) if bm != null and bm.get_shader_parameter(&"near_rooms") != null else 0.0
	TestLib.check(nr >= 30.0, "[old fails] %s LOW: a facade window within %.0f m of the street draws the room behind the glass (interior mapping on the phone tier)" % [sz, nr])
	var s := _shop(&"food")
	TestLib.check(not s.is_empty(), "%s there is a FOOD shop on the street" % sz)
	if s.is_empty():
		return
	var n: Vector3 = s["normal"]
	var w: Vector3 = s["wall"]
	var stand := w + n * 7.0 + (s["along"] as Vector3) * 1.5
	await L.tp(stand, Lib.yaw_to(stand, w))
	await L.secs(1.0)
	await L.f(4)
	var sf := _sf()
	var cam := L.p.camera_rig.camera
	var room_pt := ShopFronts.at(s, (float(s["s0"]) + float(s["sd"]) - ShopFronts.DOOR_W * 0.5) * 0.5, float(s["d"]) * 0.6, 1.6)
	var room := sf.get_node_or_null("ShopRoom") as MeshInstance3D if sf != null else null
	var lit := false
	if room != null and room.mesh != null and room.mesh.get_surface_count() > 0:
		var cols: PackedColorArray = room.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		for c in cols:
			if c.get_luminance() > 0.9:
				lit = true
				break
	TestLib.check(room != null and room.is_visible_in_tree() and room.mesh != null and lit and (room.material_override as BaseMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
			"[old fails] %s from the street the shop's room is built and lit (ceiling lights, unshaded: bright at night) (%s)" % [sz, room])
	var see := cam.is_position_in_frustum(room_pt) and not cam.is_position_behind(room_pt)
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, room_pt, Game.L_WORLD)
	var hit := L.p.get_world_3d().direct_space_state.intersect_ray(q)
	var glass_only := hit.is_empty() or absf(((hit["position"] as Vector3) - w).dot(n)) < 0.2
	var cut := false
	if sf != null and sf.get_node_or_null("ShopFacade") != null:
		var m := (sf.get_node("ShopFacade") as GeometryInstance3D).material_override as ShaderMaterial
		var t := ((room_pt - cam.global_position).dot(n))
		var on := cam.global_position + (room_pt - cam.global_position) * (((w - cam.global_position).dot(n)) / t)
		var a: Vector3 = m.get_shader_parameter(&"cut_min")
		var b: Vector3 = m.get_shader_parameter(&"cut_max")
		cut = on.x > a.x and on.x < b.x and on.y > a.y and on.y < b.y and on.z > a.z and on.z < b.z and float((bm.get_shader_parameter(&"shop_hide") as Vector2).x) < 1e8
	TestLib.check(see and glass_only and cut, "[old fails] %s the camera on the sidewalk looks through the glass into the lit room (in view %s, only glass on the way %s, facade cut there %s)" % [sz, see, glass_only, cut])


# --- shops: walk in, buy -------------------------------------------------------------------------------------------------------

func _shops(sz: String, buy: bool) -> void:
	for kind: StringName in ShopFronts.KINDS:
		var s := _shop(kind)
		if s.is_empty():
			TestLib.check(false, "[old fails] %s a %s shop stands on the street" % [sz, kind])
			continue
		var n: Vector3 = s["normal"]
		var w: Vector3 = s["wall"]
		var outside := w + n * 2.8
		await L.tp(outside, Lib.yaw_to(outside, w))
		await L.secs(0.6)
		var ok1 := await _go(w + n * 1.0, 6.0)
		var ok2 := await _go(w - n * 1.4, 4.0)
		var sf := _sf()
		var spot := sf.buy_spot() if sf != null else w - n * 3.0
		var ok3 := ok2 and await _go(spot, 6.0, 0.5)
		var gp := L.p.global_position
		if not ok3:
			var col := L.p.get_last_slide_collision()
			print("  %s walk: open lot %d (shop lot %d), blocked by %s at %s" % [kind, ShopFronts.open_lot, (s["lot"] as CityLayout.Lot).index, (str((col.get_collider() as Node).name) + "/" + str((col.get_collider_shape() as Node).name)) if col != null and col.get_collider_shape() is Node else "-", gp])
		var inside: bool = sf != null and not sf.current().is_empty() and sf.current()["kind"] == kind and -(gp - w).dot(n) > 1.5 and gp.y < 1.0
		TestLib.check(ok1 and ok2 and ok3 and inside and not InteriorGameplay.active, "[old fails] %s by the stick from the sidewalk through the door into the %s shop, to the counter (hero %s, %.1f m in, no fade) %s %s %s" % [sz, kind, gp.snapped(Vector3.ONE * 0.1), -(gp - w).dot(n), ok1, ok2, ok3])
		if not inside:
			TestLib.check(false, "[old fails] %s beside the %s shopkeeper the round context button reads BUY (not inside the shop)" % [sz, kind])
			continue
		await L.secs(0.5)
		var lbl := L.fg.button_label(&"interact")
		TestLib.check(lbl == "BUY", "[old fails] %s beside the %s shopkeeper the round context button reads BUY (%s)" % [sz, kind, lbl])
		if not buy or not (kind in [&"food", &"clothes", &"motors"]) or lbl != "BUY":
			continue
		var prog := Game.progress as Progress
		var c0 := prog.credits
		var suit0 := str(prog.hero.suit)
		var rides0 := ShopFronts.bought_rides
		L.p.hp = L.p.max_hp * 0.5
		var hp0 := L.p.hp
		var pos := L.fg.button(&"interact")
		await _tap(pos)
		await L.f(6)
		var vs := InteriorGameplay.instance.vendor_screen
		TestLib.check(vs.is_open and vs.type == ShopFronts.VENDOR[kind], "%s a finger on BUY opens the %s trade window (%s)" % [sz, kind, vs.type])
		if not vs.is_open:
			continue
		var row := -1
		for i in vs.rows.size():
			if vs.rows[i]["state"] == "buy" and (kind != &"food" or str(vs.rows[i]["kind"]) == "drink") and (kind != &"clothes" or str(vs.rows[i]["id"]).begins_with("suit:")):
				row = i
				break
		TestLib.check(row >= 0, "%s the %s window lists something to buy (%d rows)" % [sz, kind, vs.rows.size()])
		if row < 0:
			vs.close()
			continue
		var what := str(vs.rows[row]["id"])
		await _tap(vs.rects[row].get_center())
		await L.f(4)
		var c1 := prog.credits
		var good := c1 < c0
		match kind:
			&"food": good = good and L.p.hp > hp0
			&"clothes": good = good and str(prog.hero.suit) != suit0 and prog.hero.owned.has(what)
			&"motors": good = good and ShopFronts.bought_rides > rides0
		TestLib.check(good, "%s a finger on BUY buys %s in the %s shop (credits %d -> %d)" % [sz, what, kind, c0, c1])
		await _tap(vs.close_rect.get_center())
		await L.f(4)
		TestLib.check(not vs.is_open and Game.state == &"play", "%s a finger on CLOSE leaves the window and the game runs" % sz)


# --- map -----------------------------------------------------------------------------------------------------------------------

func _map(sz: String) -> void:
	var s := _shop(&"clothes")
	await _tap(L.fg.tc._minimap_rect().get_center())
	await L.f(10)
	var ms := host.get_tree().root.find_child("MapScreen", true, false) as MapScreen
	TestLib.check(ms != null and MapScreen.up, "%s a finger on the minimap opens the big map" % sz)
	if ms == null or not MapScreen.up:
		return
	var found := false
	var kinds := {}
	for mk in ms.collect_markers():
		if mk["kind"] == &"shop" and not s.is_empty() and str(mk.get("label", "")) == str(s["title"]):
			found = true
		if mk["kind"] == &"shop":
			for k: StringName in ShopFronts.KINDS:
				if str(mk.get("label", "")).ends_with(ShopFronts.TITLE[k]):
					kinds[k] = true
	TestLib.check(found and kinds.size() == 6, "[old fails] %s the map has the shops as SHOP icons with their names, all six kinds (%s; %s)" % [sz, s.get("title", "-"), kinds.keys()])
	var cls := ms.find_child("Close", true, false) as Button
	if cls != null:
		await _tap(cls.get_global_rect().get_center())
	await L.f(6)


# --- roof ----------------------------------------------------------------------------------------------------------------------

func _roof(sz: String) -> void:
	# a low flat roof near the spawn: a lot that is not a tower, a single box
	var city = Game.world
	var best: CityLayout.Lot = null
	var bd := INF
	for b in city.building_data:
		var lot: CityLayout.Lot = b.lot
		if b.cls != &"block" or lot.h < 8.0 or lot.h > 40.0 or minf(lot.w, lot.d) < 12.0:
			continue
		var dd := Vector2(lot.cx, lot.cz).distance_to(Vector2(Game.SPAWN.x, Game.SPAWN.z))
		if dd < bd:
			bd = dd
			best = lot
	TestLib.check(best != null, "%s a flat roof near the spawn" % sz)
	if best == null:
		return
	var y := best.h
	var start := Vector3(best.cx, y + 0.3, best.cz)
	var edge := Vector3(best.cx + best.w * 0.5, y, best.cz)
	await L.tp(start, Lib.yaw_to(start, edge + Vector3(5, 0, 0)))
	await L.secs(1.0)
	var on_roof := absf(L.p.global_position.y - y) < 0.6
	await _go(edge + Vector3(4.0, 0.0, 0.0), 6.0, 0.3)
	await L.secs(0.5)
	var gp := L.p.global_position
	TestLib.check(on_roof and absf(gp.y - y) < 0.6 and gp.x < edge.x + 0.05, "[old fails] %s on a roof %.0f m up, the stick walks him into the parapet and he stops on the roof (x %.2f, edge %.2f, y %.1f)" % [sz, y, gp.x, edge.x, gp.y])
	# a jump while walking takes him over it
	L.fg.stick(Vector2(0.0, -1.0))
	await L.secs(0.15)
	await L.press(&"jump")
	await L.secs(1.0)
	L.fg.stick(Vector2.ZERO)
	gp = L.p.global_position
	TestLib.check(gp.x > edge.x + 0.3 or gp.y < y - 1.0, "%s a finger on JUMP while walking takes him over the parapet (x %.2f, y %.1f)" % [sz, gp.x, gp.y])
	await L.secs(3.0)
