class_name AlienBoss
extends AlienCreature
## The five boss creatures, one per biome, each with a mechanic of its own and an EASY-first rhythm (a telegraph before every attack, a window where it is open, no sudden deaths):
##   BROODMOTHER   (forest)    walks at the hero; lobs SPORE CLOUDS (rings show where they land, the cloud hurts over time); a ROOT SLAM (jump the ring); after every slam it is WINDED: the
##                             glowing sac on its back takes double damage; at two thirds and one third of its health it calls SKITTERS.
##   STORM DRAKE   (mountains)  circles high, marks LIGHTNING strikes (rings, a second later a bolt), then marks a DIVE LINE; after the dive it lands and is GROUNDED for a few seconds: open
##                             (x1.5); in the last third swarmers join.
##   SAND LEVIATHAN (desert)    the dune maw's big brother: tremors, a ring where it will rise (move), the eruption, then it stays risen: bites along a marked line and spits a FAN of sand
##                             globs; in the later phases it erupts twice in a row. The glowing maw (head) takes double damage.
##   DEEP KRAKEN   (ocean)      floats in the sea with FOUR ARMS that rise and slam rings on the water; its mantle is shielded while any arm lives; with the arms down it SURFACES (open, x1.4) and
##                             sprays ink; the arms grow back twice.
##   HIVE WARDEN   (crash sites) a floating guardian inside an energy shield held by THREE RELAYS; destroy the relays and the shield falls (the warden is stunned); it fires a marked
##                             LANCE and an expanding PULSE RING (jump) and calls grunts.
## The boss bar is read by the HUD from AlienWorld.boss_info() ({name, frac, hint}); the hint always says the ONE thing to do right now.

const PHASE_LINES := {1: "", 2: "IT CALLS FOR HELP", 3: "IT IS ENRAGED"}

var phase_i := 1
var title := ""
var lair := Vector3.ZERO
var arena_r := 120.0
var open_k := 1.0                      ## damage multiplier while it is open (winded / grounded / surfaced)
var open_t := 0.0                      ## seconds it stays open
var inv_t := 0.0                       ## seconds invulnerable (a phase roar)
var helpers: Array[AlienCreature] = []
var relays: Array[AlienCreature] = []
var arms: Array[AlienCreature] = []
var shield_on := false
var summons_done := 0
var strikes: Array = []                ## drake lightning: [pos, t]
var _cloud_t := 5.0
var _strike_t := 4.0
var _spit_t := 3.0
var _arm_regrow := 0
var _arm_t := 0.0
var _ink_t := 4.0
var _pulse_t := 6.0
var _chain := 0
var _engaged := false
var _roar_t := 0.0
var _slam_cd := 3.0
var _orbit_a := 0.0
var _land_t := 0.0
var _hint := ""


func setup(sid: StringName, w: AlienWorld) -> bool:
	var ok := super.setup(sid, w)
	title = String(spec.get("title", spec.get("name", "")))
	arena_r = float(spec["sight"]) * 1.4
	if mat != null and mech == &"boss_warden":
		mat.set_shader_parameter(&"shield", 1.0)
	return ok


func is_boss() -> bool:
	return true


func frac() -> float:
	return clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)


func hint() -> String:
	return _hint


func damage(amount: float, crit := false, mirrored := false) -> void:
	if dead or inv_t > 0.0:
		if not dead:
			Sfx.play_at(&"ricochet", center(), -6.0)
		return
	var k := 1.0
	if open_t > 0.0:
		k = open_k
	if mech == &"boss_leviathan" and crit:
		k *= 1.5
	if mech == &"boss_kraken":
		_shield = 1.0 if not arms.is_empty() and _alive_arms() > 0 else 0.0
	if mech == &"boss_warden":
		_shield = 1.0 if shield_on else 0.0
	super.damage(amount * k, crit, mirrored)


func _on_hurt(amount: float, crit: bool) -> void:
	super._on_hurt(amount, crit)
	var np := 1 if frac() > 0.66 else (2 if frac() > 0.33 else 3)
	if np > phase_i and not dead:
		phase_i = np
		_enter_phase(np)


