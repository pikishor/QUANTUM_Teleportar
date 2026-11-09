class_name RosterBoss
extends AlienBoss
## The four roster-2 bosses (wave 108): MOUNTAIN TITAN, MECH COLOSSUS, SEA LEVIATHAN, AIR GUNSHIP. They are AlienBosses (engage / disengage, phases at two thirds and one third with a roar and a second of
## invulnerability, the boss bar and its ONE hint, music, drops) with WEAK POINTS (RosterWeak) as the main idea: while any component part stands the body takes only ARMOUR_K of every hit, the parts take
## their multiplier, and every broken part opens the boss for a while. Every attack shows a ring or a line first; the hint always names the one thing to do.
##   TITAN      walks at the hero, STOMPS (a ring: jump it), throws BOULDERS (rings where they land); three CRYSTALS on its back and shoulders (240 hp each): each one staggers it, with all three gone it
##              KNEELS for 6 s (open x2.2); the crystals grow back once at half strength.
##   COLOSSUS   holds 14-32 m away, sweeps a GATLING arc (two lines mark its edges), fires a missile BARRAGE (a ring per missile), stomps up close; two KNEE joints (300 hp): each one makes it limp
##              (slower), with both gone it kneels for 6 s and the REACTOR on its back is the target (x2.5).
##   LEVIATHAN  swims under the water toward the hero, marks a ring, ERUPTS (bite, tail sweep in later phases), stays surfaced 6 s (open x1.8, fan of spit) and sinks; the GILLS on its neck take x2.2.
##   GUNSHIP    circles at 22 m, marks a STRAFE line (fly off it), fires a rocket barrage (rings), calls drones in phase 2; two ENGINES (260 hp): each one slows it and smokes, with both gone it
##              crash-lands and stays grounded (open x1.8); the tail rotor on its back takes x2.2.

const ARMOUR_K := 0.45
const ROCK := Color(0.62, 0.56, 0.5)
const STEEL := Color(1.0, 0.55, 0.15)

var wk: RosterWeak
var crystals_broken := 0
var knees_broken := 0
var engines_broken := 0
var regrown := 0
var kneel_t := 0.0
var strafes := 0
var barrages := 0
var stomps := 0
var throws := 0
var sweeps := 0
var erupts := 0
var _gat_cd := 5.0
var _msl_cd := 6.0
var _spit_t2 := 3.0
var _tail_t := 6.0
var _sweep_a := 0.0
var _sweep_base := Vector3.ZERO
var _fire_t := 0.0
var _smoke_t := 0.0
var _lead := Vector3.ZERO
var _dir2 := Vector2.ZERO
var _tr_t := 0.0


func setup(sid: StringName, w: AlienWorld) -> bool:
	if not RosterKit.setup_body(self, sid, w):
		return false
	title = String(spec.get("title", spec["name"]))
	arena_r = float(spec["sight"]) * 1.4
	wk = RosterWeak.new(self)
	if cls == AlienSpecies.AIR:
		alt = float((spec["alt"] as Array)[0])
	_slam_cd = 3.0
	_cloud_t = 5.0
	return true


func hit_ray(o: Vector3, d: Vector3) -> Dictionary:
	return wk.hit_ray(o, d)


func _to_world(local: Vector3) -> Vector3:
	return Basis(Vector3.UP, heading) * (local * vis) + Vector3(0.0, -(1.0 - rise) * _bury_depth(), 0.0)


func stagger(_power: float) -> void:
	pass


func damage(amount: float, crit := false, mirrored := false) -> void:
	if dead or inv_t > 0.0 or not exposed:
		super.damage(amount, crit, mirrored)
		return
	var amt := amount
	var wi := wk.take()
	if wi >= 0:
		amt = wk.damage_part(wi, amt)
		_pulse = 1.0
		if world != null and world.fx != null:
			world.fx.spark(global_position + _to_world((wk.defs[wi] as Dictionary)["pos"] as Vector3), Color(1.0, 1.0, 0.6))
	elif _armoured():
		amt *= ARMOUR_K
	super.damage(amt, crit, mirrored)


func _armoured() -> bool:
	if open_t > 0.0:
		return false
	for i in wk.defs.size():
		if wk.alive[i] and float((wk.defs[i] as Dictionary).get("comp", 0.0)) > 0.0:
			return true
	return false


