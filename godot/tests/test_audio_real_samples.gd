extends RefCounted
## OPEN-SOURCE SOUND (owner round 4: "weapon sounds sound like Tetris"). The synthesised shots, impacts, explosions, footsteps, engines, UI cues and ambience beds were replaced by real CC0
## recordings (tools/audio/real_clips.py cuts them, tools/audio/make_real.py builds the game files, docs/AUDIO_SOURCES.md lists every sample with source URL, author and licence).
## Checked here, from the shipped files and in the REAL scene (main.tscn):
##  * provenance: docs/AUDIO_SOURCES.md and art_sources/audio_<group>/{LICENSE.txt, SOURCE.md} exist, every row says CC0 and carries a URL, every committed clip is listed;
##  * every weapon of WeaponDefs resolves to a shipped sound, the repeating classes have several different takes (an 18 rounds / s minigun does not machine-gun one sample), the takes are
##    different recordings, loud and below the ceiling, and a recording of a real gun is not a pure tone (a share of its energy lies above 1 kHz in its first 40 ms);
##  * families: footsteps per surface, impacts per material, explosions, engines (loops), UI cues and the ambience beds all load through Sfx with the shape the mix expects;
##  * the audio folder stays inside its size budget (the number is printed);
##  * live: each hitscan weapon of the real game plays its own sound through the real PlayerWeapon.
## Waits on state, never frame counts; user:// state is reset. Run: tools/test.sh tests/test_audio_real_samples.gd

const DIR := "res://assets/audio/"
const TMP := "user://test_audio_real_samples.cfg"
const BUDGET_MB := 25.0                     ## 24 MB before wave 113: the 19 weapon sound sets of the roster (tools/audio/make_weapons_v3.py: 4 takes each, 0.7 MB) are the only addition
## Sound names whose takes must be several different recordings.
const TAKES := {&"shot": 4, &"shot_twin": 3, &"shot_rev": 3, &"shot_scatter": 3, &"shot_mini": 4, &"shot_burst": 4, &"shot_flux": 3, &"shot_arc": 2, &"shot_rail": 2, &"shot_gravity": 2,
		&"shot_supp": 2, &"shot_oc": 2, &"shot_far": 2, &"enemy_shot": 3, &"enemy_shot_far": 2, &"step_asphalt": 6, &"step_metal": 6, &"step_stairs": 4, &"step_tile": 4, &"step_carpet": 4, &"step_roof": 4,
		&"impact_flesh": 4, &"impact_concrete": 4, &"impact_metal": 4, &"impact_glass": 4, &"impact_asphalt": 4, &"boom": 4, &"explosion_small": 2, &"car_crash": 3, &"car_bump": 3, &"ricochet": 4, &"whizz": 4}
const FAMILY_LEN := {&"step_asphalt": [0.09, 0.8], &"step_metal": [0.09, 0.8], &"impact_flesh": [0.2, 1.2], &"impact_metal": [0.2, 1.5], &"impact_concrete": [0.2, 1.2], &"boom": [1.5, 5.0],
		&"explosion_small": [1.0, 3.0], &"car_crash": [1.0, 3.0], &"engine_start": [1.0, 2.5], &"horn": [0.4, 1.2]}
const BEDS: Array[StringName] = [&"rain_asphalt", &"rain_metal", &"rain_awning", &"traffic_far", &"wind", &"city_hum"]


func run(host: Node) -> void:
	_test_provenance()
	_test_weapon_files()
	_test_families()
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


## Share of the energy of the first `ms` after the onset that lies ABOVE a one-pole high-pass at `fc`: a real gun's crack is broadband, a sine thump is not.
func _high_share(x: PackedFloat32Array, fc: float, ms: float) -> float:
	var pk := 0.0
	for v in x:
		pk = maxf(pk, absf(v))
	var i0 := 0
	while i0 < x.size() and absf(x[i0]) < pk * 0.0316:
		i0 += 1
	var a := 1.0 - exp(-TAU * fc / 44100.0)
	var lp := 0.0
	var e_hi := 0.0
	var e_all := 0.0
	var n := mini(int(ms * 44.1), x.size() - i0)
	for i in n:
		var s := x[i0 + i]
		lp += a * (s - lp)
		e_hi += (s - lp) * (s - lp)
		e_all += s * s
	return e_hi / maxf(e_all, 1e-12)


