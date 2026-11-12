class_name Operative
extends Drone
## Observer Corp rifleman (hp 80): the human enemy. Patrols near home, notices the player (or the quantum clone), takes aim for a moment, fires short
## three-round bursts with a tracer and a spread that grows with distance, strafes between bursts, backs off when pressed, flanks when it has no line of
## sight for a while, and calls for help when hit (alerts everyone within 50 m). Street props have no colliders, so there is no cover system: the strafe and
## the aim windup stand in for peeking.
## Visuals: Game.load_model("operative"), an articulated skinned model (one draw call) posed by CharacterRig: stride cycle with knee bends along the real
## speed and direction (strafe, back-pedal), rifle at low ready while patrolling and shouldered for the aim windup and the burst (both hands on the rifle, the
## head follows the aim pitch), recoil kick per round, hit flinch, and a death fall (the knees buckle, the body drops onto its side and goes limp).
## Without the model: a primitive humanoid with LegL / LegR (swung by the speed). Hits show dust and armour chips, blood only behind Game.graphic_violence.

const HELP_RADIUS := 50.0
const CORPSE_TIME := 4.0
const FALL_TIME := 0.45
const STRIDE_RAD_PER_M := 3.2
const LEG_AMP := 0.62
const FLANK_AFTER := 2.5
const STRIDE_RATE := 1.7               ## stride phase per metre travelled (the rig)
const READY_IDLE := 0.45               ## rifle at low ready while patrolling
const READY_AWARE := 0.8

var leg_l: Node3D                      ## hip pivots (the primitive's legs hang from them; with the model they mirror the thigh swing)
var leg_r: Node3D
var rig: CharacterRig
var hanim: HumanoidAnim                ## upper-body state machine of the Vael humanoid model (aim, fire, flinch, die, weapon mount); null for the old model and every specialist

var rush := false                      ## an encounter squad member (Encounters): closes to the middle of its range and hides only for a moment (RUSH_* below); activate() clears it
var _aim_t := 0.0
var _burst_left := 0
var _shot_t := 0.0
var _no_los := 0.0
var _flank := 1.0
var _stride := 0.0
var _roll_sign := 1.0
var _lean := 0.0
var _volley_origin := Vector3.ZERO
var _phase := 0.0
var _amp := 0.0
var _dir := Vector2(0.0, 1.0)         ## smoothed body-space movement direction (x right, y forward)
var _ready := READY_IDLE
var _aim_pitch := 0.0
var _kick := 0.0
var _flinch := 0.0
var _clock := 0.0
var _buckle := 0.0
var loco: Locomotion
var _last_pos := Vector3.ZERO
var _have_last := false
var _fdir := Vector2.ZERO               ## where the last hit came from, body space (x right, y forward)
var _death_kind := 0                    ## 0 onto the side, 1 forward, 2 backward
var _rest_drop := 0.0
var _aim_override := Vector3.INF            ## where the next round is aimed when it is not at the target (the sniper lock)
var _called := false                    ## the squad callout of this life has been made
var _assigned_t := 0.0                  ## seconds of an assigned flank left
var _cover_on := false
var _cover := Vector3.INF
var _cover_state := 0                   ## 0 none, 1 running to cover, 2 hidden, 3 peeking
var _cover_t := 0.0
var _cover_cd := 0.0
var _cover_dir := Vector2.ZERO
var _cover_search_t := 0.0
var _peeked := false
var tactic_role: StringName = &""       ## squad role from the callout: anchor (holds cover, suppresses), flanker (arcs round), pusher (closes in)
var _camp_t := 0.0                      ## seconds the target has stayed put
var _camp_ref := Vector3.INF
var _camp_flank_cd := 0.0
var _suppress_cd := 0.0
var _suppressing := false
static var round_stats := {"fired": 0, "hit": 0, "near": 0}     ## every round that flew at the hero (blocked ones do not count), how many hit and how many passed within NEAR_MISS; tests and bots read and reset it
var suppress_bursts := 0                ## suppressing bursts fired this life (blind fire at the target from cover)
var _retreating := false
var _reinforce_called := false
var faction: StringName = TacticsTable.OBSERVER   ## TacticsTable row: observer (disciplined), vael (hive rush), raider (hit and run); picked on activation, tests may set it
var _leaping := false                   ## running from one cover to a closer one while the squad covers (leapfrog)
var leaps := 0                          ## leapfrog advances this life
var flushes := 0                        ## flush grenades thrown this life
var regroups := 0                       ## times it came back from a retreat
var _retreat_t := 0.0
var _regroup_immune := 0.0
var unsticks := 0                       ## times it side-stepped along a wall it was pushing into (no path finding: a blocked flank or advance gets a sidestep)
var _last_xz := Vector2.INF
var _blk_t := 0.0
var _unstick_t := 0.0
var _unstick_dir := 1.0
var kit: StringName = &"rifleman"       ## squad kit of the roster look (TacticsTable.KITS): set by set_kit() when the director spawns the trooper
var kit_set := false                    ## the director gave this trooper a squad kit (spawn with a look)
var squad_job := false                  ## the director gave this trooper a squad role (set_squad_role), with a kit or without (a backup): the director's squad fights to the end, it never retreats
var kit_speed := 1.0
var kit_range := 1.0
var kit_hp := 1.0
var kit_aim := 1.0
var kit_cover := 1.0
var _hit_k := 0.0                       ## 1 on a hit, fades in ~0.12 s: the body flashes white-hot (hero_body.gdshader hit_k)
var _crouch := 0.0                      ## 0..1: crouched behind low cover (the model's height squashes; the head and shoulders stay above the cover)
var throws := false                     ## a grenadier / commander lobs grenades at the hero
var grenades_thrown := 0                ## this life
var _grenade_cd := 0.0
var _grenade_wind := 0.0
const UNSTICK_AFTER := 1.0
const UNSTICK_FOR := 2.2
const CALL_HP := 0.5
const RUSH_COVER_USE := 0.3            ## a rusher looks for cover this often (x the faction's cover_use)
const RUSH_HIDE := 0.45                ## ... and hides this share of the faction's hide time
const RUSH_CLOSE := 0.4                ## ... and keeps walking in until it stands this close to the middle of its range (share of range)


func _make_shape() -> Shape3D:
	var cap := CapsuleShape3D.new()
	var k := float(cfg.get("scale", 1.0))
	cap.radius = 0.35 * k
	cap.height = 1.5 * k
	return cap


func body_box() -> Array:
	var k := float(cfg.get("scale", 1.0)) * _dist_scale
	return [global_position, global_position + Vector3(0.0, 1.8 * k, 0.0), 0.42 * k]


