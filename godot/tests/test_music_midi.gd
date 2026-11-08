extends RefCounted
## MUSIC FROM MIDI (tools/music/compose.py, FluidR3 GM SoundFont): four composed tracks (explore, menu, combat, chase), five stems each, plus seven theme layers.
##  * files: every stem and layer has its MIDI source (parsed here: tempo, note count, last note inside three passes of the loop) and its OGG, nothing left of the old synthesised music;
##  * loop points: every OGG is exactly one 30.000 s (1,323,000 sample) loop with the loop flag set by Sfx, the five stems of a track have the same length to the sample, the MIDI tempo
##    times the bar count is that 30 s;
##  * loudness (measured on the encoded files by the composer and recorded in tools/music/manifest.json; the numbers are cross-checked against the files by size and against Godot's length):
##    each track's five stems sum to about -22 LUFS under a -6 dBFS peak, combat and chase sit below explore, the layers are quiet, the seam of every file is click free;
##  * adaptive layering: Sfx picks the track from the music state (stems are the intensity layers inside it), builds each as one synchronized stream and the live game switches tracks.
## Waits on state, never on frame counts. Run: tools/test.sh tests/test_music_midi.gd

const DIR := "res://assets/audio/"
const MIDI_DIR := "res://tools/music/midi/"
const MANIFEST := "res://tools/music/manifest.json"
const STEMS: Array[String] = ["pad", "pulse", "bass", "perc", "lead"]
const TRACK_BPM := {"explore": 96, "menu": 64, "combat": 144, "chase": 160}
const TRACK_BARS := {"explore": 12, "menu": 8, "combat": 18, "chase": 20}
const PREFIX := {"explore": "music_", "menu": "mus_menu_", "combat": "mus_combat_", "chase": "mus_chase_"}
const LAYERS: Array[String] = ["district_0", "district_1", "district_2", "district_3", "night", "boss", "chase"]
const LAYER_BASE := {"district_0": "explore", "district_1": "explore", "district_2": "explore", "district_3": "explore", "night": "explore", "boss": "combat", "chase": "chase"}
const LOOP_SAMPLES := 1323000
const OLD_SYNTH := ["make_music.py", "make_redesign_music.py"]


func run(host: Node) -> void:
	_test_midi()
	var man := _test_manifest()
	_test_files(man)
	_test_loudness(man)
	await _test_wiring(host)


# ------------------------------------------------------------------ MIDI source
## Minimal SMF reader: returns {ok, tempo_us, notes, last_note_tick, division, tracks}
func _read_midi(path: String) -> Dictionary:
	var out := {"ok": false, "tempo_us": 0, "notes": 0, "last_note_tick": 0, "division": 0, "tracks": 0, "channels": {}}
	var b := FileAccess.get_file_as_bytes(path)
	if b.size() < 22 or b.slice(0, 4).get_string_from_ascii() != "MThd":
		return out
	var ntrk := (b[10] << 8) | b[11]
	out["division"] = (b[12] << 8) | b[13]
	out["tracks"] = ntrk
	var at := 14
	for _t in ntrk:
		if at + 8 > b.size() or b.slice(at, at + 4).get_string_from_ascii() != "MTrk":
			return out
		var size := (b[at + 4] << 24) | (b[at + 5] << 16) | (b[at + 6] << 8) | b[at + 7]
		var p := at + 8
		var end := mini(p + size, b.size())
		var tick := 0
		var running := 0
		while p < end:
			var delta := 0
			while p < end:
				var c := b[p]
				p += 1
				delta = (delta << 7) | (c & 0x7F)
				if c & 0x80 == 0:
					break
			tick += delta
			var st := b[p]
			if st == 0xFF:
				var mtype := b[p + 1]
				p += 2
				var ln := 0
				while p < end:
					var c2 := b[p]
					p += 1
					ln = (ln << 7) | (c2 & 0x7F)
					if c2 & 0x80 == 0:
						break
				if mtype == 0x51 and ln == 3:
					out["tempo_us"] = (b[p] << 16) | (b[p + 1] << 8) | b[p + 2]
				p += ln
				continue
			if st == 0xF0 or st == 0xF7:
				p += 1
				var ln2 := 0
				while p < end:
					var c3 := b[p]
					p += 1
					ln2 = (ln2 << 7) | (c3 & 0x7F)
					if c3 & 0x80 == 0:
						break
				p += ln2
				continue
			if st & 0x80:
				running = st
				p += 1
			var kind := running & 0xF0
			var ch := running & 0x0F
			var n_data := 1 if (kind == 0xC0 or kind == 0xD0) else 2
			if kind == 0x90 and b[p + 1] > 0:
				out["notes"] += 1
				out["last_note_tick"] = maxi(int(out["last_note_tick"]), tick)
				(out["channels"] as Dictionary)[ch] = true
			p += n_data
		at += 8 + size
	out["ok"] = true
	return out


