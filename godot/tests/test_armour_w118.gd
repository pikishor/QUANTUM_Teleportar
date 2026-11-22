extends RefCounted
## WAVE 118: TANKS AND HELICOPTERS THE PLAYER CAN FIND (owner round 7: "where are tanks and helicopters etc. everything is pending for such long time").
## The real main scene from a fresh start, the phone HUD, REAL FINGERS only (InputEventScreenTouch / InputEventScreenDrag through Input.parse_input_event, tests/w116_fingers.gd),
## the phone-only layers on (CrateReveal._quiet = 0). Nothing here calls a game function to act; positions are set up by teleport, every action is a finger.
##   map     the minimap shows an armour glyph at the start; the big map (a finger on the minimap) has the TANKS + AIR chip and a tank, a helicopter and a plane icon in an
##           uncharted city; a finger on the tank icon sets the GPS route to the ARMY YARD; the chip filters them; CLOSE
##   demo    pause > EXTRAS > TEST > SPAWN: the first rows are TANK, HELICOPTER, PLANE; a finger on each puts one on free ground next to the hero
##   yard    the ARMY YARD holds a tank, a light tank and an armoured carrier 105 m out and keeps them while the car pool is squeezed; walk to the tank, ENTER, drive 30 m,
##           FIRE the gun, EXIT
##   heli    CITY HELIPAD EAST: walk to the helicopter, ENTER, UP (take off), fly, FIRE, DOWN (land), EXIT
##   call    MORE > CALL: the CALL-IN list; TANK is delivered beside the hero, a second TANK is refused on its cooldown, HELICOPTER comes
## ARMOUR_OLD=1 switches the wave 118 parts off (ArmourSites.fixed_on / icons_on / demo_on, CallIn.enabled): the checks marked [old fails] fail. ARMOUR_PARTS=map,demo,... picks parts.
## Run: tools/test.sh tests/test_armour_w118.gd
const TIMEOUT_SECONDS := 145
const Fingers := preload("res://tests/w116_fingers.gd")

var host: Node
var fg: Fingers
var p: Player
var vm: VehicleManager
var old := false


