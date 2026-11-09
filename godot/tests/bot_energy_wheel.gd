extends RefCounted
## Visual bot (wave 108): the WEAPON wheel with everything unlocked, ten class wedges (ENERGY and BLAST included), taken at frame 25.
##   BOT_RES=1200x540 BOT_USER_ARGS="--touch" tools/bot.sh res://tests/bot_energy_wheel.gd /tmp/wheel 25 1
## Shots are taken every 25 frames: frame 25 = weapon wheel, 50 = ability wheel, 75 = no wheel.

var _tc: TouchControls


func step(_t: float, _delta: float) -> bool:
	var hud := Game.get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null or Game.player == null:
		return false
	_tc = hud.touch
	var f: int = Dev.get(&"_frame")
	if f == 2:
		for id: StringName in WeaponDefs.IDS:
			WeaponDefs.unlock(id)
	if f == 3:
		Game.state = &"play"
		_tc.controls_on = true
		_tc.set_process(true)
	if f == 10:
		_tc._open_wheel(&"weapon", -1, Vector2.ZERO)
	if f == 35:
		_tc.wheel.close()
		_tc._open_wheel(&"ability", -1, Vector2.ZERO)
	if f == 60:
		_tc.wheel.close()
	return false