func _part_hint() -> String:
	for i in wk.defs.size():
		if wk.alive[i] and float((wk.defs[i] as Dictionary).get("comp", 0.0)) > 0.0:
			return "SHOOT THE GLOWING %s" % String((wk.defs[i] as Dictionary).get("tip", "PART"))
	return ""


func _part_broken(_i: int, _pid: StringName, fx: StringName) -> void:
	FX.burst(center(), Color(1.0, 0.8, 0.4), 18, 8.0, 0.6, 4.0, 2.4)
	FX.shake(0.35)
	Sfx.play_at(&"boom", global_position + Vector3(0.0, 3.0, 0.0), -4.0, 0.9)
	match fx:
		&"crystal":
			crystals_broken += 1
			open_t = 2.5
			open_k = 1.6
			_go(&"hurt")
			Game.say("CRYSTAL DOWN", 1.6)
			if wk.parts_alive() == 0:
				_kneel()
		&"knee":
			knees_broken += 1
			open_t = 2.0
			open_k = 1.4
			_go(&"hurt")
			Game.say("KNEE DOWN", 1.6)
			if knees_broken >= 2:
				_kneel()
		&"engine":
			engines_broken += 1
			open_t = 2.0
			open_k = 1.4
			Game.say("ENGINE DOWN", 1.6)
			if engines_broken >= 2:
				_go(&"crash")


func _kneel() -> void:
	kneel_t = 6.0
	open_t = 6.0
	open_k = 2.2
	_go(&"kneel")
	Game.say("%s IS DOWN  SHOOT IT" % String(spec["name"]), 2.2)


func _regrow() -> void:
	if regrown >= 1:
		return
	regrown += 1
	for i in wk.defs.size():
		if float((wk.defs[i] as Dictionary).get("comp", 0.0)) > 0.0:
			wk.alive[i] = true
			wk.hp[i] = float((wk.defs[i] as Dictionary)["comp"]) * 0.5 * Difficulty.mult("hp")
	crystals_broken = 0
	knees_broken = 0


func _enter_phase(n: int) -> void:
	super._enter_phase(n)
	match mech:
		&"boss_titan":
			_summon(&"hiveling", 3 + n)
		&"boss_colossus":
			if n >= 2:
				_summon(&"wasp_drone", 2)
		&"boss_gunship":
			if n >= 2:
				_summon(&"wasp_drone", 2)
		&"boss_leviathan2":
			_tail_t = 1.5


func _engage() -> void:
	super._engage()
	_hint = _part_hint()


func _apply() -> void:
	super._apply()
	if mat != null:
		var fd := flat_dist()
		mat.set_shader_parameter(&"far_k", 0.5 * smoothstep(14.0, 60.0, fd) if is_finite(fd) else 0.0)


func _idle_roster(dt: float) -> void:
	match mech:
		&"boss_gunship":
			alt = lerpf(alt, 24.0, dt)
			_orbit_a += dt * 0.25
			position.x = lair.x + cos(_orbit_a) * 40.0
			position.z = lair.z + sin(_orbit_a) * 40.0
			heading = _orbit_a + PI * 0.5
			ground = TerrainHeight.height_at(position.x, position.z)
		&"boss_leviathan2":
			set_exposed(false)
			rise = 0.0
		_:
			_play(&"idle", 1.0)


func _tick_roster(dt: float, d: float) -> void:
	kneel_t = maxf(0.0, kneel_t - dt)
	match mech:
		&"boss_titan": _tick_titan(dt, d)
		&"boss_colossus": _tick_colossus(dt, d)
		&"boss_leviathan2": _tick_leviathan2(dt, d)
		&"boss_gunship": _tick_gunship(dt, d)


# --- helpers -------------------------------------------------------------------------------------------------------------------------------------------

func _ring(at: Vector3, r: float, secs: float, col: Color) -> void:
	if world != null and world.fx != null:
		world.fx.ring(Vector3(at.x, TerrainHeight.height_at(at.x, at.z) + 0.1, at.z), r, secs, col)


func _boulders(from: Vector3, n: int, flight: float, r: float, dmg: float, col: Color, size: float) -> void:
	var h := hero_pos()
	for k in n:
		var off := Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0)) if k > 0 else Vector3.ZERO
		if world != null and world.fire != null:
			world.fire.shell(from, Vector3(h.x + off.x, 0.0, h.z + off.z), flight + 0.3 * float(k), r, dmg, col, size, 0.0, 0.5, self)


