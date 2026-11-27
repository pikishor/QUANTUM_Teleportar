extends RefCounted
## w128-open PROBE (not a suite test): where the on-foot PLAYER script time goes. Times each part of the player's frame by calling it N times while the hero runs.
##   godot --headless --path . res://tests/runner.tscn -- --test=res://tests/probe_w128_player.gd
const TIMEOUT_SECONDS := 200
const N := 300


func run(host: Node) -> void:
	Sfx.muted = true
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	Game.state = &"play"
	var p := Game.player as Player
	p.teleport_to(Vector3(-10.6, 0.4, -40.0))
	await TestLib.frames(host, 20)
	Input.action_press(&"move_forward")
	await TestLib.frames(host, 30)
	var dt := 1.0 / 60.0
	var parts := {
		"body.update_view": func() -> void: p.body.update_view(p, dt, p.global_position, p.yaw),
		"player._process_body": func() -> void: p._process_body(dt),
		"player._physics_process_body": func() -> void: p._physics_process_body(dt),
		"camera_rig._process_body": func() -> void: p.camera_rig._process_body(dt),
		"camera_rig._physics_process_body": func() -> void: p.camera_rig._physics_process_body(dt),
		"weapon._physics_process_body": func() -> void: p.weapon._physics_process_body(dt),
	}
	var z := Vector3.ZERO
	parts["cover.update"] = func() -> void: p.cover.update(dt, true, 4.0)
	parts["combat_step.wish"] = func() -> void: p.combat_step.wish(p, dt, 1.0, false, false, true)
	parts["snake.tick"] = func() -> void: p.snake.tick(p, dt, Vector2(0, -1), Vector3(0, 0, -1), true, false)
	parts["traversal.tick"] = func() -> void: p.traversal.tick(p, dt, 1.0, Vector3(0, 0, -1), false)
	parts["swim.tick"] = func() -> void: p.swim.tick(p, dt, Vector3(0, 0, -1), false, false)
	parts["verbs.tick"] = func() -> void: p.verbs.tick(p, dt, 1.0, Vector3(0, 0, -1), true, false)
	parts["move_and_slide"] = func() -> void: p.move_and_slide()
	parts["weapon.tick"] = func() -> void: p.weapon.tick(dt, false, false, false, true)
	parts["weapon.poll_switch"] = func() -> void: p.weapon.poll_switch()
	parts["rescue_if_lost"] = func() -> void: p.rescue_if_lost()
	parts["_try_step_up"] = func() -> void: p._try_step_up(dt)
	parts["_reach_after_slide"] = func() -> void: p._reach_after_slide()
	parts["_event_gravity"] = func() -> void: p._event_gravity()
	if p.body.rig != null:
		parts["rig (CharacterRig) _process?"] = func() -> void: p.body.rig.call(&"_process", dt) if p.body.rig.has_method(&"_process") else null
	for k: String in parts:
		var c: Callable = parts[k]
		c.call()
		var t0 := Time.get_ticks_usec()
		for i in N:
			c.call()
		var us := float(Time.get_ticks_usec() - t0) / float(N)
		print("PLAYERPART %-36s %7.1f us" % [k, us])
	Input.action_release(&"move_forward")
	main.queue_free()