func _enter_phase(n: int) -> void:
	inv_t = 1.6
	_pulse = 1.0
	FX.shake(0.5)
	Sfx.bark(&"growl", global_position, 0.4, 0.0)
	if world != null:
		world.fx.ring(Vector3(position.x, TerrainHeight.height_at(position.x, position.z) + 0.1, position.z), 9.0, 1.4, Color(1.0, 0.8, 0.3))
	Game.say("%s  %s" % [title, String(PHASE_LINES.get(n, ""))], 2.2)
	if mat != null:
		mat.set_shader_parameter(&"rage", 1.0 if n >= 3 else 0.0)
	match mech:
		&"boss_brood":
			if n >= 2:
				_summon(&"skitter", 4)
		&"boss_drake":
			if n >= 3:
				_summon(&"swarmer", 5)
		&"boss_warden":
			_summon(&"hive_grunt", 2)
		&"boss_leviathan":
			_chain = 1 if n == 2 else 2


func _summon(sid: StringName, n: int) -> void:
	if world == null:
		return
	summons_done += n
	var made := world.spawn_group(sid, Vector3(position.x, ground, position.z), n, site, 7.0, true)
	for m in made:
		helpers.append(m)
		m.aggro = true


func _alive_arms() -> int:
	var n := 0
	for a in arms:
		if is_instance_valid(a) and not a.dead:
			n += 1
	return n


func _alive_relays() -> int:
	var n := 0
	for r in relays:
		if is_instance_valid(r) and not r.dead:
			n += 1
	return n


func _engage() -> void:
	if _engaged:
		return
	_engaged = true
	aggro = true
	Sfx.boss_active = true
	Sfx.boss_phase = 1
	Game.say(title, 2.4)
	if mech == &"boss_kraken":
		_spawn_arms(4)
	if mech == &"boss_warden":
		shield_on = _alive_relays() > 0
	if world != null:
		world.boss_engaged(self)


func _disengage() -> void:
	if not _engaged:
		return
	_engaged = false
	aggro = false
	hp = max_hp
	phase_i = 1
	Sfx.boss_active = false
	if mat != null:
		mat.set_shader_parameter(&"rage", 0.0)
	if world != null:
		world.boss_left(self)


func die(hero_kill := true) -> void:
	if dead:
		return
	Sfx.boss_active = false
	for h in helpers:
		if is_instance_valid(h) and not h.dead:
			h.die(false)
	for a in arms:
		if is_instance_valid(a) and not a.dead:
			a.die(false)
	for r in relays:
		if is_instance_valid(r) and not r.dead:
			r.die(false)
	FX.shake(0.9)
	if world != null:
		world.fx.dust(global_position, Color(0.9, 0.8, 0.6))
	super.die(hero_kill)
	Game.say("%s DOWN" % title, 3.0)
	if _engaged and world != null:
		world.boss_left(self)
	_engaged = false


func _tick_extra(dt: float, d: float) -> void:
	inv_t = maxf(0.0, inv_t - dt)
	open_t = maxf(0.0, open_t - dt)
	if inv_t > 0.0:
		_pulse = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.03)
	if not _engaged:
		if world != null and world.hero_alive() and d <= float(spec["sight"]):
			_engage()
		else:
			_idle_boss(dt)
			return
	elif world == null or not world.hero_alive() or Vector2(position.x - lair.x, position.z - lair.z).length() > arena_r + 40.0 or d > arena_r * 1.6:
		_disengage()
		return
	if inv_t > 0.0 and mech != &"boss_kraken":
		_play(&"idle", 1.0)
		return
	match mech:
		&"boss_brood": _tick_brood(dt, d)
		&"boss_drake": _tick_drake(dt, d)
		&"boss_leviathan": _tick_leviathan(dt, d)
		&"boss_kraken": _tick_kraken(dt, d)
		&"boss_warden": _tick_warden(dt, d)
		_: _tick_roster(dt, d)


## The roster-2 bosses (RosterBoss) put their own mechanics here (wave 108).
func _tick_roster(_dt: float, _d: float) -> void:
	pass


func _idle_roster(_dt: float) -> void:
	_play(&"idle", 1.0)


