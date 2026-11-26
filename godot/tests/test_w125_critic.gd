extends RefCounted
## WAVE 125 CRITIC (w125-critic): the defects the critic found in the new helicopters, cockpit and helipads, each checked in the REAL main scene with REAL fingers
## (InputEventScreenTouch / ScreenDrag through tests/w116_fingers.gd, Game.force_touch, phone-only layers on: CrateReveal._quiet = 0).
##   1 ROTOR: a helicopter flown at a wall at an angle stopped with its rotor disc inside the facade (the collider is only the fuselage).
##   2 BADGE: the radio plate covered the helicopter's name badge over the horizon.
##   3 FLOOR: the tower's "ROOF" floor name stayed on in a helicopter parked on a roof pad, under the PARKED card and the compass.
## W125C_OLD=1 switches the three fixes off (the code the builders delivered): every [old fails] check fails.
## Run: tools/test.sh tests/test_w125_critic.gd
const TIMEOUT_SECONDS := 140
const Fingers := preload("res://tests/w116_fingers.gd")

var host: Node
var fg: Fingers
var p: Player
var vm: VehicleManager


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


func _tap(action: StringName) -> bool:
	if not fg.press(6, action):
		return false
	await _f(4)
	fg.up(6)
	await _f(3)
	return true


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
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
	await _rotor()
	await _badge()
	await _floor()
	fg.up_all()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	CrateReveal._quiet = -1
	Game.state = &"menu"
	Game.force_touch = false
	main.queue_free()
	await _f(2)


## Setup: a helicopter of `kind` parked in front of the hero at `at`. Then fingers only: the stick walks him to it, ENTER boards it.
func _board(kind: StringName, at: Vector3) -> Vehicle:
	if vm.driven != null:
		await _tap(&"interact")
		await _f(6)
	p.teleport_to(at)
	p.velocity = Vector3.ZERO
	p.yaw = 0.0
	p.camera_rig.reset_view(0.0, -0.15)
	await _f(15)
	DemoMenu.spawn_vehicle(kind)
	var v: Vehicle = null
	for c: Vehicle in vm.list:
		if is_instance_valid(c) and c.kind == kind and (v == null or c.global_position.distance_to(p.global_position) < v.global_position.distance_to(p.global_position)):
			v = c
	if v == null:
		return null
	fg.stick(Vector2(0.0, -1.0))
	await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 8.0)
	fg.stick(Vector2.ZERO)
	await _f(3)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle != null, 1.0)
	return v if p.vehicle == v else null


## The nearest wall within the rotor radius of any hub, measured by 16 horizontal rays per hub (vehicles and floors ignored). INF when none.
func _clearance(v: Vehicle) -> float:
	var space := v.get_world_3d().direct_space_state
	var best := INF
	for hub in VehicleCraft.rotor_hubs(v):
		for i in 16:
			var a := TAU * float(i) / 16.0
			var q := PhysicsRayQueryParameters3D.create(hub, hub + Vector3(cos(a), 0.0, sin(a)) * 20.0, v.collision_mask, [v.get_rid()])
			var r := space.intersect_ray(q)
			if r.is_empty() or absf((r["normal"] as Vector3).y) > 0.6 or r.get("collider") is Vehicle:
				continue
			best = minf(best, hub.distance_to(r["position"]))
	return best