## A person: a head sphere on a standing capsule from the feet (HitZones), sized by the type's `scale`. Feet, legs, torso and head all count, nothing beside the body does.
func hit_ray(o: Vector3, d: Vector3) -> Dictionary:
	var k := float(cfg.get("scale", 1.0)) * _dist_scale
	return HitZones.ray(o, d, global_position, 1.8 * k, 0.36 * k, 0.2 * k)


func _build_visual() -> void:
	super._build_visual()
	rig = CharacterRig.find(model) if uses_model else null
	loco = Locomotion.new(rig) if rig != null else null
	if loco != null:
		loco.scale_amp = 0.9
	hanim = null
	if rig != null and not humanoid.is_empty():
		hanim = HumanoidAnim.new()
		hanim.set_weapon(StringName(cfg.get("weapon", &"rifle")))
		hanim.windup_time = float(cfg.get("aim_time", 0.45))
		hanim.death_time = FALL_TIME * 1.2
	if rig != null and rig.reflection != null:
		rig.reflection.range = 18.0                    # a trooper is reflected only when close (one draw call each)
	_restore_baked_glow()
	var mirror_body: MeshInstance3D = null
	if rig != null:
		mirror_body = rig.rest_mesh
		for n: String in ["WristL", "WristR", "MagWell", "MagPouch"]:
			var m := model.get_node_or_null(n)
			if m != null:
				model.remove_child(m)
				m.free()
		leg_l = Node3D.new()
		leg_l.name = "LegL"
		leg_r = Node3D.new()
		leg_r.name = "LegR"
		model.add_child(leg_l)
		model.add_child(leg_r)
		leg_l.position = Vector3(-0.1, 0.93, 0.0)
		leg_r.position = Vector3(0.1, 0.93, 0.0)
	else:
		leg_l = model.get_node_or_null("LegL") as Node3D
		leg_r = model.get_node_or_null("LegR") as Node3D
		mirror_body = model.get_node_or_null("Body") as MeshInstance3D
	# no reflection for the skinned model: the proxy would copy its rest-pose mesh, a second body that stands still while the real one moves
	if rig == null and is_instance_valid(Game.world) and Game.world.has_method(&"get_mirror_root") and mirror_body != null:
		var proxy := MirrorProxy.new()
		add_child(proxy)
		var arr: Array[MeshInstance3D] = [mirror_body]
		proxy.track(arr)


## DynamicFill recolours "Glow" surfaces, but the baked character has ONE atlas material ("Gear") whose emission texture already carries the red optic slit,
## the trim lights and the status strips: DynamicFill's faint fill emission would dim all of that, so the imported emission values are put back.
func _restore_baked_glow() -> void:
	for mi: MeshInstance3D in DynamicFill._meshes(model):
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(si) as BaseMaterial3D
			var ov := mi.get_surface_override_material(si) as BaseMaterial3D
			if src != null and ov != null and src.resource_name == "Gear" and src.emission_enabled:
				ov.emission = src.emission
				ov.emission_energy_multiplier = src.emission_energy_multiplier
				if RenderingServer.get_current_rendering_method() == "gl_compatibility":
					ov.albedo_color = ov.albedo_color * 0.6          # that renderer lights the same scene much brighter


## LOD hook: the skinned body's shadow is the rig's shadow-only proxy.
func _apply_shadow(on: bool) -> void:
	if rig != null:
		rig.set_shadow(on)
	else:
		super._apply_shadow(on)


func _on_activate() -> void:
	rush = false
	_called = false
	_assigned_t = 0.0
	_cover_on = bool(cfg.get("cover", false))
	_cover = Vector3.INF
	_cover_state = 0
	_cover_t = 0.0
	_cover_cd = 0.0
	_cover_search_t = randf() * 0.5
	_peeked = false
	tactic_role = &""
	_camp_t = 0.0
	_camp_ref = Vector3.INF
	_camp_flank_cd = 0.0
	_suppress_cd = 0.0
	_suppressing = false
	suppress_bursts = 0
	_retreating = false
	_reinforce_called = false
	_leaping = false
	unsticks = 0
	_last_xz = Vector2.INF
	_blk_t = 0.0
	_unstick_t = 0.0
	leaps = 0
	flushes = 0
	regroups = 0
	_retreat_t = 0.0
	_regroup_immune = 0.0
	var gm := Game.enemies as EnemyManager
	faction = TacticsTable.faction_for(type, gm.chapter_now() if gm != null else 0, randf())
	kit = &"rifleman"
	kit_set = false
	squad_job = false
	kit_speed = 1.0
	kit_range = 1.0
	kit_hp = 1.0
	kit_aim = 1.0
	kit_cover = 1.0
	throws = false
	_crouch = 0.0
	_hit_k = 0.0
	if humanoid_body != null:
		humanoid_body.set_instance_shader_parameter(&"hit_k", 0.0)
		humanoid_body.set_instance_shader_parameter(&"far_k", 0.0)
	_far_k = 0.0
	_dist_scale = 1.0
	grenades_thrown = 0
	_grenade_cd = 0.0
	_grenade_wind = 0.0
	_aim_t = 0.0
	_burst_left = 0
	_shot_t = 0.0
	_no_los = 0.0
	_flank = 1.0 if randf() < 0.5 else -1.0
	_stride = 0.0
	_lean = 0.0
	_phase = 0.0
	_amp = 0.0
	_ready = READY_IDLE
	_aim_pitch = 0.0
	_kick = 0.0
	_flinch = 0.0
	_buckle = 0.0
	_fdir = Vector2.ZERO
	_death_kind = 0
	_rest_drop = 0.0
	_have_last = false
	if loco != null:
		loco.reset()
	if hanim != null:
		hanim.reset()
	if leg_l != null:
		leg_l.rotation.x = 0.0
	if leg_r != null:
		leg_r.rotation.x = 0.0
	if rig != null:
		rig.reset()
		rig.death_kind = 0
		rig.flinch_dir = Vector2.ZERO


## The squad kit of this body's roster look (the encounter director calls it after activate): speed, health, range, cover habit, grenades. Returns the kit's health multiplier.
func set_kit() -> float:
	if humanoid.is_empty() or type != &"operative":
		return 1.0
	var k := TacticsTable.kit(StringName(humanoid.get("class", &"rifleman")))
	kit = StringName(humanoid.get("class", &"rifleman"))
	kit_set = true
	kit_speed = float(k["speed"])
	kit_range = float(k["range"]) * TacticsTable.SQUAD_RANGE
	kit_hp = float(k["hp"])
	kit_aim = float(k["aim"])
	kit_cover = float(k["cover"])
	throws = bool(k["throws"])
	_grenade_cd = randf_range(TacticsTable.GRENADE_FIRST.x, TacticsTable.GRENADE_FIRST.y)
	return kit_hp * TacticsTable.SQUAD_HP