func _idle_boss(dt: float) -> void:
	match mech:
		&"boss_drake":
			alt = lerpf(alt, 26.0, dt)
			_orbit_a += dt * 0.25
			position.x = lair.x + cos(_orbit_a) * 40.0
			position.z = lair.z + sin(_orbit_a) * 40.0
			heading = _orbit_a + PI * 0.5
			ground = TerrainHeight.height_at(position.x, position.z)
			_play(&"fly", 0.7)
		&"boss_warden":
			alt = 5.0 + sin(Time.get_ticks_msec() * 0.001) * 0.6
			_play(&"idle", 0.6)
		&"boss_leviathan":
			set_exposed(false)
			rise = 0.0
		&"boss_kraken":
			_play(&"idle", 1.0)
		_:
			_idle_roster(dt)


# --- BROODMOTHER ----------------------------------------------------------------------------------------------------------------------------------

func _tick_brood(dt: float, d: float) -> void:
	_cloud_t -= dt
	_slam_cd -= dt
	_hint = "SHOOT THE GLOWING SAC NOW" if open_t > 0.0 else ("JUMP THE ROOT SLAM" if state == &"windup" else "KEEP MOVING  DODGE THE SPORES")
	match state:
		&"idle", &"chase":
			state = &"chase"
			_steer(_hero2(), float(spec["run"]) if d > 9.0 else float(spec["walk"]), dt)
			_play(&"walk" if d < 12.0 else &"run", 0.9)
			if _slam_cd <= 0.0 and d <= 6.5:
				_go(&"windup")
				_pulse = 1.0
				_play_once(&"attack", 0.8)
				world.fx.ring(Vector3(position.x, ground + 0.1, position.z), 7.5, float(spec["windup"]) * _aggr_k(), Color(0.85, 0.4, 1.0))
			elif _cloud_t <= 0.0 and d > 8.0 and d < 55.0:
				_aim = hero_pos()
				_aim.y = TerrainHeight.height_at(_aim.x, _aim.z)
				_go(&"lob")
				_play_once(&"attack", 1.0)
				for k in (2 if phase_i == 1 else 3):
					var off := Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0)) if k > 0 else Vector3.ZERO
					var p := _aim + off
					p.y = TerrainHeight.height_at(p.x, p.z)
					world.fx.ring(p + Vector3(0.0, 0.1, 0.0), 4.0, 1.5, Color(0.8, 0.45, 1.0))
					world.lob_cloud(global_position + Vector3(0.0, 3.6, 0.0), p, 1.5, 4.0, 5.0)
		&"lob":
			_face(Vector2(_aim.x, _aim.z), dt, 5.0)
			if st_t >= 0.9:
				_cloud_t = (6.5 if phase_i == 1 else 4.5) * _aggr_k()
				_go(&"chase")
		&"windup":
			_face(_hero2(), dt, 3.0)
			_pulse = clampf(st_t / (float(spec["windup"]) * _aggr_k()), 0.0, 1.0)
			if st_t >= float(spec["windup"]) * _aggr_k():
				_slam_now(7.5)
				_slam_cd = float(spec["cool"]) * _aggr_k()
				open_t = 3.2
				open_k = 2.0
				_go(&"winded")
		&"winded":
			_play(&"idle", 0.5)
			_beat = 1.0 if open_t > 0.0 else 0.0
			if st_t >= 3.0:
				_beat = 0.0
				_go(&"chase")


# --- STORM DRAKE ----------------------------------------------------------------------------------------------------------------------------------