func _rotor() -> void:
	var v := await _board(&"h_utility", Vector3(-30.0, 0.0, 4.0))
	TestLib.check(v != null, "rotor: the hero boards a MULE UTILITY by finger")
	if v == null:
		return
	fg.press(1, &"jump")
	await _until(func() -> bool: return VehicleCraft.altitude(v) > 14.0, 15.0)
	fg.up(1)
	# setup: face the nearest wall 25..120 m away at 70 degrees off square (a glancing pass along it), so the fuselage's nose does not meet it before the disc
	var space := v.get_world_3d().direct_space_state
	var best := INF
	var nrm := Vector3.ZERO
	for i in 32:
		var a := TAU * float(i) / 32.0
		var dir := Vector3(-sin(a), 0.0, -cos(a))
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(v.global_position, v.global_position + dir * 120.0, v.collision_mask, [v.get_rid()]))
		if r.is_empty() or absf((r["normal"] as Vector3).y) > 0.6:
			continue
		var d := v.global_position.distance_to(r["position"])
		if d > 25.0 and d < best:
			best = d
			nrm = r["normal"]
	TestLib.check(best < INF, "rotor: a wall in reach (%.0f m)" % best)
	if best == INF:
		return
	var inward := -Vector3(nrm.x, 0.0, nrm.z).normalized()
	var fly := inward.rotated(Vector3.UP, deg_to_rad(70.0))
	v.heading = atan2(-fly.x, -fly.z)
	await _f(2)
	var rr := float(v.spec["rotor_r"])
	var least := INF
	fg.stick(Vector2(0.0, -1.0))
	for t in 600:
		await host.get_tree().physics_frame
		least = minf(least, _clearance(v))
	fg.stick(Vector2.ZERO)
	TestLib.check(least >= rr * 0.9, "[old fails] rotor: flown at a wall by the stick, the rotor disc stays out of it (closest wall %.1f m from a hub, rotor radius %.1f m, hits %d)" % [least, rr, v.hits])
	fg.press(1, &"crouch")
	await _until(func() -> bool: return not v.craft.airborne, 25.0)
	fg.up(1)


func _badge() -> void:
	var v := vm.driven
	TestLib.check(v != null and HeliRoster.is_heli(v.kind), "badge: in a helicopter")
	if v == null:
		return
	var st: Object = Game.story
	st.set(&"enabled", true)
	st.call(&"say", "ORACLE", "Unregistered coherence detected over the towers. Keep low and keep moving.", "w125c", 0.0, 2)
	await _until(func() -> bool: return str((st.get(&"current") as Dictionary).get("id", "")) == "w125c", 6.0)
	await _f(20)
	var view: Object = st.get(&"view")
	for vp: Vector2 in [fg.vp(), Vector2(2400, 1080), Vector2(1200, 540)]:
		var s := UiUtil.ui_scale(vp)
		var sub: Rect2 = view.call(&"subtitle_rect", vp)
		var b := FlightHud.badge_rect(vp, s, UiUtil.insets(vp), v)
		TestLib.check(sub.has_area() and not (b.has_area() and sub.grow(5.0 * s).intersects(b)), "[old fails] badge at %dx%d: the radio plate %s does not cover the helicopter name badge %s" % [int(vp.x), int(vp.y), str(sub), str(b)])
	st.set(&"enabled", false)
	(st.get(&"queue") as Array).clear()   # integrator w125: under load game lines were still queued behind ours and took the plate next
	st.call(&"skip_line")
	await _until(func() -> bool: return not (view.call(&"subtitle_rect", fg.vp()) as Rect2).has_area(), 6.0)
	await _f(4)
	var vp2 := fg.vp()
	TestLib.check(FlightHud.badge_rect(vp2, UiUtil.ui_scale(vp2), UiUtil.insets(vp2), v).has_area(), "badge: back once the radio line is gone")


func _floor() -> void:
	var pd := Helipads.pad(&"w125_roof_east")
	TestLib.check(not pd.is_empty(), "floor: the EAST TOWER PAD exists")
	if pd.is_empty():
		return
	var c: Vector3 = pd["pos"]
	var v := vm.driven
	if v == null:
		return
	fg.press(1, &"jump")
	await _until(func() -> bool: return VehicleCraft.altitude(v) > 8.0, 10.0)
	fg.up(1)
	v.global_position = c + Vector3(0.0, 25.0, 0.0)                      # setup: over the roof pad
	await _f(30)
	fg.press(1, &"crouch")
	var landed := await _until(func() -> bool: return not v.craft.airborne and absf(v.speed) < 3.0, 25.0)
	fg.up(1)
	await _f(20)
	var tl := TowerLift.instance
	var txt := tl.floor_label_text() if tl != null else ""
	TestLib.check(landed and p.vehicle == v and absf(v.global_position.y - c.y) < 2.0, "floor: landed on the roof pad by DOWN (dy %.1f)" % (v.global_position.y - c.y))
	TestLib.check(txt == "", "[old fails] floor: in the helicopter on the roof pad no floor name shows under the PARKED card (shows '%s')" % txt)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == null, 2.0)
	await _f(20)
	TestLib.check(p.vehicle == null, "floor: EXIT by finger on the pad")
	print("floor on foot: '%s'" % (tl.floor_label_text() if tl != null else "-"))
