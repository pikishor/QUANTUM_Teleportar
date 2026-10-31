extends RefCounted
## Visual bot of the HUD module: the real game (scenes/main.tscn) driven through its screens.
##   tools/bot.sh res://tests/bot_hud.gd <out_prefix> 20 6        (every 20 frames, 6 pictures; RENDERER=compat works)
## Phases: 0 title menu  1 play HUD (minimap, heat, message, hurt flash)  2 pause  3 DECOHERED  4 SECTOR STABILIZED  5 touch HUD on a phone layout

var _every := 20
var _phase := -1


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1 and kv[0] == "every":
			_every = maxi(10, int(kv[1]))


func step(_t: float, _delta: float) -> bool:
	var hud := Game.get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null or Game.player == null:
		return false
	if hud.settings.path == UiSettings.DEFAULT_PATH:
		hud.settings = UiSettings.new("user://bot_hud.cfg")      # never touch the real settings or best score
	var f: int = Dev.get(&"_frame")
	var slot := (f - 1) / _every
	var k := ((f - 1) % _every) + 1
	if slot != _phase:
		_phase = slot
		match slot:
			0:
				Game.state = &"menu"
			1:
				Game.state = &"play"
				Game.score = 1250
				Game.heat = 3.4
				Game.say("TELEPORTED  -  ALICE BITS 01 > BOB APPLIES X", 60.0)
				Game.player.set(&"hp", 62.0)
				Game.player.set(&"energy", 64.0)
				if is_instance_valid(Game.enemies):
					for i in 3:
						Game.enemies.call(&"spawn", &"sentinel", Game.player.global_position + Vector3(14.0 + i * 11.0, 0.0, -18.0 + i * 13.0), true)
			2:
				Game.state = &"paused"
			3:
				Game.state = &"dead"
			4:
				Game.state = &"win"
			5:
				Game.state = &"play"
				hud.touch.controls_on = true
				hud.touch.perf_on = true
				hud.touch.set_process(true)
	if _phase == 1 or _phase == 5:
		Game.heat = 3.4
	if _phase == 1 and k > _every - 4 and is_instance_valid(Game.player):
		Game.player.set(&"last_hurt_time", PlayerUtil.now())
		Game.player.set(&"last_hurt_from", Game.player.global_position + Vector3(8.0, 0.0, 8.0))
	return false
