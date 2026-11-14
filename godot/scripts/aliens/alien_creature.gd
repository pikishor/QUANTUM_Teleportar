class_name AlienCreature
extends Node3D
## One alien of the wild (wave 107b): fauna that hunts, a camp guard, a nest heart, a turret. A plain steering body (no physics: the terrain height is asked at a low rate, trees and rocks do
## not stop it) that the AlienWorld ticks. It answers the enemy contract of the game, so every weapon, blast, verb and the aim assist treat it like any other enemy: group `enemy`, `damage()`,
## `center()`, `radius`, `hit_ray()` (a head sphere and a body sphere: HitZones), `stagger()`, `disable()`, `dead`, `active`.
##
## Behaviours (`mech` in AlienSpecies, one `_tick_<mech>` each, all with a TELEGRAPH before the attack: a glow, a ground ring or a line, because the game is EASY first):
##   leap     pack hunters surround the hero, crouch, then jump at him                    melee    walk up, wind up, claw
##   burst    a spore popper runs in and swells; killed early it only pops                spit     keeps its distance and lobs acid globs (slow enough to dodge)
##   slam     a brute raises its fists; the ground ring shows the shockwave (jump it)     ambush   a stalker, cloaked, creeps up, drops the cloak and pounces, then fades away
##   swoop    flyers circle high, hover, dive at the hero, climb away                     float    a drift ray hangs over the water and fires shock bolts
##   turret   a sentry turns, charges and fires a short burst                             nest     the hive heart pulses and hatches skitters until it is destroyed
##   relay    a shield relay (the warden's shield stands while one lives)                  burrow / serpent   the dune maw under the sand and the reef lurker in the sea: they travel
##            hidden (a tremor ring, a wake), mark where they will rise, rise, bite and sink again; they can only be hurt while risen
## Hurt creatures flinch and flash; death is a colourful blast, an alien puddle and a dissolve into quantum dust (no gore), then loot (AlienLoot) and a bounty.

signal died(c: AlienCreature)

const GRAVITY := 22.0
const DEATH_TIME := 1.15
const TURN := 7.0
const HOVER_MIN := 1.6

var id: StringName = &""
var type: StringName = &""                      ## the same as `id` (the aim assist and the HUD ask for `type`)
var spec: Dictionary = {}
var family: StringName = AlienSpecies.FAUNA
var cls: StringName = AlienSpecies.GROUND
var mech: StringName = &"melee"
var world: AlienWorld = null
var hp := 50.0
var max_hp := 50.0
var dead := false
var active := true
var radius := 0.6                                ## the body hit sphere (the aim assist reads it)
var state: StringName = &"idle"
var st_t := 0.0
var heading := 0.0
var vel := Vector3.ZERO
var ground := 0.0
var water_y := TerrainHeight.NO_WATER
var home := Vector3.ZERO
var leash := 90.0
var site: StringName = &""                       ## the camp, nest or lair it belongs to
var group: Dictionary = {}                       ## the pack (shared by reference): {members: Array}
var slot := 0.0                                  ## a pack member's angle around the hero
var cool := 0.0
var aggro := false
var exposed := true                              ## false while burrowed / submerged: untouchable and unseen
var rise := 1.0                                  ## 0 buried .. 1 up (worms, serpents)
var vis := 1.0
var alt := 0.0                                   ## flyers: metres over the ground
var phase := 0.0
var orb := 8.0
var by_hero := true
var attacks_done := 0                            ## tests and balance: attacks that left the creature
var hits_landed := 0                             ## attacks that hurt the hero
var model: Node3D = null
var ap: AnimationPlayer = null
var mesh: MeshInstance3D = null
var mat: ShaderMaterial = null
var shapes: Array = []                           ## [[local pos, radius, is_head], ...] scaled by `vis`, turned by `heading`
var _clip: StringName = &""
var _wander_t := 0.0
var _wander_to := Vector2.ZERO
var _gy_t := 0.0
var _stun := 0.0
var _off := 0.0
var _pulse := 0.0
var _dead_t := 0.0
var _stuck := 0.0
var _aim := Vector3.ZERO                         ## where a telegraphed attack was aimed when it started
var _aim2 := Vector2.ZERO
var _burrow_t := 0.0
var _voice_t := 3.0
var _hatch_t := 4.0
var _pitch := 0.0
var _hurt_flinch := 0.0
var _last_pos := Vector3.INF
var _shield := 0.0
var _beat := 0.0


## Builds the body of species `sid`. Returns false when its model is missing (the world then skips it).
func setup(sid: StringName, w: AlienWorld) -> bool:
	id = sid
	type = sid
	world = w
	spec = AlienSpecies.data(sid)
	if spec.is_empty():
		return false
	family = spec["family"]
	cls = spec["cls"]
	mech = spec["mech"]
	vis = float(spec.get("vis", 1.0))
	max_hp = float(spec["hp"]) * Difficulty.mult("hp")
	hp = max_hp
	radius = float(spec["r"]) * vis
	mat = AlienKit.material(spec["glow"], 0.5 if String(spec.get("model", "")) != "" else 0.4)
	mat.set_shader_parameter(&"body_h", maxf(float(spec.get("hy", 1.6)) * vis, 1.4))
	var model_id := String(spec.get("model", ""))
	if model_id != "":
		var ps := AlienKit.scene(sid)
		if ps == null:
			return false
		model = ps.instantiate() as Node3D
		add_child(model)
		for n in model.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			mi.material_override = mat
			mi.extra_cull_margin = 2.0
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh = mi
		var found := model.find_children("*", "AnimationPlayer", true, false)
		if not found.is_empty():
			ap = found[0] as AnimationPlayer
		model.scale = Vector3.ONE * vis
		shapes = [[Vector3(0.0, float(spec["cy"]), 0.0), float(spec["r"]), false]]
		if float(spec["hr"]) > 0.0:
			shapes.append([Vector3(0.0, float(spec["hy"]), -0.1), float(spec["hr"]), true])
	else:
		var pm := AlienKit.proc_mesh(StringName(spec["proc"]))
		if pm == null:
			return false
		mesh = MeshInstance3D.new()
		mesh.mesh = pm
		mesh.material_override = mat
		mesh.extra_cull_margin = 4.0
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.scale = Vector3.ONE * vis
		add_child(mesh)
		model = mesh
		match StringName(spec["proc"]):
			&"worm":
				mat.set_shader_parameter(&"wiggle", 0.35)
				mat.set_shader_parameter(&"wiggle_rate", 3.2)
				shapes = [[Vector3(0.0, 2.2, 0.0), 1.55, false], [Vector3(0.0, 5.5, -1.2), 1.5, false], [Vector3(0.0, 8.4, -4.4), 1.9, true]]
			&"serpent":
				mat.set_shader_parameter(&"wiggle", 0.25)
				mat.set_shader_parameter(&"wiggle_rate", 4.0)
				shapes = [[Vector3(0.0, 1.8, 0.0), 0.8, false], [Vector3(0.0, 4.2, -0.9), 0.8, false], [Vector3(0.0, 6.2, -3.4), 1.0, true]]
			&"tentacle":
				mat.set_shader_parameter(&"wiggle", 0.9)
				mat.set_shader_parameter(&"wiggle_rate", 2.2)
				shapes = [[Vector3(0.0, 2.2, -0.3), 1.0, false], [Vector3(0.0, 6.2, -1.4), 0.9, false], [Vector3(0.0, 9.0, -4.2), 0.8, true]]
			&"kraken":
				shapes = [[Vector3(0.0, 1.8, 0.6), 3.4, false], [Vector3(0.0, 2.2, -3.2), 1.9, true]]
			_:
				shapes = [[Vector3(0.0, float(spec["cy"]), 0.0), float(spec["r"]), false]]
	if cls == AlienSpecies.BURROW or cls == AlienSpecies.WATER and id != &"deep_kraken":
		set_exposed(false)
		rise = 0.0
	phase = randf() * TAU
	slot = randf() * TAU
	_voice_t = randf_range(2.0, 7.0)
	add_to_group(&"alien")
	if exposed:
		add_to_group(&"enemy")
	return true


