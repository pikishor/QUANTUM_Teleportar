extends RefCounted
## Wave 129 AIRFIELD DRAWS (owner: inside a vehicle on the airfield the frame was over budget: MED 155-171 / 140, LOW 116-131 / 100, LOW with 9 tanks about 150).
## Real main scene at a 20:9 phone window, touch HUD on, reward cards ON (CrateReveal._quiet = 0). The hero walks up to each parked machine and boards it by REAL FINGERS
## (tests/w116_fingers.gd: the left thumb on the stick until the context button says ENTER, then a tap on it). Each view is measured at 4 headings (the right thumb swipes the view
## round) and the WORST frame counts: total draws (with shadow passes and every canvas layer) and total triangles must stay inside PerfProbe.BUDGETS of the tier (LOW+ its
## own tighter budget). The touch layout is judged the way the gate judges it (PerfProbe.HUD_TOUCH_MAX_DRAWS: what the touch layout may add to a frame): the canvas draws of
## the touch layer (measured by hiding it) are allowed on top of the budget up to that cap, never more.
## Views: on foot at the HELI LINE, the PLANE LINE, the apron gates, the hangars and the ARMY BASE; boarded in a fighter on the apron, a helicopter on the heli line, a tank at the
## ARMY BASE with 9 tanks parked in front, and flying a plane over the outskirts.
## Needs a real renderer (prints a NOTE and checks nothing on the dummy renderer of --headless):
##   tools/air_perf.sh [tiers]          (xvfb, Vulkan Mobile, one process per tier; tools/perf_report.sh runs it with PERF_CHECK=1)
##   W129A_OLD=1   the old airfield code (AirDraws.old): every [old fails] view must then go over the budget.      AIR_VIEWS=foot_heli,tank9   a subset

const Fingers := preload("res://tests/w116_fingers.gd")
const YAWS := 4
var host: Node
var fg: Fingers
var p: Player
var vm: VehicleManager
var tier := 1
var budget := {}
var real := true
var worst := {}                      ## view -> [draws, prims, touch canvas draws]


func _f(n: int) -> void:
	await TestLib.frames(host, n)


func _until(cond: Callable, frames: int) -> bool:
	for i in frames:
		if cond.call():
			return true
		await _f(1)
	return cond.call()


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	var win_size := host.get_window().size
	host.get_window().size = Vector2i(1200, 540)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await _f(20)
	Game.state = &"play"
	CrateReveal._quiet = 0
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	fg = Fingers.new(host)
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	TestMode.god = true
	p.max_hp = 1.0e6
	p.hp = 1.0e6
	DemoMenu.set_time(13.0)
	TestMode.set_weather("CLEAR")
	TestLib.check(fg.tc != null and fg.tc.controls_on, "the touch HUD is on")
	tier = clampi(Game.quality, 0, 2)
	budget = PerfProbe.BUDGETS[tier].duplicate()
	if Game.low_plus and tier == 0:
		budget.merge(PerfProbe.LOW_PLUS_BUDGET, true)
	await _f(10)
	real = int(PerfProbe.snapshot(host.get_viewport())["total_draws"]) > 0
	if not real:
		print("NOTE: dummy renderer (--headless): the airfield draw budget is checked under xvfb only (tools/air_perf.sh)")
	var only := OS.get_environment("AIR_VIEWS").split(",", false)
	var views := ["foot_heli", "foot_plane", "foot_gates", "foot_hangar", "foot_base", "jet", "heli", "tank9", "flight"]
	for v: String in views:
		if not only.is_empty() and not only.has(v):
			continue
		await call("_v_" + v)
		await _leave()
	if real:
		for v: String in worst:
			var w: Array = worst[v]
			var allow := mini(int(w[2]), PerfProbe.HUD_TOUCH_MAX_DRAWS)
			TestLib.check(int(w[0]) <= int(budget["draws"]) + allow and int(w[1]) <= int(budget["prims"]),
				"%s: worst frame %d draws (touch layer %d, allowed %d of it), %d triangles (budget %d + %d / %d, tier %d%s)" % [v, w[0], w[2], allow, w[1], budget["draws"], allow, budget["prims"], tier, " LOW+" if Game.low_plus else ""])
	fg.up_all()
	CrateReveal._quiet = -1
	host.get_window().size = win_size
	Game.force_touch = false
	main.queue_free()
	await _f(2)