func _idle_speed() -> float:
	return float(cfg["walk"])


func _ground_y(x: float, z: float) -> float:
	if InteriorSpace.contains_xz(x, z):              # standing on the floor of a generated interior (scripts/interiors/)
		return InteriorSpace.floor_y
	var city := Game.world as City
	if city != null:
		return city.ground_height(x, z, global_position.y + 1.0)
	return 0.0


func _hit_effect(crit: bool) -> void:
	_flinch = 1.0 if crit else 0.7
	if hp > 0.0:                                            # the killing blow has its own death effect
		_hit_k = 1.0
		if humanoid_body != null:
			humanoid_body.set_instance_shader_parameter(&"hit_k", 1.0)
	_fdir = _dir_to_player()
	if hanim != null:
		hanim.hit(_fdir, _flinch)
	var c := center()
	if hp <= 0.0:
		pass                                                             # the killing blow gets the death effect only
	elif Game.graphic_violence:
		_burst(c, Color(0.5, 1.0, 0.2), 6, 3.5, 0.5, 9.0, 1.8)           # Vael ichor, not blood
	else:
		_burst(c, Color(0.85, 0.8, 0.7), 5, 2.5, 0.5, 3.0, 2.0)      # dust off the plates
		if crit:
			_burst(c, Color(1.0, 0.82, 0.45), 5, 5.0, 0.2, 9.0)      # chips and sparks (a crit only: a second emitter per hit is a draw call each)
	if _burst_left > 0 and _stagger > 0.0:
		_burst_left = maxi(0, _burst_left - 1)


## Where the player is, in this body's frame (x right, y forward), unit length; zero when there is no player.
func _dir_to_player() -> Vector2:
	var p := Game.player as Node3D
	if p == null or not is_instance_valid(p):
		return Vector2.ZERO
	var h := Vector3(p.global_position.x - global_position.x, 0.0, p.global_position.z - global_position.z)
	if h.length() < 0.2:
		return Vector2.ZERO
	h = h.normalized()
	return Vector2(h.dot(Vector3(cos(yaw), 0.0, -sin(yaw))), h.dot(Vector3(-sin(yaw), 0.0, -cos(yaw))))


func alert() -> void:
	aware = true


func damage(amount: float, crit := false, mirrored := false) -> void:
	var was_aware := aware
	super.damage(amount, crit, mirrored)
	if not was_aware and not dead and not mirrored:
		var mgr := Game.enemies as EnemyManager
		if mgr != null:
			mgr.alert_near(global_position, HELP_RADIUS, self)     # calls for help


func _death_effect() -> void:
	var c := center()
	if Game.graphic_violence:
		ichor(c, 0.8)
	_burst(c, Color(0.95, 0.82, 0.6), 12, 4.0, 0.5, 5.0, 2.4)       # dust and sparks in ONE emitter (was two)
	Sfx.play_at(&"hit", c, 0.0, 0.8)
	_roll_sign = 1.0 if randf() < 0.5 else -1.0
	var from := _dir_to_player()               # shot from the front: it is thrown back, from behind: it falls forward, from the side: it falls away from the shot
	_death_kind = 0
	if from != Vector2.ZERO:
		if absf(from.y) > absf(from.x) * 0.8:
			_death_kind = 2 if from.y > 0.0 else 1
		else:
			_roll_sign = 1.0 if from.x > 0.0 else -1.0
	if randf() < 0.25:
		_death_kind = randi() % 3
	_burst_left = 0
	_aim_t = 0.0
	if hanim != null:
		hanim.die(_death_kind)


## How fast the body turns towards the target (a shield trooper turns slowly: that is the window to flank him).
func _turn_rate() -> float:
	return 8.0


func _think_aware(delta: float, dx: float, dz: float, d: float) -> void:
	var speed: float = float(cfg["speed"]) * kit_speed
	var rng: float = float(cfg["range"]) * kit_range
	yaw = lerp_angle(yaw, atan2(-dx, -dz), 1.0 - exp(-_turn_rate() * delta))
	var ux := dx / d
	var uz := dz / d
	_no_los = 0.0 if los else _no_los + delta
	if not _called:
		_called = true
		var mgr := Game.enemies as EnemyManager
		if mgr != null:
			mgr.squad_callout(self, _tgt)                  # the squad is told: neighbours wake up and get flank sides
	_assigned_t = maxf(0.0, _assigned_t - delta)
	if _unstick(delta, ux, uz, d, speed, rng):
		return
	if _tactics(delta, ux, uz, d, speed, rng):
		return
	_move_aware(delta, ux, uz, d, speed, rng)
	_fire_cycle(delta, d, rng)


## Blocked-walker watchdog: it meant to move but a wall (a building edge, a prop) stopped it for UNSTICK_AFTER seconds, so it side-steps along the obstacle for UNSTICK_FOR seconds.
## Returns true while the side-step drives the frame.
func _unstick(delta: float, ux: float, uz: float, d: float, speed: float, rng: float) -> bool:
	var cur := Vector2(global_position.x, global_position.z)
	if _last_xz.is_finite():
		var wanted := _moved * delta
		if wanted > 0.01 and cur.distance_to(_last_xz) < wanted * 0.25 and _cover_state != 2:
			_blk_t += delta
		else:
			_blk_t = maxf(0.0, _blk_t - delta)
	_last_xz = cur
	if _unstick_t <= 0.0 and _blk_t > UNSTICK_AFTER and not _retreating:
		_unstick_t = UNSTICK_FOR
		_unstick_dir = 1.0 if randf() < 0.5 else -1.0
		_blk_t = 0.0
		_assigned_t = 0.0
		unsticks += 1
		_leave_cover(0.8)
	if _unstick_t <= 0.0:
		return false
	_unstick_t -= delta
	_mx = ux * 0.2 - uz * _unstick_dir
	_mz = uz * 0.2 + ux * _unstick_dir
	_speed = speed
	_fire_cycle(delta, d, rng)
	return true


## The squad leader's order: come in from this side (+1 / -1) for `seconds`.
func assign_flank(side: float, seconds := 8.0) -> void:
	_flank = side
	_assigned_t = seconds
	_leave_cover(0.0)


