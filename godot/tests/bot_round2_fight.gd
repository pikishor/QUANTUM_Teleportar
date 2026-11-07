extends RefCounted
## Round 2 fight frames (director review defect 13, tests/test_director_round2_b.gd): the real game in the market with the phone HUD on, the encounter director's first wave brought
## forward, a hero who shoots whoever he sees (aim assist level error) and is NOT invulnerable unless FIGHT_GOD=1, so the near misses, the flanks and the bursts are what the player sees.
## It prints one FIGHT line per second (hero hp, enemies alive and their roles, rounds fired / hit / near misses) and saves a frame every FRAME_EVERY game seconds.
##   FIGHT_OUT=<dir> FIGHT_SECONDS=36 BOT_RES=1600x720 QUALITY=0 ENGINE_ARGS="--fixed-fps 12" BOT_TIMEOUT=500 tools/bot.sh res://tests/bot_round2_fight.gd /tmp/x 100000 1

const FightBot := preload("res://tests/fight_bot.gd")
const FRAME_EVERY := 1.5

var _out := ""
var _secs := 36.0
var _p: Player
var _bot: FightBot
var _t := 0.0
var _last_frame := -100.0
var _last_log := -100.0
var _setup_done := false
var _done := false
var _saving := false
var _god := false
var _turn_t := -10.0


func _init() -> void:
	_out = OS.get_environment("FIGHT_OUT")
	_god = OS.get_environment("FIGHT_GOD") != ""
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
	var hud := tree.get_first_node_in_group(&"hud") as Hud
	if hud != null:
		if hud.settings.path == UiSettings.DEFAULT_PATH:
			hud.settings = UiSettings.new("user://bot_fight2.cfg")
		hud.touch.controls_on = true
	DirAccess.make_dir_recursive_absolute(_out)
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	for id: StringName in WeaponDefs.IDS:
		WeaponDefs.unlock(id)
	_p.weapon.switch_to(&"carbine", true)
	var m := Game.missions
	if m != null:
		m.contracts.enabled = false
	if Game.story != null:
		(Game.story as Story).skip_cards()
	TestMode.set_weather("CLEAR")
	Game.civilian_casualties = false
	var enc := Encounters.current
	enc.enabled = true
	enc.reset()
	enc.play_t = Encounters.FIRST_DELAY - 3.0
	_bot = FightBot.new()
	_bot.setup(_p)
	_bot.aim_error = 0.01
	Game.state = &"play"


## FIGHT_LOOKS=1: no fight, a frozen squad in two ranks in front of the hero (every trooper type, several of the plain one) for close looks at how different the enemies are.
func _line_up() -> void:
	var mgr := Game.enemies as EnemyManager
	mgr.clear()
	Encounters.current.enabled = false
	var fwd := -_p.camera_rig.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var types: Array[StringName] = [&"operative", &"operative", &"operative", &"operative", &"flanker", &"shield", &"sniper", &"operative", &"operative", &"stalker"]
	for i in types.size():
		var rank := i / 5
		var col := i % 5
		var ang := deg_to_rad(-34.0 + 17.0 * col + 8.0 * rank)
		var pos: Vector3 = _p.global_position + (fwd * cos(ang) + right * sin(ang)) * (8.0 + 4.0 * rank)
		var d := mgr.spawn(types[i], pos, false, false)
		if d != null:
			d.yaw = atan2(-(_p.global_position.x - pos.x), -(_p.global_position.z - pos.z))
			d.set_physics_process(false)
			print("LOOK ", types[i], " class=", d.humanoid.get("class", "-"), " scale=", d.humanoid.get("scale3", "-"))


