extends RefCounted
## Dev helper (not a test): how long City takes to build. tools/test.sh tests/dev_world_timing.gd


func run(host: Node) -> void:
	var scene := load("res://scenes/world.tscn") as PackedScene
	var t0 := Time.get_ticks_usec()
	var city := scene.instantiate() as City
	var t1 := Time.get_ticks_usec()
	host.add_child(city)
	var t2 := Time.get_ticks_usec()
	print("instantiate %.1f ms, _ready (build everything) %.1f ms" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
	await TestLib.frames(host, 2)
	print("static memory after build: %.1f MB, objects %d" % [OS.get_static_memory_usage() / 1048576.0, int(Performance.get_monitor(Performance.OBJECT_COUNT))])
