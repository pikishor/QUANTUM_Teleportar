class_name ChaseRunner
extends Node
## Vehicle chase set pieces (Game.missions.chases, wave 68): six scripted scenarios (ChaseScripts) built from the game's own vehicles, patrols and weapons: pursue a convoy, escape a roadblock net,
## chase a hover vehicle (ROOFTOP TO STREET), race through closing gates, escort an allied car under fire, duel a boss patrol vehicle. Data and rubber-banding live in chase_scripts.gd.
## A run lays its route along one straight street toward the city centre (axis, lane and coordinate from the player's position), puts the player in a car (his own, or a sport car when
## he is on foot), saves a checkpoint at each fraction of progress (target hit points, gate number, escort distance), and after a failure retries from the last checkpoint after
## ChaseScripts.RETRY_DELAY s, at most MAX_TRIES attempts. It simulates only while Game.state == play; tick() is callable by tests.
## API: can_start(id) · start(id) · abort(reason) · retry() · tick(dt) · hud_line() · waypoint() · progress_frac() · state (&"idle" running retry) · result (last run)

signal started(id: StringName)
signal checkpoint_reached(id: StringName, index: int)
signal failed(id: StringName, reason: String, will_retry: bool)
signal finished(id: StringName, ok: bool)

var id: StringName = &""
var def: Dictionary = {}
var state: StringName = &"idle"
var clock := 0.0                       ## s since this attempt began
var tries := 0                         ## attempts started in this run
var prog := 0.0                        ## 0..1 progress of the current attempt
var cp_index := 0                      ## checkpoints saved so far
var cp: Dictionary = {}                ## the last checkpoint: {prog, gate, travelled, hp_frac}
var result: Dictionary = {}            ## {id, ok, reason, reward, tries, time} of the last run
var target: Vehicle                    ## pursue: the fleeing car · escort: the allied car · duel: the boss
var guards: Array[Vehicle] = []        ## pursue: the rest of the convoy
var chasers: Array[Vehicle] = []       ## escape / escort: patrol vehicles
var gate_i := 0
var gate_t := 0.0
var retry_t := 0.0
var fail_reason := ""

var _axis := 0
var _dir := 1
var _road_i := 0
var _along0 := 0.0
var _far_t := 0.0
var _awake := false
var _alive_t := 0.0
var _markers: Array[MeshInstance3D] = []
var _heat_prev := 0.0


func _ready() -> void:
	add_to_group(&"chases")
	set_physics_process(true)
	Game.new_game.connect(abort.bind("RESET"))
	Game.respawn.connect(_on_respawn)


func _exit_tree() -> void:
	_clear_cars()


# --- access -------------------------------------------------------------------------------------------------------------------

func is_running() -> bool:
	return state != &"idle"


func can_start(cid: StringName) -> bool:
	if is_running() or not ChaseScripts.DEFS.has(cid) or not is_instance_valid(Game.player) or not is_instance_valid(Game.vehicles):
		return false
	var m := Game.missions as Missions
	if m != null:
		if m.campaign != null and m.campaign.is_running():
			return false
		if m.sides != null and m.sides.active:
			return false
		if m.contracts != null and bool(m.contracts.is_active()):
			return false
	return true


func start(cid: StringName) -> bool:
	if not can_start(cid):
		return false
	id = cid
	def = ChaseScripts.def(cid)
	tries = 0
	cp_index = 0
	cp = {"prog": 0.0, "gate": 0, "travelled": 0.0, "hp_frac": 0.0}
	result = {}
	_heat_prev = Game.heat
	_pick_route()
	started.emit(cid)
	return _begin_attempt()


func abort(reason := "ABANDONED") -> void:
	if state == &"idle":
		return
	_end(false, reason)


func retry() -> bool:
	if state != &"retry":
		return false
	return _begin_attempt()


func _on_respawn() -> void:
	if state == &"running":
		_fail("DOWN")


# --- route ----------------------------------------------------------------------------------------------------------------------