func _test_midi() -> void:
	var bad: Array[String] = []
	var tempo_bad: Array[String] = []
	var thin: Array[String] = []
	var overrun: Array[String] = []
	var count := 0
	for tr: String in TRACK_BPM:
		for st in STEMS:
			var info := _read_midi(MIDI_DIR + "%s_%s.mid" % [tr, st])
			count += 1
			if not info["ok"]:
				bad.append("%s_%s" % [tr, st])
				continue
			var bpm := 60000000.0 / float(info["tempo_us"]) if int(info["tempo_us"]) > 0 else 0.0
			if absf(bpm - float(TRACK_BPM[tr])) > 0.05:
				tempo_bad.append("%s_%s %.2f" % [tr, st, bpm])
			if int(info["notes"]) < 20:
				thin.append("%s_%s" % [tr, st])
			var loop_ticks := int(info["division"]) * 4 * int(TRACK_BARS[tr])
			if int(info["last_note_tick"]) >= 3 * loop_ticks:      # the loop is written three times for the seamless render, no note may start beyond the third pass
				overrun.append("%s_%s" % [tr, st])
	for l in LAYERS:
		var info := _read_midi(MIDI_DIR + "layer_%s.mid" % l)
		count += 1
		if not info["ok"]:
			bad.append("layer_" + l)
			continue
		var base: String = LAYER_BASE[l]
		var bpm := 60000000.0 / float(info["tempo_us"]) if int(info["tempo_us"]) > 0 else 0.0
		if absf(bpm - float(TRACK_BPM[base])) > 0.05:
			tempo_bad.append("layer_%s %.2f" % [l, bpm])
		if int(info["notes"]) < 20:
			thin.append("layer_" + l)
	TestLib.check(bad.is_empty() and count == 27, "all 27 MIDI sources (20 stems + 7 layers) exist and parse (%d read, bad: %s)" % [count, str(bad)])
	TestLib.check(tempo_bad.is_empty(), "every MIDI file carries the tempo of its track: explore 96, menu 64, combat 144, chase 160 BPM (off: %s)" % str(tempo_bad))
	TestLib.check(thin.is_empty() and overrun.is_empty(), "every MIDI part has real content and stays inside its loop (thin: %s, overrun: %s)" % [str(thin), str(overrun)])
	# the grid: BPM x bars x 4 / 60 is 30 s for all four tracks, so the stems, layers and tracks share one sample grid
	var grid_ok := true
	for tr: String in TRACK_BPM:
		grid_ok = grid_ok and absf(float(TRACK_BARS[tr]) * 4.0 * 60.0 / float(TRACK_BPM[tr]) - 30.0) < 0.0001
	TestLib.check(grid_ok, "tempo x bars gives exactly 30 s for every track")
	var melodic := _read_midi(MIDI_DIR + "combat_pulse.mid")
	var drums := _read_midi(MIDI_DIR + "combat_perc.mid")
	TestLib.check((melodic["channels"] as Dictionary).has(0) and (drums["channels"] as Dictionary).has(9), "the combat chugs are on a melodic channel and the drums on channel 10 (General MIDI)")


