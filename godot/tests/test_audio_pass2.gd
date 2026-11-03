extends RefCounted
## AUDIO PASS 2 test: new files and the size budget, time-of-day layers and beds (night pad, night insects, dawn chirps), the thunder duck, ability sounds
## (phase step, entangle, superposition, collapse) and the new UI cues. Run: tools/test.sh tests/test_audio_pass2.gd

const DIR := "res://assets/audio/"
const OGGS: Array[StringName] = [&"music_night", &"dawn_chirps", &"night_insects", &"thunder_roll"]
const WAVS: Array[StringName] = [&"entangle_link", &"collapse", &"superpos_split", &"phase_step", &"ui_slide", &"ui_toggle"]
const TOTAL_BUDGET_MB := 30.0
const PASS2_BUDGET_MB := 1.5
const STUB_PLAYER := "extends Node3D\nvar velocity := Vector3.ZERO\nvar vehicle = null\nvar hp := 100.0\nvar max_hp := 100.0\nvar body = null\nvar quantum = null\nvar air_time := 0.0\n"

var _keep: Array = []


func _size(n: String) -> int:
	var f := FileAccess.open(DIR + n, FileAccess.READ)
	return f.get_length() if f != null else 0


func run(host: Node) -> void:
	var was_muted := Sfx.muted
	var was_state := Game.state
	var was_auto := Sfx.auto_music
	Sfx.muted = false
	Sfx.auto_music = true
	Sfx.hour_override = -1.0
	Sfx.reset_world()
	# files and budget
	var ok := true
	var added := 0
	for n in OGGS:
		var v := Sfx.variants_of(n)
		ok = ok and not v.is_empty() and (v[0] is AudioStreamOggVorbis)
		added += _size(String(n) + ".ogg")
	for n in WAVS:
		var v := Sfx.variants_of(n)
		ok = ok and not v.is_empty() and (v[0] is AudioStreamWAV)
		added += _size(String(n) + ".wav")
	TestLib.check(ok, "all pass-2 files exist and load (4 OGG, 6 WAV)")
	TestLib.check(float(added) / 1048576.0 < PASS2_BUDGET_MB, "pass 2 adds %.2f MB (< %.1f)" % [float(added) / 1048576.0, PASS2_BUDGET_MB])
	var total := 0
	var d := DirAccess.open(DIR)
	if d != null:
		for f in d.get_files():
			if f.ends_with(".wav") or f.ends_with(".ogg"):
				total += _size(f)
	TestLib.check(float(total) / 1048576.0 < TOTAL_BUDGET_MB, "audio total %.1f MB stays under %.0f" % [float(total) / 1048576.0, TOTAL_BUDGET_MB])
	var ml := (Sfx.variants_of(&"music_night")[0] as AudioStreamOggVorbis).get_length()
	var md := (Sfx.variants_of(&"music_district_0")[0] as AudioStreamOggVorbis).get_length()
	TestLib.check(absf(ml - md) < 0.05, "the night pad is on the same 30 s grid as the other layers")
	# time of day weights (no clock: nothing changes)
	TestLib.check(Sfx.night_weight() == 0.0 and Sfx.dawn_weight() == 0.0, "no clock, no time-of-day sound")
	Sfx.hour_override = 23.0
	TestLib.check(Sfx.night_weight() == 1.0 and Sfx.dawn_weight() == 0.0, "23:00 is night")
	Sfx.hour_override = 12.0
	TestLib.check(Sfx.night_weight() == 0.0 and Sfx.dawn_weight() == 0.0, "noon has neither")
	Sfx.hour_override = 6.0
	TestLib.check(Sfx.dawn_weight() > 0.8 and Sfx.night_weight() == 0.0, "06:00 is dawn")
	# night layer
	var p := _stub(host)
	Game.player = p
	Game.state = &"play"
	Game.heat = 0.0
	Sfx.boss_active = false
	Sfx.chase_active = false
	Sfx.stop_music()
	Sfx.play_music()
	Sfx.set_music_state(&"explore", true)
	Sfx.hour_override = 12.0
	TestLib.check(String(Sfx.wanted_layer()).begins_with("music_district_"), "by day the district layer is wanted")
	Sfx.hour_override = 23.0
	TestLib.check(Sfx.wanted_layer() == &"music_night", "at night the night pad layer is wanted")
	Sfx._step_layers(0.1)
	var i := Sfx._layer_cur
	TestLib.check(i >= 0 and Sfx.layer_player_name(i) == &"music_night" and Sfx._layers[i].playing, "the night layer starts on a layer player")
	for _k in 120:
		Sfx._step_layers(0.1)
	TestLib.check(Sfx.layer_db(i) > float(Sfx.LAYER_DB[&"night"]) - 1.5, "and fades up to its level (%.1f dB)" % Sfx.layer_db(i))
	Sfx.boss_active = true
	Sfx.set_music_state(Sfx.wanted_music_state(), true)
	TestLib.check(Sfx.wanted_layer() == &"music_boss", "the boss theme still wins at night")
	Sfx.boss_active = false
	Sfx.set_music_state(&"explore", true)
	# beds
	TestLib.check(Sfx._amb.has(&"night_insects") and Sfx._amb.has(&"dawn_chirps"), "insect and chirp beds exist")
	Sfx.start_ambience()
	Game.atmosphere = _atmos(0.0)
	Sfx.hour_override = 23.0
	for _k in 80:
		Sfx._step_ambience(0.2)
	var ins_night := float(Sfx._amb_vol[&"night_insects"])
	var chirp_night := float(Sfx._amb_vol[&"dawn_chirps"])
	Sfx.hour_override = 6.0
	for _k in 120:
		Sfx._step_ambience(0.2)
	var chirp_dawn := float(Sfx._amb_vol[&"dawn_chirps"])
	var ins_dawn := float(Sfx._amb_vol[&"night_insects"])
	TestLib.check(ins_night > 0.2 and chirp_night < 0.05, "night: insects up (%.2f), no chirps (%.2f)" % [ins_night, chirp_night])
	TestLib.check(chirp_dawn > 0.2 and ins_dawn < 0.05, "dawn: chirps up (%.2f), insects gone (%.2f)" % [chirp_dawn, ins_dawn])
	Game.atmosphere = _atmos(1.0)
	Sfx.hour_override = 23.0
	for _k in 120:
		Sfx._step_ambience(0.2)
	TestLib.check(float(Sfx._amb_vol[&"night_insects"]) < 0.1, "heavy rain hides the insects")
	# thunder duck
	Sfx._duck_hold[&"thunder"] = 0.0
	Sfx._play_oneshot(&"thunder_roll", -6.0)
	TestLib.check(float(Sfx._duck_hold[&"thunder"]) > 0.0, "thunder ducks the music and the rain bed")
	Sfx._step_ducks(0.2)
	TestLib.check(Sfx.effective_bus_db(&"Ambient") < -0.5 and Sfx.effective_bus_db(&"Music") < -0.5, "the buses dip under the thunder")
	# ability sounds
	Sfx.reset_world()
	Sfx.last_played = &""
	Sfx.play(&"blink")
	TestLib.check(Sfx._last_start.has("phase_step") or Sfx.last_played == &"phase_step", "blink lays the phase-step sound under it")
	Sfx.reset_world()
	Sfx.play(&"link")
	TestLib.check(Sfx.last_played == &"entangle_link", "a link plays the ENTANGLE sound")
	Sfx.reset_world()
	Sfx.play(&"superpos")
	TestLib.check(Sfx.last_played == &"superpos_split", "SUPERPOSITION plays its split sound")
	Sfx.reset_world()
	Sfx.play(&"collapse")
	TestLib.check(Sfx.last_played == &"collapse" and float(Sfx._duck_hold[&"ability"]) > 0.0, "COLLAPSE plays and ducks briefly")
	# collapse follows the decoy vanishing
	var q := _quantum_stub()
	p.set(&"quantum", q)
	Sfx.reset_world()
	Sfx._step_quantum(0.1)
	q.set(&"clone", _node3d(host))
	Sfx._step_quantum(0.1)
	TestLib.check(Sfx._was_super, "the decoy is noticed")
	Sfx.last_played = &""
	var c = q.get(&"clone")
	q.set(&"clone", null)
	if is_instance_valid(c):
		c.free()
	Sfx._step_quantum(0.1)
	TestLib.check(Sfx.last_played == &"collapse", "the decoy vanishing plays COLLAPSE")
	# UI
	Sfx.reset_world()
	Sfx.ui(&"slide")
	TestLib.check(Sfx.last_played == &"ui_slide", "ui(slide)")
	Sfx._last_start.clear()
	Sfx.ui(&"toggle")
	TestLib.check(Sfx.last_played == &"ui_toggle", "ui(toggle)")
	# cleanup
	Sfx.hour_override = -1.0
	Sfx.stop_music()
	Sfx.stop_ambience()
	Sfx.reset_world()
	Sfx.muted = was_muted
	Sfx.auto_music = was_auto
	Game.state = was_state
	Game.player = null
	Game.atmosphere = null
	for n in _keep:
		if is_instance_valid(n):
			n.free()
	TestLib.check(true, "audio pass 2 test finished")


func _src(src: String) -> Object:
	var sc := GDScript.new()
	sc.source_code = src
	sc.reload()
	var o: Object = sc.new()
	if o is Node:
		_keep.append(o)
	return o


func _stub(host: Node) -> Node3D:
	var p := _src(STUB_PLAYER) as Node3D
	host.add_child(p)
	return p


func _atmos(rain: float) -> Node:
	var a := _src("extends Node\nvar rain_now := %f\n" % rain) as Node
	return a


func _quantum_stub() -> Object:
	return _src("extends Node\nvar clone = null\nvar links: Array = []\n")


func _node3d(host: Node) -> Node3D:
	var n := Node3D.new()
	host.add_child(n)
	return n
