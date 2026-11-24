extends RefCounted
## w121-floors probe (dev, not in the suite): how entering a building works today, by REAL FINGERS in the real main scene (phone HUD, phone-only layers on).
## Prints PROBE lines: the nearest tall building, its USE door, what the door does (fade time, where the room is, its size vs the lot), how many floors, and what the
## stick does against the facade. Run: tools/test.sh tests/dev_w121_probe.gd
const TIMEOUT_SECONDS := 140
const Lib := preload("res://tests/w120_reach_lib.gd")


func run(h: Node) -> void:
	var L := Lib.new()
	await L.start(h)
	var city = Game.world
	var best: Dictionary = {}
	var bd := INF
	for b in city.building_data:
		var lot: CityLayout.Lot = b.lot
		if lot.h < 28.0 or b.cls != &"block" or not CityLayout.is_core_block(lot.block_i, lot.block_j):
			continue
		var dd := Vector2(lot.cx, lot.cz).distance_to(Vector2(Game.SPAWN.x, Game.SPAWN.z))
		if dd < bd:
			bd = dd
			best = {"lot": lot, "b": b}
	var lot: CityLayout.Lot = best["lot"]
	print("PROBE tall block lot %d at (%.0f, %.0f) %.1f x %.1f x %.1f m style %d" % [lot.index, lot.cx, lot.cz, lot.w, lot.d, lot.h, best["b"].style])
	var door: Dictionary = {}
	for d in city.doors:
		if int(d["id"]) == lot.index:
			door = d
	print("PROBE its door: type %s at %s" % [door.get("type"), door.get("pos")])
	# walk at the facade beside the door
	var dpos: Vector3 = door["pos"]
	var n: Vector3 = door["normal"]
	var side := n.cross(Vector3.UP).normalized() * 4.0
	var start: Vector3 = dpos + side + n * 4.0
	await L.tp(start, Lib.yaw_to(start, dpos + side - n * 5.0))
	var r := await L.walk(dpos + side - n * 5.0, 4.0, 0.5)
	print("PROBE stick into the facade 4 m beside the door: %.1f m short, blocked by %s" % [r["dist"], r["block"]])
	# the USE door by a finger
	await L.tp(dpos + n * 0.3, Lib.yaw_to(dpos, dpos - n))
	await L.secs(0.6)
	var t0 := Time.get_ticks_msec()
	var label := L.fg.button_label(&"interact")
	await L.press(&"interact")
	var black := 0
	while not InteriorGameplay.active and Time.get_ticks_msec() - t0 < 4000:
		if InteriorGameplay.instance.is_fading():
			black += 1
		await L.f(1)
	await L.f(30)
	print("PROBE ENTER by finger (button %s): inside %s after %d ms, fading frames %d, hero at %s (lot centre %s)" % [label, InteriorGameplay.active, Time.get_ticks_msec() - t0, black, L.p.global_position, Vector2(lot.cx, lot.cz)])
	print("PROBE room bounds %s (lot %.1f x %.1f), InteriorSpace floor_y %.1f max_y %.1f -> floors: 1" % [InteriorSpace.bounds, lot.w, lot.d, InteriorSpace.floor_y, InteriorSpace.max_y])
	print("PROBE stairs in room: %s" % [str(L.p.global_position.y)])
	await L.finish()