# ------------------------------------------------------------------ manifest
func _test_manifest() -> Dictionary:
	var txt := FileAccess.get_file_as_string(MANIFEST)
	var parsed: Variant = JSON.parse_string(txt)
	TestLib.check(parsed is Dictionary and (parsed as Dictionary).has("files"), "tools/music/manifest.json exists and parses (written by compose.py from the encoded files)")
	if not (parsed is Dictionary):
		return {}
	var man: Dictionary = parsed
	TestLib.check(int(man.get("loop_samples", 0)) == LOOP_SAMPLES and (man["files"] as Array).size() == 27 and String(man.get("soundfont", "")).contains("MIT"),
			"the manifest lists 27 files on a %d sample loop and names the MIT-licensed SoundFont" % LOOP_SAMPLES)
	return man


# ------------------------------------------------------------------ OGG files and loop points
func _ogg(file_name: String) -> AudioStreamOggVorbis:
	var path := DIR + file_name
	if not FileAccess.file_exists(path):
		return null
	var s := Sfx._loop_stream(StringName(file_name.get_basename())) as AudioStreamOggVorbis
	return s


func _test_files(man: Dictionary) -> void:
	var missing: Array[String] = []
	var wrong_len: Array[String] = []
	var no_loop: Array[String] = []
	var spread_bad: Array[String] = []
	for tr: String in TRACK_BPM:
		var lens: Array[float] = []
		for st in STEMS:
			var fn: String = "%s%s.ogg" % [PREFIX[tr], st]
			var o := _ogg(fn)
			if o == null:
				missing.append(fn)
				continue
			lens.append(o.get_length())
			if absf(o.get_length() - 30.0) > 0.01:
				wrong_len.append("%s %.4f" % [fn, o.get_length()])
			if not o.loop or o.loop_offset != 0.0:
				no_loop.append(fn)
		if lens.size() == 5 and (lens.max() - lens.min()) > 0.003:
			spread_bad.append("%s %.4f" % [tr, lens.max() - lens.min()])
	for l in LAYERS:
		var fn := "music_%s.ogg" % l
		var o := _ogg(fn)
		if o == null:
			missing.append(fn)
			continue
		if absf(o.get_length() - 30.0) > 0.01:
			wrong_len.append("%s %.4f" % [fn, o.get_length()])
		if not o.loop:
			no_loop.append(fn)
	var legacy := _ogg("music_ambient.ogg")
	TestLib.check(missing.is_empty(), "all 20 stem OGGs and 7 layer OGGs exist (missing: %s)" % str(missing))
	TestLib.check(wrong_len.is_empty() and legacy != null and absf(legacy.get_length() - 30.0) < 0.01, "every loop is one 30 s pass (off: %s)" % str(wrong_len))
	TestLib.check(no_loop.is_empty() and spread_bad.is_empty(), "every loop has its loop flag from offset 0 and the five stems of a track stay sample-locked (spread over 3 ms: %s, no loop: %s)" % [str(spread_bad), str(no_loop)])
	# the manifest agrees with the files that are committed (sizes) and with Godot's length (to a few samples)
	var drift: Array[String] = []
	var seam_bad: Array[String] = []
	for e: Dictionary in (man.get("files", []) as Array):
		var fn: String = e["file"]
		var f := FileAccess.open(DIR + fn, FileAccess.READ)
		if f == null:
			drift.append(fn + " missing")
			continue
		if f.get_length() != int(e["bytes"]):
			drift.append("%s %d != %d" % [fn, f.get_length(), int(e["bytes"])])
		if int(e["samples"]) != LOOP_SAMPLES:
			drift.append("%s %d samples" % [fn, int(e["samples"])])
		if float(e["seam"]) > 1.5:
			seam_bad.append("%s %.2f" % [fn, float(e["seam"])])
	TestLib.check(drift.is_empty(), "the manifest matches the committed OGG files (rerun tools/music/compose.py if not): %s" % str(drift))
	TestLib.check(seam_bad.is_empty(), "no loop has a click at its seam (jump across the seam at most 1.5 x the steepest step inside): %s" % str(seam_bad))
	var old_gone := true
	for n in OLD_SYNTH:
		var src := FileAccess.get_file_as_string("res://tools/audio/" + n)
		old_gone = old_gone and src.contains("SUPERSEDED")
	TestLib.check(old_gone, "the old numpy music generators are marked SUPERSEDED by tools/music/compose.py (they no longer write the shipped music)")


