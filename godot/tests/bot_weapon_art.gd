extends RefCounted
## Look-dev bot of the weapon kit (wave 114): the real game and the real camera, the hero with one weapon (BOT_WEAPON, default carbine) in a timeline of frames: idle, aim, a burst of shots, the empty gun,
## reload. Used for the in-hand firing / reload frames of docs/shots/round6.
##   BOT_RES=1600x720 BOT_WEAPON=a_pillar ENGINE_ARGS="--fixed-fps 12" tools/bot.sh res://tests/bot_weapon_art.gd /tmp/out/f 6 12
## The timeline (game seconds at 12 fps with --every 6 = one picture per half second): 0-1 idle, 1-2 aim, 2-3.5 trigger held (a burst), 3.5 release, 4 reload pressed.

var _every := 6
var _count := 12
var _setup_done := false
var _p: Player
var _t := 0.0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			if kv[0] == "every":
				_every = maxi(1, int(kv[1]))
			elif kv[0] == "count":
				_count = maxi(1, int(kv[1]))


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	WeaponDefs.hero_mode = true
	var m := Game.missions
	if m != null:
		m.contracts.enabled = false
	Encounters.current.enabled = false
	var w := OS.get_environment("BOT_WEAPON")
	_p.weapon.switch_to(StringName(w) if w != "" else &"carbine", true)
	_p.max_hp = 1.0e6
	_p.hp = _p.max_hp
	_p.invuln = 600.0


func step(_t: float, delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.missions == null:
		return false
	if not _setup_done:
		_setup()
	Game.state = &"play"
	_t += delta
	var f: int = Dev.get(&"_frame")
	if _t > 1.0 and _t < 3.6:
		Input.action_press(&"aim")
	else:
		Input.action_release(&"aim")
	if _t > 2.0 and _t < 3.5:
		Input.action_press(&"fire")
	else:
		Input.action_release(&"fire")
	if _t > 4.0 and _t < 4.2:
		Input.action_press(&"reload")
	else:
		Input.action_release(&"reload")
	if f >= _every * _count:
		Input.action_release(&"fire")
		Input.action_release(&"aim")
		return true
	return false
