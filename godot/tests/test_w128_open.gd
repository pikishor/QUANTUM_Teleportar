extends RefCounted
## WAVE 128 OPEN ITEMS (w128-open): the follow-ups left open by waves 124-127, each check driving the real main scene with REAL fingers (tests/w116_fingers.gd:
## InputEventScreenTouch / ScreenDrag through Input.parse_input_event), Game.force_touch, phone-only layers on (CrateReveal._quiet = 0). Set-up only places the hero and vehicles.
##  1 PROPS: a battle tank driven by the stick into a street lamp knocks it down and rolls on (lamp posts, signals, hydrants, benches stopped tanks dead, as walls: tank missions
##    through the city stalled on them); the drawn lamp disappears with its collider
##  3 DEMO: the title's DEMO button (MORE, then DEMO, by finger) starts the sandbox with GOD MODE and INFINITE AMMO on (they were switched off at every demo start); the demo menu
##    has VEHICLES and AIRCRAFT tabs listing every ground vehicle kind and every aircraft kind, and a finger on an entry puts that vehicle next to the hero (a plane on the runway),
##    where a finger on ENTER boards it; god mode is still on after the launches
##  4 CREWS: a tank crew whose vehicle was freed is dropped by the TankCrews tick (it used to cast the freed object: a SCRIPT ERROR every physics frame and the rest of the tick skipped)
##  5 PLAYER: the weapon number-key poll of every on-foot physics tick (PlayerWeapon.poll_switch) formatted and looked up 229 action names twice a tick (0.1 to 0.17 ms of the
##    2.1 ms PLAYER time); it now reads a cached list of the 8 number keys. The check times it (a generous bound: the old code is 40x over it)
##  2 HULLS: a car driven over a bridge deck by the stick does not touch a van standing on the ground under the deck (hull contacts were x / z only: the van was shoved, and a car on the
##    deck was pushed sideways into the parapet, the wave 127 CI failure)
## W128O_OLD=1 is the code before the fixes: the checks marked [old fails] fail.
## Run: tools/test.sh tests/test_w128_open.gd   (OPEN_PARTS=props,hulls to run some parts)
const TIMEOUT_SECONDS := 140
const Fingers := preload("res://tests/w116_fingers.gd")
const CityColliders := preload("res://scripts/world/city_colliders.gd")

var host: Node
var fg: Fingers
var p: Player
var vm: VehicleManager
var _t := 0.0


