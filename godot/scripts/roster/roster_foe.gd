class_name RosterFoe
extends AlienCreature
## The 15 non-boss enemies of roster 2 (wave 108; data in RosterSpecies, bodies in RosterKit, bosses in RosterBoss). An AlienCreature (so the AlienWorld ticks, pools, despawns, rewards and loots it and every
## weapon, blast, verb, aim assist and the minimap treat it as an enemy) with its own brains, chosen by the species `mech`:
##   ros_gun      one brain for every gunner (the five mercenaries, the shield bearer, the beam sniper): ADVANCE to its `keep` range (back-pedal inside it, strafe in it), use COVER (move to a spot the hero has no
##                line to, crouch, PEEK out sideways for one volley, go back), FLANK (an arc to the hero's side before the first shots), throw a GRENADE (a ring on the ground, a fuse), RETREAT when hurt
##                (to the nearest medic, else away) and come back, a MEDIC revives the fallen and heals the wounded; a REVIVABLE unit that dies with a medic near goes DOWN for up to 9 s (a red ring):
##                shoot it again to finish it, or the medic stands it up with 45 % health. Shots: burst, pellets (shotgun cone), rocket (ring + slow flight), beam (a visible lock line, then a ray).
##   ros_swarm    hivelings circle the hero and SURGE together (a pulse first, at most the AlienWorld leap gate rush at once), bite and bounce back.
##   ros_charge   the plate brute: stalks, ROARS (a line shows the charge), CHARGES on that line, stumbles (open), SLAMS a ring up close; its three armour plates soak shots from their side (the front plate
##                from the front) until they break, then the core is open.
##   ros_stalk    the veil stalker: cloaked, circles in, drops the cloak to windup, POUNCES, slinks away cloaked; any hit shows it for 1.4 s.
##   ros_jet      the jet elite: a gunner that BOOSTS into the air (hover, shoot from above, land somewhere else); shooting the jetpack (component hp) grounds it.
##   ros_walker   the strider: a slow gunner with a missile SALVO (rings), KNEELS once at 35 % (open), rear core on the back.
##   ros_crawler  the spider mech: climbs steep ground, LEAPS onto the hero's spot (a ring first), shock ring on landing, twin lasers, a vent on its back.
##   ros_drone    the wasp drone: orbits, marks a line, STRAFES it firing, climbs; a hit on the rotor ring (component hp) makes it crash.
##   ros_turret   the auto turret: tracks, spins up with a line, fires a burst; the sensor on top is the weak point.
## Everything telegraphs (a ring, a line, a pulse), the windups scale with Difficulty (AlienCreature._aggr_k), and at most the leap gate's number of units are in a windup at once (EASY 2).
## Shots: `AlienWorld.shoot` bullets, `RosterFire` rockets / grenades / shells, instant beams and pellets (checked against the hero's body). Weak points: RosterWeak.

const MUZZLE := {&"shield_bearer": Vector3(0.74, 1.3, -0.9), &"jet_elite": Vector3(0.3, 1.32, -0.95), &"beam_sniper": Vector3(0.22, 1.62, -1.5), &"strider": Vector3(0.0, 3.5, -2.3),
	&"crawler": Vector3(0.4, 1.0, -2.2), &"wasp_drone": Vector3(0.14, 0.4, -0.9), &"auto_turret": Vector3(0.14, 1.0, -1.4), &"merc_rifle": Vector3(0.04, 1.32, -1.1),
	&"merc_rocket": Vector3(0.3, 1.68, -1.15), &"merc_shotgun": Vector3(0.08, 1.24, -0.95), &"merc_sniper": Vector3(0.06, 1.3, -1.7), &"merc_medic": Vector3(0.12, 1.28, -0.7)}
## id -> [shot sound, pitch] (the weapon sounds of assets/audio: every unit has its own voice)
const SND := {&"merc_rifle": [&"shot_ar2", 1.0], &"merc_rocket": [&"shot_cmissile", 0.9], &"merc_shotgun": [&"shot_scatter", 1.0], &"merc_sniper": [&"shot_amr", 1.0], &"merc_medic": [&"shot_mp", 1.1],
	&"shield_bearer": [&"shot_eplasma", 0.9], &"jet_elite": [&"shot_espike", 1.0], &"beam_sniper": [&"shot_ebeam", 0.85], &"strider": [&"shot_chaingun", 0.8], &"crawler": [&"shot_erepeat", 1.0],
	&"wasp_drone": [&"shot_burst", 1.3], &"auto_turret": [&"shot_mini", 1.0]}
const NO_STAGGER: Array[StringName] = [&"strider", &"crawler", &"auto_turret", &"plate_brute", &"shield_bearer"]
const LOS_EVERY := 0.2
const DOWN_MAX := 9.0
const REVIVE_FRAC := 0.45
const MERC_COLOR := Color(1.0, 0.85, 0.3)
const GRID_COLOR := Color(1.0, 0.35, 0.2)

var faction: StringName = &""
var wk: RosterWeak
var plates: Array[Dictionary] = []
var shield_hp := 0.0
var shield_t := 0.0                          ## seconds the shield stays down after it broke
var crouch := 0.0
var crouch_to := 0.0
var lift := 0.0                              ## metres above the ground (the jet elite)
var downed := false
var down_t := 0.0
var revived := 0
var revives_left := 0
var revives_done := 0
var retreated := false
var cover_spot := Vector2.INF
var cover_fail := 0.0
var in_cover := false
var peek_dir := 1.0
var burst_left := 0
var burst_t := 0.0
var nade_cd := 5.0
var nades := 0
var reveal_t := 0.0
var cloak_k := 0.0
var grounded_t := 0.0
var jet_mode: StringName = &"ground"
var jet_t := 5.0
var jet_h := 5.0
var jet_air := 0.0
var jet_dest := Vector2.INF
var salvo_cd := 6.0
var salvos := 0
var kneeled := false
var leap_cd := 4.0
var open_t := 0.0
var open_k := 1.0
var heal_cd := 0.0
var stride_k := 0.0
var squash := 1.0

var _los := false
var _los_t := 0.0
var _cover_t := 0.0
var _chan: RosterFoe = null
var _chan_line := 0.0
var _hit_t := -10.0
var _no_down := false
var _flank_rolled := false
var _flank_side := 1.0
var _retreat_to := Vector2.INF
var _muz_side := 1.0
var _stride_t := 0.0
var _last_xz := Vector2.INF
var _orbit_a := 0.0
var _surge_t := 3.0
var _dive_dir := Vector2.ZERO
var _land_to := Vector3.ZERO
var _land_from := Vector3.ZERO
var _ray := PhysicsRayQueryParameters3D.new()
var _beacon_t := 0.0
var _mat_time := 0.0
var base_vis := 1.0
## species the hero has been told about this session (first contact shows one line: name and the one thing to do)
static var told := {}


func setup(sid: StringName, w: AlienWorld) -> bool:
	if not RosterKit.setup_body(self, sid, w):
		return false
	faction = StringName(spec["faction"])
	base_vis = vis
	wk = RosterWeak.new(self)
	wk.plates_left = Callable(self, "plate_up")
	if spec.has("shield"):
		shield_hp = float(spec["shield"]) * Difficulty.mult("hp")
	if spec.has("plates"):
		_build_plates()
	revives_left = 1 if Difficulty.current == Difficulty.EASY else 2
	nade_cd = randf_range(3.0, 8.0)
	leap_cd = randf_range(2.5, 5.0)
	jet_t = randf_range(2.5, 5.0)
	salvo_cd = randf_range(4.0, 8.0)
	_surge_t = randf_range(1.5, 5.0)
	cloak_k = float(spec.get("cloak", 0.0))
	if cls == AlienSpecies.AIR:
		alt = float((spec["alt"] as Array)[0]) if spec.has("alt") else 5.0
	return true


