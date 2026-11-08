extends RefCounted
## Render bot of the Mission Board: the phone HUD on, the real game from the start spot; saves the frames the render-look-fix loops judge: the first job with its objective line and beacon,
## the pause menu with MISSIONS, the board, a mission of another type under way (a car, a smash, a sneak), the map with the three pins and its MISSIONS button, free roam.
##   BOARD_OUT=<dir> BOARD_ONLY=board,first BOT_RES=2400x1080 QUALITY=0 BOT_TIMEOUT=900 tools/bot.sh res://tests/bot_mission_board.gd /tmp/x 100000 1
## Every frame goes through the Hud's own button path (press_button), like a tap.

var _out := ""
var _hud: Hud
var _board: MissionBoard
var _i := 0
var _wait := 0
var _ready_done := false
var _steps: Array = []
var _only: PackedStringArray = PackedStringArray()


func _init() -> void:
	_out = OS.get_environment("BOARD_OUT")
	if OS.get_environment("BOARD_ONLY") != "":
		_only = OS.get_environment("BOARD_ONLY").split(",", false)
	_steps = [
		["first", "_s_first"],
		["pause", "_s_pause"],
		["board", "_s_board"],
		["hijack", "_s_hijack"],
		["smash", "_s_smash"],
		["sneak", "_s_sneak"],
		["patrol", "_s_patrol"],
		["map", "_s_map"],
		["freeroam", "_s_free"],
	]
	if not _only.is_empty():
		_steps = _steps.filter(func(st: Array) -> bool: return _only.has(String(st[0])))


func step(_t: float, _dt: float) -> bool:
	if not _ready_done:
		var n := Engine.get_main_loop() as SceneTree
		_hud = n.get_first_node_in_group(&"hud") as Hud
		if _hud == null or Game.player == null or Game.missions == null:
			return false
		for a in n.root.find_children("*", "AutoQuality", true, false):
			(a as AutoQuality).enabled = false
		DirAccess.make_dir_recursive_absolute(_out)
		_hud.settings = UiSettings.new("user://bot_board.cfg")
		_hud.touch.controls_on = true
		_board = (Game.missions as Missions).board
		_board.set_take_over(true)
		_board.auto_open = false
		Game.start_new_game()
		(Game.story as Story).skip_cards()
		(Game.player as Player).hp = 100.0
		_ready_done = true
		_wait = 6
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _i >= _steps.size():
		_hud.get_tree().quit()
		return true
	var name := String(_steps[_i][0])
	var phase: int = int(_ph.get(name, 0))
	if phase == 0:
		_ph[name] = 1
		call(String(_steps[_i][1]))
		_wait = 8                                              # let the renderer catch up with the new screen / state
		return false
	_hud.get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [_out, _i, name])
	print("BOARDSHOT ", name, " state ", Game.state, " board ", _board.state, " line '", _hud._camp_text, "'")
	_i += 1
	return false


var _ph := {}


func _reset_play() -> void:
	if Game.state != &"play":
		Game.state = &"play"
	if _board.is_running():
		_board.abandon()
	(Game.missions as Missions).campaign.abort()
	_board.state = &"idle"


func _start(t: StringName, first := false) -> void:
	_reset_play()
	var o := _board.build(t, (Game.player as Player).global_position, first)
	_board.accept_offer(o)
	await_ticks()


func await_ticks() -> void:
	var k := (Game.missions as Missions).campaign
	for i in 4:
		k.tick(0.5)                                             # arms and begins the first step at once (the bot's frames are slow)


func _s_first() -> void:
	_start(&"patrol", true)
	_hud._text_t = 0.0


func _s_pause() -> void:
	Game.state = &"paused"
	_hud._layout_key = ""


func _s_board() -> void:
	Game.state = &"play"
	_reset_play()
	_board.generate()
	Game.state = &"paused"
	_hud.open_board()


func _s_hijack() -> void:
	Game.state = &"play"
	_start(&"hijack")
	_hud._text_t = 0.0


func _s_smash() -> void:
	_start(&"demolition")
	_hud._text_t = 0.0


func _s_sneak() -> void:
	_start(&"stealth")
	var k := (Game.missions as Missions).campaign
	k.skip_step()                                              # the first walk is done: the guards of the sneak are up
	for i in 6:
		k.tick(0.5)
	_hud._text_t = 0.0


func _s_patrol() -> void:
	_start(&"patrol")
	_hud._text_t = 0.0


func _s_map() -> void:
	_reset_play()
	_board.generate()
	var ms := Engine.get_main_loop().root.find_child("MapScreen", true, false) as MapScreen
	if ms != null:
		ms.open()


func _s_free() -> void:
	var ms := Engine.get_main_loop().root.find_child("MapScreen", true, false) as MapScreen
	if ms != null and ms.is_open():
		ms.close_screen()
	_reset_play()
	_hud._text_t = 0.0