func _f(n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame
		await host.get_tree().process_frame


func _step() -> void:
	await host.get_tree().physics_frame
	_t += 1.0 / float(Engine.physics_ticks_per_second) * Engine.time_scale


func _until(cond: Callable, secs: float) -> bool:
	var t0 := _t
	while _t - t0 < secs:
		if cond.call():
			return true
		await _step()
	return cond.call()


func _tap(action: StringName) -> bool:
	if not fg.press(6, action):
		return false
	await _f(4)
	fg.up(6)
	await _f(3)
	return true


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	var old := OS.get_environment("W128O_OLD") == "1"
	CityColliders.knock_on = not old
	VehicleManager.hull_height_on = not old
	DemoMode.god_on_enter = not old
	TestMode.reset_toggles()
	host.get_tree().root.size = Vector2i(1200, 540)
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
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 2.0
	Engine.max_physics_steps_per_frame = 4
	var parts := OS.get_environment("OPEN_PARTS")
	if parts == "" or parts.contains("props"):
		await _props()
	if parts == "" or parts.contains("hulls"):
		await _hulls()
	if parts == "" or parts.contains("demo"):
		await _demo()
	if parts == "" or parts.contains("crews"):
		await _crews()
	if parts == "" or parts.contains("player"):
		await _player_cost()
	fg.up_all()
	CityColliders.knock_on = true
	VehicleManager.hull_height_on = true
	DemoMode.god_on_enter = true
	if DemoMode.active:
		DemoMode.quit()
	TestMode.reset_toggles()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
	CrateReveal._quiet = -1
	Game.state = &"menu"
	Game.force_touch = false
	main.queue_free()
	await _f(2)


## Puts the hero `back` metres behind vehicle `v` and boards it with the stick and a finger on ENTER.
func _board(v: Vehicle, back := 6.0) -> bool:
	var tries: Array[Vector3] = [-v.forward() * (float(v.spec["len"]) * 0.5 + back), v.right() * (float(v.spec["wid"]) * 0.5 + back), -v.right() * (float(v.spec["wid"]) * 0.5 + back)]
	for off: Vector3 in tries:
		fg.up_all()
		await _leave()
		var at := v.global_position + off
		p.teleport_to(Vector3(at.x, v.global_position.y + 0.4, at.z))
		var d := v.global_position - at
		p.yaw = atan2(-d.x, -d.z)
		p.camera_rig.reset_view(p.yaw, -0.1)
		p.velocity = Vector3.ZERO
		await _f(10)
		fg.stick(Vector2(0.0, -0.7))
		await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER" and v.edge_distance(p.global_position) < VehicleSpecs.ENTER_REACH - 0.6, 8.0)
		fg.stick(Vector2.ZERO)
		await _f(3)
		await _tap(&"interact")
		await _until(func() -> bool: return p.vehicle == v, 1.5)
		if p.vehicle == v:
			return true
		print("board %s from %s: label '%s', hero %.1f m off" % [v.kind, off.snapped(Vector3.ONE), fg.button_label(&"interact"), _flat(p.global_position, v.global_position)])
	return false


func _leave() -> void:
	if p.vehicle != null:
		fg.up_all()
		await _tap(&"interact")
		await _until(func() -> bool: return p.vehicle == null, 1.5)


func _clear(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, Game.L_WORLD | Game.L_VEHICLE)
	return space.intersect_ray(q).is_empty()


## The drawn scale of the instance of family `fam` standing at `o` (the windowed family or the plain MultiMesh), -1 when none is found.
func _drawn_scale(fam: String, o: Vector3) -> float:
	for f in Game.world.stream_families():
		if f.name != fam:
			continue
		for cell: PackedFloat32Array in f.cells:
			for k in range(0, cell.size(), f.stride):
				if absf(cell[k + 3] - o.x) < 0.06 and absf(cell[k + 11] - o.z) < 0.06:
					return Vector3(cell[k], cell[k + 4], cell[k + 8]).length()
	return -1.0


# --- 1 PROPS ---------------------------------------------------------------------------------------------------------------------------

func _props() -> void:
	var pc = Game.world.prop_colliders()
	var lamps: Array[Transform3D] = pc.instances_of("Lamps")
	TestLib.check(lamps.size() > 50, "the city has street lamps with colliders (%d)" % lamps.size())
	await _ram(lamps, "street lamp", func(o: Vector3) -> bool: return _drawn_scale("Lamps", o) >= 0.0 and _drawn_scale("Lamps", o) < 0.01,
			func(o: Vector3) -> bool: return _drawn_scale("Lamps", o) > 0.5)
	var kits: Array[Transform3D] = []
	for fam in ["KitDrCluster", "KitBin", "KitTransformer", "KitCrates", "KitBench", "KitStall"]:
		kits.append_array(pc.instances_of(fam))
	TestLib.check(kits.size() > 20, "the city has street-kit pieces with colliders (%d)" % kits.size())
	var kw = Game.world.kit_window()
	await _ram(kits, "street-kit piece (bin, crates, transformer, bench)", func(o: Vector3) -> bool: return kw.is_hidden(o), func(o: Vector3) -> bool: return not kw.is_hidden(o))


## A battle tank 12 m behind the nearest prop of `list` with a clear run-up, boarded and driven into it by the stick: it rolls on, the prop is knocked down, `gone` says its drawn
## instance is away; far away it comes back (`back`).
func _ram(list: Array[Transform3D], what: String, gone: Callable, back: Callable) -> void:
	var pc = Game.world.prop_colliders()
	var space := host.get_tree().root.get_world_3d().direct_space_state
	var start_at := p.global_position
	list.sort_custom(func(a: Transform3D, b: Transform3D) -> bool: return _flat(a.origin, start_at) < _flat(b.origin, start_at))
	var pk := ParkedCars.instance
	var lamp := Vector3.INF
	var fwd := Vector3.ZERO
	for xf: Transform3D in list.slice(0, 60):
		var o := xf.origin
		if o.y > 1.0:
			continue
		for k in 4:
			var a := float(k) * TAU / 4.0
			var f := Vector3(sin(a), 0.0, cos(a))
			var r := Vector3(f.z, 0.0, -f.x)
			var ok := true
			for side: float in [-2.4, -1.2, 0.0, 1.2, 2.4]:
				for hy: float in [0.15, 1.0]:
					var y := Vector3(0.0, hy, 0.0) + r * side
					var tail := 1.4 if absf(side) < 1.5 else -1.0
					if not _clear(space, o - f * 18.0 + y, o - f * tail + y) or not _clear(space, o + f * maxf(tail, 1.4) + y, o + f * 12.0 + y):
						ok = false
						break
				if not ok:
					break
			if ok and pk != null:
				for st in range(-16, 13, 3):
					if pk.car_near(o + f * float(st), 2.2) >= 0:
						ok = false
						break
			if ok:
				lamp = o
				fwd = f
				break
		if lamp != Vector3.INF:
			break
	TestLib.check(lamp != Vector3.INF, "a %s with a clear 17 m run-up and 12 m beyond it" % what)
	if lamp == Vector3.INF:
		return
	p.teleport_to(lamp - fwd * 22.0 + Vector3(0.0, 0.4, 0.0))
	await _f(10)
	vm._fixed_n += 1
	var tk := vm.spawn_parked(&"tank", lamp - fwd * 12.0, atan2(-fwd.x, -fwd.z))
	tk.set_meta(&"hold", true)
	vm._count_fixed()
	await _f(6)
	var boarded := await _board(tk)
	TestLib.check(boarded, "a finger on ENTER boards the battle tank behind the %s" % what)
	if not boarded:
		return
	await _f(10)
	var start := tk.global_position
	var knocked0: int = pc.knocked_total
	var seen0: bool = back.call(lamp)
	fg.stick(Vector2(0.0, -1.0))
	var through := await _until(func() -> bool: return (tk.global_position - start).dot(fwd) > 20.0, 12.0)
	fg.stick(Vector2.ZERO)
	var driven := (tk.global_position - start).dot(fwd)
	if not through:
		var tc := tk.move_and_collide(fwd * 0.5, true)
		if tc != null:
			print("ram %s: blocked by %s at %s" % [what, (tc.get_collider() as Node).get_path() if tc.get_collider() is Node else "?", tc.get_position()])
	TestLib.check(through, "[old fails] the stick drives the tank into the %s and on past it (%.1f m driven of 20, it stood 12 m ahead)" % [what, driven])
	TestLib.check(pc.knocked_total > knocked0, "[old fails] the %s is knocked down (%d knocked)" % [what, pc.knocked_total - knocked0])
	TestLib.check(seen0 and gone.call(lamp), "[old fails] the drawn %s disappears with it" % what)
	var standing := false
	for b: StaticBody3D in pc.bodies:
		if _flat(b.global_position, lamp) < 0.5 and b.global_position.y > -100.0:
			standing = true
	TestLib.check(not standing, "no collider is left standing where the %s was" % what)
	await _leave()
	tk.remove_meta(&"hold")
	if tk.active:
		vm._release(tk)
	vm._count_fixed()
	pc.refill(lamp + Vector3(200.0, 0.0, 0.0))
	TestLib.check(back.call(lamp) and pc.down.is_empty(), "the %s stands again once the hero is far away" % what)
	pc.refill(p.global_position)


# --- 2 HULLS ---------------------------------------------------------------------------------------------------------------------------

func _hulls() -> void:
	Bridges.ensure()
	RoadLanes.ensure()
	var b := Bridges.by_id(&"mountain_track_4")
	TestLib.check(not b.is_empty(), "the MOUNTAIN TRACK bridge exists")
	if b.is_empty():
		return
	# the deck point 30 m along, where the gully floor is well under it; the car runs up from 12 m before it along the deck
	var best_s := -1.0
	var best_gap := 0.0
	for s in range(14, 56, 2):
		var pt: Array = Bridges.point_at(b, float(s))
		var c: Vector3 = pt[0]
		var dk := Bridges.deck_y(c.x, c.z, c.y + 0.5)
		var g := TerrainHeight.height_at(c.x, c.z)
		if dk != Bridges.NONE and dk - g > best_gap:
			best_gap = dk - g
			best_s = float(s)
	TestLib.check(best_s > 0.0 and best_gap > 3.2, "a deck point high over the gully floor (%.1f m)" % best_gap)
	if best_s < 0.0:
		return
	var m: Array = Bridges.point_at(b, best_s)
	var mid: Vector3 = m[0]
	var back: Vector3 = (Bridges.point_at(b, best_s - 9.0) as Array)[0]
	var dir := Vector3(mid.x - back.x, 0.0, mid.z - back.z).normalized()
	var deck := Bridges.deck_y(mid.x, mid.z, mid.y + 0.5)
	var ground := TerrainHeight.height_at(mid.x, mid.z)
	p.teleport_to(Vector3(back.x, deck + 0.5, back.z) - dir * 8.0)
	await _f(8)
	# the van stands on the gully floor right under the deck point
	var van := vm.spawn_parked(&"van", Vector3(mid.x, ground, mid.z), atan2(-dir.x, -dir.z))
	van.set_meta(&"hold", true)
	van.global_position.y = ground
	van.base_y = ground
	await _f(4)
	van.global_position.y = ground
	var van0 := van.global_position
	TestLib.check(deck - van0.y > 3.0, "the van stands under the deck (%.2f, deck %.2f)" % [van0.y, deck])
	var car := vm.spawn_parked(&"sedan", Vector3(back.x, deck, back.z) - dir * 2.0, atan2(-dir.x, -dir.z))
	car.set_meta(&"hold", true)
	await _f(6)
	var boarded := await _board(car, 4.0)
	TestLib.check(boarded, "a finger on ENTER boards the sedan on the deck")
	if not boarded:
		van.remove_meta(&"hold")
		vm._release(van)
		return
	var c0 := car.global_position
	var crossed := false
	var worst_side := 0.0
	var ok_y := true
	fg.stick(Vector2(0.0, -0.55))
	var t0 := _t
	while _t - t0 < 6.0:
		await _step()
		var off := car.global_position - c0
		var along := off.dot(dir)
		worst_side = maxf(worst_side, absf(off.dot(Vector3(dir.z, 0.0, -dir.x))))
		var dk := Bridges.deck_y(car.global_position.x, car.global_position.z, deck)
		if dk != Bridges.NONE and car.global_position.y < dk - 1.0:
			ok_y = false
		if along > _flat(c0, mid) + 3.0:
			crossed = true
			break
	fg.stick(Vector2.ZERO)
	var moved := _flat(van.global_position, van0)
	print("hulls: crossed %s, van moved %.2f m, car side drift %.2f m, van y %.2f" % [crossed, moved, worst_side, van.global_position.y])
	TestLib.check(crossed and ok_y, "the stick drives the sedan along the deck over the van's spot (crossed %s, on the deck %s)" % [crossed, ok_y])
	TestLib.check(moved < 0.15, "[old fails] the van on the ground under the deck is not touched by the car above it (moved %.2f m)" % moved)
	await _leave()
	for v: Vehicle in [car, van]:
		v.remove_meta(&"hold")
		if v.active:
			vm._release(v)


# --- 3 DEMO ----------------------------------------------------------------------------------------------------------------------------

func _touch(pos: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventScreenTouch.new()
		e.index = 0
		e.position = host.get_tree().root.get_final_transform() * pos
		e.pressed = down
		Input.parse_input_event(e)
		for i in 2:
			await host.get_tree().physics_frame
			await host.get_tree().process_frame


func _hud_rect(hud: Node, id: StringName) -> Rect2:
	hud.call(&"_ensure_layout")
	for b: Dictionary in hud.get(&"buttons"):
		if b["id"] == id:
			return b["rect"]
	return Rect2()


func _drag(a: Vector2, b: Vector2) -> void:
	var xf := host.get_tree().root.get_final_transform()
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = xf * a
	t.pressed = true
	Input.parse_input_event(t)
	await host.get_tree().process_frame
	for k in range(1, 7):
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = xf * a.lerp(b, float(k) / 6.0)
		Input.parse_input_event(d)
		await host.get_tree().process_frame
	t = InputEventScreenTouch.new()
	t.index = 0
	t.position = xf * b
	t.pressed = false
	Input.parse_input_event(t)
	await host.get_tree().process_frame
	await host.get_tree().process_frame


## Scrolls the demo page by finger drags until the entry is in view, then taps it.
func _tap_entry(dp: DemoPanel, label: String) -> bool:
	dp.layout()
	var it := {}
	for e in dp.items:
		if not e.get("head", false) and String(e["label"]) == label:
			it = e
	if it.is_empty():
		return false
	var r: Rect2 = it["rect"]
	var top := float(dp.call(&"_top"))
	var vis_h := dp.get_viewport().get_visible_rect().size.y - top - 20.0
	var guard := 0
	while (r.position.y - dp.scroll < 0.0 or r.end.y - dp.scroll > vis_h) and guard < 20:
		guard += 1
		var want := clampf(r.position.y - 10.0, 0.0, float(dp.call(&"_max_scroll")))
		var step := clampf(dp.scroll - want, -vis_h * 0.6, vis_h * 0.6)
		if absf(step) < 20.0:
			step = 20.0 * signf(step) if step != 0.0 else -20.0
		var x := r.get_center().x
		var y0 := top + vis_h * 0.5 - step * 0.5
		await _drag(Vector2(x, y0), Vector2(x, y0 + step))
	await _touch(Vector2(r.get_center().x, r.get_center().y + top - dp.scroll))
	return true


func _demo() -> void:
	await _leave()
	var hud := host.get_tree().get_first_node_in_group(&"hud")
	var dp := host.get_tree().root.find_children("*", "DemoPanel", true, false)[0] as DemoPanel
	Engine.time_scale = 1.0
	TestMode.reset_toggles()
	Game.state = &"menu"
	await _f(4)
	await _touch(_hud_rect(hud, &"menu_gear").get_center())
	var dr := _hud_rect(hud, &"demo")
	TestLib.check(dr.size.x > 0.0, "the title's MORE page has the DEMO button")
	await _touch(dr.get_center())
	await _f(6)
	TestLib.check(DemoMode.active and Game.state == &"play", "a finger on DEMO starts the sandbox")
	TestLib.check(TestMode.god and TestMode.infinite_ammo, "[old fails] the demo starts in GOD MODE with INFINITE AMMO (god %s, ammo %s)" % [TestMode.god, TestMode.infinite_ammo])
	if not DemoMode.active:
		return
	await _f(10)
	TestLib.check(_badge_clear(dp) == "", "[old fails] the DEMO badge lies on no touch button on foot (%s)" % _badge_clear(dp))
	var ground := {}
	var air := {}
	for g: Dictionary in DemoMode.vehicle_groups(false):
		for k: StringName in g["kinds"]:
			ground[k] = true
	for g: Dictionary in DemoMode.vehicle_groups(true):
		for k: StringName in g["kinds"]:
			air[k] = true
	for tab: String in ["VEHICLES", "AIRCRAFT"]:
		await _touch(dp.entry_rect().get_center())
		var ti := DemoPanel.TABS.find(tab)
		TestLib.check(dp.is_open and ti >= 0, "[old fails] the demo menu has a %s tab" % tab)
		if ti < 0 or not dp.is_open:
			dp.close()
			continue
		await _touch((dp.call(&"_tab_rects") as Array)[ti].get_center())
		TestLib.check(dp.page == ti, "a finger on %s opens it" % tab)
		var listed := {}
		dp.layout()
		for it in dp.items:
			if not it.get("head", false) and it.get("kind", &"") == &"vehicle":
				listed[it["id"]] = true
		var want: Dictionary = air if tab == "AIRCRAFT" else ground
		var missing := want.keys().filter(func(k) -> bool: return not listed.has(k))
		TestLib.check(want.size() >= (50 if tab == "AIRCRAFT" else 50) and missing.is_empty(), "%s lists every kind (%d, missing %s)" % [tab, want.size(), str(missing.slice(0, 4))])
		dp.close()
		await _f(2)
	# a finger on a few entries of each class: the vehicle waits next to the hero and ENTER boards it
	var picks: Array[StringName] = [&"sport", &"t_heavy", &"boat", &"h_attack", &"p_fighter", &"p_jumbo"]
	var bad: Array[String] = []
	for k: StringName in picks:
		if not VehicleSpecs.SPECS.has(k):
			continue
		await _leave()
		var tab := "AIRCRAFT" if air.has(k) else "VEHICLES"
		var ti := DemoPanel.TABS.find(tab)
		if ti < 0:
			bad.append("%s: no tab" % k)
			continue
		await _touch(dp.entry_rect().get_center())
		await _touch((dp.call(&"_tab_rects") as Array)[ti].get_center())
		var ok := await _tap_entry(dp, VehicleSpecs.name_of(k))
		await _f(6)
		var v: Vehicle = null
		for c: Vehicle in vm.list:
			if is_instance_valid(c) and c.active and c.kind == k and _flat(c.global_position, p.global_position) < 60.0:
				v = c
		if not ok or v == null or dp.is_open:
			bad.append("%s: tapped %s, near %s, status '%s'" % [k, ok, v != null, dp.status])
			continue
		var p0 := p.global_position
		var d := v.global_position - p0
		p.yaw = atan2(-d.x, -d.z)
		p.camera_rig.reset_view(p.yaw, -0.1)
		fg.stick(Vector2(0.0, -0.7))
		await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER" and v.edge_distance(p.global_position) < VehicleSpecs.ENTER_REACH - 0.6, 10.0)
		fg.stick(Vector2.ZERO)
		await _f(3)
		await _tap(&"interact")
		await _until(func() -> bool: return p.vehicle == v, 1.5)
		if p.vehicle != v:
			bad.append("%s: ENTER did not board (label '%s', %.1f m)" % [k, fg.button_label(&"interact"), v.edge_distance(p.global_position)])
		else:
			await _f(10)
			var cl := _badge_clear(dp)
			if cl != "":
				bad.append("%s: DEMO badge on %s" % [k, cl])
	TestLib.check(bad.is_empty(), "[old fails] a finger on a VEHICLES / AIRCRAFT entry puts it next to the hero and ENTER boards it (%s)" % str(bad))
	TestLib.check(TestMode.god and TestMode.infinite_ammo, "[old fails] GOD MODE and INFINITE AMMO are still on after the launches")
	await _leave()
	dp.close()
	DemoMode.quit()
	await _f(4)
	TestLib.check(not DemoMode.active and not TestMode.god, "QUIT DEMO puts the toggles back off")


# --- 4 CREWS ---------------------------------------------------------------------------------------------------------------------------

func _crews() -> void:
	var tc := TankCrews.current
	TestLib.check(tc != null, "the tank crews run")
	if tc == null:
		return
	Game.state = &"play"
	var ghost := Vehicle.new()
	ghost.free()
	tc.crews.append({"v": ghost, "mode": &"base"})
	var n0 := tc.crews.size()
	await _f(6)
	TestLib.check(tc.crews.size() == n0 - 1, "[old fails] the crew of a freed vehicle is dropped by the next tick (%d -> %d)" % [n0, tc.crews.size()])
	for i in range(tc.crews.size() - 1, -1, -1):
		if not is_instance_valid(tc.crews[i]["v"]):
			tc.crews.remove_at(i)


## "" when the DEMO badge overlaps no visible touch button (circle of its radius), else the actions it lies on.
func _badge_clear(dp: DemoPanel) -> String:
	var r := dp.entry_rect()
	var s := UiUtil.ui_scale(dp.get_viewport().get_visible_rect().size)
	var hits: Array[String] = []
	for b: Dictionary in TouchControls.BUTTONS:
		if fg.tc == null or not fg.tc.button_visible(b):
			continue
		var c := fg.tc._button_center(b)
		var rad := float(b.get("r", 40.0)) * s
		var q := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
		if q.distance_to(c) < rad:
			hits.append(String(b["action"]))
	return ",".join(hits)


# --- 5 PLAYER --------------------------------------------------------------------------------------------------------------------------

func _player_cost() -> void:
	await _leave()
	await _f(4)
	var w := p.weapon
	w.poll_switch()
	var best := INF
	for rep in 3:                                      # the best of three runs of 400 polls (a loaded machine only makes a run slower)
		var t0 := Time.get_ticks_usec()
		for i in 400:
			w.poll_switch()
		best = minf(best, float(Time.get_ticks_usec() - t0) / 400.0)
		await _f(1)
	TestLib.check(best < 20.0, "[old fails] the weapon number-key poll of an on-foot tick costs %.1f us (bound 20 us)" % best)
	# the number keys still switch weapons: the 2 key takes the second weapon of the roster when it is owned
	var keys: Array = PlayerWeapon.number_keys()
	TestLib.check(keys.size() >= 4 and String(keys[1][1]) == "weapon_2", "the number keys weapon_1.. are found (%d)" % keys.size())
