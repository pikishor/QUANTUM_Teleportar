extends RefCounted
## Probe of the touch audit engine: the play HUD on foot, MORE, car, helicopter, snake flight, interior.
const TIMEOUT_SECONDS := 140
const Audit := preload("res://tests/touch_audit_lib.gd")


func run(h: Node) -> void:
	var a := Audit.new()
	if not await a.boot(h, "probe2"):
		TestLib.check(false, "boot")
		return
	var prog := Game.progress as Progress
	prog.new_campaign()
	Game.state = &"play"
	await a.frames(30)
	var p := Game.player as Player
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	(Game.enemies as EnemyManager).clear()
	print("STATE ", Game.state, " ids ", a.hud_ids(), " tut ", a.hud.tutorial() != null and a.hud.tutorial().get("active"))
	await a.press_hud_frame("foot")
	print("MORE tap ", await a.tap_hud("more"), " open ", a.tc.more_open, " ids ", a.hud_ids())
	await a.press_hud_frame("foot+more")
	await a.tap_hud("more")
	# car
	var vm := Game.vehicles as VehicleManager
	var car := vm.spawn_parked(&"sedan", p.global_position + Vector3(3.0, 0.3, 0.0), 0.0)
	print("car ", car, " dist ", car.global_position.distance_to(p.global_position) if car != null else -1.0)
	print("USE shows ", await a.until(func() -> bool: return not a.hud_button("interact").is_empty(), 300), " ids ", a.hud_ids())
	print("ENTER tap ", await a.tap_hud("interact"))
	print("in car ", await a.until(func() -> bool: return p.vehicle != null, 300), " ids ", a.hud_ids())
	await a.press_hud_frame("car")
	await a.tap_hud("more")
	print("car more ", a.hud_ids())
	await a.press_hud_frame("car+more")
	await a.tap_hud("more")
	print("EXIT tap ", await a.tap_hud("interact"))
	print("out of car ", await a.until(func() -> bool: return p.vehicle == null, 300))
	if p.vehicle != null:
		vm.exit_vehicle()
	for kind: StringName in [&"heli", &"plane", &"gunship", &"tank"]:
		var n0 := vm.list.size()
		print(DemoMenu.spawn_vehicle(kind))
		var hv: Vehicle = null
		for v: Vehicle in vm.list:
			if is_instance_valid(v) and v.kind == kind:
				hv = v
		if hv == null:
			print(kind, " NOT SPAWNED")
			continue
		await a.pframes(30)
		vm.enter(hv)
		await a.pframes(20)
		print(kind, " in ", p.vehicle == hv, " ids ", a.hud_ids())
		await a.press_hud_frame(String(kind))
		await a.tap_hud("more")
		await a.press_hud_frame(String(kind) + "+more")
		await a.tap_hud("more")
		if Game.state != &"play":
			print("STATE LEFT PLAY ", Game.state)
			Game.state = &"play"
		print(kind, " EXIT tap ", await a.tap_hud("interact"), " out ", await a.until(func() -> bool: return p.vehicle == null, 300))
		if p.vehicle != null:
			vm.exit_vehicle()
		await a.pframes(20)
		if is_instance_valid(hv):
			hv.global_position += Vector3(0, -500, 0)
		await a.pframes(5)
	# snake flight
	p.global_position += Vector3(0, 60, 0)
	await a.pframes(30)
	print("air ids ", a.hud_ids(), " airtime ", p.air_time, " mode ", p.snake.mode)
	print("FLY tap ", await a.tap_hud("fly", 8))
	await a.pframes(20)
	print("mode ", p.snake.mode, " ids ", a.hud_ids())
	await a.press_hud_frame("snake_flight", ["fly"])
	print("LAND tap ", await a.tap_hud("fly"), " label ")
	await a.pframes(120)
	print("mode after land ", p.snake.mode, " y ", p.global_position.y)
	# interior
	print(InteriorTestActions.enter(&"shop"))
	await a.pframes(60)
	print("interior ", InteriorGameplay.active, " ids ", a.hud_ids(), " prompt ", InteriorGameplay.prompt)
	await a.press_hud_frame("interior")
	print("LEAVE tap ", await a.tap_hud("interact", 8), " label ", a.hud_button("interact").get("label", "?"))
	await a.pframes(60)
	print("interior after leave ", InteriorGameplay.active, " prompt '", InteriorGameplay.prompt, "' ids ", a.hud_ids())
	print(a.table())
	for c in a.checks:
		if not c[0]:
			print("CHECK FAIL ", c[1])
	await a.shutdown()
