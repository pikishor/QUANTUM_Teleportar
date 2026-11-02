class_name Overseer
extends Specialist
## The Vael Overseer, the boss of the chapter 3 and chapter 6 contracts (ContractTypes `boss`): the operative rig at 1.95x in violet with a crest of spikes (one extra draw).
## Three phases by health (above 66 %, above 33 %, below):
##   1  SUMMONS   every 9 s two sentinels or a striker appear around him (at most 3 of his drones alive, caps respected); he fires four-round bursts at 20-30 m.
##   2  PULSES    every 8 s he plants, raises his shield (damage x0.12 while it is up) and charges for 2 s (EnemyMarks charge, threat_charge 0..1), then a shield pulse hits the player
##                within 38 m unless something solid stands between them (the COVER-TIMING mechanic: hide behind a prop at the charge, come out and shoot after the pulse).
##   3  ENRAGE    1.5x speed, ground slams (radius 6.5 m, 32 damage after a 0.55 s windup) whenever he is within 6 m, a striker pair as the phase begins and then every 14 s.
## Each phase change makes him invulnerable for 1 s, flashes a violet ring and sends an ORACLE radio line (StoryData.BOSS_RADIO). While he lives Sfx.boss_active is true (the music state `boss`).

signal phase_changed(phase: int)

const PHASE_2_AT := 0.66
const PHASE_3_AT := 0.33
const SUMMON_EVERY := 9.0
const SUMMON_MAX := 3
const PULSE_EVERY := 8.0
const OV_PULSE_WIND := 2.0
const PULSE_RADIUS := 38.0
const PULSE_DAMAGE := 30.0
const PULSE_SHIELD_FACTOR := 0.12
const INVULN := 1.0
const ENRAGE_SPEED := 1.5
const OPEN_TIME := 3.0
const OPEN_FACTOR := 1.5

var phase := 1
var pulses_fired := 0
var pulse_hits := 0
var summoned: Array[Drone] = []

var _invuln_t := 0.0
var _open_t := 0.0                     ## COLLAPSE broke the pulse: damage x1.5 for OPEN_TIME seconds
var _summon_t := 4.0
var _pulse_t := PULSE_EVERY
var _ov_pulse_wind := 0.0
var _spikes: MeshInstance3D


func setup(t: StringName) -> void:
	super.setup(t)
	_build_spikes()


func _on_activate() -> void:
	super._on_activate()
	phase = 1
	pulses_fired = 0
	pulse_hits = 0
	summoned.clear()
	_invuln_t = 0.0
	_summon_t = 4.0
	_pulse_t = PULSE_EVERY
	_ov_pulse_wind = 0.0
	_open_t = 0.0
	Sfx.boss_active = true
	_say("phase1")


func deactivate() -> void:
	Sfx.boss_active = false
	super.deactivate()


func die() -> void:
	super.die()
	Sfx.boss_active = false
	var mgr := Game.enemies as EnemyManager
	if mgr != null:
		for s in summoned.duplicate():                       # the hive link snaps: his drones go with him
			if is_instance_valid(s) and s.active:
				mgr.release(s)
	summoned.clear()
	_say("down")


func _death_effect() -> void:
	super._death_effect()
	Game.explode(center(), 8.0, {"enemy_dmg": 0.0, "car_dmg": 0.0, "player_dmg": 0.0, "color": Color(0.72, 0.3, 1.0)})


func _build_spikes() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 9
	for i in n:
		var a := lerpf(-1.25, 1.25, float(i) / float(n - 1))         # an arc over the shoulders, at the back
		var base := Vector3(sin(a) * 0.42, 1.45 + 0.1 * cos(a * 2.0), 0.28 + 0.08 * absf(a))
		var tip := base + Vector3(sin(a) * 0.35, 0.65 + 0.2 * (1.0 - absf(a) / 1.3), 0.35)
		var side := Vector3(cos(a), 0.0, -sin(a)) * 0.09
		var fwd := Vector3(0.0, 0.0, 0.1)
		for tri: Array in [[base - side, base + side, tip], [base + side, base + fwd, tip], [base + fwd, base - side, tip]]:
			for v: Vector3 in tri:
				st.add_vertex(v * _base_scale)
	st.generate_normals()
	_spikes = MeshInstance3D.new()
	_spikes.name = "Spikes"
	_spikes.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.05, 0.14)
	mat.emission_enabled = true
	mat.emission = Color(0.72, 0.3, 1.0)
	mat.emission_energy_multiplier = 1.4
	mat.roughness = 0.4
	_spikes.material_override = mat
	_spikes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_spikes)


func hp_fraction() -> float:
	return clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)


func _phase_for(f: float) -> int:
	return 1 if f > PHASE_2_AT else (2 if f > PHASE_3_AT else 3)


func shield_active() -> bool:
	return _ov_pulse_wind > 0.0


func is_invulnerable() -> bool:
	return _invuln_t > 0.0


func damage(amount: float, crit := false, mirrored := false) -> void:
	if dead or not active:
		return
	if _invuln_t > 0.0:
		_flash = 0.1
		return
	if _ov_pulse_wind > 0.0:
		amount *= PULSE_SHIELD_FACTOR
	elif _open_t > 0.0:
		amount *= OPEN_FACTOR
	super.damage(amount, crit, mirrored)
	if not dead:
		_bar_t = BAR_SECONDS
		_check_phase()


## COLLAPSE (Quantum.collapse_all disables every enemy in range): a charging pulse is cancelled and he is open for OPEN_TIME seconds.
func disable(seconds: float) -> void:
	if _ov_pulse_wind > 0.0 and not dead and active:
		_ov_pulse_wind = 0.0
		_open_t = OPEN_TIME
		_pulse_t = PULSE_EVERY
		FX.blast(center(), 6.0, Color(0.3, 0.94, 1.0), 0.4)
	super.disable(minf(seconds, 1.0))