# --- the enemy contract (weapons, blasts, verbs, aim assist, minimap) ----------------------------------------------------------------------------------

func center() -> Vector3:
	if shapes.is_empty():
		return global_position + Vector3(0.0, 1.0, 0.0)
	return global_position + _to_world((shapes[0] as Array)[0] as Vector3)


func body_box() -> Array:
	var c := center()
	return [c - Vector3(0.0, radius, 0.0), c + Vector3(0.0, radius, 0.0), radius]


func _to_world(local: Vector3) -> Vector3:
	return Basis(Vector3.UP, heading) * (local * vis) + Vector3(0.0, -(1.0 - rise) * _bury_depth(), 0.0)


func _bury_depth() -> float:
	return float(spec.get("rise", 4.0)) * vis if cls == AlienSpecies.BURROW or cls == AlienSpecies.WATER else 0.0


## The nearest hit of a ray on the body shapes: {t, zone, point}, {} for a miss (a buried or submerged body cannot be hit).
func hit_ray(o: Vector3, d: Vector3) -> Dictionary:
	if dead or not active or not exposed:
		return {}
	var best := INF
	var zone: StringName = HitZones.BODY
	for s: Array in shapes:
		var c := global_position + _to_world(s[0] as Vector3)
		var r := float(s[1]) * vis
		var t := PlayerUtil.ray_sphere(o, d, c, r)
		if t < best:
			best = t
			zone = HitZones.HEAD if bool(s[2]) else HitZones.BODY
	if best == INF:
		return {}
	return {"t": best, "zone": zone, "point": o + d * best}


## Burrowed and submerged bodies leave the `enemy` group (no aim assist, no minimap dot, no blast damage, no bracket) and join it again when they rise.
func set_exposed(v: bool) -> void:
	exposed = v
	if dead:
		return
	if v and not is_in_group(&"enemy"):
		add_to_group(&"enemy")
	elif not v and is_in_group(&"enemy"):
		remove_from_group(&"enemy")


func is_hittable() -> bool:
	return not dead and active and exposed


func stagger(power: float) -> void:
	if dead or family == AlienSpecies.BOSS or mech == &"nest" or mech == &"turret" or mech == &"relay":
		return
	_stun = maxf(_stun, 0.12 + 0.2 * power)
	_hurt_flinch = 0.25
	if ap != null and ap.has_animation(&"hit") and state != &"leap":
		_clip = &""
		ap.play(&"hit", 0.05)


func disable(seconds: float) -> void:
	if dead or family == AlienSpecies.BOSS:
		seconds *= 0.3
	_off = maxf(_off, seconds)


func is_disabled() -> bool:
	return _off > 0.0


## The damage contract of every enemy: `crit` only changes the effect, the amount is already scaled by the weapon.
func damage(amount: float, crit := false, _mirrored := false) -> void:
	if dead or not active or amount <= 0.0:
		return
	if not exposed:
		return
	if _shield > 0.0:
		amount *= 0.12
		Sfx.play_at(&"ricochet", center(), -6.0)
		if world != null and world.fx != null:
			world.fx.spark(center(), Color(0.4, 0.9, 1.0))
	hp -= amount
	_pulse = 1.0
	if not aggro:
		_wake()
	_on_hurt(amount, crit)
	Sfx.play_at(&"hit", center(), -5.0)
	if hp <= 0.0:
		die()


## Hook for subclasses (the bosses react to phases).
func _on_hurt(_amount: float, _crit: bool) -> void:
	if mech == &"nest":
		_on_nest_hurt()
	if world != null:
		world.note_hit(self)


func _wake() -> void:
	aggro = true
	if not group.is_empty():
		for m: AlienCreature in (group.get("members", []) as Array):
			if is_instance_valid(m) and m != self and not m.dead and not m.aggro:
				m.aggro = true
	if world != null:
		world.alert_site(site, self)


## Death: a colourful blast, an alien puddle, the dissolve into quantum dust, the loot and the bounty. Idempotent.
func die(hero_kill := true) -> void:
	if dead:
		return
	dead = true
	by_hero = hero_kill
	hp = minf(hp, 0.0)
	_dead_t = 0.0
	state = &"dying"
	vel = Vector3.ZERO
	set_exposed(true)
	if is_in_group(&"enemy"):
		remove_from_group(&"enemy")
	var c: Color = spec["glow"]
	var pos := center()
	var big := maxf(1.2, radius * 1.4)
	if mech != &"burst":
		FX.blast(pos, big * 1.6, c, 0.35, -1, 0.0, Game.quality < 2)
	if FX.qvfx != null:
		FX.qvfx.death_dust(pos, 1.5 * maxf(0.85, radius), 0.45 * maxf(0.85, radius), c)
	if FX.marks != null and mech != &"burst" and StringName(get(&"camp") if get(&"camp") != null else &"") != &"merc":
		var g: Vector3 = FX.marks.ground_under(pos, 6.0)
		if g != Vector3.INF:
			FX.marks.splat(g, Vector3.UP, 1.3 * maxf(0.85, radius) + randf() * 0.5, c.lerp(Color(0.5, 1.0, 0.2), 0.5))
	if hero_kill and Game.graphic_violence:
		FX.burst(pos, Color(0.5, 1.0, 0.2), int(14.0 * minf(big, 3.0)), 6.0, 0.9, 12.0, 2.4)
	if ap != null and ap.has_animation(&"dead"):
		ap.play(&"dead", 0.08)
	if String(spec.get("voice", "")) != "":
		Sfx.bark(&"yelp", pos, randf_range(0.6, 0.9) if big > 1.5 else randf_range(1.0, 1.3), -2.0)
	if hero_kill:
		Game.score += int(spec["score"])
		SkillTree.add_xp(SkillTree.kill_xp(int(spec["score"])))
		Crafting.on_kill(int(spec["score"]), family == AlienSpecies.BOSS)
	if world != null:
		world.on_died(self, hero_kill)
	died.emit(self)


func _tick_dead(dt: float) -> void:
	_dead_t += dt
	var k := clampf((_dead_t - 0.55) / (DEATH_TIME - 0.55), 0.0, 1.0)
	if mat != null:
		mat.set_shader_parameter(&"dissolve", k)
		mat.set_shader_parameter(&"pulse", 0.0)
	if mech == &"nest" or mech == &"relay" or mech == &"turret" or (cls == AlienSpecies.BURROW or cls == AlienSpecies.WATER):
		position.y -= dt * 0.9 * vis if mech != &"turret" else 0.0
	if _dead_t >= DEATH_TIME:
		active = false
		visible = false


