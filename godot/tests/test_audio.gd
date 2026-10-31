extends RefCounted
## AUDIO module test: the sound catalogue (variant counts, formats, durations, peak levels), loop continuity, the bus layout, per-bus volume, mute, ducking, voice pools and
## caps, a 20-shot firefight summed numerically (peak and RMS), the adaptive music states and their game hooks, the hero / vehicle / quantum / radio hooks and the lifecycle reset.
## Run: tools/test.sh tests/test_audio.gd   (tools/audio/check_audio.py checks the committed files, OGG included, and the whole mix with the music)

const SR := 44100
## group -> [minimum variants, shortest seconds, longest seconds] (WAV one-shots; every variant must satisfy the duration and the level window)
const GROUPS := {
	&"step_asphalt": [4, 0.15, 0.7], &"step_metal": [4, 0.15, 0.8], &"step_stairs": [4, 0.2, 0.9], &"land_asphalt": [2, 0.15, 0.7], &"land_metal": [2, 0.2, 0.8],
	&"shot": [4, 0.3, 1.5], &"enemy_shot": [3, 0.2, 1.2], &"shot_far": [2, 1.0, 2.5], &"enemy_shot_far": [2, 1.0, 2.5], &"dry_fire": [2, 0.1, 0.4], &"reload": [3, 0.8, 2.0],
	&"impact_concrete": [4, 0.2, 1.2], &"impact_metal": [4, 0.3, 1.5], &"impact_glass": [4, 0.3, 1.5], &"impact_flesh": [4, 0.2, 1.2], &"impact_asphalt": [4, 0.2, 1.0],
	&"ricochet": [4, 0.3, 0.9], &"whizz": [4, 0.15, 0.5], &"boom": [4, 1.5, 5.0], &"explosion_small": [2, 1.0, 3.0], &"distant_boom": [2, 1.0, 4.0], &"distant_gunfire": [2, 1.5, 3.5],
	&"trooper_alert": [3, 0.4, 1.5], &"trooper_attack": [3, 0.3, 1.2], &"trooper_pain": [3, 0.2, 1.0], &"trooper_death": [3, 0.8, 2.5],
	&"hero_pain": [3, 0.2, 0.8], &"hero_effort": [3, 0.15, 0.7], &"hero_death": [1, 0.8, 2.0], &"drone_charge": [1, 0.5, 1.5], &"drone_alert": [1, 0.3, 1.0], &"drone_death": [1, 0.8, 2.0],
	&"blink": [3, 0.5, 2.5], &"link": [3, 0.5, 2.5], &"superpos": [1, 0.8, 3.0], &"superpos_enter": [1, 0.8, 2.5], &"quantum_ready": [1, 0.3, 1.0], &"quantum_fail": [1, 0.3, 1.0],
	&"engine_start": [1, 1.0, 2.0], &"car_crash": [3, 1.0, 3.0], &"car_bump": [3, 0.3, 1.0], &"horn": [2, 0.4, 1.2], &"car_door": [1, 0.2, 0.8],
	&"ui_click": [1, 0.05, 0.3], &"ui_tick": [1, 0.03, 0.2], &"ui_confirm": [1, 0.2, 1.0], &"ui_back": [1, 0.2, 1.0], &"ui_error": [1, 0.2, 0.8], &"ui_pause": [1, 0.2, 1.0], &"ui_resume": [1, 0.2, 1.0],
	&"heartbeat": [1, 0.4, 1.2], &"breath_in": [2, 0.3, 1.0], &"breath_out": [2, 0.3, 1.0], &"gasp": [1, 0.2, 0.8], &"radio_open": [1, 0.2, 0.6], &"radio_close": [1, 0.1, 0.5],
	&"radio_glitch": [3, 0.1, 0.6], &"babble": [8, 0.05, 0.2], &"pickup_health": [1, 0.3, 1.5], &"pickup_energy": [1, 0.3, 1.5], &"pickup_ammo": [1, 0.2, 1.0], &"credit": [1, 0.3, 1.5],
	&"mission_start": [1, 0.8, 3.0], &"mission_complete": [1, 1.0, 4.0], &"objective_ping": [1, 0.3, 1.5], &"heat_up": [1, 0.5, 2.0], &"heat_down": [1, 0.5, 2.0],
	&"siren": [2, 2.0, 4.0], &"sting_death": [1, 3.0, 7.0], &"sting_win": [1, 3.0, 8.0],
}
const LOOPS: Array[StringName] = [&"drone_hum", &"radio_static", &"superpos_loop", &"entangle_loop", &"engine_low", &"engine_high", &"tyre_squeal", &"traffic_loop"]
const BEDS: Array[StringName] = [&"rain_asphalt", &"rain_metal", &"rain_awning", &"traffic_far", &"wind", &"city_hum"]
const PEAK_MAX_DB := -9.0            ## every one-shot sits below this (headroom for a dozen of them at once)
const PEAK_MIN_DB := -30.0

const STUB_PLAYER := "extends Node3D\nvar velocity := Vector3(0, 0, 5)\nvar vehicle = null\nvar hp := 100.0\nvar max_hp := 100.0\nvar body = null\nvar quantum = null\nvar air_time := 0.0\n"
const STUB_BODY := "extends Node\nvar loco = null\n"
const STUB_LOCO := "extends RefCounted\nvar footfalls := 0\n"
const STUB_QUANTUM := "extends Node\nvar clone = null\nvar links: Array = []\n"
const STUB_VEHICLES := "extends Node\nvar driven = null\nvar list: Array = []\n"
const STUB_ENEMY := "extends Node3D\nvar aware := false\nvar hp := 60.0\nvar dead := false\nvar type: StringName = &\"operative\"\nvar charge := 0.0\nfunc threat_charge() -> float:\n\treturn charge\n"
const STUB_ENEMIES := "extends Node\nvar list: Array = []\n"
const STUB_CAR := "extends Node3D\nvar speed := 0.0\nvar slip := 0.0\nvar active := true\n"

