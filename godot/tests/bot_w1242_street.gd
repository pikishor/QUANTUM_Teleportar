extends RefCounted
## w1242-street LOOK bot (frames only, placement by teleport): the street at eye height (kerb props, storefronts, a junction name sign, a bus stop, the walk-in shop sign,
## a tower lobby window from inside).
##   W1242_OUT=<dir> BOT_RES=1200x540 BOT_USER_ARGS=--touch ENGINE_ARGS="--fixed-fps 30" QUALITY=0 BOT_TIMEOUT=500 tools/bot.sh res://tests/bot_w1242_street.gd /tmp/x 100000 1
var _started := false
var _done := false
var tree: SceneTree
var p: Player
var out := ""


func step(_t: float, _dt: float) -> bool:
	if _started:
		return _done
	tree = Engine.get_main_loop() as SceneTree
	if tree.get_first_node_in_group(&"hud") == null or not is_instance_valid(Game.player):
		return false
	_started = true
	_run()
	return false


func frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func shot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png("%s/%s.png" % [out, nm])
	print("W1242 shot ", nm, " pos ", p.global_position.snapped(Vector3(0.1, 0.1, 0.1)))


func place(pos: Vector3, look: Vector3, n := 90, pitch := -0.05) -> void:
	var yaw := atan2(-(look.x - pos.x), -(look.z - pos.z))
	p.teleport_to(pos)
	p.velocity = Vector3.ZERO
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	await frames(n)


