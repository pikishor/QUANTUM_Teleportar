extends RefCounted
## WAVE 118 CRITIC: the defects the independent review found (tests/bot_w118_critic.gd, frames at 844x390), each with a check that fails on the old code.
## The real main scene, the phone HUD, REAL FINGERS (tests/w116_fingers.gd: InputEventScreenTouch / Drag through Input.parse_input_event), reward cards on (CrateReveal._quiet = 0).
##   gps   a finger on the minimap, a finger on the tank icon: on foot the GPS line says ON FOOT with a walking ETA (old: CAR, 214 m in 0:11)          CRITIC_OLD=1 fails
##   tag   on the street the snake's ZIP tag never covers a touch button (old: ZIP ROOF +81 M on ABILITY, frame foot_844)                        CRITIC_OLD=1 fails
##   air   in a flying helicopter the door button does not say EXIT (a finger on it did nothing: LAND TO GET OUT); on the ground it says EXIT   CRITIC_OLD=1 fails
##   dial  in a tank the turret dial is not under the left thumb (inside the stick's ring)                                                    CRITIC_OLD=1 fails
## CRITIC_PARTS=gps,tag picks parts.   Run: tools/test.sh tests/test_critic_w118.gd
const TIMEOUT_SECONDS := 120
const Fingers := preload("res://tests/w116_fingers.gd")
const STREET := Vector3(-30.0, 0.0, 4.0)

var host: Node
var fg: Fingers
var p: Player
var old := false