var _keep: Array = []
var _host: Node


func run(host: Node) -> void:
	_host = host
	var was_muted := Sfx.muted
	var was_auto := Sfx.auto_music
	var was_state := Game.state
	var was_heat := Game.heat
	Sfx.muted = false
	Sfx.auto_music = false
	Sfx.reset_world()
	_catalog()
	_loops()
	_ogg()
	_buses()
	_volume_mute_duck()
	_pools()
	_mix()
	_music_states()
	_music_hooks()
	_hero_hooks()
	_enemy_hooks()
	_vehicle_hooks()
	_quantum_and_ambience()
	_radio()
	_lifecycle()
	Sfx.stop_music()
	Sfx.stop_ambience()
	Sfx.reset_world()
	Sfx.auto_music = was_auto
	Sfx.muted = was_muted
	Game.heat = was_heat
	Game.state = was_state
	Game.player = null
	Game.vehicles = null
	for n in _keep:
		if is_instance_valid(n):
			n.free()
	TestLib.check(true, "audio test finished")


# ------------------------------------------------------------------ helpers
func _wav(stream: AudioStream) -> AudioStreamWAV:
	return stream as AudioStreamWAV


func _pcm(s: AudioStreamWAV) -> PackedFloat32Array:
	var d := s.data
	var out := PackedFloat32Array()
	out.resize(d.size() / 2)
	for i in out.size():
		out[i] = float(d.decode_s16(i * 2)) / 32768.0
	return out


func _peak_db(x: PackedFloat32Array) -> float:
	var p := 0.0
	for v in x:
		p = maxf(p, absf(v))
	return 20.0 * log(maxf(p, 1e-9)) / log(10.0)


func _db(x: float) -> float:
	return 20.0 * log(maxf(x, 1e-9)) / log(10.0)


func _stub(src: String) -> Object:
	var sc := GDScript.new()
	sc.source_code = src
	sc.reload()
	var o: Object = sc.new()
	if o is Node:
		_keep.append(o)
	return o


# ------------------------------------------------------------------ catalogue
func _catalog() -> void:
	var bad_fmt := 0
	var bad_dur := 0
	var bad_peak := 0
	var short_groups: Array[String] = []
	var files := 0
	for g: StringName in GROUPS:
		var spec: Array = GROUPS[g]
		var v := Sfx.variants_of(g)
		if v.size() < int(spec[0]):
			short_groups.append("%s (%d of %d)" % [g, v.size(), int(spec[0])])
		for s in v:
			files += 1
			var w := _wav(s)
			if w == null or w.format != AudioStreamWAV.FORMAT_16_BITS or w.mix_rate != SR or w.stereo:
				bad_fmt += 1
				continue
			var dur := w.get_length()
			if dur < float(spec[1]) or dur > float(spec[2]):
				bad_dur += 1
				printerr("  duration of %s: %.2f s outside %.2f..%.2f" % [g, dur, spec[1], spec[2]])
			var pk := _peak_db(_pcm(w))
			if pk > PEAK_MAX_DB or pk < PEAK_MIN_DB:
				bad_peak += 1
				printerr("  peak of %s: %.1f dBFS" % [g, pk])
	TestLib.check(short_groups.is_empty(), "every sound group has its variants (%s)" % ("all %d groups" % GROUPS.size() if short_groups.is_empty() else ", ".join(short_groups)))
	TestLib.check(bad_fmt == 0, "%d one-shot files are 44.1 kHz mono 16-bit WAV (%d wrong)" % [files, bad_fmt])
	TestLib.check(bad_dur == 0, "every one-shot has a plausible duration (%d outside its range)" % bad_dur)
	TestLib.check(bad_peak == 0, "every one-shot peaks between %.0f and %.0f dBFS (%d outside)" % [PEAK_MIN_DB, PEAK_MAX_DB, bad_peak])
	TestLib.check(Sfx.variants_of(&"does_not_exist").is_empty(), "an unknown name has no variants (callers are silently ignored)")
	TestLib.check(Sfx.variants_of(&"step_asphalt").size() >= 4 and Sfx.variants_of(&"step_metal").size() >= 4 and Sfx.variants_of(&"step_stairs").size() >= 4, "footsteps: 4+ variants each on asphalt, metal and stairs")
	TestLib.check(Sfx.variants_of(&"shot").size() >= 4 and Sfx.variants_of(&"enemy_shot").size() >= 3, "weapon shots have layered variants")
	# the originals are still variant 0 of their families, unchanged (their own levels are checked by test_assets)
	TestLib.check(Sfx.variants_of(&"boom")[0].resource_path.ends_with("boom.wav") and Sfx.variants_of(&"link")[0].resource_path.ends_with("link.wav"), "the original sounds stay variant 0 of their families")


