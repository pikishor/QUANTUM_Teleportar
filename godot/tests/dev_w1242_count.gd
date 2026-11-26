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
		for k in StreetDetail.KIND_COUNT:
			var g := StreetDetail.make_geo(k, 0, "KESTREL ST|ORBIT AVE" if k == StreetDetail.NAME_SIGN else "ARMS", 0, true)
			print("COUNT tris ", StreetDetail.KIND_NAMES[k], " ", int(g["count"]) / 3)
		for sc in [0.65, 0.85, 1.0]:
			sd.q_scale = sc
			sd.update(Vector2(Game.SPAWN.x, Game.SPAWN.z), true)
			print("COUNT scale ", sc, " window tris ", sd.triangles, " near props ", sd.near_props)
	await L.finish()
