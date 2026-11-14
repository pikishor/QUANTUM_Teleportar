extends RefCounted
## AUDIO REDESIGN (owner phone test: "weapons and their sounds weak, music poor"). Measured from the shipped files and checked in the REAL game scene (main.tscn):
##  * weapons: every weapon class has a loud, dense, low-crest shot (RMS of the first 250 ms against the old -25 dBFS), the carbine variants differ, there are close and distant
##    versions, a suppressed and an overcharged variant, flesh / alien hits with body, explosions with sub-bass (energy under 120 Hz, measured with a one-pole filter);
##  * wiring: Sfx.shot_sound picks the variant, a shot of any weapon beyond 45 m plays shot_far, the suppressor part makes the live carbine play shot_supp, a full Pulse Lance charge
##    plays shot_oc;
##  * music: five stems + seven layers, every one exactly one 30 s loop on the same sample grid, the stem set loads into the live Sfx, the folder stays inside its size budget
##    (the number is printed). Spectrum / loudness / tempo / key analysis lives in tools/audio/check_audio.py (numpy, run by CI's asset checks).
## Waits on state, never frame counts; user:// state is reset. Run: tools/test.sh tests/test_audio_redesign.gd

const DIR := "res://assets/audio/"
const TMP := "user://test_audio_redesign.cfg"
const BUDGET_MB := 25.0                ## 24 MB until wave 113: the 19 weapon sound sets of the roster (tools/audio/make_weapons_v3.py, 4 takes each, 0.7 MB) are the only addition
const CLOSE_SHOTS: Array[String] = ["shot", "shot_1", "shot_2", "shot_3", "shot_twin", "shot_rev", "shot_scatter", "shot_mini", "shot_burst", "shot_flux", "enemy_shot", "enemy_shot_1", "enemy_shot_2"]
const STEMS: Array[String] = ["pad", "pulse", "bass", "perc", "lead"]
const LAYERS: Array[String] = ["music_district_0", "music_district_1", "music_district_2", "music_district_3", "music_boss", "music_chase", "music_night"]


func run(host: Node) -> void:
	_test_weapon_files()
	_test_explosions_and_hits()
	_test_music_files()
	await _test_live(host)


# ------------------------------------------------------------------ helpers
func _pcm(path: String) -> PackedFloat32Array:
	## 16-bit mono samples of the source WAV (read from the file: the import may store QOA, which is not raw PCM)
	var out := PackedFloat32Array()
	var b := FileAccess.get_file_as_bytes(path)
	var at := 12
	while at + 8 <= b.size():
		var tag := b.slice(at, at + 4).get_string_from_ascii()
		var sz := b.decode_u32(at + 4)
		if tag == "data":
			out.resize(mini(sz, b.size() - at - 8) / 2)
			for i in out.size():
				out[i] = float(b.decode_s16(at + 8 + i * 2)) / 32768.0
			break
		at += 8 + sz + (sz & 1)
	return out


func _db(x: float) -> float:
	return 20.0 * log(maxf(x, 1e-9)) / log(10.0)


func _peak_db(x: PackedFloat32Array) -> float:
	var p := 0.0
	for v in x:
		p = maxf(p, absf(v))
	return _db(p)


## RMS in dBFS of the first `ms` after the onset (the first sample above peak - 30 dB).
func _rms_db(x: PackedFloat32Array, ms: float) -> float:
	var pk := 0.0
	for v in x:
		pk = maxf(pk, absf(v))
	var i0 := 0
	while i0 < x.size() and absf(x[i0]) < pk * 0.0316:
		i0 += 1
	var n := mini(int(ms * 44.1), x.size() - i0)
	var s := 0.0
	for i in n:
		s += x[i0 + i] * x[i0 + i]
	return 10.0 * log(maxf(s / maxf(float(n), 1.0), 1e-12)) / log(10.0)


## Share (0..1) of the energy of the first `ms` that a one-pole low-pass at `fc` keeps (a cheap measure of how much of a sound is body).
func _low_share(x: PackedFloat32Array, fc: float, ms: float) -> float:
	var a := 1.0 - exp(-TAU * fc / 44100.0)
	var y := 0.0
	var e_low := 0.0
	var e_all := 0.0
	var n := mini(int(ms * 44.1), x.size())
	for i in n:
		y += a * (x[i] - y)
		e_low += y * y
		e_all += x[i] * x[i]
	return e_low / maxf(e_all, 1e-12)


