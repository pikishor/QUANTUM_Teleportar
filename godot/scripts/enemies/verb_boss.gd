class_name VerbBoss
extends Specialist
## The verb bosses: Vael bosses built so one quantum verb is the answer. Armoured (damage x0.1) until the verb exposes them. Chosen by the type's `verb`:
##   hazard   SMELTER  (chapter 4)  vents: magenta rings on the ground arm for a few seconds (flicker one second before). ENTANGLE swaps the boss to where the player stood,
##            so stand in a ring while it is dormant or about to arm, swap, and the boss burns in it (exposed while inside an armed ring). The rings hurt the player too.
##   shield   BULWARK  (chapter 7)  a shield (hex quad) that stops every shot. COLLAPSE breaks it for a window (6 / 5 / 4 s by phase), then it reforms (flicker one second before).
##   hunter   HOUND    (chapter 7)  hunts a SUPERPOSITION decoy and ignores the player while one exists. It locks onto the decoy for 3 s (exposed, charge bar) and a decoy collapsed
##            next to it then bites a big share of its health (BACKLASH).
##   hover    SKIMMER  (chapter 5)  rides a hover skiff (an amber disc under its feet): circles the player at 14 m and RAMS along a locked line after a 0.8 s windup (a sidestep
##            dodges it). COLLAPSE crashes the skiff for 5 / 4 / 3 s by phase: it drops to the ground, cannot move and is exposed.
##   phase    PHASEWRIGHT (chapter 2)  uses QUANTUM TELEPORT: after a 0.9 s windup it phases out (invulnerable, hidden), reappears 7 m behind the player and slashes a ring after a
##            0.6 s tell. Exposed for 3 s after the slash; COLLAPSE during the windup breaks the jump (exposed 4 s).
## Phases by health (66 % / 33 %): one second of invulnerability, a ring, an ORACLE line (StoryData.VERB_BOSS_RADIO) and escalation (more rings, faster cycles, summons).
## Not pausing anything: all timers run on the physics delta.

signal phase_changed(phase: int)

const ARMOR := 0.1
const PHASE_2_AT := 0.66
const PHASE_3_AT := 0.33
const INVULN := 1.0
const HZ_RADIUS := 4.5
const HZ_DPS := 110.0
const HZ_PLAYER_DPS := 14.0
const HZ_DIST := 14.0
const BREAK_TIME := [6.0, 5.0, 4.0]
const FEED_TIME := 3.0
const FEED_RANGE := 3.6
const BACKLASH := 0.12
const SUMMON_EVERY := 10.0
const SUMMON_MAX := 2
const COLOR := Color(1.0, 0.24, 0.94)
const HOVER_LIFT := 1.1
const CRASH_TIME := [5.0, 4.0, 3.0]
const RAM_WIND := 0.8
const RAM_TIME := 1.1
const RAM_DMG := 22.0
const TP_WIND := 0.9
const TP_OUT := 0.5
const SLASH_WIND := 0.6
const SLASH_RADIUS := 4.0
const SLASH_DMG := 22.0
const EXPOSE_TIME := 3.0
const BREAK_EXPOSE := 4.0

var mode: StringName = &"hazard"
var phase := 1
var summoned: Array[Drone] = []
var hazards: Array[Vector3] = []
var shield_is_up := true
var backlashes := 0
var hazard_burns := 0.0

var _invuln_t := 0.0
var _hz_t := 0.0
var _hz_hurt := 0.0
var _arena_ready := false
var _hz_mesh: MeshInstance3D
var _hz_mat: StandardMaterial3D
var _break_t := 0.0
var _feed_t := 0.0
var _clone_near := 0.0
var _summon_t := 6.0
var crashed_t := 0.0
var crashes := 0
var rams := 0
var teleports := 0
var slashes := 0
var breaks := 0
var _lift := 0.0
var _ram_cd := 4.0
var _ram_wind := 0.0
var _ram_t := 0.0
var _ram_dir := Vector2.ZERO
var _ram_hit := false
var _platform: MeshInstance3D
var _tp_cd := 3.0
var _tp_wind := 0.0
var _tp_out := 0.0
var _slash_wind := 0.0
var _expose_t := 0.0


