extends RefCounted
## Look-dev bot for the air and vehicle missions and the free-roam courses (wave 107): runs the REAL board missions and activities frame by frame and photographs them with the real game camera.
##   BOT_RES=1200x540 ENGINE_ARGS="--fixed-fps 30" tools/bot.sh res://tests/bot_world_missions.gd OUT 90 N        (one view per 90 frames, N views)
## env WM_VIEWS = comma list of views (default: board,pursuit,river,race,school,treasure):
##   board      the Mission Board screen with a world mission on offer (hero at the lodge)
##   pursuit    MOUNTAIN PURSUIT: the hero in the 4x4 on QUARRY TRACK, the smuggler's pickup 70 m ahead on the road
##   river      RIVER CHASE: the hero in the speedboat on the river, the smuggler's boat ahead
##   race       AIR RACE: the hero in the helicopter in EASTWATER CANYON with the gate rings ahead
##   school     FLIGHT SCHOOL: the start ring on the runway of the airport and its beam
##   trial      OFF-ROAD TRIAL: the rover on QUARRY TRACK under way through the gate rings
##   treasure   TREASURE HUNT: the scanner pulse reveals a cache (the beam)
const E := 90

var _n := 0
var _views: Array[String] = []
var _pf: PathFollow
var _vm: VehicleManager
var _board: MissionBoard
var _camp: CampaignRunner
var _hero_veh: Vehicle


func _init() -> void:
	var v := OS.get_environment("WM_VIEWS")
	for s in (v if v != "" else "board,pursuit,river,school,treasure,race").split(",", false):
		_views.append(s.strip_edges())


func step(_t: float, _d: float) -> bool:
	var p := Game.player as Player
	if p == null:
		return false
	_n += 1
	if _n == 1:
		Game.state = &"play"
		p.max_hp = 1.0e6
		p.hp = p.max_hp
		if Game.enemies != null:
			(Game.enemies as EnemyManager).clear()
		if is_instance_valid(Game.atmosphere):
			(Game.atmosphere as Atmosphere).set_weather(0.0, 0.15)
		if is_instance_valid(Game.world):
			(Game.world as City).day_night.set_hour(11.0)
		_vm = Game.vehicles as VehicleManager
		_vm.stream_every = 1.0e9
		_vm._stream_t = 1.0e9
		var m := Game.missions as Missions
		_board = m.board
		_camp = m.campaign
		_camp.guide_enabled = false
		_board.world_offers = true
		_board.auto_open = false
	var idx := (_n - 1) / E
	var k := (_n - 1) % E
	if idx >= _views.size():
		return true
	_view(p, _views[idx], k)
	return false


func _land(p: Player, at: Vector3) -> void:
	p.teleport_to(Vector3(at.x, TerrainHeight.height_at(at.x, at.z) + 1.0, at.z))


func _begin(t: StringName, origin: Vector3) -> void:
	if _board.is_running():
		_board.abandon("BOT")
	var o := _board.build(t, origin)
	_board.accept_offer(o)


func _enter_first_provided(p: Player) -> bool:
	if _camp.ws == null or _camp.ws.provided.is_empty():
		return false
	var v: Vehicle = _camp.ws.provided[0]
	if _vm.driven != v:
		p.teleport_to(v.global_position + v.right() * 2.4 + Vector3(0.0, 0.2, 0.0))
		_vm.enter(v)
	_hero_veh = v
	return _vm.driven == v


func _steer(v: Vehicle, pf: PathFollow, want: float) -> void:
	var st := pf.drive(v, want, 0.016)
	v.script_thr = 0.0
	v.script_steer = 0.0
	for a in [&"move_forward", &"move_back", &"move_left", &"move_right"]:
		Input.action_release(a)
	if st.x >= 0.0:
		Input.action_press(&"move_forward", st.x)
	else:
		Input.action_press(&"move_back", -st.x)
	if st.y >= 0.0:
		Input.action_press(&"move_right", st.y)
	else:
		Input.action_press(&"move_left", -st.y)


func _fly(h: Vehicle, tgt: Vector3) -> void:
	var dx := tgt.x - h.global_position.x
	var dz := tgt.z - h.global_position.z
	var err := wrapf(atan2(-dx, -dz) - h.heading, -PI, PI)
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	if err > 0.05:
		Input.action_press(&"move_left", clampf(err * 1.6, 0.15, 1.0))
	elif err < -0.05:
		Input.action_press(&"move_right", clampf(-err * 1.6, 0.15, 1.0))
	if absf(err) < 0.7:
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