## First contact with a type: one line with its name and the one thing to do (weak point, flank, shoot the medic first). Once per type and session.
func _wake() -> void:
	super._wake()
	if not told.has(id) and world != null and world.hero_alive() and flat_dist() < 70.0:
		told[id] = true
		Game.say("%s  %s" % [String(spec["name"]), String(spec.get("tip", ""))], 3.2)


func _build_plates() -> void:
	for p: Dictionary in (spec["plates"] as Array):
		var n := MeshInstance3D.new()
		n.mesh = RosterKit.plate_mesh(StringName(p["side"]))
		n.material_override = mat
		n.extra_cull_margin = 3.0
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.scale = Vector3.ONE * vis
		add_child(n)
		var hp_p := float(p["hp"]) * Difficulty.mult("hp")
		plates.append({"side": StringName(p["side"]), "hp": hp_p, "max": hp_p, "node": n})


func plate_up(side: StringName) -> bool:
	var s := String(side)
	if s.begins_with("plate_"):
		s = s.substr(6)
	for p in plates:
		if String(p["side"]) == s and float(p["hp"]) > 0.0:
			return true
	return false


func plates_up() -> int:
	var n := 0
	for p in plates:
		if float(p["hp"]) > 0.0:
			n += 1
	return n


# --- the enemy contract: shapes, damage, shield, stagger --------------------------------------------------------------------------------------------

func _to_world(local: Vector3) -> Vector3:
	return Basis(Vector3.UP, heading) * Vector3(local.x, local.y * squash, local.z) * vis + Vector3(0.0, lift - (1.0 - rise) * _bury_depth(), 0.0)


func hit_ray(o: Vector3, d: Vector3) -> Dictionary:
	return wk.hit_ray(o, d)


func stagger(power: float) -> void:
	if dead or downed or NO_STAGGER.has(id):
		return
	super.stagger(power)


func shield_blocks(from: Vector3) -> bool:
	if shield_hp <= 0.0 or shield_t > 0.0 or dead or downed:
		return false
	var l := Basis(Vector3.UP, -heading) * (from - global_position)
	var l2 := Vector2(l.x, l.z)
	if l2.length() < 0.2:
		return false
	return -l2.normalized().y > float(spec.get("shield_arc", 0.55))


func shield_hit(amount: float, hit: Vector3) -> void:
	shield_hp -= amount
	_pulse = maxf(_pulse, 0.5)
	Sfx.play_at(&"ricochet", hit, -6.0)
	if world != null and world.fx != null:
		world.fx.spark(hit, Color(0.4, 0.9, 1.0))
	if shield_hp <= 0.0:
		break_shield()


func break_shield() -> void:
	if shield_hp <= 0.0 and shield_t > 0.0:
		return
	if float(spec.get("shield", 0.0)) <= 0.0:
		return
	shield_hp = 0.0
	shield_t = float(spec.get("shield_down", 4.5))
	open_t = shield_t
	open_k = 1.4
	_stun = maxf(_stun, 0.7)
	FX.burst(center(), Color(0.4, 0.95, 1.0), 14, 6.0, 0.5, 2.0, 1.6)
	Sfx.play_at(&"ricochet", center(), -2.0, 0.7)


func damage(amount: float, crit := false, mirrored := false) -> void:
	if dead or not active or amount <= 0.0 or not exposed:
		return
	if downed:
		_finish_downed()
		return
	var amt := amount
	var by_ray := wk.from_ray()
	var wi := wk.take()
	if wi >= 0:
		amt = wk.damage_part(wi, amt)
		_pulse = 1.0
		if world != null and world.fx != null:
			world.fx.spark(global_position + _to_world((wk.defs[wi] as Dictionary)["pos"] as Vector3), Color(1.0, 1.0, 0.6))
	elif not plates.is_empty():
		amt = _through_plates(amt, by_ray)
	if open_t > 0.0:
		amt *= open_k
	if in_cover and crouch > 0.6:
		amt *= 0.6                                           # cover soaks part of every shot
	if cloak_k > 0.0 or id == &"veil_stalker":
		reveal_t = 1.4
	_hit_t = RosterWeak.now()
	super.damage(amt, crit, mirrored)


## Armour: the plate on the side the hero stands soaks the hit (a blast or a melee blow passes half through); a broken plate drops off and may open the core.
func _through_plates(amt: float, by_ray: bool) -> float:
	var l := Basis(Vector3.UP, -heading) * (hero_pos() - global_position) if hero_pos().is_finite() else Vector3(0.0, 0.0, -1.0)
	var ang := absf(atan2(l.x, -l.z))                                      # 0 = straight ahead
	if ang > 2.3:
		return amt                                                         # from behind: no plate there
	var side: StringName = &"front" if ang < 1.05 else (&"left" if l.x < 0.0 else &"right")
	var hit: Dictionary = {}
	for p in plates:
		if StringName(p["side"]) == side and float(p["hp"]) > 0.0:
			hit = p
	if hit.is_empty():
		return amt
	var soak := amt if by_ray else amt * 0.5
	hit["hp"] = float(hit["hp"]) - soak
	_pulse = 0.6
	Sfx.play_at(&"ricochet", center(), -5.0)
	if float(hit["hp"]) <= 0.0:
		(hit["node"] as MeshInstance3D).visible = false
		FX.burst(global_position + Vector3(0.0, 2.0, 0.0), Color(1.0, 0.8, 0.3), 12, 6.0, 0.5, 6.0, 1.8)
		Sfx.play_at(&"hit", center(), -2.0, 0.6)
		_stun = maxf(_stun, 0.5)
		if side == &"front":
			open_t = 3.0
			open_k = 1.3
	return amt - soak if not by_ray else amt * 0.08


func _part_broken(_i: int, _pid: StringName, fx: StringName) -> void:
	FX.burst(center(), Color(1.0, 0.7, 0.3), 14, 6.0, 0.5, 4.0, 1.8)
	Sfx.play_at(&"hit", center(), -2.0, 0.6)
	match fx:
		&"ground":
			jet_mode = &"down"
			grounded_t = 3.5
			open_t = 3.5
			open_k = 1.5
			_stun = maxf(_stun, 1.2)
		&"crash":
			_go(&"crash")
		&"stun":
			_stun = maxf(_stun, 2.5)
			open_t = 2.5
			open_k = 1.3


func is_boss() -> bool:
	return false


# --- going down and getting up (the revive) ----------------------------------------------------------------------------------------------------------

func _medic_near(r: float) -> RosterFoe:
	if world == null:
		return null
	for o in world.creatures:
		var m := o as RosterFoe
		if m != null and m != self and not m.dead and not m.downed and bool(m.spec.get("medic", false)) and m.revives_left > 0 and m.global_position.distance_to(global_position) <= r:
			return m
	return null


func can_go_down() -> bool:
	return bool(spec.get("revivable", false)) and revived < 1 and not _no_down and _medic_near(26.0) != null


func die(hero_kill := true) -> void:
	if dead:
		return
	if hero_kill and not downed and can_go_down():
		_go_down()
		return
	downed = false
	if mesh != null:
		mesh.rotation = Vector3.ZERO
	squash = 1.0
	super.die(hero_kill)