## One straight street toward the centre of the city: the axis is the player's dominant street, the direction runs toward 0 so the whole route fits.
func _pick_route() -> void:
	var pp := Game.player.global_position
	_axis = 0 if absf(pp.z - VehicleSpecs.road_center(VehicleSpecs.road_index(pp.z))) <= absf(pp.x - VehicleSpecs.road_center(VehicleSpecs.road_index(pp.x))) else 1
	var perp := pp.z if _axis == 0 else pp.x
	_road_i = VehicleSpecs.road_index(perp)
	_along0 = clampf(pp.x if _axis == 0 else pp.z, -ChaseScripts.MAX_ALONG, ChaseScripts.MAX_ALONG)
	_dir = -1 if _along0 > 0.0 else 1
	if absf(_along0) < 40.0:
		_dir = 1


func _line() -> float:
	return VehicleSpecs.road_center(_road_i) + VehicleSpecs.lane_offset(_axis, _dir, Game.LANE)


## Point `s` metres along the route from the start (lane centre, y 0).
func route_point(s: float, lateral := 0.0) -> Vector3:
	var a := _along0 + float(_dir) * s
	var l := _line() + lateral
	return Vector3(a, 0.0, l) if _axis == 0 else Vector3(l, 0.0, a)


func _along_of(p: Vector3) -> float:
	return (p.x if _axis == 0 else p.z)


## Metres travelled along the route by a position (negative behind the start).
func _travelled(p: Vector3) -> float:
	return (_along_of(p) - _along0) * float(_dir)


func _heading() -> float:
	return VehicleSpecs.heading_for(_axis, _dir)


# --- attempts -------------------------------------------------------------------------------------------------------------------

func _begin_attempt() -> bool:
	_clear_cars()
	tries += 1
	clock = 0.0
	retry_t = 0.0
	fail_reason = ""
	_far_t = 0.0
	_awake = false
	_alive_t = 0.0
	prog = float(cp["prog"])
	gate_i = int(cp["gate"])
	var mode := StringName(def["mode"])
	var s0 := 0.0
	if mode == &"gate":
		s0 = float(def["gate_gap"]) * float(gate_i) - 22.0 if gate_i > 0 else 0.0
	elif mode == &"escort":
		s0 = float(cp["travelled"])
	var car := _player_car(route_point(s0))
	if car == null:
		_end(false, "NO CAR")
		return false
	state = &"running"
	Game.heat = maxf(Game.heat, float(def["heat"]))
	match mode:
		&"pursue": _setup_pursue()
		&"escape": _setup_escape()
		&"gate": _setup_gate()
		&"escort": _setup_escort(float(cp["travelled"]))
		&"duel": _setup_duel()
	_show_markers()
	Game.say("%s%s" % [ChaseScripts.title(id), "" if tries <= 1 else "   RETRY %d/%d" % [tries, ChaseScripts.MAX_TRIES]], 3.0)
	return true


func _fail(reason: String) -> void:
	if state != &"running":
		return
	fail_reason = reason
	var again := tries < ChaseScripts.MAX_TRIES
	failed.emit(id, reason, again)
	if not again:
		_end(false, reason)
		return
	state = &"retry"
	retry_t = ChaseScripts.RETRY_DELAY
	_hide_markers()
	Game.say("%s   RETRY SOON" % reason, 2.4)


func _end(ok: bool, reason: String) -> void:
	var cid := id
	var left := 0.0
	var tl := float(def.get("time", 0.0))
	if tl > 0.0:
		left = clampf(1.0 - clock / tl, 0.0, 1.0)
	var pay := 0
	var prog_node := Game.progress as Progress
	if ok:
		pay = ChaseScripts.reward(cid, left)
		if prog_node != null:
			prog_node.add_credits(pay)
			prog_node.add_reputation(int(def["rep"]))
	elif prog_node != null and reason != "RESET":
		prog_node.add_reputation(-1)
	result = {"id": cid, "ok": ok, "reason": reason, "reward": pay, "tries": tries, "time": clock}
	state = &"idle"
	_clear_cars(not ok)
	_hide_markers()
	Game.heat = minf(Game.heat, maxf(_heat_prev, 0.0)) if ok else 0.0
	id = &""
	Game.say(("%s COMPLETE  +%d" % [ChaseScripts.title(cid), pay]) if ok else ("%s FAILED  %s" % [ChaseScripts.title(cid), reason]), 4.0)
	finished.emit(cid, ok)