func _view(p: Player, v: String, k: int) -> void:
	var hud := p.get_tree().get_first_node_in_group(&"hud") as Hud
	if k == 0 and v != "board" and hud != null:
		hud._board_open = false
		Game.state = &"play"
	if k == 0 and _vm.driven != null:
		_release_inputs()
		_vm.exit_vehicle()
	match v:
		"board":
			if k == 0:
				if _vm.driven != null:
					_vm.exit_vehicle()
				_land(p, Vector3(-385.0, 0.0, -1960.0))
				_board.abandon("BOT")
				_board.generate(p.global_position)
			elif k == 10 and hud != null:
				hud.open_board()
		"pursuit":
			if k == 0:
				if hud != null:
					hud._board_open = false
				Game.state = &"play"
				_land(p, Vector3(1520.0, 0.0, 330.0))
				_begin(&"mountain_pursuit", p.global_position)
			elif k > 3:
				if _vm.driven == null:
					if _enter_first_provided(p):
						_pf = PathFollow.new(WorldSites.road_route("QUARRY TRACK"))
				elif _camp.kind == &"pursuit" and _pf != null:
					_steer(_vm.driven, _pf, 17.0)
		"river":
			if k == 0:
				_release_inputs()
				if _vm.driven != null:
					_vm.exit_vehicle()
				WaterLayout.ensure()
				var rp: PackedVector2Array = (WaterLayout.paths[0] as Dictionary)["pos"]
				_land(p, Vector3(rp[150].x + 40.0, 0.0, rp[150].y + 40.0))
				_begin(&"river_chase", p.global_position)
				_pf = null
			elif k > 3:
				if _vm.driven == null:
					if _enter_first_provided(p):
						_pf = PathFollow.new(WorldSites.river_route(0, 150, 268))
				elif _camp.kind == &"pursuit" and _pf != null:
					_steer(_vm.driven, _pf, 20.0)
		"race":
			if k == 0:
				_release_inputs()
				if _vm.driven != null:
					_vm.exit_vehicle()
				var pad := WorldSites.pad(&"dust_wells")
				_land(p, (pad["pos"] as Vector3) + Vector3(0.0, 0.0, 30.0))
				_begin(&"air_race", pad["pos"])
			elif k > 3:
				if _vm.driven == null:
					_enter_first_provided(p)
				elif _camp.kind == &"gates" and _camp.ws.gi < _camp.ws.gates.size():
					var ws := _camp.ws
					if k == 20 and ws.gi == 0:                            # a hop to 120 m before gate 3 so the rings are in view (the test flew the whole course)
						var g2: Vector3 = ws.gates[2]
						var g1: Vector3 = ws.gates[1]
						var dir := (g2 - g1).normalized()
						_vm.driven.global_position = g1 - dir * 60.0
						_vm.driven.heading = atan2(-dir.x, -dir.z)
						_vm.driven.rotation.y = _vm.driven.heading
						ws.gi = 1
						ws.marks.show_gate(ws.gates, 1, float(_camp.step["radius"]), false)
						_camp.pos = ws.gates[1]
					_fly(_vm.driven, ws.gates[ws.gi])
		"school":
			if k == 0:
				_release_inputs()
				if _vm.driven != null:
					_vm.exit_vehicle()
				_board.abandon("BOT")
				var st: Vector3 = Freedom.current.roam.course(&"flight_school")["start"]
				_land(p, st + Vector3(-10.0, 0.0, 70.0))
				p.camera_rig.yaw = 0.0
		"trial":
			if k == 0:
				_release_inputs()
				_board.abandon("BOT")
				var c: Dictionary = Freedom.current.roam.course(&"offroad")
				var st2: Vector3 = c["start"]
				_land(p, st2 + Vector3(8.0, 0.0, 10.0))
				_pf = PathFollow.new(WorldSites.road_route("QUARRY TRACK"))
				_hero_veh = _vm.spawn_parked(&"rover", st2 + Vector3(0.0, 0.0, 2.0), WorldMissions.heading_to(st2, (c["gates"] as Array)[0]))
			elif k == 6 and _hero_veh != null:
				p.teleport_to(_hero_veh.global_position + _hero_veh.right() * 2.4 + Vector3(0.0, 0.2, 0.0))
				_vm.enter(_hero_veh)
			elif k > 8 and _vm.driven != null and _pf != null:
				_steer(_vm.driven, _pf, 14.0)
		"treasure":
			if k == 0:
				_release_inputs()
				var c0: Vector3 = Freedom.current.roam.caches()[0]["pos"]
				_land(p, c0 + Vector3(34.0, 0.0, 6.0))
				Gear.give(&"scanner")
				Gear.equip(&"scanner")
				p.camera_rig.yaw = PI * 0.5
			elif k == 20:
				p.energy = 100.0
				p.gadgets.use()


func _release_inputs() -> void:
	for a in [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"crouch", &"fire"]:
		Input.action_release(a)