func is_gone() -> bool:
	return dead and _dead_t >= DEATH_TIME


# --- the simulation ------------------------------------------------------------------------------------------------------------------------------

func hero_pos() -> Vector3:
	return world.hero_pos if world != null else Vector3.INF


func flat_dist() -> float:
	var h := hero_pos()
	if not h.is_finite():
		return INF
	return Vector2(h.x - global_position.x, h.z - global_position.z).length()


func _aggr_k() -> float:
	return 1.0 / maxf(Difficulty.mult("aggr"), 0.4)


func tick(dt: float) -> void:
	if dead:
		_tick_dead(dt)
		return
	if not active:
		return
	st_t += dt
	cool = maxf(0.0, cool - dt)
	_pulse = maxf(0.0, _pulse - dt * 5.0)
	_stun = maxf(0.0, _stun - dt)
	_off = maxf(0.0, _off - dt)
	_hurt_flinch = maxf(0.0, _hurt_flinch - dt)
	_voice_t -= dt
	_refresh_ground(dt)
	if _off > 0.0 or (_stun > 0.0 and state != &"leap" and state != &"dive"):
		_hold_pose(dt)
		_apply()
		return
	var d := flat_dist()
	if world == null or not world.hero_pos.is_finite():
		d = INF
	match mech:
		&"leap": _tick_leap(dt, d)
		&"melee": _tick_melee(dt, d)
		&"burst": _tick_burst(dt, d)
		&"spit": _tick_spit(dt, d)
		&"slam": _tick_slam(dt, d)
		&"ambush": _tick_ambush(dt, d)
		&"swoop": _tick_swoop(dt, d)
		&"float": _tick_float(dt, d)
		&"turret": _tick_turret(dt, d)
		&"nest": _tick_nest(dt, d)
		&"relay": _tick_relay(dt, d)
		&"burrow": _tick_burrow(dt, d)
		&"serpent": _tick_serpent(dt, d)
		_: _tick_extra(dt, d)
	if _voice_t <= 0.0:
		_voice_t = randf_range(4.0, 9.0)
		_voice()
	_apply()


## Subclasses (the bosses) add their own mechanics here.
func _tick_extra(_dt: float, _d: float) -> void:
	pass


func _voice() -> void:
	var v := StringName(spec.get("voice", ""))
	if v == &"" or not aggro or flat_dist() > 60.0:
		return
	Sfx.bark(v, global_position, randf_range(0.55, 0.75) if radius > 1.2 else randf_range(0.95, 1.25), -6.0)


func _refresh_ground(dt: float) -> void:
	_gy_t -= dt
	if _gy_t > 0.0:
		return
	_gy_t = 0.08
	ground = TerrainHeight.height_at(position.x, position.z)
	water_y = TerrainHeight.water_level_for(position.x, position.z, ground)


func _hold_pose(dt: float) -> void:
	vel = vel.move_toward(Vector3.ZERO, 30.0 * dt)
	if cls == AlienSpecies.GROUND:
		_play(&"idle", 1.0)


func _sees(d: float) -> bool:
	if world == null or not world.hero_alive():
		return false
	var sight := float(spec["sight"])
	if aggro:
		sight *= 1.6
	return d <= sight


func _lost(d: float) -> bool:
	return world == null or not world.hero_alive() or d > float(spec["sight"]) * 2.3 or (site != &"" and Vector2(global_position.x - home.x, global_position.z - home.z).length() > leash)


func _go(s: StringName) -> void:
	state = s
	st_t = 0.0


func _face(to: Vector2, dt: float, rate := TURN) -> float:
	var d := to - Vector2(position.x, position.z)
	if d.length() < 0.05:
		return 0.0
	var want := atan2(-d.x, -d.y)
	var diff := wrapf(want - heading, -PI, PI)
	heading = lerp_angle(heading, want, clampf(rate * dt, 0.0, 1.0))
	return diff


## Walks toward `to` (xz) at `speed`: turns first, refuses steep ground and deep water (turns aside), returns the metres moved.
func _steer(to: Vector2, speed: float, dt: float) -> float:
	var diff := _face(to, dt)
	var turn_slow := clampf(1.0 - absf(diff) / 2.2, 0.15, 1.0)
	var step := speed * turn_slow * dt
	var fwd := Vector2(-sin(heading), -cos(heading))
	var nx := position.x + fwd.x * step
	var nz := position.z + fwd.y * step
	var ny := TerrainHeight.height_at(nx, nz)
	var w := TerrainHeight.water_level_for(nx, nz, ny)
	var wet := w != TerrainHeight.NO_WATER and w - ny > 0.55
	if (ny - ground) > maxf(step * 1.7, 0.08) and step > 0.001 or wet:
		_stuck += dt
		heading += 0.9 * (1.0 if int(phase * 10.0) % 2 == 0 else -1.0) * dt * 3.0
		return 0.0
	_stuck = maxf(0.0, _stuck - dt)
	position.x = nx
	position.z = nz
	ground = ny
	return step


func _wander(dt: float) -> void:
	_wander_t -= dt
	var pos2 := Vector2(position.x, position.z)
	if _wander_t <= 0.0:
		_wander_t = randf_range(3.0, 7.0)
		var a := randf() * TAU
		_wander_to = Vector2(home.x, home.z) + Vector2(cos(a), sin(a)) * randf_range(0.0, 7.0) if site != &"" else pos2 + Vector2(cos(a), sin(a)) * randf_range(4.0, 12.0)
	if pos2.distance_to(_wander_to) > 1.2 and _wander_t > 0.4:
		_steer(_wander_to, float(spec["walk"]), dt)
		_play(&"walk", 1.0)
	else:
		_play(&"idle", 1.0)


## Pack members keep a body apart (a crowd of skitters never stacks into one point on the hero).
func _separate(dt: float) -> void:
	if group.is_empty():
		return
	for member in (group.get("members", []) as Array):
		# the loop variable is NOT typed: assigning a freed pack member to a typed variable is itself a script error (1198 of them in an 8 minute soak)
		if member == self or not is_instance_valid(member):
			continue
		var m := member as AlienCreature
		if m == null or m.dead:
			continue
		var d := Vector2(position.x - m.position.x, position.z - m.position.z)
		var l := d.length()
		if l < 1.3:
			var push := (d / maxf(l, 0.05)) * (1.3 - l) * 3.0 * dt if l > 0.01 else Vector2(randf() - 0.5, randf() - 0.5) * dt
			position.x += push.x
			position.z += push.y


func _hero2() -> Vector2:
	var h := hero_pos()
	return Vector2(h.x, h.z)


func _hero_airborne() -> bool:
	var h := hero_pos()
	return h.y - TerrainHeight.height_at(h.x, h.z) > 1.7 + 0.9


func _hurt_hero(amount: float, at := Vector3.ZERO) -> bool:
	if world == null:
		return false
	var ok := world.hurt_hero(amount, global_position if at == Vector3.ZERO else at, self)
	if ok:
		hits_landed += 1
	return ok


