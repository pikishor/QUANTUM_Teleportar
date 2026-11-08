extends RefCounted
## Visual bot of the interior tasks: what a phone player sees inside a building (the contextual USE button, the floating plates over the objects, the task status line, the LEAVE button),
## from the real game camera with the touch layer on, one PNG per spot.
##   TASKS_OUT=<dir> [TASKS_SPOTS=a,b] BOT_RES=2400x1080 BOT_USER_ARGS=--touch QUALITY=1 BOT_FASTEXIT=1 tools/bot.sh res://tests/bot_interior_tasks.gd /tmp/x 4000 1
const SETTLE := 22
## name: [interior type, what]   what: entry | gate | object | vendor | far | leave_ask
const SPOTS := {
	&"t1_lobby_entry": [&"lobby", &"entry"],
	&"t2_lobby_gate": [&"lobby", &"gate"],
	&"t3_lobby_safe": [&"lobby", &"object"],
	&"t4_checkpoint_hack": [&"checkpoint", &"object"],
	&"t5_weapons_talk": [&"weapons", &"vendor"],
	&"t6_apartment_clear": [&"apartment", &"hostage"],
	&"t7_club_find": [&"club", &"entry"],
	&"t8_warehouse_plant": [&"warehouse", &"stealth"],
	&"t9_server_copy": [&"server_room", &"stealth"],
	&"t10_med_nojob": [&"med_bay", &"entry"],
	&"t11_leave_ask": [&"checkpoint", &"leave_ask"],
	&"t12_bar_exit": [&"bar", &"exit"],
}
var _spots: Array[StringName] = []
var _i := 0
var _wait := 0
var _p: Player
var _out := ""
var _stage := 0


func _init() -> void:
	_out = OS.get_environment("TASKS_OUT")
	var s := OS.get_environment("TASKS_SPOTS")
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
		DirAccess.make_dir_recursive_absolute(_out)
		_begin()
	if _i >= _spots.size():
		return true
	if _wait > 0:
		_wait -= 1
		_p.hp = _p.max_hp
		_p.invuln = 99.0
		_blind()
		if _wait == 8 and _stage == 1:
			_after_settle()
		return false
	var img := _p.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, _spots[_i]])
	var ig := InteriorGameplay.instance
	print("TASKS %s prompt '%s' status '%s' hud '%s' plates %d draws %d" % [_spots[_i], InteriorGameplay.prompt, InteriorGameplay.status_line, InteriorGameplay.hud_line,
			ig.tasks.prompts.plates.size() if ig != null and ig.tasks != null and ig.tasks.prompts != null else -1, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	_i += 1
	if _i >= _spots.size():
		print("TASKS_DONE")
		if OS.get_environment("BOT_FASTEXIT") != "":
			OS.kill(OS.get_process_id())
		return true
	_begin()
	return false


func _blind() -> void:
	var ig := InteriorGameplay.instance
	if ig != null and ig.active and is_instance_valid(ig.actors):
		for g in ig.actors.guards:
			if is_instance_valid(g):
				g.aware_dist = 0.0
				g.suspicion = 0.0
	Game.heat = 0.0


func _begin() -> void:
	_wait = SETTLE
	_stage = 1
	Game.state = &"play"
	if is_instance_valid(Game.enemies):
		TestMode.kill_all_enemies()
	TestMode.set_weather("CLEAR")
	TestMode.set_heat(0.0)
	var sp: Array = SPOTS[_spots[_i]]
	var ig := InteriorGameplay.instance
	if ig == null:
		return
	if ig.active:
		ig.leave(true)
	((Game.missions as Missions).stealth as StealthRunner).abort("RESET")
	var list := ig.doors_of(sp[0], Game.SPAWN)
	if list.is_empty():
		ig.test_enter(sp[0])
	else:
		_p.teleport_to(list[0]["pos"])
		ig.enter(list[0], true)
	_p.camera_rig.reset_view(ig.interior.get("door_yaw") if ig.interior != null else 0.0, -0.12)


## Part way through the settle time (the room has been built and ticked): put the hero at the spot of the shot and aim the camera at the object.
func _after_settle() -> void:
	_stage = 2
	var ig := InteriorGameplay.instance
	if ig == null or not ig.active:
		return
	var sp: Array = SPOTS[_spots[_i]]
	var m := ig.missions
	var look := Vector3.INF
	match sp[1]:
		&"gate":
			if is_instance_valid(m.puzzles) and not m.puzzles.next_gate().is_empty():
				var g: Dictionary = m.puzzles.next_gate()
				_stand(m.puzzles.at(float(g["depth"]) + 2.4), m.puzzles.at(float(g["depth"])))
		&"object":
			if is_instance_valid(m.puzzles):
				while m.puzzles.assist():
					pass
			var at := m.target_pos
			var away: Vector3 = (ig.interior.get("door_pos") as Vector3) - at
			away.y = 0.0
			_stand(at + away.normalized() * 1.7, at)
		&"vendor":
			var v := ig.actors.vendor
			if v != null:
				var away2: Vector3 = (ig.interior.get("door_pos") as Vector3) - v.global_position
				away2.y = 0.0
				_stand(v.global_position + away2.normalized() * 2.2, v.global_position)
		&"hostage":
			var h := ig.actors.hostage
			if h != null:
				var away3: Vector3 = (ig.interior.get("door_pos") as Vector3) - h.global_position
				away3.y = 0.0
				_stand(h.global_position + away3.normalized() * 3.6, h.global_position)
		&"stealth":
			var st := (Game.missions as Missions).stealth
			var want: StringName = StealthScripts.for_interior(sp[0])
			if want != &"":
				st.start(want)
				var away4: Vector3 = (ig.interior.get("door_pos") as Vector3) - st.target_pos
				away4.y = 0.0
				_stand(st.target_pos + away4.normalized() * 1.5, st.target_pos)
		&"leave_ask":
			if is_instance_valid(m.puzzles):
				while m.puzzles.assist():
					pass
			var at2 := m.target_pos
			var away5: Vector3 = (ig.interior.get("door_pos") as Vector3) - at2
			away5.y = 0.0
			_stand(at2 + away5.normalized() * 1.7, at2)
			m.hacking = true
			m.progress = 0.35
			_wait = 18                             # a few more frames: the press happens next
			Input.action_press(&"leave_building")
			_p.get_tree().create_timer(0.12).timeout.connect(func() -> void: Input.action_release(&"leave_building"))
		&"exit":
			var ex := InteriorGameplay.exit_point(ig.interior)
			var inward: Vector3 = (ig.interior.get("bounds") as Rect2).get_center().x * Vector3.RIGHT + Vector3(0.0, 0.0, (ig.interior.get("bounds") as Rect2).get_center().y) - ex
			inward.y = 0.0
			_stand(ex + inward.normalized() * 1.2, ex)


func _stand(pos: Vector3, look_at: Vector3) -> void:
	_p.teleport_to(Vector3(pos.x, InteriorGameplay.ORIGIN.y + 0.1, pos.z))
	_p.camera_rig.look_at_point(Vector3(look_at.x, 1.2, look_at.z))