# ------------------------------------------------------------------ loudness
func _test_loudness(man: Dictionary) -> void:
	var tracks: Dictionary = man.get("tracks", {})
	var bad: Array[String] = []
	for tr: String in TRACK_BPM:
		var t: Dictionary = tracks.get(tr, {})
		if t.is_empty() or float(t["lufs"]) < -26.0 or float(t["lufs"]) > -19.0 or float(t["peak_db"]) > -5.0:
			bad.append("%s %s" % [tr, str(t)])
	TestLib.check(bad.is_empty(), "each track's five stems sum to -26 .. -19 LUFS with the peak under -5 dBFS (%s)" % str(bad))
	var ex: float = float((tracks.get("explore", {}) as Dictionary).get("lufs", 0.0))
	var co: float = float((tracks.get("combat", {}) as Dictionary).get("lufs", 0.0))
	var ch: float = float((tracks.get("chase", {}) as Dictionary).get("lufs", 0.0))
	TestLib.check(co < ex and ch < ex and ex - co < 3.0, "combat (%.1f) and chase (%.1f) sit a little under explore (%.1f) so that shots stay on top, and tracks are within 3 LU of each other" % [co, ch, ex])
	var quiet: Array[String] = []
	var loud_layers: Array[String] = []
	var spread: Array[float] = []
	for e: Dictionary in (man.get("files", []) as Array):
		if e["kind"] == "layer":
			if float(e["lufs"]) < -36.0 or float(e["lufs"]) > -18.0 or float(e["peak_db"]) > -7.5:
				loud_layers.append("%s %.1f" % [e["file"], float(e["lufs"])])
		else:
			spread.append(float(e["lufs"]))
			if float(e["lufs"]) < -45.0:
				quiet.append("%s %.1f" % [e["file"], float(e["lufs"])])
	TestLib.check(loud_layers.is_empty() and quiet.is_empty(), "the 7 layers sit at -36 .. -18 LUFS and no stem is silent (layers off: %s, silent: %s)" % [str(loud_layers), str(quiet)])
	# optional independent measurement of one stem with ffmpeg when it is installed (the runner may not have it): an ebur128 pass must agree with the manifest's lufs_itu within 1 LU
	var out: Array = []
	var code := OS.execute("ffmpeg", ["-hide_banner", "-nostats", "-i", ProjectSettings.globalize_path(DIR + "mus_combat_pad.ogg"), "-af", "ebur128", "-f", "null", "-"], out, true)
	if code == 0 and not out.is_empty():
		var text: String = String(out[0])
		var re := RegEx.new()
		re.compile("I:\\s+(-?[0-9.]+) LUFS")
		var from := maxi(text.rfind("Integrated loudness:"), 0)          # the summary block (progress lines carry running values)
		var found := re.search_all(text.substr(from))
		var v := float(found[0].get_string(1)) if not found.is_empty() else 0.0
		var want := 0.0
		for e: Dictionary in (man.get("files", []) as Array):
			if e["file"] == "mus_combat_pad.ogg":
				want = float(e["lufs_itu"])
		TestLib.check(not found.is_empty() and absf(v - want) < 1.0, "ffmpeg's integrated loudness of the combat pad (%.1f LUFS) agrees with the manifest (%.1f)" % [v, want])
	else:
		print("  note: ffmpeg not available, skipped the independent loudness cross-check")


