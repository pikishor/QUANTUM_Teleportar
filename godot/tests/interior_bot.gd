extends RefCounted
## A phone player's hands inside a building, for the interior task tests and audits. It plays the REAL composed game (scenes/main.tscn) with the touch layer on and uses only what a phone player has:
## the virtual move stick and the look drag (TouchControls.touch_down / touch_move), the USE and LEAVE buttons (touched at their drawn centre, and only when the touch layer shows them),
## the floating prompt text and the task status line it reads from the HUD statics. It walks along a path searched on the room's real physics (tests/room_walk.gd), so furniture, walls and
## the quantum gate corridor count. Time runs SPEED_UP times faster than the wall clock (physics ticks and time scale).
##   var bot := InteriorBot.new(); await bot.setup(host); await bot.enter_door(type); await bot.walk_to(point, reach); await bot.use(); ...

const RoomWalk := preload("res://tests/room_walk.gd")
const SPEED_UP := 4
const TICK_RATE := 60 * SPEED_UP
const FINGER_STICK := 11
const FINGER_BTN := 12

var host: Node
var main: Node
var p: Player
var ig: InteriorGameplay
var tc: TouchControls
var prog: Progress
var findings: Array[String] = []
var game_s := 0.0                       ## game seconds spent (physics frames, scaled)
var stuck_events := 0
var blind := false                      ## the room's guards cannot notice the hero (stealth runs: the walk is under test, the sight rules are tested elsewhere)
var debug := OS.get_environment("BOTDEBUG") != ""
var trace_on := true                   ## record the cells walked (diagnosis maps)
var trace_cells := {}
var last_fail := ""                     ## why the last walk_to gave up (for test messages)

var _rws: Array[RoomWalk] = []
var _rw_key := -1
var _stick_down := false
var _last_pos := Vector3.ZERO
var _still := 0.0


func setup(h: Node) -> bool:
	host = h
	Sfx.muted = true
	Game.force_touch = true
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Engine.physics_ticks_per_second = TICK_RATE
	Engine.time_scale = float(SPEED_UP)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.name = "BotMain"
	host.add_child(main)
	await TestLib.frames(host, 30)
	p = Game.player as Player
	ig = InteriorGameplay.instance
	prog = Game.progress as Progress
	for n in main.find_children("*", "TouchControls", true, false):
		tc = n as TouchControls
	if p == null or ig == null or prog == null or tc == null:
		return false
	prog.autosave_enabled = false
	prog.path = "user://bot_interior_save.cfg"
	prog.new_campaign()
	ig.autosave = false
	var hud := host.get_tree().root.find_child("Hud", true, false) as Hud
	if hud != null and hud.settings.path == UiSettings.DEFAULT_PATH:
		hud.settings = UiSettings.new("user://bot_interior_settings.cfg")
	tc.controls_on = true
	return true


