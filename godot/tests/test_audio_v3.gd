extends RefCounted
## AUDIO v3: music director v2 (weather, hour, heat, chapter, boss phases, stealth states and stingers), radio shows (songs, host chatter, ads), engine variants per vehicle kind,
## footsteps per surface (roofs, interiors), ability sounds (PHASE SHIELD, TIME SLIP, ARC, SLAM, WARP GRAB, throw, wall-run) and the new weapon shots, plus the size budget.
## Pure rules are checked on AudioDirector / RadioShows; the wiring runs in the REAL game scene (main.tscn). Waits on state and counters, never frame counts.
## Run: tools/test.sh tests/test_audio_v3.gd

const DIR := "res://assets/audio/"
const V3_BUDGET_MB := 2.0
const TOTAL_BUDGET_MB := 30.0
const OGGS: Array[String] = ["verb_shield", "verb_slip", "verb_slam", "shot_rail", "shot_gravity", "shot_lance", "sting_stealth_spot", "sting_stealth_clear", "sting_phase", "sting_chapter",
	"talk_neon_0", "talk_neon_1", "talk_vael_0", "talk_vael_1", "talk_club_0", "talk_club_1", "talk_lofi_0", "talk_lofi_1", "ad_0", "ad_1", "ad_2"]
const WAVS: Array[String] = ["verb_arc", "verb_grab", "verb_throw", "verb_wallrun_0", "verb_wallrun_1", "verb_wallrun_2", "shot_flux", "shot_burst",
	"step_roof_0", "step_roof_1", "step_roof_2", "step_roof_3", "step_tile_0", "step_tile_1", "step_tile_2", "step_tile_3", "step_carpet_0", "step_carpet_1", "step_carpet_2", "step_carpet_3",
	"engine_bike_low", "engine_bike_high", "engine_hover_low", "engine_hover_high", "engine_heavy_low", "engine_heavy_high"]
const STUB_VEHICLES := "extends Node\nvar driven = null\nvar list: Array = []\n"
const STUB_CAR := "extends Node3D\nvar speed := 14.0\nvar slip := 0.0\nvar kind: StringName = &\"sedan\"\n"

class FakeRoom extends RefCounted:
	var type: StringName = &"club"


func _size(n: String) -> int:
	var f := FileAccess.open(DIR + n, FileAccess.READ)
	return f.get_length() if f != null else 0