func _save_checkpoint(extra := {}) -> void:
	cp = {"prog": prog, "gate": gate_i, "travelled": float(extra.get("travelled", 0.0)), "hp_frac": float(extra.get("hp_frac", 0.0))}
	cp_index += 1
	Sfx.play(&"ui_contract_accept")
	Game.say("CHECKPOINT %d" % cp_index, 1.6)
	checkpoint_reached.emit(id, cp_index)


# --- cars -----------------------------------------------------------------------------------------------------------------------

func _slot() -> void:
	var vm := Game.vehicles as VehicleManager
	if vm.list.size() >= vm.cap():
		vm.call(&"_free_slot")


func _hold(v: Vehicle) -> void:
	v.set_meta(&"hold", true)


func _spawn_traffic(kind: StringName, s: float, cruise: float, hp: float) -> Vehicle:
	var vm := Game.vehicles as VehicleManager
	_slot()
	var v := vm.spawn_traffic(kind, _axis, _road_i, _dir, _along0 + float(_dir) * s)
	if v == null:
		return null
	v.max_hp = hp
	v.hp = hp
	v.ai_cruise = cruise
	_hold(v)
	return v


func _spawn_patrol(s: float, lateral: float, tactic: StringName, chasing: bool) -> Vehicle:
	var vm := Game.vehicles as VehicleManager
	_slot()
	var v := vm.spawn_parked(&"vael_patrol", route_point(s, lateral), _heading())
	if v == null:
		return null
	v.chasing = chasing
	v.tactic = tactic
	vm.patrols_spawned += 1
	_hold(v)
	return v


## The player's car, placed at `at` facing along the route: the one he drives, or a fresh sport car he is put into.
func _player_car(at: Vector3) -> Vehicle:
	var vm := Game.vehicles as VehicleManager
	var p := Game.player as Player
	var car := p.vehicle as Vehicle if p.vehicle is Vehicle else null
	if car == null:
		_slot()
		car = vm.spawn_parked(ChaseScripts.PLAYER_KIND, at, _heading())
		if car == null:
			return null
		vm.enter(car)
	else:
		car.global_position = Vector3(at.x, 0.0, at.z)
		car.heading = _heading()
		car.rotation = Vector3(0.0, _heading(), 0.0)
		car._heading_set = _heading()
		car.speed = 0.0
		car.vel = Vector3.ZERO
		car.hp = maxf(car.hp, car.max_hp * 0.6)
	_hold(car)
	return car


func _player_car_now() -> Vehicle:
	var p := Game.player as Player
	return p.vehicle as Vehicle if p != null and p.vehicle is Vehicle else null


func _clear_cars(release := true) -> void:
	var all: Array[Vehicle] = []
	if is_instance_valid(target):
		all.append(target)
	for v: Vehicle in guards:
		if is_instance_valid(v):
			all.append(v)
	for v: Vehicle in chasers:
		if is_instance_valid(v):
			all.append(v)
	var vm := Game.vehicles as VehicleManager
	for v: Vehicle in all:
		v.remove_meta(&"hold")
		v.max_hp = float(v.spec["hp"])           # pooled cars come back with their own hit points (the duel boss has several times)
		v.hp = minf(v.hp, v.max_hp)
		if release and vm != null and not v.driver_is_player and vm.list.has(v):
			vm.call(&"_release", v)             # a failed / restarted run clears its cars at once (no pool slots left behind)
		elif not v.dead:
			if v.patrol:
				v.chasing = false
			else:
				v.ai_stun = 3.0
	var pc := _player_car_now()
	if pc != null and pc.has_meta(&"hold"):
		pc.remove_meta(&"hold")
	target = null
	guards.clear()
	chasers.clear()


# --- setups ---------------------------------------------------------------------------------------------------------------------