func teardown() -> void:
	release()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Sfx.muted = false
	Game.force_touch = false
	if main != null and is_instance_valid(main):
		main.queue_free()
	await TestLib.frames(host, 2)
	for f in ["user://bot_interior_save.cfg", "user://bot_interior_save.cfg.bak", "user://bot_interior_settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func frames(n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame
		game_s += host.get_physics_process_delta_time()
		_keep_alive()


## The bot is not here to be shot: the hero cannot die (the guards still fight, the door and the prompts are what is under test).
func _keep_alive() -> void:
	if is_instance_valid(p) and not p.is_dead():
		p.invuln = maxf(p.invuln, 5.0)
		p.hp = p.max_hp
	if blind and InteriorGameplay.active and is_instance_valid(ig.actors):
		for g in ig.actors.guards:
			if is_instance_valid(g):
				g.aware_dist = 0.0                  # nothing is within sight range, not even a guard the hero walks through
				g.suspicion = 0.0
		Game.heat = 0.0


func button(action: StringName) -> Dictionary:
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == action:
			return b
	return {}


## True when the touch layer is drawing the button (a phone player can only touch what is on screen).
func visible_button(action: StringName) -> bool:
	return tc.button_visible(button(action))


## Touch a button at its drawn centre. Returns false (nothing touched) when the button is not shown.
func touch(action: StringName) -> bool:
	var b := button(action)
	if b.is_empty() or not tc.button_visible(b):
		return false
	tc.touch_down(FINGER_BTN, tc.call("_button_center", b))
	await frames(3)
	tc.touch_up(FINGER_BTN)
	await frames(2)
	return true


## USE: wait (up to `secs` game seconds) for the button to appear, then touch it. Returns false when it never showed.
func use(secs := 2.0) -> bool:
	var t := 0.0
	while t < secs and not visible_button(&"interact"):
		await frames(2)
		t += 2.0 * host.get_physics_process_delta_time()
		tc._use_t = 0.0                       # the touch layer re-reads the prompt now
	return await touch(&"interact")


## A way out is on screen: the LEAVE button, or at the door the USE button that already says LEAVE.
func exit_control_visible() -> bool:
	if visible_button(&"leave_building"):
		return true
	tc._use_t = 0.0
	await frames(2)
	return visible_button(&"interact") and tc._label_of(button(&"interact")) == "LEAVE"


func prompt() -> String:
	return InteriorGameplay.prompt


## The label on the USE button right now (the first word of the prompt), "" when the button is hidden.
func use_label() -> String:
	tc._use_t = 0.0                           # the touch layer re-reads the prompt now
	await frames(2)
	if not visible_button(&"interact"):
		return ""
	return tc._label_of(button(&"interact"))


func release() -> void:
	if _stick_down:
		tc.touch_up(FINGER_STICK)
		_stick_down = false
	for a in [&"move_forward", &"sprint", &"move_left", &"move_right", &"move_back"]:
		Input.action_release(a)


## The move stick: `dir` is the wanted walking direction in the WORLD (x, z); it is turned into the stick's own frame (right / forward of the camera) so the hero goes where it is told even while the
## camera is still turning. `push` 0..1 is how far the thumb goes (0.7 = a firm walk, below the sprint threshold: a room is not a street). Without `dir` the stick is released.
func _stick(on: bool, dir := Vector2.ZERO, push := 0.7) -> void:
	var vp := host.get_viewport().get_visible_rect().size
	var s := vp.y / 720.0
	var origin := Vector2(110.0 * s, vp.y - 170.0 * s)             # left thumb zone (clear of every button on a phone and on the square headless window)
	if on and not _stick_down:
		tc.touch_down(FINGER_STICK, origin)
		_stick_down = true
	if on:
		var yaw := p.camera_rig.yaw
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var right := Vector2(cos(yaw), -sin(yaw))
		var v := Vector2(dir.dot(right), -dir.dot(fwd)) if dir != Vector2.ZERO else Vector2(0.0, -1.0)
		tc.touch_move(FINGER_STICK, origin + v.normalized() * 100.0 * s * push, Vector2(0.0, -4.0))
	elif _stick_down:
		tc.touch_up(FINGER_STICK)
		_stick_down = false


func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func face(point: Vector3) -> void:
	p.camera_rig.look_at_point(Vector3(point.x, p.global_position.y + 1.4, point.z))


## Walkability grids of the room as it is now (rebuilt when a new room is built): a wide one (a 0.5 m radius: a path on it keeps clear of every corner) and the hero's own size. Closed puzzle
## barriers do not count: USE opens them.
func grids() -> Array[RoomWalk]:
	var key := ig.enter_count * 1000 + (1 if is_instance_valid(ig.interior) else 0)
	if not _rws.is_empty() and key == _rw_key:
		return _rws
	_rw_key = key
	_rws.clear()
	var excl: Array[RID] = []
	var pz := ig.missions.puzzles
	if is_instance_valid(pz):
		for g: Dictionary in pz.gates:
			var b := g["barrier"] as StaticBody3D
			if is_instance_valid(b):
				excl.append(b.get_rid())
	for r in [0.52, RoomWalk.RADIUS]:
		var rw := RoomWalk.new()
		rw.radius = r
		rw.build((ig.interior.get("bounds") as Rect2).grow(0.5), p.get_world_3d().direct_space_state, excl)
		_rws.append(rw)
	return _rws


func grid() -> RoomWalk:
	return grids()[1]


## Walk (stick + look, along a searched path) until within `reach` of `target`. Returns true on arrival, false after `max_s` game seconds or when nothing can be reached.
func walk_to(target: Vector3, reach: float, max_s := 40.0) -> bool:
	var t0 := game_s
	var path := PackedVector3Array()
	var replan := 0
	var path_i := 1
	trace_cells.clear()
	_still = 0.0
	_last_pos = p.global_position
	while game_s - t0 < max_s:
		var pp := p.global_position
		if flat(pp, target) < reach:
			release()
			last_fail = ""
			return true
		replan -= 1
		if replan <= 0 or path.is_empty():
			replan = 20
			path = PackedVector3Array()
			for rw: RoomWalk in grids():                                  # the wide grid first: its paths keep off the corners; the hero-sized one when the wide one cannot get there
				rw.reachable(pp)
				var goal := rw.goal_near(target, reach * 0.85)
				if goal.is_finite() and flat(goal, target) <= reach:
					path = rw.path_to(goal)
					if not path.is_empty():
						break
			path_i = 1
			if path.is_empty():
				release()
				var g1 := grid()
				last_fail = "no path from %s to a cell within %.1f m of %s (reachable cells %d, gap %.1f)" % [str(pp), reach, str(target), g1.reachable(pp), g1.reach_gap(target)]
				return false
		while path_i < path.size() - 1 and flat(pp, path[path_i]) < 0.45:          # cells are passed when the hero is on them
			path_i += 1
		var next := path[mini(path_i + 1, path.size() - 1)]                       # steer at the cell after the next one (a short lookahead keeps the hero on the centre line)
		if flat(pp, path[path.size() - 1]) < 0.35:                      # at the end of the path but still outside the reach: a last small step toward the target
			next = target
		face(next)
		_stick(true, Vector2(next.x - pp.x, next.z - pp.z).normalized())
		await frames(1)
		if trace_on:
			trace_cells[grid().cell_of(p.global_position)] = true
		if flat(p.global_position, _last_pos) < 0.02:
			_still += host.get_physics_process_delta_time()
			if _still > 1.5:
				stuck_events += 1
				if debug:
					var col := ""
					for ci in p.get_slide_collision_count():
						var c := p.get_slide_collision(ci)
						col += " %s n=%s" % [str((c.get_collider() as Node).get_parent().name) + "/" + str((c.get_collider() as Node).name), str(c.get_normal())]
					var sq := PhysicsShapeQueryParameters3D.new()
					var cap := CapsuleShape3D.new()
					cap.radius = 0.4
					cap.height = 1.7
					sq.shape = cap
					sq.collision_mask = 0xFFFF
					sq.transform = Transform3D(Basis.IDENTITY, p.global_position + Vector3(0.0, 0.9, 0.0))
					sq.exclude = [p.get_rid()]
					for hit in p.get_world_3d().direct_space_state.intersect_shape(sq, 8):
						var c := hit["collider"] as Node
						print("BOTSTUCK overlapping ", c.get_path(), " layer ", (c as CollisionObject3D).collision_layer)
					print("BOTSTUCK state %s time_scale %.2f pos %s vel %s next %s yaw %.2f floor %s hp %.0f dead %s traversal %s count %d crouch %s slide %s wallrun %s" % [str(Game.state), Engine.time_scale, str(p.global_position), str(p.velocity), str(next), p.camera_rig.yaw, str(p.is_on_floor()), p.hp, str(p.is_dead()), str(p.traversal.kind), p.traversal.count, str(p.cover.crouching), str(p.cover.sliding), str(p.wall_running)])
				_still = 0.0
				replan = 0
				Input.action_press(&"jump")
				await frames(2)
				Input.action_release(&"jump")
		else:
			_still = 0.0
			_last_pos = p.global_position
	release()
	if OS.get_environment("BOTMAP") != "":
		dump_map(target)
	last_fail = "timed out after %.0f s at %s, %.1f m from %s (reach %.1f), stuck events %d, ahead: %s" % [max_s, str(p.global_position), flat(p.global_position, target), str(target), reach, stuck_events, _what_blocks()]
	return false


## ASCII floor plan of the room as the bot sees it: # blocked, . free, ~ unreachable, P the hero, T the target, * the trace of the walk (diagnosis only: BOTMAP=1).
func dump_map(target: Vector3) -> void:
	var rw := grid()
	rw.reachable(p.global_position)
	var marks := {rw.cell_of(target): "T", rw.cell_of(p.global_position): "P"}
	for c in trace_cells:
		if not marks.has(c):
			marks[c] = "o"
	print("BOTMAP origin %s hero %s target %s" % [str(rw.origin), str(p.global_position), str(target)])
	var fwd := Vector3(-sin(p.camera_rig.yaw), 0.0, -cos(p.camera_rig.yaw))
	for dd in [0.3, 0.6, 0.9, 1.2]:
		var q: Vector3 = p.global_position + fwd * dd
		var shape := CylinderShape3D.new()
		shape.radius = 0.36
		shape.height = 1.5
		var sq := PhysicsShapeQueryParameters3D.new()
		sq.shape = shape
		sq.collision_mask = Game.L_WORLD
		sq.transform = Transform3D(Basis.IDENTITY, Vector3(q.x, 0.85, q.z))
		var hits := p.get_world_3d().direct_space_state.intersect_shape(sq, 4)
		var names := ""
		for h in hits:
			names += " " + str((h["collider"] as Node).get_parent().name)
		var c := rw.cell_of(q)
		print("BOTMAP ahead %.1f m: grid blocked %s physics hits %d%s" % [dd, str(rw.blocked[rw.idx(c)] != 0 if rw.inside(c) else "outside"), hits.size(), names])
	var pz := ig.missions.puzzles
	if is_instance_valid(pz):
		for c in pz.get_children():
			if c is StaticBody3D and c.collision_layer != 0:
				var bs := (c.get_child(0) as CollisionShape3D).shape as BoxShape3D
				print("BOTMAP puzzle body at %s size %s layer %d" % [str(c.global_position), str(bs.size), c.collision_layer])
	for y in rw.rows:
		var line := ""
		for x in rw.cols:
			var c := Vector2i(x, y)
			if marks.has(c):
				line += marks[c]
			elif rw.blocked[rw.idx(c)] != 0:
				line += "#"
			elif rw.dist[rw.idx(c)] >= 0:
				line += "."
			else:
				line += "~"
		print("BOTMAP ", line)


## What stands in front of the hero (ray hits at three heights): the diagnosis a failed walk reports.
func _what_blocks() -> String:
	var pp := p.global_position
	var fwd := Vector3(-sin(p.camera_rig.yaw), 0.0, -cos(p.camera_rig.yaw))
	var out := ""
	for h in [0.3, 0.9, 1.5]:
		var q := PhysicsRayQueryParameters3D.create(pp + Vector3(0.0, h, 0.0), pp + Vector3(0.0, h, 0.0) + fwd * 2.0, 0xFFFF)
		var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var col := hit["collider"] as Node
			out += " h%.1f:%s(%s layer %d at %.1f m)" % [h, str(col.get_parent().name) + "/" + str(col.name), col.get_class(), int((col as CollisionObject3D).collision_layer) if col is CollisionObject3D else -1, pp.distance_to(hit["position"])]
	return out if out != "" else "nothing within 2 m"


## Walk to the floor-plan point nearest the exit and press LEAVE the way the door prompt asks (USE at the door), then wait for the street. Returns true when outside.
func leave_by_door(max_s := 40.0) -> bool:
	if not InteriorGameplay.active:
		last_fail = "not inside"
		return false
	var ex := InteriorGameplay.exit_point(ig.interior)
	if not await walk_to(Vector3(ex.x, 0.0, ex.z), InteriorGameplay.REACH_EXIT - 0.3, max_s):
		return false
	var t := 0.0
	while t < 1.5 and not InteriorGameplay.prompt.begins_with("LEAVE"):
		await frames(2)
		t += 2.0 * host.get_physics_process_delta_time()
	if not InteriorGameplay.prompt.begins_with("LEAVE") or not await use(2.0):
		last_fail = "the USE button never offered LEAVE at the exit (prompt '%s')" % InteriorGameplay.prompt
		return false
	var out := await wait_outside()
	if not out:
		last_fail = "USE at the exit did not leave (prompt was '%s', busy %s, vendor open %s)" % [InteriorGameplay.prompt, str(ig.busy), str(InteriorGameplay.vendor_open)]
	return out


## The LEAVE button: from anywhere. `taps` is how many times it is pressed (a job in progress asks for two).
func leave_button(taps := 1) -> bool:
	for i in taps:
		if not await touch(&"leave_building"):
			return false
	return await wait_outside()


func wait_outside(max_s := 4.0) -> bool:
	var t := 0.0
	while t < max_s and (InteriorGameplay.active or ig.busy):
		await frames(4)
		t += 4.0 * host.get_physics_process_delta_time()
	return not InteriorGameplay.active


## Go to a street door of `type` (teleport next to it: the street walk is another audit), wait for the ENTER prompt and touch USE. Falls back to the TEST menu entry when the city has no such door.
func enter_door(type: StringName) -> bool:
	if InteriorGameplay.active:
		ig.leave(true)
		await frames(3)
	var em := Game.enemies as EnemyManager
	if em != null:
		em.clear()                            # nobody hunts the hero from the street: no follower comes through the door behind him
	Game.heat = 0.0
	var list := ig.doors_of(type, p.global_position)
	var core_list := list.filter(func(d: Dictionary) -> bool: return absf((d["pos"] as Vector3).x) <= CityLayout.CORE_HALF and absf((d["pos"] as Vector3).z) <= CityLayout.CORE_HALF)
	if not core_list.is_empty():
		list = core_list                      # the rooms of the core are the audited ones (the 2080 m map has outer doors whose rooms differ with every map size)
	var entered := false
	if not list.is_empty():
		var d := list[0]
		p.teleport_to((d["pos"] as Vector3) + Vector3(0.0, 0.1, 0.0))
		await frames(8)
		Game.heat = 0.0
		if prompt().begins_with("ENTER") and await use(2.0):
			entered = await _wait_inside()
		elif ig.enter(d, true):
			entered = true
	else:
		entered = ig.test_enter(type).begins_with("INSIDE")
	await frames(6)
	return entered and InteriorGameplay.active


func _wait_inside(max_s := 4.0) -> bool:
	var t := 0.0
	while t < max_s and (not InteriorGameplay.active or ig.busy):
		await frames(4)
		t += 4.0 * host.get_physics_process_delta_time()
	return InteriorGameplay.active


## Make the room's guards harmless to the audit (the fight is tested elsewhere): they do not see the hero.
func calm_guards() -> void:
	for g in ig.actors.guards:
		if is_instance_valid(g):
			g.suspicion = 0.0
