extends RefCounted
## TEMPORARY probe (landscape builder). Delete before finishing.
func run(host: Node) -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 8)
	Game.state = &"play"
	var city := Game.world as City
	var p := Game.player as Player
	print("AWAKE at start: veg ", city.vegetation.awake, " landscape ", (city.landscape as Landscape).awake)
	p.teleport_to(Vector3(520.0, 1.0, 40.0))
	var times: Array = []
	for i in 14:
		var t0 := Time.get_ticks_msec()
		await TestLib.frames(host, 1)
		times.append(Time.get_ticks_msec() - t0)
	print("FRAME ms after crossing the edge: ", times)
	print("AWAKE after: veg ", city.vegetation.awake, " landscape ", (city.landscape as Landscape).awake, " stats ", (city.landscape as Landscape).stats())
	print("PROBE done")
