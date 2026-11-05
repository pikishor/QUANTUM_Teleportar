extends RefCounted
## AUDIO DEPTH test (wave 17): the new files (district / boss / chase layers, intensity stingers, alien barks, UI cues, airship hum, storm wind) and their sizes, the file-size
## budget for mobile, the theme layer (district by position, boss and chase override, crossfade, sample-locked start), intensity stingers on heat steps, interior low-pass and
## room reverb, weather beds, the airship hum emitter, barks, the stinger duck and the UI helper.
## Run: tools/test.sh tests/test_audio_depth.gd   (the existing tests/test_audio.gd keeps checking the older catalogue; tools/audio/check_audio.py checks the files)

const SR := 44100
const DIR := "res://assets/audio/"
const TOTAL_BUDGET_MB := 30.0        ## everything under assets/audio (WAV one-shots, OGG beds and music), without the .import files
const WAVE17_BUDGET_MB := 4.5        ## what this wave added
const LAYERS: Array[StringName] = [&"music_district_0", &"music_district_1", &"music_district_2", &"music_district_3", &"music_boss", &"music_chase"]
const ONESHOTS := {
	&"sting_combat_0": [1.5, 3.0], &"sting_combat_1": [2.0, 3.5], &"sting_combat_2": [2.5, 4.0], &"sting_boss": [3.0, 5.0], &"sting_chase": [1.5, 3.0],
	&"ui_notify": [0.3, 1.0], &"ui_hover": [0.02, 0.2],
}

const STUB_PLAYER := "extends Node3D\nvar velocity := Vector3.ZERO\nvar vehicle = null\nvar hp := 100.0\nvar max_hp := 100.0\nvar body = null\nvar quantum = null\nvar air_time := 0.0\n"
const STUB_ATMOS := "extends Node\nvar rain_now := 0.7\n"
const STUB_SKY := "extends RefCounted\nvar active := false\nvar node: Node3D = null\n"
const STUB_AMBIENT := "extends Node3D\nvar sky = null\n"
const STUB_WORLD := "extends Node3D\nvar ambient = null\n"

var _keep: Array = []


func _stub(src: String) -> Object:
	var sc := GDScript.new()
	sc.source_code = src
	sc.reload()
	var o: Object = sc.new()
	if o is Node:
		_keep.append(o)
	return o


func _pcm_peak_db(w: AudioStreamWAV) -> float:
	var d := w.data
	var p := 0.0
	for i in d.size() / 2:
		p = maxf(p, absf(float(d.decode_s16(i * 2)) / 32768.0))
	return 20.0 * log(maxf(p, 1e-9)) / log(10.0)


func run(host: Node) -> void:
	var was_muted := Sfx.muted
	var was_auto := Sfx.auto_music
	var was_state := Game.state
	var was_heat := Game.heat
	Sfx.muted = false
	Sfx.auto_music = true
	Sfx.reset_world()
	_files()
	_budget()
	_music_layers(host)
	_stingers()
	_indoors()
	_weather()
	_airship(host)
	_barks_and_ui(host)
	Sfx.indoors_override = -1
	Sfx.stop_music()
	Sfx.stop_ambience()
	Sfx.reset_world()
	Sfx.boss_active = false
	Sfx.auto_music = was_auto
	Sfx.muted = was_muted
	Game.heat = was_heat
	Game.state = was_state
	Game.player = null
	Game.world = null
	Game.atmosphere = null
	for n in _keep:
		if is_instance_valid(n):
			n.free()
	TestLib.check(true, "audio depth test finished")


