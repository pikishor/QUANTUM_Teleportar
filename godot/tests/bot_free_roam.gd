extends RefCounted
## Look-dev bot for the free-roam world (wave 111): puts the hero (and the world) into each situation of scripts/roam/ and photographs it with the real game camera.
##   BOT_RES=1200x540 ENGINE_ARGS="--fixed-fps 30" tools/bot.sh res://tests/bot_free_roam.gd OUT 50 N        (one view per 50 frames, N views)
## env RW_VIEWS = comma list (default below):
##   pad        a found QUANTUM PAD ring and beam at the airport, 30 m away
##   travel     standing on a found pad: the travel panel with the found pads as buttons
##   relic      the scanner pulse shows a relic in the mountains (ring and beam)
##   fish       the harbour pier at dusk: line cast, bobber, the prompt line
##   stunt      a stunt ramp on the desert road with the landing ring
##   race       the start ring of a landmark race on the road, a sport car behind it
##   crash      SUPPLY CRASH on the plains (smoke, ring)
##   raid       ALIEN RAID at night
##   convoy     the smuggler convoy on its road
##   smugglers  guards and a van at the stash
##   photo      a photo spot ring (the sunset light at the lighthouse)
##   map        the big map with the pads, photo spots, fishing places and the counter
const E := 50

var _n := 0
var _views: Array[String] = []
var _vm: VehicleManager
var _rw: RoamWorld
var _look := Vector3.INF
var _veh: Vehicle
var _ev: Dictionary = {}


func _init() -> void:
	var v := OS.get_environment("RW_VIEWS")
	for s in (v if v != "" else "pad,travel,relic,fish,stunt,race,crash,raid,convoy,smugglers,photo,map").split(",", false):
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
		_vm = Game.vehicles as VehicleManager
		_vm.stream_every = 1.0e9
		_vm._stream_t = 1.0e9
		_rw = Freedom.current.roam_world
		_rw.reset()
		_rw.events.enabled = false
		var m := Game.missions as Missions
		m.campaign.guide_enabled = false
		m.board.auto_open = false
	if _n < 20 or not TerrainMap.ready:
		return false
	var idx := (_n - 20) / E
	var k := (_n - 20) % E
	if idx >= _views.size():
		return true
	_view(p, _views[idx], k)
	if _look.is_finite() and is_instance_valid(p):
		var from: Vector3 = p.global_position
		p.camera_rig.yaw = atan2(-(_look.x - from.x), -(_look.z - from.z))
		p.camera_rig.pitch = -0.04
	return false


func _land(p: Player, at: Vector3, off := Vector3.ZERO) -> void:
	_leave(p)
	var q := at + off
	p.teleport_to(Vector3(q.x, TerrainHeight.height_at(q.x, q.z) + 1.0, q.z))


func _leave(p: Player) -> void:
	if _vm.driven != null:
		_vm.exit_vehicle()
	for a in [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"crouch"]:
		Input.action_release(a)


func _spawn(kind: StringName, at: Vector3, h: float) -> Vehicle:
	var v := _vm.spawn_parked(kind, at, h)
	var tries := 0
	while v == null and tries < 12:                                      # the pool is full of street cars: free the farthest ones
		_vm._release_farthest(at)
		v = _vm.spawn_parked(kind, at, h)
		tries += 1
	if v != null:
		v.set_meta(&"hold", true)
	return v


func _enter(p: Player, v: Vehicle, k: int) -> void:
	if k == 4:
		p.teleport_to(v.global_position + v.right() * 2.4 + Vector3(0.0, 0.2, 0.0))
	elif k == 8:
		_vm.enter(v)                                                     # the same two steps as the tests: stand beside it, a few frames later get in


func _hour(h: float) -> void:
	RoamData.hour_override = h
	if is_instance_valid(Game.world):
		(Game.world as City).day_night.set_hour(h)