func _f(n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame
		await host.get_tree().process_frame


func _tap_at(pos: Vector2, frames := 3) -> void:
	fg.down(7, pos)
	await _f(frames)
	fg.up(7)
	await _f(3)


func _tp(pos: Vector3, yaw: float, pitch := 0.05) -> void:
	fg.up_all()
	await _f(2)
	p.snake.cancel()
	p.snake.reset()
	p.teleport_to(pos)
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	p.velocity = Vector3.ZERO
	await _f(30)


## w119 CI: the outdoor context slot turns from SNAKE BLAST to ENTER only after a vehicle has stayed in reach TouchControls.SLOT_SETTLE seconds (w119 critic); a finger
## goes on ENTER once it is drawn, as a player's would (20 frames at 140 fps were less than that, and the press found no ENTER button). At most 3 s.
func _wait_enter() -> void:
	for i in 180:
		if fg.button_label(&"interact") == "ENTER":
			return
		await _f(1)


func _switch(on: bool) -> void:
	MapScreen.foot_fix = on
	SnakeFx.tag_dodge = on
	TouchControls.door_air_fix = on
	VehicleHud.dial_fix = on


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	old = OS.get_environment("CRITIC_OLD") == "1"
	_switch(not old)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	var old_size := host.get_tree().root.size
	host.get_tree().root.size = Vector2i(844, 390)                     # the phone the owner plays on
	await _f(20)
	Game.state = &"play"
	CrateReveal._quiet = 0
	p = Game.player as Player
	fg = Fingers.new(host)
	(Game.enemies as EnemyManager).patrol_groups().clear()
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	TestMode.god = true
	var parts := (OS.get_environment("CRITIC_PARTS") if OS.get_environment("CRITIC_PARTS") != "" else "gps,tag,air,dial").split(",")
	for part in parts:
		match part:
			"gps": await _gps()
			"tag": await _tag()
			"air": await _air()
			"plane": await _plane()
			"dial": await _dial()
	fg.up_all()
	_switch(true)
	CrateReveal._quiet = -1
	Game.state = &"menu"
	Game.force_touch = false
	host.get_tree().root.size = old_size
	main.queue_free()
	await _f(2)


# --- the GPS line on foot ---------------------------------------------------------------------------------------------------------------
func _gps() -> void:
	await _tp(Game.SPAWN + Vector3(0.0, 0.2, 0.0), -PI * 0.5)
	await _tap_at(fg.tc._minimap_rect().get_center())
	await _f(30)
	var ms := host.get_tree().root.find_child("MapScreen", true, false) as MapScreen
	TestLib.check(ms != null and MapScreen.up, "a finger on the minimap opens the big map")
	if ms == null or not MapScreen.up:
		return
	var yard := ArmourSites.YARD
	await _tap_at(ms._map.get_global_transform() * ms.world_to_map(yard.x, yard.z))
	await _f(10)
	await _f(20)
	var line := String(ms._sub_text)
	var speed := float(ms._route_m) / maxf(ms._route_eta, 0.1)
	TestLib.check(ms.has_waypoint() and line.contains("ON FOOT") and speed < 8.0,
			"[old fails] on foot, a finger on the tank icon: the GPS line says ON FOOT and the ETA is a walk (%s; %.1f m/s)" % [line, speed])
	var cls := ms.find_child("Close", true, false) as Button
	await _tap_at(cls.get_global_rect().get_center())
	if MapScreen.up:
		ms.close_screen()
	ms.clear_waypoint()
	await _f(4)


# --- the zip tag never covers a touch button --------------------------------------------------------------------------------------------
func _tag() -> void:
	var seen := 0
	var bad: Array[String] = []
	for pose: Array in [[STREET, -PI * 0.5, 0.05], [STREET, -PI * 0.5, 0.25], [STREET + Vector3(0, 0, 3), -PI * 0.35, 0.15], [Game.SPAWN, -PI * 0.5, 0.2]]:
		await _tp(pose[0], pose[1], pose[2])
		SnakeFx.last_tag = Rect2()
		await _f(20)
		if SnakeFx.current == null or SnakeFx.current.zip_mark.is_empty() or SnakeFx.last_tag.size == Vector2.ZERO:
			continue
		seen += 1
		var plate := SnakeFx.last_tag
		var s := fg.tc._scale()
		for b: Dictionary in TouchControls.BUTTONS:
			if fg.tc.button_visible(b):
				var bc := fg.tc._button_center(b)
				var r := float(b["r"]) * UiSettings.s_button_size * s
				if Vector2(clampf(bc.x, plate.position.x, plate.end.x), clampf(bc.y, plate.position.y, plate.end.y)).distance_to(bc) < r:
					bad.append("%s at pose %d" % [b["label"], seen])
	TestLib.check(seen >= 1, "the snake marks a zip target on the street (%d poses)" % seen)
	TestLib.check(bad.is_empty(), "[old fails] the ZIP tag never covers a touch button (%s)" % str(bad))


# --- the door button in the air ---------------------------------------------------------------------------------------------------------
func _air() -> void:
	var vm := Game.vehicles as VehicleManager
	await _tp(STREET, -PI * 0.5)
	vm._fixed_n += 1                                                    # set-up: room for one more over the tier's car cap
	var heli := vm.spawn_parked(&"gunship", p.global_position + Vector3(0.0, 0.0, -7.0), 0.0)
	vm._count_fixed()
	await _f(10)
	if heli == null:
		TestLib.check(false, "a helicopter to fly")
		return
	p.teleport_to(heli.global_position + Vector3(0.0, 0.2, 4.5))
	await _f(20)
	await _wait_enter()
	fg.press(6, &"interact")
	await _f(4)
	fg.up(6)
	await _f(10)
	TestLib.check(p.vehicle == heli, "a finger on ENTER: in the helicopter (%s)" % str(p.vehicle))
	if p.vehicle != heli:
		return
	var ground := fg.button_label(&"interact")
	fg.press(1, &"jump")
	for i in 900:
		await host.get_tree().physics_frame
		if VehicleCraft.altitude(heli) > 15.0:
			break
	fg.up(1)
	await _f(6)
	var air := fg.button_label(&"interact")
	fg.press(6, &"interact")
	await _f(4)
	fg.up(6)
	await _f(6)
	TestLib.check(VehicleCraft.altitude(heli) > 10.0 and p.vehicle == heli, "UP lifts it and the door does not drop the hero (%.0f m)" % VehicleCraft.altitude(heli))
	TestLib.check(ground == "EXIT" and air != "" and air != "EXIT", "[old fails] the door says EXIT on the ground and not EXIT in the air, where it cannot work (%s / %s)" % [ground, air])
	fg.press(1, &"crouch")
	for i in 1500:
		await host.get_tree().physics_frame
		if not heli.craft.airborne and absf(heli.speed) < 6.0:
			break
	fg.up(1)
	await _f(30)
	TestLib.check(fg.button_label(&"interact") == "EXIT", "landed, the door says EXIT again (%s)" % fg.button_label(&"interact"))
	fg.press(6, &"interact")
	await _f(4)
	fg.up(6)
	await _f(10)
	vm._release(heli)                                                   # clean-up: the next part spawns its own vehicle
	await _f(4)


# --- MORE > CALL > PLANE (probe) ------------------------------------------------------------------------------------------------------
func _plane() -> void:
	await _tp(Game.SPAWN + Vector3(0.0, 0.2, 0.0), -PI * 0.5)
	var msgs: Array[String] = []
	var rec := func(t: String, _s: float) -> void: msgs.append(t)
	Game.message.connect(rec)
	if not fg.tc.more_open:
		fg.press(6, &"more")
		await _f(4)
		fg.up(6)
		await _f(4)
	fg.press(6, &"garage_call")
	await _f(4)
	fg.up(6)
	await _f(6)
	var b := CallIn.instance.find_child("Call_Plane", true, false) as Button if is_instance_valid(CallIn.instance) else null
	if b != null:
		await _tap_at(b.get_global_rect().get_center())
	await _f(10)
	var plane: Vehicle = null
	for v in (Game.vehicles as VehicleManager).list:
		if v.kind == &"plane" and v.has_meta(&"called"):
			plane = v
	Game.message.disconnect(rec)
	print("PLANE PROBE row %s plane %s msgs %s" % [str(b != null), str(plane.global_position.round()) if plane != null else "none", str(msgs)])
	TestLib.check(plane != null and plane.global_position.distance_to(p.global_position) < 40.0, "a finger on PLANE in the CALL-IN list delivers a plane near the hero (%s)" % str(msgs))


# --- the tank dial and the stick ---------------------------------------------------------------------------------------------------------
func _dial() -> void:
	var vm := Game.vehicles as VehicleManager
	await _tp(STREET, -PI * 0.5)
	vm._fixed_n += 1
	var tank := vm.spawn_parked(&"tank", p.global_position + Vector3(0.0, 0.0, -8.0), 0.0)
	vm._count_fixed()
	await _f(10)
	if tank == null:
		TestLib.check(false, "a tank to drive")
		return
	tank.set_meta(&"spawned", true)                                   # w119 CI: as the demo SPAWN list marks it, so ENTER prefers it over a police car tailing the hero (VehicleManager.reach_car)
	p.teleport_to(tank.global_position + Vector3(0.0, 0.2, 5.0))
	await _f(20)
	await _wait_enter()
	fg.press(6, &"interact")
	await _f(4)
	fg.up(6)
	await _f(30)
	TestLib.check(p.vehicle == tank, "a finger on ENTER: in the tank")
	VehicleHud.last_dial = Vector2.INF
	fg.stick(Vector2(0.0, -1.0))                                       # the left thumb on the stick, as when driving
	await _f(20)
	var s := fg.tc._scale()
	var thumb: Vector2 = fg.held.get(0, Vector2.INF)
	var dial := VehicleHud.last_dial
	fg.stick(Vector2.ZERO)
	var vs := fg.vp()
	var home := Vector2(190.0 * s + UiUtil.insets(vs).x, vs.y - 170.0 * s - UiUtil.insets_v(vs).y)
	var ring := TouchControls.STICK_RADIUS * s
	TestLib.check(dial.is_finite() and dial.distance_to(home) >= ring + 40.0 * s and dial.distance_to(thumb) >= ring,
			"[old fails] the tank's turret dial is clear of the stick's ring and the thumb (dial %s, stick home %s r %.0f, thumb %s)" % [str(dial), str(home), ring, str(thumb)])
	await _f(5)
	fg.press(6, &"interact")
	await _f(4)
	fg.up(6)
	await _f(10)