func _loops() -> void:
	var bad_loop := 0
	var bad_seam := 0
	for n in LOOPS:
		var w := _wav(Sfx.variants_of(n)[0] if not Sfx.variants_of(n).is_empty() else null)
		if w == null:
			bad_loop += 1
			continue
		if w.loop_mode != AudioStreamWAV.LOOP_FORWARD or w.get_length() < 0.9:
			bad_loop += 1
		var x := _pcm(w)
		var max_step := 0.0
		for i in range(1, x.size()):
			max_step = maxf(max_step, absf(x[i] - x[i - 1]))
		var seam := absf(x[0] - x[x.size() - 1])
		if seam > 1.5 * max_step:
			bad_seam += 1
			printerr("  loop seam of %s: %.4f vs steepest step %.4f" % [n, seam, max_step])
	TestLib.check(bad_loop == 0, "%d loops (engine, tyres, drone, radio static, quantum) loop forward and last longer than a second (%d wrong)" % [LOOPS.size(), bad_loop])
	TestLib.check(bad_seam == 0, "loop continuity: the jump across every loop seam is no larger than the steepest step inside it (%d clicks)" % bad_seam)


func _ogg() -> void:
	var ok := 0
	var lens := PackedFloat32Array()
	for n in BEDS:
		var s := Sfx.variants_of(n)
		if not s.is_empty() and s[0] is AudioStreamOggVorbis and absf((s[0] as AudioStreamOggVorbis).get_length() - 24.0) < 0.3:
			ok += 1
	TestLib.check(ok == BEDS.size(), "%d ambience beds (rain on three surfaces, traffic, wind, city hum) are 24 s OGG loops (%d of %d)" % [BEDS.size(), ok, BEDS.size()])
	var th := Sfx.variants_of(&"thunder")
	TestLib.check(th.size() == 3 and (th[0] is AudioStreamOggVorbis) and (th[0] as AudioStreamOggVorbis).get_length() > 5.0, "three thunder rolls")
	var stems_ok := true
	for st in Sfx.STEMS:
		var s := Sfx.variants_of(StringName("music_" + String(st)))
		if s.is_empty() or not (s[0] is AudioStreamOggVorbis):
			stems_ok = false
			continue
		lens.append((s[0] as AudioStreamOggVorbis).get_length())
	TestLib.check(stems_ok and lens.size() == 5, "the five music stems (pad, pulse, bass, perc, lead) are OGG files")
	var same := lens.size() == 5
	for l in lens:
		same = same and absf(l - lens[0]) < 0.01 and absf(l - 30.0) < 0.1
	TestLib.check(same, "all stems are exactly one 30 s loop long, so they stay sample-locked (%s)" % str(lens))


# ------------------------------------------------------------------ buses, volume, mute, ducking
func _buses() -> void:
	var idx := {}
	for b in Sfx.BUS_NAMES:
		idx[b] = AudioServer.get_bus_index(b)
	TestLib.check(idx.values().all(func(i: int) -> bool: return i >= 0), "buses Master, SFX, Music, Ambient and Voice exist")
	TestLib.check(AudioServer.get_bus_effect(idx[&"Master"], 0) is AudioEffectLimiter, "Master ends in a limiter")
	TestLib.check(AudioServer.get_bus_effect(idx[&"SFX"], 0) is AudioEffectCompressor, "SFX has a compressor")
	TestLib.check(AudioServer.get_bus_effect(idx[&"Music"], 0) is AudioEffectLowPassFilter and AudioServer.get_bus_effect(idx[&"Ambient"], 0) is AudioEffectLowPassFilter, "Music and Ambient have a low-pass for muffling")
	var sends_ok := true
	for b: StringName in [&"SFX", &"Music", &"Ambient", &"Voice"]:
		sends_ok = sends_ok and AudioServer.get_bus_send(idx[b]) == &"Master"
	TestLib.check(sends_ok, "every bus feeds Master")


func _volume_mute_duck() -> void:
	var m := AudioServer.get_bus_index(&"Music")
	var s := AudioServer.get_bus_index(&"SFX")
	Sfx.set_bus_volume(&"Music", 0.5)
	TestLib.check(absf(AudioServer.get_bus_volume_db(m) - (-6.02)) < 0.1, "per-bus volume: Music at 50%% is %.1f dB" % AudioServer.get_bus_volume_db(m))
	Sfx.apply_volumes({"SFX": 0.25, "Nonsense": 0.1})
	TestLib.check(absf(AudioServer.get_bus_volume_db(s) - (-12.04)) < 0.1 and absf(Sfx.volumes()["SFX"] - 0.25) < 0.02, "apply_volumes() sets the saved volumes (SFX 25%% = %.1f dB), unknown buses are ignored" % AudioServer.get_bus_volume_db(s))
	Sfx.set_bus_volume(&"Music", 1.0)
	Sfx.set_bus_volume(&"SFX", 1.0)
	TestLib.check(absf(AudioServer.get_bus_volume_db(m)) < 0.05 and absf(AudioServer.get_bus_volume_db(s)) < 0.05, "volumes return to 0 dB")
	# ducking
	Sfx.reset_world()
	Sfx.duck(&"explosion")
	Sfx._step_ducks(0.1)
	var music_db := Sfx.effective_bus_db(&"Music")
	TestLib.check(absf(music_db - (-9.0)) < 0.5 and Sfx.effective_bus_db(&"Ambient") < -10.0 and absf(Sfx.effective_bus_db(&"SFX")) < 0.01, "an explosion ducks Music (%.1f dB) and Ambient, not the effects" % music_db)
	TestLib.check(absf(AudioServer.get_bus_volume_db(m) - music_db) < 0.2, "the duck reaches the real bus (%.1f dB)" % AudioServer.get_bus_volume_db(m))
	Sfx._step_ducks(1.0)                                                         # the hold runs out ...
	var mid := Sfx.duck_amount(&"explosion")
	Sfx._step_ducks(1.0)
	var later := Sfx.duck_amount(&"explosion")
	Sfx._step_ducks(3.0)
	TestLib.check(mid > later and later > 0.0 and Sfx.duck_amount(&"explosion") == 0.0 and absf(Sfx.effective_bus_db(&"Music")) < 0.01, "the duck releases slowly (%.2f -> %.2f -> 0) and the music comes fully back" % [mid, later])
	Sfx.duck(&"radio")
	Sfx._step_ducks(0.5)
	TestLib.check(Sfx.effective_bus_db(&"SFX") < -2.0 and Sfx.effective_bus_db(&"Music") < -6.0, "the radio ducks the music, the ambience and a little of the effects")
	Sfx.reset_world()
	# mute
	Sfx.muted = true
	TestLib.check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master")), "mute mutes the Master bus")
	var before := Sfx.voices_in_use()
	Sfx.play(&"shot")
	Sfx.play_at(&"boom", Vector3.ZERO)
	TestLib.check(Sfx.voices_in_use() == before, "a muted Sfx starts no voices")
	Sfx.muted = false
	TestLib.check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master")), "unmuting restores the Master bus")