func _go_down() -> void:
	downed = true
	down_t = 0.0
	hp = 1.0
	_go(&"downed")
	crouch = 0.0
	squash = 0.3
	_beacon_t = 0.0
	Sfx.bark(&"yelp", global_position, 1.0, -4.0)
	if world != null and world.fx != null:
		world.fx.ring(Vector3(position.x, ground + 0.1, position.z), 1.6, 1.0, Color(1.0, 0.25, 0.2))


func _finish_downed() -> void:
	_no_down = true
	downed = false
	hp = 0.0
	die(true)


func revive(frac := REVIVE_FRAC) -> void:
	if not downed or dead:
		return
	downed = false
	revived += 1
	hp = max_hp * frac
	squash = 1.0
	if mesh != null:
		mesh.rotation = Vector3.ZERO
	_go(&"advance")
	cool = 1.0
	FX.burst(center(), Color(0.3, 1.0, 0.5), 12, 4.0, 0.6, -1.0, 1.6)
	if world != null and world.fx != null:
		world.fx.ring(Vector3(position.x, ground + 0.1, position.z), 2.2, 0.6, Color(0.3, 1.0, 0.5))


func _tick_down(dt: float) -> void:
	down_t += dt
	_beacon_t -= dt
	if _beacon_t <= 0.0 and world != null and world.fx != null:
		_beacon_t = 1.3
		world.fx.ring(Vector3(position.x, ground + 0.1, position.z), 1.3, 1.0, Color(1.0, 0.25, 0.2))
	if down_t >= DOWN_MAX or _medic_near(60.0) == null and down_t > 3.0:
		_finish_downed()


# --- brains: the dispatcher ---------------------------------------------------------------------------------------------------------------------------

## The timers run every tick, stunned or not (a stunned bearer's shield still comes back).
func tick(dt: float) -> void:
	if not dead and active:
		_mat_time += dt
		open_t = maxf(0.0, open_t - dt)
		reveal_t = maxf(0.0, reveal_t - dt)
		heal_cd = maxf(0.0, heal_cd - dt)
		if shield_t > 0.0:
			shield_t -= dt
			if shield_t <= 0.0 and float(spec.get("shield", 0.0)) > 0.0:
				shield_hp = float(spec["shield"]) * 0.5
		_los_t -= dt
	super.tick(dt)


func _tick_extra(dt: float, d: float) -> void:
	if downed:
		_tick_down(dt)
		_anim(dt)
		return
	crouch = move_toward(crouch, crouch_to, dt * 5.0)
	match mech:
		&"ros_gun": _tick_gun(dt, d)
		&"ros_swarm": _tick_swarm(dt, d)
		&"ros_charge": _tick_charge(dt, d)
		&"ros_stalk": _tick_stalk(dt, d)
		&"ros_jet": _tick_jet(dt, d)
		&"ros_walker": _tick_walker(dt, d)
		&"ros_crawler": _tick_crawler(dt, d)
		&"ros_drone": _tick_drone(dt, d)
		&"ros_turret": _tick_turret2(dt, d)
	_anim(dt)


func _anim(dt: float) -> void:
	var xz := Vector2(position.x, position.z)
	if _last_xz.is_finite() and dt > 0.0:
		var sp := xz.distance_to(_last_xz) / dt
		var ref := maxf(float(spec.get("run", 4.0)), 2.0)
		stride_k = lerpf(stride_k, clampf(sp / ref, 0.0, 1.0), clampf(dt * 8.0, 0.0, 1.0))
		_stride_t += dt * (3.0 + 9.0 * stride_k)
	_last_xz = xz
	crouch = move_toward(crouch, crouch_to, dt * 5.0)


## Position, facing and shader state (the AlienCreature base plus lift, crouch, stride, cloak, shield and the downed pose).
func _apply() -> void:
	var fd := flat_dist()
	var ds := 1.0 + 0.5 * smoothstep(10.0, 36.0, fd) if is_finite(fd) and family != AlienSpecies.BOSS else 1.0        # readability: a far figure is drawn a little bigger
	vis = base_vis * ds
	radius = float(spec["r"]) * vis
	super._apply()
	var tgt := 1.0 - 0.3 * crouch
	squash = 0.3 if downed else tgt
	if cls == AlienSpecies.GROUND and lift > 0.0:
		position.y += lift
	if mesh != null:
		mesh.scale = Vector3(vis, vis * squash, vis)
		mesh.rotation.x = 1.45 if downed else 0.0
	if mat != null:
		mat.set_shader_parameter(&"stride", 0.0 if downed else (stride_k if stride_k > 0.05 else 0.0))
		mat.set_shader_parameter(&"stride_t", _stride_t)
		var ck := 0.0
		if float(spec.get("cloak", 0.0)) > 0.0:
			ck = cloak_k
		mat.set_shader_parameter(&"cloak", ck)
		mat.set_shader_parameter(&"shield", 0.3 if (shield_hp > 0.0 and shield_t <= 0.0) else 0.0)
		mat.set_shader_parameter(&"far_k", (0.55 if aggro else 0.3) * smoothstep(9.0, 34.0, fd) if is_finite(fd) else 0.0)
	for p in plates:
		var n := p["node"] as MeshInstance3D
		if is_instance_valid(n) and float(p["hp"]) > 0.0:
			n.visible = visible


# --- helpers ----------------------------------------------------------------------------------------------------------------------------------------------

func _bolt_color() -> Color:
	match faction:
		RosterSpecies.CONTRACT:
			return MERC_COLOR
		RosterSpecies.GRID:
			return GRID_COLOR
	return spec["glow"]


func _muzzle() -> Vector3:
	var m: Vector3 = MUZZLE.get(id, Vector3(0.2, 1.3, -0.9))
	var mx := m.x * _muz_side if id == &"crawler" or id == &"wasp_drone" or id == &"auto_turret" else m.x
	return global_position + Basis(Vector3.UP, heading) * Vector3(mx, m.y * squash, m.z) * vis + Vector3(0.0, lift, 0.0)


func _lead_point() -> Vector3:
	var h := hero_pos()
	if Difficulty.current != Difficulty.EASY and world != null:
		h += Vector3(world.hero_vel2.x, 0.0, world.hero_vel2.y) * 0.3
	return h


func _blocked(a: Vector3, b: Vector3) -> bool:
	var n := int(a.distance_to(b) / 5.0)
	for k in range(1, n + 1):                                                            # the terrain between (no collider needed)
		var p := a.lerp(b, float(k) / float(n + 1))
		if TerrainHeight.height_at(p.x, p.z) > p.y + 0.3:
			return true
	if not is_inside_tree():
		return false
	var dir := b - a
	var l := dir.length()
	if l < 0.5:
		return false
	_ray.from = a
	_ray.to = a + dir * (1.0 - 0.4 / l)
	_ray.exclude = _hero_excludes()
	return not get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()


func _hero_excludes() -> Array[RID]:
	var out: Array[RID] = []
	var p := Game.player
	if p is CollisionObject3D:
		out.append((p as CollisionObject3D).get_rid())
		var v: Variant = p.get(&"vehicle")
		if v is CollisionObject3D and is_instance_valid(v):
			out.append((v as CollisionObject3D).get_rid())
	return out


## Does the foe have a line to the hero's chest (terrain and world colliders)? Cached for LOS_EVERY seconds.
func _los_to_hero() -> bool:
	if _los_t > 0.0:
		return _los
	_los_t = LOS_EVERY
	var h := hero_pos()
	if not h.is_finite():
		_los = false
		return false
	_los = not _blocked(global_position + Vector3(0.0, maxf(1.0 * squash, 0.8) * vis + lift, 0.0), h)
	return _los