## Correlation at lag 0 of the first n samples (1 = the same recording, about 0 = unrelated).
func _corr(a: PackedFloat32Array, b: PackedFloat32Array, n: int) -> float:
	n = mini(n, mini(a.size(), b.size()))
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in n:
		sab += a[i] * b[i]
		saa += a[i] * a[i]
		sbb += b[i] * b[i]
	return sab / maxf(sqrt(saa * sbb), 1e-12)


func _take_names(base: String) -> Array[String]:
	var out: Array[String] = []
	for ext in ["wav", "ogg"]:
		if FileAccess.file_exists(DIR + base + "." + ext):
			out.append(base + "." + ext)
			break
	for k in 16:
		for ext in ["wav", "ogg"]:
			if FileAccess.file_exists("%s%s_%d.%s" % [DIR, base, k, ext]):
				out.append("%s_%d.%s" % [base, k, ext])
				break
	return out


func _repo_file(rel: String) -> String:
	## a file of the repository outside the Godot project (docs/, art_sources/); empty when the test runs from a bare export
	var p := ProjectSettings.globalize_path("res://").path_join("../" + rel).simplify_path()
	return FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""


# ------------------------------------------------------------------ provenance
func _test_provenance() -> void:
	var doc := _repo_file("docs/AUDIO_SOURCES.md")
	TestLib.check(doc.length() > 5000, "docs/AUDIO_SOURCES.md exists and lists the samples (%d bytes)" % doc.length())
	var rows := 0
	var bad_rows: Array[String] = []
	for line in doc.split("\n"):
		if line.begins_with("| art_sources/audio_"):
			rows += 1
			var cols := line.split("|")
			if cols.size() < 7 or not String(cols[3]).contains("https://opengameart.org/content/") or not String(cols[5]).contains("CC0") or String(cols[4]).strip_edges().is_empty():
				bad_rows.append(String(cols[1]).strip_edges())
	TestLib.check(rows >= 150 and bad_rows.is_empty(), "AUDIO_SOURCES.md: %d samples, each with a source URL, an author and the licence CC0 (bad: %s)" % [rows, str(bad_rows.slice(0, 5))])
	var groups := ["firearm_library", "gunshot_singles", "explosion_singles", "breaking_falling_75", "impact_punch", "kenney_scifi", "kenney_interface", "scifi_number99", "cc0_100", "footsteps", "vehicles", "swishes", "ui_sounds", "ambience"]
	var missing: Array[String] = []
	for g in groups:
		var lic := _repo_file("art_sources/audio_%s/LICENSE.txt" % g)
		var src := _repo_file("art_sources/audio_%s/SOURCE.md" % g)
		if not lic.contains("CC0") or not src.contains("https://opengameart.org/content/"):
			missing.append(g)
	TestLib.check(missing.is_empty(), "every audio pack keeps its LICENSE.txt (CC0) and SOURCE.md (page URL) in art_sources (missing: %s)" % str(missing))
	var third := _repo_file("docs/THIRD_PARTY.md")
	TestLib.check(third.contains("AUDIO_SOURCES.md") and third.contains("Free Firearm Sound Library"), "docs/THIRD_PARTY.md credits the audio packs and points at the table")
	var man := FileAccess.get_file_as_string(DIR + "real_manifest.json")
	var data: Variant = JSON.parse_string(man)
	TestLib.check(data is Dictionary and (data as Dictionary).get("built", []).size() >= 150, "the build manifest lists the sounds made from real clips (%d)" % ((data as Dictionary).get("built", []).size() if data is Dictionary else 0))