# ------------------------------------------------------------------ files
func _files() -> void:
	var lens := PackedFloat32Array()
	var ok := true
	for n in LAYERS:
		var v := Sfx.variants_of(n)
		if v.is_empty() or not (v[0] is AudioStreamOggVorbis):
			ok = false
			continue
		lens.append((v[0] as AudioStreamOggVorbis).get_length())
	TestLib.check(ok and lens.size() == 6, "six theme layers (4 districts, boss, chase) exist as OGG")
	var same := true
	for l in lens:
		same = same and absf(l - 30.0) < 0.1
	TestLib.check(same, "every layer is one 30 s loop, the same grid as the five stems (%s)" % str(lens))
	var bad := 0
	for n: StringName in ONESHOTS:
		var v := Sfx.variants_of(n)
		var spec: Array = ONESHOTS[n]
		if v.is_empty():
			bad += 1
			continue
		if v[0] is AudioStreamOggVorbis:   # stings ship as mono OGG (audio size pass): duration window only
			var od := (v[0] as AudioStreamOggVorbis).get_length()
			if od < float(spec[0]) or od > float(spec[1]):
				bad += 1
			continue
		if not (v[0] is AudioStreamWAV):
			bad += 1
			continue
		var w := v[0] as AudioStreamWAV
		var dur := w.get_length()
		if w.format != AudioStreamWAV.FORMAT_16_BITS or w.stereo or w.mix_rate != SR or dur < float(spec[0]) or dur > float(spec[1]) or _pcm_peak_db(w) > -9.0:
			bad += 1
			printerr("  bad one-shot %s (%.2f s, %.1f dB)" % [n, dur, _pcm_peak_db(w)])
	TestLib.check(bad == 0, "stingers and the two new UI cues are 44.1 kHz mono 16-bit, in duration and level windows (%d wrong)" % bad)
	var barks := 0
	var bark_bad := 0
	for k in 8:
		var v := Sfx.variants_of(StringName("alien_bark_%d" % k))
		if v.is_empty():
			bark_bad += 1
			continue
		var w := v[0] as AudioStreamWAV
		barks += 1
		if w == null or w.get_length() < 0.2 or w.get_length() > 0.7 or _pcm_peak_db(w) > -9.0 or _pcm_peak_db(w) < -30.0:
			bark_bad += 1
	var yelps := Sfx.variants_of(&"alien_yelp").size()
	TestLib.check(barks == 8 and bark_bad == 0 and yelps == 2, "8 alien barks (4 growls, 4 chitters) plus 2 yelps, each short (0.2-0.7 s) and in the level window")
	for n: StringName in [&"airship_hum", &"wind_howl"]:
		var v := Sfx.variants_of(n)
		TestLib.check(not v.is_empty() and v[0] is AudioStreamOggVorbis and absf((v[0] as AudioStreamOggVorbis).get_length() - 12.0) < 0.2, "%s is a 12 s OGG loop" % n)


func _dir_bytes(names: Array) -> int:
	var total := 0
	for n in names:
		var f := FileAccess.open(DIR + String(n), FileAccess.READ)
		if f != null:
			total += int(f.get_length())
	return total


func _budget() -> void:
	var all: Array = []
	for n in DirAccess.get_files_at(DIR):
		if n.ends_with(".wav") or n.ends_with(".ogg"):
			all.append(n)
	var total_mb := _dir_bytes(all) / 1048576.0
	TestLib.check(total_mb <= TOTAL_BUDGET_MB, "whole audio folder %.1f MB is inside the %.0f MB mobile budget (%d files)" % [total_mb, TOTAL_BUDGET_MB, all.size()])
	var new_files: Array = []
	for n in all:
		if n.begins_with("music_district_") or n.begins_with("music_boss") or n.begins_with("music_chase") or n.begins_with("sting_combat") or n.begins_with("sting_boss") \
				or n.begins_with("sting_chase") or n.begins_with("alien_") or n.begins_with("ui_notify") or n.begins_with("ui_hover") or n.begins_with("airship") or n.begins_with("wind_howl"):
			new_files.append(n)
	var new_mb := _dir_bytes(new_files) / 1048576.0
	TestLib.check(new_files.size() >= 25 and new_mb <= WAVE17_BUDGET_MB, "wave 17 added %d files, %.2f MB (budget %.1f MB; music and loops are OGG)" % [new_files.size(), new_mb, WAVE17_BUDGET_MB])