# ------------------------------------------------------------------ voices
func _count_family(players: Array, fams: Array[String], fam: String) -> int:
	var n := 0
	for i in players.size():
		if players[i].playing and fams[i] == fam:
			n += 1
	return n


func _stop_all() -> void:
	for p in Sfx._players:
		p.stop()
	for p3 in Sfx._players3d:
		p3.stop()
	Sfx._last_start.clear()


func _pools() -> void:
	_stop_all()
	for i in 40:
		Sfx._last_start.clear()
		Sfx.play(&"shot")
	var shots := _count_family(Sfx._players, Sfx._fam_flat, "shot")
	TestLib.check(shots > 0 and shots <= 6, "40 shots in one frame use at most 6 voices (the family cap): %d" % shots)
	_stop_all()
	Sfx.play(&"shot")
	Sfx.play(&"shot")
	TestLib.check(_count_family(Sfx._players, Sfx._fam_flat, "shot") == 1, "two shots closer than the minimum gap start one voice")
	_stop_all()
	var total := 0
	for rep in 3:
		for n: StringName in [&"shot", &"impact_concrete", &"step_asphalt", &"whizz", &"ricochet", &"trooper_pain", &"enemy_shot", &"blink", &"pickup_health", &"drone_charge", &"engine_start", &"heartbeat", &"breath_in"]:
			Sfx._last_start.clear()
			Sfx.play(n)
	total = Sfx.voices_in_use()
	TestLib.check(total <= Sfx.POOL, "a crowd of sounds never exceeds the pool (%d of %d voices)" % [total, Sfx.POOL])
	Sfx._last_start.clear()
	Sfx.play(&"boom")
	TestLib.check(_count_family(Sfx._players, Sfx._fam_flat, "boom") == 1, "an explosion always gets a voice: it steals one from a less important sound")
	_stop_all()
	for i in 30:
		Sfx._last_start.clear()
		Sfx.play_at(&"boom", Vector3(float(i), 0.0, 0.0))
	var booms := _count_family(Sfx._players3d, Sfx._fam_3d, "boom")
	var all3d := 0
	for p3 in Sfx._players3d:
		all3d += 1 if p3.playing else 0
	TestLib.check(booms > 0 and booms <= 3 and all3d <= Sfx.POOL_3D, "positional explosions: at most 3 voices (%d), pool %d of %d" % [booms, all3d, Sfx.POOL_3D])
	_stop_all()
	var seen := {}
	for i in 24:
		Sfx._last_start.clear()
		Sfx.play(&"step_asphalt")
		for p in Sfx._players:
			if p.playing and p.stream != null:
				seen[p.stream.resource_path] = true
		for p in Sfx._players:
			p.stop()
	TestLib.check(seen.size() >= 4, "footsteps rotate through their variants (%d different files in 24 steps)" % seen.size())
	_stop_all()


# ------------------------------------------------------------------ the mix: a 20-shot firefight, summed
## Sums events the way Sfx would play them (family caps cut the family's oldest voice, the 20-voice pool steals the oldest of lower or equal priority) and returns the buffer.
func _simulate(events: Array, seconds: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int(seconds * SR))
	var live: Array = []                                         # {fam, prio, start, end, pcm, gain}
	var last := {}
	events.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
	for e: Array in events:
		var t: float = e[1]
		var rule: Array = Sfx._rule(e[0])
		var fam: String = rule[0]
		if t - float(last.get(fam, -100.0)) < float(rule[3]):
			continue
		last[fam] = t
		if not _pcm_cache.has(e[0]):
			_pcm_cache[e[0]] = _pcm(Sfx.variants_of(e[0])[0] as AudioStreamWAV)
		var pcm: PackedFloat32Array = _pcm_cache[e[0]]
		var start := int(t * SR)
		live = live.filter(func(v: Dictionary) -> bool: return int(v["end"]) > start)
		var same := live.filter(func(v: Dictionary) -> bool: return v["fam"] == fam)
		if same.size() >= int(rule[2]):
			var old: Dictionary = same[0]
			for v: Dictionary in same:
				if int(v["start"]) < int(old["start"]):
					old = v
			old["end"] = start
			live = live.filter(func(v: Dictionary) -> bool: return int(v["end"]) > start)
		if live.size() >= Sfx.POOL:
			var victim: Dictionary = {}
			for v: Dictionary in live:
				if int(v["prio"]) <= int(rule[1]) and (victim.is_empty() or int(v["prio"]) < int(victim["prio"]) or (int(v["prio"]) == int(victim["prio"]) and int(v["start"]) < int(victim["start"]))):
					victim = v
			if victim.is_empty():
				continue
			victim["end"] = start
			live = live.filter(func(v: Dictionary) -> bool: return int(v["end"]) > start)
		live.append({"fam": fam, "prio": int(rule[1]), "start": start, "end": start + pcm.size(), "pcm": pcm, "gain": db_to_linear(float(e[2]))})
		var v2: Dictionary = live[live.size() - 1]
		_accumulate(buf, v2)
	return buf