func _setup_pursue() -> void:
	var t := _spawn_traffic(StringName(def["kind"]), float(def["gap"]), float(def["cruise"]), float(def["hp"]))
	if t == null:
		_end(false, "NO SPACE")
		return
	target = t
	t.hp = maxf(t.max_hp * (1.0 - float(cp["hp_frac"]) * (1.0 - ChaseScripts.DISABLE)), 1.0)
	for i in int(def["guards"]):
		var g := _spawn_traffic(&"sedan", float(def["gap"]) + 18.0 + 16.0 * float(i), float(def["cruise"]), float(def["hp"]))
		if g != null:
			guards.append(g)


func _setup_escape() -> void:
	var at := float(def["net_at"])
	if float(cp["prog"]) > 0.0:
		at = maxf(at - 40.0, 40.0)
	for i in int(def["net"]):
		var lat := (float(i) - float(int(def["net"]) - 1) * 0.5) * 6.0
		var v := _spawn_patrol(at + float(i % 2) * 5.0, lat, &"block", false)
		if v != null:
			chasers.append(v)


func _setup_gate() -> void:
	gate_t = _budget(gate_i)


func _setup_escort(travelled: float) -> void:
	var t := _spawn_traffic(StringName(def["kind"]), travelled + 16.0, float(def["cruise"]), float(def["hp"]))
	if t == null:
		_end(false, "NO SPACE")
		return
	target = t
	t.hp = t.max_hp * clampf(float(cp["hp_frac"]), 0.35, 1.0) if travelled > 0.0 else t.max_hp
	for i in int(def["chasers"]):
		var v := _spawn_patrol(travelled - 60.0 - 24.0 * float(i), float(i) * 4.0 - 2.0, &"ram", true)
		if v != null:
			chasers.append(v)


func _setup_duel() -> void:
	var v := _spawn_patrol(-float(def["gap"]), 0.0, &"ram", true)
	if v == null:
		_end(false, "NO SPACE")
		return
	var base := v.max_hp
	v.max_hp = base * float(def["hp_mult"])
	v.hp = maxf(v.max_hp * (1.0 - float(cp["prog"])), 1.0)
	target = v
	chasers.append(v)


func _budget(i: int) -> float:
	var b: Array = def["budget"]
	return float(b[clampi(i, 0, b.size() - 1)])


# --- ticking --------------------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state == &"idle" or Game.state != &"play" or not is_instance_valid(Game.player):
		return
	tick(delta)


func tick(delta: float) -> void:
	if state == &"idle":
		return
	if state == &"retry":
		retry_t -= delta
		if retry_t <= 0.0:
			retry()
		return
	if not is_instance_valid(Game.player):
		return
	clock += delta
	var limit := float(def["time"])
	if limit > 0.0 and clock >= limit:
		_fail("TIME UP")
		return
	if float(def["heat"]) > 0.0 and Game.heat < float(def["heat"]):
		Game.heat = float(def["heat"])
	var pc := _player_car_now()
	match StringName(def["mode"]):
		&"pursue": _tick_pursue(delta, pc)
		&"escape": _tick_escape(delta, pc)
		&"gate": _tick_gate(delta, pc)
		&"escort": _tick_escort(delta, pc)
		&"duel": _tick_duel(delta, pc)
	if state == &"running":
		_cap_chasers(pc)
		_move_markers()


func _gap(v: Vehicle) -> float:
	var pp := Game.player.global_position
	return Vector2(v.global_position.x - pp.x, v.global_position.z - pp.z).length()


func _cap_chasers(pc: Vehicle) -> void:
	if pc == null:
		return
	for v: Vehicle in chasers:
		if not is_instance_valid(v) or v.dead or not v.chasing:
			continue
		var cap := ChaseScripts.chase_cap(id, _gap(v)) * float(v.spec.get("max", 40.0))
		if absf(v.speed) > cap:
			v.speed = signf(v.speed) * cap


func _ref_check(v: Vehicle) -> bool:
	return is_instance_valid(v) and v.active and not v.dead