## An encounter squad member's role from the director: pusher (rushes straight in), flanker (arcs round the side first, then rushes), anchor (takes cover and suppresses). The role is
## final: the squad call that normally hands the roles out is skipped (`_called`), and the other specialists simply rush.
func set_squad_role(role: StringName, side: float) -> void:
	_called = true
	squad_job = true
	if not uses_tactics():
		rush = true
		return
	tactic_role = role
	match role:
		&"flanker":
			rush = true
			assign_flank(side, 9.0)
		&"anchor":
			rush = false
			_cover_on = true
		_:
			rush = true


## The director's pressure: a squad member that sits in cover or arcs round for too long is told to come in (a straggler must not stall a wave).
func squad_rush() -> void:
	if not uses_tactics():
		rush = true
		return
	tactic_role = &"pusher"
	rush = true
	_cover_on = false
	_assigned_t = 0.0
	_leave_cover(0.0)


## Still doing something other than coming in (cover, a flank arc, holding back)? The director's pressure keeps telling such a trooper until it pushes.
func needs_push() -> bool:
	return _cover_on or _cover_state != 0 or not rush or tactic_role != &"pusher"


func flank_side() -> float:
	return _flank


## Plain operatives and flankers play the full tactics (the other specialists keep their own plans).
func uses_tactics() -> bool:
	return type == &"operative" or type == &"flanker"


func is_retreating() -> bool:
	return _retreating


func is_leaping() -> bool:
	return _leaping


func _row(key: String) -> Variant:
	return TacticsTable.val(faction, key)


## Squad tactics on top of cover: low-hp retreat, a call for reinforcement, a flank when the target camps, suppressing fire from cover, pusher advance.
## Returns true when it drove the frame itself (the retreat).
func _tactics(delta: float, ux: float, uz: float, d: float, speed: float, rng: float) -> bool:
	if not uses_tactics() or _tgt_clone:
		return false
	_camp_flank_cd = maxf(0.0, _camp_flank_cd - delta)
	_suppress_cd = maxf(0.0, _suppress_cd - delta)
	_regroup_immune = maxf(0.0, _regroup_immune - delta)
	var gm := Game.enemies as EnemyManager
	var frac := hp / maxf(max_hp, 1.0)
	if frac < CALL_HP and not _reinforce_called:
		_reinforce_called = true
		var mgr := Game.enemies as EnemyManager
		if mgr != null:
			mgr.call_reinforcement(self)
	var retreat_hp := float(_row("retreat_hp")) if not (kit_set or squad_job) else 0.0         # the director's squad fights to the end, backups included (a wounded straggler walking away held a wave open for 35 s: the last one of a wave hid behind his cover for good, the director's pressure kept clearing his cover state and he stood there until WAVE_MAX)
	if frac < retreat_hp and retreat_hp > 0.0 and _regroup_immune <= 0.0 and not _retreating:
		_retreating = true
		_retreat_t = 0.0
		_leaping = false
	if _retreating:
		_retreat(delta, ux, uz, d, speed)
		return true
	# the target camps: the anchors and covered shooters send themselves round the side
	if _camp_ref.is_finite() and Vector2(_tgt.x - _camp_ref.x, _tgt.z - _camp_ref.z).length() < 2.0:
		_camp_t += delta
	else:
		_camp_t = 0.0
		_camp_ref = _tgt
	if _camp_t > float(_row("camp_s")) and _camp_flank_cd <= 0.0 and _assigned_t <= 0.0 and tactic_role != &"pusher" and d < rng * 1.3:
		_camp_flank_cd = float(_row("flank_cd"))
		_camp_t = 0.0
		assign_flank(-_flank if _cover_state != 0 else _flank, 7.0)
		return false
	# the grenadier: stands for GRENADE_WIND (the windup tell: arm back, the muzzle flare swells), then the ball leaves his hand and flies at the hero (EnemyGrenades)
	if throws:
		_grenade_cd = maxf(0.0, _grenade_cd - delta)
		if _grenade_wind > 0.0:
			_grenade_wind -= delta
			_mx = 0.0
			_mz = 0.0
			_speed = 0.0
			if _grenade_wind <= 0.0:
				if gm != null and gm.try_grenade(self):
					grenades_thrown += 1
				_grenade_cd = randf_range(TacticsTable.GRENADE_EVERY.x, TacticsTable.GRENADE_EVERY.y)
			return true
		if _grenade_cd <= 0.0 and los and _burst_left == 0 and _aim_t <= 0.0 and _cover_state != 1 and d > TacticsTable.GRENADE_RANGE.x and d < TacticsTable.GRENADE_RANGE.y \
				and gm != null and gm.grenade_ready():
			_grenade_wind = TacticsTable.GRENADE_WIND
			return true
	# flush: the hero holds cover, so a grenade is lobbed at him (one at a time, squad cooldown)
	if bool(_row("flush")) and gm != null and _cover_state != 1 and _burst_left == 0 and gm.hero_holding(float(_row("flush_hold"))):
		var spot := Vector3(_tgt.x, Game.player.global_position.y if is_instance_valid(Game.player) else 0.0, _tgt.z)
		if d > TacticsTable.FLUSH_RANGE.x and d < TacticsTable.FLUSH_RANGE.y and gm.try_think() and gm.try_flush(self, spot):
			flushes += 1
	# suppress: an anchor hidden behind cover (or any covered trooper while a teammate leaps or flanks) keeps the target's head down with blind bursts
	var covering := gm != null and (gm.leaping_near(self) > 0 or gm.flanking_near(self) > 0)
	if (tactic_role == &"anchor" or covering) and _cover_state == 2 and _suppress_cd <= 0.0 and _burst_left == 0 and d < rng:
		var sr: Vector2 = _row("suppress")
		_suppress_cd = randf_range(sr.x, sr.y) * (float(_row("suppress_flank_mult")) if covering else 1.0)
		_suppressing = true
		_burst_left = 2
		_shot_t = 0.0
		var off := Vector3(randf_range(-2.5, 2.5), randf_range(-0.5, 0.5), randf_range(-2.5, 2.5))
		_aim_override = _tgt + off
		suppress_bursts += 1
	if tactic_role == &"pusher" and _assigned_t <= 0.0 and d > rng * 0.3 and _cover_state == 0:
		_mx = ux
		_mz = uz
		_speed = speed * 0.9
		_fire_cycle(delta, d, rng)
		return true
	return false


