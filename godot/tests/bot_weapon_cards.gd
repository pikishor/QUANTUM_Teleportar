extends RefCounted
## Visual bot: the WEAPONS catalogue (pictures, bars, diagram, ruler, where to get it) on a phone. One shot every 40 frames: carbine, rocket launcher (blast), sawn shotgun (not owned),
## bolt sniper (not owned, ruler), knife (melee page), singularity throwable (gear card), then the loadout and the weapon wheel with pictures.
##   BOT_RES=2400x1080 QUALITY=0 tools/bot.sh res://tests/bot_weapon_cards.gd /tmp/x/wc 40 8
var _plan: Array = [&"carbine", &"rocket", &"sawn", &"bolt", &"knife", &"singularity"]
var _i := 0
var _loadout_done := false


func step(_t: float, _dt: float) -> bool:
	var hud := Game.get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null or Game.player == null:
		return false
	var f: int = Dev.get(&"_frame")
	if f == 3:
		if hud.settings.path == UiSettings.DEFAULT_PATH:
			hud.settings = UiSettings.new("user://bot_hud.cfg")
		WeaponDefs.reset_unlocked()
		(Game.progress as Progress).credits = 4000
		Game.state = &"paused"
		hud.press_button(&"shop")
		hud.press_button(&"hero_tab_weapons")
	if f > 5 and f % 40 == 30 and _i < _plan.size():
		WeaponsScreen.select(_plan[_i])
		_i += 1
		hud._layout_key = ""
	if f == 40 * 6 + 30 and not _loadout_done:
		_loadout_done = true
		hud.press_button(&"shop_back")
		hud._shop_open = false
		hud.press_button(&"loadout")
	return false