func _tick_pursue(delta: float, pc: Vehicle) -> void:
	if not is_instance_valid(target) or (not target.active and not target.dead):
		_fail("TARGET LOST")
		return
	var gap := _gap(target)
	var f := ChaseScripts.rubber(id, gap)
	target.ai_cruise = float(def["cruise"]) * f
	for g: Vehicle in guards:
		if is_instance_valid(g) and not g.dead:
			g.ai_cruise = float(def["cruise"]) * f
	var hp_f := 0.0 if target.dead else clampf(target.hp / target.max_hp, 0.0, 1.0)
	if target.dead or hp_f <= ChaseScripts.DISABLE:
		prog = 1.0
		if not target.dead:
			target.ai_stun = 1.0e6
		_end(true, "")
		return
	prog = clampf((1.0 - hp_f) / (1.0 - ChaseScripts.DISABLE), 0.0, 1.0)
	_check_fraction({"hp_frac": prog})
	if pc == null and Game.state == &"play" and clock > 2.0:
		_far_t += delta * 0.5                                # on foot: the target gets away twice as slowly
	if gap > float(def["lose"]):
		_far_t += delta
		if _far_t > float(def["lose_s"]):
			_fail("TARGET GOT AWAY")
	else:
		_far_t = maxf(_far_t - delta, 0.0)


func _check_fraction(extra: Dictionary) -> void:
	var cps: Array = def["checkpoints"]
	if cp_index < cps.size() and prog >= float(cps[cp_index]):
		_save_checkpoint(extra)


func _tick_escape(_delta: float, _pc: Vehicle) -> void:
	var p := Game.player.global_position
	var tr := _travelled(p)
	if not _awake:
		var near := false
		for v: Vehicle in chasers:
			if is_instance_valid(v) and _gap(v) < float(def["net_wake"]):
				near = true
		if near or clock > 5.0:
			_awake = true
			for v: Vehicle in chasers:
				if is_instance_valid(v):
					v.chasing = true
			Game.say("NET CLOSING", 1.6)
	prog = clampf(tr / float(def["dist"]), 0.0, 1.0)
	_check_fraction({})
	var goal := route_point(float(def["dist"]))
	if Vector2(goal.x - p.x, goal.z - p.z).length() <= float(def["radius"]) or tr >= float(def["dist"]):
		prog = 1.0
		_end(true, "")


func _tick_gate(delta: float, _pc: Vehicle) -> void:
	var p := Game.player.global_position
	gate_t -= delta
	var r := gate_radius()
	var g := gate_pos(gate_i)
	prog = clampf((float(gate_i) + 0.0) / float(def["gates"]), 0.0, 1.0)
	if Vector2(g.x - p.x, g.z - p.z).length() <= r:
		gate_i += 1
		if gate_i >= int(def["gates"]):
			prog = 1.0
			_end(true, "")
			return
		prog = float(gate_i) / float(def["gates"])
		_save_checkpoint({})
		gate_t = _budget(gate_i)
		Game.say("GATE %d/%d" % [gate_i, int(def["gates"])], 1.2)
		_show_markers()
		return
	if gate_t <= 0.0:
		_fail("GATE CLOSED")


func gate_pos(i: int) -> Vector3:
	return route_point(float(def.get("gate_gap", 60.0)) * float(i + 1))


## The ring of the current gate: wide when it opens, shrinking while its budget runs out.
func gate_radius() -> float:
	var b := _budget(gate_i)
	var f := clampf(gate_t / maxf(b, 0.001), 0.0, 1.0)
	return lerpf(float(def["radius"]) * 0.45, float(def["radius"]), f)