## n physics ticks, each followed by a whole engine frame (process_frame). TestLib.frames waits PHYSICS ticks only: on a loaded machine several ticks fit in one engine frame, the input buffer is flushed once a frame, and a
## finger lift sent with Input.parse_input_event then arrives after the check that reads it (measured with a 200-tap probe: 0 late lifts alone, 21 to 35 of 200 with three tests running).
func _f(n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame
		await host.get_tree().process_frame


func _until(cond: Callable, secs: float) -> bool:
	for i in int(secs * 60.0):
		if cond.call():
			return true
		await host.get_tree().physics_frame
	return cond.call()


func _secs(s: float) -> void:
	for i in int(s * 60.0):
		await host.get_tree().physics_frame


func _tp(pos: Vector3, yaw: float) -> void:
	fg.up_all()
	await _f(2)
	p.snake.cancel()
	p.snake.reset()
	p.teleport_to(pos)
	p.camera_rig.reset_view(yaw, -0.1)
	p.yaw = yaw
	p.velocity = Vector3.ZERO
	await _f(20)


## A finger down and up at a canvas position.
func _tap_at(pos: Vector2, frames := 3) -> void:
	fg.down(7, pos)
	await _f(frames)
	fg.up(7)
	await _f(3)


func _tap(action: StringName) -> bool:
	if not fg.press(6, action):
		return false
	await _f(4)
	fg.up(6)
	await _f(3)
	return true


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _live(id: StringName) -> Vehicle:
	var v: Variant = vm._spawned.get(id)
	if is_instance_valid(v) and (v as Vehicle).active and not (v as Vehicle).dead:
		return v as Vehicle
	return null


func _called(kind: StringName) -> Vehicle:
	for v in vm.list:
		if v.kind == kind and v.has_meta(&"called") and v.active:
			return v
	return null


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	old = OS.get_environment("ARMOUR_OLD") == "1"
	ArmourSites.fixed_on = not old
	ArmourSites.icons_on = not old
	ArmourSites.demo_on = not old
	ArmourSites.pick_on = not old and OS.get_environment("ARMOUR_PICK_OLD") != "1"      # ARMOUR_PICK_OLD=1 ARMOUR_PARTS=call: only the ENTER preference off
	ArmourSites._markers.clear()
	ArmourSites.reset_calls()
	CallIn.enabled = not old
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
	if NearTraffic.instance != null:                                    # no moving traffic; the kerb cars stay until the yard part is over (they are part of what it checks)
		NearTraffic.instance.enabled = false
		NearTraffic.instance.count = 0
		NearTraffic.instance.reset()
	if RoadTraffic.instance != null:
		RoadTraffic.instance.enabled = false
		RoadTraffic.instance.reset()
	TestMode.god = true
	Difficulty.set_mode(1)
	TestLib.check(fg.tc != null and fg.tc.controls_on and _flat(p.global_position, Game.SPAWN) < 3.0, "a fresh start: the phone HUD is up and the hero stands at the spawn (%s)" % ("the wave 117 state, ARMOUR_OLD=1" if old else "wave 118"))
	var parts := (OS.get_environment("ARMOUR_PARTS") if OS.get_environment("ARMOUR_PARTS") != "" else "map,demo,yard,heli,call").split(",")
	for part in parts:
		match part:
			"map": await _map()
			"demo": await _demo()
			"yard":
				await _yard()
				TrafficField.bare_street()
			"heli": await _heli()
			"call": await _call()
	fg.up_all()
	ArmourSites.fixed_on = true
	ArmourSites.icons_on = true
	ArmourSites.demo_on = true
	ArmourSites.pick_on = true
	ArmourSites._markers.clear()
	ArmourSites.reset_calls()
	CallIn.enabled = true
	CallIn.close()
	MenuFlags.all_extras = false
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
	CrateReveal._quiet = -1
	Game.state = &"menu"
	Game.force_touch = false
	main.queue_free()
	await _f(2)


func _fast(on: bool) -> void:
	Engine.physics_ticks_per_second = 180 if on else 60                # real 1/60 s ticks, three game seconds a second
	Engine.time_scale = 3.0 if on else 1.0
	Engine.max_physics_steps_per_frame = 3 if on else 8


# --- the map ----------------------------------------------------------------------------------------------------------------------------
func _map() -> void:
	await _f(20)
	var mms := host.get_tree().root.find_children("*", "Minimap", true, false)
	var mm := mms[0] as Minimap if not mms.is_empty() else null
	TestLib.check(mm != null and mm.armour_drawn >= 1, "[old fails] at the start the minimap shows a tank / helicopter glyph (%d drawn)" % (mm.armour_drawn if mm != null else -1))
	await _tap_at(fg.tc._minimap_rect().get_center())
	await _f(30)
	var ms := host.get_tree().root.find_child("MapScreen", true, false) as MapScreen
	TestLib.check(ms != null and MapScreen.up, "a finger on the minimap opens the big map")
	if ms == null or not MapScreen.up:
		return
	var glyphs := {}
	for mk in ms.lod_markers(ms.visible_markers()):
		if mk["kind"] == &"armour":
			glyphs[mk["glyph"]] = int(glyphs.get(mk["glyph"], 0)) + 1
	for q: Array in ms.armour_pins:
		glyphs[StringName("far " + String(q[1]["glyph"]))] = 1
	TestLib.check(glyphs.has(&"tank") and glyphs.has(&"heli") and (glyphs.has(&"plane") or glyphs.has(&"far plane")), "[old fails] the fresh, uncharted map draws a tank, a helicopter and a plane icon (%s)" % str(glyphs))
	var plane_pin := Vector2.INF
	for q: Array in ms.armour_pins:
		if q[1]["glyph"] == &"plane":
			plane_pin = ms._map.get_global_transform() * (q[0] as Vector2)
	if plane_pin != Vector2.INF:
		await _tap_at(plane_pin)
		await _f(6)
		TestLib.check(ms.has_waypoint() and String(ms.selected.get("label", "")).begins_with("PLANE"), "a finger on the plane pin at the edge sets the GPS to the plane (%s)" % str(ms.selected.get("label", "")))
	var chip := ms.find_child("F_armour", true, false) as Button
	TestLib.check(chip != null and chip.is_visible_in_tree() and chip.text.begins_with("TANKS + AIR") and chip.get_global_rect().size.y >= 40.0, "[old fails] the legend has the TANKS + AIR chip (%s)" % (chip.text if chip != null else "none"))
	var yard := ArmourSites.YARD
	var at: Vector2 = ms._map.get_global_transform() * ms.world_to_map(yard.x, yard.z)
	var free := ms._map.get_global_rect().has_point(at) and not ms._legend_rect.grow(30.0).has_point(ms.world_to_map(yard.x, yard.z)) and not ms._right_rect.grow(30.0).has_point(ms.world_to_map(yard.x, yard.z))
	TestLib.check(free, "the ARMY YARD lies on the open part of the map at the opening zoom (%s)" % str(at))
	await _tap_at(at)
	await _f(6)
	var wp_ok := ms.has_waypoint() and _flat(ms.waypoint, yard) < 12.0 and String(ms.selected.get("label", "")) == "TANKS"
	TestLib.check(wp_ok, "[old fails] a finger on the tank icon sets the GPS waypoint on the ARMY YARD (waypoint %s, picked %s)" % [str(ms.waypoint) if ms.has_waypoint() else "none", str(ms.selected.get("label", ""))])
	var route := ms.route_points()
	TestLib.check(route.size() >= 2, "the GPS draws a route to it (%d points)" % route.size())
	if chip != null and chip.is_visible_in_tree():
		await _tap_at(chip.get_global_rect().get_center())
		var n_off := 0
		for mk in ms.visible_markers():
			if mk["kind"] == &"armour":
				n_off += 1
		var still := chip.is_visible_in_tree()                           # a chip switched off must stay on screen, or it can never be switched on again
		await _tap_at(chip.get_global_rect().get_center())
		var n_on := 0
		for mk in ms.visible_markers():
			if mk["kind"] == &"armour":
				n_on += 1
		TestLib.check(n_off == 0 and n_on >= 5 and still, "a finger on the chip hides the icons and the chip stays, a second one brings them back (%d, %d, chip on screen %s)" % [n_off, n_on, still])
	var cls := ms.find_child("Close", true, false) as Button
	await _tap_at(cls.get_global_rect().get_center())
	TestLib.check(not MapScreen.up and Game.state == &"play", "a finger on CLOSE closes the map")
	if MapScreen.up:
		ms.close_screen()
	await _f(4)
	var mm_ok := mm != null and mm.armour_drawn >= 1
	TestLib.check(mm_ok or old, "the minimap still points at the armour with the route on")
	ms.clear_waypoint()


# --- the demo / test menu's SPAWN list -----------------------------------------------------------------------------------------------------------
func _demo() -> void:
	await _tp(Game.SPAWN + Vector3(0.0, 0.2, 0.0), -PI * 0.5)
	MenuFlags.all_extras = true                                        # the setting that shows the TEST card (OPTIONS > GAME > ALL EXTRAS)
	var hud := host.get_tree().get_first_node_in_group(&"hud") as Hud
	var tms := host.get_tree().root.find_children("*", "TestMenu", true, false)
	var tm := tms[0] as TestMenu if not tms.is_empty() else null
	if tm == null or hud == null:
		TestLib.check(false, "the scene has a TEST menu")
		return
	await _tap_at(fg.tc._pause_center())
	await _f(10)
	var gear := Rect2()
	for b: Dictionary in hud.buttons:
		if b["id"] == &"menu_gear":
			gear = b["rect"]
	TestLib.check(Game.state == &"paused" and gear.size.x > 0.0, "a finger on PAUSE: the pause menu with EXTRAS")
	await _tap_at(gear.get_center())
	await _f(10)
	await _tap_at(tm.entry_rect().get_center())
	await _f(6)
	TestLib.check(tm.is_open, "EXTRAS > TEST opens the TEST menu by a finger")
	if not tm.is_open:
		Game.state = &"play"
		return
	await _tap_at(tm._tab_rects()[TestMenu.TABS.find("SPAWN")].get_center())
	await _f(4)
	tm.layout()
	var first: Array[String] = []
	for it in tm.items:
		if not it.get("head", false) and first.size() < 7:
			first.append(String(it["label"]))
	TestLib.check(first.size() >= 6 and first[0] == VehicleSpecs.name_of(&"tank") and first.has(VehicleSpecs.name_of(&"heli")) and first.has(VehicleSpecs.name_of(&"plane")), "[old fails] the SPAWN list starts with the tank, the helicopter and the plane (%s)" % str(first))
	var before := vm.list.size()
	var got: Array[String] = []
	for k: StringName in [&"tank", &"heli", &"plane"]:
		tm.layout()
		for it in tm.items:
			if not it.get("head", false) and String(it["label"]) == VehicleSpecs.name_of(k):
				var r: Rect2 = it["rect"]
				await _tap_at(Vector2(r.get_center().x, r.get_center().y + tm._top() - tm.scroll))
				break
		var v := _called(k)
		if v != null:
			var inside: bool = Game.world.call(&"is_inside_building", Vector3(v.global_position.x, 1.0, v.global_position.z))
			got.append("%s %.0f m%s" % [k, _flat(v.global_position, p.global_position), " IN A BUILDING" if inside else ""])
	TestLib.check(got.size() == 3 and not " ".join(got).contains("BUILDING") and _called(&"tank") != null and _flat(_called(&"tank").global_position, p.global_position) < 25.0,
			"[old fails] a finger on TANK, HELICOPTER and PLANE puts each on free ground next to the hero (%s, %d -> %d vehicles)" % [str(got), before, vm.list.size()])
	await _tap_at(tm._close_rect().get_center())
	await _f(6)
	TestLib.check(not tm.is_open, "a finger on CLOSE closes the TEST menu")
	if tm.is_open:
		tm.close()
	Game.state = &"play"
	await _f(4)
	for k: StringName in [&"tank", &"heli", &"plane"]:
		var v := _called(k)
		if v != null:
			vm._release(v)
	MenuFlags.all_extras = false


# --- the ARMY YARD ----------------------------------------------------------------------------------------------------------------------------
func _yard() -> void:
	_fast(true)
	var yard := ArmourSites.YARD
	await _tp(Vector3(yard.x - 8.0, 0.2, yard.z - 105.0), PI)           # 105 m south of the yard, on the cross street
	vm._spawn_t = 0.0
	await _secs(4.5)                                                    # one fixed vehicle a second
	var kinds := {}
	for id: StringName in [&"depot", &"depot_light", &"depot_apc"]:
		var v := _live(id)
		if v != null and _flat(v.global_position, yard) < 14.0:
			kinds[v.kind] = true
	TestLib.check(kinds.has(&"tank") and kinds.has(&"ltank") and kinds.has(&"apc"), "[old fails] 105 m out the ARMY YARD already holds a tank, a light tank and an armoured carrier (%s)" % str(kinds.keys()))
	await _tp(Vector3(yard.x - 8.0, 0.2, yard.z - 13.0), PI)            # on the pavement in front of the tank's bay, looking at it
	vm._spawn_t = 0.0
	await _secs(2.5)
	var kerb_cars := 0                                                  # the tanks' way out: no kerb car and no solid street prop between the bays and the road
	var pc := ParkedCars.instance
	if pc != null:
		for i in pc._n:
			var cp := pc.car_position(i)
			if pc.car_alive(i) and absf(cp.x - yard.x) <= 15.0 and cp.z - yard.z <= -11.0 and cp.z - yard.z >= -20.0:
				kerb_cars += 1
	var props: Array[String] = []
	var cc: Variant = (Game.world as City).prop_colliders()
	for i in cc._xf.size():
		var o: Vector3 = cc._xf[i].origin
		if absf(o.x - yard.x) <= 13.0 and o.z - yard.z <= -11.0 and o.z - yard.z >= -17.5:
			props.append(String(cc._spec_list[cc._spec[i]][3]))
	TestLib.check(pc != null and pc.enabled and pc.cell_count() > 0 and kerb_cars == 0 and props.is_empty(), "[old fails] the way out of the yard is clear: no kerb car (%d) and no solid street prop (%s) between the bays and the road" % [kerb_cars, str(props)])
	var first: Array = [_live(&"depot"), _live(&"depot_light"), _live(&"depot_apc")]
	for i in 6:                                                         # the pool is squeezed the way a LOW phone squeezes it: nothing of the yard may go
		vm._free_slot()
	vm._trim_to_cap()
	var held := true                                                    # read at once: a released one would be put back a second later
	for fv: Variant in first:
		if fv == null or not (fv as Vehicle).active or not vm.list.has(fv):
			held = false
	await _secs(1.0)
	var tank := _live(&"depot")
	TestLib.check(held, "[old fails] the three stay on the yard while the car pool is squeezed and trimmed (%d live vehicles, cap %d)" % [vm.list.size(), vm.cap()])
	TestLib.check(ArmourSites.instance != null and ArmourSites.instance.built_count() >= 1 or old, "the yard's paint, barriers and sign are built near the hero")
	if tank == null:
		await _secs(3.0)
		tank = _live(&"depot")
	if tank == null:
		TestLib.check(false, "a tank stands on the yard to walk to")
		_fast(false)
		return
	fg.stick(Vector2(0.0, -1.0))
	var reached := await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 12.0)
	fg.stick(Vector2.ZERO)
	await _f(3)
	TestLib.check(reached, "walking to the tank by the stick brings up ENTER (%.1f m from its middle)" % _flat(p.global_position, tank.global_position))
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle != null, 1.0)
	TestLib.check(p.vehicle == tank, "a finger on ENTER: the hero drives the tank (%s)" % (str(p.vehicle.kind) if p.vehicle != null else "on foot"))
	if p.vehicle != tank:
		_fast(false)
		return
	TestLib.check(fg.button(&"fire") != Vector2.INF and fg.button(&"interact") != Vector2.INF and fg.button_label(&"interact") == "EXIT", "in the tank FIRE and EXIT are on screen (%s)" % str(fg.tc.visible_ids()))
	var from := tank.global_position
	fg.stick(Vector2(0.0, -1.0))
	var drove := await _until(func() -> bool: return _flat(tank.global_position, from) >= 30.0, 16.0)
	fg.stick(Vector2.ZERO)
	TestLib.check(drove, "the stick drives the tank 30 m out of its bay (%.1f m)" % _flat(tank.global_position, from))
	var ammo0: int = tank.weapons.ammo
	fg.press(6, &"fire")
	var fired := await _until(func() -> bool: return tank.weapons.ammo < ammo0, 4.0)
	fg.up(6)
	TestLib.check(fired, "a finger on FIRE: the tank gun fires (%d -> %d shells)" % [ammo0, tank.weapons.ammo])
	await _until(func() -> bool: return absf(tank.speed) < 1.0, 4.0)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == null, 1.0)
	TestLib.check(p.vehicle == null and vm.driven == null and p.global_position.y < 2.0, "a finger on EXIT: the hero stands beside the tank (y %.1f)" % p.global_position.y)
	_fast(false)


