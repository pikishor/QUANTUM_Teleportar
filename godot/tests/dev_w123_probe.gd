extends RefCounted
## w123-clutter PROBE (not a check): the real main scene, phone HUD, REAL FINGERS (stick + view swipes). Walks 4 city streets and 2 outskirts streets,
## prints where the hero got stuck, and lists every door within 200 m of the spawn with a street prop or a kerb car in the lane between the door and the kerb.
## Run: tools/test.sh tests/dev_w123_probe.gd
const TIMEOUT_SECONDS := 280
const Lib := preload("res://tests/w120_reach_lib.gd")
const C := preload("res://tests/w123_clutter_lib.gd")
var L: Lib


func run(h: Node) -> void:
	h.get_tree().root.size = Vector2i(844, 390)
	L = Lib.new()
	await L.start(h)
	L.fast(true)
	var s := Game.SPAWN
	var walks := [[s, s + Vector3(-70, 0, 0)], [Vector3(-80, 0, 12.6), Vector3(-80, 0, 70)], [Vector3(12.6, 0, 40), Vector3(12.6, 0, 110)], [Vector3(80 + 12.6, 0, -60), Vector3(92.6, 0, 10)]]
	for wk in walks:
		var a: Vector3 = wk[0]
		var b: Vector3 = wk[1]
		await L.tp(Vector3(a.x, 0.5, a.z), Lib.yaw_to(a, b))
		var r := await L.walk(b, 40.0, 2.0)
		print("PROBE walk %s -> %s reached=%s dist=%.1f block=%s" % [a, b, r["reached"], r["dist"], (r["block"] as Array).map(func(x): return x["what"])])
	var doors := C.doors_near(s, 200.0)
	var bad := 0
	for d in doors:
		await L.tp((d["wall"] as Vector3) + (d["n"] as Vector3) * 2.0 + Vector3(0, 0.5, 0), 0.0)
		var bl := C.blockers(d)
		if not bl.is_empty():
			bad += 1
			print("PROBE BLOCKED %s kerb %.1f: %s" % [d["what"], d["kerb"], bl])
	print("PROBE doors %d, blocked %d" % [doors.size(), bad])
	await L.finish()
