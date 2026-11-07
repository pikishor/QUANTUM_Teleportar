extends RefCounted
## Life census bot: the market street around the spawn from the real game camera. At 5 positions (all within 40 m of the spawn) it waits for the city to fill,
## prints a census (civilians, moving cars, vendors, fauna, events, draws) and saves one PNG per spot.
##   SLICE_OUT=<dir> [SLICE_SPOTS=a,b] [SLICE_HUD=0] [SLICE_WAIT=60] BOT_RES=2400x1080 [QUALITY=0|1|2] tools/bot.sh res://tests/bot_slice_life.gd /tmp/x 1000 1
const SPOTS := {
	&"l_e": [-1.5708, -0.10, 0.0, 0.0],             # [yaw, pitch, dx, dz] from the spawn (-30, 4): the market avenue, looking east
	&"l_w": [1.5708, -0.10, -24.0, -4.0],           # the avenue, looking west
	&"l_n": [3.1416, -0.10, 30.0, -26.0],           # the cross road at x = 0, looking north
	&"l_s": [0.0, -0.10, 30.0, 24.0],               # the same cross road, looking south
	&"l_e2": [-1.5708, -0.10, 14.0, -2.0],          # next to the junction, looking east along the avenue
	# close-ups of a near car: [yaw, pitch, side, front] the hero stands this far beside / ahead of a frozen car (SLICE_SPOTS=car_a,car_b,car_c)
	&"car_a": [0.0, -0.05, 5.5, 3.0],
	&"car_b": [0.0, -0.05, 6.5, -4.0],
	&"car_c": [0.0, -0.18, 4.5, 0.0],
	# the market stalls next to the spawn (SLICE_SPOTS=stall_a,stall_b): the hero stands 6 m from the counter, looking at it
	&"stall_a": [0.0, -0.12, 0.0, 0.0],
	&"stall_b": [0.0, -0.12, 0.0, 0.0],
}
var _spots: Array[StringName] = []
var _i := 0
var _wait := 0
var _p: Player
var _out := ""
var _wait_n := 60
var _car_phase := false


func _init() -> void:
	_out = OS.get_environment("SLICE_OUT")
	var w := OS.get_environment("SLICE_WAIT")
	if w != "":
		_wait_n = int(w)
	var s := OS.get_environment("SLICE_SPOTS")
	for n in (s.split(",", false) if s != "" else PackedStringArray()):
		_spots.append(StringName(n))
	if _spots.is_empty():
		for k in SPOTS:
			_spots.append(k)


