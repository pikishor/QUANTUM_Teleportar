extends RefCounted
## Visual bot of the story layer: the real game driven through the title tagline, a prologue card, the chapter banner, a radio subtitle (also with the
## touch layout), the DECOHERED quote and the chapter end card.
##   tools/bot.sh res://tests/bot_story.gd <out_prefix> 16 8        (every 16 frames, 8 pictures; RENDERER=compat works)

var _every := 16
var _phase := -1


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1 and kv[0] == "every":
			_every = maxi(8, int(kv[1]))


func step(_t: float, _delta: float) -> bool:
	var hud := Game.get_tree().root.find_child("Hud", true, false) as Hud
	var story := Game.story as Story
	if hud == null or story == null or Game.player == null:
		return false
	if hud.settings.path == UiSettings.DEFAULT_PATH:
		hud.settings = UiSettings.new("user://bot_story.cfg")
	var f: int = Dev.get(&"_frame")
	var slot := (f - 1) / _every
	if slot != _phase:
		_phase = slot
		match slot:
			0:
				Game.state = &"menu"
			1:
				Game.start_new_game()
				story.advance(2.6)                              # prologue card 1, partly typed
			2:
				story.advance_card()
				story.skip_cards()                              # chapter banner
				story.advance(0.6)
			3:
				story.banner_t = -1.0                           # radio subtitle: ORACLE, then (touch layout) a VAEL line
				story.queue.clear()
				story.say("ORACLE", "Sector 02. Taller towers, more eyes. Blink between them, link their drones, and do not stand still.", "bot")
			4:
				story.queue.clear()
				story.skip_line()
				Game.force_touch = true
				if hud.touch != null:
					hud.touch.set(&"controls_on", true)
				story.say("VAEL BROADCAST", "Human in Sector 01, you are observed. Hold still. Stillness is a gift to the hive.", "bot2")
			5:
				story.skip_line()
				Game.state = &"dead"
				Game.player_died.emit()
				story.advance(1.2)
			6:
				Game.state = &"play"
				Game.respawn.emit()
				Game.state = &"win"
				Game.sector_cleared.emit()
				story.advance(1.0)
	return false
