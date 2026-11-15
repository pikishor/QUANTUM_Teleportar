extends RefCounted
## Dev probe: take off and fly with the stick forward, boost, hover, land. Prints the flight internals. Run: tools/test.sh tests/dev_snake_fly.gd

const TIMEOUT_SECONDS := 100.0
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
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	Game.state = &"play"
	TestMode.god = true
	Difficulty.set_mode(1)
	p.teleport_to(Game.SPAWN)
	await frames(30)
	p.camera_rig.reset_view(-PI * 0.5, 0.15)
	var sn := p.snake
	Input.action_press(&"fly")
	await frames(3)
	Input.action_release(&"fly")
	var t := 0.0
	var phase_i := 0
	while t < 14.0:
		await frames(6)
		t += 0.1
		if t > 1.0 and phase_i == 0:
			phase_i = 1
			Input.action_press(&"move_forward")
		if t > 5.0 and phase_i == 1:
			phase_i = 2
			Input.action_press(&"snake")
		if t > 7.0 and phase_i == 2:
			phase_i = 3
			Input.action_release(&"snake")
			Input.action_release(&"move_forward")
		if t > 10.0 and phase_i == 3:
			phase_i = 4
			Input.action_press(&"fly")
			await frames(3)
			Input.action_release(&"fly")
		var f := sn.flight
		if int(t * 10.0) % 4 == 0:
			print("FLY %4.1f %-5s ph %-7s sp %5.1f v (%5.1f %5.1f %5.1f) pos (%7.1f %6.1f %7.1f) e %5.1f dir (%.2f %.2f %.2f) boost %s floor %s" % [t, sn.mode_name(), String(f.phase), f.speed, p.velocity.x, p.velocity.y, p.velocity.z, p.global_position.x, p.global_position.y, p.global_position.z, sn.energy, f.dir.x, f.dir.y, f.dir.z, f.boosting, p.is_on_floor()])
	print("FLY SUMMARY flights %d best %.1f max alt %.1f dist %.0f landings %d crashes %d boosts %d" % [sn.flight.flights, sn.flight.best_speed, sn.flight.max_alt, sn.flight.distance, sn.flight.landings, sn.flight.crashes, sn.flight.boosts])