func _melee_hit(extra_reach := 0.9, cone := 1.3) -> bool:
	var h := hero_pos()
	var to := Vector2(h.x - global_position.x, h.z - global_position.z)
	if to.length() > float(spec["reach"]) + extra_reach:
		return false
	var fwd := Vector2(-sin(heading), -cos(heading))
	if absf(wrapf(atan2(-to.x, -to.y) - heading, -PI, PI)) > cone and to.length() > 1.4:
		return false
	attacks_done += 1
	return _hurt_hero(float(spec["dmg"]))


func _play(clip: StringName, spd := 1.0) -> void:
	if ap == null:
		return
	var name := clip
	if not ap.has_animation(name):
		match clip:
			&"run": name = &"walk" if ap.has_animation(&"walk") else (&"fly" if ap.has_animation(&"fly") else &"idle")
			&"walk": name = &"fly" if ap.has_animation(&"fly") else &"idle"
			&"fly": name = &"idle"
			&"jump": name = &"run" if ap.has_animation(&"run") else &"idle"
			_: name = &"idle"
		if not ap.has_animation(name):
			return
	if _clip != name:
		_clip = name
		ap.play(name, 0.18)
	ap.speed_scale = spd


func _play_once(clip: StringName, spd := 1.0) -> void:
	if ap == null or not ap.has_animation(clip):
		return
	_clip = clip
	ap.play(clip, 0.08)
	ap.speed_scale = spd


## Position, facing, shader state of this frame.
func _apply() -> void:
	if cls == AlienSpecies.AIR:
		position.y = lerpf(position.y, maxf(ground + HOVER_MIN, ground + alt), 0.2) if state != &"dive" and state != &"landed" else position.y
	elif cls == AlienSpecies.BURROW or cls == AlienSpecies.WATER or cls == AlienSpecies.STATIC:
		var base := ground
		if cls == AlienSpecies.WATER and water_y != TerrainHeight.NO_WATER:
			base = water_y
		position.y = base - (1.0 - rise) * _bury_depth() if cls != AlienSpecies.STATIC else ground
	elif state != &"leap" and state != &"pounce":
		position.y = lerpf(position.y, ground, clampf(18.0 * get_physics_process_delta_time(), 0.0, 1.0)) if absf(position.y - ground) < 1.5 else ground
	rotation = Vector3(_pitch, heading, 0.0)
	visible = exposed or rise > 0.02
	if mat != null:
		mat.set_shader_parameter(&"pulse", maxf(_pulse, _hurt_flinch))
		mat.set_shader_parameter(&"beat", 1.0 + 0.35 * sin(Time.get_ticks_msec() * 0.012 + phase) + _beat)
		mat.set_shader_parameter(&"shield", clampf(_shield, 0.0, 1.0))


# --- leap: pack hunters ---------------------------------------------------------------------------------------------------------------------------

func _tick_leap(dt: float, d: float) -> void:
	var run := float(spec["run"])
	match state:
		&"idle":
			_wander(dt)
			if aggro or _sees(d):
				_wake()
				_go(&"chase")
		&"chase":
			if _lost(d):
				aggro = false
				_go(&"idle")
				return
			var lr: Array = spec["leap"]
			var h2 := _hero2()
			var tgt := h2
			if d > float(lr[1]) + 2.0:
				tgt = h2 + Vector2(cos(slot), sin(slot)) * clampf(d * 0.25, 1.5, 4.5)       # the pack fans out and comes in from all sides
			if d > 1.5:
				_steer(tgt, run * (1.0 if d > 6.0 else 0.8), dt)
				_play(&"run", clampf(run / 6.0, 0.8, 1.6))
			else:
				_face(h2, dt, 10.0)
				_play(&"idle", 1.0)
			_separate(dt)
			if cool <= 0.0:
				if d <= float(spec["reach"]):
					_aim2 = h2
					_pulse = 1.0
					_go(&"windup")
					_play_once(&"attack", 1.6)
				elif d <= float(lr[1]) and d >= float(lr[0]) and world != null and world.leap_gate(self):
					_aim = hero_pos()
					_go(&"crouch")
					_play(&"idle", 0.5)
		&"crouch":
			_face(Vector2(_aim.x, _aim.z), dt, 12.0)
			_pulse = clampf(st_t / (float(spec["windup"]) * _aggr_k()), 0.0, 1.0)
			if st_t >= float(spec["windup"]) * _aggr_k():
				_launch()
		&"leap":
			vel.y -= GRAVITY * dt
			position += vel * dt
			_play(&"jump", 1.0)
			var gy := TerrainHeight.height_at(position.x, position.z)
			if position.y <= gy + 0.05 and vel.y < 0.0:
				position.y = gy
				ground = gy
				var h := hero_pos()
				if Vector2(h.x - position.x, h.z - position.z).length() < 2.3 and absf(h.y - position.y) < 2.8:
					attacks_done += 1
					_hurt_hero(float(spec["dmg"]) * 1.3)
				if world != null:
					world.fx.dust(position, spec["glow"])
				cool = float(spec["cool"]) * _aggr_k() * randf_range(0.9, 1.4)
				_go(&"recover")
			elif st_t > 1.6:
				_go(&"recover")
		&"windup":
			_face(_hero2(), dt, 12.0)
			_pulse = clampf(st_t / 0.35, 0.0, 1.0)
			if st_t >= 0.35 * _aggr_k():
				_melee_hit(1.0)
				cool = float(spec["cool"]) * _aggr_k()
				_go(&"recover")
		&"recover":
			_play(&"idle", 1.0)
			if st_t >= 0.55:
				_go(&"chase")


func _launch() -> void:
	var h := hero_pos()
	var d := Vector2(h.x - position.x, h.z - position.z)
	var t := clampf(d.length() / 11.0, 0.32, 0.8)
	var lead := Vector2.ZERO
	if world != null:
		lead = world.hero_vel2 * t * 0.5
	var tgt := Vector2(h.x, h.z) + lead
	var dv0 := tgt - Vector2(position.x, position.z)
	tgt -= dv0.normalized() * minf(1.5, dv0.length() * 0.4)               # land at the hero's feet, never inside him
	var dv := tgt - Vector2(position.x, position.z)
	vel = Vector3(dv.x / t, (h.y - 0.9 - position.y) / t + 0.5 * GRAVITY * t, dv.y / t)
	heading = atan2(-dv.x, -dv.y)
	Sfx.bark(&"chitter", position, randf_range(1.0, 1.4), -4.0)
	_play_once(&"jump", 1.0)
	_go(&"leap")


# --- melee ----------------------------------------------------------------------------------------------------------------------------------------

func _tick_melee(dt: float, d: float) -> void:
	match state:
		&"idle":
			_wander(dt)
			if aggro or _sees(d):
				_wake()
				_go(&"chase")
		&"chase":
			if _lost(d):
				aggro = false
				_go(&"return")
				return
			if d > 1.4:
				_steer(_hero2(), float(spec["run"]), dt)
				_play(&"run", 1.0)
			else:
				_face(_hero2(), dt, 8.0)
			_separate(dt)
			if d <= float(spec["reach"]) and cool <= 0.0:
				_pulse = 1.0
				_go(&"windup")
				_play_once(&"attack", 0.9 / (float(spec["windup"]) * _aggr_k() + 0.2))
		&"windup":
			_face(_hero2(), dt, 8.0)
			_pulse = clampf(st_t / (float(spec["windup"]) * _aggr_k()), 0.0, 1.0)
			if st_t >= float(spec["windup"]) * _aggr_k():
				_melee_hit()
				cool = float(spec["cool"]) * _aggr_k()
				Sfx.play_at(&"trooper_attack", global_position, -8.0, 0.7)
				_go(&"recover")
		&"recover":
			if st_t >= 0.45:
				_go(&"chase")
		&"return":
			_return_home(dt)


