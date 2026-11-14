extends RefCounted
## DEV BOT of the wave 114 play critic: the crate reveal over the real game, with a fight on (RV_FIGHT=1: an alerted enemy 18 m ahead) or in a quiet street (RV_FIGHT=0), frames every 6 steps.
##   RV_FIGHT=1 BOT_RES=1688x780 QUALITY=0 BOT_USER_ARGS="--touch" ENGINE_ARGS="--fixed-fps 12" tools/bot.sh res://tests/bot_w114_reveal.gd /tmp/x/f 6 6

var _setup_done := false
var _p: Player
var _t := 0.0


func step(_t0: float, delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.missions == null:
		return false
	var f: int = Dev.get(&"_frame")
	if not _setup_done:
		_setup_done = true
		_p = Game.player as Player
		var mgr := Game.enemies as EnemyManager
		mgr.patrol_groups().clear()
		mgr.clear()
		WeaponDefs.hero_mode = true
		Game.missions.contracts.enabled = false
		Encounters.current.enabled = false
		_p.max_hp = 1.0e6
		_p.hp = _p.max_hp
		_p.invuln = 1.0e5
		TestMode.god = true
		_p.weapon.switch_to(&"a_pillar", true)
		if OS.get_environment("RV_FIGHT") == "1":
			var fwd := -_p.camera_rig.camera.global_basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			var pos := _p.global_position + fwd * 18.0
			for k in 3:
				var d := mgr.spawn(&"operative", pos + fwd.cross(Vector3.UP) * (float(k) - 1.0) * 3.0, true)
				if d != null:
					d.set_physics_process(false)
					d.global_position = pos + fwd.cross(Vector3.UP) * (float(k) - 1.0) * 3.0
					d.max_hp = 1.0e6
					d.hp = 1.0e6
					d.aware = true
		return false
	Game.state = &"play"
	_t += delta
	if f == 4:
		CrateReveal._quiet = 0
		CrateReveal.enabled = true
		CrateReveal.request(&"railgun", "CRATE OPENED", true)
		print("RVBOT reveal compact=", CrateReveal.current.compact if CrateReveal.current != null else "none")
	return f >= 40