func setup(t: StringName) -> void:
	super.setup(t)
	mode = StringName(str(cfg.get("verb", "hazard")))
	if mode == &"shield":
		_build_shield()
		shield_node.scale = Vector3(2.0, 2.0, 2.0)
	elif mode == &"hover":
		_build_platform()


func _on_activate() -> void:
	super._on_activate()
	phase = 1
	summoned.clear()
	hazards.clear()
	_arena_ready = false
	_invuln_t = 0.0
	_hz_t = 0.0
	_hz_hurt = 0.0
	_break_t = 0.0
	_feed_t = 0.0
	_clone_near = 0.0
	_summon_t = 6.0
	crashed_t = 0.0
	crashes = 0
	rams = 0
	teleports = 0
	slashes = 0
	breaks = 0
	_lift = HOVER_LIFT if mode == &"hover" else 0.0
	_ram_cd = 4.0
	_ram_wind = 0.0
	_ram_t = 0.0
	_ram_hit = false
	_tp_cd = 3.0
	_tp_wind = 0.0
	_tp_out = 0.0
	_slash_wind = 0.0
	_expose_t = 0.0
	if _platform != null:
		_platform.visible = true
	if model != null:
		model.visible = true
	shield_is_up = mode == &"shield"
	backlashes = 0
	hazard_burns = 0.0
	if shield_node != null:
		shield_node.visible = shield_is_up
	Sfx.boss_active = true
	Sfx.boss_phase = 1
	_say("intro")


func deactivate() -> void:
	Sfx.boss_active = false
	if _platform != null:
		_platform.visible = false
	if _hz_mesh != null:
		_hz_mesh.visible = false
	super.deactivate()


func die() -> void:
	super.die()
	Sfx.boss_active = false
	_tp_out = 0.0
	if model != null:
		model.visible = true
	if _platform != null:
		_platform.visible = false
	if _hz_mesh != null:
		_hz_mesh.visible = false
	var mgr := Game.enemies as EnemyManager
	if mgr != null:
		for s in summoned.duplicate():
			if is_instance_valid(s) and s.active:
				mgr.release(s)
	summoned.clear()
	_say("down")


func _death_effect() -> void:
	super._death_effect()
	Game.explode(center(), 8.0, {"enemy_dmg": 0.0, "car_dmg": 0.0, "player_dmg": 0.0, "color": COLOR})


# --- state for the HUD, the runner and tests ------------------------------------------------------------------------------

func hp_fraction() -> float:
	return clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)


func is_invulnerable() -> bool:
	return _invuln_t > 0.0


func bar_time() -> float:
	return 0.0 if dead else BAR_SECONDS


func hazard_armed() -> bool:
	if mode != &"hazard" or hazards.is_empty():
		return false
	return fmod(_hz_t, _hz_rest() + _hz_armed()) >= _hz_rest()


## True during the second before the rings arm (they flicker).
func hazard_warning() -> bool:
	if mode != &"hazard" or hazards.is_empty():
		return false
	var c := fmod(_hz_t, _hz_rest() + _hz_armed())
	return c >= _hz_rest() - 1.0 and c < _hz_rest()


func in_hazard(pos: Vector3) -> bool:
	for h in hazards:
		if Vector2(pos.x - h.x, pos.z - h.z).length() <= HZ_RADIUS:
			return true
	return false


## Is the boss hurt by every shot right now (the verb has exposed it)?
func exposed() -> bool:
	match mode:
		&"hazard":
			return hazard_armed() and in_hazard(global_position)
		&"shield":
			return not shield_is_up
		&"hunter":
			return _feed_t > 0.0
		&"hover":
			return crashed_t > 0.0
		&"phase":
			return _expose_t > 0.0
	return false


func break_left() -> float:
	return _break_t


func feeding() -> bool:
	return _feed_t > 0.0


func _hz_armed() -> float:
	return 6.0 + 1.5 * float(phase - 1)


func _hz_rest() -> float:
	return 3.0 - 0.5 * float(phase - 1)


# --- damage ----------------------------------------------------------------------------------------------------------------

