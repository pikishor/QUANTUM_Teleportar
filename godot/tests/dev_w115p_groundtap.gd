extends RefCounted
## Dev probe (wave 115 PLAY critic): what does a first TAP on SNAKE do on a street? 60 random core street spots x random headings, pitch 0.1 (the default view), a 0.12 s tap: zip, climb, swing (hop) or a miss.
## env GT_N (60), GT_DIFF (1)
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
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	p = Game.player as Player
	sn = p.snake
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	TrafficField.bare_street()
	Game.state = &"play"
	TestMode.god = true
	Difficulty.set_mode(int(OS.get_environment("GT_DIFF")) if OS.get_environment("GT_DIFF") != "" else 1)
	var city := Game.world as City
	city.collision_chunks().activate_all()
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var n := int(OS.get_environment("GT_N")) if OS.get_environment("GT_N") != "" else 60
	var tally := {"zip": 0, "climb": 0, "swing": 0, "whiff": 0, "nothing": 0}
	var hints := {}
	for i in n:
		sn.cancel()
		p.invuln = 0.0
		sn.energy = 100.0
		var rp := city.random_core_road_point()
		var yaw := rng.randf() * TAU
		p.teleport_to(rp)
		p.camera_rig.reset_view(yaw, 0.1)
		p.yaw = yaw
		await frames(30)
		var hint := String(sn.hint)
		hints[hint] = int(hints.get(hint, 0)) + 1
		var z0 := sn.zips
		var c0 := sn.climbs
		var s0 := sn.swings
		var w0 := sn.whiffs
		Input.action_press(&"snake")
		await frames(7)
		Input.action_release(&"snake")
		await frames(30)
		var kind := "nothing"
		if sn.zips > z0:
			kind = "zip"
		elif sn.climbs > c0:
			kind = "climb"
		elif sn.swings > s0:
			kind = "swing"
		elif sn.whiffs > w0:
			kind = "whiff"
		tally[kind] = int(tally[kind]) + 1
		await frames(10)
	print("GT %d random street taps: %s | the button label before the tap: %s" % [n, str(tally), str(hints)])
	main.queue_free()
	await frames(3)