func is_open() -> bool:
	return _open_t > 0.0


func _check_phase() -> void:
	var np := _phase_for(hp_fraction())
	if np <= phase:
		return
	phase = np
	_invuln_t = INVULN
	_ov_pulse_wind = 0.0
	_slam_wind = 0.0
	FX.blast(center(), 7.0, Color(0.72, 0.3, 1.0), 0.5)
	FX.shake(0.6)
	_say("phase%d" % phase)
	if phase == 2:
		_pulse_t = 3.0
	elif phase == 3:
		_summon(2, &"striker")
		_summon_t = 14.0
	phase_changed.emit(phase)


func _say(key: String) -> void:
	if not is_instance_valid(Game.story) or not Game.story.has_method(&"say"):
		return
	var lines: Array = StoryData.BOSS_RADIO.get(key, [])
	if lines.is_empty():
		return
	var l: Dictionary = lines[randi() % lines.size()]
	Game.story.call(&"say", str(l["s"]), str(l["t"]), "boss.%s" % key, 0.0, 2)


func _turn_rate() -> float:
	return 1.4 if _ov_pulse_wind > 0.0 else 5.0


func _move_aware(delta: float, ux: float, uz: float, d: float, speed: float, rng: float) -> void:
	_invuln_t = maxf(0.0, _invuln_t - delta)
	_open_t = maxf(0.0, _open_t - delta)
	_tick_boss(delta)
	if _ov_pulse_wind > 0.0:
		_speed = 0.0
		_ov_pulse_wind -= delta
		_tele = 0.0
		if _ov_pulse_wind <= 0.0:
			_ov_pulse_wind = 0.0
			_pulse()
		return
	if phase == 3:
		_slam_cd = maxf(0.0, _slam_cd - delta)
		if _slam_wind > 0.0:
			_speed = 0.0
			_slam_wind -= delta
			if _slam_wind <= 0.0:
				_slam()
			return
		if d < 6.0 and _slam_cd <= 0.0:
			_slam_wind = SLAM_WIND
			return
		if d > 7.0:
			_mx = ux
			_mz = uz
			_speed = speed * ENRAGE_SPEED
			return
	super._move_aware(delta, ux, uz, d, speed * (ENRAGE_SPEED if phase == 3 else 1.0), rng)


func _fire_cycle(delta: float, d: float, rng: float) -> void:
	if _ov_pulse_wind > 0.0 or _slam_wind > 0.0:
		return
	super._fire_cycle(delta, d, rng)


func _tick_boss(delta: float) -> void:
	for i in range(summoned.size() - 1, -1, -1):
		var s := summoned[i]
		if not is_instance_valid(s) or not s.active or s.dead:
			summoned.remove_at(i)
	_summon_t -= delta
	if phase != 2 and _summon_t <= 0.0:
		_summon_t = SUMMON_EVERY if phase == 1 else 14.0
		_summon(2 if phase == 1 else 1, &"sentinel" if phase == 1 and randf() < 0.7 else &"striker")
	if phase == 2:
		_pulse_t -= delta
		if _pulse_t <= 0.0 and _ov_pulse_wind <= 0.0:
			_pulse_t = PULSE_EVERY
			_ov_pulse_wind = OV_PULSE_WIND
			Sfx.play_at(&"boom", center(), -6.0, 0.6)
			_say("pulse")


func _summon(count: int, type: StringName) -> int:
	var mgr := Game.enemies as EnemyManager
	if mgr == null:
		return 0
	var made := 0
	for i in count:
		if summoned.size() >= SUMMON_MAX:
			break
		var a := randf() * TAU
		var at := global_position + Vector3(cos(a), 0.0, sin(a)) * randf_range(5.0, 8.0)
		var s := mgr.spawn(type, at, true)
		if s == null:
			break
		summoned.append(s)
		made += 1
		FX.burst(s.center(), s.cfg["color"], 14, 5.0, 0.5, 0.0)
	return made


## The shield pulse: hits the player within PULSE_RADIUS unless the world (a wall or any prop collider) is between us.
func _pulse() -> void:
	pulses_fired += 1
	var o := center()
	FX.blast(Vector3(global_position.x, global_position.y + 0.3, global_position.z), 10.0, Color(0.72, 0.3, 1.0), 0.5)
	FX.shake(0.4)
	var p := Game.player
	if not is_instance_valid(p):
		return
	var t: Vector3 = p.call(&"chest_position") if p.has_method(&"chest_position") else p.global_position + Vector3(0.0, 1.2, 0.0)
	if o.distance_to(t) > PULSE_RADIUS or _line_clear(o, t) == false:
		return
	pulse_hits += 1
	p.call(&"damage", PULSE_DAMAGE, o)


func _slam_radius() -> float:
	return 6.5


func _slam_damage() -> float:
	return 32.0


func threat_charge() -> float:
	if dead:
		return 0.0
	if _ov_pulse_wind > 0.0:
		return clampf(1.0 - _ov_pulse_wind / OV_PULSE_WIND, 0.0, 1.0)
	if _slam_wind > 0.0:
		return clampf(1.0 - _slam_wind / SLAM_WIND, 0.0, 1.0)
	return super.threat_charge()


func bar_time() -> float:
	return 0.0 if dead else BAR_SECONDS


## Where the pulse is in its cycle (tests): seconds of charge left, 0 when not charging.
func pulse_left() -> float:
	return _ov_pulse_wind