func damage(amount: float, crit := false, mirrored := false) -> void:
	if dead or not active:
		return
	if _invuln_t > 0.0:
		_flash = 0.1
		return
	if mode == &"phase" and _tp_out > 0.0:
		return                                                  # phased out: hits pass through
	if mode == &"shield" and shield_is_up:
		_flash = 0.1
		_bar_t = BAR_SECONDS
		aware = true
		return
	if not exposed():
		amount *= ARMOR
	super.damage(amount, crit, mirrored)
	if not dead:
		_bar_t = BAR_SECONDS
		_check_phase()


## Damage that skips the armour (the rings, the decoy's backlash).
func _raw(amount: float) -> void:
	if dead or not active or _invuln_t > 0.0:
		return
	super.damage(amount, false, true)
	if not dead:
		_bar_t = BAR_SECONDS
		_check_phase()


## COLLAPSE (Quantum.collapse_all) calls this on every enemy in range: it breaks the BULWARK's shield.
func disable(seconds: float) -> void:
	if mode == &"hover" and crashed_t <= 0.0 and not dead and active:
		crashed_t = CRASH_TIME[clampi(phase - 1, 0, 2)]
		crashes += 1
		_ram_wind = 0.0
		_ram_t = 0.0
		_ram_cd = 5.0
		FX.blast(center(), 6.0, COLOR, 0.4)
		FX.shake(0.4)
		_say("crash")
	if mode == &"phase" and _tp_wind > 0.0 and not dead and active:
		_tp_wind = 0.0
		_tp_cd = 3.0
		_expose_t = BREAK_EXPOSE
		breaks += 1
		FX.blast(center(), 6.0, COLOR, 0.4)
		FX.shake(0.4)
		_say("break")
	if mode == &"shield" and shield_is_up and not dead and active:
		shield_is_up = false
		_break_t = BREAK_TIME[clampi(phase - 1, 0, 2)]
		if shield_node != null:
			shield_node.visible = false
		FX.blast(center(), 6.0, COLOR, 0.4)
		FX.shake(0.4)
		_say("break")
	super.disable(minf(seconds, 1.0))


func _check_phase() -> void:
	var f := hp_fraction()
	var np := 1 if f > PHASE_2_AT else (2 if f > PHASE_3_AT else 3)
	if np <= phase:
		return
	phase = np
	Sfx.boss_phase = np
	_invuln_t = INVULN
	FX.blast(center(), 7.0, COLOR, 0.5)
	FX.shake(0.6)
	_say("phase%d" % phase)
	_summon_t = 2.0
	if mode == &"hazard":
		_build_hazards()
	phase_changed.emit(phase)


func _say(key: String) -> void:
	if not is_instance_valid(Game.story) or not Game.story.has_method(&"say"):
		return
	var lines: Array = StoryData.VERB_BOSS_RADIO.get(str(mode), {}).get(key, [])
	if lines.is_empty():
		return
	var l: Dictionary = lines[randi() % lines.size()]
	Game.story.call(&"say", str(l["s"]), str(l["t"]), "vboss.%s.%s" % [mode, key], 0.0, 2)


# --- behaviour -------------------------------------------------------------------------------------------------------------

func _move_aware(delta: float, ux: float, uz: float, d: float, speed: float, rng: float) -> void:
	_invuln_t = maxf(0.0, _invuln_t - delta)
	_tick_boss(delta)
	if mode == &"hover":
		_move_hover(delta, ux, uz, d, speed)
		return
	if mode == &"phase":
		if _move_phase(delta, ux, uz, d, speed):
			return
		speed *= 1.0 + 0.15 * float(phase - 1)
	if mode == &"hunter":
		if _feed_t > 0.0:
			_speed = 0.0
			return
		var mgr := Game.enemies as EnemyManager
		var c: Node3D = mgr.get_clone() if mgr != null else null
		if c != null:
			var dx := c.global_position.x - global_position.x
			var dz := c.global_position.z - global_position.z
			var dd := maxf(sqrt(dx * dx + dz * dz), 0.01)
			_mx = dx / dd
			_mz = dz / dd
			_speed = speed * (1.5 if phase >= 2 else 1.3)
			return
	super._move_aware(delta, ux, uz, d, speed * (1.25 if phase == 3 else 1.0), rng)


