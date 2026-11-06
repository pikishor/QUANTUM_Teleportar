extends RefCounted
## Glitch scan bot: real-game-camera frames at the phone aspect (touch HUD on) of the places where the owner saw translucent slabs, white sheets and the black hero patch.
##   GLITCH_OUT=<dir> GLITCH_SPOTS=a,b GLITCH_HOUR=12 BOT_RES=1200x540 QUALITY=0 tools/bot.sh res://tests/bot_glitch_scan.gd /tmp/x 100000 1
## Spots: street_<hour> (spawn crosswalk, hero from behind), int_<type> (hero from behind in a door's interior), hero_back / hero_side (closeups), hud_off variants add `_clean`.
## Prints GLITCH <spot> <flat-translucent fraction> <rect> per shot. The same numeric check is VisualQaLib.translucent_slabs.
const SETTLE := 14
var _i := 0
var _wait := 0
var _spots: Array[String] = []
var _out := ""
var _p: Player
var _hud: Hud
var _cine: Transform3D
var _use_cine := false
var _hide_hud := false


func _init() -> void:
	_out = OS.get_environment("GLITCH_OUT")
	var s := OS.get_environment("GLITCH_SPOTS")
	if s != "":
		for n in s.split(",", false):
			_spots.append(n)
	else:
		_spots.assign(["street_12", "street_21", "hero_back", "hero_side"])
		for t in InteriorData.TYPES:
			_spots.append("int_%s" % t)


func step(_t: float, _dt: float) -> bool:
	if _p == null:
		_p = Game.player as Player
		if _p == null:
			return false
		_hud = _p.get_tree().get_first_node_in_group(&"hud") as Hud
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
	var img := _p.get_viewport().get_texture().get_image()
	var sl := VisualQaLib.translucent_slabs(img)
	var name := _spots[_i]
	img.save_png("%s/%s.png" % [_out, name])
	print("GLITCH %s slab=%.4f rect=%s kind=%s" % [name, sl["frac"], sl["rect"], sl["kind"]])
	_i += 1
	if _i >= _spots.size():
		print("GLITCH_DONE")
		if OS.get_environment("BOT_FASTEXIT") != "":
			OS.kill(OS.get_process_id())
		return true
	_begin()
	return false


func _hold() -> void:
	_p.hp = _p.max_hp
	_p.set(&"last_hurt_time", -100.0)
	if _use_cine:
		_p.camera_rig.cine_set(_cine, 70.0)


func _begin() -> void:
	_wait = SETTLE
	_use_cine = false
	Game.state = &"play"
	if is_instance_valid(Game.enemies):
		TestMode.kill_all_enemies()
	TestMode.set_weather("CLEAR")
	TestMode.set_heat(0.0)
	if _hud != null and _hud.touch != null:
		_hud.touch.controls_on = true
		_hud.touch.set_process(true)
	var spot := _spots[_i]
	var ig := InteriorGameplay.instance
	if ig != null and ig.active and not spot.begins_with("int_"):
		ig.leave(true)
	var dn: DayNight = (Game.world as City).day_night
	dn.frozen = true
	if spot.begins_with("street_"):
		dn.set_hour(float(spot.trim_prefix("street_")))
		_p.teleport_to(Game.SPAWN)
		_p.camera_rig.reset_view(-PI * 0.5, -0.12)
	elif spot.begins_with("int_"):
		if ig != null:
			ig.leave(true)
			_p.teleport_to(Game.SPAWN)
			var doors := ig.doors_of(StringName(spot.trim_prefix("int_")), Game.SPAWN)
			if not doors.is_empty():
				ig.enter(doors[0], true)
	elif spot.begins_with("hero_"):
		dn.set_hour(12.0)
		_p.teleport_to(Game.SPAWN)
		var o := _p.global_position
		var off := Vector3(0.0, 1.4, 2.4) if spot == "hero_back" else Vector3(2.4, 1.3, 0.3)
		var yaw := _p.body.global_basis.get_euler().y if _p.body != null else 0.0
		var rot := Basis(Vector3.UP, yaw)
		_cine = Transform3D(Basis.IDENTITY, o + rot * off).looking_at(o + Vector3(0, 1.0, 0), Vector3.UP)
		_use_cine = true