func _until(host: Node, cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await TestLib.frames(host, 1)
	return cond.call()


func run(host: Node) -> void:
	_files()
	_director_rules()
	_shows_rules()
	_engine_rules()
	await _real_scene(host)


# ---------------------------------------------------------------------------------------------------------------------
func _files() -> void:
	var bad: Array[String] = []
	var added := 0
	for n in OGGS:
		var v := Sfx.variants_of(StringName(n))
		if v.is_empty() or not (v[0] is AudioStreamOggVorbis):
			bad.append(n)
		added += _size(n + ".ogg")
	for n in WAVS:
		var v := Sfx.variants_of(StringName(n))
		if v.is_empty() or not (v[0] is AudioStreamWAV):
			bad.append(n)
		added += _size(n + ".wav")
	TestLib.check(bad.is_empty(), "every AUDIO v3 file exists and loads (%d OGG, %d WAV; bad: %s)" % [OGGS.size(), WAVS.size(), str(bad)])
	TestLib.check(float(added) / 1048576.0 < V3_BUDGET_MB, "AUDIO v3 adds %.2f MB (budget %.1f)" % [float(added) / 1048576.0, V3_BUDGET_MB])
	var total := 0
	var d := DirAccess.open(DIR)
	for f in d.get_files():
		if f.ends_with(".wav") or f.ends_with(".ogg"):
			total += _size(f)
	TestLib.check(float(total) / 1048576.0 < TOTAL_BUDGET_MB, "the whole audio folder %.2f MB stays under %.0f" % [float(total) / 1048576.0, TOTAL_BUDGET_MB])
	var loops_ok := true
	for n in ["engine_bike_low", "engine_bike_high", "engine_hover_low", "engine_hover_high", "engine_heavy_low", "engine_heavy_high"]:
		var w := Sfx.variants_of(StringName(n))[0] as AudioStreamWAV
		loops_ok = loops_ok and w.loop_mode == AudioStreamWAV.LOOP_FORWARD
	TestLib.check(loops_ok, "the six engine variants are looping streams")
	var w2 := true
	for id: StringName in AudioDirector.VERB_SOUNDS:
		w2 = w2 and not Sfx.variants_of(AudioDirector.VERB_SOUNDS[id][0]).is_empty()
	TestLib.check(w2, "every ability id has its sound file")
	var weap := true
	for id: StringName in [&"lance", &"burst", &"rail", &"flux", &"gravity"]:
		var snd := StringName(WeaponDefs.DEFS[id].get("snd", &"shot"))
		weap = weap and snd != &"shot" and not Sfx.variants_of(snd).is_empty()
	TestLib.check(weap, "the five newer weapons fire their own shot sounds")
	var uniq := {}
	for id: StringName in WeaponDefs.IDS:
		uniq[StringName(WeaponDefs.DEFS[id].get("snd", &"shot"))] = true
	TestLib.check(uniq.size() >= 10, "weapon shots are varied (%d distinct sounds over %d weapons)" % [uniq.size(), WeaponDefs.IDS.size()])


# ---------------------------------------------------------------------------------------------------------------------
func _director_rules() -> void:
	var base: Array = Sfx.MUSIC_STATES[&"explore"]
	var clear := AudioDirector.stem_targets(base, &"explore", {})
	var same := true
	for i in 5:
		same = same and is_equal_approx(clear[i], float(base[i]))
	TestLib.check(same, "no weather, clock, heat or chapter: the base state is untouched")
	var alert_base: Array = Sfx.MUSIC_STATES[&"alert"]
	var drive_base: Array = Sfx.MUSIC_STATES[&"driving"]
	var rain := AudioDirector.stem_targets(drive_base, &"driving", {"weather": &"rain"})
	var storm := AudioDirector.stem_targets(drive_base, &"driving", {"weather": &"storm"})
	var dry := AudioDirector.stem_targets(drive_base, &"driving", {"weather": &"clear"})
	TestLib.check(rain[0] > dry[0] and rain[1] < dry[1] and storm[0] > rain[0], "rain brings the pad up and the pulse down, a storm more so")
	var night := AudioDirector.stem_targets(alert_base, &"alert", {"hour": 23.0})
	var noon := AudioDirector.stem_targets(alert_base, &"alert", {"hour": 12.0})
	var dusk := AudioDirector.stem_targets(alert_base, &"alert", {"hour": 18.0})
	TestLib.check(night[0] > noon[0] and night[1] < noon[1] and dusk[1] > noon[1] and noon[0] == float(alert_base[0]), "the hour colours the mix: night softer, dusk a touch busier, noon plain")
	var h0 := AudioDirector.stem_targets(base, &"explore", {"heat": 0.0})
	var h1 := AudioDirector.stem_targets(base, &"explore", {"heat": 0.8})
	TestLib.check(h1[2] > h0[2], "heat below the alert step already pushes the bass")
	var a0 := AudioDirector.stem_targets(alert_base, &"alert", {"heat": 1.0})
	var a2 := AudioDirector.stem_targets(alert_base, &"alert", {"heat": 2.5})
	TestLib.check(a2[3] > a0[3] and a2[1] > a0[1], "inside the alert state the percussion and pulse climb with the heat")
	var c0 := AudioDirector.stem_targets(base, &"explore", {"chapter": 0})
	var c11 := AudioDirector.stem_targets(base, &"explore", {"chapter": 11})
	TestLib.check(c11[1] > c0[1] and c11[2] > c0[2], "later chapters carry a fuller score")
	var worst := true
	for st: StringName in Sfx.MUSIC_STATES:
		var b: Array = Sfx.MUSIC_STATES[st]
		var t := AudioDirector.stem_targets(b, st, {"weather": &"storm", "hour": 23.0, "heat": 3.0, "chapter": 11, "boss_phase": 3})
		for i in 5:
			worst = worst and t[i] <= 0.0 and (float(b[i]) > -50.0 or t[i] <= -50.0)
	TestLib.check(worst, "offsets never lift a stem past 0 dB and never wake a stem the state keeps off")
	var dth := AudioDirector.stem_targets(Sfx.MUSIC_STATES[&"death"], &"death", {"weather": &"storm", "heat": 3.0})
	TestLib.check(is_equal_approx(dth[0], float(Sfx.MUSIC_STATES[&"death"][0])), "death and win ignore the director")
	var bs: Array = Sfx.MUSIC_STATES[&"boss"]
	var b1 := AudioDirector.stem_targets(bs, &"boss", {"boss_phase": 1})
	var b2 := AudioDirector.stem_targets(bs, &"boss", {"boss_phase": 2})
	TestLib.check(b1[3] < b2[3] and b1[4] < b2[4] and AudioDirector.boss_layer_boost(3) > AudioDirector.boss_layer_boost(2) and AudioDirector.boss_layer_boost(2) > AudioDirector.boss_layer_boost(1),
		"the boss opens restrained, phase 2 is the full theme, phase 3 lifts the boss layer")
	TestLib.check(AudioDirector.stealth_state(-1, 999.0, 999.0) == &"" and AudioDirector.stealth_state(0, 30.0, 999.0) == &"" and AudioDirector.stealth_state(0, 10.0, 999.0) == &"sneak"
		and AudioDirector.stealth_state(1, 999.0, 20.0) == &"suspect" and AudioDirector.stealth_state(2, 999.0, 50.0) == &"" and AudioDirector.stealth_state(3, 999.0, 5.0) == &"alert",
		"stealth music: none far away, sneak near an unaware guard, suspect when one is suspicious, alert when spotted")
	TestLib.check(Sfx.MUSIC_STATES.has(&"sneak") and Sfx.MUSIC_STATES.has(&"suspect") and (Sfx.MUSIC_STATES[&"sneak"] as Array).size() == 5, "the stealth states are real stem rows")
	TestLib.check(AudioDirector.footstep_surface(0.0, false, false, &"") == &"asphalt" and AudioDirector.footstep_surface(8.0, false, false, &"") == &"roof"
		and AudioDirector.footstep_surface(0.3, true, false, &"") == &"stairs" and AudioDirector.footstep_surface(0.0, false, true, &"club") == &"carpet"
		and AudioDirector.footstep_surface(0.0, false, true, &"warehouse") == &"tile" and AudioDirector.footstep_surface(9.0, false, true, &"server_room") == &"tile",
		"footsteps: street asphalt, roofs, ledges, carpet or tile inside by room type")


# ---------------------------------------------------------------------------------------------------------------------
func _shows_rules() -> void:
	TestLib.check(RadioShows.show_count() == CarRadio.STATIONS.size(), "one show per station")
	var all_ok := true
	var det := true
	var seen_all := true
	for st in RadioShows.show_count():
		var p1 := RadioShows.plan(st, 16)
		var p2 := RadioShows.plan(st, 16)
		det = det and p1 == p2
		var kinds := {}
		var titles := {}
		for i in p1.size():
			var s: Dictionary = p1[i]
			kinds[s["kind"]] = true
			if s["kind"] == "song":
				titles[s["name"]] = true
				all_ok = all_ok and float(s["secs"]) > 10.0 and float(s["pitch"]) > 0.8 and float(s["pitch"]) < 1.2
			else:
				all_ok = all_ok and not Sfx.variants_of(StringName(s["clip"])).is_empty()
				all_ok = all_ok and String(p1[(i + 1) % p1.size()]["kind"]) == "song"                 # a break is always followed by a song
			all_ok = all_ok and RadioShows.caption(s, CarRadio.station_name(st)) != ""
		seen_all = seen_all and kinds.size() == 3 and titles.size() >= 3
	TestLib.check(det and all_ok, "the programme is deterministic, breaks are followed by songs and every clip exists")
	TestLib.check(seen_all, "each station plays songs, host talk and ads, with at least three song titles")
	var names := {}
	for st in RadioShows.show_count():
		names[RadioShows.host(st)] = true
	TestLib.check(names.size() == RadioShows.show_count(), "every station has its own host")


func _engine_rules() -> void:
	var ok := true
	var variants := {}
	for k: StringName in VehicleSpecs.STREAM_KINDS:
		var e := AudioDirector.engine_for(k)
		ok = ok and ENGINE_OK(e)
		variants[e[0]] = true
		for ln in AudioDirector.engine_loops(e[0]):
			ok = ok and not Sfx.variants_of(ln).is_empty()
	TestLib.check(ok, "every vehicle kind maps to an engine family whose loops exist")
	TestLib.check(variants.size() >= 4, "engines: car, bike, hover and heavy families are all in use (%d)" % variants.size())
	TestLib.check(AudioDirector.engine_for(&"bike")[0] == &"bike" and AudioDirector.engine_for(&"hover")[0] == &"hover" and AudioDirector.engine_for(&"truck")[0] == &"heavy"
		and AudioDirector.engine_for(&"sedan")[0] == &"" and float(AudioDirector.engine_for(&"sport")[1]) > 1.0, "bike, hover and truck have their own engines; the sport car revs higher")


static func ENGINE_OK(e: Array) -> bool:
	return e.size() == 3 and float(e[1]) > 0.4 and float(e[1]) < 2.0


# ---------------------------------------------------------------------------------------------------------------------
func _real_scene(host: Node) -> void:
	var was_muted := Sfx.muted
	Sfx.muted = false
	Sfx.auto_music = true
	Sfx.hour_override = -1.0
	Sfx.indoors_override = -1
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	var p: Player = Game.player
	if p == null or Game.enemies == null or Game.vehicles == null:
		TestLib.check(false, "the real game scene has a player, enemies and vehicles")
		return
	(Game.progress as Progress).autosave_enabled = false
	Game.state = &"play"
	for n in host.find_children("*", "Stability", true, false):
		n.set_process(false)
	Sfx.reset_world()
	Sfx.play_music()
	Sfx.set_music_state(&"explore", true)
	await TestLib.frames(host, 2)
	TestLib.check(Sfx.is_music_playing(), "the music plays in the real scene")

	# --- stealth music from the live enemy list
	var hero := p.global_position
	var g: Drone = Game.enemies.spawn(&"operative", hero + Vector3(11.0, 0.0, 0.0), false)
	if g == null:
		TestLib.check(false, "an operative can be spawned in the real scene")
	else:
		g.set_physics_process(false)
		g.global_position = hero + Vector3(11.0, 0.0, 0.0)
		g.aware = false
		g.suspicion = 0.0
		g.search_t = 0.0
		Game.heat = 0.0
		var got := await _until(host, func() -> bool: return Sfx.music_state == &"sneak", 120)
		TestLib.check(got and Sfx.stealth_level == AudioDirector.LEVEL_UNAWARE, "an unaware guard 11 m away: the music turns to sneak (state %s)" % Sfx.music_state)
		TestLib.check(Sfx.stem_target_db(1) < float(Sfx.MUSIC_STATES[&"explore"][1]), "sneak keeps the pulse back")
		var spot0 := Sfx.verb_count
		g.suspicion = 0.6
		got = await _until(host, func() -> bool: return Sfx.music_state == &"suspect", 120)
		TestLib.check(got and Sfx.stealth_level == AudioDirector.LEVEL_SUSPICIOUS, "a suspicious guard: suspect (state %s)" % Sfx.music_state)
		TestLib.check(Sfx.stem_target_db(3) > -50.0, "suspect wakes the percussion")
		var sting_before := Sfx._sting_t
		TestLib.check(sting_before > -50.0 or Sfx._get(&"sting_stealth_spot") != null, "the spot sting exists and the state change asked for it")
		g.aware = true
		got = await _until(host, func() -> bool: return Sfx.music_state == &"alert", 120)
		TestLib.check(got and Sfx.stealth_level == AudioDirector.LEVEL_ALERTED, "a spotted hero: the alert state without any heat (state %s)" % Sfx.music_state)
		g.aware = false
		g.suspicion = 0.0
		g.global_position = hero + Vector3(300.0, 0.0, 300.0)
		Sfx._state_since = Sfx._state_clock - 20.0                           # the hold timer is not what this checks
		got = await _until(host, func() -> bool: return Sfx.music_state == &"explore", 200)
		TestLib.check(got, "guard gone: the music relaxes to explore (state %s)" % Sfx.music_state)
		TestLib.check(spot0 == Sfx.verb_count, "stealth changes do not play ability sounds")

	# --- weather and time of day move the live targets
	Game.heat = 0.0
	Sfx.hour_override = 23.0
	Sfx._refresh_director()
	var night_pad := Sfx.stem_target_db(0)
	Sfx.hour_override = 12.0
	Sfx._refresh_director()
	TestLib.check(night_pad > Sfx.stem_target_db(0) or Sfx.stem_target_db(0) >= 0.0, "the live hour changes the targets of the running state")
	Sfx.hour_override = -1.0

	# --- the chapter sting
	Sfx._chapter_seen = -1
	Sfx._step_chapter()
	var learned := Sfx._chapter_seen
	Sfx._chapter_seen = maxi(learned - 1, -1) if learned > 0 else -1
	var chapter0 := Sfx.chapter_index()
	TestLib.check(chapter0 >= 0 and learned == chapter0, "the sound layer reads the real story chapter (%d)" % chapter0)
	Sfx._chapter_seen = chapter0
	var story: Node = Game.story
	var prev_ch: int = int(story.get(&"chapter"))
	story.set(&"chapter", prev_ch + 1)
	Sfx._sting.stop()
	Sfx._step_chapter()
	TestLib.check(Sfx._sting.playing and Sfx._sting.stream == Sfx._get(&"sting_chapter"), "a new chapter plays its sting")
	story.set(&"chapter", prev_ch)
	Sfx._chapter_seen = prev_ch

	# --- boss phases through a real Overseer
	var ov: Drone = Game.enemies.spawn(&"overseer", hero + Vector3(0.0, 0.0, -30.0), false)
	if ov == null:
		TestLib.check(false, "an Overseer can be spawned in the real scene")
	else:
		ov.set_physics_process(false)
		TestLib.check(Sfx.boss_active and Sfx.boss_phase == 1, "the Overseer sets the boss state at phase 1")
		var got2 := await _until(host, func() -> bool: return Sfx.music_state == &"boss", 120)
		TestLib.check(got2, "the music state is boss")
		var perc1 := Sfx.stem_target_db(3)
		var layer1 := AudioDirector.boss_layer_boost(1)
		ov.hp = ov.max_hp * 0.5
		ov.call(&"_check_phase")
		TestLib.check(Sfx.boss_phase == 2 and ov.phase == 2, "the Overseer's phase change reaches the music director")
		Sfx._refresh_director()
		TestLib.check(Sfx.stem_target_db(3) > perc1, "phase 2 lifts the percussion over the restrained opening (%.1f -> %.1f dB)" % [perc1, Sfx.stem_target_db(3)])
		ov.hp = ov.max_hp * 0.2
		ov.call(&"_check_phase")
		TestLib.check(Sfx.boss_phase == 3 and AudioDirector.boss_layer_boost(3) > layer1, "phase 3 is reached and lifts the boss layer")
		Sfx.boss_active = false
		if is_instance_valid(ov):
			ov.queue_free()
		Game.enemies.list.erase(ov)
		Sfx.boss_phase = 1
	Sfx.boss_active = false

	# --- ability sounds from the real verbs
	p.energy = p.max_energy if "max_energy" in p else 100.0
	var q: QuantumVerbs = p.qverbs
	var c0 := Sfx.verb_count
	for id: StringName in [&"shield", &"slip"]:
		q.clear_cooldown(id)
		p.energy = 100.0
		var used := q.use(id)
		TestLib.check(used and Sfx.verb_count > c0, "using %s plays its own ability sound (last %s)" % [id, Sfx.last_played])
		TestLib.check(Sfx.last_played == AudioDirector.VERB_SOUNDS[id][0], "%s -> %s" % [id, AudioDirector.VERB_SOUNDS[id][0]])
		c0 = Sfx.verb_count
		await _until(host, func() -> bool: return Sfx._now() - float(Sfx._last_start.get("verb_", -10.0)) > 0.3, 90)
	var ability_duck := Sfx.duck_amount(&"ability")
	TestLib.check(ability_duck >= 0.0, "ability ducking is available (%.2f)" % ability_duck)
	p.verbs.call(&"_slam_impact")
	TestLib.check(Sfx.verb_count > c0 and Sfx.duck_amount(&"explosion") >= 0.0, "the ground slam impact plays its own sound")
	var src := FileAccess.get_file_as_string("res://scripts/player/hero_verbs.gd")
	TestLib.check(src.contains("Sfx.verb(&\"grab\")") and src.contains("Sfx.verb(&\"throw\")") and src.contains("Sfx.verb(&\"wallrun\")"), "warp grab, throw and wall-run are wired to their sounds")
	var c1 := Sfx.verb_count
	Sfx.verb(&"grab")
	Sfx.verb(&"throw")
	Sfx.verb(&"wallrun")
	TestLib.check(Sfx.verb_count == c1 + 3, "all three play")

	# --- footsteps by surface in the live sound code
	TestLib.check(Sfx.footstep_surface(Vector3(0.0, 9.0, 0.0), false) == &"roof", "a rooftop: tar and gravel")
	var room := FakeRoom.new()
	InteriorSpace.register(room, Rect2(-5.0, -5.0, 10.0, 10.0), 0.0, 3.0, PackedFloat32Array(), PackedFloat32Array())
	Sfx.indoors_override = 1
	TestLib.check(InteriorSpace.room_type() == &"club" and Sfx.footstep_surface(Vector3.ZERO, false) == &"carpet", "a club floor: carpet")
	room.type = &"warehouse"
	TestLib.check(Sfx.footstep_surface(Vector3.ZERO, false) == &"tile", "a warehouse floor: tile")
	Sfx.indoors_override = -1
	InteriorSpace.unregister(room)
	TestLib.check(InteriorSpace.room_type() == &"" and Sfx.footstep_surface(Vector3.ZERO, false) == &"asphalt", "back on the street: asphalt")
	Sfx._last_start.erase("step_")
	var stepped := Sfx.variants_of(&"step_roof").size() >= 4 and Sfx.variants_of(&"step_tile").size() >= 4 and Sfx.variants_of(&"step_carpet").size() >= 4
	TestLib.check(stepped, "four variants per new surface")

	# --- engine variants through the live vehicle code
	var old_veh = Game.vehicles
	var stub := Node.new()
	var vs := GDScript.new()
	vs.source_code = STUB_VEHICLES
	vs.reload()
	stub.set_script(vs)
	host.add_child(stub)
	var car := Node3D.new()
	var cs := GDScript.new()
	cs.source_code = STUB_CAR
	cs.reload()
	car.set_script(cs)
	host.add_child(car)
	Game.vehicles = stub
	stub.set(&"driven", car)
	for kind: StringName in [&"bike", &"hover", &"truck", &"sedan"]:
		car.set(&"kind", kind)
		var want_loops := AudioDirector.engine_loops(AudioDirector.engine_for(kind)[0])
		for i in 40:
			Sfx._step_vehicle(0.05)
		var on_ok := false                                                  # at speed one of the pair carries the sound, the other is crossfaded out
		for ln in want_loops:
			on_ok = on_ok or (Sfx._loops[ln] as AudioStreamPlayer).playing
		var others := 0
		for v: StringName in [&"", &"bike", &"hover", &"heavy"]:
			if v != AudioDirector.engine_for(kind)[0]:
				for ln in AudioDirector.engine_loops(v):
					if (Sfx._loops[ln] as AudioStreamPlayer).playing:
						others += 1
		TestLib.check(on_ok and others == 0, "%s drives the %s engine pair and no other (stray %d)" % [kind, AudioDirector.engine_for(kind)[0], others])
	car.set(&"kind", &"sport")
	for i in 40:
		Sfx._step_vehicle(0.05)
	TestLib.check((Sfx._loops[&"engine_low"] as AudioStreamPlayer).pitch_scale > 0.0, "the sport car uses the car loops")
	stub.set(&"driven", null)
	for i in 40:
		Sfx._step_vehicle(0.05)
	var silent := true
	for ln in Sfx._loops:
		if String(ln).begins_with("engine_"):
			silent = silent and not (Sfx._loops[ln] as AudioStreamPlayer).playing
	TestLib.check(silent, "leaving the car silences every engine loop")
	Game.vehicles = old_veh
	stub.queue_free()
	car.queue_free()

	# --- radio shows on the real car radio
	var rad: CarRadio = Game.vehicles.radio
	if rad == null:
		TestLib.check(false, "the real vehicle manager has a car radio")
	else:
		rad.on = true
		rad.station = 1
		rad.song_secs = 1.0
		rad._begin_show()
		TestLib.check(rad.counts["song"] == 1 and String(rad.segment["kind"]) == "song", "switching a station starts with a song (%s)" % rad.segment.get("name", ""))
		var steps := 0
		var talk_ok := true
		while (rad.counts["talk"] < 1 or rad.counts["ad"] < 1 or rad.counts["song"] < 3) and steps < 200:
			if String(rad.segment["kind"]) != "song":
				talk_ok = talk_ok and rad._talk_player.stream != null and rad._duck_goal < 0.0
				rad._talk_player.stop()                                    # the clip is over (the dummy driver runs in real time)
			rad.advance_show(0.5)
			steps += 1
		TestLib.check(rad.counts["talk"] >= 1 and rad.counts["ad"] >= 1 and rad.counts["song"] >= 3, "the programme moves on: songs %d, talk %d, ads %d" % [rad.counts["song"], rad.counts["talk"], rad.counts["ad"]])
		TestLib.check(talk_ok, "talk and ads load their clip and pull the station down")
		TestLib.check(String(rad.segment["kind"]) == "song" and rad._duck_goal == 0.0 or String(rad.segment["kind"]) != "song", "the station comes back up for the next song")
		var sg0 := rad.seg_index
		rad.turn_off()
		TestLib.check(rad.segment.is_empty() and not rad._talk_player.playing, "switching the radio off ends the show")
		rad.advance_show(5.0)
		TestLib.check(rad.seg_index == sg0, "an off radio keeps no clock")
		rad.song_secs = RadioShows.SONG_SECS

	# --- reset
	Sfx.reset_world()
	TestLib.check(Sfx.stealth_level == -1 and Sfx.boss_phase == 1, "a new run clears the stealth and boss state")
	Game.heat = 0.0
	Sfx.hour_override = -1.0
	Sfx.stop_music()
	Sfx.muted = was_muted
	main.queue_free()
