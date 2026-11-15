extends RefCounted
## Dev probe of the wave 115 LOOK critic (not a test): a thumb policy plays a long swing / zip / climb / flight run through the real city WITHOUT a renderer (headless, --fixed-fps 60) and measures what the
## frames of tests/bot_critic_snake.gd show: the camera popping (it jumps more than the hero moved), the lens inside a wall, the hero hidden behind a wall, a swing stuck on its rope, the vehicle prompt
## shown to a hero who hangs 20 m over the street, the time spent in each state. Prints the first events of each kind with the state they happened in.
##   CP_SECS (game seconds, default 90)  CP_START="x,z,yaw" (default -30,4,-1.5708)  CP_DIFF (0..3, default 1)  CP_HUD=0 (skip the HUD prompt probe)
## Run: godot --headless --fixed-fps 60 --path . res://tests/runner.tscn -- --test=res://tests/dev_critic_snake_play.gd   (about 2 minutes; tools/test.sh stops at 150 s)

const TIMEOUT_SECONDS := 560.0

var host: Node
var p: Player
var sn: SnakeTraversal
var goals: Array[Vector3] = []


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func _yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.x - from.x), -(to.z - from.z))


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	SnakeMissions.reset_flags()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	p = Game.player as Player
	sn = p.snake
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	if Game.missions != null:
		Game.missions.contracts.enabled = false
	Game.state = &"play"
	TestMode.god = true
	SnakeTraversal.assist = true
	Difficulty.set_mode(int(OS.get_environment("CP_DIFF")) if OS.get_environment("CP_DIFF") != "" else 1)
	var secs := float(OS.get_environment("CP_SECS")) if OS.get_environment("CP_SECS") != "" else 90.0
	if OS.get_environment("CP_PULL") != "":
		CameraRig.snake_pull_in = float(OS.get_environment("CP_PULL"))                  # A/B of the camera pull-in rate (1e6 = the old cut)
	var start := Vector3(-30.0, 0.0, 4.0)
	var start_yaw := -PI * 0.5
	if OS.get_environment("CP_START") != "":
		var sp := OS.get_environment("CP_START").split(",")
		start = Vector3(float(sp[0]), 0.0, float(sp[1]))
		start_yaw = float(sp[2])
	var city := Game.world as City
	if OS.get_environment("CP_BARE") == "1":
		TrafficField.bare_street()                                   # parked and driving cars are anchors too (and move): a run about the buildings
	if OS.get_environment("CP_GOALS") != "":                        # "x,z;x,z": the same route every run (the random core road points differ from run to run)
		for g in OS.get_environment("CP_GOALS").split(";", false):
			var gp := g.split(",")
			goals.append(Vector3(float(gp[0]), 0.0, float(gp[1])))
	var pts: Array[Vector3] = []
	for i in (0 if not goals.is_empty() else 40):
		var rp: Vector3 = city.random_core_road_point()
		if rp.is_finite():
			pts.append(rp)
	var cur := start
	while not pts.is_empty() and goals.size() < 6:
		var best := 0
		for k in pts.size():
			var d := Vector2(pts[k].x - cur.x, pts[k].z - cur.z).length()
			var bd := Vector2(pts[best].x - cur.x, pts[best].z - cur.z).length()
			var ahead := Vector2(pts[k].x - cur.x, pts[k].z - cur.z).normalized().dot(Vector2(-sin(start_yaw), -cos(start_yaw)))
			if d > 90.0 and d < 420.0 and ahead > -0.2 and (bd <= 90.0 or d < bd):
				best = k
		cur = pts[best]
		pts.remove_at(best)
		goals.append(cur)
	if goals.is_empty():
		goals.append(start + Vector3(-sin(start_yaw), 0.0, -cos(start_yaw)) * 400.0)
	print("CP goals ", goals)
	p.teleport_to(start)
	await frames(2)
	p.camera_rig.reset_view(start_yaw, 0.1)
	p.yaw = start_yaw
	await frames(30)
	var hud := host.get_tree().root.find_child("Hud", true, false)
	var gi := 0
	var t := 0.0
	var dt := 1.0 / 60.0
	var fly_t := 0.0
	var fly_tapped := false
	var fly_rel := -1.0
	var tap_until := -1.0
	var prev_cam := Vector3.ZERO
	var prev_rel := Vector3.ZERO
	var mode_time := {}
	var counts := {"frames": 0, "pops": 0, "inside": 0, "occluded": 0, "stuck": 0, "prompt_air": 0, "obstructed": 0, "hero_hidden_long": 0}
	var logged := {"pops": 0, "inside": 0, "occluded": 0, "prompt_air": 0}
	var max_pop := 0.0
	var max_acc := 0.0
	var hist: Array = []
	var in_run := 0
	var max_in_run := 0
	var hero_jumps := 0
	var prev_pos := Vector3.ZERO
	var big_pops := 0
	var prev_v := Vector3.ZERO
	var stuck_t := 0.0
	var occ_run := 0.0
	var max_occ_run := 0.0
	var prompts := {}
	var space := p.get_world_3d().direct_space_state
	var last_mode := -1
	while t < secs:
		await frames(1)
		t += dt
		var on_floor := p.is_on_floor()
		var pos := p.global_position
		if Vector2(pos.x - goals[gi].x, pos.z - goals[gi].z).length() < 45.0:
			gi = (gi + 1) % goals.size()
		var want := _yaw_to(pos, goals[gi])
		var d := wrapf(want - p.camera_rig.yaw, -PI, PI)
		var turn := clampf(d, -1.7 * dt, 1.7 * dt)
		var want_pitch := 0.2 if not on_floor else 0.05
		var dp := clampf(want_pitch - p.camera_rig.pitch, -0.8 * dt, 0.8 * dt)
		if sn.mode != SnakeTraversal.Mode.CLIMB and sn.mode != SnakeTraversal.Mode.ZIP:
			p.camera_rig.add_look(-turn, -dp)
		match int(sn.mode):
			SnakeTraversal.Mode.NONE:
				fly_t = 0.0
				fly_tapped = false
				if on_floor:
					Input.action_press(&"move_forward")
					if t >= tap_until + 0.7:
						Input.action_press(&"snake")
						tap_until = t + 0.12
					elif t >= tap_until:
						Input.action_release(&"snake")
				else:
					Input.action_release(&"move_forward")
					Input.action_press(&"snake")
					tap_until = t
			SnakeTraversal.Mode.SWING:
				Input.action_release(&"move_forward")
				Input.action_press(&"snake")
				tap_until = t
			SnakeTraversal.Mode.CLIMB:
				Input.action_press(&"move_forward")
				Input.action_release(&"snake")
				tap_until = t + 0.5
			SnakeTraversal.Mode.ZIP:
				Input.action_release(&"snake")
				tap_until = t + 0.5
			SnakeTraversal.Mode.FLY:
				fly_t += dt
				Input.action_press(&"move_forward")
				if fly_t < 1.5:
					Input.action_press(&"snake")
				else:
					Input.action_release(&"snake")
				if fly_t > 4.0 and not fly_tapped:
					fly_tapped = true
					Input.action_press(&"fly")
					fly_rel = t + 0.12
		if fly_rel > 0.0 and t >= fly_rel:
			Input.action_release(&"fly")
			fly_rel = -1.0
		if int(sn.mode) != last_mode:
			print("CP %.1f mode %d -> %d at (%.0f, %.0f, %.0f) v %.1f" % [t, last_mode, sn.mode, pos.x, pos.y, pos.z, p.velocity.length()])
			last_mode = sn.mode
		# the probes (the camera has moved in this frame's _process)
		var cam := p.camera_rig.camera
		counts["frames"] = int(counts["frames"]) + 1
		mode_time[int(sn.mode)] = float(mode_time.get(int(sn.mode), 0.0)) + dt
		var rel := cam.global_position - pos
		if prev_cam != Vector3.ZERO:
			var pop := ((cam.global_position - prev_cam) - (pos - (prev_cam - prev_rel))).length()
			max_pop = maxf(max_pop, pop)
			if pop > 0.9:
				counts["pops"] = int(counts["pops"]) + 1
				if int(logged["pops"]) < 14:
					logged["pops"] = int(logged["pops"]) + 1
					var cr := p.camera_rig
					print("CP   pop %.2f m at t=%.2f mode %d hero (%.0f, %.0f, %.0f) v %.1f cam dist %.2f | ratio %.2f arm_raw %.2f through_wall %s door_tight %.2f cam.dist_add %.2f swing_ph %s" % [pop, t, sn.mode, pos.x, pos.y, pos.z, p.velocity.length(), rel.length(), cr._ratio, cr._arm_raw, str(cr.through_wall), cr.door_tight, sn.cam.dist_add, str(sn.swing.phase)])
		if prev_pos != Vector3.ZERO and last_mode == sn.mode:
			var step_len := (pos - prev_pos).length()
			var allowed := p.velocity.length() * dt * 1.6 + 1.2
			if step_len > allowed:
				hero_jumps += 1
				if int(logged.get("hjump", 0)) < 8:
					logged["hjump"] = int(logged.get("hjump", 0)) + 1
					print("CP   hero jumped %.1f m in one frame (allowed %.1f) at t=%.2f mode %d ph %s from (%.1f %.1f %.1f) to (%.1f %.1f %.1f) v %.1f rope %.1f goal %.1f" % [step_len, allowed, t, sn.mode, str(sn.swing.phase), prev_pos.x, prev_pos.y, prev_pos.z, pos.x, pos.y, pos.z, p.velocity.length(), sn.swing.rope, sn.swing.rope_goal])
		prev_pos = pos
		var cr2 := p.camera_rig
		hist.append("t=%.2f mode %d ph %s pos (%.1f %.1f %.1f) cam (%.1f %.1f %.1f) yaw %.3f pitch %.3f ratio %.2f raw %.2f dadd %.2f hadd %.2f fov %.1f v %.1f" % [t, sn.mode, str(sn.swing.phase), pos.x, pos.y, pos.z, cam.global_position.x, cam.global_position.y, cam.global_position.z, cr2.yaw, cr2.pitch, cr2._ratio, cr2._arm_raw, sn.cam.dist_add, sn.cam.height_add, cam.fov, p.velocity.length()])
		if hist.size() > 6:
			hist.pop_front()
		if big_pops < 6 and prev_cam != Vector3.ZERO and ((cam.global_position - prev_cam) - (pos - (prev_cam - prev_rel))).length() > 1.8:
			big_pops += 1
			for hl in hist:
				print("CP   hist ", hl)
		prev_cam = cam.global_position
		prev_rel = rel
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, pos + Vector3(0, 1.0, 0), Game.L_WORLD)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			counts["occluded"] = int(counts["occluded"]) + 1
			occ_run += dt
			max_occ_run = maxf(max_occ_run, occ_run)
			if int(logged["occluded"]) < 8:
				logged["occluded"] = int(logged["occluded"]) + 1
				var hc := hit.get("collider") as Node
				print("CP   hero hidden at t=%.2f mode %d hero (%.0f, %.0f, %.0f) cam dist %.2f hit %s at %s (hero side: %.2f m from the camera) ratio %.2f arm_raw %.2f" % [t, sn.mode, pos.x, pos.y, pos.z, rel.length(), hc.name if hc != null else "?", str(hit.get("position")), cam.global_position.distance_to(hit["position"]), p.camera_rig._ratio, p.camera_rig._arm_raw])
		else:
			occ_run = 0.0
		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = cam.global_position
		pq.collision_mask = Game.L_WORLD
		if space.intersect_point(pq, 1).is_empty():
			in_run = 0
		else:
			in_run += 1
			max_in_run = maxi(max_in_run, in_run)
			counts["inside"] = int(counts["inside"]) + 1
			if int(logged["inside"]) < 8:
				logged["inside"] = int(logged["inside"]) + 1
				print("CP   lens inside a collider at t=%.2f mode %d hero (%.0f, %.0f, %.0f) cam dist %.2f" % [t, sn.mode, pos.x, pos.y, pos.z, rel.length()])
		if p.camera_rig.is_obstructed():
			counts["obstructed"] = int(counts["obstructed"]) + 1
		if sn.mode == SnakeTraversal.Mode.SWING and sn.swing.phase == &"hang":
			var acc := (p.velocity - prev_v).length() / dt
			max_acc = maxf(max_acc, acc)
			if acc > 90.0:
				counts["jerk"] = int(counts.get("jerk", 0)) + 1
				if int(logged.get("jerk", 0)) < 6:
					logged["jerk"] = int(logged.get("jerk", 0)) + 1
					print("CP   swing acceleration %.0f m/s2 at t=%.2f hero (%.0f, %.0f, %.0f) v %.1f rope %.1f angle %.2f" % [acc, t, pos.x, pos.y, pos.z, p.velocity.length(), sn.swing.rope, sn.swing.rope_angle])
		prev_v = p.velocity
		if sn.mode == SnakeTraversal.Mode.SWING and p.velocity.length() < 4.0:
			stuck_t += dt
			if stuck_t > 1.0:
				counts["stuck"] = int(counts["stuck"]) + 1
		else:
			stuck_t = 0.0
		if hud != null and OS.get_environment("CP_HUD") != "0" and (sn.active() or (not on_floor and p.air_time > 0.5)):
			var ht: String = hud.call(&"hint_text")
			if ht != "":
				prompts[ht] = int(prompts.get(ht, 0)) + 1
				if ht.contains("VEHICLE") or ht.contains("HIJACK") or ht.contains("ENTER"):
					counts["prompt_air"] = int(counts["prompt_air"]) + 1
					if int(logged["prompt_air"]) < 6:
						logged["prompt_air"] = int(logged["prompt_air"]) + 1
						print("CP   prompt '%s' shown in the air at t=%.2f mode %d hero y %.0f" % [ht, t, sn.mode, pos.y])
	Input.action_release(&"snake")
	Input.action_release(&"move_forward")
	Input.action_release(&"fly")
	var names := {0: "NONE", 1: "SWING", 2: "ZIP", 3: "CLIMB", 4: "FLY"}
	var parts: PackedStringArray = []
	for k in mode_time:
		parts.append("%s %.1f s" % [names.get(k, str(k)), float(mode_time[k])])
	print("CP RESULT frames %d  pops(>0.9 m) %d (max %.2f m)  lens inside collider %d  hero hidden %d frames (longest %.2f s)  obstructed %d  stuck-swing frames %d  vehicle prompt in the air %d" % [int(counts["frames"]), int(counts["pops"]), max_pop, int(counts["inside"]), int(counts["occluded"]), max_occ_run, int(counts["obstructed"]), int(counts["stuck"]), int(counts["prompt_air"])])
	print("CP RESULT longest run of frames with the lens inside a collider: %d" % max_in_run)
	print("CP RESULT hero jumps (a frame that moved him more than 1.6 x his speed + 1.2 m): ", hero_jumps)
	print("CP RESULT swing hang: max acceleration %.0f m/s2, frames over 90 m/s2: %d" % [max_acc, int(counts.get("jerk", 0))])
	print("CP RESULT time in ", ", ".join(parts), "  swings ", sn.swings, " zips ", sn.zips, " climbs ", sn.climbs, " flights ", sn.flights, " mantles ", sn.climb.mantles, " best chain ", sn.swing.best_chain)
	print("CP RESULT prompts shown while a state ran or in the air: ", prompts)
	sn.cancel()
	TestMode.god = false
	main.queue_free()
	await frames(3)