func _fire_cycle(delta: float, d: float, rng: float) -> void:
	if _feed_t > 0.0 or _ram_wind > 0.0 or _ram_t > 0.0 or _tp_wind > 0.0 or _tp_out > 0.0 or _slash_wind > 0.0:
		return
	if mode == &"hunter":
		var mgr := Game.enemies as EnemyManager
		if mgr != null and mgr.get_clone() != null:
			return                                       # it only has eyes for the decoy
	super._fire_cycle(delta, d, rng)


func _tick_boss(delta: float) -> void:
	for i in range(summoned.size() - 1, -1, -1):
		var s := summoned[i]
		if not is_instance_valid(s) or not s.active or s.dead:
			summoned.remove_at(i)
	if mode != &"hunter" or phase >= 2:
		_summon_t -= delta
		if _summon_t <= 0.0 and phase >= (1 if mode == &"shield" else 2):
			_summon_t = SUMMON_EVERY / Difficulty.mult("aggr")
			_summon(1, &"sentinel" if phase == 1 else &"striker")
	match mode:
		&"hazard":
			if not _arena_ready:
				_arena_ready = true
				_build_hazards()
			_tick_hazards(delta)
		&"shield":
			if _break_t > 0.0:
				_break_t -= delta
				if shield_node != null:
					shield_node.visible = _break_t < 1.0 and int(_break_t * 12.0) % 2 == 0     # flickers back
				if _break_t <= 0.0:
					_break_t = 0.0
					shield_is_up = true
					if shield_node != null:
						shield_node.visible = true
					_say("reform")
		&"hunter":
			_tick_hunter(delta)
		&"hover":
			_lift = move_toward(_lift, 0.0 if crashed_t > 0.0 else HOVER_LIFT, delta * 3.0)
			if crashed_t > 0.0:
				crashed_t = maxf(crashed_t - delta, 0.0)
			if _platform != null:
				_platform.visible = not dead and (crashed_t <= 0.0 or int(crashed_t * 8.0) % 2 == 0)
		&"phase":
			_expose_t = maxf(_expose_t - delta, 0.0)
			if model != null:
				model.visible = _tp_out <= 0.0


func _tick_hazards(delta: float) -> void:
	_hz_t += delta
	var armed := hazard_armed()
	if _hz_mat != null:
		var a := 0.5 if armed else (0.35 if hazard_warning() and int(_hz_t * 10.0) % 2 == 0 else 0.1)
		_hz_mat.albedo_color = Color(1.2, 0.3, 1.1, a)
	if not armed:
		return
	if in_hazard(global_position):
		hazard_burns += delta
		_raw(HZ_DPS * delta)
	var p := Game.player
	if is_instance_valid(p) and in_hazard(p.global_position):
		_hz_hurt -= delta
		if _hz_hurt <= 0.0:
			_hz_hurt = 0.5
			p.call(&"damage", HZ_PLAYER_DPS * 0.5, global_position)


func _tick_hunter(delta: float) -> void:
	var mgr := Game.enemies as EnemyManager
	var c: Node3D = mgr.get_clone() if mgr != null else null
	if c != null:
		var near := Vector2(c.global_position.x - global_position.x, c.global_position.z - global_position.z).length()
		_clone_near = near
		if _feed_t <= 0.0 and near < FEED_RANGE:
			_feed_t = FEED_TIME
			_say("lock")
	elif _clone_near >= 0.0:
		# the decoy is gone: if it went off while we fed on it next to us, it bites back
		if _feed_t > 0.0 and _clone_near < 6.0:
			backlashes += 1
			_raw(max_hp * BACKLASH)
			stagger(1.5)
			FX.blast(center(), 6.0, COLOR, 0.4)
			_say("backlash")
		_clone_near = -1.0
	if _feed_t > 0.0:
		_feed_t = maxf(_feed_t - delta, 0.0)
		if c == null and _feed_t > 0.5:
			_feed_t = 0.5                                      # nothing left to feed on


