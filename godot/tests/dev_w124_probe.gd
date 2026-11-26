extends RefCounted
## Wave 124 frame-rate probe (not a CI test). Owner round 7: LOW+ 37 to 45 FPS on foot, 13 to 28 in flight. The real main scene under software Vulkan (xvfb), --fixed-fps 30.
## Four scenes per tier: FOOT (walking in the city), DRIVE (driving a car down a city street), FLY_CITY (snake flight at 90 m over the blocks), FLY_OUT (flight at 90 m over the outskirts).
## Per scene, averaged over W124_FRAMES frames after a settle: visible and total (with shadow passes) draws and triangles, shadow-casting lights in range, node count, frame ms and
## the PerfTimers script time of every system. Prints `W124 <scene> ...` lines and `W124T <scene> <system> <ms>`.
## Run (one tier per call):
##   xvfb-run -a -s "-screen 0 1280x720x24" $(tools/get_godot.sh) --rendering-driver vulkan --rendering-method mobile --fixed-fps 30 --resolution 1200x540 --path . \
##     res://tests/runner.tscn -- --test=res://tests/dev_w124_probe.gd --timeout=400 --quality=0 [--low-plus]
## env W124_FRAMES (default 90), W124_ONLY=FOOT,FLY_CITY (subset).

const TIMEOUT_SECONDS := 400
var host: Node
var p: Player


func _f(n: int) -> void:
	for i in n:
		await host.get_tree().process_frame


func run(h: Node) -> void:
	host = h
	Game.force_touch = true
	Sfx.muted = true
	seed(20260101)
	RenderRes.user_mode = -1
	RenderRes.gov_mode = -1
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await _f(20)
	if "--low-plus" in OS.get_cmdline_user_args() and Game.has_method(&"set_low_plus"):
		Game.call(&"set_low_plus", true)
	p = Game.player as Player
	var em := Game.enemies as EnemyManager
	em.patrol_groups().clear()
	em.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	p.invuln = 1.0e6
	TestMode.god = true
	Game.state = &"play"
	CrateReveal._quiet = 0
	var only := OS.get_environment("W124_ONLY")
	for sc in ["FOOT", "DRIVE", "FLY_CITY", "FLY_OUT"]:
		if only != "" and not (sc in only.split(",")):
			continue
		await _scene(sc)
	main.queue_free()
	await _f(2)


func _release() -> void:
	for a in [&"move_forward", &"snake", &"fly", &"accelerate"]:
		if InputMap.has_action(a):
			Input.action_release(a)