# ------------------------------------------------------------------ weapons
func _test_weapon_files() -> void:
	var missing: Array[String] = []
	var snd_names: Dictionary = {}
	for id: StringName in WeaponDefs.IDS:
		var d: Dictionary = WeaponDefs.DEFS[id]
		var snd := StringName(d.get("snd", &"shot"))
		snd_names[snd] = true
		if _take_names(String(snd)).is_empty():
			missing.append("%s -> %s" % [id, snd])
	TestLib.check(missing.is_empty(), "all %d weapons (%d sound classes) resolve to shipped sounds (missing: %s)" % [WeaponDefs.IDS.size(), snd_names.size(), str(missing)])
	TestLib.check(snd_names.size() >= 11, "the arsenal uses %d distinct shot sounds (at least 11 classes)" % snd_names.size())
	var few: Array[String] = []
	for k: StringName in TAKES:
		var n := _take_names(String(k)).size()
		if n < int(TAKES[k]):
			few.append("%s %d of %d" % [k, n, int(TAKES[k])])
	TestLib.check(few.is_empty(), "every repeating sound has its takes (a minigun does not machine-gun one sample; short: %s)" % str(few))
	# the takes of a class are different recordings, not copies
	var copies: Array[String] = []
	for k in [&"shot", &"shot_twin", &"shot_mini", &"shot_burst", &"shot_rev", &"shot_scatter", &"step_asphalt", &"step_metal", &"impact_flesh", &"impact_metal"]:
		var names := _take_names(String(k))
		var xs: Array[PackedFloat32Array] = []
		for nm in names:
			if nm.ends_with(".wav"):
				xs.append(_pcm(DIR + nm))
		for i in xs.size():
			for j in range(i + 1, xs.size()):
				if absf(_corr(xs[i], xs[j], 4000)) > 0.9:
					copies.append("%s %d~%d" % [k, i, j])
	TestLib.check(copies.is_empty(), "the takes of a class are different recordings (near copies: %s)" % str(copies))
	# loud, dense, below the one-shot ceiling; a real gun has a crack (energy above 1 kHz), a synthesised sine thump has none
	var weak: Array[String] = []
	var tall: Array[String] = []
	var dull: Array[String] = []
	var nshots := 0
	for k in [&"shot", &"shot_twin", &"shot_rev", &"shot_scatter", &"shot_mini", &"shot_burst", &"enemy_shot"]:
		for nm in _take_names(String(k)):
			var x := _pcm(DIR + nm)
			if x.is_empty():
				continue
			nshots += 1
			var rms := _rms_db(x, 250.0)
			var pk := _peak_db(x)
			if rms < -24.0:
				weak.append("%s %.1f" % [nm, rms])
			if pk > -9.0 or pk < -20.0:
				tall.append("%s %.1f" % [nm, pk])
			if _high_share(x, 1000.0, 40.0) < 0.04:
				dull.append(nm)
	TestLib.check(nshots >= 24 and weak.is_empty() and tall.is_empty(), "%d gun takes are loud (RMS of the first 250 ms at least -24 dBFS) and below -9 dBFS (weak: %s, tall: %s)" % [nshots, str(weak), str(tall)])
	TestLib.check(dull.is_empty(), "every gun take has a broadband crack, not a pure thump (4 %% of its first 40 ms above 1 kHz; dull: %s)" % str(dull))


# ------------------------------------------------------------------ families through Sfx
func _test_families() -> void:
	var off: Array[String] = []
	for k: StringName in FAMILY_LEN:
		var win: Array = FAMILY_LEN[k]
		var vs := Sfx.variants_of(k)
		if vs.is_empty():
			off.append("%s (none)" % k)
			continue
		for s in vs:
			if s.get_length() < float(win[0]) or s.get_length() > float(win[1]):
				off.append("%s %.2f s" % [k, s.get_length()])
	TestLib.check(off.is_empty(), "footsteps, impacts, explosions, crashes, engine start and horn have the lengths a real recording gives them (outside: %s)" % str(off))
	# engines: seamless loops of whole engine cycles, long enough, re-pitched variants for bike and heavy
	var bad_loop: Array[String] = []
	for k in [&"engine_low", &"engine_high", &"engine_bike_low", &"engine_bike_high", &"engine_heavy_low", &"engine_heavy_high"]:
		var x := _pcm(DIR + String(k) + ".wav")
		var s := Sfx.variants_of(k)
		var w := (s[0] as AudioStreamWAV) if not s.is_empty() else null
		if x.size() < 44100 or w == null or w.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			bad_loop.append(String(k))
			continue
		var step := 0.0
		for i in range(1, x.size()):
			step = maxf(step, absf(x[i] - x[i - 1]))
		if absf(x[0] - x[x.size() - 1]) > 1.5 * step:
			bad_loop.append(String(k) + " seam")
	TestLib.check(bad_loop.is_empty(), "the six engine loops are real recordings of whole cycles, seamless and over a second (bad: %s)" % str(bad_loop))
	TestLib.check(not Sfx.variants_of(&"engine_low").is_empty() and not Sfx.variants_of(&"tyre_squeal").is_empty(), "the engine and the tyre loops the driving code asks for exist")
	# UI cues: every cue Sfx maps to a shipped file, short and below the ceiling
	var ui_bad: Array[String] = []
	for cue: StringName in Sfx.UI_CUES:
		var nm := String(Sfx.UI_CUES[cue])
		var vs := _take_names(nm)
		if vs.is_empty() or not vs[0].ends_with(".wav"):
			ui_bad.append(nm)
			continue
		var x := _pcm(DIR + vs[0])
		if x.size() / 44100.0 > 1.0 or _peak_db(x) > -9.0:
			ui_bad.append(nm)
	TestLib.check(ui_bad.is_empty(), "all %d UI cues are shipped, short and below the ceiling (bad: %s)" % [Sfx.UI_CUES.size(), str(ui_bad)])
	# ambience beds: real recordings made seamless, 24 s mono OGG
	var bed_bad: Array[String] = []
	for b in BEDS:
		var o := load(DIR + String(b) + ".ogg") as AudioStreamOggVorbis
		if o == null or absf(o.get_length() - 24.0) > 0.3:
			bed_bad.append(String(b))
	TestLib.check(bed_bad.is_empty(), "the six ambience beds are 24 s OGG loops (bad: %s)" % str(bed_bad))
	# size budget
	var total := 0
	for n in DirAccess.get_files_at(DIR):
		if n.ends_with(".wav") or n.ends_with(".ogg"):
			total += FileAccess.open(DIR + n, FileAccess.READ).get_length()
	var mb := float(total) / 1048576.0
	print("  audio folder: %.2f MB (budget %.0f MB)" % [mb, BUDGET_MB])
	TestLib.check(mb <= BUDGET_MB, "the audio folder is %.1f MB, inside the %.0f MB budget" % [mb, BUDGET_MB])