## Low hp: run for cover (hide for good) or, with none, straight away from the target.
func _retreat(delta: float, ux: float, uz: float, d: float, speed: float) -> void:
	_aim_t = 0.0
	_burst_left = 0
	_retreat_t += delta
	_cover_cd = maxf(0.0, _cover_cd - delta)
	var mgr0 := Game.enemies as EnemyManager
	if _regroup_ready(mgr0):
		_retreating = false
		_regroup_immune = 15.0
		regroups += 1
		_leave_cover(1.0)
		return
	var medic: Drone = mgr0.medic_for(self) if mgr0 != null else null
	if medic != null and medic.global_position.distance_to(global_position) > float(medic.cfg.get("heal_radius", 9.0)) * 0.5:
		var to_m := Vector2(medic.global_position.x - global_position.x, medic.global_position.z - global_position.z).normalized()
		_mx = to_m.x                                          # the medic is the priority: a hurt trooper falls back to the mender
		_mz = to_m.y
		_speed = speed * 1.15
		return
	if _cover_state == 0 and _cover_cd <= 0.0:
		var mgr := Game.enemies as EnemyManager
		if mgr == null or mgr.try_think():
			var c := EnemyCover.find(self, _tgt, 30.0, faction)
			_cover_cd = 1.0
			if c.is_finite():
				_cover = c
				_cover_state = 1
				_cover_dir = Vector2(ux, uz)
	if _cover_state == 1:
		var to_c := Vector2(_cover.x - global_position.x, _cover.z - global_position.z)
		if to_c.length() < 0.7:
			_cover_state = 2
		else:
			var u := to_c.normalized()
			_mx = u.x
			_mz = u.y
			_speed = speed * 1.2
			return
	if _cover_state == 2:
		_speed = 0.0
		return
	_mx = -ux
	_mz = -uz
	_speed = speed * 1.1


## Back in the fight: the retreat has lasted regroup_s and either the health is back (a mender) or enough allies stand close.
func _regroup_ready(mgr: EnemyManager) -> bool:
	var need := float(_row("regroup_s"))
	if need <= 0.0 or _retreat_t < need:
		return false
	if hp / maxf(max_hp, 1.0) >= float(_row("regroup_hp")):
		return true
	return mgr != null and mgr.allies_near(self, float(_row("regroup_radius"))) >= int(_row("regroup_allies"))


## Does this soldier take flank orders? (brutes charge, the boss is its own plan)
func role_flanks() -> bool:
	return type != &"brute" and type != &"overseer" and type != &"walker" and not EnemyTypes.is_elite(type)


## Default operative movement: close in when far or blind (at an angle after FLANK_AFTER s without sight), back off when pressed, strafe in between; cover first when the cfg
## asks for it (cover_on): run behind a nearby prop collider, wait hidden, peek to fire a burst, leave when flanked or rushed.
func _move_aware(delta: float, ux: float, uz: float, d: float, speed: float, rng: float) -> void:
	if _cover_on and _assigned_t <= 0.0 and _cover_move(delta, ux, uz, d, speed, rng):
		return
	if _assigned_t > 0.0 and d > rng * 0.45:                  # an assigned flank: arc round the target even while it can see us
		_mx = ux * 0.55 - uz * 0.85 * _flank
		_mz = uz * 0.55 + ux * 0.85 * _flank
		_speed = speed * 1.05
	elif d > rng * 0.95 or not los or (rush and d > rng * RUSH_CLOSE):
		_mx = ux
		_mz = uz
		_speed = speed
		if not los and _no_los > FLANK_AFTER:         # no sight line for a while: come in at an angle
			_mx = ux * 0.6 - uz * 0.8 * _flank
			_mz = uz * 0.6 + ux * 0.8 * _flank
	elif d < rng * 0.4:
		_mx = -ux
		_mz = -uz
		_speed = speed * 0.7
	else:
		_strafe_t -= delta
		if _strafe_t <= 0.0:
			_strafe_t = randf_range(1.0, 2.5)
			_strafe = -_strafe
		_mx = -uz * _strafe
		_mz = ux * _strafe
		_speed = speed * 0.45


## Aim, then a short burst, then a pause.
func _fire_cycle(delta: float, d: float, rng: float) -> void:
	if _suppressing:
		_shot_t -= delta
		if _burst_left > 0 and _shot_t <= 0.0:
			_shoot(d)
			_burst_left -= 1
			_shot_t = float(cfg["burst_gap"]) * 1.5
		if _burst_left <= 0:
			_suppressing = false
			_aim_override = Vector3.INF
		return
	if _cover_state == 1 or _cover_state == 2:
		_aim_t = 0.0                                          # running to cover or hiding behind it: no shooting
		return
	if _aim_t > 0.0:
		_speed *= 0.2
		_aim_t -= delta
		if _aim_t <= 0.0:
			_burst_left = int(cfg["burst"])
			_shot_t = 0.0
			_volley_origin = _muzzle_pos()
			Sfx.play_at(&"enemy_shot", _volley_origin, -4.0)
	elif _burst_left > 0:
		_speed *= 0.3
		_shot_t -= delta
		if _shot_t <= 0.0:
			_shoot(d)
			_burst_left -= 1
			_shot_t = float(cfg["burst_gap"])
			if _burst_left == 0:
				var f: Vector2 = cfg["fire"]
				_fire_t = randf_range(f.x, f.y) / Difficulty.mult("aggr")
	else:
		_fire_t -= delta
		if los and d < rng * 1.15 and _fire_t <= 0.0:
			_aim_t = float(cfg["aim_time"]) * kit_aim


# --- cover: pooled prop colliders (EnemyCover.find) ------------------------------------------------------------------

## The director's squad takes only LOW cover (EnemyCover.LOW_MAX): it crouches behind it, stays shootable and stands up to fire.
func low_cover_only() -> bool:
	return kit_set and (rush or tactic_role != &"")


func cover_state() -> int:
	return _cover_state


func cover_point() -> Vector3:
	return _cover


## Leapfrog: from hidden, the target still far, and the squad has a free leap slot: run to a cover at least leap_step closer while the others suppress.
func _try_leap(d: float, rng: float, to_t: Vector2) -> bool:
	if not bool(_row("leapfrog")) or _retreating or d < float(_row("leap_min")) or d > rng * 1.05:
		return false
	var gm := Game.enemies as EnemyManager
	if gm == null or gm.leaping_near(self) >= TacticsTable.tier_cap(TacticsTable.LEAPERS, Game.quality) or not gm.try_think():
		return false
	var c := EnemyCover.find(self, _tgt, float(cfg.get("cover_radius", 22.0)), faction, float(_row("leap_step")), low_cover_only())
	if not c.is_finite():
		return false
	_cover = c
	_cover_state = 1
	_cover_dir = to_t
	_leaping = true
	leaps += 1
	return true