func _step_dir(dir: Vector2, speed: float, dt: float) -> float:
	if dir.length() < 0.001:
		return 0.0
	var step := speed * dt
	var n := dir.normalized()
	var nx := position.x + n.x * step
	var nz := position.z + n.y * step
	var ny := TerrainHeight.height_at(nx, nz)
	var w := TerrainHeight.water_level_for(nx, nz, ny)
	var wet := w != TerrainHeight.NO_WATER and w - ny > 0.55
	var steep := (ny - ground) > maxf(step * 1.7, 0.08) and step > 0.001 and not bool(spec.get("climb", false))
	if wet or steep:
		_stuck += dt
		return 0.0
	_stuck = maxf(0.0, _stuck - dt)
	position.x = nx
	position.z = nz
	ground = ny
	return step


## Walks toward `to` (xz). With `face` the body keeps looking at the hero (back-pedal, strafe), else it turns to the walking direction first.
func _walk(to: Vector2, speed: float, dt: float, face := false) -> float:
	if face:
		_face(_hero2(), dt, 9.0)
		return _step_dir(to - Vector2(position.x, position.z), speed, dt)
	return _steer(to, speed, dt)


func _crouch_to_set(v: float) -> void:
	crouch_to = v
	in_cover = v > 0.5


func _leap_ok() -> bool:
	return world == null or world.leap_gate(self)


func _should_retreat() -> bool:
	var f := float(spec.get("retreat", 0.0))
	return f > 0.0 and not retreated and hp < max_hp * f


## Another living RosterFoe of the species flag `medic`, nearest first within `r`.
func _nearest_medic(r: float) -> RosterFoe:
	var best: RosterFoe = null
	var bd := r
	for o in world.creatures:
		var m := o as RosterFoe
		if m != null and m != self and not m.dead and not m.downed and bool(m.spec.get("medic", false)):
			var dd := m.global_position.distance_to(global_position)
			if dd < bd:
				bd = dd
				best = m
	return best


## A spot within 10 m the hero has no line to (a candidate must be dry, not steep, and blocked from crouch height), nearest first; Vector2.INF for none.
func find_cover(threat: Vector3) -> Vector2:
	var from2 := Vector2(position.x, position.z)
	var best := Vector2.INF
	var bs := INF
	var base_a := randf() * TAU
	for ring: float in [3.0, 6.0, 9.5]:
		for k in 8:
			var a := base_a + TAU * float(k) / 8.0
			var c2 := from2 + Vector2(cos(a), sin(a)) * ring
			var gy := TerrainHeight.height_at(c2.x, c2.y)
			var w := TerrainHeight.water_level_for(c2.x, c2.y, gy)
			if (w != TerrainHeight.NO_WATER and w - gy > 0.4) or absf(gy - ground) > ring * 0.6:
				continue
			if _blocked(Vector3(c2.x, gy + 1.0, c2.y), threat):
				var sc := ring + Vector2(c2.x - threat.x, c2.y - threat.z).length() * 0.02
				if sc < bs:
					bs = sc
					best = c2
		if best.is_finite():
			break
	return best


# --- shooting (shared by every brain) ------------------------------------------------------------------------------------------------------------------

func _begin_shot() -> void:
	var kind := StringName(spec.get("shot", &"burst"))
	_aim = _lead_point()
	var from := _muzzle()
	_go(&"windup")
	_pulse = 0.0
	var wt := float(spec["windup"]) * _aggr_k()
	var col := _bolt_color()
	if world != null and world.fx != null:
		match kind:
			&"beam", &"rocket":
				world.fx.line(from, from + (_aim - from).normalized() * minf(from.distance_to(_aim) + 4.0, 80.0), wt, col)
			_:
				if wt >= 0.45 and id != &"hiveling":
					world.fx.line(from, from + (_aim - from).normalized() * minf(from.distance_to(_aim), 30.0), minf(wt, 0.8), col)
	_play_once(&"attack", 1.0)


func _tick_shoot(dt: float, _d: float) -> void:
	match state:
		&"windup":
			var wt := float(spec["windup"]) * _aggr_k()
			_face(Vector2(_aim.x, _aim.z), dt, 9.0)
			_pulse = clampf(st_t / wt, 0.0, 1.0)
			if st_t < wt * 0.7:
				_aim = _aim.lerp(_lead_point(), clampf(dt * 4.0, 0.0, 1.0))                   # the aim follows the hero, then it is locked: a late move dodges
			if st_t >= wt:
				_fire_start()
		&"fire":
			_face(Vector2(_aim.x, _aim.z), dt, 9.0)
			burst_t -= dt
			if burst_t <= 0.0 and burst_left > 0:
				_shoot_one()
				burst_left -= 1
				burst_t = float(spec.get("gap", 0.15))
			if burst_left <= 0 and burst_t <= 0.0:
				_end_shot()
		&"recover":
			if st_t >= 0.45:
				_after_shot()


func _fire_start() -> void:
	match StringName(spec.get("shot", &"burst")):
		&"burst":
			burst_left = int(spec.get("n", 3))
			burst_t = 0.0
			_go(&"fire")
		&"pellets":
			_fire_pellets()
			_end_shot()
		&"rocket":
			_fire_rocket()
			_end_shot()
		&"beam":
			_fire_beam()
			_end_shot()
		_:
			burst_left = 1
			burst_t = 0.0
			_go(&"fire")


func _end_shot() -> void:
	cool = float(spec["cool"]) * _aggr_k() * randf_range(0.9, 1.2)
	_go(&"recover")


func _after_shot() -> void:
	match mech:
		&"ros_drone":
			_go(&"climb")
		&"ros_turret":
			_go(&"track")
		_:
			if bool(spec.get("cover", false)) and cover_fail <= 0.0 and cls != AlienSpecies.STATIC:
				_go(&"cover")
			else:
				_go(&"advance")


func _shot_sound(at: Vector3, db: float) -> void:
	var row: Array = SND.get(id, [&"enemy_shot", 0.8])
	Sfx.play_at(StringName(row[0]), at, db, float(row[1]) * randf_range(0.95, 1.06))


func _spread() -> float:
	return float(spec.get("spread", 0.05)) * (1.5 if Difficulty.current == Difficulty.EASY else 1.0)


func _shoot_one() -> void:
	var from := _muzzle()
	var dir := (_aim - from).normalized()
	var sp := _spread()
	dir = dir.rotated(Vector3.UP, randf_range(-sp, sp))
	dir = dir.rotated(dir.cross(Vector3.UP).normalized(), randf_range(-sp, sp) * 0.5) if absf(dir.y) < 0.95 else dir
	var col := _bolt_color()
	if world != null:
		world.shoot(from, dir, float(spec.get("speed", 30.0)), float(spec["dmg"]), 0.5, col, 0.55, self)
	attacks_done += 1
	_muz_side = -_muz_side
	FX.burst(from, col, 3, 3.0, 0.12, 0.0, 1.3)
	_shot_sound(from, -5.0)


func _fire_pellets() -> void:
	var from := _muzzle()
	var dir := (_aim - from).normalized()
	var h := hero_pos()
	var to := h - from
	var reach := float(spec["reach"])
	attacks_done += 1
	FX.burst(from + dir * 0.6, Color(1.0, 0.75, 0.3), 7, 9.0, 0.18, 0.0, 1.0)
	_shot_sound(from, -2.0)
	if to.length() <= reach and absf(dir.angle_to(to.normalized())) <= float(spec.get("cone", 0.26)) and not _blocked(from, h):
		var fall := 1.0 - 0.45 * clampf(to.length() / reach, 0.0, 1.0)
		if _hurt_hero(float(spec["dmg"]) * fall):
			world.knock_hero(Vector3(to.x, 0.0, to.z).normalized() * 6.0 + Vector3.UP * 2.0)