func _view(p: Player, view: String, k: int) -> void:
	if k == 0:
		_rw.events.reset()                                            # each view starts clean: the last event's wreck, raiders and ring are gone
		if AlienWorld.instance != null:
			AlienWorld.instance.clear_all()
		Input.action_release(&"move_forward")
		_veh = null
		_ev = {}
	match view:
		"pad":
			if k == 0:
				_hour(11.0)
				var pd := RoamData.pad(&"airport")
				_rw.found_pad(&"airport")
				_land(p, pd["pos"], Vector3(-26.0, 0.0, 14.0))
				_look = pd["pos"]
		"travel":
			if k == 0:
				_hour(11.0)
				_rw.found_pad(&"airport")
				_rw.found_pad(&"hub")
				_rw.found_pad(&"observatory")
				_rw.found_pad(&"harbour")
				_rw.found_pad(&"dust_wells")
				var pd2 := RoamData.pad(&"observatory")
				_rw.travel._quiet = &""
				_land(p, pd2["pos"])
				_look = (pd2["pos"] as Vector3) + Vector3(-30.0, 40.0, -80.0)
		"relic":
			if k == 0:
				_hour(11.0)
				var rl: Dictionary = {}
				for r in RoamData.relics():
					if r["biome"] == &"mountain":
						rl = r
						break
				var rp: Vector3 = rl["pos"]
				var best_o := Vector3(50.0, 0.0, 0.0)
				var best_h := -1.0e9
				for a in 8:
					var o := Vector3(cos(TAU * float(a) / 8.0) * 50.0, 0.0, sin(TAU * float(a) / 8.0) * 50.0)
					var gh := TerrainHeight.height_at(rp.x + o.x, rp.z + o.z)
					if gh > best_h:
						best_h = gh
						best_o = o
				_land(p, rp, best_o)                              # stand on the high side: the ring on the ground is seen from above
				Gear.give(&"scanner")
				Gear.equip(&"scanner")
				_look = rl["pos"]
			elif k == 6:
				_rw.scan(p.global_position)
		"fish":
			if k == 0:
				_hour(18.7)
				for f in RoamData.fish_spots():
					if f["id"] == &"fs_pier":
						_land(p, f["pos"])
						p.teleport_to((f["pos"] as Vector3) + Vector3(0.0, 1.2, 0.0))
						_look = (f["pos"] as Vector3) + (f["cast"] as Vector3) * 14.0
						_ev = f
			elif k == 4:
				_rw.fishing.cast_now(_ev)
			elif k == 18:
				_rw.fishing.force_bite()
		"stunt":
			if k == 0:
				_hour(15.0)
				var s: Dictionary = RoamData.stunts()[1]
				_land(p, s["pos"], -(s["dir"] as Vector3) * 38.0)
				_veh = _spawn(&"suv", (s["pos"] as Vector3) - (s["dir"] as Vector3) * 30.0, float(s["yaw"]))
				_look = Vector3.INF
				_ev = s
			elif _veh != null:
				_enter(p, _veh, k)
			if _veh != null and k > 12 and k < 60 and _rw.runs.attempts == 0:
				Input.action_press(&"move_forward")
		"race":
			if k == 0:
				_hour(9.0)
				var r: Dictionary = RoamData.races()[0]
				var hf := Vector3(-sin(float(r["heading"])), 0.0, -cos(float(r["heading"])))
				_land(p, r["start"], -hf * 40.0)
				_veh = _spawn(&"sport", (r["start"] as Vector3) - hf * 34.0, float(r["heading"]))
				Input.action_release(&"move_forward")
				_look = Vector3.INF
			elif _veh != null:
				_enter(p, _veh, k)
		"crash":
			if k == 0:
				_hour(14.0)
				var pl := _plains()
				_land(p, pl)
				_ev = _rw.events.spawn(&"crash", pl + Vector3(0.0, 0.0, -30.0))
				_look = _ev["pos"]
		"raid":
			if k == 0:
				_hour(23.0)
				var pl2 := _plains()
				_land(p, pl2)
				_ev = _rw.events.spawn(&"raid", pl2 + Vector3(0.0, 0.0, -48.0))
				_look = _ev["pos"]
		"convoy":
			if k == 0:
				_hour(10.0)
				var rt := WorldSites.road_route("DESERT ROAD")
				var q := rt[rt.size() / 3]
				_land(p, q, Vector3(40.0, 0.0, 0.0))
				_ev = _rw.events.spawn_near(p.global_position, &"convoy")
				print("BOT convoy: spawned=%s can=%s hero=%s biome=%s" % [str(not _ev.is_empty()), str(_rw.events.can_spawn_at(p.global_position)), str(p.global_position), str(TerrainBase.biome_at(p.global_position.x, p.global_position.z, p.global_position.y))])
				_look = (_ev["pos"] as Vector3) if not _ev.is_empty() else Vector3.INF
			elif k == 3 and not _ev.is_empty():
				var lead := (_ev["vehicles"] as Array)[0] as Vehicle                   # the hero stands 45 m behind the truck, on the road
				var fwd := lead.forward()
				var hp := lead.global_position - fwd * 45.0
				p.teleport_to(Vector3(hp.x, TerrainHeight.height_at(hp.x, hp.z) + 1.0, hp.z))
			elif not _ev.is_empty() and k > 5:
				var lv := (_ev["vehicles"] as Array)[0] as Vehicle
				if is_instance_valid(lv):
					_look = lv.global_position
		"smugglers":
			if k == 0:
				_hour(16.0)
				var pl3 := _plains()
				_land(p, pl3)
				_ev = _rw.events.spawn(&"smugglers", pl3 + Vector3(0.0, 0.0, -28.0))
				_look = _ev["pos"]
		"photo":
			if k == 0:
				_hour(18.6)
				for s2 in RoamData.photo_spots():
					if s2["id"] == &"ph_lighthouse":
						_land(p, s2["pos"], Vector3(-50.0, 0.0, -30.0))
						_look = s2["pos"]
		"map":
			if k == 0:
				_hour(11.0)
				for id: StringName in [&"airport", &"hub", &"observatory", &"harbour"]:
					_rw.found_pad(id)
				_look = Vector3.INF
			elif k == 10:
				var hud := Game.get_tree().root.find_child("Hud", true, false) as Hud
				if hud != null:
					var ms := hud.touch.get_node_or_null("MapScreen") as MapScreen
					if ms == null:
						hud.touch.open_map()
						ms = hud.touch.get_node_or_null("MapScreen") as MapScreen
					else:
						ms.open()
					if ms != null:
						ms.discover(p.global_position)
						ms.set_world_mode(true)


func _plains() -> Vector3:
	for r in RoamData.relics():
		if r["biome"] == &"plains":
			var q: Vector3 = r["pos"]
			return q + Vector3(40.0, 0.0, 40.0)                       # never on the relic itself (it would be picked up)
	return RoamData.relics()[0]["pos"]
