extends RefCounted
## Visual bot of the combat-feel wave: the real game from the start spot, the encounter director ON (first squad after a short countdown), a fight bot that shoots whoever comes, and
## a frame sequence of the whole thing: squads arriving, tracers, muzzle flash, hits, deaths, civilians in the street.
##   BOT_RES=844x390 BOT_WEAPON=scatter BOT_CIV=1 tools/bot.sh res://tests/bot_combat_feel.gd /tmp/out/f 4 24
## BOT_WEAPON picks the weapon in hand (default carbine), BOT_CIV=1 stages a citizen in front of the hero and shoots it, BOT_FIRST=n the director's first-contact countdown in seconds.

const FightBot := preload("res://tests/fight_bot.gd")

var _bot: FightBot
var _setup_done := false
var _p: Player
var _every := 4
var _count := 24
var _civ := -1
var _civ_mode := false
var _civ_t := 0.0


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
	for id: StringName in WeaponDefs.IDS:
		WeaponDefs.unlock(id)
	var w := OS.get_environment("BOT_WEAPON")
	_p.weapon.switch_to(StringName(w) if w != "" else &"carbine", true)
	var m := Game.missions
	if m != null:
		m.contracts.enabled = false
	var enc := Encounters.current
	enc.enabled = true
	enc._calm_t = float(OS.get_environment("BOT_FIRST")) if OS.get_environment("BOT_FIRST") != "" else 2.0
	_bot = FightBot.new()
	_bot.setup(_p)
	_bot.aim_error = 0.006
	_civ_mode = OS.get_environment("BOT_CIV") == "1"
	if _civ_mode:
		enc.enabled = false
		var amb: Node3D = (Game.world as City).ambient
		var crowd: RefCounted = amb.crowd
		for k in 30:
			crowd.step(0.1, _p.global_position)


func step(t: float, delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.missions == null:
		return false
	if not _setup_done:
		_setup()
	var f: int = Dev.get(&"_frame")
	Game.state = &"play"
	if _civ_mode:
		_civ_step(delta)
	else:
		_bot.step(delta)
	if f % 10 == 0 and _civ >= 0:
		var cr: RefCounted = (Game.world as City).ambient.crowd
		print("BOTCIV f=%d civ=%d alive=%s dying=%s pos=%s hero=%s shots=%d hits=%d killed=%d" % [f, _civ, cr.is_alive(_civ), cr.is_dying(_civ), cr.person_position(_civ), _p.global_position, _p.weapon.shots_fired, _p.weapon.civilian_hits, cr.killed_total])
	if f % 30 == 0:
		var enc := Encounters.current
		print("BOT f=%d enc=%s alive=%d shots=%d hits=%d kills=%d" % [f, enc.stats(), (Game.enemies as EnemyManager).alive_count(), _bot.shots, _bot.hits, _bot.kills])
	if f >= _every * _count:
		_bot.finish()
		Input.action_release(&"fire")
		return true
	return false


func _civ_step(_delta: float) -> void:
	var amb: Node3D = (Game.world as City).ambient
	var crowd: RefCounted = amb.crowd
	if _civ < 0 or not crowd.is_alive(_civ) or crowd.person_position(_civ).distance_to(_p.global_position) > 14.0:
		_civ = -1
		for i in crowd.count:                                  # stand somebody in the street 7 m ahead of the hero (the sidewalk line is replaced for the picture)
			if crowd.is_alive(i):
				_civ = i
				break
		if _civ < 0:
			return
		var fwd := -_p.camera_rig.camera.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var at := _p.global_position + fwd * 7.0 + Vector3(0.0, 0.0, 0.0)
		crowd._axis[_civ] = 0
		crowd._lat[_civ] = at.z
		crowd._off[_civ] = 0.0
		crowd._u[_civ] = at.x
		crowd._dir[_civ] = 1.0 if fwd.x < 0.0 else -1.0
		crowd._idle[_civ] = 60.0
		crowd._flee[_civ] = 0.0
		crowd._hp[_civ] = 28.0
	_p.invuln = 5.0
	_p.camera_rig.aim_at(crowd.person_position(_civ) + Vector3(0.0, 1.1, 0.0))
	Input.action_press(&"fire")
