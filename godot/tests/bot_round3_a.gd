extends RefCounted
## Director round 3, gameplay half (tests/test_director_round3_a.gd): frames of the hack pad, of a car driven into a wall with the throttle held (the wedge and the way out) and of
## the hero's stance while he fires.  R3_SET=hack|car|stance  R3_OUT=<dir>  R3_SECONDS=14
##   R3_OUT=/tmp/r3 R3_SET=hack BOT_RES=2400x1080 QUALITY=0 ENGINE_ARGS="--fixed-fps 12" BOT_USER_ARGS="--touch" BOT_TIMEOUT=500 BOT_FASTEXIT=1 tools/bot.sh res://tests/bot_round3_a.gd /tmp/x 100000 1

var _out := ""
var _set := "hack"
var _secs := 14.0
var _p: Player
var _t := 0.0
var _last_frame := -100.0
var _last_log := -100.0
var _setup_done := false
var _saving := false
var _car: Vehicle
var _hp_prev := 0.0


func _init() -> void:
	_out = OS.get_environment("R3_OUT")
	_set = OS.get_environment("R3_SET") if OS.get_environment("R3_SET") != "" else "hack"
	if OS.get_environment("R3_SECONDS") != "":
		_secs = float(OS.get_environment("R3_SECONDS"))


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	var tree := Engine.get_main_loop() as SceneTree
	for n in tree.root.find_children("*", "AutoQuality", true, false):
		(n as AutoQuality).enabled = false
	for n in tree.root.find_children("*", "Stability", true, false):
		n.set_process(false)
	var hud := tree.get_first_node_in_group(&"hud") as Hud
	if hud != null:
		if hud.settings.path == UiSettings.DEFAULT_PATH:
			hud.settings = UiSettings.new("user://bot_r3a.cfg")
		hud.touch.controls_on = true
	DirAccess.make_dir_recursive_absolute(_out)
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	Encounters.current.enabled = false
	if Game.story != null:
		(Game.story as Story).skip_cards()
	TestMode.set_weather("CLEAR")
	var m := Game.missions
	if m != null:
		m.contracts.enabled = false
	Game.state = &"play"
	_p.max_hp = 1000.0
	_p.hp = 1000.0
	if _set == "hack":
		var fwd := -_p.camera_rig.camera.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var at := _p.global_position + fwd * 13.0
		m.campaign.enabled = true
		m.campaign.start_custom({"id": "r3bot", "clears_sector": false, "steps": [{"kind": "hack", "pos": [at.x, at.z], "hold": 40.0, "radius": 9.0, "obj": "Hack the ledger node"}, {"kind": "reach", "pos": [-200.0, 0.0], "obj": "Go on"}]})
	elif _set == "car":
		var vm := Game.vehicles as VehicleManager
		_car = vm.starter
		if _car != null:
			vm.enter(_car)
			Input.action_press(&"move_forward")


func step(_unused: float, delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.missions == null:
		return false
	if not _setup_done:
		_setup()
	if _saving:
		return false
	_t += delta
	Game.state = &"play"
	if _set == "hack":
		_p.invuln = 5.0
		Game.heat = 0.0
		if _t > 6.0 and _t < 9.0:                                        # walk into the pad
			Input.action_press(&"move_forward")
		else:
			Input.action_release(&"move_forward")
	if _set == "car" and _car != null:
		if _car.hp < _hp_prev - 3.0:
			print("R3 HULL t=%.2f -%.0f v=%.1f crashes=%d hits=%d last_impact=%.1f state=%d" % [_t, _hp_prev - _car.hp, _car.vel.length(), _car.crashes, _car.hits, _car.last_impact, _car.dmg_state])
		_hp_prev = _car.hp
	if _t - _last_log >= 1.0:
		_last_log = _t
		var line := ""
		if _set == "car" and _car != null:
			line = "hull=%.0f/%.0f v=%.1f km/h wedge=%d crashes=%d" % [_car.hp, _car.max_hp, _car.vel.length() * 3.6, _car.wedge_count, _car.crashes]
		print("R3 t=%.0f %s" % [_t, line])
	if _t - _last_frame >= 1.5:
		_last_frame = _t
		_save_frame()
	if _t >= _secs:
		Input.action_release(&"move_forward")
		if OS.get_environment("BOT_FASTEXIT") != "":
			OS.kill(OS.get_process_id())
		return true
	return false


func _save_frame() -> void:
	_saving = true
	await RenderingServer.frame_post_draw
	var img := _p.get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%04d.png" % [_out, _set, int(_t * 10.0)])
	_saving = false
