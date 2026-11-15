extends RefCounted
## Dev probe (wave 115 PLAY critic, not a test): how do the snake buttons answer REAL finger behaviour (taps of 0.05 to 0.3 s, holds, a press right after leaving the ground), measured in the real scene
## on the builders' own spots (so an anchor exists)? Prints one line per case. SECTIONS=air,flight (env INP_ONLY picks one).
## Run: scratchpad/run_probe.sh tests/dev_w115p_input.gd 140 "^INP"

const TIMEOUT_SECONDS := 140.0

var host: Node
var p: Player
var sn: SnakeTraversal


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func release_all() -> void:
	for a in [&"snake", &"fly", &"jump", &"move_forward", &"move_back", &"move_left", &"move_right", &"crouch", &"sprint", &"fire"]:
		Input.action_release(a)


func prep(pos: Vector3, yaw := -PI * 0.5, pitch := 0.0) -> void:
	release_all()
	sn.cancel()
	TrafficField.bare_street()
	p.invuln = 0.0
	p.hp = p.max_hp
	sn.energy = SnakePower.max_energy()
	p.teleport_to(pos)
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	await frames(12)


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
	Game.state = &"play"
	TestMode.god = true
	Difficulty.set_mode(1)
	SnakeTraversal.assist = true
	var only := OS.get_environment("INP_ONLY")
	if only == "" or only == "air":
		await _air_taps()
	if only == "" or only == "flight":
		await _flight_cases()
	release_all()
	main.queue_free()
	await frames(3)


## An air tap of different lengths at a spot with a known anchor: does a short press swing?
func _air_taps() -> void:
	for hold_ticks in [3, 6, 9, 12, 18, 30]:
		await prep(Vector3(-30.0, 40.0, 4.0), -PI * 0.5, 0.2)
		var s0 := sn.swings
		var w0 := sn.whiffs
		var rel0 := sn.swing.releases
		Input.action_press(&"snake")
		await frames(hold_ticks)
		Input.action_release(&"snake")
		await frames(90)
		print("INP air tap %.2f s: swings started %d, bitten %d, releases %d, whiffs %d, mode after 1.5 s %s, y %.1f" % [float(hold_ticks) / 60.0, sn.swings - s0, sn.swing.swings, sn.swing.releases - rel0, sn.whiffs - w0, sn.mode_name(), p.global_position.y])
	# a press the instant the hero leaves the ground (a thumb on SNAKE while running off a roof): zip or swing?
	await prep(Vector3(-30.0, 38.0, 4.0), -PI * 0.5, 0.2)
	sn.cancel()
	release_all()
	# a tap on the ground facing a tall facade: ZIP, then what does the hero do on arrival (the wall: a climb)?
	await prep(Vector3(-30.0, 0.0, 4.0), PI, 0.38)
	var z0 := sn.zips
	Input.action_press(&"snake")
	await frames(6)
	Input.action_release(&"snake")
	var seen: Array[String] = []
	for i in 240:
		await frames(1)
		var m := sn.mode_name()
		if seen.is_empty() or seen[seen.size() - 1] != m:
			seen.append(m)
		if sn.mode == SnakeTraversal.Mode.NONE and i > 30 and p.is_on_floor():
			break
	print("INP ground tap at a facade: zips %d, modes %s, end y %.1f, on floor %s" % [sn.zips - z0, str(seen), p.global_position.y, str(p.is_on_floor())])


func _flight_cases() -> void:
	# 1 take-off, 2 stick forward, 3 LAND: time to the ground and damage
	await prep(Vector3(-30.0, 0.0, 4.0), -PI * 0.5, 0.12)
	Input.action_press(&"fly")
	await frames(4)
	Input.action_release(&"fly")
	await frames(60)
	var y1 := p.global_position.y
	Input.action_press(&"move_forward")
	await frames(120)
	var sp := p.velocity.length()
	var y2 := p.global_position.y
	Input.action_press(&"fly")
	await frames(4)
	Input.action_release(&"fly")
	var t := 0
	var hp0 := p.hp
	while t < 600 and not (sn.mode == SnakeTraversal.Mode.NONE and p.is_on_floor()):
		await frames(1)
		t += 1
	Input.action_release(&"move_forward")
	print("INP flight: take-off y %.1f after 1 s, cruise %.1f m/s at y %.1f, LAND took %.1f s, hp %.0f -> %.0f, mode %s, floor %s, energy %.0f" % [y1, sp, y2, float(t) / 60.0, hp0, p.hp, sn.mode_name(), str(p.is_on_floor()), sn.energy])
	# hold SNAKE on open ground with nothing to bite: how long to flight
	await prep(Vector3(3000.0, 0.0, 200.0), 0.0, -0.1)
	var f0 := sn.flights
	Input.action_press(&"snake")
	var tt := 0
	while tt < 240 and sn.flights == f0:
		await frames(1)
		tt += 1
	Input.action_release(&"snake")
	print("INP hold SNAKE on open ground: flight after %.2f s (flights %d), whiffs %d" % [float(tt) / 60.0, sn.flights - f0, sn.whiffs])
	await frames(20)
	# FLY with a locked flight (HARD without WING POWER): the message and the state
	Difficulty.set_mode(2)
	await prep(Vector3(3000.0, 0.0, 200.0), 0.0, -0.1)
	Input.action_press(&"fly")
	await frames(4)
	Input.action_release(&"fly")
	await frames(30)
	print("INP HARD: FLY pressed -> mode %s, flights %d, locked %s" % [sn.mode_name(), sn.flights, str(not SnakePower.flight_unlocked())])
	Difficulty.set_mode(1)
