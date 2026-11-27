extends RefCounted
## WAVE 128 CI (w128-ci-apk): a hero with his back to a TOWER keeps the see-through-the-facade camera arm when the tower's walk-in shell opens.
## CI 46059341693 (shard 1): test_hud_camera_final "walking off the wall changes the arm smoothly (worst step 0.81 m per 0.4 m of walking)" failed on both attempts (FLAKY with 0.80 m in
## wave 126). Cause: the weapons shop of that check is in a tower lot. Near a tower, TowerFloors opens its walk-in shell: it switches the lot's city box off and puts its own wall boxes
## in a StaticBody "TowerShell". CameraRig only lets the lens sit behind a BUILDING wall (THROUGH_ARM, `_is_facade`: shapes named Building*, chunk bodies), and the shell's walls had plain
## names, so the moment the shell opened the arm fell from 1.9 m to the wall distance (about 1.1 m) in ONE frame: a jump into the hero's shoulder. On the runner the shell opened within
## the first step of the walk-off (0.81 m jump); here it opened one step later (0.43 m), so the check passed. The fix names the shell's OUTER walls BuildingTowerWall
## (TowerFloors.shell_facade). W128CI_OLD=1 = the code before: the [old fails] checks fail.
## Run: tools/test.sh tests/test_w128_ci.gd
const TIMEOUT_SECONDS := 120

var host: Node


func _f(n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame
		await host.get_tree().process_frame


func _until(cond: Callable, max_secs: float) -> bool:
	var n := int(max_secs * 60.0)
	while n > 0 and not cond.call():
		await _f(1)
		n -= 1
	return cond.call()


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	TowerFloors.shell_facade = OS.get_environment("W128CI_OLD") != "1"
	host.get_tree().root.size = Vector2i(1200, 540)
	TowerFloors.enabled = false                      # the tower stays a closed city box until the hero stands at it
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await _f(20)
	Game.state = &"play"
	TestMode.god = true
	var p := Game.player as Player
	var rig: CameraRig = p.camera_rig
	var tf := TowerFloors.instance
	var tw: Dictionary = tf.nearest(Game.SPAWN) if tf != null else {}
	TestLib.check(not tw.is_empty(), "there is a walk-in tower near the spawn")
	if tw.is_empty():
		TowerFloors.enabled = true
		main.queue_free()
		return
	var lot: CityLayout.Lot = tw["lot"]
	var n: Vector3 = tw["n"]
	var t: Vector3 = tw["t"]
	var du := TowerFloors.door_u(tw)
	var u := du - TowerFloors.DOOR_W * 0.5 - 2.5
	if u < 1.5:
		u = du + TowerFloors.DOOR_W * 0.5 + 2.5
	# a point on the street face of the lot, away from the door gap; the street height from a ray down
	var face := Vector3(lot.cx, 0.0, lot.cz) + n * TowerFloors._half_n(tw) + t * (-TowerFloors._half_t(tw) + TowerFloors.IN + u)
	var q := PhysicsRayQueryParameters3D.create(face + n * 2.0 + Vector3(0.0, 40.0, 0.0), face + n * 2.0 + Vector3(0.0, -40.0, 0.0), Game.L_WORLD)
	var gh := p.get_world_3d().direct_space_state.intersect_ray(q)
	var gy: float = (gh["position"] as Vector3).y if not gh.is_empty() else 0.0
	var yaw := atan2(-n.x, -n.z)                      # looking out to the street: the camera arm points back into the facade
	var stand := func(d: float) -> void:
		p.teleport_to(Vector3(face.x, gy + 0.1, face.z) + n * d)
		p.yaw = yaw
	stand.call(0.8)
	rig.reset_view(yaw, -0.1)
	rig.snap()
	await _f(30)
	var closed_d := rig.camera.global_position.distance_to(rig.get_pivot_position())
	TestLib.check(TowerFloors.open_lot != lot.index, "the tower is still a closed city box (lot %d)" % lot.index)
	TestLib.check(rig.through_wall and closed_d >= CameraRig.THROUGH_ARM - 0.45, "with his back to the closed tower the lens sits behind the facade (%.2f m from his head, through %s)" % [closed_d, str(rig.through_wall)])
	# the hero is at the tower: its walk-in shell opens (TowerFloors switches the city box off and builds its own walls)
	TowerFloors.enabled = true
	var opened := await _until(func() -> bool: return TowerFloors.open_lot == lot.index, 3.0)
	TestLib.check(opened, "the tower's walk-in shell opens with the hero at its wall (open lot %d)" % TowerFloors.open_lot)
	var worst := 0.0
	var prev := closed_d
	for i in 30:
		stand.call(0.8)
		await _f(1)
		var dd := rig.camera.global_position.distance_to(rig.get_pivot_position())
		worst = maxf(worst, absf(dd - prev))
		prev = dd
	TestLib.check(rig.through_wall and prev >= CameraRig.THROUGH_ARM - 0.45, "[old fails] the open shell's wall is a facade too: the lens stays behind it (%.2f m, through %s)" % [prev, str(rig.through_wall)])
	TestLib.check(worst < 0.3, "[old fails] the arm does not jump when the shell opens (worst frame %.2f m)" % worst)
	# the shell's inner walls (stairwell, slabs) stay plain: only the outer walls are named as a facade
	var named := 0
	var plain := 0
	var shell := tf.find_child("TowerShell", false, false)
	if shell != null:
		for c in shell.get_children():
			if String(c.name).begins_with("Building"):
				named += 1
			else:
				plain += 1
	var want := 6 if TowerFloors.shell_facade else 0
	TestLib.check(named == want and plain > 0, "the shell names its %d outer wall boxes as facade, its %d inner boxes stay plain" % [named, plain])
	main.queue_free()
	await _f(2)