func _tick_drake(dt: float, d: float) -> void:
	_strike_t -= dt
	_hint = "SHOOT IT NOW  IT IS GROUNDED" if state == &"grounded" else ("MOVE  A DIVE IS COMING" if state == &"mark" else "DODGE THE LIGHTNING RINGS")
	var gy := TerrainHeight.height_at(position.x, position.z)
	ground = gy
	# lightning strikes run beside every state
	var i := strikes.size() - 1
	while i >= 0:
		var st: Array = strikes[i]
		st[1] = float(st[1]) - dt
		if float(st[1]) <= 0.0:
			_strike_now(st[0] as Vector3)
			strikes.remove_at(i)
		i -= 1
	match state:
		&"idle", &"circle":
			state = &"circle"
			_orbit_a += dt * (0.55 if phase_i < 3 else 0.8)
			var h := hero_pos()
			var want := Vector3(h.x + cos(_orbit_a) * 34.0, 0.0, h.z + sin(_orbit_a) * 34.0)
			var dir := Vector2(want.x - position.x, want.z - position.z)
			var mv := dir.normalized() * minf(dir.length(), float(spec["run"]) * 0.7 * dt * 2.0)
			position.x += mv.x
			position.z += mv.y
			heading = lerp_angle(heading, atan2(-dir.x, -dir.y), clampf(3.0 * dt, 0.0, 1.0))
			alt = lerpf(alt, 24.0 + 4.0 * sin(_orbit_a * 2.0), clampf(2.0 * dt, 0.0, 1.0))
			position.y = gy + alt
			_play(&"fly", 1.0)
			if _strike_t <= 0.0 and d < 90.0:
				_strike_t = (5.5 if phase_i == 1 else 3.8) * _aggr_k()
				var n := 2 if phase_i == 1 else 3
				for k in n:
					var p := hero_pos() + Vector3(randf_range(-7.0, 7.0), 0.0, randf_range(-7.0, 7.0)) if k > 0 else hero_pos()
					p.y = TerrainHeight.height_at(p.x, p.z)
					strikes.append([p, 1.4 + 0.45 * float(k)])
					world.fx.ring(p + Vector3(0.0, 0.1, 0.0), 3.6, 1.4 + 0.45 * float(k), Color(0.5, 0.85, 1.0))
				if state == &"circle" and randf() < 0.6 and d < 70.0:
					_aim = hero_pos()
					world.fx.line(global_position, _aim, 1.5 * _aggr_k(), Color(1.0, 0.3, 0.2))
					_go(&"mark")
		&"mark":
			_face(Vector2(_aim.x, _aim.z), dt, 4.0)
			_pulse = clampf(st_t / (1.5 * _aggr_k()), 0.0, 1.0)
			if st_t >= 1.5 * _aggr_k():
				vel = (_aim + Vector3(0.0, 0.3, 0.0) - global_position).normalized() * float(spec["run"])
				_go(&"dive")
		&"dive":
			position += vel * dt
			heading = atan2(-vel.x, -vel.z)
			_pitch = atan2(vel.y, Vector2(vel.x, vel.z).length()) * -1.0
			alt = position.y - gy
			if position.y <= gy + 1.6 or st_t > 3.0:
				position.y = gy + 1.4
				_pitch = 0.0
				var h2 := hero_pos()
				if global_position.distance_to(h2) < 6.0:
					attacks_done += 1
					_hurt_hero(float(spec["dmg"]))
					world.knock_hero(Vector3(h2.x - position.x, 0.0, h2.z - position.z).normalized() * 8.0 + Vector3.UP * 5.0)
				FX.blast(global_position, 5.0, Color(0.5, 0.85, 1.0), 0.4, -1, 0.0, false)
				FX.shake(0.5)
				Sfx.play_at(&"boom", global_position, -2.0, 0.8)
				open_t = 5.5
				open_k = 1.5
				_go(&"grounded")
		&"grounded":
			alt = 1.4
			position.y = gy + 1.4
			_pitch = 0.0
			_play(&"idle", 0.6)
			_face(_hero2(), dt, 2.0)
			_beat = 1.0
			if st_t >= 5.5:
				_beat = 0.0
				_go(&"takeoff")
		&"takeoff":
			_play(&"fly", 1.4)
			position.y += 11.0 * dt
			alt = position.y - gy
			if alt >= 18.0:
				_go(&"circle")


func _strike_now(p: Vector3) -> void:
	FX.blast(p + Vector3(0.0, 0.4, 0.0), 3.6, Color(0.5, 0.85, 1.0), 0.35, -1, 0.0, false)
	FX.burst(p + Vector3(0.0, 6.0, 0.0), Color(0.7, 0.95, 1.0), 10, 3.0, 0.3, 0.0, 2.4)
	FX.shake(0.2)
	Sfx.play_at(&"thunder", p, -4.0, 1.2)
	var h := hero_pos()
	if Vector2(h.x - p.x, h.z - p.z).length() < 3.6 and not _hero_airborne():
		attacks_done += 1
		_hurt_hero(float(spec["dmg"]) * 0.7)


# --- SAND LEVIATHAN -------------------------------------------------------------------------------------------------------------------------------