func _fire_rocket() -> void:
	var from := _muzzle()
	var g := Vector3(_aim.x, TerrainHeight.height_at(_aim.x, _aim.z), _aim.z)
	attacks_done += 1
	FX.burst(global_position + Basis(Vector3.UP, heading) * Vector3(0.3, 1.5, 0.9), Color(1.0, 0.6, 0.2), 8, 5.0, 0.3, 0.0, 1.6)         # the back blast
	_shot_sound(from, -1.0)
	if world != null and world.fire != null:
		world.fire.rocket(from, g, float(spec.get("speed", 17.0)), float(spec.get("boom", 3.6)), float(spec["dmg"]), Color(1.0, 0.55, 0.2), 0.9, self)


func _fire_beam() -> void:
	var from := _muzzle()
	var dir := (_aim - from).normalized()
	var end := from + dir * (from.distance_to(_aim) + 8.0)
	attacks_done += 1
	if world != null and world.fx != null:
		world.fx.line(from, end, 0.22, _bolt_color().lerp(Color.WHITE, 0.4))
	_shot_sound(from, -1.0)
	var h := hero_pos()
	if h.is_finite() and Geometry3D.get_closest_point_to_segment(h, from, end).distance_to(h) < 0.95 and not _blocked(from, h):
		_hurt_hero(float(spec["dmg"]))


# --- the gunner brain ---------------------------------------------------------------------------------------------------------------------------------

func _tick_gun(dt: float, d: float) -> void:
	cover_fail = maxf(0.0, cover_fail - dt)
	nade_cd = maxf(0.0, nade_cd - dt)
	if bool(spec.get("medic", false)) and _tick_medic(dt, d):
		return
	var h2 := _hero2()
	var p2 := Vector2(position.x, position.z)
	var keep: Array = spec.get("keep", [8.0, 20.0])
	var run := float(spec["run"])
	match state:
		&"windup", &"fire", &"recover":
			_tick_shoot(dt, d)
		&"idle":
			crouch_to = 0.0
			_wander(dt)
			if aggro or _sees(d):
				_wake()
				_go(&"advance")
		&"advance":
			if _lost(d):
				aggro = false
				_go(&"idle")
				return
			crouch_to = 0.0
			in_cover = false
			var los := _los_to_hero()
			if _should_retreat():
				_go(&"retreat")
				return
			if not _flank_rolled:
				_flank_rolled = true
				if randf() < float(spec.get("flank", 0.0)):
					_flank_side = 1.0 if randf() < 0.5 else -1.0
					_go(&"flank")
					return
			if d > float(keep[1]) or not los:
				_walk(h2, run, dt)
			elif d < float(keep[0]):
				_walk(p2 + (p2 - h2).normalized() * 6.0, float(spec["walk"]) * 1.2, dt, true)
			else:
				var perp := (h2 - p2).orthogonal().normalized() * (1.0 if int(phase * 3.0 + st_t / 2.2) % 2 == 0 else -1.0)
				_walk(p2 + perp * 3.0, float(spec["walk"]) * 0.7, dt, true)
			_separate(dt)
			if los and d <= float(spec["reach"]) and cool <= 0.0:
				if bool(spec.get("cover", false)) and cover_fail <= 0.0 and not in_cover:
					var sp := find_cover(hero_pos())
					if sp.is_finite():
						cover_spot = sp
						_go(&"cover")
						return
					cover_fail = 4.0
				if float(spec.get("nade", 0.0)) > 0.0 and nade_cd <= 0.0 and d >= 10.0 and d <= 28.0 and _leap_ok():
					_go(&"nade")
					return
				if float(spec.get("bash", 0.0)) > 0.0 and d < 4.2:
					_go(&"bash")
					return
				if d >= 1.5 and _leap_ok():
					_begin_shot()
		&"cover":
			if not cover_spot.is_finite() or st_t > 5.0:
				cover_fail = 3.0
				_go(&"advance")
				return
			if p2.distance_to(cover_spot) > 0.7:
				_walk(cover_spot, run, dt)
			else:
				_crouch_to_set(1.0)
				_cover_t = randf_range(0.9, 2.0) * _aggr_k()
				_go(&"covered")
		&"covered":
			_face(h2, dt, 6.0)
			_cover_t -= dt
			if d < 5.5 or d > float(spec["reach"]) * 1.4:
				cover_spot = Vector2.INF
				cover_fail = 3.0
				_go(&"advance")
			elif _cover_t <= 0.0 and cool <= 0.0 and _leap_ok():
				peek_dir = 1.0 if randf() < 0.5 else -1.0
				_crouch_to_set(0.0)
				_go(&"peek")
		&"peek":
			_face(h2, dt, 8.0)
			if _los_to_hero():
				_begin_shot()
			elif st_t < 1.4:
				_step_dir((h2 - p2).orthogonal().normalized() * peek_dir, run * 0.5, dt)
			else:
				_crouch_to_set(1.0)
				cover_fail = 2.0
				_go(&"advance")
		&"flank":
			var away := p2 - h2
			var mid := (float(keep[0]) + float(keep[1])) * 0.5
			var tgt := h2 + (away.normalized() if away.length() > 0.1 else Vector2.RIGHT).rotated(_flank_side * 1.0) * mid
			_walk(tgt, run, dt)
			if st_t > 4.5 or p2.distance_to(tgt) < 2.5:
				_go(&"advance")
		&"retreat":
			if st_t < dt + 0.001:
				retreated = true
				var md := _nearest_medic(60.0)
				_retreat_to = Vector2(md.position.x, md.position.z) if md != null else p2 + (p2 - h2).normalized() * 24.0
			_walk(_retreat_to, run * 1.1, dt)
			if p2.distance_to(_retreat_to) < 2.5 or st_t > 5.0:
				_crouch_to_set(1.0)
				_go(&"rest")
		&"rest":
			hp = minf(max_hp, hp + max_hp * 0.05 * dt)
			if st_t > 3.0:
				_crouch_to_set(0.0)
				hp = minf(max_hp, hp + max_hp * 0.12)
				_go(&"advance")
		&"nade":
			_face(h2, dt, 8.0)
			_pulse = clampf(st_t / 0.6, 0.0, 1.0)
			if st_t >= 0.6 * _aggr_k():
				_throw_grenade()
				_go(&"recover")
		&"bash":
			if st_t < dt + 0.001 and world != null and world.fx != null:
				world.fx.ring(global_position + Basis(Vector3.UP, heading) * Vector3(0.0, 0.0, -1.4), 2.4, 0.6 * _aggr_k(), Color(0.4, 0.95, 1.0))
			_face(h2, dt, 5.0)
			_pulse = clampf(st_t / (0.6 * _aggr_k()), 0.0, 1.0)
			if st_t >= 0.6 * _aggr_k():
				if _melee_hit(0.6, 1.1):
					world.knock_hero(Vector3(sin(-heading), 0.0, -cos(heading)) * -7.0 + Vector3.UP * 2.5)
				cool = float(spec["cool"]) * _aggr_k()
				_go(&"recover")
		_:
			_go(&"advance")