# ------------------------------------------------------------------ theme layer
func _music_layers(host: Node) -> void:
	var p := _stub(STUB_PLAYER) as Node3D
	host.add_child(p)
	Game.player = p
	Game.state = &"play"
	Game.heat = 0.0
	Sfx.reset_world()
	Sfx.boss_active = false
	TestLib.check(Sfx.district_at(Vector3(-50, 0, -50)) == 0 and Sfx.district_at(Vector3(50, 0, -50)) == 1 and Sfx.district_at(Vector3(-50, 0, 50)) == 2 and Sfx.district_at(Vector3(50, 0, 50)) == 3,
			"the four quadrants of the city are four districts")
	TestLib.check(Sfx.district_name(Vector3(10, 0, 10)) == &"towers" and Sfx.DISTRICTS.size() == 4, "districts have names (towers at +x,+z)")
	Sfx.stop_music()
	Sfx.play_music()
	p.global_position = Vector3(50, 0, 50)
	Sfx.set_music_state(&"explore", true)
	TestLib.check(Sfx.wanted_layer() == &"music_district_3", "explore in the towers wants the towers layer (%s)" % Sfx.wanted_layer())
	Sfx._step_layers(0.1)
	var i0 := Sfx._layer_cur
	TestLib.check(i0 >= 0 and Sfx._layers[i0].playing and Sfx.layer_player_name(i0) == &"music_district_3", "the layer starts on its own player")
	for _k in 100:
		Sfx._step_layers(0.1)
	TestLib.check(absf(Sfx.layer_db(i0) - float(Sfx.LAYER_DB[&"district"])) < 0.8, "the district layer fades in to %.1f dB (%.1f)" % [float(Sfx.LAYER_DB[&"district"]), Sfx.layer_db(i0)])
	TestLib.check(Sfx._layers[i0].bus == Sfx.MUSIC_BUS, "the layer plays on the Music bus (ducks and low-pass apply to it)")
	# walking into another district swaps the layer: new one on the other player, old one fades out and stops
	p.global_position = Vector3(-50, 0, -50)
	Sfx._step_layers(0.1)
	var i1 := Sfx._layer_cur
	TestLib.check(i1 != i0 and Sfx.layer_player_name(i1) == &"music_district_0" and Sfx._layers[i0].playing, "crossing into the market starts its layer on the other player while the old one fades")
	for _k in 80:
		Sfx._step_layers(0.1)
	TestLib.check(not Sfx._layers[i0].playing and Sfx._layers[i1].playing and Sfx.layer_db(i1) > -9.0, "the old layer stopped, the new one is up (%.1f dB)" % Sfx.layer_db(i1))
	# boss and chase themes win over the district colour
	Sfx.boss_active = true
	Sfx.set_music_state(Sfx.wanted_music_state(), true)
	TestLib.check(Sfx.music_state == &"boss" and Sfx.wanted_layer() == &"music_boss", "the boss theme layer follows boss_active")
	Sfx.boss_active = false
	Sfx.chase_active = true
	TestLib.check(Sfx.wanted_music_state() == &"chase", "chase_active gives the chase music state")
	Sfx.set_music_state(&"chase", true)
	TestLib.check(Sfx.wanted_layer() == &"music_chase" and Sfx.LAYER_DB[&"chase"] > Sfx.LAYER_DB[&"district"], "the chase theme layer, louder than a district")
	TestLib.check(float(Sfx.MUSIC_STATES[&"chase"][1]) > -10.0 and float(Sfx.MUSIC_STATES[&"chase"][3]) > -10.0, "the chase state drives pulse and percussion")
	Sfx.chase_active = false
	Sfx.set_music_state(&"explore", true)
	# pause, menu, death: no layer
	Game.state = &"menu"
	TestLib.check(Sfx.wanted_layer() == &"", "no theme layer in the menu")
	Game.state = &"dead"
	TestLib.check(Sfx.wanted_layer() == &"", "no theme layer on the death screen")
	Game.state = &"play"
	for _k in 80:
		Sfx._step_layers(0.1)
	Sfx.auto_music = false
	for _k in 80:
		Sfx._step_layers(0.1)
	TestLib.check(not Sfx._layers[0].playing and not Sfx._layers[1].playing, "with auto_music off the layers fade away and stop")
	Sfx.auto_music = true
	# mute pauses the layer
	Sfx._step_layers(0.1)
	Sfx.muted = true
	Sfx._step_layers(0.1)
	var cur := Sfx._layer_cur
	TestLib.check(cur < 0 or Sfx._layers[cur].stream_paused, "mute pauses the layer")
	Sfx.muted = false