func _return_home(dt: float) -> void:
	var to := Vector2(home.x, home.z)
	_steer(to, float(spec["walk"]) * 2.0, dt)
	_play(&"walk", 1.4)
	if Vector2(position.x, position.z).distance_to(to) < 2.5 or st_t > 12.0:
		hp = minf(max_hp, hp + max_hp * 0.4)
		_go(&"idle")


# --- burst: the spore popper ---------------------------------------------------------------------------------------------------------------------

func _tick_burst(dt: float, d: float) -> void:
	match state:
		&"idle":
			_wander(dt)
			if aggro or _sees(d):
				_wake()
				_go(&"chase")
		&"chase":
			if _lost(d):
				aggro = false
				_go(&"idle")
				return
			_steer(_hero2(), float(spec["run"]), dt)
			_play(&"walk", 2.0)
			if d <= float(spec["reach"]):
				_go(&"fuse")
				_beat = 1.0
				Sfx.bark(&"yelp", position, 1.5, -4.0)
				if world != null:
					world.fx.ring(Vector3(position.x, ground + 0.1, position.z), float(spec["reach"]) + 0.4, float(spec["windup"]) * _aggr_k(), Color(0.95, 1.0, 0.2))
		&"fuse":
			_pulse = 0.5 + 0.5 * sin(st_t * 30.0)
			scale = Vector3.ONE * (1.0 + 0.5 * clampf(st_t / (float(spec["windup"]) * _aggr_k()), 0.0, 1.0))
			_play(&"idle", 2.0)
			if st_t >= float(spec["windup"]) * _aggr_k():
				_burst_now(true)


func _burst_now(hurts := true) -> void:
	if dead:
		return
	var c := Vector3(position.x, ground + 0.6, position.z)
	var r := float(spec["reach"]) + 0.4
	if hurts and world != null:
		var h := hero_pos()
		if h.distance_to(c) <= r + 0.6:
			attacks_done += 1
			_hurt_hero(float(spec["dmg"]))
		world.spore_cloud(c, r * 0.9, 3.2)
	FX.blast(c, r * 0.9, Color(0.95, 1.0, 0.2), 0.4, -1, 0.0, false)
	FX.shake(0.15)
	Sfx.play_at(&"explosion_small", c, -4.0, 1.2)
	scale = Vector3.ONE
	die(false)


# --- spit: acid spitters --------------------------------------------------------------------------------------------------------------------------

func _tick_spit(dt: float, d: float) -> void:
	var keep: Array = spec["keep"]
	match state:
		&"idle":
			_wander(dt)
			if aggro or _sees(d):
				_wake()
				_go(&"chase")
		&"chase":
			if _lost(d):
				aggro = false
				_go(&"return")
				return
			var h2 := _hero2()
			if d > float(keep[1]):
				_steer(h2, float(spec["run"]), dt)
				_play(&"run", 1.0)
			elif d < float(keep[0]):
				var away := Vector2(position.x, position.z) + (Vector2(position.x, position.z) - h2).normalized() * 6.0
				_steer(away, float(spec["run"]) * 0.8, dt)
				_play(&"walk", 1.5)
			else:
				_face(h2, dt, 5.0)
				var side := Vector2(position.x, position.z) + (h2 - Vector2(position.x, position.z)).orthogonal().normalized() * (4.0 if int(phase * 3.0) % 2 == 0 else -4.0)
				_steer(side, float(spec["walk"]), dt)
				_play(&"walk", 1.0)
			if cool <= 0.0 and d <= float(spec["reach"]) and d > 4.0:
				_aim = hero_pos() + Vector3(0.0, 0.1, 0.0)
				_pulse = 1.0
				_go(&"windup")
				_play_once(&"attack", 1.1)
		&"windup":
			_face(Vector2(_aim.x, _aim.z), dt, 10.0)
			_aim = _aim.lerp(hero_pos(), 0.04)                                            # the aim follows the hero a little, then it is fixed
			_pulse = clampf(st_t / (float(spec["windup"]) * _aggr_k()), 0.0, 1.0)
			if st_t >= float(spec["windup"]) * _aggr_k():
				var from := global_position + Basis(Vector3.UP, heading) * Vector3(0.0, 1.3 * vis, -0.7)
				if world != null:
					world.shoot(from, (_aim - from).normalized(), 17.0, float(spec["dmg"]), 0.9, Color(0.75, 1.0, 0.15), 0.9, self)
				attacks_done += 1
				cool = float(spec["cool"]) * _aggr_k()
				Sfx.play_at(&"enemy_shot", from, -6.0, 0.6)
				_go(&"recover")
		&"recover":
			if st_t >= 0.5:
				_go(&"chase")
		&"return":
			_return_home(dt)


# --- slam: the crag brute -------------------------------------------------------------------------------------------------------------------------

func _tick_slam(dt: float, d: float) -> void:
	var sr := float(spec.get("slam_r", 5.0))
	match state:
		&"idle":
			_wander(dt)
			if aggro or _sees(d):
				_wake()
				_go(&"chase")
		&"chase":
			if _lost(d):
				aggro = false
				_go(&"return")
				return
			_steer(_hero2(), float(spec["run"]), dt)
			_play(&"run", 0.8)
			if d <= float(spec["reach"]) + 1.0 and cool <= 0.0:
				_go(&"windup")
				_pulse = 1.0
				_play_once(&"attack", 0.8)
				if world != null:
					world.fx.ring(Vector3(position.x, ground + 0.1, position.z), sr, float(spec["windup"]) * _aggr_k(), Color(1.0, 0.45, 0.2))
		&"windup":
			_face(_hero2(), dt, 3.0)
			_pulse = clampf(st_t / (float(spec["windup"]) * _aggr_k()), 0.0, 1.0)
			if st_t >= float(spec["windup"]) * _aggr_k():
				_slam_now(sr)
				cool = float(spec["cool"]) * _aggr_k()
				_go(&"recover")
		&"recover":
			if st_t >= 0.7:
				_go(&"chase")
		&"return":
			_return_home(dt)


func _slam_now(sr: float) -> void:
	var c := Vector3(position.x, ground, position.z)
	FX.blast(c + Vector3(0.0, 0.3, 0.0), sr * 0.55, Color(1.0, 0.55, 0.25), 0.4, -1, 0.0, false)
	FX.shake(0.4)
	Sfx.play_at(&"verb_slam", c, -2.0, 0.7)
	if world != null:
		world.fx.dust(c, Color(0.8, 0.7, 0.55))
		var h := hero_pos()
		var flat := Vector2(h.x - c.x, h.z - c.z).length()
		if flat <= sr and not _hero_airborne():                           # a jump clears the wave
			attacks_done += 1
			_hurt_hero(float(spec["dmg"]))
			world.knock_hero(Vector3(h.x - c.x, 0.0, h.z - c.z).normalized() * 9.0 + Vector3.UP * 5.0)


# --- ambush: the shade stalker --------------------------------------------------------------------------------------------------------------------

