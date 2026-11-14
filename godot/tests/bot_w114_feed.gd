extends RefCounted
## DEV BOT of the wave 114 play critic: the play HUD at phone aspect with a busy kill / pickup feed (four lines with weapon pictures), the objective line and a toast; frames at step 8 and 14.
##   BOT_RES=1688x780 QUALITY=0 BOT_USER_ARGS="--touch" ENGINE_ARGS="--fixed-fps 12" tools/bot.sh res://tests/bot_w114_feed.gd /tmp/x/f 8 2

var _setup_done := false
var _p: Player


func step(_t0: float, _delta: float) -> bool:
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
		Game.heat = 0.0
		return false
	Game.state = &"play"
	if f == 3:
		var hud := (Engine.get_main_loop() as SceneTree).get_first_node_in_group(&"hud") as Hud
		var now := PlayerUtil.now()
		hud.feed.clear()
		hud.feed.push(HudFeed.KILL, "OPERATIVE  RIFT CARBINE", now + 9.0, &"a_pillar")
		hud.feed.push(HudFeed.KILL, "BRUTE  SHARD SCATTER", now + 9.0, &"scatter")
		hud.feed.push(HudFeed.PICKUP, "NEW WEAPON  TWIN RIVET SMG", now + 9.0, &"s_rivet")
		hud.feed.push(HudFeed.KILL, "VAEL RAIDER  ION BATTLE RIFLE", now + 9.0, &"e_ioncarb")
		Game.say("HIJACK COMPACT", 30.0)
	return f >= 18
