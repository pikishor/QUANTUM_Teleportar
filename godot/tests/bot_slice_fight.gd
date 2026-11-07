extends RefCounted
## Scripted 90-second fight bot of the slice wave (docs/shots/slice/fight_*.png): the real game from the start spot in the market, the phone HUD on, the encounter director ON with its
## opening script (a quiet walk, a radio callout, a patrol, three escalating waves, then calm), and a hero who plays it like a player: he jogs a short loop in the first seconds, turns to
## the callout, shoots whoever he sees (aim assist level error), reloads, and keeps the street. The bot prints one line per second of game time and saves a frame every FRAME_EVERY
## game seconds (more often while a wave is on: BURST_EVERY).
##   FIGHT_OUT=<dir> FIGHT_SECONDS=90 BOT_RES=1600x720 QUALITY=0 ENGINE_ARGS="--fixed-fps 12" BOT_TIMEOUT=900 tools/bot.sh res://tests/bot_slice_fight.gd /tmp/x 100000 1
## Frames are written by this bot (Dev only saves its own sequence), as <dir>/f_<game second *10>.png.

const FightBot := preload("res://tests/fight_bot.gd")
const FRAME_EVERY := 3.0
const BURST_EVERY := 1.0

var _out := ""
var _secs := 90.0
var _p: Player
var _bot: FightBot
var _t := 0.0
var _last_frame := -100.0
var _last_log := -100.0
var _setup_done := false
var _hud: Hud
var _done := false
var _saving := false
var _shots := 0
var _lined := false
var _turn_t := -10.0


func _init() -> void:
	_out = OS.get_environment("FIGHT_OUT")
	if OS.get_environment("FIGHT_SECONDS") != "":
		_secs = float(OS.get_environment("FIGHT_SECONDS"))


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	var tree := Engine.get_main_loop() as SceneTree
	for n in tree.root.find_children("*", "AutoQuality", true, false):
		(n as AutoQuality).enabled = false
	for n in tree.root.find_children("*", "Stability", true, false):
		n.set_process(false)
	_hud = tree.get_first_node_in_group(&"hud") as Hud
	if _hud != null:
		if _hud.settings.path == UiSettings.DEFAULT_PATH:
			_hud.settings = UiSettings.new("user://bot_fight.cfg")
		_hud.touch.controls_on = true
	DirAccess.make_dir_recursive_absolute(_out)
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	for id: StringName in WeaponDefs.IDS:
		WeaponDefs.unlock(id)
	var w := OS.get_environment("BOT_WEAPON")
	_p.weapon.switch_to(StringName(w) if w != "" else &"carbine", true)
	var m := Game.missions
	if m != null:
		m.contracts.enabled = false
	if Game.story != null:
		(Game.story as Story).skip_cards()
	TestMode.set_weather("CLEAR")
	Game.civilian_casualties = false                  # the bot's rounds pass through bystanders: a fight picture, not a wanted-level run
	var enc := Encounters.current
	enc.enabled = OS.get_environment("FIGHT_LINE") == ""
	enc.reset()
	_bot = FightBot.new()
	_bot.setup(_p)
	_bot.aim_error = 0.01
	Game.state = &"play"


## FIGHT_LINE=1: no director; troopers stand in a staggered line 8-32 m ahead (unaware, frozen in place) for close looks at readability at distance.
func _line_up() -> void:
	var mgr := Game.enemies as EnemyManager
	mgr.clear()
	var fwd := -_p.camera_rig.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var dists := [7.0, 11.0, 15.0, 20.0, 26.0, 33.0]
	for i in dists.size():
		var pos: Vector3 = _p.global_position + fwd * float(dists[i]) + right * (3.5 if i % 2 == 0 else -3.5)
		var d := mgr.spawn(&"operative", pos, false, false)
		if d != null:
			d.yaw = atan2(-(_p.global_position.x - pos.x), -(_p.global_position.z - pos.z))
			d.set_physics_process(false)


func step(_unused: float, delta: float) -> bool:
	if _done:
		return true
	if Game.player == null or Game.enemies == null or Game.missions == null:
		return false
	if not _setup_done:
		_setup()
	if _saving:
		return false
	_t += delta
	Game.state = &"play"
	if OS.get_environment("FIGHT_LINE") != "":
		_p.invuln = 5.0
		if not _lined:
			_lined = true
			_line_up()
		if OS.get_environment("FIGHT_LINE") == "tracer":
			var cam := _p.camera_rig.camera
			var cp := cam.global_position
			var f := -cam.global_basis.z
			var r := cam.global_basis.x
			FX.tracer(cp + r * 3.0 - Vector3(0.0, 0.8, 0.0) + f * 6.0, cp - r * 1.0 - Vector3(0.0, 0.9, 0.0) + f * 0.8, Color(1.0, 0.25, 0.2))
			FX.tracer(_p.global_position + Vector3(0.4, 1.5, 0.0), _p.global_position + f * 25.0 + Vector3(0.0, 1.4, 0.0), Color(1.0, 0.93, 0.6))
		if _t - _last_frame >= 1.0 and not _saving:
			_last_frame = _t
			_save_frame()
		if _t >= _secs:
			_done = true
			if OS.get_environment("BOT_FASTEXIT") != "":
				OS.kill(OS.get_process_id())
			return true
		return false
	var enc := Encounters.current
	_p.invuln = 5.0
	if is_instance_valid(Game.story):
		(Game.story as Story).skip_cards()
	_bot.step(delta)
	if _bot.target == null and not enc.squad.is_empty():       # a player turns to the arrow on the edge of the screen
		var near: Drone = null
		var bd := 1.0e9
		for d in enc.squad:
			if is_instance_valid(d) and d.active and not d.dead and d.global_position.distance_to(_p.global_position) < bd:
				bd = d.global_position.distance_to(_p.global_position)
				near = d
		if near != null and _t - _turn_t > 1.5:
			_turn_t = _t
			_p.camera_rig.aim_at(near.center())
	var mgr := Game.enemies as EnemyManager
	if _t - _last_log >= 1.0:
		_last_log = _t
		print("FIGHT t=%.0f heat=%.1f enc=%s alive=%d shots=%d hits=%d kills=%d" % [_t, Game.heat, enc.stats(), mgr.alive_count(), _bot.shots, _bot.hits, _bot.kills])
	var every := BURST_EVERY if enc.state == &"wave" else FRAME_EVERY
	if _t - _last_frame >= every:
		_last_frame = _t
		_save_frame()
	if _t >= _secs:
		_bot.finish()
		print("FIGHT_DONE kills=%d shots=%d hits=%d %s" % [_bot.kills, _bot.shots, _bot.hits, enc.stats()])
		_done = true
		if OS.get_environment("BOT_FASTEXIT") != "":
			OS.kill(OS.get_process_id())
		return true
	return false


func _save_frame() -> void:
	_saving = true
	await RenderingServer.frame_post_draw
	var img := _p.get_viewport().get_texture().get_image()
	img.save_png("%s/f_%04d.png" % [_out, int(_t * 10.0)])
	_shots += 1
	_saving = false
