extends RefCounted
## Weapons in the live game: for every weapon the hero stands at the market spawn and holds it; three shots each: `game` (the real over-the-shoulder camera, hip), `aim` (the real camera
## while aiming: ADS, the muzzle flash and the HUD weapon plate) and `three` (a close 3/4 view from the front right, lit by the street). Saves PNGs, prints draws and triangles.
##   WH_OUT=<dir> [WH_WEAPONS=a,b] [WH_VIEWS=game,aim,three] BOT_RES=1200x540 QUALITY=0 tools/bot.sh res://tests/bot_weapon_hold.gd /tmp/x 1000 1
const SETTLE := 45
var _weapons: Array[StringName] = []
var _views: PackedStringArray = PackedStringArray(["game", "aim", "three"])
var _i := 0
var _v := 0
var _wait := 0
var _p: Player
var _out := ""


func _init() -> void:
	_out = OS.get_environment("WH_OUT")
	var s := OS.get_environment("WH_WEAPONS")
	for n in (s.split(",", false) if s != "" else PackedStringArray()):
		_weapons.append(StringName(n))
	if _weapons.is_empty():
		for id: StringName in WeaponDefs.IDS:
			_weapons.append(id)
	var v := OS.get_environment("WH_VIEWS")
	if v != "":
		_views = v.split(",", false)


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
		for id: StringName in WeaponDefs.IDS:
			WeaponDefs.unlock(id)
		DirAccess.make_dir_recursive_absolute(_out)
		_begin()
	_p.hp = _p.max_hp
	if _views[_v] == "three":
		var o := _p.global_position
		var cam := Transform3D(Basis.IDENTITY, o + Vector3(1.5, 1.45, -1.5).rotated(Vector3.UP, _p.rotation.y)).looking_at(o + Vector3(0.0, 1.25, 0.0), Vector3.UP)
		_p.camera_rig.cine_set(cam, 55.0)
	if _wait > 0:
		_wait -= 1
		return false
	var img := _p.get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%s.png" % [_out, _weapons[_i], _views[_v]])
	print("WH %s %s draws %d prims %d" % [_weapons[_i], _views[_v], RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	_v += 1
	if _v >= _views.size():
		_v = 0
		_i += 1
	if _i >= _weapons.size():
		Input.action_release(&"aim")
		print("WH_DONE")
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
	TestMode.set_weather("CLEAR")
	TestMode.set_heat(0.0)
	_p.teleport_to(Game.SPAWN + Vector3(0.0, 0.1, 0.0))
	_p.camera_rig.reset_view(-1.5708, -0.05)
	_p.weapon.switch_to(_weapons[_i], true)
	var aim := _views[_v] == "aim"
	if aim:
		Input.action_press(&"aim")
	else:
		Input.action_release(&"aim")