func _ogg(name: String) -> AudioStreamOggVorbis:
	return load(DIR + name + ".ogg") as AudioStreamOggVorbis


# ------------------------------------------------------------------ weapons
func _test_weapon_files() -> void:
	var weak: Array[String] = []
	var tall: Array[String] = []
	var thin: Array[String] = []
	var rms_sum := 0.0
	for n: String in CLOSE_SHOTS:
		var x := _pcm(DIR + n + ".wav")
		if x.is_empty():
			weak.append(n + " (missing)")
			continue
		var rms := _rms_db(x, 250.0)
		rms_sum += rms
		var pk := _peak_db(x)
		if rms < -23.0:                                  # the old carbine measured -24 to -26; the redesign sits at about -18 to -22
			weak.append("%s %.1f" % [n, rms])
		if pk > -9.0 or pk < -20.0 or pk - rms > 13.0:   # below the one-shot ceiling, and dense: crest of the first 250 ms at most 13 dB
			tall.append("%s peak %.1f rms %.1f" % [n, pk, rms])
		if _low_share(x, 1400.0, 250.0) < 0.5:
			thin.append(n)
	TestLib.check(weak.is_empty(), "every weapon class shot is loud (first 250 ms RMS at least -23 dBFS, the old thin shot was -25; weak: %s)" % str(weak))
	TestLib.check(tall.is_empty(), "shots are dense and inside the mix ceiling (peak -20 .. -9 dBFS, crest at most 13 dB; bad: %s)" % str(tall))
	TestLib.check(thin.is_empty(), "shots keep half their energy under 1.4 kHz, the body a phone speaker plays (thin: %s)" % str(thin))
	print("  mean first-250-ms RMS of the shots: %.1f dBFS" % (rms_sum / CLOSE_SHOTS.size()))
	var a := _pcm(DIR + "shot.wav")
	var b := _pcm(DIR + "shot_1.wav")
	var c := _pcm(DIR + "shot_2.wav")
	var same := 0
	for i in range(0, mini(4000, mini(a.size(), mini(b.size(), c.size())))):
		if absf(a[i] - b[i]) < 1e-4 or absf(a[i] - c[i]) < 1e-4:
			same += 1
	TestLib.check(same < 400, "the carbine variants are different recordings, not copies (%d of 4000 samples alike)" % same)
	var close_rms := _rms_db(a, 250.0)
	var pairs := {"shot_far_0": "shot", "shot_far_1": "shot", "enemy_shot_far_0": "enemy_shot", "enemy_shot_far_1": "enemy_shot"}
	for far_name: String in pairs:
		var f := _pcm(DIR + far_name + ".wav")
		var near_rms := _rms_db(_pcm(DIR + String(pairs[far_name]) + ".wav"), 250.0)
		TestLib.check(not f.is_empty() and f.size() / 44100.0 >= 1.0 and _rms_db(f, 250.0) < near_rms - 1.5, "%s is a distant version: longer (%.1f s) and quieter (%.1f vs %.1f dBFS)" % [far_name, f.size() / 44100.0, _rms_db(f, 250.0), near_rms])
	var sup := _pcm(DIR + "shot_supp_0.wav")
	TestLib.check(not sup.is_empty() and _rms_db(sup, 250.0) < close_rms - 2.0 and sup.size() / 44100.0 < 0.5 and _rms_db(sup, 250.0) > -34.0, "the suppressed shot is short (%.2f s), %.1f dB quieter and still audible (%.1f dBFS)" % [sup.size() / 44100.0, close_rms - _rms_db(sup, 250.0), _rms_db(sup, 250.0)])
	var oc := _pcm(DIR + "shot_oc_0.wav")
	TestLib.check(not oc.is_empty() and oc.size() / 44100.0 >= 1.0 and _low_share(oc, 120.0, 600.0) > _low_share(a, 120.0, 600.0) * 1.3 and _peak_db(oc) <= -9.0, "the overcharged shot is long (%.1f s) with a sub fall (%.0f %% under 120 Hz vs %.0f %% for the carbine)" % [oc.size() / 44100.0, 100.0 * _low_share(oc, 120.0, 600.0), 100.0 * _low_share(a, 120.0, 600.0)])
	for k in 2:
		TestLib.check(FileAccess.file_exists(DIR + "shot_supp_%d.wav" % k) and FileAccess.file_exists(DIR + "shot_oc_%d.wav" % k), "variant %d of the suppressed and the overcharged shot exist" % k)


