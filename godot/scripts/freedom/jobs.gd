class_name Jobs
extends Node
## Open-world activities that are simply there on the street (no menu): STREET RACE (magenta), TAXI FARE (amber), DELIVERY (green), BOUNTY (red) markers on junctions across the whole
## map and six STUNT JUMP ramps (cyan) with a landing ring. Slow down on a marker and the job starts by itself (race and taxi need a vehicle), the next goal is a tall beam and a diamond on
## the minimap, the reward is credits (Progress.add_credits). A race is a four-gate loop for time, a fare / delivery goes to a far junction against a clock, a bounty is one tough Vael
## operative somewhere 55-100 m from the marker, a stunt jump is a ramp taken fast in any vehicle (or on foot with a sprint and a QUANTUM GLIDE) that lands in the ring.
## Visuals: ONE MultiMesh of beams for every marker and landing ring, ONE for the ramps, ONE pooled beam for the live goal (3 draw calls in all). No physics bodies: a ramp lifts the
## vehicle model along its slope and the flight is a scripted arc (the car physics stays 2D). Ticks only while Game.is_playing() and outside interiors.

signal started(kind: StringName)
signal finished(kind: StringName, success: bool, credits: int)
signal stunt_done(ramp: int, credits: int)

var save_path := "user://freedom.cfg"
var active: StringName = &""
var spot := 0
var elapsed := 0.0
var limit := 0.0
var gate_i := 0
var goal := Vector3.INF
var prompt := ""
var done := {&"race": 0, &"taxi": 0, &"delivery": 0, &"bounty": 0}      ## completed jobs this profile (tests wait on these)
var failed := 0
var credits_paid := 0
var stunts: Dictionary = {}                                             ## ramp index -> best landing distance error (m), present = done
var stunt_attempts := 0
var best_race: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var auto_start := true
var _dwell := 0.0
var _cool := 0.0
var _acc := 0.0
var _away := 0.0
var _dist := 0.0
var _gates: Array[Vector3] = []
var _target: Drone
var _mmi: MultiMeshInstance3D
var _ramps_mmi: MultiMeshInstance3D
var _goal_node: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _near_kind: StringName = &""
var _near_k := -1
var _marker_pos: Array[Dictionary] = []                                 ## {kind, k, pos}
# stunt state
var _air_car: Vehicle
var _air_t := 0.0
var _air_T := 1.0
var _air_ramp := -1
var _lifted: Vehicle
var _hero_air := -1
var _hero_t := 0.0
var _hero_cool := 0.0
var _ramp_cache: Array[Dictionary] = []                                 ## FreedomData.ramp(i) for every ramp (the tick reads them every frame)


func _ready() -> void:
	name = "Jobs"
	add_to_group(&"jobs")
	for i in FreedomData.RAMPS.size():
		_ramp_cache.append(FreedomData.ramp(i))
	_build_markers()
	_build_ramps()
	_load()
	Game.player_died.connect(func() -> void: stop(false, "", false))
	Game.respawn.connect(reset_runtime)
	Game.new_game.connect(reset_runtime)


func reset_runtime() -> void:
	stop(false, "", false)
	_cool = 0.0
	_cancel_air()


func marker_count() -> int:
	return _marker_pos.size()


## Position of every marker as {kind, k, pos} (tests, the map).
func marker_list() -> Array[Dictionary]:
	return _marker_pos


func nearest_marker(pos: Vector3, within: float) -> Dictionary:
	var best := {}
	var bd := within
	for m in _marker_pos:
		var d := Vector2((m["pos"] as Vector3).x - pos.x, (m["pos"] as Vector3).z - pos.z).length()
		if d < bd:
			bd = d
			best = m
	return best


