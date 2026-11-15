extends RefCounted
## Dev probe (not a test): the real city, the real hero, a hand-off swing run driven only through the input actions. Prints one line per half second and a summary: the numbers the
## swing constants are tuned with. Run: tools/test.sh tests/dev_snake_chain.gd   env SC_SECS=24 SC_YAW=-1.5708 (radians) SC_X, SC_Z (start), SC_DIFF (difficulty 0..3), SC_ASSIST=0
## Prints: "t mode pos speed energy chain swings ground" and at the end distance, max speed, swings, ground touches.

const TIMEOUT_SECONDS := 120.0

var host: Node
var p: Player


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	p = Game.player as Player
	var em := Game.enemies as EnemyManager
	em.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	Game.state = &"play"
	TestMode.god = true
	var diff := int(OS.get_environment("SC_DIFF")) if OS.get_environment("SC_DIFF") != "" else 0
	Difficulty.set_mode(diff)
	SnakeTraversal.assist = OS.get_environment("SC_ASSIST") != "0"
	if OS.get_environment("SC_ASSIST_ACC") != "":
		SnakeSwing.assist_acc = float(OS.get_environment("SC_ASSIST_ACC"))
	if OS.get_environment("SC_ASSIST_RISE") != "":
		SnakeSwing.assist_rise = float(OS.get_environment("SC_ASSIST_RISE"))
	if OS.get_environment("SC_REL_FAST") != "":
		SnakeSwing.rel_fast = float(OS.get_environment("SC_REL_FAST"))
	if OS.get_environment("SC_REL_SLOW") != "":
		SnakeSwing.rel_slow = float(OS.get_environment("SC_REL_SLOW"))
	var secs := float(OS.get_environment("SC_SECS")) if OS.get_environment("SC_SECS") != "" else 24.0
	var yaw := float(OS.get_environment("SC_YAW")) if OS.get_environment("SC_YAW") != "" else -PI * 0.5
	var start := Game.SPAWN
	if OS.get_environment("SC_X") != "":
		start = Vector3(float(OS.get_environment("SC_X")), 0.0, float(OS.get_environment("SC_Z")))
	var start_y := float(OS.get_environment("SC_Y")) if OS.get_environment("SC_Y") != "" else 0.0
	p.teleport_to(start + Vector3(0.0, start_y, 0.0))
	await frames(30 if start_y <= 0.0 else 1)
	p.camera_rig.reset_view(yaw, 0.28)
	p.yaw = yaw
	await frames(5)
	print("SC start ", p.global_position, " yaw ", yaw, " diff ", diff, " assist ", SnakeTraversal.assist)
	# a hop, then hold SNAKE in the air
	if start_y <= 0.0:
		Input.action_press(&"jump")
		await frames(14)
		Input.action_release(&"jump")
	var t := 0.0
	var pressed := false
	var ground := 0
	var was_ground := true
	var origin := p.global_position
	var max_speed := 0.0
	var last_print := -1.0
	var sn := p.snake
	var air_t := 0.0
	while t < secs:
		await frames(1)
		t += 1.0 / 60.0
		p.camera_rig.yaw = yaw if not sn.active() else p.camera_rig.yaw
		if not pressed and p.air_time > 0.25:
			Input.action_press(&"snake")
			pressed = true
		var on_floor := p.is_on_floor() and p.air_time < 0.05
		if on_floor and not was_ground:
			ground += 1
		was_ground = on_floor
		max_speed = maxf(max_speed, p.velocity.length())
		if t - last_print >= 0.5:
			last_print = t
			print("SC %5.1f %-5s pos (%7.1f %6.1f %7.1f) v %5.1f e %5.1f chain %d swings %d ground %d" % [t, sn.mode_name(), p.global_position.x, p.global_position.y, p.global_position.z, p.velocity.length(), sn.energy, sn.swing.chain, sn.swings, ground])
		if on_floor and t > 3.0 and sn.mode == SnakeTraversal.Mode.NONE:
			Input.action_release(&"snake")
			pressed = false
			await frames(10)
			Input.action_press(&"jump")
			await frames(10)
			Input.action_release(&"jump")
	Input.action_release(&"snake")
	var d := Vector2(p.global_position.x - origin.x, p.global_position.z - origin.z).length()
	for e in sn.swing.log:
		print("SC swing ", e)
	print("SC SUMMARY dist %.0f m, max speed %.1f, swings %d, best chain %d, ground touches %d, whiffs %d, rays last %d" % [d, max_speed, sn.swings, sn.best_chain, ground, sn.whiffs, sn.anchors.rays])
	Difficulty.set_mode(1)
