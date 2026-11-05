extends RefCounted
## Visual bot of the decluttered HUD: default play frame, MORE open, ABILITY wheel, WEAPON wheel, a toast, pause, pause with the gear open, title, title with the gear open.
##   BOT_RES=844x390 QUALITY=0 tools/bot.sh res://tests/bot_hud_declutter.gd /tmp/out 30 9      (every 30 frames, 9 shots)

var _last := -1


func step(_t: float, _delta: float) -> bool:
	var hud := Game.get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null or Game.player == null:
		return false
	var f: int = Dev.get(&"_frame")
	if f == _last:
		return false
	_last = f
	var tc := hud.touch
	match f:
		3:
			if hud.settings.path == UiSettings.DEFAULT_PATH:
				hud.settings = UiSettings.new("user://bot_declutter.cfg")
			Game.state = &"play"
			tc.controls_on = true
			tc.set_process(true)
			(Game.enemies as EnemyManager).clear()
		25:
			Game.say("QUANTUM CORE RECOVERED  1/6", 2.0)
		55:
			tc.more_open = true
		85:
			tc.more_open = false
			tc._open_wheel(&"ability", -1, Vector2.ZERO)
			tc.wheel.sel = 1
		115:
			tc.wheel.close()
			tc._open_wheel(&"weapon", -1, Vector2.ZERO)
		145:
			tc.wheel.close()
			Game.state = &"paused"
		175:
			hud.press_button(&"menu_gear")
		205:
			Game.state = &"menu"
		235:
			hud.press_button(&"menu_gear")
	if f > 3 and f < 200 and is_instance_valid(Game.story):
		Game.story.banner_t = -1.0
	return false