func _scene(sc: String) -> void:
	_release()
	var vm := Game.vehicles as VehicleManager
	if vm.driven != null:
		vm.exit_vehicle()
		await _f(10)
	var sn := p.snake
	sn.cancel()
	sn.reset()
	var alt := 90.0
	var goal := Vector3.ZERO
	match sc:
		"FOOT":
			p.teleport_to(Game.SPAWN)
			p.camera_rig.reset_view(-PI * 0.5, -0.05)
			goal = Game.SPAWN + Vector3(400, 0, 0)
		"DRIVE":
			p.teleport_to(Game.SPAWN)
			await _f(30)
			var car := vm.reach_car(p.global_position)
			if car == null:
				for c in vm.list:
					if is_instance_valid(c) and c.active and not c.dead and (c.global_position - p.global_position).length() < 120.0:
						car = c
						break
			if car != null:
				p.teleport_to(car.global_position + Vector3(1.5, 0, 0))
				await _f(2)
				vm.enter(car)
			goal = Game.SPAWN + Vector3(600, 0, 0)
		"FLY_CITY":
			p.teleport_to(Vector3(-200.0, alt, 4.0))
			goal = Vector3(900.0, alt, 300.0)
		"FLY_OUT":
			p.teleport_to(Vector3(1700.0, alt, 900.0))
			goal = Vector3(2600.0, alt, -600.0)
	await _f(20)
	if sc.begins_with("FLY"):
		Input.action_press(&"fly")
		await _f(2)
		Input.action_release(&"fly")
	if sc == "DRIVE" and InputMap.has_action(&"accelerate"):
		Input.action_press(&"accelerate")
	Input.action_press(&"move_forward")
	var n := int(OS.get_environment("W124_FRAMES")) if OS.get_environment("W124_FRAMES") != "" else 90
	var acc := {"draws": 0.0, "prims": 0.0, "total_draws": 0.0, "total_prims": 0.0}
	var peak := {"draws": 0, "total_draws": 0, "total_prims": 0}
	var ms := 0.0
	var shadow_lights := 0.0
	var lights := 0.0
	var steps := 0
	for i in 40 + n:
		_steer(sc, goal, alt)
		var t := Time.get_ticks_usec()
		await _f(1)
		if i == 40:
			PerfTimers.reset()
		if i < 40:
			continue
		ms += float(Time.get_ticks_usec() - t) / 1000.0
		var s := PerfProbe.snapshot(host.get_viewport())
		for k in acc:
			acc[k] += float(s[k])
		for k in peak:
			peak[k] = maxi(peak[k], int(s[k]))
		if i % 15 == 0:
			var l := _lights()
			lights += l[0]
			shadow_lights += l[1]
			steps += 1
	_release()
	var pos := p.global_position
	print("W124 %s tier=%d lp=%s pos=%s mode=%s draws=%.0f prims=%.0f total_draws=%.0f (peak %d) total_prims=%.0f (peak %d) lights=%.1f shadow_lights=%.1f nodes=%d frame_ms=%.1f script_ms=%.2f" % [
		sc, Game.quality, str(Game.low_plus), pos.snapped(Vector3.ONE), sn.mode_name() if vm.driven == null else "CAR", acc["draws"] / n, acc["prims"] / n, acc["total_draws"] / n,
		peak["total_draws"], acc["total_prims"] / n, peak["total_prims"], lights / maxf(steps, 1), shadow_lights / maxf(steps, 1),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), ms / n, PerfTimers.total_ms()])
	if OS.get_environment("W124_CENSUS") != "":
		_census(sc)
	if OS.get_environment("W124_HIDE") != "":
		await _hide_scan(sc)
	for id in PerfTimers.ranked():
		print("W124T %s %s %.3f" % [sc, PerfTimers.NAMES[id], PerfTimers.avg_ms(id)])


func _steer(sc: String, goal: Vector3, alt: float) -> void:
	var pos := p.global_position
	if sc.begins_with("FLY"):
		p.snake.energy = SnakePower.max_energy()
		if p.snake.mode != SnakeTraversal.Mode.FLY:
			Input.action_press(&"fly")
		else:
			Input.action_release(&"fly")
	var want := atan2(-(goal.x - pos.x), -(goal.z - pos.z))
	var d := wrapf(want - p.camera_rig.yaw, -PI, PI)
	p.camera_rig.add_look(-clampf(d, -0.06, 0.06), 0.0)
	if sc.begins_with("FLY"):
		var dp := clampf((alt - pos.y) * 0.01, -0.3, 0.3) - p.camera_rig.pitch
		p.camera_rig.add_look(0.0, -clampf(dp, -0.03, 0.03))


## [lights visible within their range of the camera, of them with shadows]
func _lights() -> Array:
	var cam := host.get_viewport().get_camera_3d()
	var a := 0
	var b := 0
	for l in host.get_tree().root.find_children("*", "Light3D", true, false):
		var li := l as Light3D
		if not li.is_visible_in_tree():
			continue
		if li is DirectionalLight3D:
			a += 1
			b += 1 if li.shadow_enabled else 0
			continue
		var r: float = li.get(&"omni_range") if li is OmniLight3D else li.get(&"spot_range")
		if cam != null and li.global_position.distance_to(cam.global_position) < r + 60.0:
			a += 1
			b += 1 if li.shadow_enabled else 0
	return [a, b]