# ------------------------------------------------------------------ the live game
func _test_wiring(host: Node) -> void:
	TestLib.check(Sfx.track_for_state(&"menu") == &"menu" and Sfx.track_for_state(&"combat") == &"combat" and Sfx.track_for_state(&"boss") == &"combat" and Sfx.track_for_state(&"chase") == &"chase",
			"menu, combat (and the boss) and chase pick their own tracks")
	TestLib.check(Sfx.track_for_state(&"explore") == &"explore" and Sfx.track_for_state(&"alert") == &"explore" and Sfx.track_for_state(&"driving") == &"explore" and Sfx.track_for_state(&"sneak") == &"explore"
			and Sfx.track_for_state(&"death", &"combat") == &"combat" and Sfx.track_for_state(&"win") == &"explore", "calm, alert, driving and stealth ride on the explore track, death keeps the running one")
	var was_auto := Sfx.auto_music
	var was_state := Game.state
	var was_heat := Game.heat
	Sfx.auto_music = false
	Sfx.stop_music()
	Game.state = &"menu"
	Sfx.play_music()
	TestLib.check(Sfx.is_music_playing() and Sfx.music_track == &"menu" and Sfx._music.stream == Sfx._track_streams[&"menu"], "the title screen plays the menu theme")
	Game.state = &"play"
	var built := true
	for tr in Sfx.TRACKS:
		var sync := Sfx._build_track(tr)
		built = built and sync != null and sync.stream_count == 5
		if sync != null:
			for i in 5:
				built = built and sync.get_sync_stream(i) is AudioStreamOggVorbis
	TestLib.check(built and Sfx.TRACKS.size() == 4, "each of the four tracks builds into one synchronized stream of five OGG stems")
	var steps := {&"explore": &"explore", &"combat": &"combat", &"chase": &"chase", &"menu": &"menu", &"alert": &"explore"}
	var ok := true
	for st: StringName in steps:
		Sfx.set_music_state(st, true)
		ok = ok and Sfx.music_track == steps[st] and Sfx._music.playing and Sfx._music.stream == Sfx._track_streams[steps[st]]
		for i in 5:
			ok = ok and absf(Sfx.stem_db(i) - float(Sfx.MUSIC_STATES[st][i])) < 0.01
	TestLib.check(ok, "the live music follows the state through the four tracks with the state's stem levels (the intensity layers)")
	Sfx.set_music_state(&"combat", true)
	Sfx._step_music(2.0)
	var combat_stems := 0
	for i in 5:
		combat_stems += 1 if Sfx.stem_db(i) > -20.0 else 0
	Sfx.set_music_state(&"alert", true)
	Sfx._step_music(2.0)
	var alert_stems := 0
	for i in 5:
		alert_stems += 1 if Sfx.stem_db(i) > -20.0 else 0
	TestLib.check(combat_stems == 5 and alert_stems < combat_stems and Sfx.music_track == &"explore", "combat lifts all five stems (%d), alert on the explore track keeps fewer (%d)" % [combat_stems, alert_stems])
	# game facts drive it: heat 3 is combat, a chase flag is chase
	Sfx.auto_music = true
	Game.heat = 4.0
	Sfx.set_music_state(Sfx.wanted_music_state(), true)
	TestLib.check(Sfx.music_state == &"combat" and Sfx.music_track == &"combat", "heat 4 in the game puts the combat track on")
	Game.heat = 0.0
	Sfx.chase_active = true
	Sfx.set_music_state(Sfx.wanted_music_state(), true)
	TestLib.check(Sfx.music_track == &"chase", "a chase puts the chase track on")
	Sfx.chase_active = false
	Sfx.auto_music = false
	Sfx.set_music_state(&"explore", true)
	Sfx._step_music(2.0)
	Sfx.stop_music()
	Sfx.auto_music = was_auto
	Game.state = was_state
	Game.heat = was_heat
	await TestLib.frames(host, 1)
