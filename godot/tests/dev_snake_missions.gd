extends RefCounted
## Dev probe: the two snake missions through the runner, printing the runner state. Run: tools/test.sh tests/dev_snake_missions.gd
const TIMEOUT_SECONDS := 120.0
var host: Node


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func run(hst: Node) -> void:
	host = hst
	Sfx.muted = true
	SnakeMissions.reset_flags()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	var p := Game.player as Player
	(Game.enemies as EnemyManager).clear()
	Game.state = &"play"
	TestMode.god = true
	var board := (Game.missions as Missions).board
	var camp := (Game.missions as Missions).campaign
	var chase := board.build(&"roof_chase", Game.SPAWN)
	print("MS chase offer: ", chase.get("title"), " steps ", (chase.get("steps") as Array).size())
	for st in chase["steps"]:
		print("MS   step ", st["kind"], " ", st["pos"], " text ", st["text"])
	print("MS start ", camp.start_custom(chase["chapter"]), " state ", camp.state, " idx ", camp.step_index)
	for i in 4:
		var n := 0
		while not (camp.state == &"active" and camp.step_index == i) and n < 300:
			await frames(1)
			n += 1
		print("MS step %d active after %d frames: state %s kind %s pos %s target %s" % [i, n, camp.state, camp.step.get("kind"), str(camp.step.get("pos")), str(camp.target)])
		if i == 3:
			await frames(30)
			print("MS   step 3 after 30 frames: target ", camp.target, " foes ", camp.foes.size(), " alive ", (Game.enemies as EnemyManager).alive_count(), " cap ", (Game.enemies as EnemyManager).cap(), " state ", camp.state)
			break
		var q: Vector3 = camp.step["pos"]
		p.teleport_to(q + Vector3(0.0, 0.3, 0.0))
		await frames(30)
		print("MS   hero %s state %s idx %d" % [str(p.global_position), camp.state, camp.step_index])
