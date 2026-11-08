extends RefCounted
## Scripted 90-second REAL FIGHT bot (real-fight wave, docs/shots/slice/real_fight_*.jpg): the real game from the start spot in the market, the phone HUD on, the encounter director ON
## (contact in about 10 s, three waves of 3-6 troopers with distinct roles, a breather), and a hero who plays like a player (tests/real_fight_bot.gd): he strafes while he fires, backs
## off from a rusher, drops a target that ducks behind a car, walks towards the fight and turns to the threat arrows. One log line every LOG_EVERY game seconds, a frame every FRAME_EVERY
## game seconds (BURST_EVERY while a wave is on) and one 0.5 s after each kill (the death effect), FIGHT_KILLS=0 turns those off.
##   FIGHT_OUT=<dir> FIGHT_SECONDS=90 BOT_RES=1200x540 QUALITY=0 ENGINE_ARGS="--fixed-fps 12" BOT_USER_ARGS="--touch" BOT_FASTEXIT=1 BOT_TIMEOUT=560 tools/bot.sh res://tests/bot_real_fight.gd /tmp/x 100000 1
## Frames are written by this bot (Dev only saves its own sequence), as <dir>/f_<game second *10>.png (k_<..>.png for the kill frames).

const RealFightBot := preload("res://tests/real_fight_bot.gd")
const FRAME_EVERY := 3.0
const BURST_EVERY := 1.0
const LOG_EVERY := 2.0
const KILL_DELAY := 0.5

var _out := ""
var _secs := 90.0
var _p: Player
var _bot: RealFightBot
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
var _kill_at := -10.0
var _kills_seen := 0
var _min_d := 1.0e9


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
	enc.enabled = OS.get_environment("FIGHT_LINE") == "" and OS.get_environment("FIGHT_CLOSE") == ""
	enc.reset()
	_bot = RealFightBot.new()
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
		var d := mgr.spawn(&"operative", pos, OS.get_environment("FIGHT_LINE") == "aware", false, &"", i)
		if d != null:
			d.yaw = atan2(-(_p.global_position.x - pos.x), -(_p.global_position.z - pos.z))
			d.set_physics_process(false)


## FIGHT_CLOSE=1: no director; three aware troopers (rifleman, scout, grenadier) 9-14 m ahead, normal AI, a frame every CLOSE_EVERY s: hit reactions, deaths and the grenade up close.
func _close_up() -> void:
	var mgr := Game.enemies as EnemyManager
	mgr.clear()
	var fwd := -_p.camera_rig.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var spots := [[11.0, -3.0, 0], [14.0, 4.0, 2], [18.0, -1.0, 3]]
	for sp in spots:
		var pos: Vector3 = _p.global_position + fwd * float(sp[0]) + right * float(sp[1])
		var d := mgr.spawn(&"operative", pos, true, true, &"", int(sp[2]))
		if d != null:
			(d as Operative).set_squad_role(&"anchor" if int(sp[2]) == 3 else &"pusher", 1.0)


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
	if OS.get_environment("FIGHT_CLOSE") != "" and not _lined:
		_lined = true
		_close_up()
	if is_instance_valid(Game.story):
		(Game.story as Story).skip_cards()
	_bot.step(delta)
	var mgr := Game.enemies as EnemyManager
	for e in mgr.list:
		if e.active and not e.dead and e.aware:
			_min_d = minf(_min_d, e.global_position.distance_to(_p.global_position))
	if _bot.kills > _kills_seen:
		_kills_seen = _bot.kills
		if _kill_at < 0.0 and OS.get_environment("FIGHT_KILLS") != "0":
			_kill_at = _t + KILL_DELAY
	if _t - _last_log >= LOG_EVERY:
		_last_log = _t
		var nearest := 1.0e9
		var aware_n := 0
		for e in mgr.list:
			if e.active and not e.dead and e.aware:
				aware_n += 1
				nearest = minf(nearest, e.global_position.distance_to(_p.global_position))
		print("FIGHT t=%.0f ph=%s w=%d alive=%d aware=%d near=%.0f min=%.0f moved=%.0f strafes=%d back=%d adv=%d fwm=%d shots=%d hits=%d kills=%d gren=%d" % [_t, enc.phase, enc.wave, mgr.alive_count(), aware_n,
				nearest if nearest < 1.0e8 else -1.0, _min_d if _min_d < 1.0e8 else -1.0, _bot.moved, _bot.strafes, _bot.back_steps, _bot.advance_steps, _bot.fire_while_moving, _bot.shots, _bot.hits, _bot.kills, int(mgr.get("grenades_thrown") if mgr.get("grenades_thrown") != null else 0)])
	if _kill_at >= 0.0 and _t >= _kill_at and not _saving:
		_kill_at = -10.0
		_save_frame("k")
	var every := BURST_EVERY if enc.state == &"wave" else FRAME_EVERY
	if OS.get_environment("FIGHT_CLOSE") != "":
		every = 0.4
	if _t - _last_frame >= every:
		_last_frame = _t
		_save_frame()
	if _t >= _secs:
		_bot.finish()
		print("FIGHT_DONE kills=%d shots=%d hits=%d moved=%.0f strafes=%d min_d=%.0f %s" % [_bot.kills, _bot.shots, _bot.hits, _bot.moved, _bot.strafes, _min_d, enc.stats()])
		_done = true
		if OS.get_environment("BOT_FASTEXIT") != "":
			OS.kill(OS.get_process_id())
		return true
	return false


func _save_frame(prefix := "f") -> void:
	_saving = true
	await RenderingServer.frame_post_draw
	var img := _p.get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%04d.png" % [_out, prefix, int(_t * 10.0)])
	_shots += 1
	_saving = false
