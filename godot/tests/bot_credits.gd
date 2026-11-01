extends RefCounted
## Looks at the credits cinematic on the real game: starts it, then jumps its clock to the middle of four blocks so the screenshot sequence shows head, lines and subtitle.
##   tools/bot.sh res://tests/bot_credits.gd <out_prefix> 20 6
var _every := 20
var _phase := -1


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1 and kv[0] == "every":
			_every = maxi(10, int(kv[1]))


func step(_t: float, _delta: float) -> bool:
	var hud := Game.get_tree().root.find_child("Hud", true, false) as Hud
	var ci := Cinematics.instance
	if hud == null or ci == null or Game.player == null:
		return false
	var f: int = Dev.get(&"_frame")
	var slot := (f - 1) / _every
	if slot == _phase:
		return false
	_phase = slot
	var mids := [0.5, 1.5, 3.5, 5.5]
	match slot:
		0:
			hud.settings = UiSettings.new("user://bot_credits.cfg")
			Game.start_new_game()
		1:
			ci.force = true
			print("BOT_CREDITS started=", ci.play(&"credits"))
		2, 3, 4, 5:
			if ci.active:
				ci.t = (float(mids[slot - 2]) + 0.5) * ci.plan.credit_seconds
		6:
			print("BOT_CREDITS active=", ci.active, " state=", Game.state)
	return false
