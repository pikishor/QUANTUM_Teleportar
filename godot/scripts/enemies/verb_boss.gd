class_name VerbBoss
extends Specialist
## The verb bosses: Vael bosses built so one quantum verb is the answer. Armoured (damage x0.1) until the verb exposes them. Chosen by the type's `verb`:
##   hazard   SMELTER  (chapter 4)  vents: magenta rings on the ground arm for a few seconds (flicker one second before). ENTANGLE swaps the boss to where the player stood,
##            so stand in a ring while it is dormant or about to arm, swap, and the boss burns in it (exposed while inside an armed ring). The rings hurt the player too.
##   shield   BULWARK  (chapter 7)  a shield (hex quad) that stops every shot. COLLAPSE breaks it for a window (6 / 5 / 4 s by phase), then it reforms (flicker one second before).
##   hunter   HOUND    (chapter 7)  hunts a SUPERPOSITION decoy and ignores the player while one exists. It locks onto the decoy for 3 s (exposed, charge bar) and a decoy collapsed
##            next to it then bites a big share of its health (BACKLASH).
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


func setup(t: StringName) -> void:
	super.setup(t)
	mode = StringName(str(cfg.get("verb", "hazard")))
	if mode == &"shield":
		_build_shield()
		shield_node.scale = Vector3(2.0, 2.0, 2.0)


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
	shield_is_up = mode == &"shield"
	backlashes = 0
	hazard_burns = 0.0
	if shield_node != null:
		shield_node.visible = shield_is_up
	Sfx.boss_active = true
	_say("intro")


func deactivate() -> void:
	Sfx.boss_active = false
	if _hz_mesh != null:
		_hz_mesh.visible = false
	super.deactivate()


func die() -> void:
	super.die()
	Sfx.boss_active = false
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
	if _feed_t > 0.0:
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
		if _summon_t <= 0.0 and phase >= (2 if mode == &"hazard" else 1):
			_summon_t = SUMMON_EVERY
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