func _tick_ambush(dt: float, d: float) -> void:
	var pr: Array = spec["pounce"]
	var cloak := 0.0
	match state:
		&"idle":
			_wander(dt)
			cloak = 0.5
			if aggro or _sees(d):
				_wake()
				_go(&"chase")
		&"chase":
			cloak = 0.85 if d > 9.0 else 0.6
			if _lost(d):
				aggro = false
				_go(&"idle")
				return
			var h2 := _hero2()
			_steer(h2 + Vector2(cos(slot), sin(slot)) * clampf(d * 0.2, 1.0, 3.0), float(spec["run"]) * 0.75, dt)
			_play(&"walk", 2.0)
			if cool <= 0.0 and d <= float(pr[1]) and d >= float(pr[0]) and (world == null or world.leap_gate(self)):
				_aim = hero_pos()
				_go(&"crouch")
		&"crouch":
			cloak = lerpf(0.6, 0.1, clampf(st_t / (float(spec["windup"]) * _aggr_k()), 0.0, 1.0))
			_face(Vector2(_aim.x, _aim.z), dt, 12.0)
			_pulse = clampf(st_t / (float(spec["windup"]) * _aggr_k()), 0.0, 1.0)
			if st_t >= float(spec["windup"]) * _aggr_k():
				_launch()
				state = &"leap"
		&"leap":
			cloak = 0.1
			vel.y -= GRAVITY * dt
			position += vel * dt
			var gy := TerrainHeight.height_at(position.x, position.z)
			if position.y <= gy + 0.05 and vel.y < 0.0:
				position.y = gy
				ground = gy
				var h := hero_pos()
				if Vector2(h.x - position.x, h.z - position.z).length() < 2.4 and absf(h.y - position.y) < 2.8:
					attacks_done += 1
					_hurt_hero(float(spec["dmg"]))
				cool = float(spec["cool"]) * _aggr_k()
				_go(&"retreat")
			elif st_t > 1.4:
				_go(&"retreat")
		&"retreat":
			cloak = lerpf(0.1, 0.8, clampf(st_t / 1.0, 0.0, 1.0))
			var away := Vector2(position.x, position.z) + (Vector2(position.x, position.z) - _hero2()).normalized() * 8.0
			_steer(away, float(spec["run"]), dt)
			_play(&"run", 1.2)
			if st_t >= 1.6:
				_go(&"chase")
	if _hurt_flinch > 0.0:
		cloak = 0.0
	if mat != null:
		mat.set_shader_parameter(&"cloak", cloak)


# --- swoop: swarmers ------------------------------------------------------------------------------------------------------------------------------

func _tick_swoop(dt: float, d: float) -> void:
	var al: Array = spec["alt"]
	match state:
		&"idle":
			alt = lerpf(alt, 5.0, dt)
			position.x += sin(phase + st_t * 0.4) * 1.2 * dt
			position.z += cos(phase + st_t * 0.35) * 1.2 * dt
			_play(&"fly", 1.0)
			if aggro or _sees(d):
				_wake()
				_go(&"circle")
		&"circle":
			if world == null or not world.hero_alive() or d > float(spec["sight"]) * 2.2:
				aggro = false
				_go(&"idle")
				return
			phase += dt * (1.4 + float(spec["run"]) * 0.02) * (1.0 if orb > 0.0 else -1.0)
			var h := hero_pos()
			var want := Vector3(h.x + cos(phase) * absf(orb), 0.0, h.z + sin(phase) * absf(orb))
			var tgt_alt := (h.y - ground) + float(al[0]) + 0.5 * (float(al[1]) - float(al[0])) * (0.5 + 0.5 * sin(phase * 2.0 + slot))
			alt = lerpf(alt, tgt_alt, clampf(3.0 * dt, 0.0, 1.0))
			var dir := Vector2(want.x - position.x, want.z - position.z)
			var sp := float(spec["run"]) * 0.7
			var mv := dir.normalized() * minf(dir.length(), sp * dt * 1.6)
			position.x += mv.x
			position.z += mv.y
			heading = lerp_angle(heading, atan2(-dir.x, -dir.y), clampf(6.0 * dt, 0.0, 1.0))
			_play(&"fly", 1.6)
			if cool <= 0.0 and d < 18.0 and world != null and world.leap_gate(self):
				_aim = hero_pos()
				_go(&"hover")
		&"hover":
			var h2 := hero_pos()
			_face(Vector2(h2.x, h2.z), dt, 12.0)
			_pulse = clampf(st_t / (float(spec["windup"]) * _aggr_k()), 0.0, 1.0)
			_pitch = lerpf(_pitch, 0.5, dt * 6.0)
			if st_t >= float(spec["windup"]) * _aggr_k():
				_aim = hero_pos() + Vector3(0.0, 0.2, 0.0)
				vel = (_aim - global_position).normalized() * float(spec["run"])
				_go(&"dive")
		&"dive":
			position += vel * dt
			alt = position.y - ground
			heading = atan2(-vel.x, -vel.z)
			_pitch = lerpf(_pitch, atan2(-vel.y, Vector2(vel.x, vel.z).length()) * -1.0, dt * 10.0)
			var h3 := hero_pos()
			if global_position.distance_to(h3 + Vector3(0.0, 0.2, 0.0)) < 1.5:
				attacks_done += 1
				_hurt_hero(float(spec["dmg"]))
				cool = float(spec["cool"]) * _aggr_k() * randf_range(1.0, 1.8)
				_go(&"climb")
			elif st_t > 1.3 or position.y < TerrainHeight.height_at(position.x, position.z) + 0.6:
				cool = float(spec["cool"]) * _aggr_k()
				_go(&"climb")
		&"climb":
			_pitch = lerpf(_pitch, -0.5, dt * 5.0)
			var gy2 := TerrainHeight.height_at(position.x, position.z)
			ground = gy2
			position.y += 7.0 * dt
			alt = position.y - gy2
			position.x += -sin(heading) * 6.0 * dt
			position.z += -cos(heading) * 6.0 * dt
			if st_t >= 0.9:
				_pitch = 0.0
				_go(&"circle")
	if state != &"dive" and state != &"hover":
		_pitch = lerpf(_pitch, 0.0, clampf(6.0 * dt, 0.0, 1.0))


# --- float: drift rays ----------------------------------------------------------------------------------------------------------------------------

func _tick_float(dt: float, d: float) -> void:
	var al: Array = spec["alt"]
	var base := ground if water_y == TerrainHeight.NO_WATER else maxf(ground, water_y)
	alt = (base - ground) + float(al[0]) + 1.5 + sin(Time.get_ticks_msec() * 0.0015 + phase) * 0.8
	_play(&"fly", 0.6)
	match state:
		&"idle":
			position.x += sin(phase + st_t * 0.3) * 0.8 * dt
			position.z += cos(phase + st_t * 0.27) * 0.8 * dt
			if aggro or _sees(d):
				_wake()
				_go(&"chase")
		&"chase":
			if world == null or not world.hero_alive() or d > float(spec["sight"]) * 2.4:
				aggro = false
				_go(&"idle")
				return
			var h2 := _hero2()
			var want := 17.0
			if d > want + 3.0:
				_steer(h2, float(spec["run"]), dt)
			elif d < want - 5.0:
				_steer(Vector2(position.x, position.z) + (Vector2(position.x, position.z) - h2).normalized() * 6.0, float(spec["walk"]), dt)
			else:
				_face(h2, dt, 3.0)
			if cool <= 0.0 and d <= float(spec["shot"]) + 6.0 and d > 5.0:
				_pulse = 1.0
				_aim = hero_pos()
				_go(&"windup")
		&"windup":
			_face(Vector2(_aim.x, _aim.z), dt, 8.0)
			_pulse = clampf(st_t / (float(spec["windup"]) * _aggr_k()), 0.0, 1.0)
			if st_t >= float(spec["windup"]) * _aggr_k():
				var from := global_position + Vector3(0.0, -0.3, 0.0)
				if world != null:
					world.shoot(from, (hero_pos() - from).normalized(), 19.0, float(spec["dmg"]), 0.8, Color(0.3, 1.0, 0.95), 0.9, self)
				attacks_done += 1
				cool = float(spec["cool"]) * _aggr_k()
				Sfx.play_at(&"shot_arc", from, -8.0, 1.3)
				_go(&"chase")