func _tick_escort(delta: float, pc: Vehicle) -> void:
	if not _ref_check(target):
		_fail("ESCORT LOST")
		return
	var gap := _gap(target)
	target.ai_cruise = float(def["cruise"]) * ChaseScripts.rubber(id, gap)
	var shooters := 0
	for v: Vehicle in chasers:
		if _ref_check(v) and Vector2(v.global_position.x - target.global_position.x, v.global_position.z - target.global_position.z).length() < ChaseScripts.FIRE_RANGE:
			shooters += 1
	if shooters > 0:
		target.damage(float(def["fire"]) * float(shooters) * delta)
		if not _ref_check(target):
			_fail("ESCORT LOST")
			return
	var tr := _travelled(target.global_position)
	prog = clampf(tr / float(def["dist"]), 0.0, 1.0)
	_check_fraction({"travelled": maxf(tr, 0.0), "hp_frac": target.hp / target.max_hp})
	if tr >= float(def["dist"]):
		prog = 1.0
		_end(true, "")
		return
	if gap > float(def["leash"]) or pc == null:
		_far_t += delta
		if _far_t > float(def["leash_s"]):
			_fail("ESCORT ABANDONED")
	else:
		_far_t = maxf(_far_t - delta, 0.0)


func _tick_duel(_delta: float, _pc: Vehicle) -> void:
	if not is_instance_valid(target) or (not target.active and not target.dead):
		_fail("BOSS LOST")
		return
	if target.dead or target.hp <= 0.0:
		prog = 1.0
		_end(true, "")
		return
	prog = clampf(1.0 - target.hp / target.max_hp, 0.0, 1.0)
	_check_fraction({})


# --- HUD, markers ---------------------------------------------------------------------------------------------------------------

func progress_frac() -> float:
	return prog


## HUD line while a run is on ("" when idle).
func hud_line() -> String:
	if state == &"idle":
		return ""
	var head := ChaseScripts.title(id)
	if state == &"retry":
		return "%s  %s  RETRY IN %d" % [head, fail_reason, int(ceilf(maxf(retry_t, 0.0)))]
	var what := ""
	match StringName(def["mode"]):
		&"pursue": what = "TARGET %d%%" % int(prog * 100.0)
		&"escape": what = "EXIT %d%%" % int(prog * 100.0)
		&"gate": what = "GATE %d/%d  %d s" % [gate_i + 1, int(def["gates"]), int(ceilf(maxf(gate_t, 0.0)))]
		&"escort": what = "ESCORT %d%%  HP %d" % [int(prog * 100.0), int(target.hp) if is_instance_valid(target) else 0]
		&"duel": what = "BOSS HP %d%%" % int((1.0 - prog) * 100.0)
	var tl := float(def["time"])
	var clk := "" if tl <= 0.0 else "  %d s" % int(ceilf(maxf(tl - clock, 0.0)))
	return "%s  %s%s" % [head, what, clk]


## Where the player should go (Vector3.INF when the goal is a moving car without a fixed place, or idle).
func waypoint() -> Vector3:
	if state != &"running":
		return Vector3.INF
	match StringName(def["mode"]):
		&"escape": return route_point(float(def["dist"]))
		&"gate": return gate_pos(gate_i)
		&"escort": return route_point(float(def["dist"]))
	if is_instance_valid(target):
		return target.global_position
	return Vector3.INF


func _marker(i: int) -> MeshInstance3D:
	while _markers.size() <= i:
		var m := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.7
		c.bottom_radius = 0.7
		c.height = 70.0
		c.radial_segments = 8
		c.rings = 1
		m.mesh = c
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.72, 0.25, 0.35) if _markers.size() == 0 else Color(0.25, 0.9, 1.0, 0.35)
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		m.top_level = true
		m.visible = false
		_markers.append(m)
	return _markers[i]


func _show_markers() -> void:
	_marker(0).visible = true
	_move_markers()


func _hide_markers() -> void:
	for m: MeshInstance3D in _markers:
		m.visible = false


func marker_visible() -> bool:
	return not _markers.is_empty() and _markers[0].visible


func _move_markers() -> void:
	var w := waypoint()
	if not w.is_finite():
		return
	var m := _marker(0)
	m.visible = true
	m.global_position = Vector3(w.x, 35.0, w.z)
	if StringName(def["mode"]) == &"gate":
		var s := gate_radius() / maxf(float(def["radius"]), 0.1)
		m.scale = Vector3(s * 4.0, 1.0, s * 4.0)
	else:
		m.scale = Vector3.ONE