func _summon(count: int, type: StringName) -> int:
	var mgr := Game.enemies as EnemyManager
	if mgr == null:
		return 0
	var made := 0
	for i in count:
		if summoned.size() >= SUMMON_MAX:
			break
		var a := randf() * TAU
		var s := mgr.spawn(type, global_position + Vector3(cos(a), 0.0, sin(a)) * randf_range(5.0, 8.0), true)
		if s == null:
			break
		summoned.append(s)
		made += 1
		FX.burst(s.center(), s.cfg["color"], 10, 5.0, 0.5, 0.0)
	return made


func threat_charge() -> float:
	if dead:
		return 0.0
	if _ram_wind > 0.0:
		return clampf(1.0 - _ram_wind / RAM_WIND, 0.0, 1.0)
	if _tp_wind > 0.0:
		return clampf(1.0 - _tp_wind / TP_WIND, 0.0, 1.0)
	if _slash_wind > 0.0:
		return clampf(1.0 - _slash_wind / SLASH_WIND, 0.0, 1.0)
	if _feed_t > 0.0:
		return clampf(_feed_t / FEED_TIME, 0.0, 1.0)
	if mode == &"hazard" and hazard_warning():
		return clampf(fmod(_hz_t, _hz_rest() + _hz_armed()) - (_hz_rest() - 1.0), 0.0, 1.0)
	if mode == &"shield" and _break_t > 0.0 and _break_t < 1.0:
		return 1.0 - _break_t
	return super.threat_charge()


# --- the rings ---------------------------------------------------------------------------------------------------------------

## Rings round the arena centre (the boss's spot when it woke): two in phase 1, three after. One mesh, one draw call.
func _build_hazards() -> void:
	var c := global_position if hazards.is_empty() else _hz_center()
	var n := 2 if phase == 1 else 3
	hazards.clear()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var a := 0.6 + TAU * float(i) / float(n)
		var h := Vector3(c.x + cos(a) * HZ_DIST, 0.0, c.z + sin(a) * HZ_DIST)
		hazards.append(h)
		var y := _ground_y(h.x, h.z) + 0.07
		for k in 24:
			var a0 := TAU * float(k) / 24.0
			var a1 := TAU * float(k + 1) / 24.0
			st.add_vertex(Vector3(h.x, y, h.z))
			st.add_vertex(Vector3(h.x + cos(a1) * HZ_RADIUS, y, h.z + sin(a1) * HZ_RADIUS))
			st.add_vertex(Vector3(h.x + cos(a0) * HZ_RADIUS, y, h.z + sin(a0) * HZ_RADIUS))
	_hz_center_v = c
	if _hz_mesh == null:
		_hz_mesh = MeshInstance3D.new()
		_hz_mesh.name = "Hazards"
		_hz_mesh.top_level = true
		_hz_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hz_mat = StandardMaterial3D.new()
		_hz_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hz_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hz_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_hz_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_hz_mat.albedo_color = Color(1.2, 0.3, 1.1, 0.1)
		_hz_mesh.material_override = _hz_mat
		add_child(_hz_mesh)
	_hz_mesh.global_transform = Transform3D.IDENTITY
	_hz_mesh.mesh = st.commit()
	_hz_mesh.visible = true


var _hz_center_v := Vector3.ZERO


func _hz_center() -> Vector3:
	return _hz_center_v


# --- hover: the skiff ---------------------------------------------------------------------------------------------------------

func _ground_y(x: float, z: float) -> float:
	return super._ground_y(x, z) + (_lift if mode == &"hover" else 0.0)


func _build_platform() -> void:
	_platform = MeshInstance3D.new()
	_platform.name = "Skiff"
	var cm := CylinderMesh.new()
	cm.top_radius = 1.5
	cm.bottom_radius = 1.2
	cm.height = 0.2
	cm.radial_segments = 16
	cm.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.15)
	mat.emission_energy_multiplier = 1.6
	cm.material = mat
	_platform.mesh = cm
	_platform.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_platform)


