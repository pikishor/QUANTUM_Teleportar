extends RefCounted
## Dev probe: how many process frames per physics tick and per game second does the headless runner give (to size waits)?
const TIMEOUT_SECONDS := 60.0
var host: Node

func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 40)
	var p := Game.player as Player
	Game.state = &"play"
	var f0 := Engine.get_process_frames()
	var ph0 := Engine.get_physics_frames()
	var t0 := p.snake.time
	var r0 := Time.get_ticks_msec()
	await TestLib.frames(host, 120)
	print("CLK 120 awaited frames = %d process frames, %d physics ticks, %.2f game s on the snake clock, %d ms real" % [Engine.get_process_frames() - f0, Engine.get_physics_frames() - ph0, p.snake.time - t0, Time.get_ticks_msec() - r0])
	main.queue_free()
	await TestLib.frames(host, 3)
