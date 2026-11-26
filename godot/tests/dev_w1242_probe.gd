extends RefCounted
## w1242-street probe (dev only): cars on the sidewalk near benches and bus stops, bus dwell count.
const TIMEOUT_SECONDS := 400
const Lib := preload("res://tests/w120_reach_lib.gd")
var L: Lib

func _corners(pos: Vector3, yaw: float, hl: float, hw: float) -> Array:
	var f := Vector3(sin(yaw), 0, cos(yaw))
	var r := Vector3(f.z, 0, -f.x)
	return [pos + f * hl + r * hw, pos + f * hl - r * hw, pos - f * hl + r * hw, pos - f * hl - r * hw]

func run(h: Node) -> void:
	L = Lib.new()
	await L.start(h)
	NearTraffic.instance.enabled = true
	NearTraffic.instance.count = NearTraffic.instance.cap() if NearTraffic.instance.has_method(&"cap") else 24
	RoadTraffic.instance.enabled = true
	var pc: ParkedCars = Game.world.ambient.parked
	var bs: Array = StreetLife.benches.duplicate()
	bs.sort_custom(func(a, b): return Vector2(a.x, a.z).distance_to(Vector2(Game.SPAWN.x, Game.SPAWN.z)) < Vector2(b.x, b.z).distance_to(Vector2(Game.SPAWN.x, Game.SPAWN.z)))
	var bad := 0
	var tot := 0
	for k in 8:
		var b: Vector3 = bs[k]
		await L.tp(Vector3(b.x + 3.0, 0.3, b.z + 3.5 * b.y), 0.0)
		await L.secs(8.0)
		for v in h.get_tree().get_nodes_in_group(&"vehicle"):
			var vp: Vector3 = v.global_position
			if vp.distance_to(L.p.global_position) < 40.0 and absf(vp.x) < 1000.0:
				var off := 0
				for c in _corners(vp, v.global_rotation.y, 2.3, 0.9):
					if not CityLayout.on_road(c.x, c.z, 0.0):
						off += 1
				print("bench ", k, " vehicle ", v.name, " ", vp.snapped(Vector3.ONE * 0.1), " corners off road ", off)
	for i in ParkedCars.CAP:
		if not pc.car_alive(i):
			continue
		tot += 1
		var pos := pc.car_position(i)
		for c in _corners(pos, pc.car_yaw(i), 2.3, 0.9):
			if not CityLayout.on_road(c.x, c.z, 0.0) and absf(c.x) < CityLayout.HALF and absf(c.z) < CityLayout.HALF:
				bad += 1
				print("ON SIDEWALK car ", i, " ", pc.car_kind(i), " at ", pos.snapped(Vector3.ONE * 0.1), " yaw ", snappedf(pc.car_yaw(i), 0.01), " corner ", c.snapped(Vector3.ONE * 0.1))
				break
	print("PROBE parked=", tot, " on sidewalk=", bad)
	for v in h.get_tree().get_nodes_in_group(&"vehicle"):
		var vp: Vector3 = v.global_position
		if not CityLayout.on_road(vp.x, vp.z, 1.0):
			print("VEHICLE off road ", v.name, " ", vp.snapped(Vector3.ONE * 0.1))
	await L.finish()