## Worst total draws / triangles over YAWS headings (the right thumb swipes the view a quarter turn each time), 20 frames settled per heading.
func _measure(view: String, settle := 45) -> void:
	await _f(settle)
	var wd := 0
	var wp := 0
	var px_per_turn: float = await _px_quarter()
	for i in YAWS:
		if i > 0:
			fg.look(px_per_turn, 0.0, 8)
		await _f(12)
		var hd := 0
		var hv := 0
		var hc := 0
		for k in 4:
			await _f(1)
			var s := PerfProbe.snapshot(host.get_viewport())
			wd = maxi(wd, int(s["total_draws"]))
			wp = maxi(wp, int(s["total_prims"]))
			if int(s["total_draws"]) >= hd:
				hd = int(s["total_draws"])
				hv = int(s["draws"])
				var rid := host.get_viewport().get_viewport_rid()
				hc = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		if OS.get_environment("AIR_VERBOSE") != "":
			print("AIR   %s heading %d: total %d  3d %d  canvas %d  shadow %d" % [view, i, hd, hv, hc, hd - hv - hc])
	var touch := await _touch_cost()
	worst[view] = [wd, wp, touch]
	print("AIR VIEW %s tier %d: worst %d draws %d prims, touch layer %d (vehicle %s)" % [view, tier, wd, wp, touch, str(p.vehicle.kind) if p.vehicle != null else "-"])


## Canvas draws of the touch layer now (hidden for two frames: the difference of the main viewport's canvas draws).
func _touch_cost() -> int:
	if not real or fg.tc == null:
		return 0
	var layer: CanvasLayer = fg.tc                                     # TouchControls is the touch layer itself
	var rid := host.get_viewport().get_viewport_rid()
	var a := 0
	var b := 0
	for i in 3:
		await _f(1)
		a = maxi(a, RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
	layer.visible = false
	await _f(2)
	b = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	layer.visible = true
	await _f(2)
	return maxi(0, a - b)


## Canvas pixels of a right-thumb swipe that turns the view about a quarter turn (measured once on the camera's yaw).
var _quarter := 0.0
func _px_quarter() -> float:
	if _quarter > 0.0:
		return _quarter
	var rig := p.camera_rig
	var y0: float = rig.yaw if &"yaw" in rig else p.yaw
	fg.look(200.0, 0.0, 8)
	await _f(4)
	var y1: float = rig.yaw if &"yaw" in rig else p.yaw
	var d := absf(wrapf(y1 - y0, -PI, PI))
	_quarter = clampf(200.0 * (PI * 0.5) / maxf(d, 0.05), 80.0, 1100.0)
	return _quarter


func _stand(at_local: Vector3, look_local: Vector3) -> void:
	var w := Airport.to_world(at_local)
	w.y = TerrainHeight.height_at(w.x, w.z) + 0.3
	var lw := Airport.to_world(look_local)
	var d := lw - w
	var yaw := atan2(-d.x, -d.z)
	p.teleport_to(w)                                       # setup: the hero is put at the view (the measured thing is the frame, not the walk)
	p.yaw = yaw
	p.camera_rig.reset_view(yaw, -0.1)
	vm._spawn_t = 0.0
	await _f(4)


## Walks up to `v` with the left thumb until the context button says ENTER, then taps it. True when aboard.
func _board(v: Vehicle) -> bool:
	if v == null:
		return false
	var dd := v.global_position - p.global_position
	p.camera_rig.reset_view(atan2(-dd.x, -dd.z), -0.1)
	await _f(3)
	fg.stick(Vector2(0.0, -1.0))
	await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 600)
	fg.stick(Vector2.ZERO)
	await _f(3)
	if fg.press(2, &"interact"):
		await _f(4)
		fg.up(2)
	await _until(func() -> bool: return p.vehicle == v, 90)
	if p.vehicle != v:
		print("AIR board failed: label '%s', %.1f m from %s" % [fg.button_label(&"interact"), p.global_position.distance_to(v.global_position), v.kind])
	return p.vehicle == v


func _leave() -> void:
	if p.vehicle == null:
		return
	if fg.press(2, &"interact"):
		await _f(4)
		fg.up(2)
	await _until(func() -> bool: return p.vehicle == null, 90)
	if p.vehicle != null:
		vm.exit_vehicle()                                         # cleanup only between views
	await _f(10)


## The nearest parked vehicle of a class (or any) to a local spot, after the spawner has filled the place.
func _near(local: Vector3, cls := &"") -> Vehicle:
	var w := Airport.to_world(local)
	var best: Vehicle = null
	var bd := 1.0e9
	await _f(30)
	for v: Vehicle in vm.list:
		if not is_instance_valid(v) or not v.active or not v.visible:
			continue
		if cls != &"" and VehicleSpecs.cls_of(v.kind) != cls:
			continue
		var d := Vector2(v.global_position.x - w.x, v.global_position.z - w.z).length()
		if d < bd:
			bd = d
			best = v
	return best if bd < 80.0 else null


func _v_foot_heli() -> void:
	await _stand(Vector3(1318.0, 0.0, -760.0), Vector3(1334.0, 3.0, -700.0))
	await _measure("foot_heli")