func _stomp_hit(r: float, mult := 1.0) -> void:
	FX.blast(global_position, r * 0.8, Color(1.0, 0.8, 0.4), 0.4, -1, 0.0, false)
	FX.shake(0.5)
	Sfx.play_at(&"boom", global_position, -2.0, 0.7)
	attacks_done += 1
	if flat_dist() < r and not _hero_airborne():
		_hurt_hero(float(spec["dmg"]) * mult)
		var h := hero_pos()
		world.knock_hero(Vector3(h.x - position.x, 0.0, h.z - position.z).normalized() * 7.0 + Vector3.UP * 5.0)


# --- MOUNTAIN TITAN -------------------------------------------------------------------------------------------------------------------------------------

func _tick_titan(dt: float, d: float) -> void:
	_cloud_t -= dt
	_slam_cd -= dt
	var wt := float(spec["windup"]) * _aggr_k()
	_hint = _part_hint() if wk.parts_alive() > 0 else "SHOOT IT NOW  IT KNEELS"
	if state == &"windup":
		_hint = "JUMP THE STOMP RING"
	match state:
		&"idle", &"chase":
			state = &"chase"
			_steer(_hero2(), float(spec["run"]) if d > 14.0 else float(spec["walk"]), dt)
			_play(&"walk", 0.8)
			if _slam_cd <= 0.0 and d <= 9.5:
				_ring(global_position, 8.5, wt, Color(1.0, 0.8, 0.4))
				_pulse = 1.0
				_go(&"windup")
			elif _cloud_t <= 0.0 and d > 13.0 and d < 70.0:
				_go(&"throw")
		&"windup":
			_face(_hero2(), dt, 2.5)
			_pulse = clampf(st_t / wt, 0.0, 1.0)
			if st_t >= wt:
				_stomp_hit(8.5)
				stomps += 1
				_slam_cd = float(spec["cool"]) * _aggr_k()
				open_t = 2.0
				open_k = 1.3
				_go(&"winded")
		&"throw":
			_face(_hero2(), dt, 3.0)
			_pulse = clampf(st_t / 1.1, 0.0, 1.0)
			if st_t >= 1.1:
				_boulders(global_position + Basis(Vector3.UP, heading) * Vector3(1.6, 8.0, -1.6), 2 if phase_i == 1 else 3, 1.8, 3.8, float(spec["dmg"]) * 0.7, ROCK, 1.6)
				throws += 1
				attacks_done += 1
				_cloud_t = (6.5 if phase_i == 1 else 4.5) * _aggr_k()
				_go(&"chase")
		&"winded":
			if st_t >= 2.0:
				_go(&"chase")
		&"hurt":
			if st_t >= 2.5:
				_go(&"chase")
		&"kneel":
			_beat = 1.0
			if st_t >= 6.0:
				_beat = 0.0
				_regrow()
				_go(&"chase")


# --- MECH COLOSSUS ---------------------------------------------------------------------------------------------------------------------------------------