## Summing is done once the cut points are final: re-run with the recorded ends. (Simple approach: accumulate now and subtract the cut tail when a voice is cut.)
func _accumulate(buf: PackedFloat32Array, v: Dictionary) -> void:
	v["acc"] = true
	var pcm: PackedFloat32Array = v["pcm"]
	var g: float = v["gain"]
	var s: int = v["start"]
	for i in pcm.size():
		if s + i >= buf.size():
			break
		buf[s + i] += pcm[i] * g
	_cuts.append(v)


var _cuts: Array = []
var _pcm_cache := {}


func _mix() -> void:
	# A 3 s firefight: 20 shots at the fire interval, 4 enemy shots, 8 impacts, 4 whizzes, a trooper's pain and alert, steps, 1 explosion, a hurt. Cut voices are
	# subtracted from the buffer afterwards (their tail would not have played).
	var ev: Array = []
	for k in 20:
		ev.append([&"shot", k * 0.11, -2.0])
	for k in 4:
		ev.append([&"enemy_shot", 0.3 + k * 0.5, -4.0])
	for k in 8:
		ev.append([&"impact_flesh" if k % 3 == 0 else (&"impact_concrete" if k % 3 == 1 else &"impact_metal"), 0.2 + k * 0.25, -2.0])
	for k in 4:
		ev.append([&"whizz", 0.4 + k * 0.5, -4.0])
	ev.append_array([[&"trooper_pain", 0.5, 0.0], [&"trooper_alert", 1.4, 0.0], [&"step_asphalt", 0.3, -6.0], [&"step_asphalt", 0.7, -6.0], [&"boom", 1.0, -3.0], [&"hurt", 1.2, 0.0], [&"reload", 2.3, 0.0]])
	_cuts.clear()
	var buf := _simulate_cut(ev, 5.0)
	var peak := 0.0
	var sum_sq := 0.0
	var n_rms := 0
	for i in int(3.2 * SR):
		var v := absf(buf[i])
		peak = maxf(peak, v)
		sum_sq += buf[i] * buf[i]
		n_rms += 1
	var rms := sqrt(sum_sq / float(n_rms))
	TestLib.check(peak < 0.89, "a 20-shot firefight with hits, an explosion and voices sums to %.1f dBFS peak before the limiter (below -1: no clipping)" % _db(peak))
	TestLib.check(_db(rms) > -40.0 and _db(rms) < -14.0, "its RMS is %.1f dBFS (audible, and far from squashed)" % _db(rms))
	# sustained fire for 10 s
	var rapid: Array = []
	for k in 90:
		rapid.append([&"shot", k * 0.11, -2.0])
	_cuts.clear()
	var buf2 := _simulate_cut(rapid, 11.0)
	var pk2 := 0.0
	for v in buf2:
		pk2 = maxf(pk2, absf(v))
	TestLib.check(pk2 < 0.7, "10 s of sustained rifle fire peaks at %.1f dBFS (below -3)" % _db(pk2))


## _simulate() with the cut voices removed again from the buffer (their ends were shortened after they had been summed).
func _simulate_cut(events: Array, seconds: float) -> PackedFloat32Array:
	var buf := _simulate(events, seconds)
	for v: Dictionary in _cuts:
		var pcm: PackedFloat32Array = v["pcm"]
		var natural := int(v["start"]) + pcm.size()
		if int(v["end"]) < natural:
			var g: float = v["gain"]
			for i in range(int(v["end"]) - int(v["start"]), pcm.size()):
				var at := int(v["start"]) + i
				if at < buf.size():
					buf[at] -= pcm[i] * g
	return buf


# ------------------------------------------------------------------ music
func _targets_audible(state: StringName) -> int:
	var n := 0
	for i in 5:
		n += 1 if float(Sfx.MUSIC_STATES[state][i]) > -20.0 else 0
	return n