func _v_foot_plane() -> void:
	await _stand(Vector3(1288.0, 0.0, -700.0), Vector3(1307.0, 3.0, -620.0))
	await _measure("foot_plane")


func _v_foot_gates() -> void:
	await _stand(Vector3(1190.0, 0.0, -720.0), Vector3(1160.0, 3.0, -640.0))
	await _measure("foot_gates")


func _v_foot_hangar() -> void:
	await _stand(Vector3(1156.0, 0.0, -934.0), Vector3(1132.0, 1.0, -944.0))
	await _measure("foot_hangar")


func _v_foot_base() -> void:
	await _stand(TankRoster.BASE_LOCAL + Vector3(-22.0, 0.0, -30.0), TankRoster.BASE_LOCAL + Vector3(0.0, 0.0, 60.0))
	await _measure("foot_base")


func _v_jet() -> void:
	await _stand(Vector3(1196.0, 0.0, -900.0), Vector3(1182.0, 0.0, -908.0))
	var v := await _near(Vector3(1182.0, 0.0, -908.0), &"plane")
	var ok := await _board(v)
	TestLib.check(ok, "a finger on ENTER boards the fighter on the apron (%s)" % (str(v.kind) if v != null else "none"))
	await _measure("jet")


func _v_heli() -> void:
	await _stand(Vector3(1318.0, 0.0, -760.0), Vector3(1334.0, 3.0, -760.0))
	var v := await _near(Vector3(1334.0, 0.0, -760.0), &"heli")
	if v == null:                                                     # setup: the heli line is filled by the spawner as the hero comes; put one there when it has not yet
		var w := Airport.to_world(Vector3(1334.0, 0.0, -760.0))
		w.y = TerrainHeight.height_at(w.x, w.z)
		vm._fixed_n += 1
		v = vm.spawn_parked(&"h_utility", w, Airport.heading_world(PI * 0.5))
		if v != null:
			v.set_meta(&"hold", true)
		vm._count_fixed()
		await _f(10)
	var ok := await _board(v)
	TestLib.check(ok, "a finger on ENTER boards a helicopter on the heli line (%s)" % (str(v.kind) if v != null else "none"))
	await _measure("heli")


## A battle tank on the apron, 8 more tanks parked in a fan 25-90 m in front (the w127 view: about 150 draws on LOW).
func _v_tank9() -> void:
	var at := Airport.to_world(Vector3(1255.0, 0.0, -800.0))
	at.y = TerrainHeight.height_at(at.x, at.z)
	var hh := Airport.heading_world(-PI * 0.5)
	var fwd := Vector3(-sin(hh), 0.0, -cos(hh))
	var rt := Vector3(cos(hh), 0.0, -sin(hh))
	vm._reset_all()
	await _f(4)
	vm._fixed_n += 1
	var mine := vm.spawn_parked(&"t_heavy", at, hh)
	mine.set_meta(&"hold", true)
	mine.set_meta(&"called", true)
	vm._count_fixed()
	var kinds := [&"t_heavy", &"t_apc8", &"t_walker", &"t_hover", &"t_mine", &"t_rocket", &"t_halftrack", &"tank"]
	for i in kinds.size():
		var w := at + fwd * (25.0 + 8.0 * float(i)) + rt * (float(i % 4) - 1.5) * 12.0
		w.y = TerrainHeight.height_at(w.x, w.z)
		vm._fixed_n += 1
		var v := vm.spawn_parked(kinds[i], w, hh + 0.6 * float(i))
		if v != null:
			v.set_meta(&"hold", true)
			v.set_meta(&"called", true)
		vm._count_fixed()
	var st := at - fwd * 9.0
	p.teleport_to(st + Vector3(0.0, 0.3, 0.0))
	await _f(20)
	var ok := await _board(mine)
	TestLib.check(ok, "a finger on ENTER boards the battle tank in front of 8 parked tanks")
	p.camera_rig.reset_view(hh, -0.08)
	await _measure("tank9")


## A small plane put 110 m over the outskirts hills (setup), boarded, flown level by the thumb.
func _v_flight() -> void:
	var gx := 1750.0
	var gz := 850.0
	var gy := TerrainHeight.height_at(gx, gz)
	await _stand(Airport.to_local(Vector3(gx, gy, gz)), Airport.to_local(Vector3(gx - 50.0, gy, gz)))
	vm._fixed_n += 1
	var v := vm.spawn_parked(&"plane", p.global_position + Vector3(4.0, 0.0, 0.0), 0.0)
	vm._count_fixed()
	var ok := await _board(v)
	TestLib.check(ok, "a finger on ENTER boards the small plane")
	if ok:
		v.global_position = Vector3(gx, gy + 110.0, gz)    # setup: in the air at cruise (the frame is measured, not the take-off)
		if v.get(&"speed") != null:
			v.set(&"speed", 45.0)
	await _measure("flight", 30)