func _tick_leviathan(dt: float, d: float) -> void:
	_spit_t -= dt
	_hint = "SHOOT THE GLOWING MAW" if state == &"exposed" else ("MOVE OUT OF THE RING" if state == &"telegraph" else "KEEP MOVING  IT RISES UNDER YOU")
	_tick_burrow(dt, d)
	if state == &"exposed":
		open_t = 1.0
		open_k = 1.0
		if _spit_t <= 0.0 and d < 60.0 and st_t > 1.0:
			_spit_t = 4.0 * _aggr_k()
			var from := global_position + Basis(Vector3.UP, heading) * Vector3(0.0, 8.4 * vis, -4.4 * vis)
			var base := hero_pos() - from
			for k in range(-2, 3):
				var dir := base.rotated(Vector3.UP, 0.16 * float(k)).normalized()
				world.shoot(from, dir, 17.0, float(spec["dmg"]) * 0.45, 0.9, Color(1.0, 0.65, 0.2), 1.1, self)
			Sfx.play_at(&"shot_scatter", from, -4.0, 0.6)
			attacks_done += 1
	if state == &"exposed" and _chain > 0 and st_t > 1.4 and world != null:       # the later phases erupt again at once, where the hero went
		_chain -= 1
		var p := hero_pos()
		_aim = Vector3(p.x, TerrainHeight.height_at(p.x, p.z), p.z)
		world.fx.ring(_aim + Vector3(0.0, 0.15, 0.0), float(spec["reach"]), float(spec["windup"]) * _aggr_k() * 0.8, Color(1.0, 0.5, 0.15))
		set_exposed(false)
		rise = 0.0
		_go(&"telegraph")
	if state == &"sink" and st_t < 0.05:
		_chain = phase_i - 1


# --- DEEP KRAKEN ----------------------------------------------------------------------------------------------------------------------------------

func _spawn_arms(n: int) -> void:
	if world == null:
		return
	for k in n:
		var a := TAU * float(k) / float(n) + 0.5
		var p := Vector3(position.x + cos(a) * 15.0, 0.0, position.z + sin(a) * 15.0)
		var arm := world.spawn_one(&"kraken_arm", p, site, true)
		if arm != null:
			arm.home = p
			(arm as AlienArm).boss = self
			arm.heading = a
			arms.append(arm)


func _tick_kraken(dt: float, d: float) -> void:
	var alive := _alive_arms()
	_shield = 1.0 if alive > 0 else 0.0
	_ink_t -= dt
	_arm_t -= dt
	_hint = "CUT DOWN THE ARMS  THEN SHOOT THE BODY" if alive > 0 else "SHOOT THE BODY NOW"
	match state:
		&"idle", &"guard":
			state = &"guard"
			_face(_hero2(), dt, 1.5)
			_play(&"idle", 1.0)
			if alive == 0:
				open_t = 7.0
				open_k = 1.4
				_arm_t = 8.0
				_go(&"surfaced")
				Game.say("THE BODY SURFACES", 1.8)
			if _ink_t <= 0.0 and d < 60.0:
				_ink_t = (5.0 if phase_i == 1 else 3.2) * _aggr_k()
				var from := global_position + Vector3(0.0, 3.5, -3.0)
				var base := hero_pos() - from
				for k in range(-1, 2):
					world.shoot(from, base.rotated(Vector3.UP, 0.22 * float(k)).normalized(), 15.0, float(spec["dmg"]) * 0.4, 0.9, Color(0.2, 0.9, 0.8), 1.1, self)
				Sfx.play_at(&"shot_arc", from, -4.0, 0.6)
		&"surfaced":
			_face(_hero2(), dt, 1.0)
			_beat = 0.8
			if _ink_t <= 0.0 and d < 70.0:
				_ink_t = 3.0 * _aggr_k()
				var from2 := global_position + Vector3(0.0, 3.5, -3.0)
				var base2 := hero_pos() - from2
				for k in range(-1, 2):
					world.shoot(from2, base2.rotated(Vector3.UP, 0.22 * float(k)).normalized(), 15.0, float(spec["dmg"]) * 0.4, 0.9, Color(0.2, 0.9, 0.8), 1.1, self)
			if st_t >= 8.0:
				_beat = 0.0
				if _arm_regrow < 2:
					_arm_regrow += 1
					_spawn_arms(2 + _arm_regrow)
					Game.say("THE ARMS GROW BACK", 1.8)
				else:
					open_t = 99.0
				_go(&"guard")