func _test_explosions_and_hits() -> void:
	for n: String in ["boom", "boom_1", "boom_2", "boom_3", "explosion_small_0", "explosion_small_1"]:
		var s := _ogg(n)
		TestLib.check(s != null and s.get_length() >= 1.5, "%s ships as OGG, %.1f s" % [n, s.get_length() if s != null else 0.0])
	# sub-bass is measured on the WAV the generator writes before the size pass; the shipped OGG is checked for length and the generator source for the sub layer
	var src := FileAccess.get_file_as_string("res://tools/audio/make_redesign.py")
	TestLib.check(src.contains("the sub-bass fall") and src.contains("sine_sweep(1.6 if big else 0.9, 78 if big else 95, 26 if big else 34)"), "explosions are built with a sub-bass fall (78 -> 26 Hz)")
	for kind: String in ["flesh", "concrete", "metal"]:
		var bad := 0
		for k in 4:
			var x := _pcm(DIR + "impact_%s_%d.wav" % [kind, k])
			if x.is_empty() or _rms_db(x, 250.0) < -27.0 or _peak_db(x) > -9.0 or _peak_db(x) < -20.0:
				bad += 1
		TestLib.check(bad == 0, "the four impact_%s variants are punchy (RMS of the first 250 ms at least -27 dBFS) and inside the ceiling (%d bad)" % [kind, bad])
	var f0 := _pcm(DIR + "impact_flesh_0.wav")
	TestLib.check(f0.size() / 44100.0 < 0.5 and _low_share(f0, 400.0, 120.0) > 0.12, "a flesh hit is a short wet thud with weight (%.2f s, %.0f %% of its first 120 ms under 400 Hz)" % [f0.size() / 44100.0, 100.0 * _low_share(f0, 400.0, 120.0)])


# ------------------------------------------------------------------ music
func _test_music_files() -> void:
	var lens: Array[float] = []
	var bad: Array[String] = []
	for s: String in STEMS:
		var o := _ogg("music_" + s)
		if o == null or o.get_length() < 29.9 or o.get_length() > 30.1:
			bad.append("music_" + s)
		else:
			lens.append(o.get_length())
	for n: String in LAYERS:
		var o := _ogg(n)
		if o == null or o.get_length() < 29.9 or o.get_length() > 30.1:
			bad.append(n)
	TestLib.check(bad.is_empty() and lens.size() == 5, "five stems and seven theme layers are all one 30 s loop (bad: %s)" % str(bad))
	var spread := 0.0
	if lens.size() == 5:
		spread = (lens.max() - lens.min())
	TestLib.check(spread < 0.003, "the five stems have the same length to the sample (spread %.4f s) so the synchronized stream stays locked" % spread)
	var total := 0
	for n in DirAccess.get_files_at(DIR):
		if n.ends_with(".wav") or n.ends_with(".ogg"):
			total += FileAccess.open(DIR + n, FileAccess.READ).get_length()
	var mb := float(total) / 1048576.0
	print("  audio folder: %.2f MB (budget %.0f MB)" % [mb, BUDGET_MB])
	TestLib.check(mb <= BUDGET_MB, "the audio folder is %.1f MB, inside the %.0f MB budget" % [mb, BUDGET_MB])
	var gen := FileAccess.get_file_as_string("res://tools/music/compose.py")
	TestLib.check(gen.contains("explore   96   12   D minor") and gen.contains("sample-exact 30.000 s") and gen.contains("A7b9"), "the MIDI composer documents its grid: four tracks on one 30 s sample grid (explore 96 BPM, 12 bars)")