func _music_states() -> void:
	Sfx.stop_music()
	Sfx.play_music()
	TestLib.check(Sfx.is_music_playing() and Sfx._music.stream is AudioStreamSynchronized and (Sfx._music.stream as AudioStreamSynchronized).stream_count == 5, "play_music() starts five stems under one synchronized stream")
	var states: Array[StringName] = [&"menu", &"explore", &"alert", &"combat", &"driving", &"death", &"win"]
	var all_ok := true
	for st in states:
		Sfx.set_music_state(st, true)
		for i in 5:
			all_ok = all_ok and absf(Sfx.stem_db(i) - float(Sfx.MUSIC_STATES[st][i])) < 0.01 and absf(Sfx.stem_target_db(i) - float(Sfx.MUSIC_STATES[st][i])) < 0.01
	TestLib.check(all_ok and Sfx.music_state == &"win", "all seven music states (menu, explore, alert, combat, driving, death, win) set the stem levels they define")
	TestLib.check(_targets_audible(&"combat") == 5 and _targets_audible(&"alert") > _targets_audible(&"explore") and _targets_audible(&"combat") > _targets_audible(&"alert") and _targets_audible(&"death") == 1,
			"intensity grows: explore %d, alert %d, combat %d stems; death keeps only the pad" % [_targets_audible(&"explore"), _targets_audible(&"alert"), _targets_audible(&"combat")])
	Sfx.set_music_state(&"explore", true)
	Sfx.set_music_state(&"combat")
	var before := Sfx.stem_db(3)
	Sfx._step_music(0.1)
	var after_one := Sfx.stem_db(3)
	for i in 40:
		Sfx._step_music(0.1)
	TestLib.check(before < -50.0 and after_one > before and after_one < -10.0 and absf(Sfx.stem_db(3) - 0.0) < 0.2, "explore to combat crossfades (perc %.0f -> %.1f -> %.1f dB) instead of cutting" % [before, after_one, Sfx.stem_db(3)])
	var jump := 0.0
	Sfx.set_music_state(&"explore", true)
	Sfx.set_music_state(&"combat")
	for i in 30:
		var prev := Sfx.stem_db(1)
		Sfx._step_music(1.0 / 60.0)
		jump = maxf(jump, absf(Sfx.stem_db(1) - prev))
	TestLib.check(jump < 1.0, "stem levels move smoothly frame to frame (largest step %.2f dB)" % jump)
	Sfx.set_music_state(&"explore", true)
	Sfx._sting.stop()
	Sfx.set_music_state(&"death")
	var death_sting: bool = Sfx._sting.playing and Sfx._sting.stream != null
	Sfx._sting.stop()
	Sfx.set_music_state(&"win")
	var win_sting: bool = Sfx._sting.playing and Sfx._sting.stream != null
	Sfx._sting.stop()
	TestLib.check(death_sting and win_sting, "death and win each play their own sting")
	Sfx.set_music_state(&"nonsense")
	TestLib.check(Sfx.music_state == &"win", "an unknown state is ignored")


func _music_hooks() -> void:
	Sfx.auto_music = true
	Game.state = &"play"
	Game.heat = 0.0
	Sfx.set_music_state(&"explore", true)
	Sfx._poll_music_state()
	TestLib.check(Sfx.music_state == &"explore", "calm: explore")
	Game.heat = 1.5
	Sfx._poll_music_state()
	TestLib.check(Sfx.music_state == &"alert", "heat 1.5: alert")
	Game.heat = 3.4
	Sfx._poll_music_state()
	TestLib.check(Sfx.music_state == &"combat", "heat 3.4: combat")
	Game.heat = 0.0
	Sfx._poll_music_state()
	TestLib.check(Sfx.music_state == &"combat", "combat is held for a few seconds after the heat drops")
	Sfx._state_clock += Sfx.MUSIC_MIN_HOLD + 1.0
	Sfx._poll_music_state()
	TestLib.check(Sfx.music_state == &"explore", "then the music calms down again")
	var veh := _stub(STUB_VEHICLES) as Node
	Game.vehicles = veh
	veh.set(&"driven", Node3D.new())
	_keep.append(veh.get(&"driven"))
	Sfx._poll_music_state()
	TestLib.check(Sfx.music_state == &"driving", "a driven car: driving")
	Game.heat = 4.0
	Sfx._poll_music_state()
	TestLib.check(Sfx.music_state == &"combat", "heat beats driving")
	Game.heat = 0.0
	veh.set(&"driven", null)
	Game.vehicles = null
	Game.state = &"dead"
	TestLib.check(Sfx.music_state == &"death", "Game.state dead (state_changed): death")
	Game.state = &"win"
	TestLib.check(Sfx.music_state == &"win", "Game.state win: win")
	Game.state = &"play"
	TestLib.check(Sfx.music_state == &"explore", "playing again: explore")
	Game.state = &"menu"
	TestLib.check(Sfx.music_state == &"menu", "the main menu has its own state")
	Game.state = &"play"
	Sfx.auto_music = false


# ------------------------------------------------------------------ hero hooks
func _hero_hooks() -> void:
	var player := _stub(STUB_PLAYER) as Node3D
	var body := _stub(STUB_BODY)
	var loco := _stub(STUB_LOCO)
	player.set(&"body", body)
	body.set(&"loco", loco)
	_host.add_child(player)
	Game.player = player
	Game.state = &"play"
	_stop_all()
	Sfx._last_footfalls = -1
	Sfx._step_hero(0.016)
	TestLib.check(not Sfx._last_start.has("step_"), "no step without a foot plant")
	loco.set(&"footfalls", 1)
	Sfx._step_hero(0.016)
	TestLib.check(Sfx._last_start.has("step_"), "a foot plant (Locomotion.footfalls) plays a footstep")
	var t0: float = Sfx._last_start["step_"]
	Game.state = &"paused"
	loco.set(&"footfalls", 2)
	Sfx._step_hero(0.016)
	Game.state = &"play"
	Sfx._step_hero(0.016)
	TestLib.check(float(Sfx._last_start["step_"]) == t0, "nothing is simulated while the game is paused (and the missed step is not replayed)")
	TestLib.check(Sfx._last_start.has("ui_"), "pausing plays the pause sound")
	TestLib.check(Sfx.surface_under(Vector3(0, 0, 0), false) == &"asphalt" and Sfx.surface_under(Vector3(0, 0.3, 0), false) == &"stairs" and Sfx.surface_under(Vector3(0, 0, 0), true) == &"stairs" and Sfx.surface_under(Vector3(0, 12.0, 0), false) == &"metal",
			"surfaces: wet asphalt in the street, stairs on ledges and steps, metal on roofs")
	# jump and landing
	player.set(&"air_time", 0.5)
	Sfx._step_hero(0.016)
	player.set(&"air_time", 0.0)
	Sfx._last_start.clear()
	Sfx._step_hero(0.016)
	TestLib.check(Sfx._last_start.has("land_"), "landing from a jump plays the landing sound")
	Sfx._last_start.clear()
	Sfx.play(&"hurt")
	TestLib.check(Sfx._last_start.has("hero_"), "a hit on the hero adds Kestrel's own grunt")
	# low health
	player.set(&"hp", 15.0)
	Sfx._last_start.clear()
	Sfx._heart_t = 0.0
	Sfx._breath_t = 0.0
	Sfx._step_hero(0.016)
	TestLib.check(Sfx._last_start.has("heartbeat") and Sfx._last_start.has("breath") and Sfx._muffle_target > 0.4, "low health: heartbeat, breath, and the music and ambience muffle (%.2f)" % Sfx._muffle_target)
	player.set(&"hp", 100.0)
	Sfx._step_hero(0.016)
	TestLib.check(Sfx._muffle_target == 0.0, "full health clears the muffle")
	Sfx._step_hero(0.016)
	Game.player = null


