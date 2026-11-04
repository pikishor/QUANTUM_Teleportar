extends RefCounted
## Look-dev bot of the superhero (HeroCharacter) in the real city: the hero from the front, side and back and in close-up with a free camera, then with the game camera at MED
## and LOW, sprinting, firing, and the female / light / long-hair and buns variants. LOOK at the pictures: T-pose, floating feet, hair clipping, inverted normals, too dark.
##   tools/bot.sh res://tests/bot_superhero.gd /tmp/sh 45 11      (writes /tmp/sh_000.png ...; BOT_PHASES=0,4 selects phases)
## Phases: 0 front  1 side  2 back  3 head close-up  4 game camera MED  5 game camera LOW  6 sprint side  7 fire (3/4)  8 female light long (front)  9 female buns (back)  10 male light beard (3/4)  11 the look screen (SUIT in the pause shop, person buttons)

const Fixture := preload("res://tests/player_fixture.gd")
const NAMES: Array[String] = ["front", "side", "back", "head", "game_med", "game_low", "sprint", "fire", "female_long", "female_buns", "male_beard", "look_screen"]

var _every := 45
var _count := 12
var _phase := -1
var _setup_done := false
var _p: Player
var _cam: Camera3D
var _off := Vector3(0.0, 0.0, 3.0)       ## camera offset in the hero's frame: x right, y up, z = metres in front
var _look_h := 1.0
var _order: Array[int] = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1 and kv[0] == "count":
			_count = maxi(1, int(kv[1]))
		elif kv.size() > 1 and kv[0] == "every":
			_every = maxi(20, int(kv[1]))
	for part in OS.get_environment("BOT_PHASES").split(",", false):
		_order.append(int(part))


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	_p.max_hp = 1.0e6
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.far = 300.0
	_p.get_tree().root.add_child(_cam)
	for n in _p.get_tree().root.find_children("*", "Stability", true, false):
		n.set_process(false)
	for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
		(n as AutoQuality).enabled = false
	Game.progress.autosave_enabled = false
	Game.enemies.call(&"clear")


func _person(body: StringName, skin: StringName, hair: StringName, beard: bool) -> void:
	var h := (Game.progress as Progress).hero
	h.body = body
	h.skin_tone = skin
	h.hair = hair
	h.beard = beard
	h.changed.emit()


func _reset() -> void:
	Fixture.release_inputs()
	Game.state = &"play"
	_p.invuln = 0.0
	_p.hp = _p.max_hp
	_p.weapon.reset()
	_p.teleport_to(Game.SPAWN)
	_p.camera_rig.reset_view(-PI * 0.5, -0.05)
	_p.yaw = -PI * 0.5


func _enter(phase: int) -> void:
	_reset()
	Game.set_quality(0 if phase == 5 else 1)
	_look_h = 1.0
	_cam.make_current()
	match phase:
		0: _person(&"male", &"dark", &"parted", false); _off = Vector3(0.0, 0.3, 3.2)
		1: _off = Vector3(3.2, 0.3, 0.0)
		2: _off = Vector3(0.0, 0.3, -3.2)
		3: _off = Vector3(0.5, 0.65, 1.1); _look_h = 1.6
		4: _p.camera_rig.camera.make_current()
		5: _p.camera_rig.camera.make_current()
		6: _off = Vector3(3.4, 0.2, 0.0); Input.action_press(&"move_forward"); Input.action_press(&"sprint")
		7: _off = Vector3(2.2, 0.4, 2.4); Input.action_press(&"aim")
		8: _person(&"female", &"light", &"long", false); _off = Vector3(0.0, 0.3, 3.2)
		9: _person(&"female", &"dark", &"buns", false); _off = Vector3(0.0, 0.3, -3.2)
		10: _person(&"male", &"light", &"buzzed", true); _off = Vector3(1.8, 0.4, 2.8)
		11:
			_p.camera_rig.camera.make_current()
			var hud: Hud = null
			for n in _p.get_tree().root.find_children("*", "Hud", true, false):
				hud = n as Hud
			Game.state = &"paused"
			hud._shop_open = true
			hud.press_button(&"look_open")


func _place(phase: int) -> void:
	if phase == 4 or phase == 5:
		return
	var f := Vector3(-sin(_p.yaw), 0.0, -cos(_p.yaw))
	var r := Vector3(-f.z, 0.0, f.x)
	var tgt := _p.global_position
	_cam.global_position = tgt + r * _off.x + Vector3(0.0, _off.y + 1.0, 0.0) + f * _off.z
	_cam.look_at(tgt + Vector3(0.0, _look_h, 0.0), Vector3.UP)


func _run(phase: int, k: int) -> void:
	if phase == 7 and k > 10:
		Input.action_press(&"fire")
	_place(phase)


func step(_t: float, _dt: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.progress == null:
		return false
	if not _setup_done:
		_setup()
	var f: int = Dev.get(&"_frame")
	var slot := (f - 1) / _every
	var phase := _order[slot % _order.size()] if not _order.is_empty() else slot
	var k := ((f - 1) % _every) + 1
	if slot != _phase:
		_phase = slot
		_enter(phase)
		var b := _p.body as PlayerBody
		print("BOT phase %d %s (frame %d) tris=%s" % [phase, NAMES[phase % NAMES.size()], f, str(b.hero_info.get("tris", "old hero"))])
	_run(phase, k)
	if f >= _every * _count:
		Fixture.release_inputs()
		return true
	return false