func _throw_grenade() -> void:
	var from := global_position + Vector3(0.0, 1.5 * vis, 0.0)
	var h := hero_pos()
	var to := Vector3(h.x, 0.0, h.z)
	if world != null:
		to += Vector3(world.hero_vel2.x, 0.0, world.hero_vel2.y) * (0.0 if Difficulty.current == Difficulty.EASY else 0.5)
	nades += 1
	attacks_done += 1
	nade_cd = float(spec.get("nade", 12.0)) * _aggr_k() * randf_range(0.9, 1.3)
	Sfx.play_at(&"enemy_shot", from, -6.0, 0.7)
	if world != null and world.fire != null:
		world.fire.shell(from, to, 0.95, 3.4, 14.0, Color(1.0, 0.5, 0.15), 0.5, 0.8, 0.5, self)


# --- the medic ------------------------------------------------------------------------------------------------------------------------------------------

func _patient() -> RosterFoe:
	var best: RosterFoe = null
	var bd := 1.0e9
	var best_down := false
	for o in world.creatures:
		var m := o as RosterFoe
		if m == null or m == self or m.dead or m.faction != faction:
			continue
		var dd := m.global_position.distance_to(global_position)
		if dd > 34.0:
			continue
		var is_down := m.downed and revives_left > 0
		var wounded := not m.downed and m.hp < m.max_hp * 0.65
		if not is_down and not wounded:
			continue
		if (is_down and not best_down) or (is_down == best_down and dd < bd):
			best = m
			bd = dd
			best_down = is_down
	return best


func _tick_medic(dt: float, _d: float) -> bool:
	if state == &"channel":
		_tick_channel(dt)
		return true
	if state == &"support":
		var pt := _patient()
		if pt == null:
			_go(&"advance")
			return true
		var to := Vector2(pt.position.x, pt.position.z)
		if Vector2(position.x, position.z).distance_to(to) > 2.4:
			_walk(to, float(spec["run"]) * 1.15, dt)
			if st_t > 9.0:
				heal_cd = 3.0
				_go(&"advance")
		else:
			_chan = pt
			_chan_line = 0.0
			_go(&"channel")
		return true
	if state == &"windup" or state == &"fire" or state == &"recover" or state == &"idle" or not aggro:
		return false
	if heal_cd <= 0.0 and _patient() != null:
		_go(&"support")
		return true
	return false


func _tick_channel(dt: float) -> void:
	var pt := _chan
	if pt == null or not is_instance_valid(pt) or pt.dead:
		_go(&"advance")
		return
	_face(Vector2(pt.position.x, pt.position.z), dt, 6.0)
	crouch_to = 0.5
	if RosterWeak.now() - _hit_t < 0.5 and pt.downed:                           # shot while reviving: the revive is interrupted
		heal_cd = 4.0
		crouch_to = 0.0
		_go(&"advance")
		return
	_chan_line -= dt
	if _chan_line <= 0.0 and world != null and world.fx != null:
		_chan_line = 0.45
		world.fx.line(center(), pt.center(), 0.5, Color(0.3, 1.0, 0.5))
	if pt.downed:
		if st_t >= 2.4 * _aggr_k():
			pt.revive()
			revives_left -= 1
			revives_done += 1
			heal_cd = 2.0
			crouch_to = 0.0
			_go(&"advance")
	else:
		pt.hp = minf(pt.max_hp, pt.hp + float(spec.get("heal", 7.0)) * dt)
		if pt.hp >= pt.max_hp * 0.95 or st_t > 4.0:
			heal_cd = 3.0
			crouch_to = 0.0
			_go(&"advance")


# --- the swarm: hivelings ---------------------------------------------------------------------------------------------------------------------------------

func _tick_swarm(dt: float, d: float) -> void:
	var ring: Array = spec.get("ring", [5.5, 9.0])
	var h2 := _hero2()
	var p2 := Vector2(position.x, position.z)
	match state:
		&"idle":
			_wander(dt)
			if aggro or _sees(d):
				_wake()
				_go(&"circle")
		&"circle":
			if _lost(d):
				aggro = false
				_go(&"idle")
				return
			slot += dt * 0.7
			var r := lerpf(float(ring[0]), float(ring[1]), 0.5 + 0.5 * sin(phase))
			_steer(h2 + Vector2(cos(slot), sin(slot)) * r, float(spec["run"]) * 0.7, dt)
			_separate(dt)
			_surge_t -= dt
			if _surge_t <= 0.0 and d < 24.0 and _leap_ok():
				_aim = hero_pos()
				_pulse = 1.0
				_go(&"windup")
		&"windup":
			_face(Vector2(_aim.x, _aim.z), dt, 12.0)
			crouch_to = 1.0
			_pulse = clampf(st_t / (0.4 * _aggr_k()), 0.0, 1.0)
			if st_t >= 0.4 * _aggr_k():
				crouch_to = 0.0
				_go(&"rush")
		&"rush":
			var to := Vector2(_aim.x, _aim.z)
			var hit_r := 1.3
			if p2.distance_to(h2) < hit_r or st_t > 1.1:
				if p2.distance_to(h2) < hit_r + 0.5 and not _hero_airborne():
					attacks_done += 1
					_hurt_hero(float(spec["dmg"]))
				_surge_t = randf_range(float((spec["surge"] as Array)[0]), float((spec["surge"] as Array)[1])) * _aggr_k()
				_go(&"bounce")
			else:
				_step_dir(to - p2, float(spec["run"]) * 1.2, dt)
				_face(to, dt, 14.0)
		&"bounce":
			_step_dir(p2 - h2, float(spec["run"]) * 0.8, dt)
			if st_t > 0.9:
				_go(&"circle")
		_:
			_go(&"circle")


# --- the plate brute --------------------------------------------------------------------------------------------------------------------------------------

func _tick_charge(dt: float, d: float) -> void:
	var h2 := _hero2()
	var p2 := Vector2(position.x, position.z)
	var wt := float(spec["windup"]) * _aggr_k()
	match state:
		&"idle":
			_wander(dt)
			if aggro or _sees(d):
				_wake()
				_go(&"stalk")
		&"stalk":
			if _lost(d):
				aggro = false
				_go(&"idle")
				return
			_steer(h2, float(spec["walk"]) * 1.4, dt)
			if cool <= 0.0 and d <= 4.2:
				if world != null and world.fx != null:
					world.fx.ring(Vector3(position.x, ground + 0.1, position.z), float(spec.get("slam_r", 5.0)), wt, Color(1.0, 0.7, 0.2))
				_go(&"slam")
			elif cool <= 0.0 and d >= 7.0 and d <= 22.0 and _leap_ok():
				_aim = hero_pos()
				if world != null and world.fx != null:
					var dir := (Vector3(_aim.x, global_position.y, _aim.z) - global_position).normalized()
					world.fx.line(global_position + Vector3(0.0, 0.4, 0.0), global_position + dir * (d + 6.0) + Vector3(0.0, 0.4, 0.0), wt, Color(1.0, 0.55, 0.2))
				_go(&"roar")
		&"roar":
			_face(Vector2(_aim.x, _aim.z), dt, 8.0)
			_pulse = clampf(st_t / wt, 0.0, 1.0)
			if st_t < dt + 0.001:
				Sfx.bark(&"growl", global_position, 0.6, -2.0)
			if st_t >= wt:
				_go(&"charge")
		&"charge":
			var dir2 := Vector2(-sin(heading), -cos(heading))
			_step_dir(dir2, float(spec["run"]) * 1.7, dt)
			if p2.distance_to(h2) < 1.9 and not _hero_airborne():
				attacks_done += 1
				_hurt_hero(float(spec["dmg"]))
				world.knock_hero(Vector3(dir2.x, 0.0, dir2.y) * 9.0 + Vector3.UP * 4.0)
				_go(&"stumble")
			elif st_t > 1.2:
				_go(&"stumble")
		&"stumble":
			open_t = maxf(open_t, 0.3)
			open_k = 1.5
			if st_t >= 1.2:
				cool = float(spec["cool"]) * _aggr_k()
				_go(&"stalk")
		&"slam":
			_face(h2, dt, 3.0)
			_pulse = clampf(st_t / wt, 0.0, 1.0)
			if st_t >= wt:
				var sr := float(spec.get("slam_r", 5.0))
				FX.blast(global_position, sr * 0.8, Color(1.0, 0.7, 0.2), 0.35, -1, 0.0, false)
				FX.shake(0.35)
				Sfx.play_at(&"boom", global_position, -4.0, 0.9)
				attacks_done += 1
				if d < sr and not _hero_airborne():
					_hurt_hero(float(spec["dmg"]))
				cool = float(spec["cool"]) * _aggr_k()
				_go(&"stumble")
		_:
			_go(&"stalk")


