extends RefCounted
## w122-critic: the walk-in shops look right from inside. The real main scene at 844x390, phone HUD, REAL FINGERS (the left thumb on the stick from the sidewalk through
## the door), reward cards on. Then the shop room as built:
##   floor   the floor tiles lie above the street ground (at y 0 they z-fought it: black and white stripes over the floor, frame s1_food_b_in)
##   window  a finger on BUY opens the trade window under the shop's own sign name; after a finger buys, the BOUGHT line does not sit on the greeting
##   colour  the room's vertex colours are read as sRGB, so no wall / ceiling / counter is drawn near white (they burned to white on LOW and MED)
## W122C_OLD=1: the builders' code (TowerFloors.crit_on off).   Run: tools/test.sh tests/test_shop_look_w122c.gd
const TIMEOUT_SECONDS := 200
const Lib := preload("res://tests/w120_reach_lib.gd")
var L: Lib


func run(h: Node) -> void:
	TowerFloors.crit_on = OS.get_environment("W122C_OLD") != "1"
	VendorScreen.crit_on = TowerFloors.crit_on
	h.get_tree().root.size = Vector2i(844, 390)
	L = Lib.new()
	await L.start(h)
	L.fast(true)
	for kind: StringName in [&"food", &"pharmacy", &"motors"]:
		var s: Dictionary = ShopFronts.instance.nearest_of(kind, Game.SPAWN)
		if s.is_empty():
			TestLib.check(false, "a %s shop exists" % kind)
			continue
		var n: Vector3 = s["normal"]
		var w: Vector3 = s["wall"]
		var outside := w + n * 2.8
		await L.tp(outside, Lib.yaw_to(outside, w))
		await L.secs(0.6)
		await L.walk(w + n * 1.0, 6.0, 0.6, 0.7)
		var r := await L.walk(w - n * 1.6, 5.0, 0.6, 0.7)
		var inside := ShopFronts.inside(L.p.global_position)
		TestLib.check(inside, "%s: by the stick from the sidewalk into the shop (%s)" % [kind, L.p.global_position.snapped(Vector3.ONE * 0.1)])
		var room := ShopFronts.instance._room as MeshInstance3D
		if room == null or room.mesh == null:
			TestLib.check(false, "%s: the shop room is built" % kind)
			continue
		var a := room.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var cs: PackedColorArray = a[Mesh.ARRAY_COLOR]
		var low := INF
		for i in vs.size():
			if ns[i].y > 0.9 and (room.global_transform * vs[i]).y < 0.2:
				low = minf(low, (room.global_transform * vs[i]).y)
		# the shell and counter colours as the unshaded room material draws them (linear)
		var mat := room.material_override as BaseMaterial3D
		var pal: Dictionary = ShopFronts.instance._palette(kind)
		var hot := []
		for key in ["wall", "ceil", "counter", "top", "floor"]:
			var c: Color = pal[key]
			var lin := c.srgb_to_linear() if mat.vertex_color_is_srgb else c
			if lin.get_luminance() > 0.5:
				hot.append("%s %.2f" % [key, lin.get_luminance()])
		TestLib.check(low > 0.01, "%s: the shop floor lies above the street ground, no z-fight (lowest floor %.3f m)" % [kind, low])
		if kind == &"food":
			await _buy(s)
		TestLib.check(hot.is_empty(), "%s: no wall, ceiling, floor or counter is drawn near white (linear luminance over 0.5: %s)" % [kind, hot])
	TowerFloors.crit_on = true
	VendorScreen.crit_on = true
	await L.finish()


func _buy(s: Dictionary) -> void:
	var spot: Vector3 = ShopFronts.instance.buy_spot()
	await L.walk(spot, 6.0, 0.5, 0.6)
	await L.secs(0.4)
	var prog := Game.progress as Progress
	prog.credits = 5000
	var at := L.fg.button(&"interact")
	TestLib.check(at != Vector2.INF and L.fg.button_label(&"interact") == "BUY", "food: the round context button reads BUY beside the shopkeeper (%s)" % L.fg.button_label(&"interact"))
	if at == Vector2.INF:
		return
	L.fg.down(8, at)
	await L.f(3)
	L.fg.up(8)
	await L.f(6)
	var vs := InteriorGameplay.instance.vendor_screen
	TestLib.check(vs.is_open and vs.shown_title() == str(s["title"]), "food: the trade window carries the shop's sign name (%s, sign %s)" % [vs.shown_title(), s["title"]])
	if not vs.is_open:
		return
	vs.rumour_text = ""
	for i in vs.rows.size():
		if vs.rows[i]["state"] == "buy":
			L.fg.down(8, vs.rects[i].get_center())
			await L.f(3)
			L.fg.up(8)
			await L.f(4)
			break
	var ly := vs.line_ys()
	var gap := absf(float(ly["status"]) - float(ly["greet"]))
	TestLib.check(vs.status != "" and (float(ly["greet"]) < 0.0 or gap > 20.0 * vs._s()), "food: after a buy the BOUGHT line (%s) is not drawn over the greeting (lines %s)" % [vs.status, ly])
	L.fg.down(8, vs.close_rect.get_center())
	await L.f(3)
	L.fg.up(8)
	await L.f(4)