# --- the city helipad -------------------------------------------------------------------------------------------------------------------------
func _heli() -> void:
	_fast(true)
	var pad := ArmourSites.PAD_EAST
	await _tp(Vector3(pad.x + 2.6, 0.2, pad.z - 11.0), PI)              # on the road side of the pad, looking at the helicopter's nose
	vm._spawn_t = 0.0
	await _secs(2.5)
	var heli := _live(&"heli_pad")
	TestLib.check(heli != null and heli.cls == &"heli" and _flat(heli.global_position, pad) < 3.0, "a helicopter stands on CITY HELIPAD EAST")
	if heli == null:
		_fast(false)
		return
	fg.stick(Vector2(0.0, -1.0))
	var reached := await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 10.0)
	fg.stick(Vector2.ZERO)
	await _f(3)
	TestLib.check(reached, "walking to the helicopter by the stick brings up ENTER")
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle != null, 1.0)
	TestLib.check(p.vehicle == heli, "a finger on ENTER: the hero flies the helicopter")
	if p.vehicle != heli:
		_fast(false)
		return
	TestLib.check(fg.button(&"jump") != Vector2.INF and fg.button(&"crouch") != Vector2.INF and fg.button(&"fire") != Vector2.INF, "in the helicopter UP, DOWN, FIRE and EXIT are on screen (%s)" % str(fg.tc.visible_ids()))
	var from := heli.global_position
	fg.press(1, &"jump")
	var up := await _until(func() -> bool: return VehicleCraft.altitude(heli) > 10.0, 10.0)
	fg.up(1)
	TestLib.check(up and heli.craft.airborne, "a finger held on UP: it takes off (%.1f m above the ground)" % VehicleCraft.altitude(heli))
	fg.stick(Vector2(0.0, -1.0))
	var flew := await _until(func() -> bool: return _flat(heli.global_position, from) > 14.0, 8.0)
	fg.stick(Vector2.ZERO)
	TestLib.check(flew, "the stick flies it forward (%.1f m)" % _flat(heli.global_position, from))
	var ammo0: int = heli.weapons.ammo
	fg.press(6, &"fire")
	var fired := await _until(func() -> bool: return heli.weapons.ammo < ammo0, 3.0)
	fg.up(6)
	TestLib.check(fired, "a finger on FIRE: the helicopter's gun fires (%d -> %d)" % [ammo0, heli.weapons.ammo])
	fg.press(1, &"crouch")
	var landed := await _until(func() -> bool: return not heli.craft.airborne and absf(heli.speed) < 6.0, 20.0)
	fg.up(1)
	TestLib.check(landed, "a finger held on DOWN: it lands (%.1f m above the ground, %.1f m/s)" % [VehicleCraft.altitude(heli), heli.speed])
	await _secs(0.5)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == null, 1.0)
	TestLib.check(p.vehicle == null and vm.driven == null, "a finger on EXIT: the hero is out of the helicopter")
	_fast(false)