func _leave_cover(cooldown: float) -> void:
	_leaping = false
	_cover_state = 0
	_cover = Vector3.INF
	_cover_cd = cooldown


func _cover_move(delta: float, ux: float, uz: float, d: float, speed: float, rng: float) -> bool:
	if _tgt_clone:
		return false
	_cover_cd = maxf(0.0, _cover_cd - delta)
	var to_t := Vector2(ux, uz)
	if _cover_state != 0 and not _retreating:
		if to_t.dot(_cover_dir) < 0.5 or d < 5.5:           # the target went round the side (more than 60 degrees) or rushed us: the cover is spent
			_leave_cover(3.5)
			return false
	if _cover_state == 0:
		if _cover_cd > 0.0 or d > rng * 1.1 or d < 7.0:
			return false
		_cover_search_t -= delta
		if _cover_search_t > 0.0:
			return false
		_cover_search_t = 0.5
		if randf() > float(_row("cover_use")) * kit_cover * (RUSH_COVER_USE if rush else 1.0):
			_cover_cd = 2.0                                   # the hive mostly just charges
			return false
		var gm := Game.enemies as EnemyManager
		if gm != null and not gm.try_think():
			return false                                      # too many thinkers this frame: try again at the next search
		var c := EnemyCover.find(self, _tgt, float(cfg.get("cover_radius", 22.0)), faction, 0.0, low_cover_only())
		if not c.is_finite():
			_cover_cd = 1.5
			return false
		_cover = c
		_cover_state = 1
		_cover_dir = to_t
	var to_c := Vector2(_cover.x - global_position.x, _cover.z - global_position.z)
	match _cover_state:
		1:
			if to_c.length() < 0.7:
				_cover_state = 2
				_leaping = false
				var hr: Vector2 = _row("hide")
				_cover_t = randf_range(hr.x, hr.y) * (RUSH_HIDE if rush else 1.0)
			else:
				var u := to_c.normalized()
				_mx = u.x
				_mz = u.y
				_speed = speed * 1.15
		2:
			_speed = 0.0
			_cover_t -= delta
			if _cover_t <= 0.0 and _try_leap(d, rng, to_t):
				return true
			if _cover_t <= 0.0:
				_cover_state = 3
				_cover_t = float(_row("peek"))
				_peeked = false
				_fire_t = 0.0
				_los_t = 0.0                                  # look again at once
		3:
			var side := Vector2(-to_t.y, to_t.x) * _strafe       # step out sideways to get a line of fire
			var spot := Vector2(_cover.x, _cover.z) + side * 1.3
			var to_s := spot - Vector2(global_position.x, global_position.z)
			if to_s.length() > 0.25:
				var u2 := to_s.normalized()
				_mx = u2.x
				_mz = u2.y
				_speed = speed * 0.6
			_cover_t -= delta
			if _aim_t > 0.0 or _burst_left > 0:
				_peeked = true
			if (_peeked and _aim_t <= 0.0 and _burst_left == 0) or _cover_t <= 0.0:
				_cover_state = 2
				var hr2: Vector2 = _row("hide")
				_cover_t = randf_range(hr2.x, hr2.y) * (RUSH_HIDE if rush else 1.0) + 0.1
				_strafe = -_strafe
	return true


## Attack telegraph: the rifle charges during the aim windup (a flare at the muzzle and an aim line), full during the burst.
func threat_charge() -> float:
	if dead:
		return 0.0
	if _grenade_wind > 0.0:
		return clampf(1.0 - _grenade_wind / TacticsTable.GRENADE_WIND, 0.0, 1.0)
	if _aim_t > 0.0:
		return clampf(1.0 - _aim_t / (float(cfg["aim_time"]) * kit_aim), 0.0, 1.0)
	return 1.0 if _burst_left > 0 else 0.0


func shows_aim_line() -> bool:
	return _aim_t > 0.0 and _tgt_ok


func muzzle_world() -> Vector3:
	return _muzzle_pos()


func mark_size() -> float:
	return 2.5 * _base_scale


func death_progress() -> float:
	return clampf(_dead_t / 0.7, 0.0, 1.0)


func _muzzle_pos() -> Vector3:
	return muzzle.global_position if muzzle != null else center() + Vector3(0.0, 0.3, 0.0)


func _tracer_color() -> Color:
	return Color(1.0, 0.45, 0.35)


## Aim error factor of the player's state (Difficulty.hurt_aim): a hurt player is missed more often.
func _hurt_aim() -> float:
	var pl := Game.player as Player
	if pl == null or not is_instance_valid(pl):
		return 1.0
	return Difficulty.hurt_aim(pl.hp / maxf(pl.max_hp, 1.0))


## Aim error (metres, the radius of the disc round the aim point the round lands in, uniform) of a trooper: a floor that even point blank keeps (a round is never a certain hit,
## it shows as a near miss), the cfg's angular spread growing with distance, climbing with every round of the volley (muzzle climb) and scaled by what the hero does: running makes him
## harder to hit, sprinting and ducking behind cover harder still, a hurt hero is missed more (Difficulty.hurt_aim). A sniper (spread 0.002) keeps a tiny disc: his shot is a laser lock.
## Chance to hit a 0.5 m body is about (0.5 / radius)^2: stationary hero ~48 % at 4 m, ~30 % at 8 m, ~12 % at 20 m over a volley; running about 60 % of that.
const AIM_FLOOR := 0.45
const AIM_FLOOR_REF := 0.035
const BURST_CLIMB := 0.22
const MOVE_MULT := 1.3
const SPRINT_MULT := 1.55
const COVER_MULT := 1.5
const NEAR_MISS := 2.2


static func aim_radius(spread: float, spread_per_m: float, d: float, burst_idx := 0, hero_speed := 0.0, hero_sprint := false, hero_cover := false, hurt := 1.0) -> float:
	var r := AIM_FLOOR * clampf(spread / AIM_FLOOR_REF, 0.0, 1.6) + d * (spread + spread_per_m * d)
	r *= 1.0 + BURST_CLIMB * float(maxi(burst_idx, 0))
	if hero_sprint:
		r *= SPRINT_MULT
	elif hero_speed > 2.0:
		r *= MOVE_MULT
	if hero_cover:
		r *= COVER_MULT
	return r * hurt


