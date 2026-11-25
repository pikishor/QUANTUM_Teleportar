extends RefCounted
const TIMEOUT_SECONDS := 200
const Lib := preload("res://tests/w120_reach_lib.gd")
func run(h: Node) -> void:
	var L := Lib.new()
	await L.start(h)
	var life = (Game.world as City).ambient.life
	life._mark_bad()
	var n := 0
	var bad := 0
	for k in StreetLife.benches.size():
		var b: Vector3 = StreetLife.benches[k]
		if b.x < -230 or b.x > 20 or absf(b.z + 228.7) > 40: continue
		n += 1
		bad += life._bad_b[k]
		print("Q bench ", Vector2(b.x, b.z), " bad ", life._bad_b[k], " ", StreetLife.solid_at(b.x, b.z, 0.3, "StreetDress"), " / ", StreetLife.solid_at(b.x, b.z, 0.3))
	print("Q near street ", n, " bad ", bad)
	L.finish()