func _tick_colossus(dt: float, d: float) -> void:
	_gat_cd -= dt
	_msl_cd -= dt
	_slam_cd -= dt
	var wt := float(spec["windup"]) * _aggr_k()
	var sp_k := 1.0 - 0.45 * float(knees_broken)
	_hint = _part_hint() if wk.parts_alive() > 1 else ("SHOOT THE REACTOR ON ITS BACK" if kneel_t > 0.0 else "BREAK THE KNEES")
	if state == &"windup":
		_hint = "JUMP THE STOMP RING"
	elif state == &"aim" or state == &"sweep":
		_hint = "MOVE OFF THE LINE  SIDE-STEP"
	match state:
		&"idle", &"hold":
			state = &"hold"
			var h2 := _hero2()
			if d > 32.0:
				_steer(h2, float(spec["walk"]) * sp_k, dt)
			elif d < 14.0:
				_face(h2, dt, 1.6)
				var p2 := Vector2(position.x, position.z)
				_steer(p2 + (p2 - h2).normalized() * 5.0, float(spec["walk"]) * 0.7 * sp_k, dt)
			else:
				_face(h2, dt, 1.6)
			if _slam_cd <= 0.0 and d <= 11.0:
				_ring(global_position, 7.0, wt, Color(1.0, 0.5, 0.15))
				_go(&"windup")
			elif _gat_cd <= 0.0 and d < 62.0:
				_aim = hero_pos()
				_sweep_base = _aim - global_position
				_sweep_base.y = 0.0
				for sg: float in [-1.0, 1.0]:
					var edge := global_position + _sweep_base.rotated(Vector3.UP, sg * 0.36)
					if world != null and world.fx != null:
						world.fx.line(global_position + Vector3(0.0, 7.0, 0.0), Vector3(edge.x, TerrainHeight.height_at(edge.x, edge.z) + 0.5, edge.z), wt, STEEL)
				_go(&"aim")
			elif _msl_cd <= 0.0 and d < 70.0:
				_go(&"barrage")
		&"windup":
			_face(_hero2(), dt, 2.0)
			_pulse = clampf(st_t / wt, 0.0, 1.0)
			if st_t >= wt:
				_stomp_hit(7.0)
				stomps += 1
				_slam_cd = float(spec["cool"]) * _aggr_k() * 1.6
				_go(&"hold")
		&"aim":
			_pulse = clampf(st_t / wt, 0.0, 1.0)
			if st_t >= wt:
				_sweep_a = -0.36
				_fire_t = 0.0
				sweeps += 1
				_go(&"sweep")
		&"sweep":
			_sweep_a += dt * 0.72 / 1.8 * 1.0
			_fire_t -= dt
			var dir := _sweep_base.rotated(Vector3.UP, _sweep_a).normalized()
			heading = lerp_angle(heading, atan2(-dir.x, -dir.z), clampf(6.0 * dt, 0.0, 1.0))
			if _fire_t <= 0.0:
				_fire_t = 0.09
				var from := global_position + Basis(Vector3.UP, heading) * Vector3(-3.0, 7.2, -3.0)
				var tgt := Vector3(global_position.x, 0.0, global_position.z) + dir * _sweep_base.length()
				tgt.y = hero_pos().y
				world.shoot(from, (tgt - from).normalized(), 38.0, float(spec["dmg"]), 0.5, STEEL, 0.6, self)
				Sfx.play_at(&"shot_mini", from, -6.0, 0.7)
			if _sweep_a >= 0.36:
				_gat_cd = float(spec["cool"]) * 2.2 * _aggr_k()
				attacks_done += 1
				_go(&"hold")
		&"barrage":
			_face(_hero2(), dt, 2.0)
			_pulse = clampf(st_t / (1.0 * _aggr_k()), 0.0, 1.0)
			if st_t >= 1.0 * _aggr_k():
				_boulders(global_position + Basis(Vector3.UP, heading) * Vector3(3.0, 7.8, -1.5), 5 if phase_i < 3 else 6, 1.6, 3.2, float(spec["dmg"]) * 1.4, STEEL, 0.9)
				barrages += 1
				attacks_done += 1
				_msl_cd = 9.0 * _aggr_k()
				_go(&"hold")
		&"hurt":
			if st_t >= 2.0:
				_go(&"hold")
		&"kneel":
			_beat = 1.0
			if st_t >= 6.0:
				_beat = 0.0
				_regrow()
				_go(&"hold")


# --- SEA LEVIATHAN ----------------------------------------------------------------------------------------------------------------------------------------

## The point toward `to2` (xz) the leviathan can reach: along the straight line while the water is at least 2.5 m deep.
func _water_point_toward(to2: Vector2) -> Vector2:
	var p2 := Vector2(position.x, position.z)
	var best := p2
	var n := 12
	for k in range(1, n + 1):
		var q := p2.lerp(to2, float(k) / float(n))
		var gy := TerrainHeight.height_at(q.x, q.y)
		var w := TerrainHeight.water_level_for(q.x, q.y, gy)
		if w == TerrainHeight.NO_WATER or w - gy < 2.5:
			break
		best = q
	return best


func _swim_to(to2: Vector2, speed: float, dt: float) -> void:
	var p2 := Vector2(position.x, position.z)
	var tgt := _water_point_toward(to2) if p2.distance_to(to2) > 3.0 else p2
	var dir := tgt - p2
	if dir.length() < 0.3:
		return
	var step := minf(speed * dt, dir.length())
	position.x += dir.normalized().x * step
	position.z += dir.normalized().y * step
	heading = lerp_angle(heading, atan2(-dir.x, -dir.y), clampf(4.0 * dt, 0.0, 1.0))


