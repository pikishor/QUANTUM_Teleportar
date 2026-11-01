extends RefCounted
## Integrator bot: intro, chapter and boss scenes on the real game, skipped, then checks the camera, state, hero and input are back.
##   tools/bot.sh res://tests/bot_cine_integ.gd <out_prefix> 20 9
var _every := 20
var _phase := -1
var _pos0 := Vector3.ZERO


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1 and kv[0] == "every":
			_every = maxi(10, int(kv[1]))


func _chk(ok: bool, what: String) -> void:
	print("CINE_INTEG ", "OK   " if ok else "FAIL ", what)


func step(_t: float, _delta: float) -> bool:
	var hud := Game.get_tree().root.find_child("Hud", true, false) as Hud
	var ci := Cinematics.instance
	var p := Game.player as Player
	if hud == null or ci == null or p == null:
		return false
	var rig := p.find_child("CameraRig", true, false) as CameraRig
	var f: int = Dev.get(&"_frame")
	var slot := (f - 1) / _every
	if slot == _phase:
		return false
	_phase = slot
	match slot:
		0:
			hud.settings = UiSettings.new("user://bot_cine.cfg")
			Game.start_new_game()
		1:
			ci.force = true
			_pos0 = p.global_position
			_chk(ci.play(&"intro"), "intro starts")
			_chk(Game.state == &"cutscene", "state cutscene")
		2:
			_chk(rig != null and rig.is_cinematic(), "rig cinematic during intro")
		3:
			ci.t = 30.0
			ci.skip()
		4:
			_chk(not ci.active and Game.state == &"play", "intro ended, state=%s" % Game.state)
			_chk(rig != null and not rig.is_cinematic(), "rig released")
			_chk(p.global_position.distance_to(_pos0) < 3.0, "hero back (%.1f m)" % p.global_position.distance_to(_pos0))
			Input.action_press(&"move_forward")
		5:
			var d := p.global_position.distance_to(_pos0)
			Input.action_release(&"move_forward")
			_chk(d > 0.3, "hero responds to input (%.1f m)" % d)
			_chk(ci.play(&"chapter"), "chapter starts")
		6:
			ci.t = 30.0
			ci.skip()
		7:
			_chk(Game.state == &"play" and not rig.is_cinematic(), "chapter ended, state=%s" % Game.state)
			_chk(ci.play(&"boss_in"), "boss_in starts")
		8:
			ci.t = 30.0
			ci.skip()
		9:
			_chk(Game.state == &"play" and not rig.is_cinematic() and Engine.time_scale == 1.0, "boss_in ended, state=%s ts=%.2f" % [Game.state, Engine.time_scale])
			_chk(ci.play(&"boss_out"), "boss_out starts")
		10:
			ci.t = 30.0
			ci.skip()
		11:
			_chk(Game.state == &"play" and not rig.is_cinematic() and Engine.time_scale == 1.0, "boss_out ended, state=%s ts=%.2f" % [Game.state, Engine.time_scale])
	return false