func _move_hover(delta: float, ux: float, uz: float, d: float, speed: float) -> void:
	if crashed_t > 0.0:
		_speed = 0.0
		return
	_ram_cd = maxf(_ram_cd - delta, 0.0)
	if _ram_wind > 0.0:
		_speed = 0.0
		_ram_wind -= delta
		if _ram_wind <= 0.0:
			_ram_t = RAM_TIME
			_ram_hit = false
			_ram_dir = Vector2(ux, uz)                          # locked: a sidestep dodges it
		return
	if _ram_t > 0.0:
		_ram_t -= delta
		_mx = _ram_dir.x
		_mz = _ram_dir.y
		_speed = speed * 3.2
		if d < 2.6 and not _ram_hit:
			_ram_hit = true
			rams += 1
			var p := Game.player
			if is_instance_valid(p):
				p.call(&"damage", RAM_DMG, global_position)
			FX.shake(0.4)
		if _ram_t <= 0.0 or _ram_hit:
			_ram_t = 0.0
			_ram_cd = maxf(2.5, 6.0 - 1.0 * float(phase - 1))
		return
	if _ram_cd <= 0.0 and d < 34.0 and d > 5.0:
		_ram_wind = RAM_WIND
		Sfx.play_at(&"boom", center(), -10.0, 0.6)
		return
	var radial := clampf((d - 14.0) / 6.0, -1.0, 1.0)
	var m := Vector2(-uz * _strafe + ux * radial, ux * _strafe + uz * radial).normalized()
	_mx = m.x
	_mz = m.y
	_speed = speed * 1.8


# --- phase: QUANTUM TELEPORT --------------------------------------------------------------------------------------------------

## Returns true when it drove the movement this tick.
func _move_phase(delta: float, _ux: float, _uz: float, d: float, _speed_in: float) -> bool:
	if _tp_out > 0.0:
		_speed = 0.0
		_tp_out -= delta
		if _tp_out <= 0.0:
			_tp_out = 0.0
			if model != null:
				model.visible = true
			FX.blast(center(), 4.0, COLOR, 0.3)
			_slash_wind = SLASH_WIND
		return true
	if _slash_wind > 0.0:
		_speed = 0.0
		_slash_wind -= delta
		if _slash_wind <= 0.0:
			_slash_wind = 0.0
			slashes += 1
			_expose_t = EXPOSE_TIME
			var at := Vector3(global_position.x, global_position.y + 0.15, global_position.z)
			Game.explode(at, SLASH_RADIUS, {"enemy_dmg": 0.0, "car_dmg": 12.0, "player_dmg": SLASH_DMG, "color": COLOR})
			FX.shake(0.5)
		return true
	if _tp_wind > 0.0:
		_speed = 0.0
		_tp_wind -= delta
		if _tp_wind <= 0.0:
			_tp_wind = 0.0
			_teleport()
		return true
	_tp_cd = maxf(_tp_cd - delta, 0.0)
	if _tp_cd <= 0.0 and d < 40.0 and _tgt_ok:
		_tp_wind = TP_WIND
		FX.blast(center(), 3.0, Color(0.4, 0.9, 1.0), 0.3)
		return true
	return false


## QUANTUM TELEPORT: a trail from the old spot to a point behind the player, phased out for TP_OUT seconds.
func _teleport() -> void:
	var from := center()
	var c := _tgt if _tgt_ok else global_position
	var dir := Vector3(c.x - global_position.x, 0.0, c.z - global_position.z)
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	var nx := c.x + dir.x * 7.0
	var nz := c.z + dir.z * 7.0
	global_position = Vector3(nx, _ground_y(nx, nz), nz)
	_have_last = false
	var to := center()
	var n := 5
	for i in n:
		FX.burst(from.lerp(to, float(i) / float(n - 1)), Color(0.4, 0.9, 1.0) if i % 2 == 0 else COLOR, 6, 2.5, 0.5, 0.0)
	teleports += 1
	_tp_out = TP_OUT
	_tp_cd = maxf(2.0, 5.0 - 1.0 * float(phase - 1))
	if model != null:
		model.visible = false
	Sfx.play_at(&"blink", center(), -4.0, 1.0)
