extends RefCounted
## Look-dev bot (wave 124): demo mode on, the DEMO menu open on the WEAPONS tab (BOT_TAB overrides), one weapon picked so a lit entry shows.
##   BOT_RES=2400x1080 QUALITY=0 tools/bot.sh res://tests/bot_demo_weapons_w124.gd /tmp/out 120 2
var _done := false


func step(_t: float, _dt: float) -> bool:
	if _done:
		return false
	var tree := Engine.get_main_loop() as SceneTree
	if Game.player == null or Game.progress == null:
		return false
	var dps := tree.root.find_children("*", "DemoPanel", true, false)
	if dps.is_empty():
		return false
	Game.state = &"menu"
	DemoMode.enter()
	Game.state = &"play"
	var dp := dps[0] as DemoPanel
	dp.open()
	var tab := OS.get_environment("BOT_TAB")
	dp.set_page(DemoPanel.TABS.find(tab if tab != "" else "WEAPONS"))
	DemoMode.equip_weapon(WeaponDefs.ids_in_class(&"pistol")[1])
	dp._layout_key = ""
	_done = true
	return false