func _run() -> void:
	out = OS.get_environment("W1242_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	Game.state = &"play"
	CrateReveal._quiet = 0
	p = Game.player as Player
	if Encounters.current != null:
		Encounters.current.enabled = false
	TestMode.god = true
	var city = Game.world
	if city.get(&"day_night") != null:
		city.day_night.set_hour(11.0)
	var only := OS.get_environment("W1242_ONLY")
	if only == "lobby":
		await _lobby()
		_done = true
		return
	if only == "close":
		await _close()
		_done = true
		return
	await place(Vector3(-20, 0.2, 11), Vector3(-90, 0, 11), 60)
	await shot("street_a")
	await place(Vector3(-62, 0.2, 11.6), Vector3(-10, 0.5, 11.6), 60)
	await shot("street_b")
	# a junction (name sign) near the spawn
	await place(Vector3(-24, 0.2, 13), Vector3(-30, 2.5, 30), 60)
	await shot("junction")
	# the nearest city door with a storefront
	var best: Dictionary = {}
	var bd := 1e9
	for d: Dictionary in city.doors:
		var w: Vector3 = d["wall"]
		var dist := w.distance_to(Game.SPAWN)
		if dist < bd and dist > 15.0 and not (ShopFronts.FROM_TYPE.has(d["type"]) or ShopFronts.OTHER_TYPES.has(d["type"])):
			bd = dist
			best = d
	if not best.is_empty():
		var w2: Vector3 = best["wall"]
		var n2: Vector3 = best["normal"]
		var t2 := Vector3(-n2.z, 0, n2.x)
		await place(w2 + n2 * 7.0 + t2 * 3.0 + Vector3(0, 0.2, 0), w2 + Vector3(0, 1.6, 0))
		await shot("storefront")
	# bus stop
	var st: Array = StreetLife.bus_stops.duplicate()
	st.sort_custom(func(a, b): return a.distance_to(Game.SPAWN) < b.distance_to(Game.SPAWN))
	var sp: Vector3 = st[0]
	await place(sp + Vector3(6, 0.2, 6), sp, 150)
	await shot("bus_stop")
	await _close()
	_done = true


func _lobby() -> void:
	var tws: Array = TowerFloors.instance.towers.duplicate()
	tws.sort_custom(func(a, b): return TowerFloors.door_pos(a, 1.3).distance_to(Game.SPAWN) < TowerFloors.door_pos(b, 1.3).distance_to(Game.SPAWN))
	var tw: Dictionary = tws[0]
	await place(TowerFloors.door_pos(tw, 2.0) + Vector3(0, 0.3, 0), TowerFloors.door_pos(tw, -4.0), 60)
	var dp := TowerFloors.door_pos(tw, -7.0)
	var outp := TowerFloors.door_pos(tw, 3.0)
	var side := (outp - dp).normalized().cross(Vector3.UP) * 6.0
	p.global_position = dp + Vector3(0, 0.1, 0)
	p.velocity = Vector3.ZERO
	var yaw := atan2(-(outp.x + side.x - dp.x), -(outp.z + side.z - dp.z))
	p.camera_rig.reset_view(yaw, 0.0)
	p.yaw = yaw
	await frames(90)
	print("W1242 lobby open_lot ", TowerFloors.open_lot, " panes ", TowerFloors.instance.glass_panes, " inside ", TowerFloors.inside(p.global_position))
	await shot("lobby_inside")


func _close() -> void:
	var city = Game.world
	# walk-in shop sign
	if ShopFronts.instance != null and not ShopFronts.instance.shops.is_empty():
		var shops: Array = ShopFronts.instance.shops.duplicate()
		shops.sort_custom(func(a, b): return (a["base"] as Vector3).distance_to(Game.SPAWN) < (b["base"] as Vector3).distance_to(Game.SPAWN))
		var s: Dictionary = shops[0]
		var bp: Vector3 = s["base"]
		var nn: Vector3 = s["n"]
		await place(bp + nn * 9.0 + Vector3(0, 0.2, 0), bp + Vector3(0, 3.5, 0), 90, 0.12)
		await shot("shop_sign")
	# tower lobby window from inside
	if TowerFloors.instance != null and not TowerFloors.instance.towers.is_empty():
		var tws: Array = TowerFloors.instance.towers.duplicate()
		tws.sort_custom(func(a, b): return TowerFloors.door_pos(a, 1.3).distance_to(Game.SPAWN) < TowerFloors.door_pos(b, 1.3).distance_to(Game.SPAWN))
		var tw: Dictionary = tws[0]
		var dp := TowerFloors.door_pos(tw, -7.0)
		var outp := TowerFloors.door_pos(tw, 3.0)
		var side := (outp - dp).normalized().cross(Vector3.UP) * 6.0
		await place(dp + Vector3(0, 0.3, 0), outp + side + Vector3(0, 1.8, 0), 120)
		await shot("lobby_glass")
	# the new kinds close up: the nearest street name sign, traffic sign, news box, billboard (new code only)
	if StreetDetail.instance != null:
		for k in [StreetDetail.NAME_SIGN, StreetDetail.TRAFFIC_SIGN, StreetDetail.NEWS_BOX, StreetDetail.BILLBOARD]:
			var bestp: Dictionary = {}
			var bd2 := 1e9
			for pl: Dictionary in StreetDetail.instance.placements:
				if int(pl["kind"]) == k and (pl["pos"] as Vector3).distance_to(Game.SPAWN) < bd2:
					bd2 = (pl["pos"] as Vector3).distance_to(Game.SPAWN)
					bestp = pl
			if bestp.is_empty():
				continue
			var pp: Vector3 = bestp["pos"]
			var far := 22.0 if k == StreetDetail.BILLBOARD else 5.0
			var cam_at := Vector3(pp.x, 0.2, pp.z) + Vector3(far * 0.7, 0, far * 0.7)
			while CityLayout.on_road(cam_at.x, cam_at.z) == false and Game.world.layout.lot_at(cam_at.x, cam_at.z, 0.5) != null:
				cam_at += Vector3(-0.5, 0, -0.5)
			await place(cam_at, pp + Vector3(0, 2.5 if k != StreetDetail.BILLBOARD else 3.0, 0), 60, 0.1 if k == StreetDetail.BILLBOARD else 0.0)
			await shot("kind_%s" % StreetDetail.KIND_NAMES[k])
	_done = true
