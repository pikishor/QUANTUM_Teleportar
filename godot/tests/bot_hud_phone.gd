extends RefCounted
## Visual bot: the phone HUD in play (touch controls, perf readout, objective + story objective + radio subtitle + centre message + vehicle-free ammo box).
##   tools/bot.sh res://tests/bot_hud_phone.gd <out_prefix> 40 2        (resolution is set by the caller: 1280x720 = 16:9, 1600x720 = 20:9)
## Frame 3: the subtitle and the message are queued; the pictures show the top lane (stack, objective, subtitle) and the bottom (ammo, buttons).

var _done := false


func step(_t: float, _delta: float) -> bool:
	var hud := Game.get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null or Game.player == null:
		return false
	var f: int = Dev.get(&"_frame")
	if f == 3 and not _done:
		_done = true
		if hud.settings.path == UiSettings.DEFAULT_PATH:
			hud.settings = UiSettings.new("user://bot_hud.cfg")
		Game.state = &"play"
		Game.score = 1250
		Game.heat = 2.4
		hud.touch.controls_on = true
		hud.touch.perf_on = true
		hud.touch.set_process(true)
		Game.player.set(&"hp", 72.0)
		Game.player.set(&"energy", 64.0)
		Game.say("QUANTUM CORE RECOVERED  1/6", 30.0)
		if is_instance_valid(Game.story):
			Game.story.say("ORACLE", "Observer patrols are sweeping the plaza. Stay low, keep to the shadows and do not teleport inside their sensor cone.", "bot_phone", 0.0, 9)
	if f > 3 and is_instance_valid(Game.story):
		Game.story.hold_left = 30.0
		Game.story.typed = 400.0
		Game.story.banner_t = -1.0
	# draw-call cost of the whole HUD layer: the same frame with and without it (frames 30 / 40 are printed; the layer is hidden from 31 to 40)
	if f == 30 or f == 40:
		print("HUD_DRAWS hud=%s draws=%d" % [str(hud.visible), int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))])
	if f == 31:
		hud.visible = false
		if is_instance_valid(Game.story) and Game.story.view != null:
			Game.story.view.visible = false
	if f == 41:
		hud.visible = true
		if is_instance_valid(Game.story) and Game.story.view != null:
			Game.story.view.visible = true
	return false