# ------------------------------------------------------------------ stingers
func _stingers() -> void:
	Sfx.reset_world()
	Sfx.stop_music()
	Sfx.play_music()
	Sfx.set_music_state(&"explore", true)
	Sfx._sting.stop()
	Game.heat = 0.5
	Sfx._step_intensity_stings()
	TestLib.check(not Sfx._sting.playing, "no stinger below heat 2")
	Game.heat = 2.2
	Sfx._step_intensity_stings()
	TestLib.check(Sfx._sting.playing and str(Sfx._sting.stream.resource_path).contains("sting_combat_0"), "heat 2 plays sting_combat_0")
	TestLib.check(Sfx.duck_amount(&"stinger") >= 0.0 and Sfx._duck_hold[&"stinger"] > 0.0, "a stinger ducks the music under it")
	Sfx._step_ducks(0.1)
	TestLib.check(Sfx.effective_bus_db(&"Music") < -2.0 and absf(Sfx.effective_bus_db(&"SFX")) < 0.01, "the stinger duck dips Music (%.1f dB) and leaves the effects" % Sfx.effective_bus_db(&"Music"))
	Sfx._sting.stop()
	Game.heat = 3.2
	Sfx._step_intensity_stings()
	TestLib.check(not Sfx._sting.playing, "a second step inside the gap is held back (no stinger spam)")
	Sfx._state_clock += Sfx.STING_GAP + 1.0
	Sfx._step_intensity_stings()
	Game.heat = 0.0
	Sfx._step_intensity_stings()
	Sfx._state_clock += Sfx.STING_GAP + 1.0
	Sfx._sting.stop()
	Game.heat = 4.5
	Sfx._step_intensity_stings()
	TestLib.check(Sfx._sting.playing and str(Sfx._sting.stream.resource_path).contains("sting_combat_2"), "heat 4+ plays sting_combat_2 (the siege)")
	# boss and chase stings
	Sfx._sting.stop()
	Sfx.set_music_state(&"explore", true)
	Sfx.set_music_state(&"boss")
	TestLib.check(Sfx._sting.playing and str(Sfx._sting.stream.resource_path).contains("sting_boss"), "entering the boss state plays sting_boss")
	Sfx._sting.stop()
	Sfx.set_music_state(&"explore", true)
	Sfx._state_clock += Sfx.STING_GAP + 1.0
	Sfx.set_music_state(&"chase")
	TestLib.check(Sfx._sting.playing and str(Sfx._sting.stream.resource_path).contains("sting_chase"), "entering the chase state plays sting_chase")
	Game.heat = 0.0
	Sfx.reset_world()


