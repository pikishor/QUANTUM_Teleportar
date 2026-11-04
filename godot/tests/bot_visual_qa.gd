extends RefCounted
## Visual QA bot: ~12 fixed spots, one PNG each plus numeric checks (tests/visual_qa_lib.gd). Use tools/visual_qa.sh.
##   VQA_OUT=<dir> (PNG folder)  VQA_SPOTS=a,b (subset)   prints VQA <spot> PASS|FAIL mean= contrast= black= [sep=] [why]
const SPOTS: Array[StringName] = [&"street_nw", &"street_ne", &"street_sw", &"street_se", &"interior", &"car", &"chase", &"boss", &"title", &"hero", &"rain", &"storm", &"sky_dawn", &"sky_noon", &"sky_dusk", &"sky_night"]
const SETTLE := 16
var _i := 0
var _wait := 0
var _phase := 0
var _spots: Array[StringName] = []
var _out := ""
var _p: Player
var _shown: Image
var _hidden_nodes: Array[MeshInstance3D] = []
var _fails := 0


func _init() -> void:
	_out = OS.get_environment("VQA_OUT")
	var s := OS.get_environment("VQA_SPOTS")
	for n in (s.split(",", false) if s != "" else PackedStringArray()):
		_spots.append(StringName(n))
	if _spots.is_empty():
		_spots.assign(SPOTS)


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
		DirAccess.make_dir_recursive_absolute(_out)
		_begin()
	if _wait > 0:
		_wait -= 1
		_hold()
		return false
	var spot := _spots[_i]
	var vp := _p.get_viewport()
	if spot == &"hero" and _phase == 0:
		_shown = vp.get_texture().get_image()
		_set_hero(false)
		_phase = 1
		_wait = 4
		return false
	var img: Image = _shown if _phase == 1 else vp.get_texture().get_image()
	var sep := -1.0
	if _phase == 1:
		var hidden := vp.get_texture().get_image()
		_set_hero(true)
		sep = float(VisualQaLib.separation(_shown, hidden)["sep"])
	var st := VisualQaLib.stats(img)
	var people := -1
	if String(spot).begins_with("street_"):
		for n in _p.get_tree().root.find_children("*", "Node3D", true, false):
			var cr = n.get("crowd")
			if cr != null and cr.has_method(&"count_near"):
				people = cr.count_near(_p.global_position, VisualQaLib.PEOPLE_RADIUS)
				break
	var why := VisualQaLib.verdict(st, sep, people)
	img.save_png("%s/%s.png" % [_out, spot])
	if why != "":
		_fails += 1
	print("VQA %s %s mean=%.3f contrast=%.3f black=%.3f%s %s" % [spot, "PASS" if why == "" else "FAIL", st["mean"], st["contrast"], st["black"], ((" sep=%.3f" % sep) if sep >= 0.0 else "") + ((" people=%d" % people) if people >= 0 else ""), why])
	_i += 1
	if _i >= _spots.size():
		print("VQA_DONE fails=%d" % _fails)
		if OS.get_environment("BOT_FASTEXIT") != "":
			OS.kill(OS.get_process_id())
		return true
	_begin()
	return false


var _look := Vector3.INF
var _cine: Transform3D
var _use_cine := false


func _hold() -> void:
	if _use_cine:
		_p.camera_rig.cine_set(_cine, 80.0)
	elif _look.is_finite():
		_p.camera_rig.look_at_point(_look)


func _begin() -> void:
	_phase = 0
	_wait = SETTLE
	_look = Vector3.INF
	_use_cine = false
	Game.state = &"play"
	if is_instance_valid(Game.enemies):
		TestMode.kill_all_enemies()
	TestMode.set_weather("CLEAR")
	var spot := _spots[_i]
	var corner := ""
	match spot:
		&"street_nw", &"street_ne", &"street_sw", &"street_se":
			corner = String(spot).trim_prefix("street_")
			TestMode.teleport(corner)
			_p.camera_rig.reset_view(-PI * 0.5 if corner.ends_with("e") else PI * 0.5, -0.08)
		&"interior":
			var ig := InteriorGameplay.instance
			if ig != null:
				ig.leave(true)
				_p.teleport_to(Game.SPAWN)
				ig.enter(ig.doors_of(&"weapons", Game.SPAWN)[0], true)
		&"car":
			_p.teleport_to(Game.SPAWN)
			_p.camera_rig.reset_view(-PI * 0.5, -0.1)
			TestMode.spawn_vehicle(&"sport")
			var veh := _nearest_vehicle()
			if veh != null:
				_cine = Transform3D(Basis.looking_at(Vector3(-1, -0.15, 0.6)), veh.global_position + Vector3(3.2, 1.3, -1.8))
				_cine = _cine.looking_at(veh.global_position + Vector3(0, 0.6, 0), Vector3.UP)
				_use_cine = true
		&"chase", &"boss":
			TestMode.teleport("spawn")
			TestMode.start_contract(&"chase" if spot == &"chase" else &"boss")
			var k = Game.missions.get(&"contracts") if is_instance_valid(Game.missions) else null
			if k != null and is_instance_valid(k.get(&"target")):
				_look = (k.get(&"target") as Node3D).global_position + Vector3(0, 1.0, 0)
		&"title":
			Game.state = &"menu"
		&"hero":
			var ig2 := InteriorGameplay.instance
			if ig2 != null:
				ig2.leave(true)
			_p.teleport_to(Game.SPAWN)
			var o := _p.global_position
			_cine = Transform3D(Basis.IDENTITY, o + Vector3(1.6, 1.5, 1.4)).looking_at(o + Vector3(0, 1.2, 0), Vector3.UP)
			_use_cine = true
		&"sky_dawn", &"sky_noon", &"sky_dusk", &"sky_night":
			_p.teleport_to(Game.SPAWN)
			_p.camera_rig.reset_view(-PI * 0.5, 0.45)
			var dn: DayNight = (Game.world as City).day_night
			dn.frozen = true
			dn.set_hour({&"sky_dawn": 6.0, &"sky_noon": 12.0, &"sky_dusk": 18.5, &"sky_night": 1.0}[spot])
		&"rain", &"storm":
			_p.teleport_to(Game.SPAWN)
			_p.camera_rig.reset_view(-PI * 0.5, -0.1)
			TestMode.set_weather("RAIN" if spot == &"rain" else "STORM")


func _nearest_vehicle() -> Node3D:
	var best: Node3D
	var bd := 1.0e9
	for v: Vehicle in (Game.vehicles as VehicleManager).list:
		if is_instance_valid(v):
			var d := v.global_position.distance_to(_p.global_position)
			if d < bd:
				bd = d
				best = v
	return best


func _set_hero(on: bool) -> void:
	if not on:
		_hidden_nodes.clear()
		for n in _p.body.find_children("*", "MeshInstance3D", true, false):
			var m := n as MeshInstance3D
			if m.visible and m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				m.visible = false
				_hidden_nodes.append(m)
	else:
		for m in _hidden_nodes:
			if is_instance_valid(m):
				m.visible = true
		_hidden_nodes.clear()