func _enemy_hooks() -> void:
	var scene := Node3D.new()
	_keep.append(scene)
	_host.add_child(scene)
	var player := _stub(STUB_PLAYER) as Node3D
	scene.add_child(player)
	Game.player = player
	Game.state = &"play"
	var mgr := _stub(STUB_ENEMIES) as Node
	var troop := _stub(STUB_ENEMY) as Node3D
	var drone := _stub(STUB_ENEMY) as Node3D
	scene.add_child(troop)
	scene.add_child(drone)
	troop.position = Vector3(12, 0, 0)
	drone.position = Vector3(20, 0, 0)
	drone.set(&"type", &"sentinel")
	mgr.set(&"list", [troop, drone])
	Game.enemies = mgr
	_stop_all()
	Sfx._en_state.clear()
	Sfx._poll_enemies()
	TestLib.check(not Sfx._last_start.has("trooper_") and not Sfx._last_start.has("drone_"), "enemies that merely exist are silent")
	TestLib.check(Sfx._hum_target[0] == drone and Sfx._hum_target[1] == null, "a drone within 45 m gets a hum emitter that follows it")
	troop.set(&"aware", true)
	Sfx._poll_enemies()
	TestLib.check(Sfx._last_start.has("trooper_"), "a trooper noticing the hero screeches")
	Sfx._last_start.clear()
	troop.set(&"hp", 30.0)
	Sfx._poll_enemies()
	TestLib.check(Sfx._last_start.has("trooper_"), "a wounded trooper cries out")
	Sfx._last_start.clear()
	drone.set(&"aware", true)
	Sfx._poll_enemies()
	Sfx._last_start.clear()
	drone.set(&"charge", 0.3)
	Sfx._poll_enemies()
	TestLib.check(Sfx._last_start.has("drone_"), "a drone's muzzle charge whines")
	Sfx._last_start.clear()
	troop.set(&"dead", true)
	Sfx._poll_enemies()
	TestLib.check(Sfx._last_start.has("trooper_"), "a dying trooper wails")
	Sfx._last_start.clear()
	Sfx._poll_enemies()
	TestLib.check(not Sfx._last_start.has("trooper_"), "a corpse stays quiet")
	Game.enemies = null
	Game.player = null
	scene.free()
	_keep.erase(scene)
	Sfx.reset_world()


func _vehicle_hooks() -> void:
	var veh := _stub(STUB_VEHICLES) as Node
	var car := _stub(STUB_CAR) as Node3D
	var scene := Node3D.new()
	_keep.append(scene)
	_host.add_child(scene)
	scene.add_child(car)
	Game.vehicles = veh
	Game.state = &"play"
	veh.set(&"driven", car)
	_stop_all()
	Sfx._step_vehicle(0.05)
	var low: AudioStreamPlayer = Sfx._loops[&"engine_low"]
	var high: AudioStreamPlayer = Sfx._loops[&"engine_high"]
	TestLib.check(low.playing and low.stream != null and Sfx._last_start.has("engine_"), "driving: the engine starts and idles")
	var idle_pitch := low.pitch_scale
	car.set(&"speed", 6.0)
	for i in 60:
		Sfx._step_vehicle(0.05)
	TestLib.check(low.pitch_scale > idle_pitch + 0.2, "the engine pitch follows the RPM (%.2f -> %.2f)" % [idle_pitch, low.pitch_scale])
	car.set(&"speed", 26.0)
	for i in 80:
		Sfx._step_vehicle(0.05)
	TestLib.check(high.playing and high.volume_db > low.volume_db, "at high revs the high loop takes over from the low one")
	car.set(&"slip", 6.0)
	for i in 20:
		Sfx._step_vehicle(0.05)
	var squeal: AudioStreamPlayer = Sfx._loops[&"tyre_squeal"]
	TestLib.check(squeal.playing and squeal.volume_db > -20.0, "sliding sideways at speed squeals the tyres")
	car.set(&"slip", 0.0)
	car.set(&"speed", 8.0)
	Sfx._last_start.clear()
	Sfx._crash_cd = 0.0
	Sfx._step_vehicle(0.05)
	TestLib.check(Sfx._last_start.has("car_") and Sfx.duck_amount(&"explosion") >= 0.0 and float(Sfx._duck_hold[&"explosion"]) > 0.0, "a sudden stop from speed is a crash (and ducks the music)")
	# traffic emitters follow the nearest moving cars
	var player := _stub(STUB_PLAYER) as Node3D
	Game.player = player
	var a := _stub(STUB_CAR) as Node3D
	var b := _stub(STUB_CAR) as Node3D
	var c := _stub(STUB_CAR) as Node3D
	var d := _stub(STUB_CAR) as Node3D
	scene.add_child(player)
	for k in [a, b, c, d]:
		scene.add_child(k)
		k.set(&"speed", 12.0)
	a.position = Vector3(30, 0, 0)
	b.position = Vector3(10, 0, 0)
	c.position = Vector3(50, 0, 0)
	d.position = Vector3(200, 0, 0)
	veh.set(&"list", [a, b, c, d])
	veh.set(&"driven", null)
	Sfx._driven = null
	Sfx._poll_emitters()
	TestLib.check(Sfx._emitter_car[0] == b and Sfx._emitter_car[1] == a and Sfx._emitter_car[2] == c, "the three nearest moving cars carry the traffic hum, nearest first; a car 200 m away does not")
	Game.player = null
	veh.set(&"driven", null)
	for i in 40:
		Sfx._step_vehicle(0.1)
	TestLib.check(not low.playing and not high.playing and not squeal.playing, "leaving the car stops the engine and the tyres")
	Game.vehicles = null
	scene.free()
	_keep.erase(scene)
	Sfx.reset_world()