func _tick_leviathan2(dt: float, d: float) -> void:
	_spit_t2 -= dt
	_tail_t -= dt
	var wt := float(spec["windup"]) * _aggr_k()
	var h2 := _hero2()
	_hint = "SHOOT THE GLOWING GILLS" if state == &"surfaced" else ("MOVE OUT OF THE RING" if state == &"telegraph" else "KEEP MOVING  IT RISES UNDER YOU")
	match state:
		&"idle", &"travel":
			state = &"travel"
			set_exposed(false)
			rise = 0.0
			_tr_t -= dt
			_swim_to(h2, float(spec["run"]), dt)
			if _tr_t <= 0.0 and world != null:
				_tr_t = 0.35
				world.fx.splash(Vector3(position.x, water_y if water_y != TerrainHeight.NO_WATER else position.y, position.z), 1.0)
			if d < 26.0 and st_t > 2.0:
				var tgt := _water_point_toward(h2)
				_aim = Vector3(tgt.x, water_y if water_y != TerrainHeight.NO_WATER else position.y, tgt.y)
				_ring(_aim, float(spec["reach"]), wt, Color(0.3, 1.0, 0.85))
				_go(&"telegraph")
		&"telegraph":
			_swim_to(Vector2(_aim.x, _aim.z), float(spec["run"]) * 0.8, dt)
			if st_t >= wt:
				set_exposed(true)
				erupts += 1
				_go(&"erupt")
		&"erupt":
			rise = minf(1.0, st_t / 0.5)
			if st_t >= 0.5:
				rise = 1.0
				FX.shake(0.5)
				Sfx.play_at(&"boom", global_position, -2.0, 0.8)
				attacks_done += 1
				if flat_dist() < float(spec["reach"]) and not _hero_airborne():
					_hurt_hero(float(spec["dmg"]))
					world.knock_hero(Vector3(hero_pos().x - position.x, 0.0, hero_pos().z - position.z).normalized() * 7.0 + Vector3.UP * 4.0)
				open_t = 6.0
				open_k = 1.8
				_spit_t2 = 1.0
				_go(&"surfaced")
		&"surfaced":
			_face(h2, dt, 2.0)
			open_t = maxf(open_t, 0.2) if st_t < 6.0 else open_t
			if _spit_t2 <= 0.0 and d < 70.0:
				_spit_t2 = 2.6 * _aggr_k()
				var from := global_position + Basis(Vector3.UP, heading) * Vector3(0.0, 8.9, -4.8)
				var base := hero_pos() - from
				for k in range(-1, 2):
					world.shoot(from, base.rotated(Vector3.UP, 0.16 * float(k)).normalized(), 16.0, float(spec["dmg"]) * 0.5, 0.9, Color(0.3, 1.0, 0.85), 1.1, self)
				attacks_done += 1
			if phase_i >= 2 and _tail_t <= 0.0 and st_t > 1.5 and d < 14.0:
				_tail_t = 7.0 * _aggr_k()
				_ring(global_position, 9.5, 1.0 * _aggr_k(), Color(0.3, 1.0, 0.85))
				_go(&"tail")
			if st_t >= 6.0:
				_go(&"sink")
		&"tail":
			_pulse = clampf(st_t / (1.0 * _aggr_k()), 0.0, 1.0)
			if st_t >= 1.0 * _aggr_k():
				_stomp_hit(9.5, 0.8)
				sweeps += 1
				_go(&"surfaced")
		&"sink":
			rise = maxf(0.0, 1.0 - st_t / 0.6)
			if st_t >= 0.6:
				rise = 0.0
				set_exposed(false)
				open_t = 0.0
				_go(&"travel")


# --- AIR GUNSHIP ------------------------------------------------------------------------------------------------------------------------------------------

