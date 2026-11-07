extends RefCounted
## The mission audit bot (owner round 3: "gets stuck in a task, tasks do not complete"). It plays the campaign in the REAL composed game (scenes/main.tscn) the way a player does, WITHOUT
## the runner's skip: it follows the HUD waypoint (`CampaignRunner.waypoint()`), walks the street grid with the real movement input, shoots with the real weapon through the camera rig,
## taps USE at doors and cars, drives a car for the chase, uses a verb to feed a rift, and takes the win screen's NEXT SECTOR. Long legs of a walk are covered in blink-sized hops along the
## street route (`hops`), the last 40 m of every leg are walked, so an unreachable goal still shows up. Every minute of waiting is game time.
## It records where a step does not progress (`findings`): kind, chapter, step, a reason class (UNREACHABLE, NO_ENEMY, TARGET_LOST, DOOR, CUTSCENE, INTERIOR, TIMEOUT, GUIDE_RECOVERED ...) and the
## numbers that explain it. The game's own stuck handler (MissionGuide) is a recovery, so an audit that sees it fire reports GUIDE_RECOVERED: the step is still a defect to fix.
##   const Audit := preload("res://tests/mission_audit.gd"); var a := Audit.new(); await a.setup(host); await a.play_chapters(4)
## Used by tests/test_mission_audit.gd (chapters 1-4, kinds) and tools/mission_audit.sh (longer, writes docs/shots/slice/mission_audit.txt).

const FightBot := preload("res://tests/fight_bot.gd")

const HOP_FROM := 90.0                  ## a remaining route longer than this is crossed in hops, the last HOP_KEEP metres are walked
const HOP_KEEP := 40.0
const HOP_MAX := 110.0
const WAYPOINT_TOL := 3.0
const SHOOT_RANGE := 48.0
const KIND_BUDGET := {                  ## game seconds a kind may take before the audit calls it TIMEOUT (generous: the step's own hold + the walk + the fight)
	&"reach": 120.0, &"enter_interior": 150.0, &"escort": 260.0, &"defend": 170.0, &"hack": 150.0, &"kill_target": 240.0, &"chase": 220.0,
	&"escape": 240.0, &"survive": 170.0, &"rift_hold": 170.0, &"heist": 300.0, &"convoy_intercept": 220.0,
}

var host: Node
var p: Player
var camp: CampaignRunner
var story: Story
var ig: InteriorGameplay
var vm: VehicleManager
var em: EnemyManager
var findings: Array[Dictionary] = []
var stats := {"steps": 0, "chapters": 0, "hops": 0, "heals": 0, "deaths": 0, "respawns": 0, "cards": 0, "doors": 0, "frames": 0, "fails": 0,
	"cutscenes": 0, "guide_events": 0, "walk_blocked": 0, "kinds": {}, "chapters_done": []}
var trace := PackedStringArray()        ## one line per step start / end (printed on request)
var game_clock := 0.0
var dt := 1.0 / 30.0
var max_game_seconds := 4000.0
var chapters_wanted := 4
var verbose := false
var max_real_seconds := 1.0e9
var debug_walk := false

var _held := {}
var _tap_off := {}
var _path := PackedVector3Array()
var _path_i := 0
var _path_goal := Vector3.INF
var _hop_cd := 0.0
var _last_pos := Vector3.ZERO
var _still_t := 0.0
var _unstick_t := 0.0
var _unstick_dir := 1.0
var _step_key := ""
var _step_t := 0.0
var _step_findings := {}
var _fight: FightBot
var _target: Node3D
var _tap_cd := 0.0
var _boss_tap := 0.0
var _chapters_done := 0
var _last_step_progress := -1.0
var _last_prog_t := 0.0
var _noprog := {}
var _win_wait := 0.0
var _state_wait := 0.0
var _door_wait := 0.0
var _drive_path := PackedVector3Array()
var _route_t := 0.0
var _stall_t := 0.0
var _reverse_t := 0.0


func setup(h: Node) -> bool:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.name = "AuditMain"
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	p = Game.player as Player
	var m := Game.missions as Missions
	if p == null or m == null or not is_instance_valid(Game.world) or not is_instance_valid(Game.enemies) or not is_instance_valid(Game.vehicles):
		return false
	camp = m.campaign
	story = Game.story as Story
	em = Game.enemies as EnemyManager
	vm = Game.vehicles as VehicleManager
	ig = InteriorGameplay.instance
	var prog := Game.progress as Progress
	if prog != null:
		prog.autosave_enabled = false
		prog.path = "user://audit_save.cfg"
	var hud := host.get_tree().root.find_child("Hud", true, false) as Hud
	if hud != null and hud.settings.path == UiSettings.DEFAULT_PATH:
		hud.settings = UiSettings.new("user://audit_settings.cfg")
	camp.enabled = true
	_fight = FightBot.new()
	_fight.p = p
	return true