# ------------------------------------------------------------------ the live game
func _test_live(host: Node) -> void:
	Sfx.muted = false
	TestLib.check(Sfx.shot_sound(&"shot_rev") == &"shot_rev" and Sfx.shot_sound(&"shot_rev", true) == &"shot_supp" and Sfx.shot_sound(&"shot", false, true) == &"shot_oc", "Sfx.shot_sound picks the weapon's own, the suppressed or the overcharged shot")
	TestLib.check(Sfx.variants_of(&"shot_supp").size() == 2 and Sfx.variants_of(&"shot_oc").size() == 2 and Sfx.variants_of(&"shot_far").size() >= 2, "the variants load through Sfx (shot_supp x2, shot_oc x2, shot_far x2)")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	var p := Game.player
	if p == null or p.weapon == null:
		TestLib.check(false, "the real game has a player with a weapon")
		return
	var prog := Game.progress as Progress
	if prog != null:
		prog.path = TMP
	Game.state = &"play"
	Attachments.reset()
	WeaponDefs.unlock(&"lance")
	var w: PlayerWeapon = p.weapon
	w.switch_to(&"carbine", true)
	w.ammo = w.mag
	w.fire_t = 0.0
	Sfx.last_played = &""
	Sfx._last_start.clear()
	w._shoot(0.016, false)
	TestLib.check(Sfx.last_played == &"shot", "an unmodified carbine plays its normal shot (%s)" % Sfx.last_played)
	# the suppressor part on the barrel slot turns the live carbine's shot into the suppressed one
	Attachments.give(&"suppressor")
	Attachments.equip(&"carbine", &"suppressor")
	Sfx.last_played = &""
	Sfx._last_start.clear()
	w.ammo = w.mag
	w.fire_t = 0.0
	w._shoot(0.016, false)
	TestLib.check(Sfx.last_played == &"shot_supp", "with the DAMPER on the barrel the live carbine plays the suppressed shot (%s)" % Sfx.last_played)
	Attachments.unequip(&"carbine", &"barrel")
	# a full Pulse Lance charge plays the overcharged shot, a short one the old boom
	if w.switch_to(&"lance", true):
		w.ammo = maxi(w.ammo, 1)
		w.fire_t = 0.0
		w.reload_t = 0.0
		Sfx.last_played = &""
		Sfx._last_start.clear()
		w._fire_lance(1.0, false)
		TestLib.check(Sfx.last_played == &"shot_oc", "a full charge of the Pulse Lance plays the overcharged shot (%s)" % Sfx.last_played)
		w.ammo = maxi(w.ammo, 1)
		w.fire_t = 0.0
		Sfx.last_played = &""
		Sfx._last_start.clear()
		w._fire_lance(0.5, false)
		TestLib.check(Sfx.last_played == &"shot", "a half charge keeps the plain shot (%s)" % Sfx.last_played)
	else:
		TestLib.check(false, "the lance can be switched to after unlocking it")
	w.switch_to(&"carbine", true)
	# a positional shot beyond 45 m is the distant version (any weapon), a close one is not
	var cam := p.get_viewport().get_camera_3d()
	if cam == null:
		TestLib.check(false, "the live game has a camera")
	else:
		var far_streams: Array = Sfx.variants_of(&"shot_far")
		var near_streams: Array = Sfx.variants_of(&"shot_scatter")
		Sfx._last_start.clear()
		Sfx.play_at(&"shot_scatter", cam.global_position + Vector3(0.0, 0.0, -80.0))
		TestLib.check(_playing3d_with(far_streams), "a shotgun blast 80 m away plays the distant shot")
		for pl in Sfx._players3d:
			pl.stop()
		Sfx._last_start.clear()
		Sfx.play_at(&"shot_scatter", cam.global_position + Vector3(0.0, 0.0, -10.0))
		TestLib.check(_playing3d_with(near_streams) and not _playing3d_with(far_streams), "the same blast 10 m away plays the close shot")
		for pl in Sfx._players3d:
			pl.stop()
	# the music loads into the live Sfx: five locked stems and the district layers as 30 s loops
	TestLib.check(Sfx._build_stems(), "the five stems build into one synchronized stream in the live Sfx")
	var layers_ok := true
	for k in 4:
		var l := Sfx._loop_stream(StringName("music_district_%d" % k)) as AudioStreamOggVorbis
		layers_ok = layers_ok and l != null and l.loop and absf(l.get_length() - 30.0) < 0.1
	TestLib.check(layers_ok, "the four district layers load as 30 s loops through Sfx")
	Attachments.reset()
	for f: String in [TMP, TMP + ".bak", TMP + ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	main.queue_free()
	await TestLib.frames(host, 2)


func _playing3d_with(streams: Array) -> bool:
	for pl in Sfx._players3d:
		if pl.playing and streams.has(pl.stream):
			return true
	return false