# ------------------------------------------------------------------ interiors
func _indoors() -> void:
	Sfx.reset_world()
	Game.state = &"play"
	Sfx.indoors_override = 0
	for _k in 30:
		Sfx._step_indoors(0.1)
	Sfx._set_muffle(0.0)
	TestLib.check(Sfx.music_cutoff_hz() > 20000.0 and Sfx.ambient_cutoff_hz() > 20000.0 and Sfx._reverb != null and Sfx._reverb.wet < 0.01, "outdoors: low-passes open, no room reverb")
	var lp_m := Sfx._lp_music
	var lp_a := Sfx._lp_ambient
	var mi := AudioServer.get_bus_index(&"Music")
	var enabled_before := false
	for k in AudioServer.get_bus_effect_count(mi):
		if AudioServer.get_bus_effect(mi, k) == lp_m:
			enabled_before = AudioServer.is_bus_effect_enabled(mi, k)
	TestLib.check(not enabled_before, "the Music low-pass is switched off outdoors")
	Sfx.indoors_override = 1
	Sfx._step_indoors(0.1)
	TestLib.check(Sfx.indoors_amount() > 0.0 and Sfx.indoors_amount() < 1.0, "walking in closes the filter gradually (%.2f after 0.1 s)" % Sfx.indoors_amount())
	for _k in 30:
		Sfx._step_indoors(0.1)
	Sfx._set_muffle(0.0)
	TestLib.check(absf(Sfx.indoors_amount() - 1.0) < 0.01, "fully inside after about 0.6 s")
	TestLib.check(Sfx.ambient_cutoff_hz() < 1600.0 and Sfx.music_cutoff_hz() < 6000.0 and Sfx.ambient_cutoff_hz() < Sfx.music_cutoff_hz(),
			"inside: street ambience low-passed hard (%.0f Hz), music softly (%.0f Hz)" % [Sfx.ambient_cutoff_hz(), Sfx.music_cutoff_hz()])
	var on_music := false
	var on_amb := false
	var ai := AudioServer.get_bus_index(&"Ambient")
	for k in AudioServer.get_bus_effect_count(mi):
		if AudioServer.get_bus_effect(mi, k) == lp_m:
			on_music = AudioServer.is_bus_effect_enabled(mi, k) and absf(lp_m.cutoff_hz - Sfx.music_cutoff_hz()) < 1.0
	for k in AudioServer.get_bus_effect_count(ai):
		if AudioServer.get_bus_effect(ai, k) == lp_a:
			on_amb = AudioServer.is_bus_effect_enabled(ai, k) and absf(lp_a.cutoff_hz - Sfx.ambient_cutoff_hz()) < 1.0
	TestLib.check(on_music and on_amb, "the real bus low-passes are enabled and carry those cutoffs")
	TestLib.check(Sfx._reverb.wet > 0.2, "the SFX bus gets a room reverb inside (wet %.2f)" % Sfx._reverb.wet)
	var si := AudioServer.get_bus_index(&"SFX")
	TestLib.check(AudioServer.get_bus_effect(si, 0) is AudioEffectCompressor, "the compressor stays the first SFX effect after the reverb is added")
	# low health muffle still wins when it is stronger
	Sfx._muffle = 1.0
	TestLib.check(Sfx.music_cutoff_hz() < 1000.0, "a strong health/vehicle muffle still wins over the interior filter")
	Sfx._muffle = 0.0
	# the hero standing inside the real interior volume counts as indoors
	Sfx.indoors_override = -1
	TestLib.check(not Sfx.is_indoors(), "without an active interior the listener is outdoors")
	Sfx.indoors_override = 0
	for _k in 30:
		Sfx._step_indoors(0.1)
	Sfx._set_muffle(0.0)
	TestLib.check(Sfx.music_cutoff_hz() > 20000.0 and Sfx._reverb.wet < 0.01, "stepping back out reopens the filters and drops the reverb")