# --- the call-in ------------------------------------------------------------------------------------------------------------------------------
func _open_call() -> bool:
	if not fg.tc.more_open:
		await _tap(&"more")
	var ok := await _tap(&"garage_call")
	await _f(4)
	return ok


func _row(name: String) -> Button:
	return CallIn.instance.find_child("Call_" + name, true, false) as Button if is_instance_valid(CallIn.instance) else null


func _call() -> void:
	await _tp(Game.SPAWN + Vector3(0.0, 0.2, 0.0), -PI * 0.5)
	await _secs(0.5)
	var pressed := await _open_call()
	TestLib.check(pressed and CallIn.is_open(), "[old fails] MORE > CALL opens the CALL-IN list (button on screen %s)" % pressed)
	if not CallIn.is_open():
		return
	var rows: Array[String] = []
	var small := 1.0e9
	for n: String in ["Car", "Tank", "Helicopter", "Plane", "Close"]:
		var b := _row(n)
		if b != null and b.is_visible_in_tree():
			rows.append(b.text)
			small = minf(small, b.get_global_rect().size.y / UiUtil.ui_scale(fg.vp()))
	TestLib.check(rows.size() == 5 and small >= UiUtil.TOUCH_MIN, "the list has CAR, TANK, HELICOPTER, PLANE and CLOSE, every row a full touch target (%s, the smallest %d base px high)" % [str(rows), int(small)])
	await _tap_at(_row("Tank").get_global_rect().get_center())
	await _f(6)
	var tank := _called(&"tank")
	var near := tank != null and _flat(tank.global_position, p.global_position) < 25.0 and not bool(Game.world.call(&"is_inside_building", Vector3(tank.global_position.x, 1.0, tank.global_position.z)))
	TestLib.check(near and not CallIn.is_open(), "a finger on TANK: a tank is delivered on free ground beside the hero and the list closes (%s)" % (("%.1f m" % _flat(tank.global_position, p.global_position)) if tank != null else "none"))
	await _open_call()
	if CallIn.is_open():
		await _tap_at(_row("Tank").get_global_rect().get_center())
		await _f(6)
	var tanks := 0
	for cv in vm.list:
		if cv.kind == &"tank" and cv.has_meta(&"called"):
			tanks += 1
	TestLib.check(tanks == 1 and ArmourSites.call_wait(&"tank") > 30.0 and CallIn.is_open() and _row("Tank").text.ends_with(" S"), "a second TANK is refused: the row shows its cooldown (%s)" % (_row("Tank").text if _row("Tank") != null else ""))
	if CallIn.is_open():
		await _tap_at(_row("Helicopter").get_global_rect().get_center())
		await _f(6)
	var heli := _called(&"heli")
	TestLib.check(heli != null and _flat(heli.global_position, p.global_position) < 25.0 and tank != null and _flat(heli.global_position, tank.global_position) > 5.0, "a finger on HELICOPTER: a helicopter is delivered too, clear of the tank")
	if tank != null:                                                    # the delivery is a real tank: walk up to it and get in
		_fast(true)
		var to := tank.global_position - p.global_position
		p.camera_rig.reset_view(atan2(-to.x, -to.z), -0.1)
		await _f(4)
		fg.stick(Vector2(0.0, -1.0))
		var reached := await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 8.0)
		fg.stick(Vector2.ZERO)
		await _f(3)
		# a car stands nearer than the called tank, both in reach: ENTER by a finger still takes the tank the hero asked for (frame call_2_tank read HIJACK SEDAN beside the delivery)
		_fast(false)
		fg.stick(Vector2(0.0, 1.0))                                        # a step back, so the car can stand nearer than the tank
		await _until(func() -> bool: return tank.edge_distance(p.global_position) >= 1.15, 3.0)
		fg.stick(Vector2.ZERO)
		await _f(8)
		var away := p.global_position - tank.global_position
		away.y = 0.0
		away = away.normalized()
		vm._fixed_n += 1                                                   # room for one more over the tier's car cap (the scene setup, not the thing under test)
		var sedan := vm.spawn_parked(&"sedan", p.global_position + away * 2.0, atan2(away.x, away.z) + PI * 0.5)
		vm._count_fixed()
		await _f(12)
		var e_tank := tank.edge_distance(p.global_position)
		var e_car := sedan.edge_distance(p.global_position) if sedan != null else -1.0
		var both := sedan != null and e_tank <= VehicleSpecs.ENTER_REACH and e_car <= VehicleSpecs.ENTER_REACH and e_car < e_tank
		var prompt := Freedom.vehicle_prompt()
		await _tap(&"interact")
		await _until(func() -> bool: return p.vehicle != null, 1.0)
		TestLib.check(both and p.vehicle == tank and prompt.contains("TANK"), "[old fails] with a car nearer than the called tank, both in reach, the prompt names the tank and a finger on ENTER takes it (edge: tank %.1f m, car %.1f m, prompt %s, in %s)" % [e_tank, e_car, prompt, str(p.vehicle)])
		TestLib.check(reached and p.vehicle != null and (p.vehicle as Vehicle).cls in [&"tank", &"heli"], "the hero walks to the delivery and gets in by ENTER (reached %s, %.1f m from the tank, button %s, in %s)" % [reached, _flat(p.global_position, tank.global_position), fg.button_label(&"interact"), str(p.vehicle)])
		_fast(false)
