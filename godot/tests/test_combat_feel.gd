extends RefCounted
## COMBAT FEEL in the REAL game scene (scenes/main.tscn), the owner's phone test: "weapons look and sound weak, enemies do not come". Checks, in the live game:
##  * the encounter director brings a squad to the hero (first contact within a countdown, 20-34 m away, aware, rushing, closing in), a cue plays, it escalates, backs up, pauses with
##    Game.state and stays out of vehicles;
##  * a fight bot that shoots whoever comes gets kills per minute and is almost never without a fight in range;
##  * the weapon: tracers that fly, real shell casings, a stronger camera kick, one silhouette per weapon class, a kill sound, and the shot sounds measured (RMS, peak) from the files.
## Time runs 4x (time_scale and tick rate together, like test_enemies); every wait is in game seconds. Run: tools/test.sh tests/test_combat_feel.gd

const FightBot := preload("res://tests/fight_bot.gd")
const K := 4
const TMP := "user://test_combat_feel.cfg"

var _p: Player
var _mgr: EnemyManager
var _enc: Encounters
var _dt := 1.0 / 60.0


func run(host: Node) -> void:
	_test_rules()
	_test_assets()
	_test_silhouettes()

	Game.civilian_casualties = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	_p = Game.player
	_mgr = Game.enemies as EnemyManager
	_enc = Encounters.current
	if _p == null or _mgr == null or _enc == null:
		TestLib.check(false, "the real game has a player, an enemy manager and the encounter director")
		return
	var prog := Game.progress as Progress
	if prog != null:
		prog.path = TMP
	Game.state = &"play"
	_mgr.patrol_groups().clear()
	_mgr.clear()
	_p.max_hp = 1.0e6
	var m := Game.missions
	if m != null:
		m.contracts.enabled = false
	TestLib.check(not _enc.enabled or not Game.autostart, "the director is off under tools and tests by default (the other tests keep their quiet street)")
	_enc.enabled = true
	_enc.reset()
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K

	await _test_first_contact(host)
	await _test_fight(host)
	await _test_pause_and_vehicle(host)
	await _test_backup(host)
	await _test_shot_feel(host)

	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	_enc.enabled = false
	_mgr.clear()
	Game.heat = 0.0
	Input.action_release(&"fire")
	for f: String in [TMP, TMP + ".bak", TMP + ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	main.queue_free()
	await TestLib.frames(host, 2)


# --- pure rules -----------------------------------------------------------------------------------------------------------

func _test_rules() -> void:
	TestLib.check(Encounters.size_of(1) == 2 and Encounters.size_of(2) == 2 and Encounters.size_of(3) == 3 and Encounters.size_of(5) == 4 and Encounters.size_of(99) == Encounters.MAX_WAVE_SIZE, "squads grow 2, 2, 3, 3, 4 ... up to the cap")
	TestLib.check(Encounters.type_of(1, 0, 0) == &"operative" and Encounters.type_of(3, 1, 1) == &"flanker" and Encounters.type_of(3, 1, 0) == &"operative", "a rusher every 3rd wave (not before chapter 1)")
	TestLib.check(Encounters.type_of(4, 1, 1) == &"shield" and Encounters.type_of(2, 2, 0) == &"striker" and Encounters.type_of(6, 3, 0) == &"sentinel", "specialists, a kamikaze and a drone join as the waves go on")
	var g0 := Encounters.gap_after(1, 0.5)
	var g9 := Encounters.gap_after(9, 0.5)
	TestLib.check(g0 > g9 and g9 >= Encounters.GAP.x * 0.6 - 0.01 and g0 <= Encounters.GAP.y, "the pause between waves shrinks (%.1f s -> %.1f s)" % [g0, g9])
	TestLib.check(Encounters.FIRST_DELAY <= 12.0 and Encounters.QUIET_MAX <= 15.0, "first contact and the quiet limit are short")


# --- the shot sounds, measured from the files ---------------------------------------------------------------------------

func _test_assets() -> void:
	for n: String in ["shot", "shot_1", "shot_2", "shot_3", "shot_scatter"]:
		var w := _wav("res://assets/audio/%s.wav" % n)
		TestLib.check(not w.is_empty(), "%s.wav is readable 16-bit PCM" % n)
		if w.is_empty():
			continue
		TestLib.check(float(w["rms250"]) > -20.0, "%s has body: RMS of the first 250 ms %.1f dBFS (the old thin shot measured -24 to -26)" % [n, w["rms250"]])
		TestLib.check(float(w["peak"]) <= -6.0 and float(w["len"]) < 1.0, "%s stays under the mix ceiling (peak %.1f dBFS) and short (%.2f s)" % [n, w["peak"], w["len"]])
		TestLib.check(float(w["low_share"]) > 0.25, "%s has low-mid energy a phone speaker plays (%.0f %% of its energy under 1.2 kHz in the first 250 ms)" % [n, 100.0 * float(w["low_share"])])
	for n: String in ["hit_kill", "civ_dissolve"]:
		TestLib.check(FileAccess.file_exists("res://assets/audio/%s.wav" % n), "%s.wav exists" % n)
	TestLib.check(WeaponDefs.def(&"scatter")["snd"] == &"shot_scatter", "the shard scatter has its own shot")


## {rms250, peak, len, low_share} of a 16-bit mono WAV, {} when unreadable. low_share: energy share below 1.2 kHz by a one-pole low-pass (no FFT needed).
func _wav(path: String) -> Dictionary:
	var b := FileAccess.get_file_as_bytes(path)
	if b.size() < 64:
		return {}
	var at := 12
	var data_at := -1
	var data_len := 0
	var rate := 44100
	while at + 8 <= b.size():
		var id := b.slice(at, at + 4).get_string_from_ascii()
		var sz := b.decode_u32(at + 4)
		if id == "fmt ":
			rate = b.decode_u32(at + 12)
		if id == "data":
			data_at = at + 8
			data_len = mini(sz, b.size() - data_at)
			break
		at += 8 + sz + (sz & 1)
	if data_at < 0:
		return {}
	var n := data_len / 2
	var peak := 0.0
	var e250 := 0.0
	var e_low := 0.0
	var n250 := mini(n, int(0.25 * rate))
	var lp := 0.0
	var a := 1.0 - exp(-TAU * 1200.0 / float(rate))
	for i in n:
		var v := float(b.decode_s16(data_at + i * 2)) / 32768.0
		peak = maxf(peak, absf(v))
		if i < n250:
			e250 += v * v
			lp += a * (v - lp)
			e_low += lp * lp
	return {"rms250": 20.0 * log(sqrt(e250 / maxf(1.0, float(n250))) + 1.0e-9) / log(10.0), "peak": 20.0 * log(peak + 1.0e-9) / log(10.0),
			"len": float(n) / float(rate), "low_share": e_low / maxf(e250, 1.0e-9)}


# --- the weapon silhouettes ----------------------------------------------------------------------------------------------

func _test_silhouettes() -> void:
	TestLib.check(WeaponModels.mesh(&"carbine") == null, "the carbine is the hero's own baked rifle: no overlay")
	var sigs := {}
	var all_ok := true
	for id: StringName in WeaponDefs.IDS:
		if id == &"carbine":
			continue
		var m := WeaponModels.mesh(id)
		if m == null:
			all_ok = false
			continue
		var bb := m.get_aabb()
		sigs["%d_%d_%d" % [roundi(bb.size.x * 40.0), roundi(bb.size.y * 40.0), roundi(bb.size.z * 40.0)]] = true
		all_ok = all_ok and bb.size.z > 0.3 and bb.size.z < 1.6 and bb.end.z > 0.2 and m.get_surface_count() == 1
	TestLib.check(all_ok, "every weapon class has ONE surface (one draw), 0.3-1.6 m long, its body behind the muzzle")
	TestLib.check(sigs.size() >= 10, "the silhouettes are distinct: %d different sizes among %d classes" % [sigs.size(), WeaponDefs.IDS.size() - 1])
	var lance := WeaponModels.mesh(&"lance").get_aabb().size
	var scatter := WeaponModels.mesh(&"scatter").get_aabb().size
	TestLib.check(lance.z >= 1.2 and scatter.z <= 1.0 and lance.z > scatter.z * 1.25, "a lance is long (%.2f m), a scatter gun short (%.2f m)" % [lance.z, scatter.z])
	TestLib.check(WeaponModels.material() is ShaderMaterial and WeaponModels.material() == WeaponModels.material(), "one shared material for every weapon")


# --- the encounter director in the live city ----------------------------------------------------------------------------

func _frame(host: Node) -> void:
	await host.get_tree().physics_frame


## Wait up to `seconds` of game time; `until` (Callable -> bool) ends the wait early. Returns the game seconds waited.
func _wait(host: Node, seconds: float, until := Callable()) -> float:
	var t := 0.0
	while t < seconds:
		await _frame(host)
		t += _dt
		_p.invuln = 5.0
		if until.is_valid() and bool(until.call()):
			break
	return t


func _test_first_contact(host: Node) -> void:
	var ppos := _p.global_position
	var t := await _wait(host, 16.0, func() -> bool: return _enc.waves_started >= 1)
	TestLib.check(_enc.waves_started >= 1, "the first squad comes within %.0f s of play (%.1f s)" % [Encounters.FIRST_DELAY + 4.0, t])
	TestLib.check(_enc.first_wave_t >= Encounters.FIRST_DELAY - 2.0 and _enc.first_wave_t <= Encounters.FIRST_DELAY + 4.0, "first contact is on the countdown (%.1f s of play)" % _enc.first_wave_t)
	TestLib.check(_enc.squad.size() >= 2 and _enc.squad.size() <= _mgr.cap(), "a squad of 2 or more, inside the tier's cap of %d (%d)" % [_mgr.cap(), _enc.squad.size()])
	var near_ok := not _enc.last_spawn_points.is_empty()
	for pt: Vector3 in _enc.last_spawn_points:
		var d := Vector2(pt.x - ppos.x, pt.z - ppos.z).length()
		near_ok = near_ok and d >= Encounters.SPAWN_MIN - 3.0 and d <= Encounters.SPAWN_MAX + 4.0
	TestLib.check(near_ok, "the squad spawns 20-34 m from the hero (%d spawn points)" % _enc.last_spawn_points.size())
	var rushers := 0
	var aware := 0
	var heat_ok := true
	for d in _enc.squad:
		aware += 1 if d.aware else 0
		heat_ok = heat_ok and d.heat_scale < 1.0 and d.reinforce
		rushers += 1 if (d is Operative and d.rush) else 0
	TestLib.check(aware == _enc.squad.size(), "every member is aware of the hero at once")
	TestLib.check(rushers >= 1 and heat_ok, "operatives rush (%d) and their kills carry a fraction of the heat" % rushers)
	TestLib.check(_enc.stings >= 1, "the threat cue played (alarm sting)")
	# they come at him: nobody shoots back for 4 s (the hero is invulnerable), the closest one is nearer than before
	var d0 := _closest(ppos)
	await _wait(host, 5.0)
	var d1 := _closest(ppos)
	TestLib.check(d1 < d0 - 2.0 or d1 < 14.0, "they close in: closest %.1f m -> %.1f m" % [d0, d1])
	TestLib.check(_enc.first_engaged_t >= 0.0 and _enc.first_engaged_t <= Encounters.FIRST_DELAY + 5.0, "time to first engagement %.1f s" % _enc.first_engaged_t)
	# a rusher spends little time in cover: hide time is a fraction of the faction's
	TestLib.check(Operative.RUSH_HIDE < 0.6 and Operative.RUSH_COVER_USE < 0.5 and Operative.RUSH_CLOSE < 0.6, "rush tuning: short hides, rare cover, closes to the middle of its range")
	_mgr.clear()
	_enc.squad.clear()


func _closest(pos: Vector3) -> float:
	var best := 1.0e9
	for d in _enc.squad:
		if is_instance_valid(d) and d.active and not d.dead:
			best = minf(best, Vector2(d.global_position.x - pos.x, d.global_position.z - pos.z).length())
	return best


func _test_fight(host: Node) -> void:
	_mgr.clear()
	_enc.reset()
	_enc._calm_t = 1.0
	Game.heat = 0.0
	var bot := FightBot.new()
	bot.setup(_p)
	bot.aim_error = 0.008
	_p.weapon.switch_to(&"carbine", true)
	var sizes: Array[int] = []
	var started := [0]
	_enc.wave_started.connect(func(_w: int, s: int) -> void:
		sizes.append(s)
		started[0] += 1)
	var samples := 0
	var engaged := 0
	var t := 0.0
	var sample_t := 0.0
	while t < 40.0:
		await _frame(host)
		t += _dt
		bot.step(_dt)
		sample_t += _dt
		if sample_t >= 1.0:
			sample_t = 0.0
			if t > 6.0:
				samples += 1
				if _aware_within(_p.global_position, 45.0) > 0:
					engaged += 1
	bot.finish()
	var kpm := bot.kills_per_minute()
	print("FIGHT BOT: %d shots, %d hits, %d kills in %.0f s = %.1f kills/min, first shot at %.1f s, waves %d, engaged %d of %d s" % [bot.shots, bot.hits, bot.kills, bot.elapsed, kpm, bot.first_shot_t, started[0], engaged, samples])
	TestLib.check(bot.first_shot_t >= 0.0 and bot.first_shot_t <= 10.0, "time to first engagement: the bot is shooting after %.1f s" % bot.first_shot_t)
	TestLib.check(bot.kills >= 3, "kills in 40 s of street fight: %d (%.1f per minute)" % [bot.kills, kpm])
	TestLib.check(bot.hits >= bot.kills * 2 and bot.shots > 20, "the shots land (%d hits of %d shots)" % [bot.hits, bot.shots])
	TestLib.check(started[0] >= 2, "a second wave follows the first (%d waves)" % started[0])
	TestLib.check(sizes.size() >= 2 and sizes[sizes.size() - 1] >= sizes[0], "waves do not shrink (%s)" % str(sizes))
	TestLib.check(samples > 0 and float(engaged) / float(samples) >= 0.6, "an enemy is aware and within 45 m %d of %d sampled seconds" % [engaged, samples])
	TestLib.check(_enc.waves_cleared >= 1 and _enc.squad_kills >= 2, "waves clear (%d) and the squad's kills are counted (%d)" % [_enc.waves_cleared, _enc.squad_kills])
	TestLib.check(Game.heat < 4.0, "a street fight alone does not max the wanted level (heat %.1f)" % Game.heat)
	for c: Dictionary in _enc.wave_started.get_connections():
		_enc.wave_started.disconnect(c["callable"])


func _aware_within(pos: Vector3, r: float) -> int:
	var n := 0
	for e in _mgr.list:
		if e.active and not e.dead and e.aware and Vector2(e.global_position.x - pos.x, e.global_position.z - pos.z).length() < r:
			n += 1
	return n


func _test_pause_and_vehicle(host: Node) -> void:
	Game.heat = 0.0
	_mgr.clear()
	_enc.reset()
	_enc._calm_t = 0.5
	Game.state = &"paused"
	var t0 := _enc.play_t
	await _wait(host, 2.0)
	TestLib.check(_enc.play_t == t0 and _mgr.alive_count() == 0, "paused (Game.state): no countdown, no squad")
	Game.state = &"play"
	var vs := GDScript.new()
	vs.source_code = "extends Node3D\nvar speed := 0.0\n"
	vs.reload()
	var dummy := Node3D.new()
	dummy.set_script(vs)
	_p.get_parent().add_child(dummy)
	_p.vehicle = dummy
	var w0 := _enc.waves_started
	await _wait(host, 2.0)
	TestLib.check(_enc.waves_started == w0 and not _enc.may_run(), "driving: the director keeps out")
	_p.vehicle = null
	dummy.queue_free()
	TestLib.check(_enc.may_run(), "on foot again: the director runs")
	await _wait(host, 3.0, func() -> bool: return _enc.waves_started > w0)
	TestLib.check(_enc.waves_started > w0, "and the next squad comes")
	_mgr.clear()
	_enc.squad.clear()


func _test_backup(_host: Node) -> void:
	Game.heat = 0.0
	_mgr.clear()
	_enc.reset()
	_enc._calm_t = 99.0
	_enc.wave = 2                                               # wave 3 has three members
	var n := _enc.start_wave(_mgr, _p.global_position)
	TestLib.check(n >= 3 and _enc.state == &"wave", "a wave of three is on (%d)" % n)
	var keep := 1
	for d in _enc.squad.duplicate():
		if keep > 0:
			keep -= 1
			continue
		d.die()
	_enc._wave_t = Encounters.BACKUP_AFTER + 1.0
	var b0 := _enc.backups
	_enc.tick(0.25)
	TestLib.check(_enc.backups == b0 + 1 and _enc.squad.size() >= 2, "one left: backup is called (%d more arrive)" % (_enc.squad.size() - 1))
	_enc.tick(0.25)
	TestLib.check(_enc.backups == b0 + 1, "backup comes once per wave")
	_mgr.clear()
	_enc.squad.clear()
	_enc.enabled = false


# --- the shot itself ----------------------------------------------------------------------------------------------------------

func _test_shot_feel(host: Node) -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Input.action_release(&"fire")
	var w := _p.weapon
	w.switch_to(&"carbine", true)
	w.ammo = w.mag
	w.fire_t = 0.0
	w.reload_t = 0.0
	await TestLib.frames(host, 2)
	_p.camera_rig.reset_view(0.0, 0.0)
	_p.camera_rig.recoil_pitch = 0.0
	var casings0: int = FX.casings.ejected
	var glow0 := _p.body._wp_glow
	w._shoot(0.016, false)
	TestLib.check(w.shells_ejected >= 1 and FX.casings.ejected == casings0 + 1 and FX.casings.live >= 1, "a shot ejects a real shell casing (%d in flight)" % FX.casings.live)
	TestLib.check(_p.camera_rig.recoil_pitch >= 0.012, "the first shot kicks the camera by %.4f rad (the old 0.0095 was too small to see)" % _p.camera_rig.recoil_pitch)
	TestLib.check(_p.body._wp_glow > glow0 and _p.body._wp_glow >= 3.0, "the weapon trim kicks light on the shot")
	var flying := -1
	for i in FX._tracers.size():
		if FX._tracer_left[i] > 0.0 and FX._tracers[i].visible:
			flying = i
	TestLib.check(flying >= 0, "a tracer is in flight")
	if flying >= 0:
		var speed: float = FX._tracer_speed[flying]
		TestLib.check(speed >= FX.TRACER_MIN_SPEED, "the streak flies at %.0f m/s (it leaves the barrel and arrives, it is not an instant line)" % speed)
		var hd0 := float((FX._tracers[flying].material_override as ShaderMaterial).get_shader_parameter(&"head_dist"))
		for k in 4:
			await host.get_tree().process_frame
		var hd1 := float((FX._tracers[flying].material_override as ShaderMaterial).get_shader_parameter(&"head_dist"))
		TestLib.check(hd1 > hd0, "the tracer's head moves along the beam (%.1f -> %.1f m)" % [hd0, hd1])
	# casings fall, bounce and vanish
	var guard := 0
	while FX.casings.live > 0 and guard < 200:
		await TestLib.frames(host, 1)
		guard += 1
	TestLib.check(FX.casings.live == 0 and not FX.casings._mmi.visible, "casings land and fade out (the draw call goes away with the last one)")
	# a kill has its own sound on top of the hit
	var dummy := _mgr.spawn(&"operative", _p.global_position + Vector3(0.0, 0.0, -12.0), true)
	if dummy != null:
		w._hit_sound(true, false)
		TestLib.check(Sfx.last_played == &"hit_kill" or Sfx.last_played == &"hit", "a kill plays its confirm sound (%s)" % Sfx.last_played)
		_mgr.clear()
	TestLib.check(FileAccess.file_exists("res://assets/audio/hit_kill.wav") and FX.TRACER_FLIGHT < 0.12, "the kill sound exists and the tracer flight is quick")