# --- turret: the spore sentry ---------------------------------------------------------------------------------------------------------------------

func _tick_turret(dt: float, d: float) -> void:
	_pulse = maxf(_pulse, 0.0)
	match state:
		&"idle":
			if aggro or _sees(d):
				_wake()
				_go(&"track")
		&"track":
			if world == null or not world.hero_alive() or d > float(spec["reach"]) * 1.8:
				aggro = false
				_go(&"idle")
				return
			_face(_hero2(), dt, 5.0)
			if cool <= 0.0 and d <= float(spec["reach"]) and world.sentry_gate(self):
				_aim = hero_pos()
				_go(&"windup")
				if world != null:
					world.fx.line(global_position + Vector3(0.0, 2.1, 0.0), _aim, float(spec["windup"]) * _aggr_k(), Color(0.85, 1.0, 0.2))
		&"windup":
			_face(Vector2(_aim.x, _aim.z), dt, 6.0)
			_pulse = clampf(st_t / (float(spec["windup"]) * _aggr_k()), 0.0, 1.0)
			if st_t >= float(spec["windup"]) * _aggr_k():
				_go(&"fire")
		&"fire":
			var shots := int(st_t / 0.22)
			if shots > int((st_t - dt) / 0.22) or st_t < dt + 0.001:
				var from := global_position + Basis(Vector3.UP, heading) * Vector3(0.0, 2.1, -0.9)
				var at := hero_pos() + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
				if world != null:
					world.shoot(from, (at - from).normalized(), 26.0, float(spec["dmg"]), 0.6, Color(0.85, 1.0, 0.2), 0.6, self)
				attacks_done += 1
				Sfx.play_at(&"enemy_shot", from, -7.0, 0.8)
			if st_t >= 0.5:
				cool = float(spec["cool"]) * _aggr_k()
				_go(&"track")


# --- nest: the hive heart -------------------------------------------------------------------------------------------------------------------------

func _tick_nest(dt: float, d: float) -> void:
	_beat = 0.4 * sin(Time.get_ticks_msec() * 0.006) + (0.6 if state == &"hatch" else 0.0)
	scale = Vector3.ONE * (1.0 + 0.025 * sin(Time.get_ticks_msec() * 0.007))
	_hatch_t -= dt
	if d < 95.0 and world != null and world.hero_alive() and _hatch_t <= 0.0:
		_hatch_t = (9.0 + randf() * 4.0) * _aggr_k()
		world.hatch(self, 2 if Game.quality == 0 else 3)
		_go(&"hatch")
	if state == &"hatch" and st_t > 0.8:
		_go(&"idle")


func _on_nest_hurt() -> void:
	if world != null and randf() < 0.18:
		_hatch_t = 0.1


# --- relay: shield relays -------------------------------------------------------------------------------------------------------------------------

func _tick_relay(_dt: float, _d: float) -> void:
	_beat = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008 + phase)


# --- burrow: the dune maw -------------------------------------------------------------------------------------------------------------------------

func _tick_burrow(dt: float, d: float) -> void:
	match state:
		&"idle":
			set_exposed(false)
			rise = 0.0
			_burrow_t -= dt
			if (aggro or _sees(d)) and _burrow_t <= 0.0:
				_wake()
				_go(&"travel")
		&"travel":
			set_exposed(false)
			rise = 0.0
			if world == null or not world.hero_alive() or d > float(spec["sight"]) * 2.2:
				aggro = false
				_go(&"idle")
				return
			var step := _steer_burrow(_hero2(), float(spec["run"]), dt)
			_burrow_trail(dt)
			if d <= 17.0 and cool <= 0.0 and step >= 0.0:
				_aim = hero_pos()
				var rp := Vector3(_aim.x, TerrainHeight.height_at(_aim.x, _aim.z), _aim.z)
				_aim = rp
				if world != null:
					world.fx.ring(rp + Vector3(0.0, 0.15, 0.0), float(spec["reach"]), float(spec["windup"]) * _aggr_k(), Color(1.0, 0.5, 0.15))
					world.fx.dust(rp, Color(0.85, 0.7, 0.5))
				Sfx.play_at(&"verb_slam", rp, -6.0, 0.5)
				_go(&"telegraph")
		&"telegraph":
			set_exposed(false)
			rise = 0.0
			FX.shake(0.04)
			var t := st_t / (float(spec["windup"]) * _aggr_k())
			if int(st_t * 8.0) != int((st_t - dt) * 8.0) and world != null:
				world.fx.dust(_aim, Color(0.85, 0.7, 0.5))
			if t >= 1.0:
				position.x = _aim.x
				position.z = _aim.z
				ground = _aim.y
				heading = atan2(-(hero_pos().x - _aim.x), -(hero_pos().z - _aim.z))
				set_exposed(true)
				_go(&"erupt")
				_erupt_hit()
		&"erupt":
			rise = clampf(st_t / 0.45, 0.0, 1.0)
			rise = 1.0 - pow(1.0 - rise, 3.0)
			_face(_hero2(), dt, 3.0)
			if st_t >= 0.5:
				_go(&"exposed")
		&"exposed":
			rise = 1.0
			set_exposed(true)
			_face(_hero2(), dt, 2.5)
			if st_t >= 2.4 + 0.0 and cool <= 0.0 and d <= float(spec["reach"]) + 7.0:
				_aim = hero_pos()
				_go(&"lunge_wind")
				if world != null:
					world.fx.line(global_position + Vector3(0.0, 7.0 * vis, 0.0), _aim, 0.7 * _aggr_k(), Color(1.0, 0.4, 0.1))
			elif st_t >= 6.5:
				_go(&"sink")
		&"lunge_wind":
			_face(Vector2(_aim.x, _aim.z), dt, 5.0)
			_pulse = clampf(st_t / (0.7 * _aggr_k()), 0.0, 1.0)
			if st_t >= 0.7 * _aggr_k():
				var h := hero_pos()
				var head := global_position + Basis(Vector3.UP, heading) * Vector3(0.0, 8.0 * vis, -4.4 * vis)
				if head.distance_to(_aim) < 1.0 or Vector2(h.x - _aim.x, h.z - _aim.z).length() < 3.2:
					if Vector2(h.x - global_position.x, h.z - global_position.z).length() < float(spec["reach"]) + 7.0:
						attacks_done += 1
						_hurt_hero(float(spec["dmg"]))
				if world != null:
					world.fx.dust(Vector3(_aim.x, ground, _aim.z), Color(0.85, 0.7, 0.5))
				FX.shake(0.25)
				Sfx.bark(&"growl", global_position, 0.5, -2.0)
				cool = float(spec["cool"]) * _aggr_k()
				_go(&"exposed")
				st_t = 3.6
		&"sink":
			rise = clampf(1.0 - st_t / 0.8, 0.0, 1.0)
			if st_t >= 0.8:
				set_exposed(false)
				rise = 0.0
				_burrow_t = float(spec["cool"]) * _aggr_k() * 0.5
				cool = float(spec["cool"]) * _aggr_k() * 0.6
				_go(&"travel")
	if state != &"erupt" and state != &"exposed" and state != &"lunge_wind":
		visible = rise > 0.02


