extends RefCounted
## Shared helpers of the three world-mission tests (test_world_missions, test_world_missions_air, test_world_roam): boot the real game scene, put the hero into vehicles, autopilots for a
## ground vehicle / boat (path following through the real inputs) and for a helicopter, starting a board mission and waiting on its steps. Counters and positions, never frame counts.

const K := 3

var _host: Node
var _p: Player
var _vm: VehicleManager
var _board: MissionBoard
var _camp: CampaignRunner
var _roam: WorldRoam


func _until(cond: Callable, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < secs:
		if cond.call():
			return true
		await _host.get_tree().process_frame
	return cond.call()


func _hold(secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < secs:
		await _host.get_tree().process_frame


func _release() -> void:
	for a in [&"move_forward", &"move_back", &"move_left", &"move_right", &"fire", &"jump", &"crouch", &"interact", &"sprint"]:
		Input.action_release(a)


func _boot(host: Node) -> Node:
	CarRadio.auto_headless = true
	Game.quality = 1
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	_p = Game.player as Player
	_vm = Game.vehicles as VehicleManager
	var m := Game.missions as Missions
	_board = m.board if m != null else null
	_camp = m.campaign if m != null else null
	var fr := Freedom.current
	_roam = fr.roam if fr != null else null
	TestLib.check(_p != null and _vm != null and _board != null and _camp != null, "the real scene has a player, vehicles, a board and a campaign runner")
	TestLib.check(_roam != null and WorldRoam.instance == _roam and _roam.get_parent() == fr, "Freedom owns the free-roam activities")
	if _p == null or _vm == null or _board == null or _roam == null:
		main.queue_free()
		CarRadio.auto_headless = false
		return null
	_p.set_physics_process(true)
	_p.max_hp = 1.0e6
	_p.hp = _p.max_hp
	(Game.enemies as EnemyManager).clear()
	_vm.stream_every = 1.0e9
	_vm._stream_t = 1.0e9
	if NearTraffic.instance != null:                      # no street traffic near the strip or the avenue
		for i in NearTraffic.instance.count:
			NearTraffic.instance._alive[i] = 0
	_camp.guide_enabled = false
	_roam.reset()
	_board.world_offers = true
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	return main


func _shutdown(main: Node) -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	_release()
	if is_instance_valid(_p):
		_p.control_hold = false
	CarRadio.auto_headless = false
	if main != null:
		main.queue_free()
	await TestLib.frames(_host, 2)


func _clear_vehicles() -> void:
	_release()
	if _vm.driven != null:
		_vm.exit_vehicle()
	for v in _vm.list.duplicate():
		if v != _vm.starter and not v.has_meta(&"hold"):
			_vm._release(v)


## Puts the hero in `v` (beside it, then through the real enter).
func _enter(v: Vehicle) -> void:
	if _vm.driven != null and _vm.driven != v:
		_vm.exit_vehicle()
	_p.teleport_to(v.global_position + v.right() * 2.4 + Vector3(0.0, 0.2, 0.0))
	await TestLib.frames(_host, 2)
	_vm.enter(v)
	await TestLib.frames(_host, 1)


## An autopilot for a ground vehicle or a boat: follows `pf` at about `want` m/s through the same inputs a player has.
func _steer_along(v: Vehicle, pf: PathFollow, want: float) -> void:
	var st := pf.drive(v, want, 0.016)
	v.script_thr = 0.0
	v.script_steer = 0.0
	Input.action_release(&"move_forward")
	Input.action_release(&"move_back")
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	if st.x >= 0.0:
		Input.action_press(&"move_forward", st.x)
	else:
		Input.action_press(&"move_back", -st.x)
	if st.y >= 0.0:
		Input.action_press(&"move_right", st.y)
	else:
		Input.action_press(&"move_left", -st.y)


## An autopilot for a helicopter: yaw at the target, fly when roughly pointed at it, climb or descend to its height.
func _fly_toward(h: Vehicle, tgt: Vector3, speed_ok := true) -> void:
	var dx := tgt.x - h.global_position.x
	var dz := tgt.z - h.global_position.z
	var hd := atan2(-dx, -dz)
	var err := wrapf(hd - h.heading, -PI, PI)
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	if err > 0.05:
		Input.action_press(&"move_left", clampf(err * 1.6, 0.15, 1.0))
	elif err < -0.05:
		Input.action_press(&"move_right", clampf(-err * 1.6, 0.15, 1.0))
	if absf(err) < 0.7 and speed_ok:
		Input.action_press(&"move_forward", 1.0)
	else:
		Input.action_release(&"move_forward")
	var dy := tgt.y - h.global_position.y
	if dy > 2.0:
		Input.action_press(&"jump")
		Input.action_release(&"crouch")
	elif dy < -2.0:
		Input.action_press(&"crouch")
		Input.action_release(&"jump")
	else:
		Input.action_release(&"jump")
		Input.action_release(&"crouch")


## Brings a helicopter down on `at`: over it at cruise height, then straight down with DOWN held until the skids touch (the flare makes it soft).
func _land_toward(h: Vector3, at: Vector3, heli: Vehicle) -> void:
	var far := Vector2(heli.global_position.x - at.x, heli.global_position.z - at.z).length()
	if far > 14.0:
		_fly_toward(heli, Vector3(at.x, maxf(at.y + 18.0, minf(heli.global_position.y, at.y + 40.0)), at.z))
		Input.action_release(&"crouch")
		return
	_fly_toward(heli, Vector3(at.x, heli.global_position.y, at.z), far > 4.0)
	Input.action_release(&"jump")
	Input.action_press(&"crouch")


## Starts the offer, waits for the first step; returns the offer ({} when the board refused).
func _start(t: StringName, origin: Vector3) -> Dictionary:
	_release()
	if _board.is_running():
		_board.abandon("TEST")
		await TestLib.frames(_host, 2)
	var o := _board.build(t, origin)
	if o.is_empty():
		TestLib.check(false, "%s: the board builds an offer" % t)
		return {}
	var ok := _board.accept_offer(o)
	TestLib.check(ok, "%s: the board starts the mission" % t)
	if not ok:
		return {}
	await _until(func() -> bool: return _camp.state == &"active", 8.0)
	return o


func _step_is(idx: int, kind: StringName, secs := 8.0) -> bool:
	return await _until(func() -> bool: return _camp.state == &"active" and _camp.step_index == idx and _camp.kind == kind and (kind != &"pursuit" or (_camp.ws.target != null)), secs)


func _land_hero(at: Vector3) -> void:
	_p.teleport_to(Vector3(at.x, TerrainHeight.height_at(at.x, at.z) + 1.0, at.z))
	await _hold(0.6)


func _finish_check(o: Dictionary, label: String, credits0: int, done0: int) -> void:
	var prog := Game.progress as Progress
	var done := await _until(func() -> bool: return _board.state == &"idle" and bool(_board.last_result.get("ok", false)), 8.0)
	TestLib.check(done, "%s: the board reports the mission done (state %s, result %s)" % [label, _board.state, str(_board.last_result)])
	TestLib.check(prog.credits >= credits0 + int(o["reward"]), "%s: it paid %d credits (%d -> %d)" % [label, int(o["reward"]), credits0, prog.credits])
	TestLib.check(MissionRewards.missions_done == done0 + 1, "%s: it counts as a mission for the weapon ladder (%d -> %d)" % [label, done0, MissionRewards.missions_done])


## True when no point of the segments between the gates lies within `clear` metres below the terrain (and every gate stands that high).
func _legs_clear(gs: Array[Vector3], clear: float) -> bool:
	for i in gs.size():
		var g := gs[i]
		if g.y < TerrainHeight.height_at(g.x, g.z) + clear:
			printerr("gate %d at %s is %.1f m over the ground" % [i, str(g), g.y - TerrainHeight.height_at(g.x, g.z)])
			return false
		if i > 0:
			var a := gs[i - 1]
			for k in range(1, 12):
				var q := a.lerp(g, float(k) / 12.0)
				if q.y < TerrainHeight.height_at(q.x, q.z) + clear * 0.5:
					printerr("leg %d-%d dips to %.1f m over the ground at %s" % [i - 1, i, q.y - TerrainHeight.height_at(q.x, q.z), str(q)])
					return false
	return true