func _tick_gunship(dt: float, d: float) -> void:
	_strike_t -= dt
	_msl_cd -= dt
	_smoke_t -= dt
	var wt := float(spec["windup"]) * _aggr_k()
	var sk := 1.0 - 0.35 * float(engines_broken)
	var gy := TerrainHeight.height_at(position.x, position.z)
	ground = gy
	_hint = _part_hint() if wk.parts_alive() > 1 else ("SHOOT IT NOW  IT IS DOWN" if state == &"grounded" else "SHOOT THE TAIL ROTOR")
	if state == &"mark":
		_hint = "MOVE OFF THE LINE"
	if _smoke_t <= 0.0 and engines_broken > 0:
		_smoke_t = 0.35
		FX.burst(global_position + Vector3(1.7 * (1.0 if engines_broken % 2 == 1 else -1.0), 1.0, 1.0), Color(0.25, 0.25, 0.25, 0.7), 4, 2.0, 0.9, -0.5, 4.0)
	match state:
		&"idle", &"orbit":
			state = &"orbit"
			_orbit_a += dt * 0.5 * sk * (1.0 if phase_i < 3 else 1.4)
			var h := hero_pos()
			var want := Vector2(h.x + cos(_orbit_a) * 34.0, h.z + sin(_orbit_a) * 34.0)
			var dir := want - Vector2(position.x, position.z)
			var mv := dir.normalized() * minf(dir.length(), float(spec["run"]) * 0.6 * sk * dt * 2.0)
			position.x += mv.x
			position.z += mv.y
			heading = lerp_angle(heading, atan2(-dir.x, -dir.y), clampf(3.0 * dt, 0.0, 1.0))
			alt = lerpf(alt, 22.0 + 2.0 * sin(_orbit_a * 2.0), clampf(2.0 * dt, 0.0, 1.0))
			if _strike_t <= 0.0 and d < 90.0 and d > 14.0:
				_aim = hero_pos()
				var line_dir := Vector2(_aim.x - position.x, _aim.z - position.z).normalized()
				_dir2 = line_dir
				strafes += 1
				if world != null and world.fx != null:
					var a := Vector3(position.x, gy + 0.5, position.z)
					var b := Vector3(_aim.x + line_dir.x * 30.0, TerrainHeight.height_at(_aim.x, _aim.z) + 0.5, _aim.z + line_dir.y * 30.0)
					world.fx.line(a, b, 1.6 * _aggr_k(), STEEL)
				_go(&"mark")
			elif _msl_cd <= 0.0 and d < 80.0:
				_go(&"rockets")
		&"mark":
			_pulse = clampf(st_t / (1.6 * _aggr_k()), 0.0, 1.0)
			heading = lerp_angle(heading, atan2(-_dir2.x, -_dir2.y), clampf(5.0 * dt, 0.0, 1.0))
			if st_t >= 1.6 * _aggr_k():
				_fire_t = 0.0
				_go(&"strafe")
		&"strafe":
			alt = lerpf(alt, 13.0, clampf(2.0 * dt, 0.0, 1.0))
			position.x += _dir2.x * float(spec["run"]) * sk * dt
			position.z += _dir2.y * float(spec["run"]) * sk * dt
			_fire_t -= dt
			if _fire_t <= 0.0:
				_fire_t = 0.08
				var from := global_position + Basis(Vector3.UP, heading) * Vector3(0.0, -1.1, -4.0)
				var tgt := Vector3(_aim.x, _aim.y, _aim.z) + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 1.6
				world.shoot(from, (tgt - from).normalized(), 40.0, float(spec["dmg"]), 0.5, STEEL, 0.6, self)
				Sfx.play_at(&"shot_chaingun", from, -6.0, 0.8)
			if st_t >= 2.0:
				_strike_t = (7.0 if phase_i == 1 else 5.0) * _aggr_k()
				attacks_done += 1
				_go(&"orbit")
		&"rockets":
			_pulse = clampf(st_t / wt, 0.0, 1.0)
			if st_t >= wt:
				_boulders(global_position + Vector3(0.0, -0.2, -0.5), 4 if phase_i < 3 else 5, 1.8, 3.2, float(spec["dmg"]) * 2.4, STEEL, 0.8)
				barrages += 1
				attacks_done += 1
				_msl_cd = 8.0 * _aggr_k()
				_go(&"orbit")
		&"crash":
			alt = maxf(1.6, alt - 6.0 * dt)
			_pitch = lerpf(_pitch, -0.25, clampf(2.0 * dt, 0.0, 1.0))
			if alt <= 1.7:
				_pitch = 0.0
				FX.blast(global_position, 6.0, STEEL, 0.5, -1, 0.0, false)
				FX.shake(0.8)
				Sfx.play_at(&"boom", global_position, 0.0, 0.7)
				open_t = 9999.0
				open_k = 1.8
				_go(&"grounded")
		&"grounded":
			alt = 1.7
			_face(_hero2(), dt, 1.5)
			open_t = 9999.0
			_fire_t -= dt
			if _fire_t <= 0.0 and d < 42.0 and st_t > 1.5:
				_fire_t = 0.5
				var from := global_position + Basis(Vector3.UP, heading) * Vector3(0.0, -1.1, -4.0)
				world.shoot(from, (hero_pos() - from).normalized(), 32.0, float(spec["dmg"]), 0.5, STEEL, 0.6, self)