func step(_t: float, _dt: float) -> bool:
	if _p == null:
		_p = Game.player as Player
		if _p == null:
			return false
		for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
			(n as AutoQuality).enabled = false
		for n in _p.get_tree().root.find_children("*", "Stability", true, false):
			n.set_process(false)
		_p.max_hp = 1.0e6
		if OS.get_environment("SLICE_HUD") == "0":
			for n in _p.get_tree().root.find_children("*", "CanvasLayer", true, false):
				var sc: Script = n.get_script()
				if sc != null and sc.resource_path.contains("/scripts/ui/"):
					(n as CanvasLayer).visible = false
		DirAccess.make_dir_recursive_absolute(_out)
		if OS.get_environment("SLICE_HOUR") != "":
			(Game.world as City).day_night.set_hour(float(OS.get_environment("SLICE_HOUR")))
		_begin()
	if _i >= _spots.size():
		return true
	if _wait > 0:
		_wait -= 1
		_p.hp = _p.max_hp
		return false
	if String(_spots[_i]).begins_with("car_") and not _car_phase:
		_car_phase = true
		if _freeze_car():
			_wait = 14
			return false
	var img := _p.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, _spots[_i]])
	var c: Dictionary = LifeCensus.take(_p.global_position, 40.0)
	var cam := Game.camera.global_position
	var near_d := 1.0e9
	var real_d := 1.0e9
	var real_what := ""
	var nt1: NearTraffic = (Game.world as City).ambient.near_traffic
	for k in nt1.count:
		if nt1.car_alive(k):
			near_d = minf(near_d, Vector2(nt1.car_position(k).x - cam.x, nt1.car_position(k).z - cam.z).length())
	for v in Game.vehicles.list:
		if v.active and not v.dead:
			var dd := Vector2(v.global_position.x - cam.x, v.global_position.z - cam.z).length()
			if dd < real_d:
				real_d = dd
				real_what = "%s ai %s starter %s patrol %s speed %.1f" % [v.kind, v.ai, v.is_starter, v.patrol, v.speed]
	print("LENS %s nearest near car %.1f m, real car %.1f m (%s) from the camera (cam y %.1f)" % [_spots[_i], near_d, real_d, real_what, cam.y])
	var nt0: NearTraffic = (Game.world as City).ambient.near_traffic
	print("CENSUS %s hurt %d fled %d heat %.2f %s draws %d prims %d" % [_spots[_i], nt0.hurt_total, (Game.world as City).ambient.crowd.fled_total(), Game.heat, str(c), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	_i += 1
	_car_phase = false
	if _i >= _spots.size():
		print("SLICE_DONE")
		if OS.get_environment("BOT_FASTEXIT") != "":
			OS.kill(OS.get_process_id())
		return true
	_begin()
	return false


## SLICE_BEFORE=1: what the street was before the life work (24 people within 40 m, no near cars, no stalls, vendors or street events), for the before / after sheet.
func _make_before() -> void:
	var amb: Node3D = (Game.world as City).ambient
	var nt: NearTraffic = amb.near_traffic
	nt.count = 0
	nt.mm.visible_instance_count = 0
	for i in nt._alive.size():
		nt._alive[i] = 0
	amb.vendors.cap = 0
	amb.beats.enabled = false
	var cr = amb.crowd
	cr.radius = 40.0
	for i in range(24, cr.count):
		cr._alive[i] = 0
	cr.count = 24
	for n in (Game.world as City).find_children("MarketStalls*", "", true, false):
		(n as Node3D).visible = false
	var f = amb.fauna
	for i in f.count:
		f.active[i] = 0
	f.count = 0


func _begin() -> void:
	if OS.get_environment("SLICE_BEFORE") == "1":
		_make_before()
	_wait = _wait_n
	Game.state = &"play"
	if is_instance_valid(Game.enemies):
		TestMode.kill_all_enemies()
	TestMode.set_weather("CLEAR")
	TestMode.set_heat(0.0)
	var sp: Array = SPOTS[_spots[_i]]
	var ig := InteriorGameplay.instance
	if ig != null and ig.active:
		ig.leave(true)
	if String(_spots[_i]).begins_with("car_"):
		_p.teleport_to(Game.SPAWN + Vector3(0.0, 0.1, 0.0))
		return
	if String(_spots[_i]).begins_with("stall_"):
		var want := 1 if _spots[_i] == &"stall_a" else -1
		for site: Dictionary in StreetVendors.sites():
			if site["forced"] and (site["pos"] as Vector3).z * float(want) > 0.0:
				var sp3: Vector3 = site["pos"]
				_p.teleport_to(Vector3(sp3.x, 0.1, sp3.z - float(want) * 5.8))
				_p.camera_rig.reset_view(0.0 if want > 0 else PI, float(sp[1]))
				return
	_p.teleport_to(Game.SPAWN + Vector3(float(sp[2]), 0.1, float(sp[3])))
	_p.camera_rig.reset_view(float(sp[0]), float(sp[1]))


## Freeze the nearest moving near car and put the hero beside it, camera on it (the car close-ups).
func _freeze_car() -> bool:
	var nt: NearTraffic = (Game.world as City).ambient.near_traffic
	var best := -1
	var bd := 1.0e9
	for i in nt.count:
		if nt.car_alive(i):
			var d := nt.car_position(i).distance_to(_p.global_position)
			if d > 8.0 and d < bd:
				bd = d
				best = i
	if best < 0:
		return false
	var sp: Array = SPOTS[_spots[_i]]
	nt._stun[best] = 999.0
	nt._spd[best] = 0.0
	var cp := nt.car_position(best)
	var f := Vector3(-sin(nt.car_yaw(best)), 0.0, -cos(nt.car_yaw(best)))
	var side := Vector3(-f.z, 0.0, f.x)
	var hero := cp + side * float(sp[2]) + f * float(sp[3])
	var hero2 := cp - side * float(sp[2]) + f * float(sp[3])
	if _road_off(hero2) < _road_off(hero):                          # stand on the road side, not in a stall
		hero = hero2
	_p.teleport_to(Vector3(hero.x, 0.1, hero.z))
	var d2 := (cp - hero).normalized()
	_p.camera_rig.reset_view(atan2(-d2.x, -d2.z), float(sp[1]))
	return true


static func _road_off(p: Vector3) -> float:
	var ix := absf(p.x - CityLayout.road_center(roundi((p.x + CityLayout.HALF) / CityLayout.PITCH)))
	var iz := absf(p.z - CityLayout.road_center(roundi((p.z + CityLayout.HALF) / CityLayout.PITCH)))
	return minf(ix, iz)