# --- the veil stalker -------------------------------------------------------------------------------------------------------------------------------------

func _tick_stalk(dt: float, d: float) -> void:
	var h2 := _hero2()
	var p2 := Vector2(position.x, position.z)
	var base := float(spec.get("cloak", 0.85))
	var tgt_cloak := 0.0 if (reveal_t > 0.0 or state == &"windup" or state == &"pounce") else (base if d > 7.0 else base * 0.75)
	cloak_k = move_toward(cloak_k, tgt_cloak, dt * 3.0)
	match state:
		&"idle":
			_wander(dt)
			if aggro or _sees(d):
				_wake()
				_go(&"stalk")
		&"stalk":
			if _lost(d):
				aggro = false
				_go(&"idle")
				return
			var side := (h2 - p2).orthogonal().normalized() * sin(phase + _mat_time * 0.6) * 5.0
			_steer(h2 + side, float(spec["walk"]) * 1.4, dt)
			if cool <= 0.0 and d < 10.0 and _leap_ok():
				_aim = hero_pos()
				if world != null and world.fx != null:
					world.fx.line(global_position + Vector3(0.0, 0.5, 0.0), _aim, 0.5 * _aggr_k(), Color(1.0, 0.2, 0.7))
				_go(&"windup")
		&"windup":
			_face(Vector2(_aim.x, _aim.z), dt, 12.0)
			_pulse = clampf(st_t / (float(spec["windup"]) * _aggr_k()), 0.0, 1.0)
			if st_t >= float(spec["windup"]) * _aggr_k():
				_go(&"pounce")
		&"pounce":
			var to := Vector2(_aim.x, _aim.z)
			_step_dir(to - p2, float(spec["run"]) * 1.25, dt)
			_face(to, dt, 14.0)
			if p2.distance_to(h2) < 1.7 or st_t > 0.6:
				if p2.distance_to(h2) < float(spec["reach"]) + 0.5 and not _hero_airborne():
					attacks_done += 1
					_hurt_hero(float(spec["dmg"]))
				cool = float(spec["cool"]) * _aggr_k()
				_go(&"slink")
		&"slink":
			_step_dir(p2 - h2, float(spec["run"]), dt)
			if st_t > 1.0:
				_go(&"stalk")
		_:
			_go(&"stalk")


# --- the jet elite ----------------------------------------------------------------------------------------------------------------------------------------

func _tick_jet(dt: float, d: float) -> void:
	grounded_t = maxf(0.0, grounded_t - dt)
	var pack := wk.part_alive(&"pack")
	var lr: Array = spec.get("lift", [3.5, 8.0])
	match jet_mode:
		&"ground":
			lift = lerpf(lift, 0.0, clampf(6.0 * dt, 0.0, 1.0))
			jet_t -= dt
			if pack and aggro and jet_t <= 0.0 and d < 40.0 and grounded_t <= 0.0 and (state == &"advance" or state == &"recover"):
				jet_mode = &"up"
				jet_h = randf_range(float(lr[0]), float(lr[1]))
				var a := randf() * TAU
				var h2 := _hero2()
				jet_dest = h2 + Vector2(cos(a), sin(a)) * randf_range(float((spec["keep"] as Array)[0]), float((spec["keep"] as Array)[1]))
				Sfx.play_at(&"boom", global_position, -12.0, 1.8)
		&"up":
			lift = move_toward(lift, jet_h, 12.0 * dt)
			_step_dir(jet_dest - Vector2(position.x, position.z), 6.0, dt)
			if absf(lift - jet_h) < 0.1:
				jet_mode = &"air"
				jet_air = randf_range(2.2, 3.2) * _aggr_k()
		&"air":
			lift = jet_h + sin(_mat_time * 3.0) * 0.25
			jet_air -= dt
			if jet_air <= 0.0 or not pack:
				jet_mode = &"down"
		&"down":
			lift = move_toward(lift, 0.0, (9.0 if pack else 14.0) * dt)
			if lift <= 0.05:
				lift = 0.0
				jet_mode = &"ground"
				jet_t = randf_range(6.0, 9.0) * _aggr_k()
				FX.burst(global_position, Color(0.8, 0.7, 0.5, 0.6), 8, 3.0, 0.5, -1.0, 3.0)
	if lift > 0.4 and int(_mat_time * 10.0) % 2 == 0:
		FX.burst(global_position + Vector3(0.0, lift - 0.2, 0.3), Color(1.0, 0.55, 0.15), 2, 3.0, 0.25, 2.0, 1.6)
	_tick_gun(dt, d)


# --- the strider ------------------------------------------------------------------------------------------------------------------------------------------

func _tick_walker(dt: float, d: float) -> void:
	salvo_cd = maxf(0.0, salvo_cd - dt)
	if not kneeled and hp < max_hp * float(spec.get("kneel", 0.35)) and aggro and state != &"kneel":
		kneeled = true
		_go(&"kneel")
		open_t = 3.5
		open_k = 1.5
		FX.shake(0.5)
		FX.burst(global_position + Vector3(0.0, 2.0, 0.0), Color(1.0, 0.6, 0.2), 14, 6.0, 0.6, 3.0, 2.0)
	if state == &"kneel":
		crouch_to = 1.0
		if st_t >= 3.5:
			crouch_to = 0.0
			_go(&"advance")
		return
	if state == &"salvo":
		_face(_hero2(), dt, 3.0)
		_pulse = clampf(st_t / (0.9 * _aggr_k()), 0.0, 1.0)
		if st_t >= 0.9 * _aggr_k():
			_launch_salvo()
			salvo_cd = float(spec.get("salvo_cd", 9.0)) * _aggr_k()
			_go(&"recover")
		return
	if aggro and salvo_cd <= 0.0 and state == &"advance" and d >= 14.0 and d <= 46.0 and _los_to_hero() and _leap_ok():
		_go(&"salvo")
		return
	_tick_gun(dt, d)


func _launch_salvo() -> void:
	var n := int(spec.get("salvo", 3))
	var h := hero_pos()
	for k in n:
		var off := Vector3(randf_range(-3.5, 3.5), 0.0, randf_range(-3.5, 3.5)) if k > 0 else Vector3.ZERO
		var from := global_position + Basis(Vector3.UP, heading) * Vector3((-1.25 if k % 2 == 0 else 1.25) * vis, 4.4 * vis, -0.4 * vis)
		if world != null and world.fire != null:
			world.fire.shell(from, Vector3(h.x + off.x, 0.0, h.z + off.z), 1.5 + 0.3 * float(k), 3.0, 12.0, Color(1.0, 0.5, 0.1), 0.8, 0.0, 0.5, self)
	attacks_done += 1
	salvos += 1
	Sfx.play_at(&"enemy_shot", global_position + Vector3(0.0, 4.0, 0.0), -3.0, 0.5)