## Draw surfaces of the geometry in the camera frustum and inside its visibility range, by "parent/name" family (names without digits). Top 14.
func _census(sc: String) -> void:
	var cam := host.get_viewport().get_camera_3d()
	if cam == null:
		return
	var planes := cam.get_frustum()
	var agg := {}
	var stack: Array = [host.get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and not (n as Node3D).visible:
			continue
		if n is CanvasItem:
			continue
		stack.append_array(n.get_children())
		if not (n is GeometryInstance3D) or (n as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var g := n as GeometryInstance3D
		var surf := 1
		var ab := AABB()
		if g is MeshInstance3D:
			if (g as MeshInstance3D).mesh == null:
				continue
			surf = (g as MeshInstance3D).mesh.get_surface_count()
			ab = (g as MeshInstance3D).get_aabb()
		elif g is MultiMeshInstance3D:
			var mm := (g as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null or mm.visible_instance_count == 0 or mm.instance_count == 0:
				continue
			surf = mm.mesh.get_surface_count()
			ab = mm.get_aabb()
		else:
			ab = g.get_aabb()
		var wab: AABB = g.global_transform * ab
		var c := wab.get_center()
		var d := c.distance_to(cam.global_position)
		if g.visibility_range_end > 0.0 and d > g.visibility_range_end + wab.size.length() * 0.5:
			continue
		var inside := true
		for pl in planes:
			var r := wab.size.length() * 0.5
			if pl.distance_to(c) > r:
				inside = false
				break
		if not inside:
			continue
		var gp := n.get_parent()
		var key := "%s/%s/%s" % [str(gp.get_parent().name).rstrip("0123456789_"), str(gp.name).rstrip("0123456789_"), str(n.name).rstrip("0123456789_")]
		agg[key] = int(agg.get(key, 0)) + surf
	var keys := agg.keys()
	keys.sort_custom(func(a, b) -> bool: return agg[a] > agg[b])
	var tot := 0
	for k in keys:
		tot += int(agg[k])
	var out := []
	for k in keys.slice(0, 14):
		out.append("%s=%d" % [k, agg[k]])
	print("W124C %s surfaces=%d %s" % [sc, tot, ", ".join(out)])
	var geo := (Game.world as Node).get_node_or_null(^"Geometry")
	var live := []
	if geo != null:
		for c in geo.get_children():
			if c is MultiMeshInstance3D and (c as MultiMeshInstance3D).visible and (c as MultiMeshInstance3D).multimesh != null:
				var vc := (c as MultiMeshInstance3D).multimesh.visible_instance_count
				if vc != 0:
					live.append("%s:%d" % [c.name, vc])
			elif c is MeshInstance3D and (c as MeshInstance3D).visible:
				var g := c as MeshInstance3D
				var dd := (g.global_transform * g.get_aabb()).get_center().distance_to(cam.global_position)
				if g.visibility_range_end <= 0.0 or dd < g.visibility_range_end + 200.0:
					live.append("%s(mesh %.0fm)" % [c.name, dd])
	print("W124G %s %d live: %s" % [sc, live.size(), ", ".join(live)])


## Hides each 3D child of the main scene and of its children one at a time and reads what the frame's total draws drop by: where the draws come from.
func _hide_scan(sc: String) -> void:
	_release()
	p.process_mode = Node.PROCESS_MODE_DISABLED
	(Game.world as Node).get(&"ambient").set(&"simulate", false)
	await _f(6)
	var base := int(PerfProbe.snapshot(host.get_viewport())["total_draws"])
	var out := []
	var cands: Array = []
	for c in host.get_children():
		for k in c.get_children():
			if k is Node3D:
				cands.append(k)
				for kk in k.get_children():
					if kk is Node3D:
						cands.append(kk)
						if kk.get_child_count() < 120 and kk.name in OS.get_environment("W124_HIDE").split(","):
							for k3 in kk.get_children():
								if k3 is Node3D:
									cands.append(k3)
									if k3.name.begins_with("Ambient") or k3.name in OS.get_environment("W124_HIDE").split(","):
										for k4 in k3.get_children():
											if k4 is Node3D:
												cands.append(k4)
	for n in cands:
		if not is_instance_valid(n):
			continue
		var nd := n as Node3D
		if not nd.visible:
			continue
		nd.visible = false
		await _f(2)
		var d := base - int(PerfProbe.snapshot(host.get_viewport())["total_draws"])
		nd.visible = true
		if d >= 2:
			out.append([d, "%s/%s" % [nd.get_parent().name, nd.name]])
	await _f(2)
	p.process_mode = Node.PROCESS_MODE_INHERIT
	(Game.world as Node).get(&"ambient").set(&"simulate", true)
	out.sort_custom(func(a, b) -> bool: return a[0] > b[0])
	print("W124H %s base=%d %s" % [sc, base, str(out.slice(0, 20))])
