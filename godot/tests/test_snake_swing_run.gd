extends RefCounted
## THE SWING RUN: the real city, the real hero, one thumb. The hero drops 40 m above the avenue, SNAKE is held, and the assist chains the swings from building to building: at least five swings
## and at least 400 m of flight without the hero touching the ground (STORY and NORMAL), with real speed (a swing peaks above 25 m/s), a release boost, the snake energy staying alive, and no frame
## of the run longer than a fraction of a second (the city streams chunks under the hero: a hitch there would show here as one long frame). Prints the numbers the tuning is judged by.
## Run: tools/test.sh tests/test_snake_swing_run.gd   (about 70 s)

const TIMEOUT_SECONDS := 140.0

var host: Node
var p: Player
var sn: SnakeTraversal


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	SnakeMissions.reset_flags()
	var mode0 := Difficulty.current
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	p = Game.player as Player
	sn = p.snake
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	Game.state = &"play"
	TestMode.god = true
	SnakeTraversal.assist = true
	await _run(0, "STORY", 11.0)
	await _run(1, "NORMAL", 9.0)
	Input.action_release(&"snake")
	Difficulty.set_mode(mode0)
	TestMode.god = false
	SnakeMissions.reset_flags()
	main.queue_free()
	await frames(3)


func _run(mode: int, tag: String, secs_each: float) -> void:
	Difficulty.set_mode(mode)
	Input.action_release(&"snake")
	sn.cancel()
	p.invuln = 0.0
	p.teleport_to(Vector3(-30.0, 40.0, 4.0))
	await frames(2)
	p.camera_rig.reset_view(-PI * 0.5, 0.2)
	p.yaw = -PI * 0.5
	await frames(4)
	sn.energy = SnakePower.max_energy()
	var s0 := sn.swings
	var best_peak := 0.0
	var path := 0.0
	var ground_in_chain := false
	var last := p.global_position
	var worst_ms := 0.0
	var frame_ms: Array[float] = []
	var t_prev := Time.get_ticks_usec()
	Input.action_press(&"snake")
	var t := 0.0
	var chained := false
	var min_energy := 100.0
	while t < 36.0:
		await frames(1)
		var now := Time.get_ticks_usec()
		var ms := float(now - t_prev) / 1000.0
		t_prev = now
		frame_ms.append(ms)
		worst_ms = maxf(worst_ms, ms)
		t += 1.0 / 60.0
		var pos := p.global_position
		if sn.swings > s0:
			path += pos.distance_to(last)
			chained = true
			best_peak = maxf(best_peak, p.velocity.length())
			min_energy = minf(min_energy, sn.energy)
			if p.is_on_floor() and sn.mode != SnakeTraversal.Mode.SWING and sn.swings - s0 < 5:
				ground_in_chain = true
		last = pos
		if sn.swings - s0 >= 7 and path > 520.0:
			break
		if chained and p.is_on_floor() and sn.mode == SnakeTraversal.Mode.NONE and sn.swings - s0 >= 5:
			break
	Input.action_release(&"snake")
	var n := sn.swings - s0
	frame_ms.sort()
	var p99 := frame_ms[int(float(frame_ms.size()) * 0.99)] if not frame_ms.is_empty() else 0.0
	var avg := 0.0
	for f in frame_ms:
		avg += f
	avg /= maxf(float(frame_ms.size()), 1.0)
	print("SWINGRUN %s: %d swings, path %.0f m, best chain %d, peak %.1f m/s, min energy %.0f, frame ms avg %.1f p99 %.1f worst %.1f" % [tag, n, path, sn.swing.best_chain, best_peak, min_energy, avg, p99, worst_ms])
	TestLib.check(n >= 5, "%s: at least five swings in one hold (%d)" % [tag, n])
	TestLib.check(path >= 400.0, "%s: the swings cover at least 400 m (%.0f m)" % [tag, path])
	TestLib.check(not ground_in_chain, "%s: the first five swings never touch the street" % tag)
	TestLib.check(best_peak > 25.0, "%s: the arcs have speed (peak %.1f m/s)" % [tag, best_peak])
	TestLib.check(sn.swing.releases >= 4, "%s: swings are let go by the chain, boost and all (%d releases)" % [tag, sn.swing.releases])
	TestLib.check(sn.energy > 5.0 or SnakePower.unlimited(), "%s: the swing run does not drain the snake energy dry (%.0f)" % [tag, sn.energy])
	TestLib.check(worst_ms < 400.0, "%s: no long frame in the run (worst %.0f ms, p99 %.1f ms)" % [tag, worst_ms, p99])
	sn.cancel()
	await frames(30)