## One round: hitscan with an aim error disc (aim_radius). The tracer ends at the first world hit or past the target; a miss that passes close shows a spark where it lands.
func _shoot(d: float) -> void:
	var origin := _muzzle_pos()
	var aim := _tgt
	var pl := Game.player as Player
	var speed := Vector2(pl.velocity.x, pl.velocity.z).length() if pl != null and is_instance_valid(pl) else 0.0
	var radius := aim_radius(float(cfg["spread"]), float(cfg["spread_per_m"]), d, int(cfg["burst"]) - _burst_left, speed, pl != null and pl.sprinting, pl != null and pl.cover != null and pl.cover.in_cover, _hurt_aim()) * Difficulty.mult("spread")
	var fire_at := _aim_override if _aim_override.is_finite() else aim      # a sniper's shot goes where the laser LOCKED, the hit test below still asks where the target really is
	var dir := (fire_at - origin).normalized()
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(dir).normalized()
	var ang := randf() * TAU
	var mag := radius * sqrt(randf())
	dir = ((fire_at - origin) + (side * cos(ang) + up * sin(ang)) * mag).normalized()
	var t_close := maxf((aim - origin).dot(dir), 0.0)
	var closest := origin + dir * t_close
	var miss := closest.distance_to(aim)
	var end := origin + dir * (t_close + 6.0)
	_ray.from = origin
	_ray.to = end
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	var blocked := false
	if not hit.is_empty():
		end = hit["position"]
		blocked = origin.distance_to(end) < t_close - 0.3
	_kick = 1.0
	if hanim != null:
		hanim.fire()
	FX.tracer(origin, end, _tracer_color())
	FX.burst(origin, Color(1.0, 0.8, 0.45), 3, 2.5, 0.08, 0.0)
	if Companion.current != null:
		Companion.current.shot_passes(origin, end, float(cfg["dmg"]))       # the ally standing in the line of fire takes the round
	var mgr := Game.enemies as EnemyManager
	var p := Game.player
	if blocked or mgr == null:
		return
	if _tgt_clone:
		if miss < 0.6:
			mgr.hit_clone()
		return
	if not is_instance_valid(p):
		return
	var reach := 1.5 if p.get(&"vehicle") != null else 0.5
	round_stats["fired"] += 1
	if miss >= reach and miss < NEAR_MISS:                    # a near miss is seen and felt: a spark where it lands, a small shake
		round_stats["near"] += 1
		if not hit.is_empty():
			_burst(end, Color(1.0, 0.82, 0.5), 4, 3.0, 0.15, 3.0)
			Sfx.impact(&"concrete", end)
		if pl != null:
			pl.camera_rig.bump(0.05)
	if miss < reach and QuantumVerbs.shield_on and QuantumVerbs.shield_hit(origin, closest):     # PHASE SHIELD: absorbed, or sent back at the shooter (snipers see through it)
		var qv := p.get(&"qverbs") as QuantumVerbs
		var res := qv.shield_block(type, float(cfg["dmg"])) if qv != null else 0
		if res == 2:
			qv.reflect_hits += 1
			damage(maxf(float(cfg["dmg"]) * QuantumVerbs.REFLECT_MULT, QuantumVerbs.REFLECT_MIN), false)
		if res != 0:
			return
	if miss < reach:
		round_stats["hit"] += 1
		p.call(&"damage", float(cfg["dmg"]) * buff_dmg * InteriorGameplay.pressure(), origin)


func _animate(delta: float) -> void:
	if rig == null:
		_animate_legs_only(delta)
		return
	var cfg_speed: float = cfg["speed"]
	var disp := Vector3.ZERO
	if _have_last:
		disp = Vector3(global_position.x - _last_pos.x, 0.0, global_position.z - _last_pos.z)
	_last_pos = global_position
	_have_last = true
	var firing := _aim_t > 0.0 or _burst_left > 0
	if hanim == null:
		var want_ready := 1.0 if firing else (READY_AWARE if aware else READY_IDLE)
		_ready = lerpf(_ready, want_ready, 1.0 - exp(-9.0 * delta))
	var want_pitch := 0.0
	var look_off := 0.0
	if aware and not dead:
		var o := _muzzle_pos()
		var hd := maxf(Vector2(_tgt.x - o.x, _tgt.z - o.z).length(), 1.0)
		want_pitch = clampf(atan2(_tgt.y - o.y, hd) * 0.6, -0.55, 0.65)
		look_off = angle_difference(yaw, atan2(-(_tgt.x - o.x), -(_tgt.z - o.z)))
	_kick = maxf(0.0, _kick - delta * 7.0)
	_flinch = maxf(0.0, _flinch - delta * 5.0)
	if _hit_k > 0.0:
		_hit_k = maxf(0.0, _hit_k - delta * 8.0)
		if humanoid_body != null:
			humanoid_body.set_instance_shader_parameter(&"hit_k", _hit_k)
	_clock += delta
	loco.update(delta, disp, yaw, true, 0.0, 1.0 if _moved > 0.1 else 0.0, false, firing, look_off)
	if hanim != null:
		_sync_hanim(delta, want_pitch)
		hanim.write(rig)
		_ready = hanim.ready
		_aim_pitch = hanim.aim_pitch
	else:
		_aim_pitch = lerpf(_aim_pitch, want_pitch, 1.0 - exp(-10.0 * delta))
		rig.aim_pitch = _aim_pitch
		rig.recoil = _kick
		rig.flinch = _flinch
		rig.flinch_dir = _fdir * minf(1.0, _flinch * 2.0)
		rig.ready = _ready
		rig.reload = -1.0
		rig.dead = 0.0
		rig.knee_buckle = 0.0
	rig.head_yaw = 0.0
	if _stagger > 0.0:
		rig.lean += -0.1 * minf(1.0, _stagger * 8.0)
	rig.apply()
	if model != null and not dead:                          # behind low cover he crouches: the body squashes to ~70 %, so the head and shoulders stay in view above the cover
		_crouch = lerpf(_crouch, 1.0 if (_cover_state == 2 and not _retreating) else 0.0, 1.0 - exp(-12.0 * delta))
		model.scale = _look_scale * _base_scale * _dist_scale * Vector3(1.0, 1.0 - 0.3 * _crouch, 1.0)
	if muzzle != null:
		muzzle.transform = hanim.muzzle_transform(rig) if hanim != null else rig.muzzle_transform()
	if leg_l != null:
		leg_l.basis = Basis.from_euler(Vector3(rig.hip_l.x, 0.0, rig.hip_l.y))
		leg_r.basis = Basis.from_euler(Vector3(rig.hip_r.x, 0.0, rig.hip_r.y))


