extends RefCounted
## Visual bot of the combat-depth wave: one picture per weapon in use (carbine, scatter, lance charged, grenade well), the shield trooper under fire and the Overseer boss fight
## through the real boss contract (HUD boss bar included).
##   tools/bot.sh res://tests/bot_combat2.gd <out_prefix> 45 6        (every 45 frames, 6 pictures: phases 0-5)
##   RENDERER=compat BOT_PHASES=2,5 tools/bot.sh ... 45 2             (only these phases, in this order; the count must match)
## Phases: 0 carbine  1 scatter  2 lance (held at full charge)  3 grenade (the well opening)  4 shield trooper  5 Overseer contract

const Fixture := preload("res://tests/player_fixture.gd")

const NAMES: Array[String] = ["carbine", "scatter", "lance", "grenade", "shield", "boss"]
const SCALES := [0.3, 0.3, 0.3, 0.7, 0.3, 0.3]

var _every := 45
var _count := 6
var _phase := -1
var _setup_done := false
var _p: Player
var _mgr: EnemyManager
var _order: Array[int] = []
var _group: Array[Drone] = []
var _froze := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			if kv[0] == "every":
				_every = maxi(30, int(kv[1]))
			elif kv[0] == "count":
				_count = maxi(1, int(kv[1]))
	for part in OS.get_environment("BOT_PHASES").split(",", false):
		_order.append(int(part))


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	_mgr = Game.enemies as EnemyManager
	_p.max_hp = 1.0e6
	_mgr.patrol_groups().clear()
	for id: StringName in WeaponDefs.IDS:
		WeaponDefs.unlock(id)
	var m := Game.missions
	if m != null:
		m.contracts.enabled = false


func _reset_player() -> void:
	Fixture.release_inputs()
	Game.state = &"play"
	_p.invuln = 0.0
	_p.hp = _p.max_hp
	_p.energy = _p.max_energy
	_p.weapon.reset()
	_p.teleport_to(Game.SPAWN)
	_p.camera_rig.reset_view(-PI * 0.5, -0.1)
	_p.yaw = -PI * 0.5
	Game.heat = 0.0


func _stage(offsets: Array, types: Array, aware: bool) -> void:
	_mgr.clear()
	_group.clear()
	for i in offsets.size():
		var d := _mgr.spawn(types[i], Game.SPAWN + (offsets[i] as Vector3), aware)
		if d != null:
			_group.append(d)


func _enter(phase: int) -> void:
	Fixture.release_inputs()
	Engine.time_scale = float(SCALES[phase % SCALES.size()])
	var contracts: Contracts = Game.missions.contracts
	if contracts.state != &"idle":
		contracts._cleanup(true)
		contracts.state = &"idle"
	_reset_player()
	match phase:
		0:
			_p.weapon.switch_to(&"carbine", true)
			_stage([Vector3(14.0, 0.0, -2.0), Vector3(20.0, 0.0, 3.0)], [&"operative", &"operative"], true)
		1:
			_p.weapon.switch_to(&"scatter", true)
			_stage([Vector3(6.5, 0.0, 0.0), Vector3(9.0, 0.0, 3.0)], [&"operative", &"flanker"], true)
		2:
			_p.weapon.switch_to(&"lance", true)
			_stage([Vector3(22.0, 0.0, 0.0), Vector3(32.0, 0.0, 1.0)], [&"heavy", &"operative"], false)
		3:
			_p.weapon.switch_to(&"grenade", true)
			_stage([Vector3(16.0, 0.0, 2.0), Vector3(18.0, 0.0, -3.0), Vector3(19.0, 0.0, 5.0)], [&"operative", &"operative", &"sentinel"], true)
		4:
			_p.weapon.switch_to(&"carbine", true)
			_stage([Vector3(11.0, 0.0, 0.0), Vector3(17.0, 0.0, 4.0)], [&"shield", &"operative"], true)
		5:
			_p.weapon.switch_to(&"lance", true)
			Game.missions.contracts.offer(&"boss", Game.SPAWN + Vector3(30.0, 0.0, 0.0))
			_p.teleport_to(Game.SPAWN + Vector3(29.0, 0.05, 1.0))
			Game.missions.contracts.tick(0.1)
			_p.camera_rig.reset_view(-PI * 0.5, -0.1)


func _aim(d: Drone, fire: bool) -> void:
	if not is_instance_valid(d) or d.dead or not d.active:
		Input.action_release(&"fire")
		return
	_p.camera_rig.aim_at(d.center())
	if fire:
		Input.action_press(&"fire")


func _run(phase: int, k: int) -> void:
	_p.invuln = 5.0
	Engine.time_scale = float(SCALES[phase % SCALES.size()])        # the tool resets the scale every frame: set it every frame
	match phase:
		0, 1:
			if not _group.is_empty():
				_aim(_group[0], true)
		4:
			if not _group.is_empty():                           # a few rounds into the shield (it flashes), then hold: the picture shows the plate up
				_aim(_group[0], k > 10 and k < 16)
				if k >= 16:
					Input.action_release(&"fire")
					_group[0].set(&"shield_hp", 150.0)
		2:
			if not _group.is_empty():
				_aim(_group[0], true)
			if k == 2:
				_p.weapon.charge = 0.9                           # hold at full charge for the picture
		3:
			if not _group.is_empty():
				_p.camera_rig.aim_at(_group[0].center() + Vector3(-2.0, -1.2, 0.0))
			if k == _every - 12:
				Input.action_press(&"fire")             # thrown late: the picture (last frame) catches the well opening
			elif k == _every - 8:
				Input.action_release(&"fire")
		5:
			var c: Contracts = Game.missions.contracts
			if k == 3 and is_instance_valid(c.target):
				(c.target as Drone).global_position = _p.global_position + Vector3(22.0, 0.0, -1.0)      # the contract spawns him 70-110 m away: bring him into the street for the picture
				(c.target as Drone).aware = true
			if is_instance_valid(c.target):
				var boss := c.target as Overseer
				_p.camera_rig.aim_at(boss.center())
				for s in boss.summoned.duplicate():                 # no strikers bursting at the lens: the picture is about the boss
					if is_instance_valid(s) and s.type == &"striker":
						_mgr.release(s)


func step(_t: float, _delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.missions == null:
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
		print("BOT phase %d %s (frame %d)" % [phase, NAMES[phase % NAMES.size()], f])
	_run(phase, k)
	if k == _every - 1:
		var alive := 0
		for d in _mgr.list:
			alive += 1 if not d.dead else 0
		print("BOT phase %d: staged %d, %d enemies alive, weapon %s %d/%d, charge %.2f, wells %d, draw calls %d, primitives %d" % [phase, _group.size(), alive, _p.weapon.current, _p.weapon.ammo, _p.weapon.mag,
				_p.weapon.charge, _p.weapon.well_positions().size(),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	if f >= _every * _count:
		Fixture.release_inputs()
		Engine.time_scale = 1.0
		return true
	return false