# ------------------------------------------------------------------ the live game
func _test_live(host: Node) -> void:
	Sfx.muted = false
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
	var w: PlayerWeapon = p.weapon
	var tried := 0
	var wrong: Array[String] = []
	var silent: Array[String] = []
	for id: StringName in WeaponDefs.IDS:
		var d: Dictionary = WeaponDefs.DEFS[id]
		if String(d.get("kind", "")) != "hit":
			continue
		WeaponDefs.unlock(id)
		if not w.switch_to(id, true):
			continue
		tried += 1
		w.ammo = w.mag
		w.fire_t = 0.0
		w.reload_t = 0.0
		Sfx.last_played = &""
		Sfx._last_start.clear()
		w._shoot(0.016, false)
		var want := StringName(d.get("snd", &"shot"))
		var vs := Sfx.variants_of(want)
		if Sfx.last_played == &"":
			silent.append(String(id))
		elif not _playing_flat_with(vs):                     # a shotgun also starts a muzzle blast after its shot: look for the shot among the voices playing
			wrong.append("%s played %s, wanted %s" % [id, Sfx.last_played, want])
		if vs.is_empty() or not (vs[0] is AudioStreamWAV or vs[0] is AudioStreamOggVorbis):
			wrong.append("%s has no stream" % want)
	for pl in Sfx._players:
		pl.stop()
	TestLib.check(tried >= 8, "the live weapon fired %d hitscan weapons of the arsenal" % tried)
	TestLib.check(silent.is_empty() and wrong.is_empty(), "each hitscan weapon plays its own recorded sound through PlayerWeapon (silent: %s, wrong: %s)" % [str(silent), str(wrong)])
	# a minigun burst picks different takes (the engine never plays the same take twice in a row)
	var seen: Dictionary = {}
	var last: Variant = null
	var repeats := 0
	for i in 40:
		var s: Variant = Sfx._pick(&"shot_mini")
		if s == last:
			repeats += 1
		seen[s] = true
		last = s
	TestLib.check(seen.size() >= 4 and repeats == 0, "40 minigun rounds use %d different takes and never the same one twice in a row (%d repeats)" % [seen.size(), repeats])
	# footsteps of the live hero come from the new surface sets
	for surf in [&"step_asphalt", &"step_metal", &"step_stairs"]:
		TestLib.check(Sfx.variants_of(surf).size() >= 4, "%s has %d takes in the live Sfx" % [surf, Sfx.variants_of(surf).size()])
	Attachments.reset()
	for f: String in [TMP, TMP + ".bak", TMP + ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	main.queue_free()
	await TestLib.frames(host, 2)


func _playing_flat_with(streams: Array) -> bool:
	for pl in Sfx._players:
		if pl.playing and streams.has(pl.stream):
			return true
	return false
