extends RefCounted
## Visual bot: the weapon HUD on a phone. Frame 10: touch controls on, a switch to the shotgun (the weapon plate pops up). Frame 50: the weapon wheel (seven class wedges) held open.
## Frame 90: the loadout screen. BOT_RES=1200x540 QUALITY=0 tools/bot.sh res://tests/bot_weapon_hud.gd /tmp/x/w 40 3  (every 40 frames, 3 shots)
var _stage := 0


func step(_t: float, _dt: float) -> bool:
	var hud := Game.get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null or Game.player == null:
		return false
	var f: int = Dev.get(&"_frame")
	var p := Game.player as Player
	if f == 3 and _stage == 0:
		_stage = 1
		if hud.settings.path == UiSettings.DEFAULT_PATH:
			hud.settings = UiSettings.new("user://bot_hud.cfg")
		Game.state = &"play"
		hud.touch.controls_on = true
		hud.touch.set_process(true)
		for id: StringName in [&"burst", &"revolver", &"marksman"]:
			WeaponDefs.unlock(id)
		p.weapon.switch_to(&"carbine", true)
	if f == 20 and _stage == 1:
		_stage = 2
		p.weapon.switch_to(&"scatter", true)
	if f == 70 and _stage == 2:
		_stage = 3
		var tc := hud.touch
		tc.wheel.open_at(&"weapon", WeaponWheel.items(), Vector2(tc._vp_size().x * 0.62, tc._vp_size().y * 0.56), tc._scale(), true)
		tc._canvas.queue_redraw()
	if f > 70 and _stage == 3:
		hud.touch._canvas.queue_redraw()
	return false