## Maps what the AI is doing onto the HumanoidAnim state machine: IDLE while unaware, AIM once aware, WINDUP during the aim time (the charge follows _aim_t), FIRE / HIT / DEAD come
## from _shoot / _hit_effect / _death_effect themselves.
func _sync_hanim(delta: float, want_pitch: float) -> void:
	if not dead:
		var st := hanim.state
		if _aim_t > 0.0:
			if st != HumanoidAnim.State.WINDUP:
				hanim.set_state(HumanoidAnim.State.WINDUP)
		elif st == HumanoidAnim.State.WINDUP:
			hanim.set_state(HumanoidAnim.State.AIM)
		elif aware and st == HumanoidAnim.State.IDLE:
			hanim.set_state(HumanoidAnim.State.AIM)
		elif not aware and st == HumanoidAnim.State.AIM:
			hanim.set_state(HumanoidAnim.State.IDLE)
	hanim.update(delta, want_pitch)


## The primitive operative (no model): legs swing with the real speed, the body leans when staggered.
func _animate_legs_only(delta: float) -> void:
	if leg_l == null or leg_r == null:
		return
	var k := clampf(_moved / float(cfg["speed"]), 0.0, 1.0)
	_stride += _moved * delta * STRIDE_RAD_PER_M
	var swing := sin(_stride) * LEG_AMP * minf(1.0, 0.25 + k)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, swing if _moved > 0.1 else 0.0, 1.0 - exp(-14.0 * delta))
	leg_r.rotation.x = lerpf(leg_r.rotation.x, -swing if _moved > 0.1 else 0.0, 1.0 - exp(-14.0 * delta))
	_lean = lerpf(_lean, 0.12 if _stagger > 0.0 else 0.0, 1.0 - exp(-12.0 * delta))
	model.rotation.x = _lean


func _place(delta: float) -> void:
	rotation.y = yaw          # no banking for a human


func _tick_dead(delta: float) -> void:
	_dead_t += delta
	_tick_drop()
	var k := clampf(_dead_t / FALL_TIME, 0.0, 1.0)
	var e := 1.0 - (1.0 - k) * (1.0 - k)
	if rig != null:
		# the knees give way first, the body falls (onto its side, forward or backward), then everything goes limp
		_kick = 0.0
		if hanim != null:
			hanim.update(delta, 0.0)
			hanim.write(rig)
			rig.amp = lerpf(rig.amp, 0.0, k)
		else:
			_buckle = clampf(_dead_t / (FALL_TIME * 0.5), 0.0, 1.0)
			_flinch = maxf(0.0, _flinch - delta * 3.0)
			rig.amp = lerpf(rig.amp, 0.0, k)
			rig.ready = lerpf(_ready, 0.0, k)
			rig.recoil = 0.0
			rig.flinch = _flinch
			rig.flinch_dir = _fdir * minf(1.0, _flinch * 2.0)
			rig.death_kind = _death_kind
			rig.knee_buckle = _buckle * (1.0 - e * 0.6)
			rig.dead = clampf((_dead_t - FALL_TIME * 0.3) / (FALL_TIME * 0.9), 0.0, 1.0)
			rig.reload = -1.0
		rig.apply()
		if leg_l != null:
			leg_l.basis = Basis.from_euler(Vector3(rig.hip_l.x, 0.0, rig.hip_l.y))
	var fall := e * PI * 0.5
	match _death_kind:
		1:
			model.rotation = Vector3(-fall, 0.0, 0.0)
			model.position = Vector3(0.0, 0.0, 0.55 * e)
		2:
			model.rotation = Vector3(fall, 0.0, 0.0)
			model.position = Vector3(0.0, 0.0, -0.55 * e)
		_:
			model.rotation = Vector3(0.0, 0.0, _roll_sign * fall)
			model.position = Vector3.ZERO
	if rig != null:                                            # lie on the floor: the lowest point of the bones' hulls rests on it
		if _dead_t < FALL_TIME + 0.6:
			_rest_drop = rig.lowest_world_y() - global_position.y
		model.position.y = -_rest_drop + 0.012
	if rig == null and leg_l != null:
		leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.5, 1.0 - exp(-6.0 * delta))
	if _dead_t > CORPSE_TIME:
		_burst(global_position + Vector3(0.0, 0.2, 0.0), Color(0.6, 0.6, 0.65), 6, 1.5, 0.5, 1.0, 2.0)
		remove = true
		set_physics_process(false)
		visible = false


func _make_fallback() -> Node3D:
	var root := Node3D.new()
	var fabric := _flat(Color(0.12, 0.13, 0.16), 0.8)
	var armor := _flat(Color(0.2, 0.22, 0.26), 0.55)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var tm := CapsuleMesh.new()
	tm.radius = 0.24
	tm.height = 0.72
	tm.material = armor
	body.mesh = tm
	body.position = Vector3(0.0, 1.3, 0.0)
	root.add_child(body)
	var head := MeshInstance3D.new()
	head.name = "Helmet"
	var hm := SphereMesh.new()
	hm.radius = 0.15
	hm.height = 0.3
	hm.material = armor
	head.mesh = hm
	body.add_child(head)
	head.position = Vector3(0.0, 0.5, 0.0)
	var visor := MeshInstance3D.new()
	visor.name = "Eye"
	var vm := BoxMesh.new()
	vm.size = Vector3(0.2, 0.05, 0.05)
	var gm := _flat(Color.BLACK, 0.5)
	gm.emission_enabled = true
	gm.emission = cfg["color"]
	gm.emission_energy_multiplier = 2.0
	gm.resource_name = "Glow"
	vm.material = gm
	visor.mesh = vm
	visor.position = Vector3(0.0, 0.52, -0.14)
	body.add_child(visor)
	var rifle := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(0.07, 0.09, 0.9)
	rm.material = _flat(Color(0.08, 0.08, 0.1), 0.5)
	rifle.mesh = rm
	rifle.position = Vector3(0.2, 0.12, -0.5)
	body.add_child(rifle)
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "LegL" if side < 0.0 else "LegR"
		var lm := CapsuleMesh.new()
		lm.radius = 0.1
		lm.height = 0.9
		lm.material = fabric
		leg.position = Vector3(side * 0.1, 0.93, 0.0)
		var inner := MeshInstance3D.new()
		inner.mesh = lm
		inner.position = Vector3(0.0, -0.46, 0.0)
		leg.add_child(inner)
		root.add_child(leg)
	var mz := Node3D.new()
	mz.name = "Muzzle"
	mz.position = Vector3(0.12, 1.38, -1.0)
	root.add_child(mz)
	return root
