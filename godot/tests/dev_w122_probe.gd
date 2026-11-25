extends RefCounted
## w122-rooms PROBE (not a check): the real main scene, phone HUD, REAL FINGERS (stick, USE by finger). Enters 6 kinds of building and prints whether the inside matches the outside.
## Run: tools/test.sh tests/dev_w122_probe.gd
const TIMEOUT_SECONDS := 150
const Lib := preload("res://tests/w120_reach_lib.gd")

var L: Lib


func run(h: Node) -> void:
	h.get_tree().root.size = Vector2i(844, 390)
	L = Lib.new()
	await L.start(h)
	L.fast(true)
	var tf := TowerFloors.instance
	tf.nearest(Game.SPAWN)
	print("PROBE towers: %d" % tf.towers.size())
	for kind in [&"office", &"apartment"]:
		var tw := _tower_of(kind)
		if tw.is_empty():
			print("PROBE %s: no tower of this kind" % kind)
			continue
		await _tower(tw)
	# city house (low block lot, USE door)
	var ig := InteriorGameplay.instance
	var city_low := {}
	for d in ig.doors():
		var id := int(d["id"])
		if id < SettlementData.DOOR_BASE and id < Game.world.layout.lots.size():
			var lot: CityLayout.Lot = Game.world.layout.lots[id]
			if lot.h < 20.0 and (d["pos"] as Vector3).distance_to(Game.SPAWN) < 300.0:
				city_low = d
				break
	await _use_door(city_low, "city house")
	var town := {}
	for d in SettlementData.doors():
		if d.get("kind") == &"house":
			town = d
			break
	await _use_door(town, "outskirts house")
	var air_c := Airport.FRAME * Vector3(1150.0, 0.0, -800.0)
	var dd := ig.nearest_door(air_c, 200.0)
	print("PROBE airport hall: nearest door within 200 m of the hangars: %s" % ("none (hangars are solid boxes, not enterable)" if dd.is_empty() else str(dd["type"])))
	dd = ig.nearest_door(Vector3(-135.0, 0.0, -55.0), 25.0)
	print("PROBE army building: door within 25 m of the yard: %s" % ("none (no army building to enter)" if dd.is_empty() else "%s id %d" % [dd["type"], dd["id"]]))
	await L.finish()


func _tower_of(kind: StringName) -> Dictionary:
	var tf := TowerFloors.instance
	var best := {}
	var bd := INF
	for t in tf.towers:
		if t["kind"] == kind:
			var d := TowerFloors.door_pos(t).distance_to(Game.SPAWN)
			if d < bd:
				bd = d
				best = t
	return best


func _tower(tw: Dictionary) -> void:
	var tf := TowerFloors.instance
	var lot: CityLayout.Lot = tw["lot"]
	var door := TowerFloors.door_pos(tw, 4.0)
	tf.open(tw)
	var p0 := tf.route(0)[0]
	tf.close()
	await L.tp(door, Lib.yaw_to(door, p0))
	var r := await L.walk(p0, 10.0, 0.6, 0.8)
	var inside := TowerFloors.inside(L.p.global_position)
	var fu := TowerFloors.inner_u(tw) + 2.0 * TowerFloors.IN
	var fv := TowerFloors.inner_v(tw) + 2.0 * TowerFloors.IN
	var fw := lot.w if absf((tw["t"] as Vector3).x) > 0.5 else lot.d
	print("PROBE tower %s lot %d %.0fx%.0fx%.0f: walked in=%s inside=%s; inside %.1f x %.1f vs outside %.1f x %.1f; levels %s" % [tw["kind"], lot.index, lot.w, lot.d, lot.h, r["reached"], inside, fu, fv, fw, (lot.d if fw == lot.w else lot.w), TowerFloors.levels_of(lot)])
	if inside:
		# stairwell window holes: facade windows on the back wall over the stair shaft (u < SHAFT_L) and on the u=0 wall over v < SHAFT_W
		var n := 0
		for k in tf._levels.size() - 1:
			for w: Rect2 in tf._windows(fu, TowerFloors.IN, k, tw["b"].style):
				if w.position.x < TowerFloors.SHAFT_L + TowerFloors.SW_T:
					n += 1
		print("PROBE   stairwell windows that open onto the street (back wall over the shaft): %d" % n)
		var furn := 0
		var kinds := {}
		for k in range(1, tf._levels.size() - 1):
			for b: Array in tf._room_boxes(k):
				furn += 1
		print("PROBE   room boxes on floors 1..n: %d (vertex-colour boxes, no texture)" % furn)
		var on_floor := 0
		for e in (Game.enemies as EnemyManager).get_children():
			if e is Node3D and TowerFloors.inside((e as Node3D).global_position):
				on_floor += 1
		print("PROBE   enemies / NPCs inside the tower: %d" % on_floor)
	await L.tp(TowerFloors.door_pos(tw, 60.0), 0.0)
	await L.secs(0.5)


func _use_door(d: Dictionary, what: String) -> void:
	if d.is_empty():
		print("PROBE %s: no door found" % what)
		return
	var pos: Vector3 = d["pos"]
	var n: Vector3 = d["normal"]
	await L.tp(pos + n * 0.5, Lib.yaw_to(pos, pos - n))
	await L.secs(0.6)
	var pressed := L.fg.press(6, &"interact")
	await L.f(4)
	L.fg.up(6)
	var t := 0.0
	while t < 4.0 and not InteriorGameplay.active:
		await L.secs(0.25)
		t += 0.25
	var b := InteriorSpace.bounds
	var outside := "?"
	if int(d["id"]) < SettlementData.DOOR_BASE:
		var lot: CityLayout.Lot = Game.world.layout.lots[int(d["id"])]
		outside = "%.1f x %.1f x %.1f m (lot %d)" % [lot.w, lot.d, lot.h, lot.index]
	print("PROBE %s (%s): USE by finger=%s entered=%s inside room %.1f x %.1f, ceiling %.1f m at %s vs outside %s" % [what, d["type"], pressed, InteriorGameplay.active, b.size.x, b.size.y, InteriorSpace.max_y - InteriorSpace.floor_y - 2.0, b.get_center(), outside])
	if InteriorGameplay.active:
		InteriorGameplay.instance.leave(true)
		await L.secs(0.5)