## Underground travel: no slope or water check (the sand is deep), the heading is the pursuit line. Returns the metres moved.
func _steer_burrow(to: Vector2, speed: float, dt: float) -> float:
	var d := to - Vector2(position.x, position.z)
	if d.length() < 0.5:
		return 0.0
	heading = lerp_angle(heading, atan2(-d.x, -d.y), clampf(5.0 * dt, 0.0, 1.0))
	var fwd := Vector2(-sin(heading), -cos(heading))
	var step := speed * dt
	var nx := position.x + fwd.x * step
	var nz := position.z + fwd.y * step
	var ny := TerrainHeight.height_at(nx, nz)
	var w := TerrainHeight.water_level_for(nx, nz, ny)
	if w != TerrainHeight.NO_WATER and w - ny > 0.4:
		heading += dt * 3.0
		return 0.0
	position.x = nx
	position.z = nz
	ground = ny
	return step


func _burrow_trail(dt: float) -> void:
	_gy_t = minf(_gy_t, 0.0)
	if world == null:
		return
	if int(st_t * 4.0) != int((st_t - dt) * 4.0):
		world.fx.dust(Vector3(position.x, ground, position.z), Color(0.85, 0.7, 0.5))
		FX.shake(0.03)
	if int(st_t * 1.5) != int((st_t - dt) * 1.5):
		world.fx.ring(Vector3(position.x, ground + 0.1, position.z), 2.6, 0.7, Color(0.9, 0.7, 0.4))


func _erupt_hit() -> void:
	var h := hero_pos()
	var rp := Vector3(position.x, ground, position.z)
	if world != null:
		world.fx.dust(rp, Color(0.9, 0.75, 0.5))
		world.fx.dust(rp + Vector3(0.0, 1.0, 0.0), Color(0.9, 0.75, 0.5))
	FX.blast(rp + Vector3(0.0, 0.5, 0.0), float(spec["reach"]) * 0.7, Color(1.0, 0.6, 0.2), 0.4, -1, 0.0, false)
	FX.shake(0.5)
	Sfx.play_at(&"boom", rp, -3.0, 0.7)
	Sfx.bark(&"growl", rp, 0.45, -1.0)
	if Vector2(h.x - rp.x, h.z - rp.z).length() < float(spec["reach"]):
		attacks_done += 1
		_hurt_hero(float(spec["dmg"]))
		if world != null:
			world.knock_hero(Vector3(h.x - rp.x, 0.0, h.z - rp.z).normalized() * 7.0 + Vector3.UP * 9.0)


# --- serpent: the reef lurker ----------------------------------------------------------------------------------------------------------------------

func _tick_serpent(dt: float, d: float) -> void:
	var on_water := water_y != TerrainHeight.NO_WATER
	match state:
		&"idle":
			set_exposed(false)
			rise = 0.0
			_burrow_t -= dt
			position.x += sin(phase + st_t * 0.2) * 0.8 * dt
			position.z += cos(phase + st_t * 0.17) * 0.8 * dt
			if (aggro or _sees(d)) and _burrow_t <= 0.0 and on_water:
				_wake()
				_go(&"travel")
		&"travel":
			set_exposed(false)
			rise = 0.0
			if world == null or not world.hero_alive() or d > float(spec["sight"]) * 2.2 or not on_water:
				aggro = false
				_go(&"idle")
				return
			var d2 := _hero2() - Vector2(position.x, position.z)
			heading = lerp_angle(heading, atan2(-d2.x, -d2.y), clampf(4.0 * dt, 0.0, 1.0))
			var step := float(spec["run"]) * dt
			var nx := position.x - sin(heading) * step
			var nz := position.z - cos(heading) * step
			var ny := TerrainHeight.height_at(nx, nz)
			var w := TerrainHeight.water_level_for(nx, nz, ny)
			if w != TerrainHeight.NO_WATER and w - ny > 2.5:
				position.x = nx
				position.z = nz
				ground = ny
				water_y = w
			if int(st_t * 3.0) != int((st_t - dt) * 3.0) and world != null:
				world.fx.ring(Vector3(position.x, water_y + 0.05, position.z), 2.4, 0.8, Color(0.4, 1.0, 0.95))
			if d <= 20.0 and cool <= 0.0:
				_aim = hero_pos()
				_aim2 = Vector2(_aim.x, _aim.z)
				var rp := Vector3(_aim.x, water_y, _aim.z)
				var tw := TerrainHeight.water_level_for(rp.x, rp.z, TerrainHeight.height_at(rp.x, rp.z))
				if tw != TerrainHeight.NO_WATER and tw - TerrainHeight.height_at(rp.x, rp.z) > 2.0:
					if world != null:
						world.fx.ring(rp + Vector3(0.0, 0.1, 0.0), float(spec["reach"]), float(spec["windup"]) * _aggr_k(), Color(0.3, 1.0, 0.95))
					_go(&"telegraph")
				else:
					cool = 1.0
		&"telegraph":
			set_exposed(false)
			if st_t >= float(spec["windup"]) * _aggr_k():
				position.x = _aim2.x
				position.z = _aim2.y
				heading = atan2(-(hero_pos().x - _aim2.x), -(hero_pos().z - _aim2.y))
				set_exposed(true)
				_go(&"erupt")
				if world != null:
					world.fx.splash(Vector3(position.x, water_y, position.z), 3.0)
				Sfx.play_at(&"water_splash_big", position, -2.0)
		&"erupt":
			rise = 1.0 - pow(1.0 - clampf(st_t / 0.4, 0.0, 1.0), 3.0)
			_face(_hero2(), dt, 5.0)
			if st_t >= 0.45:
				var h := hero_pos()
				if Vector2(h.x - position.x, h.z - position.z).length() < float(spec["reach"]):
					attacks_done += 1
					_hurt_hero(float(spec["dmg"]))
					Sfx.bark(&"growl", position, 0.6, -2.0)
				cool = float(spec["cool"]) * _aggr_k()
				_go(&"exposed")
		&"exposed":
			rise = 1.0
			_face(_hero2(), dt, 2.0)
			if st_t >= 2.6:
				_go(&"sink")
		&"sink":
			rise = clampf(1.0 - st_t / 0.7, 0.0, 1.0)
			if st_t >= 0.7:
				set_exposed(false)
				rise = 0.0
				_burrow_t = float(spec["cool"]) * _aggr_k()
				if world != null:
					world.fx.splash(Vector3(position.x, water_y, position.z), 2.0)
				_go(&"travel")