func teardown() -> void:
	_release_all()
	var main := host.get_node_or_null("AuditMain")
	Game.state = &"menu"
	if main != null:
		main.queue_free()
	await TestLib.frames(host, 2)
	for f in ["user://audit_save.cfg", "user://audit_save.cfg.bak", "user://audit_settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


# --- findings ----------------------------------------------------------------------------------------------------------

func find(reason: String, detail: String) -> void:
	var key := "%d/%d/%s" % [camp.chapter_index, camp.step_index, reason]
	if _step_findings.has(key):
		return
	_step_findings[key] = true
	var f := {"chapter": camp.chapter_index + 1, "step": camp.step_index + 1, "kind": str(camp.kind), "reason": reason, "detail": detail, "t": snappedf(game_clock, 0.1),
		"pos": p.global_position if is_instance_valid(p) else Vector3.ZERO, "goal": camp.pos}
	findings.append(f)
	if verbose:
		print("AUDIT finding: ", f)


func stuck_findings() -> Array[Dictionary]:
	return findings.filter(func(f: Dictionary) -> bool: return str(f["reason"]) in ["UNREACHABLE", "NO_ENEMY", "TARGET_LOST", "DOOR", "CUTSCENE", "INTERIOR", "TIMEOUT", "GUIDE_RECOVERED", "NO_WAYPOINT", "NO_OBJECTIVE", "NO_CAR", "WIN_SCREEN"])


func summary() -> String:
	var lines := PackedStringArray()
	lines.append("steps %d, chapters %s, game time %.0f s, hops %d, heals %d, deaths %d, fails %d, guide recoveries %d, kinds %s" % [stats["steps"], str(stats["chapters_done"]), game_clock, stats["hops"], stats["heals"], stats["deaths"], stats["fails"], stats["guide_events"], str(stats["kinds"].keys())])
	for f in findings:
		lines.append("  %s ch%d step%d %s: %s (t=%.0f, player %s, goal %s)" % [f["reason"], f["chapter"], f["step"], f["kind"], f["detail"], f["t"], str(f["pos"]), str(f["goal"])])
	return "\n".join(lines)


# --- input helpers -----------------------------------------------------------------------------------------------------

func hold(action: StringName, on: bool) -> void:
	if on and not _held.has(action):
		Input.action_press(action)
		_held[action] = true
	elif not on and _held.has(action):
		Input.action_release(action)
		_held.erase(action)


func tap(action: StringName) -> void:
	if _tap_off.has(action):
		return
	Input.action_press(action)
	_tap_off[action] = 2


func _end_taps() -> void:
	for a: StringName in _tap_off.keys():
		_tap_off[a] -= 1
		if _tap_off[a] <= 0:
			Input.action_release(a)
			_tap_off.erase(a)


func _release_all() -> void:
	for a: StringName in _held.keys():
		Input.action_release(a)
	_held.clear()
	for a: StringName in _tap_off.keys():
		Input.action_release(a)
	_tap_off.clear()
	if _fight != null:
		_fight.finish()


func _frame() -> void:
	await host.get_tree().physics_frame
	dt = host.get_physics_process_delta_time()
	game_clock += dt
	stats["frames"] += 1
	_end_taps()


# --- the player's body: walking ----------------------------------------------------------------------------------------

## A street route from a to b over the road grid (the game's own: CampaignSteps.street_route).
static func street_route(a: Vector3, b: Vector3) -> PackedVector3Array:
	return CampaignSteps.street_route(a, b)


static func path_length(path: PackedVector3Array, from_i: int, from_pos: Vector3) -> float:
	var n := 0.0
	var cur := from_pos
	for i in range(from_i, path.size()):
		n += Vector2(path[i].x - cur.x, path[i].z - cur.z).length()
		cur = path[i]
	return n


func _point_along(path: PackedVector3Array, from_i: int, from_pos: Vector3, dist: float) -> Vector3:
	var cur := from_pos
	var left := dist
	for i in range(from_i, path.size()):
		var seg := Vector2(path[i].x - cur.x, path[i].z - cur.z).length()
		if seg >= left and seg > 0.001:
			return cur.lerp(path[i], left / seg)
		left -= seg
		cur = path[i]
	return path[path.size() - 1]


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func face(point: Vector3) -> void:
	p.camera_rig.look_at_point(Vector3(point.x, p.global_position.y + 1.4, point.z))


## One frame of walking toward `goal` (a point on the ground). Returns true when within `tol`.
func walk_to(goal: Vector3, tol := WAYPOINT_TOL, allow_hop := true) -> bool:
	var pp := p.global_position
	if _flat(pp, goal) <= tol:
		hold(&"move_forward", false)
		hold(&"sprint", false)
		return true
	if _path_goal == Vector3.INF or _flat(_path_goal, goal) > 6.0 or _path.is_empty():
		_path = PackedVector3Array([pp, goal]) if InteriorGameplay.active else street_route(pp, goal)       # inside a room: straight at it (the room's own coordinates have no street grid)
		_path_i = 1
		_path_goal = goal
	_hop_cd -= dt
	while _path_i < _path.size() - 1 and _flat(pp, _path[_path_i]) < 2.5:
		_path_i += 1
	var rem := path_length(_path, _path_i, pp)
	if allow_hop and rem > HOP_FROM and _hop_cd <= 0.0 and p.vehicle == null:
		var step_len := minf(rem - HOP_KEEP, HOP_MAX)
		var to := _point_along(_path, _path_i, pp, step_len)
		p.teleport_to(Vector3(to.x, 0.3, to.z))
		stats["hops"] += 1
		_hop_cd = 0.4
		_path_goal = Vector3.INF                        # the route is rebuilt from where the hop landed
		return false
	var next := _path[mini(_path_i, _path.size() - 1)]
	if debug_walk and int(game_clock) % 3 == 0 and int(game_clock * 10.0) % 10 == 0:
		print("WALK t=%.1f pos=%s next=%s i=%d/%d vel=%s goal=%s rem=%.0f" % [game_clock, str(pp), str(next), _path_i, _path.size(), str(p.velocity), str(goal), rem])
	face(next)
	hold(&"move_forward", true)
	hold(&"sprint", true)
	_unstick(pp)
	return false


func _unstick(pp: Vector3) -> void:
	_still_t += dt
	if _flat(pp, _last_pos) > 0.8 or _still_t > 1.2:
		if _flat(pp, _last_pos) <= 0.8 and _still_t > 1.2:
			_unstick_t += 1.2
			tap(&"jump")                                    # a tap: a held jump against a wall is a ledge grab, and the hero hangs there
			if int(_unstick_t) % 3 == 1:
				hold(&"move_right" if _unstick_dir > 0.0 else &"move_left", true)
			else:
				hold(&"move_right", false)
				hold(&"move_left", false)
			if _unstick_t > 7.0 and _path_goal == Vector3.INF:
				_unstick_t = 0.0
				_unstick_dir = -_unstick_dir                  # free running (no route): just try the other side
			elif _unstick_t > 7.0:
				stats["walk_blocked"] += 1
				_unstick_t = 0.0
				_unstick_dir = -_unstick_dir
				var to := _point_along(_path, _path_i, pp, 8.0)
				p.teleport_to(Vector3(to.x, 0.3, to.z))
				var what := ""
				var fwd := Vector3(-sin(p.camera_rig.yaw), 0.0, -cos(p.camera_rig.yaw))
				for h in [0.4, 1.0, 1.6]:
					var q := PhysicsRayQueryParameters3D.create(pp + Vector3(0, h, 0), pp + Vector3(0, h, 0) + fwd * 2.5, 0xFFFF)
					var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
					if not hit.is_empty():
						var col := hit["collider"] as Node
						what += " h%.1f:%s(%s,layer %d)" % [h, str(col.name), col.get_class(), int((col as CollisionObject3D).collision_layer) if col is CollisionObject3D else -1]
				if pp.y < -0.3:
					what += " [LOW y=%.2f crouching=%s sliding=%s floor=%s wall_running=%s air=%.1f hp_vel=%s]" % [pp.y, str(p.cover.crouching), str(p.cover.sliding), str(p.is_on_floor()), str(p.wall_running), p.air_time, str(p.velocity)]
				if what.contains("Car_"):
					what = ""                                   # a car (traffic, a patrol, a cop) in the way is a moving obstacle: wait and try the other side
					_unstick_dir = -_unstick_dir
				elif not InteriorGameplay.active:             # a straight walk across a furnished room is the bot's limit, not the game's; a street walk that is blocked is a finding
					find("UNREACHABLE", "the walk is blocked %.0f m from the goal at %s, ahead:%s" % [_flat(pp, _path_goal), str(pp), what if what != "" else " nothing hit"])
		else:
			_unstick_t = 0.0
			hold(&"jump", false)
			hold(&"move_right", false)
			hold(&"move_left", false)
		_last_pos = pp
		_still_t = 0.0


func stop_walking() -> void:
	for a in [&"move_forward", &"sprint", &"jump", &"move_left", &"move_right", &"move_back"]:
		hold(a, false)


# --- the player's hands: shooting, verbs -------------------------------------------------------------------------------

func _los(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, Game.L_WORLD)
	return p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func living_enemies() -> Array[Drone]:
	var out: Array[Drone] = []
	for e in em.list:
		if e.active and not e.dead and not e.remove:
			out.append(e)
	return out


## The foe to shoot: `prefer` when it can be seen within range, else the nearest one that can be. Null when none.
func pick_foe(prefer: Node3D = null, reach := SHOOT_RANGE) -> Drone:
	var eye := p.global_position + Vector3(0.0, 1.5, 0.0)
	if prefer is Drone and is_instance_valid(prefer):
		var pd := prefer as Drone
		if pd.active and not pd.dead and _los(eye, pd.center()) and pd.global_position.distance_to(p.global_position) < reach:
			return pd
	var best: Drone = null
	var bd := reach
	for e in living_enemies():
		var d := e.global_position.distance_to(p.global_position)
		if d < bd and _los(eye, e.center()):
			bd = d
			best = e
	return best


## Shoot `foe` with the real weapon: aim through the camera rig, fire, reload when empty. Returns true when it is shooting.
func shoot(foe: Drone) -> bool:
	if p.weapon.ammo <= 0 and not p.weapon.is_reloading():
		hold(&"fire", false)
		tap(&"reload")
		return false
	if foe == null:
		hold(&"fire", false)
		return false
	p.camera_rig.aim_at(foe.center())
	hold(&"fire", true)
	return true


func heal_up() -> void:
	if not is_instance_valid(p) or p.is_dead():
		return
	if p.hp < p.max_hp * 0.5:
		p.hp = p.max_hp
		stats["heals"] += 1
	if p.weapon.ammo <= 0 and not p.weapon.is_reloading():
		tap(&"reload")


## Use a quantum verb (feeds a rift, stops a convoy car, breaks a shield).
func use_verb(action: StringName) -> void:
	if _tap_cd <= 0.0:
		tap(action)
		_tap_cd = 0.8


# --- the game around the player: cards, deaths, win screen -------------------------------------------------------------

func _globals() -> bool:
	## Returns true when the bot should not act this frame (a screen owns the game).
	_tap_cd -= dt
	if Game.state == &"dead":
		_release_all()
		stats["deaths"] += 1
		stats["respawns"] += 1
		Game.do_respawn()
		return true
	if Game.state == &"win":
		stop_walking()
		_win_wait += dt
		if _win_wait > 0.8:
			_win_wait = 0.0
			Game.do_next_sector()
			_path_goal = Vector3.INF
			if story != null:
				story.skip_cards()
		return true
	_win_wait = 0.0
	if story != null and story.cards_active():
		stats["cards"] += 1
		story.skip_cards()
		return true
	var ci := Cinematics.instance
	if ci != null and ci.active:
		stats["cutscenes"] += 1
		stop_walking()
		_state_wait += dt
		if _state_wait > 1.0:
			ci.skip()
		if _state_wait > 60.0:
			find("CUTSCENE", "a cutscene (%s) blocks the game for %.0f s" % [str(ci.active_id), _state_wait])
		return true
	if Game.state != &"play":
		_state_wait += dt
		if _state_wait > 40.0:
			find("CUTSCENE", "the game state is %s for %.0f s" % [str(Game.state), _state_wait])
			if Game.state == &"paused":
				Game.state = &"play"
		return true
	_state_wait = 0.0
	return false


# --- the campaign ------------------------------------------------------------------------------------------------------

## Plays `count` chapters from the start of a new game. Returns when they are done or the game-time budget is spent.
func play_chapters(count: int, from_chapter := 0, from_step := 0) -> void:
	chapters_wanted = count
	camp.step_completed.connect(_on_step_done)
	camp.step_failed.connect(_on_step_failed)
	camp.chapter_completed.connect(_on_chapter_done)
	Game.start_new_game()
	if story != null:
		story.skip_cards()
	if from_chapter > 0 or from_step > 0:                  # development: start in the middle (AUDIT_FROM=3:3 in tests/test_mission_audit.gd)
		if story != null:
			story.set_chapter(from_chapter)
			story.skip_cards()
		camp.start_chapter(from_chapter, from_step, true)
	var real0 := Time.get_ticks_msec()
	while _chapters_done < count and game_clock < max_game_seconds and float(Time.get_ticks_msec() - real0) / 1000.0 < max_real_seconds:
		await _frame()
		if _globals():
			continue
		heal_up()
		if is_instance_valid(camp):
			_tick_campaign()
	_release_all()


## Plays one sandbox chapter (CampaignSteps.DEMO_IDS: rift hold, quantum heist, convoy intercept) through the same bot. True when it completed on its own.
func play_demo(id: StringName, max_seconds := 300.0) -> bool:
	_step_key = ""
	if not camp.step_completed.is_connected(_on_step_done):
		camp.step_completed.connect(_on_step_done)
		camp.step_failed.connect(_on_step_failed)
	var flag := [false]
	var on_done := func(_c: int) -> void: flag[0] = true
	camp.chapter_completed.connect(on_done)
	if not camp.start_demo(id):
		find("NO_OBJECTIVE", "the %s sandbox does not start" % str(id))
		camp.chapter_completed.disconnect(on_done)
		return false
	var t0 := game_clock
	while not flag[0] and game_clock - t0 < max_seconds:
		await _frame()
		if _globals():
			continue
		heal_up()
		_tick_campaign()
	camp.chapter_completed.disconnect(on_done)
	_release_all()
	camp.abort()
	return flag[0]


func _on_step_done(_c: int, _i: int, k: StringName) -> void:
	stats["steps"] += 1
	stats["kinds"][k] = int(stats["kinds"].get(k, 0)) + 1
	trace.append("t=%.0f done %s ch%d step%d (%.0f s)" % [game_clock, str(k), _c + 1, _i + 1, _step_t])
	_path_goal = Vector3.INF
	_target = null


func _on_step_failed(c: int, i: int, k: StringName, why: String) -> void:
	stats["fails"] += 1
	trace.append("t=%.0f FAILED %s ch%d step%d: %s" % [game_clock, str(k), c + 1, i + 1, why])
	_path_goal = Vector3.INF
	_target = null


func _on_chapter_done(c: int) -> void:
	_chapters_done += 1
	stats["chapters"] += 1
	(stats["chapters_done"] as Array).append(c + 1)
	trace.append("t=%.0f chapter %d done" % [game_clock, c + 1])


func _tick_campaign() -> void:
	if camp.state != &"active":
		if not (camp.state == &"armed" and InteriorGameplay.active):
			stop_walking()
		hold(&"fire", false)
		_step_t = 0.0
		if camp.state == &"idle":
			_noprog["idle"] = float(_noprog.get("idle", 0.0)) + dt
			if float(_noprog["idle"]) > 25.0 and _chapters_done < chapters_wanted:
				find("NO_OBJECTIVE", "no step is running (the campaign runner is idle) after %.0f s in the game" % float(_noprog["idle"]))
		elif camp.state == &"armed" and InteriorGameplay.active and camp.guide != null and camp.guide.line().contains("LEAVE"):
			_leave_interior()                           # the HUD says LEAVE THE BUILDING TO CONTINUE: a player walks to the exit
		elif camp.state == &"armed":
			_noprog["armed"] = float(_noprog.get("armed", 0.0)) + dt
			if float(_noprog["armed"]) > 40.0:
				find("DOOR", "the next step stays armed for %.0f s (inside blocks it or a gate is closed)" % float(_noprog["armed"]))
				if InteriorGameplay.active:
					ig.leave(true)
		return
	_noprog.clear()
	var key := "%d/%d" % [camp.chapter_index, camp.step_index]
	if key != _step_key:
		_step_key = key
		_step_t = 0.0
		_path_goal = Vector3.INF
		_target = null
		_boss_tap = 0.0
		trace.append("t=%.0f begin %s ch%d step%d '%s'" % [game_clock, str(camp.kind), camp.chapter_index + 1, camp.step_index + 1, str(camp.step.get("text", ""))])
		if camp.hud_line() == "":
			find("NO_OBJECTIVE", "the HUD line is empty at the start of the step")
		if camp.waypoint().is_empty() and camp.kind not in [&"escape", &"survive"] and not InteriorGameplay.active:
			find("NO_WAYPOINT", "the step has no waypoint on the HUD")
	_step_t += dt
	var budget := float(KIND_BUDGET.get(camp.kind, 200.0)) + float(camp.step.get("hold", 0.0))
	if _step_t > budget:
		find("TIMEOUT", "no completion after %.0f s (budget %.0f), progress %.2f, foes %d" % [_step_t, budget, camp.progress, camp.foes_alive()])
		_recover()
		return
	_guide_watch()
	match camp.kind:
		&"reach": _do_reach()
		&"enter_interior": _do_interior()
		&"heist": _do_heist()
		&"escort": _do_escort()
		&"defend", &"hack", &"rift_hold": _do_hold()
		&"survive": _do_survive()
		&"kill_target": _do_kill()
		&"chase": _do_chase()
		&"escape": _do_escape()
		&"convoy_intercept": _do_convoy()
		_: _do_reach()


## The audit does not skip a step, but a bot that exhausted its patience has to move on so the rest of the chapter is audited: the game's own recovery (MissionGuide) is used when it exists.
func _recover() -> void:
	var g := _guide()
	if g != null and g.has_method(&"recover"):
		g.call(&"recover")
	else:
		camp.skip_step()
	_step_t = 0.0


func _guide() -> Object:
	return camp.get(&"guide") as Object


func _guide_watch() -> void:
	var g := _guide()
	if g == null:
		return
	var ev := int(g.get(&"recoveries"))
	if ev > int(stats["guide_events"]):
		stats["guide_events"] = ev
		find("GUIDE_RECOVERED", "the game's stuck handler had to recover this step (%s)" % str(g.get(&"last_reason")))


func _step_pos() -> Vector3:
	var w := camp.waypoint()
	if w.has("pos"):
		return w["pos"]
	return camp.pos if camp.pos.is_finite() else p.global_position


# --- per kind ----------------------------------------------------------------------------------------------------------

func _do_reach() -> void:
	var pp := p.global_position
	if p.vehicle != null:
		_leave_car()
		return
	var goal := _step_pos()
	var foe := pick_foe()
	if foe != null and foe.aware:
		shoot(foe)
	else:
		hold(&"fire", false)
	if InteriorGameplay.active:
		_leave_interior()
		return
	walk_to(Vector3(goal.x, pp.y, goal.z), 2.0)


func _leave_car() -> void:
	if p.vehicle != null:
		tap(&"interact")


func _leave_interior() -> void:
	if not InteriorGameplay.active:
		return
	var ex := InteriorGameplay.exit_point(ig.interior)
	if walk_to(Vector3(ex.x, p.global_position.y, ex.z), 1.4, false):
		tap(&"interact")


func _do_interior() -> void:
	if p.vehicle != null:
		_leave_car()
		return
	var phase: int = camp.get(&"_phase")
	if InteriorGameplay.active:
		if phase == 2 or camp.step.get("leave", false) == true:
			_leave_interior()
		else:
			stop_walking()
		return
	var goal := _step_pos()
	var foe := pick_foe()
	if foe != null and foe.aware:
		shoot(foe)
	if walk_to(Vector3(goal.x, p.global_position.y, goal.z), 1.6):
		face(goal)
		_door_wait = 0.0 if ig.busy else _door_wait + dt
		if ig.prompt.begins_with("ENTER"):
			stats["doors"] += 1
			tap(&"interact")
		elif _door_wait > 1.5:
			var car := vm.nearest(p.global_position, 4.2)
			find("DOOR", "standing at the door for %.1f s, the prompt is '%s' (nearest door %s at %.1f m, car in 4.2 m: %s, state %s, busy %s)" % [_door_wait, ig.prompt, str(ig.nearest_door(p.global_position, 6.0).get("id", "none")),
				_flat(p.global_position, ig.nearest_door(p.global_position, 6.0).get("pos", Vector3(999, 0, 999))), str(car.kind) if car != null else "none", str(Game.state), str(ig.busy)])
	else:
		_door_wait = 0.0


func _do_heist() -> void:
	var phase: int = camp.get(&"_phase")
	if phase == 3:
		_do_escape()
		return
	if InteriorGameplay.active:
		if camp.loot:
			_leave_interior()
			return
		# an interior job: crack the safe / free the hostage / reach the terminal by the prompt
		var m := ig.missions
		if m != null and m.is_active() and m.target_pos.is_finite():
			var tp := m.target_pos
			var foe := pick_foe()
			if foe != null:
				shoot(foe)
			if walk_to(Vector3(tp.x, p.global_position.y, tp.z), 2.4, false) or ig.prompt != "" and not ig.prompt.begins_with("LEAVE"):
				stop_walking()
				tap(&"interact")
		else:
			stop_walking()
		return
	_do_interior()


func _do_escort() -> void:
	if p.vehicle != null:
		_leave_car()
		return
	var foe := pick_foe(null, 40.0)
	shoot(foe)
	var es: Node3D = camp.escortee
	if not is_instance_valid(es):
		return
	var goal: Vector3 = camp.pos
	var leash := float(camp.step.get("leash", 26.0))
	var d_es := _flat(p.global_position, es.global_position)
	if verbose and int(_step_t) % 8 == 0 and int(_step_t * 10.0) % 10 == 0:
		print("ESCORT t=%.0f progress=%.2f d_es=%.0f es=%s me=%s aware_near=%d hp=%.0f" % [_step_t, camp.progress, d_es, str(es.global_position), str(p.global_position), living_enemies().filter(func(e: Drone) -> bool: return e.aware and _flat(e.global_position, es.global_position) < 16.0).size(), camp.escort_hp])
	if d_es > leash * 0.5 or foe == null:
		# stay near the escortee, ahead of it toward the destination
		var target := es.global_position.lerp(goal, 0.0) if d_es > leash * 0.4 else goal
		walk_to(Vector3(target.x, p.global_position.y, target.z), 2.0, false)
	else:
		stop_walking()


func _do_hold() -> void:
	if p.vehicle != null:
		_leave_car()
		return
	var goal: Vector3 = camp.pos
	var radius := float(camp.step.get("radius", 10.0))
	var foe := pick_foe()
	shoot(foe)
	var d := _flat(p.global_position, goal)
	if d > radius * 0.6:
		walk_to(Vector3(goal.x, p.global_position.y, goal.z), radius * 0.4)
	else:
		stop_walking()
		if camp.kind == &"rift_hold":
			use_verb(&"superpose")
			if _tap_cd > 0.5 and p.energy < 30.0:
				p.energy = p.max_energy


func _do_survive() -> void:
	if p.vehicle != null:
		_leave_car()
		return
	var foe := pick_foe()
	shoot(foe)
	stop_walking()
	if foe != null:
		face(foe.global_position)


func _do_kill() -> void:
	if p.vehicle != null:
		_leave_car()
		return
	var t := camp.target as Drone
	if t == null or not is_instance_valid(t):
		find("TARGET_LOST", "the kill target is gone")
		return
	if t is VerbBoss and _boss_play(t as VerbBoss):
		return
	var foe := pick_foe(t)
	shoot(foe)                                             # whatever can be seen is shot at, but the way leads to the target itself
	var goal := t.global_position
	if _flat(p.global_position, goal) > 20.0:
		walk_to(Vector3(goal.x, p.global_position.y, goal.z), 16.0)
	else:
		hold(&"move_forward", false)
		hold(&"sprint", false)
	_boss_verbs(t)


## Bosses carry shields and wind-ups: a COLLAPSE (the wave breaks a shield) now and then, like a player would.
func _boss_verbs(t: Drone) -> void:
	_boss_tap -= dt
	if t is Overseer:
		if _boss_tap <= 0.0 and t.global_position.distance_to(p.global_position) < 14.0:
			_boss_tap = 3.0
			p.energy = maxf(p.energy, 50.0)
			tap(&"collapse")


## The verb bosses are puzzles (damage x0.1 until the right verb exposes them). The bot plays the answer the HUD hint gives: COLLAPSE the PHASEWRIGHT's windup, the BULWARK's shield and the
## SKIMMER's skiff, ENTANGLE the SMELTER into a vent, draw the HOUND with SUPERPOSITION. Returns true when it handled the frame.
func _boss_play(t: VerbBoss) -> bool:
	var d := _flat(t.global_position, p.global_position)
	var foe := pick_foe(t)
	if verbose and int(_step_t) % 10 == 0 and int(_step_t * 10.0) % 10 == 0:
		print("BOSS %s t=%.0f hp=%.0f/%.0f dist=%.0f los=%s exposed=%s hint='%s' ammo=%d reloading=%s boss_pos=%s me=%s active=%s aware=%s" % [str(t.mode), _step_t, t.hp, t.max_hp, d, str(foe == t), str(t.exposed()), t.hint(), p.weapon.ammo, str(p.weapon.is_reloading()), str(t.global_position), str(p.global_position), str(t.active), str(t.aware)])
	_boss_tap -= dt
	p.energy = maxf(p.energy, 60.0)
	match t.mode:
		&"phase":
			if t.get(&"_tp_wind") > 0.0 and d < 15.0:
				use_verb(&"collapse")
			if foe == t:
				shoot(t)
			else:
				shoot(foe)
			if d > 14.0:
				walk_to(Vector3(t.global_position.x, p.global_position.y, t.global_position.z), 10.0, false)
			else:
				stop_walking()
			return true
		&"shield":
			if t.shield_is_up and d < 14.0:
				use_verb(&"collapse")
			shoot(foe if foe != null else null)
			if d > 16.0:
				walk_to(Vector3(t.global_position.x, p.global_position.y, t.global_position.z), 12.0, false)
			else:
				stop_walking()
			return true
		&"hover":
			if t.crashed_t <= 0.0 and d < 15.0:
				use_verb(&"collapse")
			shoot(foe)
			if d > 18.0:
				walk_to(Vector3(t.global_position.x, p.global_position.y, t.global_position.z), 14.0, false)
			else:
				stop_walking()
			return true
		&"hunter":
			if not is_instance_valid(em.get_clone()) and _tap_cd <= 0.0:
				use_verb(&"superpose")
			elif t.feeding():
				pass
			shoot(foe)
			if d > 16.0:
				walk_to(Vector3(t.global_position.x, p.global_position.y, t.global_position.z), 12.0, false)
			else:
				stop_walking()
			return true
		&"hazard":
			if t.hazards.is_empty():
				return false
			var ring: Vector3 = t.hazards[0]
			var bd := INF
			for h in t.hazards:
				var hd := _flat(h, p.global_position)
				if hd < bd:
					bd = hd
					ring = h
			if _flat(ring, p.global_position) > 2.0:
				walk_to(Vector3(ring.x, p.global_position.y, ring.z), 1.5, false)
				return true
			stop_walking()
			p.camera_rig.aim_at(t.center())
			if not t.hazard_armed() and not t.in_hazard(t.global_position):
				use_verb(&"entangle")
			shoot(foe if (t.exposed() or t.weakened()) else null)
			return true
	return false


func _do_chase() -> void:
	var car := camp.car
	if car == null or not is_instance_valid(car):
		find("TARGET_LOST", "the chase car is gone")
		return
	if verbose and int(_step_t) % 8 == 0 and int(_step_t * 10.0) % 10 == 0:
		print("CHASE t=%.0f dist=%.0f me=%s speed=%.1f target_speed=%.1f target_hp=%.0f/%.0f" % [_step_t, _flat(car.global_position, p.global_position), "car" if p.vehicle != null else "foot", (p.vehicle as Vehicle).speed if p.vehicle != null else 0.0, car.speed, car.hp, car.max_hp])
	var dd := _flat(car.global_position, p.global_position)
	if p.vehicle == null and dd < 45.0 and absf(car.speed) < 9.0:
		# the target is stopped at a light or boxed in: a player jumps out and shoots it with the rifle
		if dd > 18.0:
			hold(&"fire", false)
			walk_to(Vector3(car.global_position.x, p.global_position.y, car.global_position.z), 14.0, false)
		else:
			stop_walking()
			p.camera_rig.aim_at(car.global_position + Vector3(0.0, 0.8, 0.0))
			hold(&"fire", true)
		return
	if p.vehicle == null:
		var mine := _take_a_car(car)
		if not mine:
			return
	if p.vehicle != null and dd < 14.0 and absf((p.vehicle as Vehicle).speed) < 12.0 and absf(car.speed) < 9.0:
		_leave_car()
		return
	drive_toward(car.global_position)
	hold(&"fire", dd < 70.0)                              # the car's own weapon (rail gun): fire when the target is in front and close


## Walk to the closest car (the sport car near the spawn, a traffic car, any) and take it with USE. Returns true when the player is in a car.
func _take_a_car(_target_car: Node3D) -> bool:
	if p.vehicle != null:
		return true
	var best: Vehicle = null
	var bd := INF
	for c in vm.list:
		if c.dead or not c.active or c.wreck or c == camp.car or camp.convoy.has(c):
			continue
		var d := _flat(c.global_position, p.global_position)
		if d < bd:
			bd = d
			best = c
	if best == null:
		find("NO_CAR", "there is no car to take for the chase")
		return false
	var edge := best.edge_distance(p.global_position)
	if edge < 2.2 or bd < 3.5:
		stop_walking()
		tap(&"interact")
		return false
	walk_to(Vector3(best.global_position.x, p.global_position.y, best.global_position.z), 2.0, bd > 100.0)
	return false


## Drive the car toward `point` the way a player does: along the streets (the street route's next corner beyond a look-ahead), throttle, steer left / right, reverse out of a corner.
func drive_toward(point: Vector3, _vel := Vector3.ZERO) -> void:
	var car := p.vehicle as Vehicle
	if car == null:
		return
	var here := car.global_position
	_route_t -= dt
	if _drive_path.is_empty() or _route_t <= 0.0:
		_drive_path = street_route(here, point)
		_route_t = 1.5
	var aim := point
	if _flat(here, point) > 24.0:
		aim = _point_along(_drive_path, 1, here, 16.0)
	var to := aim - here
	to.y = 0.0
	var f := car.forward()
	f.y = 0.0
	var ang := f.signed_angle_to(to, Vector3.UP)           # positive: the aim point is to the left (counter-clockwise seen from above)
	if _reverse_t > 0.0:
		_reverse_t -= dt
		hold(&"move_forward", false)
		hold(&"move_back", true)
		hold(&"move_left", ang < 0.0)
		hold(&"move_right", ang >= 0.0)
		return
	if absf(car.speed) < 1.0:
		_stall_t += dt
		if _stall_t > 2.0:
			_stall_t = 0.0
			_reverse_t = 1.4
	else:
		_stall_t = 0.0
	var want_speed := 20.0 if absf(ang) < 0.35 else (11.0 if absf(ang) < 0.9 else 6.0)       # lift off for a corner, like a player
	hold(&"move_forward", car.speed < want_speed)
	hold(&"move_back", car.speed > want_speed + 7.0)
	hold(&"move_left", ang > 0.06)
	hold(&"move_right", ang < -0.06)
	hold(&"sprint", false)


func _do_escape() -> void:
	if verbose and int(_step_t) % 10 == 0 and int(_step_t * 10.0) % 10 == 0:
		print("ESCAPE t=%.0f heat=%.2f quiet=%.1f dist=%.0f/%.0f patrols=%d aware=%d pos=%s" % [_step_t, Game.heat, Game.quiet, camp.call(&"_origin_dist"), float(camp.step.get("dist", 0)), camp.call(&"_patrols_chasing"), living_enemies().filter(func(e: Drone) -> bool: return e.aware).size(), str(p.global_position)])
	# run away from where the pursuit started, away from the patrol vehicles; shoot what chases
	var origin: Vector3 = camp.get(&"_origin")
	var foe := pick_foe(null, 36.0)
	if p.vehicle != null:
		_leave_car()
	shoot(foe)
	var away := p.global_position - origin
	away.y = 0.0
	var dist := float(camp.step.get("dist", 110.0))
	if _flat(p.global_position, origin) < dist + 20.0:
		var dir := away.normalized() if away.length() > 1.0 else Vector3.RIGHT
		var target := p.global_position + dir * 60.0
		var s := street_route(p.global_position, target)
		face(s[mini(2, s.size() - 1)])
		hold(&"move_forward", true)
		hold(&"sprint", true)
		_unstick(p.global_position)
	else:
		stop_walking()
		# hide: wait for the heat to cool; patrol vehicles that still chase are shot / outrun
		for v in camp.call(&"_chasing_patrols"):
			if is_instance_valid(v) and _flat(v.global_position, p.global_position) < 40.0:
				v.damage(40.0 * dt)


func _do_convoy() -> void:
	var near := camp.call(&"_nearest_moving_car") as Vehicle
	if near == null:
		return
	var d := _flat(near.global_position, p.global_position)
	if verbose and int(_step_t) % 6 == 0 and int(_step_t * 10.0) % 10 == 0:
		print("CONVOY t=%.0f dist=%.0f me=%s speed=%.1f car_speed=%.1f stopped=%d/%d player=%s car=%s" % [_step_t, d, "car" if p.vehicle != null else "foot", (p.vehicle as Vehicle).speed if p.vehicle != null else 0.0, near.speed, camp.stopped.size(), camp.convoy.size(), str(p.global_position), str(near.global_position)])
	if p.vehicle == null:
		if camp.call(&"_take_the_car") or d > 60.0:
			_take_a_car(null)
			return
		walk_to(Vector3(near.global_position.x, p.global_position.y, near.global_position.z), 10.0)
		if d < 14.0:
			p.energy = maxf(p.energy, 60.0)
			use_verb(&"collapse")
		return
	drive_toward(near.global_position)
	hold(&"fire", d < 70.0)
	if d < 14.0 and absf((p.vehicle as Vehicle).speed) < 14.0:
		_leave_car()                                       # the verbs are a foot thing: jump out beside the convoy and use them


# --- other mission systems (side missions, contracts, heists, activities): started from the real game, audited briefly ----

## Walks the player to a world point with the real input (hops on long legs) for up to `seconds`. Returns true on arrival.
func go_to(goal: Vector3, seconds: float, tol := 2.5) -> bool:
	var t := 0.0
	_path_goal = Vector3.INF
	while t < seconds:
		await _frame()
		t += dt
		if _globals():
			continue
		heal_up()
		if walk_to(Vector3(goal.x, p.global_position.y, goal.z), tol):
			stop_walking()
			return true
	stop_walking()
	return false


## Plays one side mission (SideMissions.ORDER) with the real input until it ends. Returns {ok, reason, seconds}.
func audit_side(mid: StringName, max_seconds := 220.0) -> Dictionary:
	var sm := (Game.missions as Missions).sides
	camp.enabled = false
	camp.abort()                                            # no campaign step runs beside a side job
	var res := {"id": mid, "ok": false, "reason": "NOT STARTED", "seconds": 0.0}
	_path_goal = Vector3.INF
	if story != null:
		story.chapter = maxi(story.chapter, 8)
	if p.vehicle != null:
		vm.exit_vehicle()
	if InteriorGameplay.active:
		ig.leave(true)
	var from := PlayerUtil.nearest_street(p.global_position)
	p.teleport_to(Vector3(from.x, 0.3, from.z))
	if not sm.start(mid):
		var ct: Variant = (Game.missions as Missions).contracts
		res["reason"] = "CANNOT START (active %s, contract %s, unlocked %s at chapter %d, job_open %s)" % [str(sm.active), str(ct.state), str(SideMissions.unlocked(mid, int(story.chapter))), int(story.chapter), str(Factions.job_open(Game.progress, mid))]
		return res
	var t0 := game_clock
	var stage_i := -1
	var stage_t := 0.0
	while sm.active and game_clock - t0 < max_seconds:
		await _frame()
		if _globals():
			continue
		heal_up()
		if sm.stage != stage_i:
			stage_i = sm.stage
			stage_t = 0.0
		stage_t += dt
		if not sm.active:
			break
		if verbose and int(stage_t) % 6 == 0 and int(stage_t * 10.0) % 10 == 0:
			print("SIDEDBG %s stage %d %s t=%.0f me=%s speed=%.1f dist=%.0f" % [str(mid), stage_i + 1, str(sm.stages[stage_i]["kind"]), stage_t, "car" if p.vehicle != null else "foot", (p.vehicle as Vehicle).speed if p.vehicle != null else 0.0, _flat(p.global_position, sm.stages[stage_i]["pos"])])
		_do_side_stage(sm)
		if stage_t > 150.0:
			find("TIMEOUT", "side mission %s stage %d (%s) makes no progress for %.0f s" % [str(mid), stage_i + 1, str(sm.stages[stage_i]["kind"]), stage_t])
			sm.abort("AUDIT")
	stop_walking()
	hold(&"fire", false)
	res["seconds"] = game_clock - t0
	var r: Dictionary = sm.last_result
	if sm.active:
		sm.abort("AUDIT TIMEOUT")
		res["reason"] = "TIME BUDGET"
	else:
		res["ok"] = bool(r.get("ok", false))
		res["reason"] = str(r.get("reason", ""))
	if p.vehicle != null:
		vm.exit_vehicle()
	return res


func _do_side_stage(sm: SideMissions) -> void:
	var st: Dictionary = sm.stages[sm.stage]
	var goal: Vector3 = st["pos"]
	match String(st["kind"]):
		"goto":
			if bool(st["car"]) and p.vehicle == null:
				_take_a_car(null)
				return
			if p.vehicle != null:
				drive_toward(goal)
			else:
				walk_to(Vector3(goal.x, p.global_position.y, goal.z), float(st["r"]) * 0.5)
		"dwell":
			if _flat(p.global_position, goal) > float(st["r"]) * 0.5:
				walk_to(Vector3(goal.x, p.global_position.y, goal.z), float(st["r"]) * 0.4)
			else:
				stop_walking()
				shoot(pick_foe())
		"photo":
			if _flat(p.global_position, goal) > float(st["r"]) * 0.6:
				walk_to(Vector3(goal.x, p.global_position.y, goal.z), float(st["r"]) * 0.5)
			else:
				stop_walking()
				face(goal)
		"kill":
			var foe := pick_foe()
			var wp := sm.waypoint()
			if foe != null:
				shoot(foe)
				stop_walking()
			else:
				hold(&"fire", false)
				if wp.is_finite():
					walk_to(Vector3(wp.x, p.global_position.y, wp.z), 12.0, false)
				else:
					find("NO_ENEMY", "side mission %s: a kill stage with nobody to kill" % str(sm.id))
		"smash":
			var wp2 := sm.waypoint()
			if not wp2.is_finite():
				find("UNREACHABLE", "side mission %s: no prop to smash" % str(sm.id))
				return
			if _flat(p.global_position, wp2) > 14.0:
				hold(&"fire", false)
				walk_to(Vector3(wp2.x, p.global_position.y, wp2.z), 10.0, false)
			else:
				stop_walking()
				p.camera_rig.aim_at(wp2 + Vector3(0.0, 0.6, 0.0))
				hold(&"fire", true)


## Structure of the systems the bot does not play out: every contract kind, heist, stealth mission, vehicle chase and activity must start from the real game, say what to do (a status
## line) and, where it has a place, give the player somewhere to go. Returns lines describing what is missing.
func audit_structure() -> PackedStringArray:
	var out := PackedStringArray()
	camp.enabled = false
	camp.abort()
	var m := Game.missions as Missions
	if story != null:
		story.chapter = maxi(story.chapter, 8)
	var from := PlayerUtil.nearest_street(p.global_position)
	p.teleport_to(Vector3(from.x, 0.3, from.z))
	var ct := m.contracts
	ct.enabled = true
	for k: StringName in ContractTypes.KINDS:
		ct.abandon()
		if not ct.offer(k):
			out.append("contract %s: offer() refused" % str(k))
			continue
		var offered := ct.state == &"offered" and ct.marker_count() >= 0
		if not ct.accept():
			out.append("contract %s: accept() refused" % str(k))
			continue
		var line := ct.hud_line()
		if line == "":
			out.append("contract %s: the HUD line is empty while it runs" % str(k))
		if ct.distance_to_goal() <= 0.0 and not ct.pos.is_finite():
			out.append("contract %s: no goal to point at" % str(k))
		if not offered:
			out.append("contract %s: not offered before accepting" % str(k))
		ct.abandon()
		await _frame()
	ct.abandon()
	ct.enabled = false
	for hid: StringName in HeistScripts.IDS:
		if not m.heists.can_start(hid):
			out.append("heist %s: cannot start (can_start false)" % str(hid))
			continue
		if not m.heists.start(hid):
			out.append("heist %s: start() refused" % str(hid))
			continue
		await TestLib.frames(host, 3)
		if camp.hud_line() == "" and camp.guide.line() == "":
			out.append("heist %s: no objective line" % str(hid))
		m.heists.abort()
		camp.abort()
	for aid: StringName in Activities.IDS:
		var a := host.get_tree().get_first_node_in_group(&"activities") as Activities
		if a == null:
			out.append("activities: no Activities node")
			break
		if not a.start(aid, true):
			out.append("activity %s: start() refused" % str(aid))
			continue
		if not bool(a.readout().get("visible", false)):
			out.append("activity %s: no readout on the HUD" % str(aid))
		a.stop()
	return out
