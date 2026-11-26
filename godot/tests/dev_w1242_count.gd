extends RefCounted
const TIMEOUT_SECONDS := 200
const Lib := preload("res://tests/w120_reach_lib.gd")
func run(h: Node) -> void:
	var L := Lib.new()
	await L.start(h)
	await L.f(5)
	var sd := StreetDetail.instance
	var t0 := Time.get_ticks_msec()
	if sd != null and not sd.built:
		sd.build()
	print("COUNT built ms ", Time.get_ticks_msec() - t0)
	if sd == null:
		print("COUNT no instance")
	else:
		for k in StreetDetail.KIND_COUNT:
			print("COUNT ", StreetDetail.KIND_NAMES[k], " ", sd.kind_count[k])
		sd.update(Vector2(Game.SPAWN.x, Game.SPAWN.z), true)
		print("COUNT window tris ", sd.triangles, " near props ", sd.near_props)
	await L.finish()