## FIGHT_ROOM=<interior type> (and FIGHT_DEAD=1): the hero walks into a building while a street step runs, NOT invulnerable and not healed; a frame per second of what the plate says,
## what the room does to him and (FIGHT_DEAD=1) the dead screen with the room's job under it.
func _room_step(delta: float) -> void:
	var ig := InteriorGameplay.instance
	var m := Game.missions as Missions
	if _t < 0.5 and not InteriorGameplay.active:
		m.campaign.enabled = true
		m.campaign.start_custom({"id": "r2b", "clears_sector": false, "steps": [{"kind": "reach", "pos": [-200.0, 0.0], "obj": "Cross the trading floor to the beacon"}, {"kind": "reach", "pos": [-300.0, 0.0], "obj": "Go on"}]})
		Encounters.current.enabled = false
		Game.heat = 1.0
		print("ROOM ", ig.test_enter(StringName(OS.get_environment("FIGHT_ROOM"))))
		_p.max_hp = 100.0
		_p.hp = 100.0
		_p.invuln = InteriorGameplay.ENTRY_GRACE
	var hud := (Engine.get_main_loop() as SceneTree).get_first_node_in_group(&"hud") as Hud
	if OS.get_environment("FIGHT_DEAD") != "" and _t > _secs - 3.0 and Game.state == &"play":
		_p.invuln = 0.0
		InteriorGameplay.mercy_left = 0
		_p.damage(9999.0, _p.global_position + Vector3(0.0, 0.0, 3.0))
	if _t - _last_log >= 1.0:
		_last_log = _t
		print("ROOM t=%.0f hp=%.0f inv=%.1f pressure=%.2f mercy=%d state=%s plate='%s' hud='%s'" % [_t, _p.hp, _p.invuln, InteriorGameplay.pressure(), InteriorGameplay.mercy_left, str(Game.state), hud._campaign_line() if hud != null else "-", InteriorGameplay.hud_line])
	if _t - _last_frame >= 1.0:
		_last_frame = _t
		_save_frame()


func step(_unused: float, delta: float) -> bool:
	if _done:
		return true
	if Game.player == null or Game.enemies == null or Game.missions == null:
		return false
	if not _setup_done:
		_setup()
		if OS.get_environment("FIGHT_LOOKS") != "":
			_line_up()
	if _saving:
		return false
	_t += delta
	if OS.get_environment("FIGHT_ROOM") != "":
		if Game.state != &"dead":
			Game.state = &"play"
		_room_step(delta)
		if _t >= _secs:
			_done = true
			if OS.get_environment("BOT_FASTEXIT") != "":
				OS.kill(OS.get_process_id())
			return true
		return false
	Game.state = &"play"
	if OS.get_environment("FIGHT_LOOKS") != "":
		_p.invuln = 5.0
		if _t - _last_frame >= 1.0:
			_last_frame = _t
			_save_frame()
		if _t >= _secs:
			_done = true
			if OS.get_environment("BOT_FASTEXIT") != "":
				OS.kill(OS.get_process_id())
			return true
		return false
	var enc := Encounters.current
	if is_instance_valid(Game.story):
		(Game.story as Story).skip_cards()
	var hp := _p.hp
	_bot.step(delta)
	if not _god:
		_p.invuln = 0.0
		_p.hp = hp
		_p.max_hp = 200.0
	if _bot.target == null and not enc.squad.is_empty() and _t - _turn_t > 1.5:
		var near: Drone = null
		var bd := 1.0e9
		for d in enc.squad:
			if is_instance_valid(d) and d.active and not d.dead and d.global_position.distance_to(_p.global_position) < bd:
				bd = d.global_position.distance_to(_p.global_position)
				near = d
		if near != null:
			_turn_t = _t
			_p.camera_rig.aim_at(near.center())
	var mgr := Game.enemies as EnemyManager
	if _t - _last_log >= 1.0:
		_last_log = _t
		var roles := {}
		for e in mgr.list:
			if e.active and not e.dead:
				var k := "%s/%s" % [e.type, e.humanoid.get("class", "-")]
				roles[k] = int(roles.get(k, 0)) + 1
		var rs := Operative.round_stats
		print("FIGHT t=%.0f hp=%.0f heat=%.1f alive=%d %s enemy_rounds=%d hit=%d near=%d | hero shots=%d hits=%d kills=%d" % [_t, _p.hp, Game.heat, mgr.alive_count(), str(roles), rs["fired"], rs["hit"], rs["near"], _bot.shots, _bot.hits, _bot.kills])
	if _t - _last_frame >= FRAME_EVERY:
		_last_frame = _t
		_save_frame()
	if _t >= _secs:
		_bot.finish()
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
	_saving = false
