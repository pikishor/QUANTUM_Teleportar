extends RefCounted
## Wave 116 perf probe (not a test): where the VEHICLES script time goes while the hero FLIES (owner round 7: "VEHICLES 4 to 6.5 ms far from any car", FPS 37 to 41 with drops to 13).
## The real main scene, headless, --fixed-fps 30 (two physics ticks per frame like the phone), LOW+; the hero flies a course by the real flight code (actions) at boost speed:
## over the city, out over the suburbs and the hills. Every 3 s: the PerfTimers VEHICLES average and peak, plus the cost of ONE extra call of each ambient vehicle step at the
## hero's place (near_traffic, road_traffic, parked), timed here.  Run: W116_ROUTE="x,z;x,z" tools/cpu_frame.sh style:
##   godot --headless --fixed-fps 30 --path . res://tests/runner.tscn -- --test=res://tests/dev_w116_vehicle_air.gd --timeout=280 --quality=0 --low-plus

const TIMEOUT_SECONDS := 280
var host: Node


func run(h: Node) -> void:
	host = h
	Game.force_touch = true
	seed(20260101)
	RenderRes.user_mode = -1
	RenderRes.gov_mode = -1
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	for i in 20:
		await host.get_tree().process_frame
	if Game.has_method(&"set_low_plus"):
		Game.call(&"set_low_plus", true)
	var p := Game.player as Player
	var em := Game.enemies as EnemyManager
	em.patrol_groups().clear()
	em.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	p.invuln = 1.0e6
	TestMode.god = true
	Game.state = &"play"
	var amb: Node = (Game.world as City).ambient
	var vm := Game.vehicles as VehicleManager
	var route: Array[Vector3] = []
	var spec := OS.get_environment("W116_ROUTE") if OS.get_environment("W116_ROUTE") != "" else "300,0;900,300;1500,900;2100,900;2100,-600;900,-900;0,0"
	for s in spec.split(";", false):
		var xy := s.split(",")
		route.append(Vector3(float(xy[0]), 0.0, float(xy[1])))
	var alt := float(OS.get_environment("W116_ALT")) if OS.get_environment("W116_ALT") != "" else 70.0
	var on_foot := OS.get_environment("W116_FOOT") == "1"
	p.teleport_to(Vector3(0.0, 0.0 if on_foot else alt, 4.0))
	if OS.get_environment("W116_TP") == "1":
		p.teleport_to(Vector3(route[0].x, alt, route[0].z))
		route.remove_at(0)
	p.camera_rig.reset_view(-PI * 0.5, 0.0)
	for i in 30:
		await host.get_tree().process_frame
	var sn := p.snake
	if not on_foot:
		Input.action_press(&"fly")
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		Input.action_release(&"fly")
		Input.action_press(&"snake")                       # BOOST
	Input.action_press(&"move_forward")
	PerfTimers.reset()
	var gi := 0
	var frame := 0
	var acc := {"near": 0.0, "road": 0.0, "parked": 0.0}
	var n_acc := 0
	var worst := {"near": 0.0, "road": 0.0, "parked": 0.0}
	var frame_ms := PackedFloat64Array()
	var last := Time.get_ticks_usec()
	var total_frames := int(OS.get_environment("W116_FRAMES")) if OS.get_environment("W116_FRAMES") != "" else 2400
	print("VAIR start alt ", alt, " route ", route, " vehicles in list ", vm.list.size(), " amb ", amb != null, " low_plus ", Game.low_plus, " on_foot ", on_foot)
	while frame < total_frames and gi < route.size():
		await host.get_tree().process_frame
		frame += 1
		var now := Time.get_ticks_usec()
		frame_ms.append(float(now - last) / 1000.0)
		last = now
		sn.energy = SnakePower.max_energy()
		var pos := p.global_position
		var goal := route[gi]
		if Vector2(pos.x - goal.x, pos.z - goal.z).length() < 80.0:
			gi += 1
			continue
		var want := atan2(-(goal.x - pos.x), -(goal.z - pos.z))
		var d := wrapf(want - p.camera_rig.yaw, -PI, PI)
		p.camera_rig.add_look(-clampf(d, -0.06, 0.06), 0.0)
		if not on_foot:
			var dp := clampf((alt - pos.y) * 0.01, -0.3, 0.3) - p.camera_rig.pitch          # hold the altitude by the look pitch
			p.camera_rig.add_look(0.0, -clampf(dp, -0.03, 0.03))
			if sn.mode != SnakeTraversal.Mode.FLY:
				Input.action_press(&"fly")
				await host.get_tree().process_frame
				Input.action_release(&"fly")
		if amb != null:
			var t0 := Time.get_ticks_usec()
			amb.get(&"near_traffic").call(&"step", 0.0, pos)
			var t1 := Time.get_ticks_usec()
			amb.get(&"road_traffic").call(&"step", 0.0, pos)
			var t2 := Time.get_ticks_usec()
			amb.get(&"parked").call(&"step", 0.0, pos)
			var t3 := Time.get_ticks_usec()
			var a := float(t1 - t0) / 1000.0
			var b := float(t2 - t1) / 1000.0
			var c := float(t3 - t2) / 1000.0
			acc["near"] += a
			acc["road"] += b
			acc["parked"] += c
			worst["near"] = maxf(worst["near"], a)
			worst["road"] = maxf(worst["road"], b)
			worst["parked"] = maxf(worst["parked"], c)
			n_acc += 1
			last = Time.get_ticks_usec()                  # the extra calls are not part of the frame time
		if frame % 90 == 0:
			var srt := frame_ms.duplicate()
			srt.sort()
			var mean := 0.0
			for t in srt:
				mean += t
			mean /= maxf(srt.size(), 1)
			print("VAIR f %d pos %s v %.0f mode %s  frame mean %.1f p95 %.1f worst %.1f ms | VEHICLES avg %.2f peak %.2f (x2 with the extra calls) | extra call: near %.2f (worst %.2f) road %.2f (worst %.2f) parked %.2f (worst %.2f) ms | list %d near %d road %d parked %d" % [
				frame, pos.snapped(Vector3(1, 1, 1)), p.velocity.length(), sn.mode_name(), mean, srt[int(srt.size() * 0.95)], srt[srt.size() - 1],
				PerfTimers.avg_ms(PerfTimers.VEHICLES), PerfTimers.peak_ms(PerfTimers.VEHICLES),
				acc["near"] / maxf(n_acc, 1), worst["near"], acc["road"] / maxf(n_acc, 1), worst["road"], acc["parked"] / maxf(n_acc, 1), worst["parked"],
				vm.list.size(), _cnt(amb, &"near_traffic"), _cnt(amb, &"road_traffic"), _cnt(amb, &"parked")])
			print("VAIR   road searches %d passes %d  spawn table builds %d  road spawn calls %d" % [CityLayout.searches, CityLayout.passes, VehicleManager.point_builds, int((amb.get(&"road_traffic") as Object).get(&"spawn_calls"))])
			acc = {"near": 0.0, "road": 0.0, "parked": 0.0}
			worst = {"near": 0.0, "road": 0.0, "parked": 0.0}
			n_acc = 0
			frame_ms.clear()
			PerfTimers.reset_peaks()
	print(PerfTimers.table())
	Input.action_release(&"move_forward")
	Input.action_release(&"snake")
	main.queue_free()
	await host.get_tree().process_frame


func _cnt(amb: Node, what: StringName) -> int:
	if amb == null or amb.get(what) == null:
		return -1
	var v: Variant = (amb.get(what) as Object).get(&"drawn")
	return int(v) if v != null else -1