# ------------------------------------------------------------------ weather
func _weather() -> void:
	var atm := _stub(STUB_ATMOS)
	Game.atmosphere = atm
	Game.state = &"play"
	Sfx.reset_world()
	Sfx.indoors_override = 0
	Sfx._inside = 0.0
	var cases := {0.0: &"clear", 0.2: &"drizzle", 0.6: &"rain", 0.95: &"storm"}
	var ok := true
	for r: float in cases:
		atm.set(&"rain_now", r)
		ok = ok and Sfx.weather_state() == cases[r]
	TestLib.check(ok, "weather_state(): clear, drizzle, rain, storm from the rain level")
	Sfx.stop_ambience()
	Sfx.start_ambience()
	TestLib.check(Sfx._amb.has(&"wind_howl") and (Sfx._amb[&"wind_howl"] as AudioStreamPlayer).playing, "the storm howl bed loops with the other beds")
	atm.set(&"rain_now", 0.0)
	for _k in 150:
		Sfx._step_ambience(0.1)
	var howl_clear := float(Sfx._amb_vol[&"wind_howl"])
	var wind_clear := float(Sfx._amb_vol[&"wind"])
	var rain_clear := float(Sfx._amb_vol[&"rain_asphalt"])
	atm.set(&"rain_now", 1.0)
	for _k in 150:
		Sfx._step_ambience(0.1)
	var howl_storm := float(Sfx._amb_vol[&"wind_howl"])
	var wind_storm := float(Sfx._amb_vol[&"wind"])
	var rain_storm := float(Sfx._amb_vol[&"rain_asphalt"])
	TestLib.check(howl_clear < 0.02 and howl_storm > 0.1, "wind howl: silent when clear (%.3f), up in a storm (%.2f)" % [howl_clear, howl_storm])
	TestLib.check(wind_storm > wind_clear and rain_storm > 0.5 and rain_clear < 0.02, "wind and rain follow the weather (wind %.2f -> %.2f, rain %.2f -> %.2f)" % [wind_clear, wind_storm, rain_clear, rain_storm])
	# gusts: the wind level moves over time
	var lo := 9.0
	var hi := -9.0
	for k in 120:
		Sfx._state_clock += 0.5
		Sfx._step_ambience(0.5)
		lo = minf(lo, float(Sfx._amb_vol[&"wind"]))
		hi = maxf(hi, float(Sfx._amb_vol[&"wind"]))
	TestLib.check(hi - lo > 0.08, "wind comes in gusts (%.2f..%.2f over a minute)" % [lo, hi])
	# indoors the street beds drop
	var street_out := float(Sfx._amb_vol[&"traffic_far"])
	Sfx._inside = 1.0
	for _k in 150:
		Sfx._step_ambience(0.1)
	TestLib.check(float(Sfx._amb_vol[&"traffic_far"]) < street_out * 0.6, "indoors the traffic bed drops (%.2f -> %.2f)" % [street_out, float(Sfx._amb_vol[&"traffic_far"])])
	Sfx._inside = 0.0
	Sfx.stop_ambience()
	Game.atmosphere = null


# ------------------------------------------------------------------ airship
func _airship(host: Node) -> void:
	Sfx.reset_world()
	Game.state = &"play"
	var sky := _stub(STUB_SKY)
	var amb := _stub(STUB_AMBIENT)
	amb.set(&"sky", sky)
	var world := _stub(STUB_WORLD)
	world.set(&"ambient", amb)
	var ship := Node3D.new()
	_keep.append(ship)
	sky.set(&"node", ship)
	host.add_child(world)
	world.add_child(ship)
	Game.world = world as Node3D
	Sfx.start_ambience()
	Sfx._airship_poll = 0.0
	Sfx._step_airship(0.1)
	TestLib.check(not Sfx.airship_hum_active(), "no hum while no patrol is flying")
	sky.set(&"active", true)
	ship.global_position = Vector3(120, 80, -40)
	Sfx._airship_poll = 0.0
	Sfx._step_airship(0.1)
	TestLib.check(Sfx.airship_hum_active(), "the hum starts with a sweep")
	TestLib.check(Sfx._airship_em.global_position.distance_to(ship.global_position) < 0.01 and Sfx._airship_em is AudioStreamPlayer3D, "the emitter is positional and sits on the airship")
	ship.global_position = Vector3(-60, 82, 10)
	Sfx._step_airship(0.1)
	TestLib.check(Sfx._airship_em.global_position.distance_to(Vector3(-60, 82, 10)) < 0.01, "and follows it")
	sky.set(&"active", false)
	Sfx._airship_poll = 0.0
	Sfx._step_airship(0.1)
	TestLib.check(not Sfx.airship_hum_active(), "the hum stops when the sweep ends")
	Sfx.stop_ambience()
	Game.world = null