# --- HIVE WARDEN ----------------------------------------------------------------------------------------------------------------------------------

func _tick_warden(dt: float, d: float) -> void:
	var rl := _alive_relays()
	if shield_on and rl == 0:
		shield_on = false
		_shield = 0.0
		open_t = 5.0
		open_k = 1.5
		inv_t = 0.0
		_go(&"stunned")
		Game.say("SHIELD DOWN", 2.0)
		FX.blast(global_position, 6.0, Color(0.3, 1.0, 0.9), 0.4, -1, 0.0, false)
		FX.shake(0.5)
	_shield = 1.0 if shield_on else 0.0
	_pulse_t -= dt
	_hint = "SHOOT THE GLOWING RELAYS" if shield_on else ("SHOOT IT NOW  THE SHIELD IS DOWN" if open_t > 0.0 else "JUMP THE PULSE  DODGE THE LANCE")
	var gy := TerrainHeight.height_at(position.x, position.z)
	ground = gy
	match state:
		&"idle", &"hover":
			state = &"hover"
			_orbit_a += dt * 0.35
			var h := hero_pos()
			var want := Vector2(lair.x + cos(_orbit_a) * 14.0, lair.z + sin(_orbit_a) * 14.0)
			var dir := want - Vector2(position.x, position.z)
			var mv := dir.normalized() * minf(dir.length(), float(spec["walk"]) * dt)
			position.x += mv.x
			position.z += mv.y
			_face(Vector2(h.x, h.z), dt, 2.0)
			alt = lerpf(alt, 5.0 + 1.0 * sin(_orbit_a * 3.0), clampf(2.0 * dt, 0.0, 1.0))
			position.y = gy + alt
			_play(&"fly", 0.7)
			if cool <= 0.0 and d < 55.0 and d > 7.0:
				_aim = hero_pos()
				world.fx.line(global_position, _aim + (_aim - global_position).normalized() * 12.0, float(spec["windup"]) * _aggr_k(), Color(0.3, 1.0, 0.9))
				_go(&"lance")
			elif _pulse_t <= 0.0 and d < 22.0:
				_pulse_t = (7.5 if phase_i == 1 else 5.0) * _aggr_k()
				world.fx.ring(Vector3(position.x, gy + 0.1, position.z), 13.0, 1.5 * _aggr_k(), Color(0.3, 1.0, 0.9))
				_go(&"pulse")
		&"lance":
			_face(Vector2(_aim.x, _aim.z), dt, 4.0)
			_pulse = clampf(st_t / (float(spec["windup"]) * _aggr_k()), 0.0, 1.0)
			if st_t >= float(spec["windup"]) * _aggr_k():
				var from := global_position
				var dir2 := (_aim - from).normalized()
				var to := from + dir2 * 60.0
				FX.tracer(from, to, Color(0.3, 1.0, 0.9))
				Sfx.play_at(&"shot_rail", from, -3.0, 0.8)
				var h2 := hero_pos()
				var seg := WorldSteps.seg_dist(from, to, h2)
				if seg < 1.5:
					attacks_done += 1
					_hurt_hero(float(spec["dmg"]))
				cool = float(spec["cool"]) * _aggr_k()
				_go(&"hover")
		&"pulse":
			_play(&"idle", 1.0)
			if st_t >= 1.5 * _aggr_k():
				FX.blast(Vector3(position.x, gy + 0.4, position.z), 6.0, Color(0.3, 1.0, 0.9), 0.4, -1, 0.0, false)
				FX.shake(0.4)
				Sfx.play_at(&"verb_slam", global_position, -2.0, 0.8)
				var h3 := hero_pos()
				if Vector2(h3.x - position.x, h3.z - position.z).length() < 13.0 and not _hero_airborne():
					attacks_done += 1
					_hurt_hero(float(spec["dmg"]) * 0.8)
					world.knock_hero(Vector3(h3.x - position.x, 0.0, h3.z - position.z).normalized() * 8.0 + Vector3.UP * 4.0)
				_go(&"hover")
		&"stunned":
			_play(&"idle", 0.4)
			alt = lerpf(alt, 1.5, clampf(3.0 * dt, 0.0, 1.0))
			position.y = gy + alt
			_beat = 1.0
			if st_t >= 5.0:
				_beat = 0.0
				_go(&"hover")