## Minimap markers: {pos, color, radius, goal}. The live goal always, idle markers only within `near` metres of the player.
func markers(near := 260.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if active != &"" and goal != Vector3.INF:
		out.append({"pos": goal, "color": FreedomData.COLORS[active], "radius": FreedomData.GATE_RADIUS, "goal": true})
	var p := Game.player
	if not is_instance_valid(p):
		return out
	var pp := p.global_position
	for m in _marker_pos:
		var mp: Vector3 = m["pos"]
		if Vector2(mp.x - pp.x, mp.z - pp.z).length() <= near:
			out.append({"pos": mp, "color": FreedomData.COLORS[m["kind"]], "radius": FreedomData.ENTRY_RADIUS, "goal": false})
	for i in FreedomData.RAMPS.size():
		var r := FreedomData.ramp(i)
		var rp: Vector3 = r["land"]
		if Vector2(rp.x - pp.x, rp.z - pp.z).length() <= near:
			out.append({"pos": rp, "color": FreedomData.COLORS[FreedomData.STUNT], "radius": FreedomData.LAND_RADIUS, "goal": false})
	return out


# --- ticking ------------------------------------------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if not Game.is_playing() or InteriorGameplay.active:
		prompt = ""
		return
	_cool = maxf(_cool - dt, 0.0)
	_hero_cool = maxf(_hero_cool - dt, 0.0)
	_tick_ramps(dt)
	_acc += dt
	if _acc < 0.1:
		return
	var step := _acc
	_acc = 0.0
	if active == &"":
		_tick_idle(step)
	else:
		_tick_active(step)
	_pulse_goal()


func _driven() -> Vehicle:
	if is_instance_valid(Game.vehicles):
		var d: Variant = Game.vehicles.get("driven")
		if d is Vehicle and is_instance_valid(d):
			return d as Vehicle
	return null


func _player_speed(drv: Vehicle) -> float:
	if drv != null:
		return absf(drv.speed)
	var p := Game.player as CharacterBody3D
	return Vector2(p.velocity.x, p.velocity.z).length() if p != null else 0.0


func _tick_idle(step: float) -> void:
	prompt = ""
	var p := Game.player
	if not is_instance_valid(p):
		return
	var m := nearest_marker(p.global_position, FreedomData.ENTRY_RADIUS)
	if m.is_empty():
		_dwell = 0.0
		_near_kind = &""
		_near_k = -1
		return
	var kind: StringName = m["kind"]
	_near_kind = kind
	_near_k = int(m["k"])
	var drv := _driven()
	var name_s: String = FreedomData.NAMES[kind]
	if (kind == FreedomData.RACE or kind == FreedomData.TAXI) and drv == null:
		prompt = name_s + "  GET IN A VEHICLE"
		_dwell = 0.0
		return
	if _cool > 0.0 or not auto_start:
		return
	if _player_speed(drv) > FreedomData.ENTRY_SPEED:
		prompt = name_s + "  SLOW DOWN"
		_dwell = 0.0
		return
	prompt = name_s
	_dwell += step
	if _dwell >= FreedomData.DWELL:
		start(kind, _near_k)


## Starts job `k` of `kind` now (tests and the auto start). False when one is running or the preconditions fail.
func start(kind: StringName, k: int) -> bool:
	if active != &"" or not FreedomData.SPOTS.has(kind) or k < 0 or k >= (FreedomData.SPOTS[kind] as Array).size():
		return false
	var origin := FreedomData.marker_pos(kind, k)
	_gates.clear()
	_away = 0.0
	_dwell = 0.0
	match kind:
		FreedomData.RACE:
			_gates = FreedomData.race_gates(k)
			goal = _gates[0]
			limit = FreedomData.time_limit(kind, 0.0)
			Game.say("STREET RACE  %d GATES" % _gates.size(), 1.6)
		FreedomData.TAXI, FreedomData.DELIVERY:
			goal = FreedomData.destination(kind, k)
			_dist = Vector2(goal.x - origin.x, goal.z - origin.z).length()
			limit = FreedomData.time_limit(kind, _dist)
			Game.say(("FARE ABOARD  %d M" if kind == FreedomData.TAXI else "PACKAGE  %d M") % int(_dist), 1.6)
		FreedomData.BOUNTY:
			if not _spawn_target(origin):
				Game.say("NO TARGET HERE", 1.2)
				_cool = 2.0
				return false
			limit = FreedomData.BOUNTY_TIME
			Game.say("BOUNTY  FIND THE TARGET", 1.6)
	active = kind
	spot = k
	elapsed = 0.0
	gate_i = 0
	Sfx.play(&"pickup", -4.0)
	_show_goal()
	started.emit(kind)
	return true


func _spawn_target(origin: Vector3) -> bool:
	var em := Game.enemies as EnemyManager
	var w := Game.world
	if em == null or not is_instance_valid(w):
		return false
	var at: Vector3 = w.call(&"road_point_near", origin, FreedomData.BOUNTY_MIN, FreedomData.BOUNTY_MAX) if w.has_method(&"road_point_near") else Vector3.INF
	if at == Vector3.INF:
		return false
	var d := em.spawn(&"operative", Vector3(at.x, 0.3, at.z), false)
	if d == null:
		return false
	d.max_hp *= FreedomData.BOUNTY_HP
	d.hp = d.max_hp
	_target = d
	goal = d.global_position
	return true


func _tick_active(step: float) -> void:
	elapsed += step
	var p := Game.player
	if not is_instance_valid(p):
		return
	var pos := p.global_position
	var drv := _driven()
	var flat := Vector2(pos.x - goal.x, pos.z - goal.z).length() if goal != Vector3.INF else INF
	match active:
		FreedomData.RACE, FreedomData.TAXI:
			if drv == null:
				_away += step
				if _away > FreedomData.LEAVE_GRACE:
					stop(false, "LEFT THE VEHICLE")
					return
			else:
				_away = 0.0
	match active:
		FreedomData.RACE:
			if flat < FreedomData.GATE_RADIUS and drv != null:
				gate_i += 1
				Sfx.play(&"pickup", -6.0, 1.3)
				if gate_i >= _gates.size():
					var t := elapsed
					var n := FreedomData.reward_race(t, _gates.size())
					if best_race[spot] <= 0.0 or t < best_race[spot]:
						best_race[spot] = t
						_save()
					_finish(true, n, "RACE WON  %.1f S" % t)
					return
				goal = _gates[gate_i]
				Game.say("GATE %d / %d" % [gate_i, _gates.size()], 0.8)
				_show_goal()
		FreedomData.TAXI:
			if flat < FreedomData.ARRIVE_RADIUS and _player_speed(drv) < FreedomData.ARRIVE_SPEED and drv != null:
				var left := int(maxf(limit - elapsed, 0.0))
				_finish(true, FreedomData.TAXI_BASE + int(_dist / 100.0 * FreedomData.TAXI_PER_100M) + left * FreedomData.TAXI_BONUS, "FARE DELIVERED")
				return
		FreedomData.DELIVERY:
			if flat < 5.0:
				_finish(true, FreedomData.DELIVERY_BASE + int(_dist / 100.0 * FreedomData.DELIVERY_PER_100M), "DELIVERED")
				return
		FreedomData.BOUNTY:
			if _target == null or not is_instance_valid(_target):
				stop(false, "TARGET LOST")
				return
			if _target.dead or not _target.active:
				if _target.dead:
					_finish(true, FreedomData.BOUNTY_PAY, "BOUNTY COLLECTED")
				else:
					stop(false, "TARGET LOST")
				return
			goal = _target.global_position
	if elapsed > limit:
		stop(false, "TIME UP")


func _finish(success: bool, credits: int, text: String) -> void:
	var kind := active
	if success:
		done[kind] = int(done.get(kind, 0)) + 1
		credits_paid += credits
		_pay(credits)
		Game.say("%s  +%d" % [text, credits], 2.0)
		FX.burst(Game.player.global_position + Vector3(0.0, 1.0, 0.0), FreedomData.COLORS[kind], 14, 5.0, 0.5, 2.0)
	_clear_active()
	_cool = FreedomData.COOLDOWN
	finished.emit(kind, success, credits)


## Ends the running job as failed (message `why`, nothing when ""), no reward.
func stop(announce := true, why := "", cooldown := true) -> void:
	if active == &"":
		return
	var kind := active
	failed += 1
	if announce and why != "":
		Game.say("%s  %s" % [FreedomData.NAMES[kind], why], 1.8)
	_clear_active()
	if cooldown:
		_cool = FreedomData.COOLDOWN
	finished.emit(kind, false, 0)


func _clear_active() -> void:
	active = &""
	goal = Vector3.INF
	_gates.clear()
	if _target != null and is_instance_valid(_target) and _target.active and not _target.dead:
		var em := Game.enemies as EnemyManager
		if em != null:
			em.release(_target)
	_target = null
	if _goal_node != null:
		_goal_node.visible = false


func _pay(n: int) -> void:
	if Game.progress != null and Game.progress.has_method(&"add_credits"):
		Game.progress.call(&"add_credits", n)
	else:
		Game.add_score(n)


# --- stunt jumps ----------------------------------------------------------------------------------------------------------------

func _tick_ramps(dt: float) -> void:
	if _air_car != null:
		if not is_instance_valid(_air_car) or _air_car.dead or not _air_car.active:
			_cancel_air()
		else:
			_air_t += dt
			var k := clampf(_air_t / _air_T, 0.0, 1.0)
			_set_lift(_air_car, 4.0 * FreedomData.JUMP_APEX * k * (1.0 - k))
			if k >= 1.0:
				_land_car()
		return
	var p := Game.player as Player
	if p == null:
		return
	if _hero_air >= 0:
		_tick_hero_air(p, dt)
		return
	var car := _driven()
	var q := car.global_position if car != null else p.global_position
	var on_any := false
	for i in _ramp_cache.size():
		var r := _ramp_cache[i]
		var dir: Vector3 = r["dir"]
		var local := q - (r["pos"] as Vector3)
		var along := local.dot(dir)
		var across := absf(local.dot(Vector3(-dir.z, 0.0, dir.x)))
		if along < 0.0 or along > FreedomData.RAMP_LEN or across > FreedomData.RAMP_WID * 0.5 + 0.8:
			continue
		on_any = true
		if car != null:
			_set_lift(car, FreedomData.RAMP_H * along / FreedomData.RAMP_LEN)
			_lifted = car
			if along >= FreedomData.RAMP_LEN - 1.6 and car.speed >= FreedomData.STUNT_MIN_SPEED and car.forward().dot(dir) > 0.7:
				_launch_car(car, i)
		elif _hero_cool <= 0.0 and along >= FreedomData.RAMP_LEN - 2.2 and p.is_on_floor():
			var flat_v := Vector2(p.velocity.x, p.velocity.z)
			if flat_v.length() > 4.0 and Vector3(flat_v.x, 0.0, flat_v.y).normalized().dot(dir) > 0.6:
				_launch_hero(p, i, dir)
		break
	if not on_any and _lifted != null:
		if is_instance_valid(_lifted):
			_set_lift(_lifted, 0.0)
		_lifted = null


func _launch_car(car: Vehicle, i: int) -> void:
	_air_car = car
	_air_ramp = i
	_air_t = 0.0
	_air_T = clampf(FreedomData.JUMP_DIST / maxf(car.speed, 1.0), 0.9, 2.2)
	stunt_attempts += 1
	FX.burst(car.global_position + Vector3(0.0, 0.5, 0.0), FreedomData.COLORS[FreedomData.STUNT], 10, 5.0, 0.4, 1.0)
	Sfx.play(&"blink", -6.0, 1.2)
	Game.say("STUNT JUMP", 0.9)


func _land_car() -> void:
	var car := _air_car
	var i := _air_ramp
	_set_lift(car, 0.0)
	_air_car = null
	_lifted = null
	var land: Vector3 = _ramp_cache[i]["land"]
	var err := Vector2(car.global_position.x - land.x, car.global_position.z - land.z).length()
	FX.burst(car.global_position + Vector3(0.0, 0.3, 0.0), Color(0.7, 0.7, 0.75), 8, 4.0, 0.5, 2.0)
	FX.shake(0.3)
	Sfx.play_at(&"hit", car.global_position, -6.0)
	_stunt_result(i, err <= FreedomData.LAND_RADIUS, err)
	_air_ramp = -1


func _launch_hero(p: Player, i: int, dir: Vector3) -> void:
	_hero_air = i
	_hero_t = 0.0
	_hero_cool = 2.0
	p.velocity = dir * FreedomData.HERO_LAUNCH + Vector3.UP * FreedomData.HERO_LIFT
	stunt_attempts += 1
	FX.burst(p.global_position + Vector3(0.0, 0.5, 0.0), FreedomData.COLORS[FreedomData.STUNT], 10, 5.0, 0.4, 1.0)
	Sfx.play(&"blink", -6.0, 1.2)
	Game.say("STUNT JUMP", 0.9)


func _tick_hero_air(p: Player, dt: float) -> void:
	_hero_t += dt
	var dir: Vector3 = _ramp_cache[_hero_air]["dir"]
	var bursting: bool = p.verbs != null and p.verbs.bursting
	if _hero_t < 1.1 and not bursting:
		p.velocity.x = dir.x * FreedomData.HERO_LAUNCH
		p.velocity.z = dir.z * FreedomData.HERO_LAUNCH
	if _hero_t > 0.35 and p.is_on_floor():
		var land: Vector3 = _ramp_cache[_hero_air]["land"]
		var err := Vector2(p.global_position.x - land.x, p.global_position.z - land.z).length()
		var i := _hero_air
		_hero_air = -1
		_stunt_result(i, err <= FreedomData.HERO_LAND_RADIUS, err)
	elif _hero_t > 6.0:
		_hero_air = -1


func _stunt_result(i: int, ok: bool, err: float) -> void:
	if not ok:
		Game.say("STUNT JUMP  MISSED THE RING", 1.2)
		return
	var first := not stunts.has(i)
	var n := FreedomData.STUNT_PAY if first else FreedomData.STUNT_REPEAT
	stunts[i] = minf(float(stunts.get(i, 999.0)), err)
	credits_paid += n
	_pay(n)
	Game.say("STUNT JUMP  %d / %d  +%d" % [stunts.size(), FreedomData.RAMPS.size(), n], 1.8)
	_save()
	stunt_done.emit(i, n)


func _set_lift(car: Vehicle, h: float) -> void:
	if car == null or car.visual == null or car.visual.model == null:
		return
	car.visual.model.position.y = h + (car.bob if car.cls == &"hover" else 0.0)


func _cancel_air() -> void:
	if _air_car != null and is_instance_valid(_air_car):
		_set_lift(_air_car, 0.0)
	_air_car = null
	_air_ramp = -1
	_hero_air = -1
	if _lifted != null and is_instance_valid(_lifted):
		_set_lift(_lifted, 0.0)
	_lifted = null


func in_air() -> bool:
	return _air_car != null or _hero_air >= 0


# --- visuals ----------------------------------------------------------------------------------------------------------------------

static func beam_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 14
	var r0 := 2.3
	var r1 := 1.5
	var h := 18.0
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var b0 := Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
		var b1 := Vector3(cos(a1) * r0, 0.0, sin(a1) * r0)
		var t0 := Vector3(cos(a0) * r1, h, sin(a0) * r1)
		var t1 := Vector3(cos(a1) * r1, h, sin(a1) * r1)
		var lo := Color(1, 1, 1, 0.34)
		var hi := Color(1, 1, 1, 0.0)
		for v: Array in [[b0, lo], [t0, hi], [b1, lo], [b1, lo], [t0, hi], [t1, hi]]:
			st.set_color(v[1])
			st.add_vertex(v[0])
	var ro := 3.6
	var ri := 2.4
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var c := Color(1, 1, 1, 0.6)
		for v: Vector3 in [Vector3(cos(a0) * ri, 0.07, sin(a0) * ri), Vector3(cos(a0) * ro, 0.07, sin(a0) * ro), Vector3(cos(a1) * ri, 0.07, sin(a1) * ri),
				Vector3(cos(a1) * ri, 0.07, sin(a1) * ri), Vector3(cos(a0) * ro, 0.07, sin(a0) * ro), Vector3(cos(a1) * ro, 0.07, sin(a1) * ro)]:
			st.set_color(c)
			st.add_vertex(v)
	return st.commit()


static func ramp_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := FreedomData.RAMP_WID * 0.5
	var l := FreedomData.RAMP_LEN
	var h := FreedomData.RAMP_H
	# local frame: the ramp rises along -Z (yaw 0 = direction -Z), low end at z = 0
	var a := Vector3(-hw, 0.0, 0.0)
	var b := Vector3(hw, 0.0, 0.0)
	var c := Vector3(hw, h, -l)
	var d := Vector3(-hw, h, -l)
	var e := Vector3(hw, 0.0, -l)
	var f := Vector3(-hw, 0.0, -l)
	var top := Color(0.30, 0.34, 0.38)
	var side := Color(0.14, 0.16, 0.19)
	var edge := Color(0.3, 0.9, 1.0)
	var quads: Array = [
		[a, b, c, d, top, Vector3(0, 0.6, 0.8)],                                  # slope
		[b, e, c, c, side, Vector3.RIGHT], [f, a, d, d, side, Vector3.LEFT],         # side triangles (degenerate quad = triangle)
		[f, e, c, d, side, Vector3(0, 0, -1)],                                    # back
	]
	for q: Array in quads:
		var qa: Vector3 = q[0]
		var qb: Vector3 = q[1]
		var qc: Vector3 = q[2]
		var qd: Vector3 = q[3]
		st.set_color(q[4])
		st.set_normal(q[5])
		for v: Vector3 in [qa, qb, qc, qa, qc, qd]:
			st.add_vertex(v)
	# glowing edge strips along both top edges
	for sx: float in [-1.0, 1.0]:
		var x0 := hw * sx
		var x1 := (hw - 0.35) * sx
		st.set_color(edge)
		st.set_normal(Vector3.UP)
		for v: Vector3 in [Vector3(x0, 0.03, 0.0), Vector3(x1, 0.03, 0.0), Vector3(x1, h + 0.03, -l), Vector3(x0, 0.03, 0.0), Vector3(x1, h + 0.03, -l), Vector3(x0, h + 0.03, -l)]:
			st.add_vertex(v)
	return st.commit()


func _build_markers() -> void:
	_marker_pos.clear()
	for kind: StringName in FreedomData.KINDS:
		var arr: Array = FreedomData.SPOTS[kind]
		for k in arr.size():
			_marker_pos.append({"kind": kind, "k": k, "pos": FreedomData.marker_pos(kind, k)})
	var total := _marker_pos.size() + FreedomData.RAMPS.size()
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.vertex_color_use_as_albedo = true
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var mesh := beam_mesh()
	mesh.surface_set_material(0, _beam_mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = total
	var i := 0
	for m in _marker_pos:
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1.0, 0.55, 1.0)), m["pos"]))
		var c: Color = FreedomData.COLORS[m["kind"]]
		mm.set_instance_color(i, Color(c.r, c.g, c.b, 1.0))
		i += 1
	for r in FreedomData.RAMPS.size():
		var land: Vector3 = FreedomData.ramp(r)["land"]
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1.7, 0.3, 1.7)), land))
		var c2: Color = FreedomData.COLORS[FreedomData.STUNT]
		mm.set_instance_color(i, Color(c2.r, c2.g, c2.b, 0.7))
		i += 1
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "JobMarkers"
	_mmi.multimesh = mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.custom_aabb = AABB(Vector3(-1300, -2, -1300), Vector3(2600, 20, 2600))
	_mmi.top_level = true
	add_child(_mmi)
	_goal_node = MeshInstance3D.new()
	_goal_node.name = "JobGoal"
	_goal_node.mesh = mesh
	_goal_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_goal_node.top_level = true
	_goal_node.visible = false
	add_child(_goal_node)