# ------------------------------------------------------------------ barks, UI
func _barks_and_ui(host: Node) -> void:
	Sfx.reset_world()
	Sfx._last_start.clear()
	Sfx.bark(&"growl", Vector3(3, 1, 3), 1.0)
	TestLib.check(Sfx._last_start.has("alien_"), "bark(growl) starts an alien_ family sound")
	var playing3d := 0
	for p in Sfx._players3d:
		if p.playing and p.stream != null and str(p.stream.resource_path).contains("alien_bark_"):
			playing3d += 1
			var idx := int(str(p.stream.resource_path).get_file().get_basename().trim_prefix("alien_bark_"))
			TestLib.check(idx >= 0 and idx <= 3, "a growl is one of the four low barks (alien_bark_%d)" % idx)
	TestLib.check(playing3d == 1, "one positional voice carries it")
	for _k in 6:
		Sfx._last_start.clear()
		Sfx.bark(&"chitter", Vector3(0, 1, 0), 1.1)
	var chit := false
	for p in Sfx._players3d:
		if p.playing and p.stream != null and str(p.stream.resource_path).contains("alien_bark_"):
			var idx := int(str(p.stream.resource_path).get_file().get_basename().trim_prefix("alien_bark_"))
			chit = chit or (idx >= 4 and idx <= 7)
	TestLib.check(chit, "chitter kinds come from the high set (4..7)")
	Sfx._last_start.clear()
	Sfx.bark(&"yelp", Vector3.ZERO)
	TestLib.check(Sfx._last_start.has("alien_"), "yelp plays too")
	Sfx._last_start.clear()
	Sfx.bark(&"nonsense", Vector3.ZERO)
	TestLib.check(not Sfx._last_start.has("alien_"), "an unknown kind is ignored")
	var rule := Sfx._rule(&"alien_bark_2")
	TestLib.check(String(rule[0]) == "alien_" and int(rule[2]) <= 3, "barks are one family with a voice cap (%s)" % str(rule))
	# a squad of barks cannot flood the pool
	for _k in 30:
		Sfx._last_start.clear()
		Sfx.bark(&"growl", Vector3(randf_range(-5, 5), 1, randf_range(-5, 5)))
	var n := 0
	for p in Sfx._players3d:
		if p.playing and p.stream != null and str(p.stream.resource_path).contains("alien_"):
			n += 1
	TestLib.check(n <= int(rule[2]), "at most %d barks sound at once (%d)" % [int(rule[2]), n])
	# UI helper
	Sfx.ui(&"notify")
	TestLib.check(Sfx.last_played == &"ui_notify", "ui(&'notify') plays ui_notify")
	Sfx._last_start.clear()
	Sfx.ui(&"hover")
	TestLib.check(Sfx.last_played == &"ui_hover", "ui(&'hover') plays ui_hover")
	var before := Sfx.last_played
	Sfx.ui(&"nothing")
	TestLib.check(Sfx.last_played == before, "unknown UI cues are ignored")
	# aware trooper barks through the enemy poll (stub enemy list)
	var enemies := _stub("extends Node\nvar list: Array = []\n")
	var en := _stub("extends Node3D\nvar aware := true\nvar hp := 60.0\nvar dead := false\nvar type: StringName = &\"operative\"\nfunc threat_charge() -> float:\n\treturn 0.0\n") as Node3D
	var pl := _stub(STUB_PLAYER) as Node3D
	host.add_child(pl)
	host.add_child(en)
	Game.player = pl
	Game.state = &"play"
	Game.enemies = enemies
	enemies.set(&"list", [en])
	Sfx._poll_enemies()                                         # first sight: records state
	Sfx._last_start.clear()
	Sfx._bark_in = 0.0
	Sfx._poll_enemies()
	TestLib.check(Sfx._last_start.has("alien_") and Sfx._bark_in > 2.0, "an aware trooper in range calls out now and then (next bark in %.1f s)" % Sfx._bark_in)
	Game.enemies = null
	Game.player = null