func _quantum_and_ambience() -> void:
	var player := _stub(STUB_PLAYER) as Node3D
	var q := _stub(STUB_QUANTUM)
	player.set(&"quantum", q)
	Game.player = player
	Game.state = &"play"
	var ghost := Node3D.new()
	_keep.append(ghost)
	q.set(&"clone", ghost)
	Sfx._step_quantum(0.1)
	var sp: AudioStreamPlayer = Sfx._loops[&"superpos_loop"]
	var en: AudioStreamPlayer = Sfx._loops[&"entangle_loop"]
	TestLib.check(sp.playing and not en.playing, "a superposition ghost plays its shimmering drone")
	q.set(&"links", [1])
	Sfx._step_quantum(0.1)
	TestLib.check(en.playing, "an entanglement link plays its own drone")
	q.set(&"clone", null)
	q.set(&"links", [])
	for i in 5:
		Sfx._step_quantum(0.5)
	TestLib.check(not sp.playing and not en.playing, "the drones fade out and stop")
	Game.player = null
	# ambience
	Sfx.start_ambience()
	var all_playing := true
	for bed in BEDS:
		all_playing = all_playing and (Sfx._amb[bed] as AudioStreamPlayer).playing and (Sfx._amb[bed] as AudioStreamPlayer).stream != null
	TestLib.check(Sfx.is_ambience_on() and all_playing, "start_ambience(): rain (3 surfaces), traffic, wind and the city hum all loop")
	Sfx.set_rain_surface(&"asphalt")
	for i in 12:
		Sfx._step_ambience(0.5)
	var a1: float = Sfx._amb_vol[&"rain_asphalt"]
	var m1: float = Sfx._amb_vol[&"rain_metal"]
	Sfx.set_rain_surface(&"metal")
	for i in 12:
		Sfx._step_ambience(0.5)
	TestLib.check(a1 > m1 and float(Sfx._amb_vol[&"rain_metal"]) > float(Sfx._amb_vol[&"rain_asphalt"]), "the rain sounds change with the surface under the listener (asphalt %.2f > metal %.2f, then the reverse)" % [a1, m1])
	Sfx._thunder_in = 0.0
	Sfx._step_ambience(0.1)
	var any := false
	for o in Sfx._oneshots:
		any = any or o.playing
	TestLib.check(any, "thunder rolls over the city now and then")
	Sfx.stop_ambience()
	Sfx.reset_world()


# ------------------------------------------------------------------ radio
func _radio() -> void:
	Sfx.reset_world()
	Game.state = &"play"
	var text := "Kestrel, the rift is open."
	Sfx.radio_type(text, 5)
	TestLib.check(Sfx.is_radio_active(), "a typed radio line opens the radio")
	var pend := Sfx._radio_pending
	TestLib.check(pend >= 1 and pend <= 3, "babble follows the typed text: the one vowel of 'Kestr' queues %d syllable" % pend)
	Sfx.radio_type(text, text.length())
	var more := Sfx._radio_pending
	TestLib.check(more > pend and more <= 6, "more typed letters, more syllables (%d, capped)" % more)
	Sfx._step_radio(0.1)
	var talking := 0
	for v in Sfx._voices:
		talking += 1 if v.playing else 0
	TestLib.check(talking >= 1 and Sfx._radio_pending < more, "syllables play on the Voice bus, one at a time")
	TestLib.check(Sfx._voices[0].bus == &"Voice", "the radio voice has its own bus")
	Sfx.duck(&"radio")
	Sfx._step_ducks(0.3)
	TestLib.check(Sfx.duck_amount(&"radio") > 0.9, "the music ducks under the radio")
	for i in 10:
		Sfx._step_radio(0.1)
	TestLib.check(not Sfx.is_radio_active(), "when the typing stops the radio closes by itself")
	Sfx.reset_world()
	TestLib.check(true, "radio reset")


# ------------------------------------------------------------------ lifecycle
func _lifecycle() -> void:
	TestLib.check(Game.new_game.is_connected(Sfx.reset_world) and Game.respawn.is_connected(Sfx.reset_world) and Game.next_sector.is_connected(Sfx.reset_world), "new_game, respawn and next_sector reset the audio")
	Sfx._later(&"whizz", Vector3.ZERO, 0.0, 1.0, 5.0)
	Sfx._last_footfalls = 7
	Sfx._rpm = 0.9
	Sfx.duck(&"explosion")
	Sfx.reset_world()
	var pending := false
	for t in Sfx._pend_t:
		pending = pending or t >= 0.0
	TestLib.check(not pending and Sfx._last_footfalls == -1 and Sfx._rpm < 0.2 and float(Sfx._duck_hold[&"explosion"]) == 0.0, "reset_world() clears delayed sounds, foot counts, revs and ducks")
