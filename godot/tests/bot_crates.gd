extends RefCounted
## Visual bot: the weapon crates in the street. CR_OUT=<dir> [CR_CRATES=0,3] BOT_RES=1200x540 QUALITY=0 tools/bot.sh res://tests/bot_crates.gd /tmp/x 1000 1
## Each crate from the game camera, 11 m away on the road, looking at it (and one frame after it is opened).
const SETTLE := 40
var _list: Array[int] = []
var _i := 0
var _wait := 0
var _p: Player
var _out := ""


func _init() -> void:
	_out = OS.get_environment("CR_OUT")
	var s := OS.get_environment("CR_CRATES")
	for n in (s.split(",", false) if s != "" else PackedStringArray(["0", "1", "2", "3"])):
		_list.append(int(n))


func step(_t: float, _dt: float) -> bool:
	if _p == null:
		_p = Game.player as Player
		if _p == null:
			return false
		for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
			(n as AutoQuality).enabled = false
		_p.max_hp = 1.0e6
		DirAccess.make_dir_recursive_absolute(_out)
		_begin()
	_p.hp = _p.max_hp
	var cp := WeaponLadder.crate_pos(_list[_i])
	_p.camera_rig.cine_set(Transform3D(Basis.IDENTITY, cp + Vector3(2.6, 1.7, 3.4)).looking_at(cp + Vector3(0.0, 0.4, 0.0), Vector3.UP), 60.0)
	if _wait > 0:
		_wait -= 1
		return false
	_p.get_viewport().get_texture().get_image().save_png("%s/crate_%d.png" % [_out, _list[_i]])
	print("CR crate %d at %s" % [_list[_i], WeaponLadder.crate_pos(_list[_i])])
	_i += 1
	if _i >= _list.size():
		print("CR_DONE")
		if OS.get_environment("BOT_FASTEXIT") != "":
			OS.kill(OS.get_process_id())
		return true
	_begin()
	return false


func _begin() -> void:
	_wait = SETTLE
	Game.state = &"play"
	if is_instance_valid(Game.enemies):
		TestMode.kill_all_enemies()
	var cp := WeaponLadder.crate_pos(_list[_i])
	var from := cp + Vector3(-3.0, 0.1, 6.0)
	_p.teleport_to(from)
	_p.camera_rig.reset_view(0.0, -0.08)