# --- the crawler ------------------------------------------------------------------------------------------------------------------------------------------

func _tick_crawler(dt: float, d: float) -> void:
	leap_cd = maxf(0.0, leap_cd - dt)
	match state:
		&"leap_wind":
			crouch_to = 1.0
			_face(Vector2(_land_to.x, _land_to.z), dt, 8.0)
			_pulse = clampf(st_t / (0.7 * _aggr_k()), 0.0, 1.0)
			if st_t >= 0.7 * _aggr_k():
				crouch_to = 0.0
				_land_from = global_position
				_go(&"leap")
			return
		&"leap":
			var dist := Vector2(_land_to.x - _land_from.x, _land_to.z - _land_from.z).length()
			var T := clampf(dist / 14.0, 0.5, 1.0)
			var k := clampf(st_t / T, 0.0, 1.0)
			position.x = lerpf(_land_from.x, _land_to.x, k)
			position.z = lerpf(_land_from.z, _land_to.z, k)
			ground = TerrainHeight.height_at(position.x, position.z)
			position.y = lerpf(_land_from.y, ground, k) + 3.0 * 4.0 * k * (1.0 - k) * (dist / 14.0 + 0.4)
			if k >= 1.0:
				position.y = ground
				var sr := float(spec.get("slam_r", 4.0))
				FX.blast(global_position, sr * 0.7, Color(1.0, 0.3, 0.2), 0.3, -1, 0.0, false)
				FX.shake(0.3)
				Sfx.play_at(&"boom", global_position, -6.0, 1.0)
				attacks_done += 1
				if _hero2().distance_to(Vector2(position.x, position.z)) < sr and not _hero_airborne():
					_hurt_hero(float(spec["dmg"]) * 1.5)
				leap_cd = randf_range(6.0, 9.0) * _aggr_k()
				cool = 0.6
				_go(&"recover")
			return
	if aggro and leap_cd <= 0.0 and state == &"advance" and d >= float((spec["leap"] as Array)[0]) and d <= float((spec["leap"] as Array)[1]) and _leap_ok():
		var h := hero_pos()
		_land_to = Vector3(h.x, TerrainHeight.height_at(h.x, h.z), h.z)
		if world != null and world.fx != null:
			world.fx.ring(_land_to + Vector3(0.0, 0.1, 0.0), float(spec.get("slam_r", 4.0)), 0.7 * _aggr_k() + 0.6, Color(1.0, 0.3, 0.2))
		_go(&"leap_wind")
		return
	_tick_gun(dt, d)


# --- the wasp drone ---------------------------------------------------------------------------------------------------------------------------------------

func _fly_to(to: Vector2, speed: float, dt: float) -> void:
	var dir := to - Vector2(position.x, position.z)
	if dir.length() < 0.05:
		return
	var step := minf(speed * dt, dir.length())
	var n := dir.normalized()
	position.x += n.x * step
	position.z += n.y * step
	heading = lerp_angle(heading, atan2(-n.x, -n.y), clampf(6.0 * dt, 0.0, 1.0))


func _tick_drone(dt: float, d: float) -> void:
	var h2 := _hero2()
	var p2 := Vector2(position.x, position.z)
	var ar: Array = spec.get("alt", [4.5, 8.5])
	match state:
		&"idle":
			alt = lerpf(alt, float(ar[0]) + 0.8 * sin(phase + _mat_time), clampf(dt, 0.0, 1.0))
			_wander_fly(dt)
			if aggro or _sees(d):
				_wake()
				_go(&"orbit")
		&"orbit":
			if _lost(d):
				aggro = false
				_go(&"idle")
				return
			slot += dt * (float(spec["walk"]) / 11.0)
			alt = lerpf(alt, lerpf(float(ar[0]), float(ar[1]), 0.5 + 0.5 * sin(phase + slot)), clampf(2.0 * dt, 0.0, 1.0))
			_fly_to(h2 + Vector2(cos(slot), sin(slot)) * 11.0, float(spec["walk"]) * 1.3, dt)
			_separate(dt)
			if cool <= 0.0 and d <= float(spec["reach"]) and _los_to_hero() and _leap_ok():
				_aim = hero_pos()
				if world != null and world.fx != null:
					world.fx.line(_muzzle(), _aim, 0.7 * _aggr_k(), GRID_COLOR)
				_go(&"windup")
		&"windup":
			_face(Vector2(_aim.x, _aim.z), dt, 10.0)
			_pulse = clampf(st_t / (0.7 * _aggr_k()), 0.0, 1.0)
			if st_t >= 0.7 * _aggr_k():
				_dive_dir = (Vector2(_aim.x, _aim.z) - p2).normalized()
				burst_left = int(spec.get("n", 4))
				burst_t = 0.1
				_go(&"dive")
		&"dive":
			alt = lerpf(alt, 3.0, clampf(4.0 * dt, 0.0, 1.0))
			position.x += _dive_dir.x * float(spec["run"]) * dt
			position.z += _dive_dir.y * float(spec["run"]) * dt
			heading = atan2(-_dive_dir.x, -_dive_dir.y)
			ground = TerrainHeight.height_at(position.x, position.z)
			position.y = lerpf(position.y, ground + maxf(HOVER_MIN, alt), clampf(8.0 * dt, 0.0, 1.0))
			burst_t -= dt
			if burst_t <= 0.0 and burst_left > 0:
				_aim = hero_pos()
				_shoot_one()
				burst_left -= 1
				burst_t = float(spec.get("gap", 0.09))
			if st_t > 1.0:
				cool = float(spec["cool"]) * _aggr_k() * randf_range(0.9, 1.3)
				_go(&"climb")
		&"climb":
			alt = lerpf(alt, float(ar[1]), clampf(3.0 * dt, 0.0, 1.0))
			_fly_to(p2 + (p2 - h2).normalized() * 6.0, float(spec["walk"]) * 1.3, dt)
			if st_t > 1.0:
				_go(&"orbit")
		&"crash":
			alt = maxf(0.0, alt - 9.0 * dt)
			_pitch += dt * 6.0
			_fly_to(p2 + Vector2(-sin(heading), -cos(heading)) * 4.0, 4.0, dt)
			if st_t > 0.9:
				_pitch = 0.0
				FX.blast(global_position, 2.6, Color(1.0, 0.4, 0.2), 0.3, -1, 0.0, false)
				die(true)
		_:
			_go(&"orbit")


func _wander_fly(dt: float) -> void:
	_wander_t -= dt
	if _wander_t <= 0.0:
		_wander_t = randf_range(3.0, 6.0)
		var a := randf() * TAU
		_wander_to = Vector2(home.x, home.z) + Vector2(cos(a), sin(a)) * randf_range(0.0, 12.0)
	_fly_to(_wander_to, 3.0, dt)


# --- the auto turret ----------------------------------------------------------------------------------------------------------------------------------------

func _tick_turret2(dt: float, d: float) -> void:
	match state:
		&"idle":
			heading += 0.35 * dt * sin(phase)
			if aggro or (_sees(d) and _los_to_hero()):
				_wake()
				_go(&"track")
		&"track":
			if world == null or not world.hero_alive() or d > float(spec["reach"]) * 1.8:
				aggro = false
				_go(&"idle")
				return
			_face(_hero2(), dt, 4.0)
			if cool <= 0.0 and d <= float(spec["reach"]) and _los_to_hero() and _leap_ok():
				_begin_shot()
		&"windup", &"fire", &"recover":
			_tick_shoot(dt, d)
		_:
			_go(&"track")