func _build_ramps() -> void:
	var n := FreedomData.RAMPS.size()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.55
	mat.metallic = 0.4
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(0.05, 0.22, 0.28)
	var mesh := ramp_mesh()
	mesh.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = n
	for i in n:
		var r := FreedomData.ramp(i)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(r["yaw"])), r["pos"]))
	_ramps_mmi = MultiMeshInstance3D.new()
	_ramps_mmi.name = "StuntRamps"
	_ramps_mmi.multimesh = mm
	_ramps_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ramps_mmi.custom_aabb = AABB(Vector3(-1300, -2, -1300), Vector3(2600, 20, 2600))
	_ramps_mmi.top_level = true
	add_child(_ramps_mmi)


func _show_goal() -> void:
	if _goal_node == null or goal == Vector3.INF:
		return
	_goal_node.visible = true
	_goal_node.global_position = goal
	var c: Color = FreedomData.COLORS[active] if active != &"" else Color.WHITE
	var m := _goal_node.material_override as StandardMaterial3D
	if m == null:
		m = _beam_mat.duplicate() as StandardMaterial3D
		_goal_node.material_override = m
	m.albedo_color = Color(c.r, c.g, c.b, 1.0)


func _pulse_goal() -> void:
	if _goal_node == null or not _goal_node.visible or goal == Vector3.INF:
		return
	_goal_node.global_position = goal
	var k := 1.0 + 0.12 * sin(float(Time.get_ticks_msec()) * 0.006)
	_goal_node.scale = Vector3(k, 1.0, k)


# --- save ---------------------------------------------------------------------------------------------------------------------------

func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(save_path) != OK:
		return
	for i in best_race.size():
		best_race[i] = float(cf.get_value("race", str(i), 0.0))
	for i in FreedomData.RAMPS.size():
		if cf.has_section_key("stunt", str(i)):
			stunts[i] = float(cf.get_value("stunt", str(i), 0.0))


func _save() -> void:
	var cf := ConfigFile.new()
	for i in best_race.size():
		if best_race[i] > 0.0:
			cf.set_value("race", str(i), best_race[i])
	for i: int in stunts:
		cf.set_value("stunt", str(i), float(stunts[i]))
	cf.save(save_path)
