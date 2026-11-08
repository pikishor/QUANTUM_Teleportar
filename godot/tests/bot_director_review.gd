extends RefCounted
## Creative director review bot (docs/SLICE_REVIEW.md): plays the real game from the title like a new player and saves frames at the phone resolution.
## Acts (DR_ACTS, comma list, run in order): title (title screen, PLAY, the first seconds), first (the first objective, the way the mission audit bot plays it), fight (the director's opening
## fight), civ (shooting a bystander), car (take a car, drive, crash, look at the wreck), interior (walk to a real door, go in, look round), menus (pause, map, options, loadout, MORE).
##   DR_OUT=<dir> DR_ACTS=title,first BOT_RES=2400x1080 QUALITY=0 ENGINE_ARGS="--fixed-fps 12" BOT_USER_ARGS="--touch" tools/bot.sh res://tests/bot_director_review.gd /tmp/x 100000 1
## Frames: <dir>/<nn>_<act>_<name>.png. Lines starting DR print what the HUD said and what the world did, one per sample.

const FightBot := preload("res://tests/fight_bot.gd")
const Audit := preload("res://tests/mission_audit.gd")

var _out := ""
var _acts: PackedStringArray = []
var _ai := -1
var _t := 0.0                       ## game seconds in the current act
var _gt := 0.0
var _n := 0                         ## frame counter for the file names
var _saving := false
var _hud: Hud
var _p: Player
var _audit: Audit
var _fight: FightBot
var _stage := 0
var _next_snap := 0.0
var _setup_done := false
var _done := false
var _snap_gap := 3.0
var _data := {}
var _held := {}


func _init() -> void:
	_out = OS.get_environment("DR_OUT")
	var a := OS.get_environment("DR_ACTS")
	_acts = (a if a != "" else "title,first,fight,civ,car,interior,menus").split(",")


func _snap(name: String) -> void:
	if _saving:
		return
	_saving = true
	var tag := "%02d_%s_%s" % [_n, _acts[_ai], name]
	_n += 1
	await RenderingServer.frame_post_draw
	var img := _hud.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, tag])
	print("DR frame ", tag, " | state=", Game.state, " line='", _line(), "' hp=%.0f heat=%.1f" % [_p.hp if _p != null else -1.0, Game.heat])
	_saving = false


func _line() -> String:
	var m := Game.missions as Missions
	if m == null or m.campaign == null:
		return ""
	var c: CampaignRunner = m.campaign
	return "%s | guide %s | state %s kind %s" % [c.hud_line(), c.guide.line() if c.guide != null else "", str(c.state), str(c.kind)]


func _hold(a: StringName, on: bool) -> void:
	if on and not _held.get(a, false):
		Input.action_press(a)
		_held[a] = true
	elif not on and _held.get(a, false):
		Input.action_release(a)
		_held[a] = false


func _release() -> void:
	for a: StringName in _held.keys():
		Input.action_release(a)
	_held.clear()
	if _audit != null:
		_audit._release_all()


func _setup() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	_hud = tree.get_first_node_in_group(&"hud") as Hud
	_p = Game.player as Player
	if _hud == null or _p == null or Game.enemies == null or not (Game.missions is Missions):
		return false
	for n in tree.root.find_children("*", "AutoQuality", true, false):
		(n as AutoQuality).enabled = false
	for n in tree.root.find_children("*", "Stability", true, false):
		n.set_process(false)
	if _hud.settings.path == UiSettings.DEFAULT_PATH:
		_hud.settings = UiSettings.new("user://bot_director.cfg")
	_hud.touch.controls_on = true
	DirAccess.make_dir_recursive_absolute(_out)
	var prog := Game.progress as Progress
	if prog != null:
		prog.autosave_enabled = false
		prog.path = "user://bot_director_save.cfg"
	_audit = Audit.new()
	_audit.host = tree.root
	_audit.p = _p
	var m := Game.missions as Missions
	_audit.camp = m.campaign
	m.campaign.enabled = true
	_audit.story = Game.story as Story
	_audit.em = Game.enemies as EnemyManager
	_audit.vm = Game.vehicles as VehicleManager
	_audit.ig = InteriorGameplay.instance
	_audit._fight = FightBot.new()
	_audit._fight.p = _p
	if not _acts.has("title"):
		Game.start_new_game()
		if Game.story != null:
			(Game.story as Story).skip_cards()
	_setup_done = true
	return true


func step(_unused: float, delta: float) -> bool:
	if _done:
		return true
	if not _setup_done:
		if not _setup():
			return false
	if _saving:
		return false
	_t += delta
	_gt += delta
	_audit.dt = delta
	_audit.game_clock = _gt
	_audit._end_taps()
	if _ai < 0 or _act_finished:
		_start_next()
		if _done:
			return true
		return false
	call("_act_" + _acts[_ai], delta)
	return false


var _act_finished := false


func _start_next() -> void:
	_release()
	_ai += 1
	_act_finished = false
	_t = 0.0
	_stage = 0
	_next_snap = 0.0
	_data.clear()
	if _ai >= _acts.size():
		_done = true
		print("DR_DONE frames=", _n)
		if OS.get_environment("BOT_FASTEXIT") != "":
			OS.kill(OS.get_process_id())
		return
	print("DR act ", _acts[_ai])
	Game.state = &"play"
	_hud._on_state(&"play")
	_p.invuln = 0.0


func _finish() -> void:
	_act_finished = true


## Every `gap` game seconds a frame called name_nn; returns true when one was taken.
func _tick_snap(name: String, gap: float) -> bool:
	if _t >= _next_snap:
		_next_snap = _t + gap
		_snap("%s%03d" % [name, int(_t * 10.0)])
		return true
	return false


# --- title and the first seconds -----------------------------------------------------------------------------------------------

func _act_title(_dt: float) -> void:
	match _stage:
		0:
			Game.state = &"menu"
			_hud._on_state(&"menu")
			_hud.screen_age = 5.0
			_stage = 1
			_t = 0.0
		1:
			if _t > 1.2:
				_snap("title")
				_stage = 2
				_t = 0.0
		2:
			_hud.press_button(&"menu_gear")
			_hud._ensure_layout()
			_stage = 3
			_t = 0.0
		3:
			if _t > 0.8:
				_snap("title_more")
				_hud.press_button(&"options")
				_hud._ensure_layout()
				_stage = 4
				_t = 0.0
		4:
			if _t > 0.8:
				_snap("title_options")
				Game.state = &"play"
				Game.state = &"menu"
				_hud._on_state(&"menu")
				_hud._ensure_layout()
				_stage = 5
				_t = 0.0
		5:
			if _t > 0.5:
				_hud.press_button(&"continue" if _hud._has_save else &"deploy")
				_stage = 6
				_t = 0.0
				_next_snap = 0.3
		6:
			# PLAY pressed: what does a new player see in the first 16 seconds? (no skipping)
			if _tick_snap("play", 1.6):
				print("DR first seconds t=%.1f state=%s cards=%s cine=%s" % [_t, str(Game.state), str(Game.story.cards_active() if Game.story != null else false), str(Cinematics.instance.active if Cinematics.instance != null else false)])
			if _t > 16.0:
				_finish()


# --- the first objective -------------------------------------------------------------------------------------------------------

func _act_first(dt: float) -> void:
	_p.invuln = 0.0
	if _stage == 0:
		_stage = 1
		_t = 0.0
		_next_snap = 0.2
		Game.state = &"play"
	var camp: CampaignRunner = (Game.missions as Missions).campaign
	if _audit._globals():
		_tick_snap("gate", 2.0)
		return
	_audit.heal_up()
	_audit._tick_campaign()
	if _tick_snap("obj", 4.0):
		var wp := camp.waypoint()
		print("DR first t=%.0f wp=%s pos=(%.0f,%.0f) foes=%d" % [_t, str(wp.get("pos", "none")), _p.global_position.x, _p.global_position.z, camp.foes_alive()])
	if _t > float(OS.get_environment("DR_FIRST_SECONDS") if OS.get_environment("DR_FIRST_SECONDS") != "" else "70"):
		print("DR first-end trace: ", "\n".join(_audit.trace))
		print("DR first-end findings: ", _audit.findings)
		_finish()


# --- the director's fight ------------------------------------------------------------------------------------------------------

func _act_fight(delta: float) -> void:
	var mgr := Game.enemies as EnemyManager
	if _stage == 0:
		_stage = 1
		_t = 0.0
		_next_snap = 0.5
		_audit.camp.abort()
		_audit.camp.enabled = false
		var m := Game.missions as Missions
		m.contracts.enabled = false
		mgr.patrol_groups().clear()
		mgr.clear()
		for id: StringName in WeaponDefs.IDS:
			WeaponDefs.unlock(id)
		_p.weapon.switch_to(&"carbine", true)
		_p.teleport_to(Vector3(-30.0, 0.0, 4.0))
		Game.heat = 0.0
		Game.civilian_casualties = false
		var enc := Encounters.current
		enc.enabled = true
		enc.reset()
		_fight = FightBot.new()
		_fight.setup(_p)
		_fight.aim_error = 0.02
		_fight.strafe_fire = OS.get_environment("DR_PLANTED") == ""            # a player moves; DR_PLANTED=1 is the old standing bot
		_data["near_min"] = 999.0
		_data["aware_max"] = 0
		_data["first_seen"] = -1.0
		_data["turn"] = -10.0
	Game.state = &"play"
	var enc := Encounters.current
	if is_instance_valid(Game.story):
		(Game.story as Story).skip_cards()
	_fight.step(delta)
	_p.invuln = 5.0
	if _fight.target == null and not enc.squad.is_empty() and _t - float(_data["turn"]) > 1.5:
		var near: Drone = null
		var bd := 1.0e9
		for d in enc.squad:
			if is_instance_valid(d) and d.active and not d.dead and d.global_position.distance_to(_p.global_position) < bd:
				bd = d.global_position.distance_to(_p.global_position)
				near = d
		if near != null:
			_data["turn"] = _t
			_p.camera_rig.aim_at(near.center())
	var aware := 0
	for e in mgr.list:
		if e.active and not e.dead:
			var d := e.global_position.distance_to(_p.global_position)
			_data["near_min"] = minf(float(_data["near_min"]), d)
			if e.aware:
				aware += 1
	_data["aware_max"] = maxi(int(_data["aware_max"]), aware)
	if aware > 0 and float(_data["first_seen"]) < 0.0:
		_data["first_seen"] = _t
	if int(_t * 10.0) % 20 == 0 and int(_t * 10.0) != int(_data.get("lg", -1)):
		_data["lg"] = int(_t * 10.0)
		print("DR fight t=%.0f enc=%s alive=%d aware=%d nearest=%.1f shots=%d hits=%d kills=%d heat=%.1f" % [_t, enc.stats(), mgr.alive_count(), aware, float(_data["near_min"]), _fight.shots, _fight.hits, _fight.kills, Game.heat])
	_tick_snap("fight", 2.0 if enc.state != &"wave" else 1.0)
	if _t > float(OS.get_environment("DR_FIGHT_SECONDS") if OS.get_environment("DR_FIGHT_SECONDS") != "" else "60"):
		print("DR fight-end kills=%d shots=%d hits=%d near_min=%.1f aware_max=%d first_seen=%.1f enc=%s" % [_fight.kills, _fight.shots, _fight.hits, float(_data["near_min"]), int(_data["aware_max"]), float(_data["first_seen"]), enc.stats()])
		_fight.finish()
		enc.enabled = false
		mgr.clear()
		_finish()


# --- a bystander is shot ---------------------------------------------------------------------------------------------------------

func _act_civ(_dt: float) -> void:
	var city := Game.world as City
	var amb: Node3D = city.ambient if city != null else null
	if amb == null:
		_finish()
		return
	var crowd: RefCounted = amb.crowd
	if _stage == 0:
		Game.civilian_casualties = true
		Game.heat = 0.0
		var best := -1
		var bd := 60.0
		for i in crowd.count:
			if not crowd.is_alive(i):
				continue
			var d: float = Vector2(crowd.person_position(i).x - _p.global_position.x, crowd.person_position(i).z - _p.global_position.z).length()
			if d < bd:
				bd = d
				best = i
		if best < 0:
			print("DR civ none alive")
			_finish()
			return
		_data["i"] = best
		var pos: Vector3 = crowd.person_position(best)
		var along := Vector3(-1.0, 0.0, 0.0) if crowd._axis[best] == 0 else Vector3(0.0, 0.0, -1.0)
		_p.teleport_to(pos + along * 7.0 + Vector3(0.0, 0.1, 0.0))
		_p.camera_rig.reset_view(0.0, 0.0)
		_p.weapon.switch_to(&"carbine", true)
		_stage = 1
		_t = 0.0
		_next_snap = 0.6
		return
	var i: int = _data["i"]
	if _stage == 1:
		if crowd.is_alive(i) and not crowd.is_dying(i) and _t < 5.0:
			_p.camera_rig.aim_at(crowd.person_position(i) + Vector3(0.0, 1.0, 0.0))
			_hold(&"fire", true)
		else:
			_hold(&"fire", false)
			_stage = 2
			_data["t2"] = _t
			print("DR civ killed=%s dying=%s after %.1f s heat=%.1f" % [str(not crowd.is_alive(i)), str(crowd.is_dying(i)), _t, Game.heat])
	if _stage == 2 and _t - float(_data["t2"]) > 3.5:
		_finish()
	_tick_snap("civ", 0.8)


# --- the car: take it, drive, crash, look at the wreck ------------------------------------------------------------------------

func _act_car(delta: float) -> void:
	var vm := Game.vehicles as VehicleManager
	var em := Game.enemies as EnemyManager
	if not _data.has("car"):
		_data["car"] = vm.starter
	var car: Vehicle = _data["car"] if is_instance_valid(_data["car"]) else null
	if car == null:
		print("DR car: the car is gone (freed) at stage %d t=%.1f" % [_stage, _t])
		_hold(&"move_forward", false)
		_hold(&"move_right", false)
		if _stage < 4:
			_stage = 4
			_t = 0.0
		if _stage == 4 and _t > 3.0:
			_finish()
		else:
			_tick_snap("nocar", 1.0)
		return
	match _stage:
		0:
			em.clear()
			Encounters.current.enabled = false
			vm.stream_every = 1.0e9
			vm._stream_t = 1.0e9
			_p.hp = _p.max_hp
			Game.heat = 0.0
			car.global_position = Vector3(-330.0, 0.0, 5.0)
			car.heading = -PI * 0.5
			car.rotation = Vector3(0.0, car.heading, 0.0)
			car._heading_set = car.heading
			car.speed = 0.0
			car.vel = Vector3.ZERO
			car.visual.repair()
			car.hp = car.max_hp
			car.dmg_state = 0
			_p.teleport_to(car.global_position + Vector3(0.0, 0.0, -4.5))
			_p.camera_rig.reset_view(0.0, -0.1)
			_stage = 1
			_t = 0.0
			_next_snap = 0.8
		1:
			# walk to the car and tap USE like a player
			_audit.dt = delta
			var near := vm.nearest(_p.global_position, 4.2)
			if _tick_snap("walk", 1.5) or _t > 0.0:
				pass
			if near == car or car.edge_distance(_p.global_position) < 2.2:
				_audit.stop_walking()
				_audit.tap(&"interact")
				if _p.vehicle != null or vm.driven != null:
					_stage = 2
					_t = 0.0
					_next_snap = 0.3
					_data["x0"] = car.global_position.x
			else:
				_audit.walk_to(Vector3(car.global_position.x, _p.global_position.y, car.global_position.z), 2.0, false)
			if _t > 20.0:
				print("DR car could not be entered on foot, forcing")
				vm.enter(car)
				_stage = 2
				_t = 0.0
		2:
			_hold(&"move_forward", true)
			if _tick_snap("drive", 1.0):
				print("DR car t=%.1f speed=%.1f kmh=%.0f hp=%.0f/%.0f crashes=%d" % [_t, car.speed, car.speed * 3.6, car.hp, car.max_hp, car.crashes])
			if _t > 5.0:
				_stage = 3
				_t = 0.0
				_next_snap = 0.0
				_data["hp0"] = car.hp
		3:
			# turn into the building row and hold the throttle: a player's crash
			_hold(&"move_forward", true)
			_hold(&"move_right", _t > 0.4 and _t < 1.4)
			if _tick_snap("crash", 0.6):
				print("DR car crash t=%.1f speed=%.1f hp=%.0f/%.0f dmg=%d crashes=%d impact=%.1f" % [_t, car.speed, car.hp, car.max_hp, car.dmg_state, car.crashes, car.last_impact])
			if _t > 7.0 or car.dead or car.wreck:
				_hold(&"move_forward", false)
				_hold(&"move_right", false)
				_stage = 4
				_t = 0.0
				_next_snap = 0.5
				print("DR car crash-end hp %.0f of %.0f (lost %.0f %%) crashes=%d dead=%s" % [car.hp, car.max_hp, 100.0 * (float(_data["hp0"]) - car.hp) / car.max_hp, car.crashes, str(car.dead or car.wreck)])
		4:
			if _tick_snap("after", 1.0):
				pass
			if _t > 3.0:
				_p.camera_rig.reset_view(0.0, -0.1)
				_finish()


# --- an interior through a real door ---------------------------------------------------------------------------------------------

func _act_interior(_dt: float) -> void:
	var ig := InteriorGameplay.instance
	match _stage:
		0:
			if InteriorGameplay.active:
				ig.leave(true)
			if _p.vehicle != null:
				(Game.vehicles as VehicleManager).exit_vehicle()
			Game.heat = 0.0
			(Game.enemies as EnemyManager).clear()
			Encounters.current.enabled = false
			_p.teleport_to(Vector3(-30.0, 0.0, 4.0))
			var d := ig.nearest_door(_p.global_position, 120.0)
			if d.is_empty():
				print("DR interior: no door within 120 m of the start")
				_finish()
				return
			_data["door"] = d
			print("DR interior door %s type %s at %.0f m" % [str(d.get("id")), str(d.get("type")), (d["pos"] as Vector3).distance_to(_p.global_position)])
			_stage = 1
			_t = 0.0
			_next_snap = 1.0
		1:
			var d: Dictionary = _data["door"]
			var pos: Vector3 = d["pos"]
			if _audit.walk_to(Vector3(pos.x, _p.global_position.y, pos.z), 1.6, false):
				_audit.face(pos)
				if ig.prompt.begins_with("ENTER"):
					_snap("door_prompt")
					_audit.tap(&"interact")
					_stage = 2
					_t = 0.0
					_next_snap = 0.5
			if _t > 60.0:
				print("DR interior: could not walk to the door in 60 s (prompt '%s')" % ig.prompt)
				ig.enter(d, true)
				_stage = 2
				_t = 0.0
			_tick_snap("approach", 3.0)
		2:
			_tick_snap("in", 1.2)
			if InteriorGameplay.active and _t > 3.0:
				_stage = 3
				_t = 0.0
				_next_snap = 0.0
				print("DR interior inside %s prompt '%s' line '%s'" % [str(ig.interior.name), ig.prompt, _line()])
			if _t > 20.0:
				_finish()
		3:
			# walk across the room toward the far side (the hero is made safe here: the first look is about the room, the fight inside is on its own frame list)
			_p.invuln = 5.0
			_p.hp = _p.max_hp
			_hold(&"move_forward", true)
			if int(_t * 10.0) % 25 == 0:
				_p.camera_rig.reset_view(_p.yaw + 0.5, -0.1)
			_tick_snap("room", 1.8)
			if _t > 12.0:
				_hold(&"move_forward", false)
				for t: StringName in [&"lobby", &"apartment", &"warehouse", &"club"]:
					pass
				_stage = 4
				_t = 0.0
		4:
			if InteriorGameplay.active:
				ig.leave(true)
			_finish()


# --- menus ---------------------------------------------------------------------------------------------------------------------

func _act_menus(_dt: float) -> void:
	var steps := [
		["pause", &"paused", []],
		["pause_more", &"paused", [&"menu_gear"]],
		["options", &"paused", [&"options"]],
		["loadout", &"paused", [&"loadout"]],
		["map", &"paused", [], &"map"],
		["hud_play", &"play", []],
	]
	if _stage == 0:
		_stage = 1
		_t = 0.0
		_data["i"] = 0
		_data["wait"] = 0
		if InteriorGameplay.active:
			InteriorGameplay.instance.leave(true)
		if Game.state == &"dead":
			Game.do_respawn()
		_p.hp = _p.max_hp
		_p.invuln = 0.0
	if int(_data["wait"]) > 0:
		_data["wait"] = int(_data["wait"]) - 1
		return
	var i: int = _data["i"]
	if _data.has("shown") and bool(_data["shown"]):
		_snap(String(steps[i][0]))
		_data["shown"] = false
		_data["i"] = i + 1
		_data["wait"] = 2
		return
	if i >= steps.size():
		var mo := _hud.touch.get_node_or_null("MapScreen") as MapScreen
		if mo != null and mo.is_open():
			mo.close_screen()
		Game.state = &"play"
		_finish()
		return
	var st: Array = steps[i]
	var mo2 := _hud.touch.get_node_or_null("MapScreen") as MapScreen
	if mo2 != null and mo2.is_open():
		mo2.close_screen()
	Game.state = &"play"
	Game.state = st[1]
	_hud._on_state(st[1])
	_hud.screen_age = 5.0
	_hud._ensure_layout()
	for id: StringName in st[2]:
		_hud.press_button(id)
		_hud._ensure_layout()
	if st.size() > 3 and String(st[3]) == "map":
		var ms := _hud.touch.get_node_or_null("MapScreen") as MapScreen
		if ms != null:
			ms.open()
			_hud._screen.visible = false
	_data["shown"] = true
	_data["wait"] = 8


# --- the weapon wheel (a hold on WEAPON) and the weapon catalogue, as a player reaches them ----------------------------------------

func _act_weapons(_dt: float) -> void:
	var tc := _hud.touch
	var sw := {}
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == &"swap":
			sw = b
	match _stage:
		0:
			if InteriorGameplay.active:
				InteriorGameplay.instance.leave(true)
			Game.heat = 0.0
			(Game.enemies as EnemyManager).clear()
			Encounters.current.enabled = false
			_audit.camp.abort()
			_audit.camp.enabled = false
			_p.teleport_to(Vector3(-30.0, 0.0, 4.0))
			_p.camera_rig.reset_view(0.0, -0.1)
			print("DR weapons owned at the start: ", str(WeaponDefs.unlocked), " current ", _p.weapon.current)
			_stage = 1
			_t = 0.0
		1:
			if _t > 1.0:
				_snap("hud")
				tc.touch_down(31, tc.call("_button_center", sw))
				_stage = 2
				_t = 0.0
		2:
			if _t > 0.9:
				print("DR weapons wheel open=%s items=%d" % [str(tc.wheel.is_open), tc.wheel.items.size()])
				_snap("wheel")
				_stage = 3
				_t = 0.0
		3:
			if tc.wheel.is_open and tc.wheel.items.size() > 1:
				var to: Vector2 = tc.wheel.item_centre(1)
				tc.touch_move(31, to, Vector2(0.0, -10.0))
			if _t > 0.6:
				_snap("wheel_pick")
				var before: StringName = _p.weapon.current
				tc.touch_up(31)
				_data["before"] = before
				_stage = 4
				_t = 0.0
		4:
			if _t > 1.0:
				print("DR weapons pick changed %s -> %s" % [str(_data["before"]), str(_p.weapon.current)])
				_snap("after_pick")
				_data["i"] = 0
				_data["plan"] = [&"carbine", &"rocket", &"sawn", &"bolt", &"knife", &"singularity"]
				Game.state = &"paused"
				_hud._on_state(&"paused")
				_hud.screen_age = 5.0
				_hud._ensure_layout()
				_hud.press_button(&"shop")
				_hud.press_button(&"hero_tab_weapons")
				_stage = 5
				_t = 0.0
		5:
			if _t > 1.2:
				var plan: Array = _data["plan"]
				var i: int = _data["i"]
				if i >= plan.size():
					_stage = 6
					_t = 0.0
				else:
					WeaponsScreen.select(plan[i])
					_hud._layout_key = ""
					_data["i"] = i + 1
					_t = 0.0
					_data["shown"] = true
				if i > 0:
					_snap("cat_%s" % str(plan[i - 1]))
		6:
			if _t > 0.4:
				_hud.press_button(&"shop_back")
				_hud._shop_open = false
				_hud.press_button(&"loadout")
				_stage = 7
				_t = 0.0
		7:
			if _t > 1.0:
				_snap("loadout")
				_stage = 8
				_t = 0.0
		8:
			if _t > 0.6:
				Game.state = &"play"
				_hud._on_state(&"play")
				_finish()


# --- the map: open and close five times, by pause > MAP, the minimap and the M key; count the slowest frame, check the game comes back ----------------

func _act_mapx5(_dt: float) -> void:
	var ms := _hud.touch.get_node_or_null("MapScreen") as MapScreen
	if ms == null:
		print("DR mapx5 no map screen")
		_finish()
		return
	var now := Time.get_ticks_usec()
	if _data.has("last_us"):
		_data["worst_us"] = maxi(int(_data.get("worst_us", 0)), now - int(_data["last_us"]))
	_data["last_us"] = now
	var ways := ["pause", "minimap", "key_m", "pause", "minimap"]
	var c: int = int(_data.get("c", 0))
	match _stage:
		0:
			if InteriorGameplay.active:
				InteriorGameplay.instance.leave(true)
			Game.state = &"play"
			_hud._on_state(&"play")
			(Game.enemies as EnemyManager).clear()
			_p.teleport_to(Vector3(-30.0, 0.0, 4.0))
			_stage = 1
			_t = 0.0
			_data["c"] = 0
		1:
			if _t > 0.8:
				_data["worst_us"] = 0
				match String(ways[c]):
					"pause":
						_hud.pause_game()
						_hud._ensure_layout()
						_hud.press_button(&"pause_map")
					"minimap":
						var r: Rect2 = _hud.touch.call("_minimap_rect")
						_hud.touch.touch_down(32, r.get_center())
						_hud.touch.touch_up(32)
					"key_m":
						for pr in [true, false]:
							var e := InputEventKey.new()
							e.keycode = KEY_M
							e.physical_keycode = KEY_M
							e.pressed = pr
							Input.parse_input_event(e)
				_stage = 2
				_t = 0.0
		2:
			if _t > 1.0:
				print("DR mapx5 cycle %d via %s: open=%s state=%s worst_frame_ms=%.0f" % [c, ways[c], str(ms.is_open()), str(Game.state), float(_data["worst_us"]) / 1000.0])
				_snap("open_%d_%s" % [c, ways[c]])
				ms.zoom_by(1.6, ms._map.size * 0.5)
				ms.pan(Vector2(120, -60))
				_stage = 3
				_t = 0.0
		3:
			if _t > 0.8:
				if c == 1 or c == 3:
					_snap("panned_%d" % c)
				ms.set_zoom(1)
				_stage = 4
				_t = 0.0
		4:
			if _t > 0.6:
				if c == 4:
					_snap("whole_city")
				if c == 2:
					for pr in [true, false]:
						var e := InputEventKey.new()
						e.keycode = KEY_ESCAPE
						e.physical_keycode = KEY_ESCAPE
						e.pressed = pr
						Input.parse_input_event(e)
				else:
					ms.close_screen()
				_stage = 5
				_t = 0.0
		5:
			if (c == 0 or c == 3) and _t > 0.15 and not _data.has("early%d" % c):
				_data["early%d" % c] = true
				print("DR mapx5 early frame after close: state=%s screen_visible=%s hud_visible=%s" % [str(Game.state), str(_hud._screen.visible), str(_hud._hud.visible)])
				_snap("after_close_%d" % c)
			if _t > 1.6:
				if ms.is_open() or Game.state == &"paused":
					print("DR mapx5 cycle %d: after the map closed the state is %s (the pause menu is back for a map opened from pause; the bot taps RESUME) open=%s" % [c, str(Game.state), str(ms.is_open())])
					if ms.is_open():
						ms.close_screen()
					if Game.state == &"paused":
						_hud.toggle_pause()
				_data["x0"] = _p.global_position
				_hold(&"move_forward", true)
				_stage = 6
				_t = 0.0
		6:
			if _t > 1.0:
				_hold(&"move_forward", false)
				var moved: float = _p.global_position.distance_to(_data["x0"])
				print("DR mapx5 cycle %d closed: state=%s moved %.1f m with move_forward held, worst_frame_ms=%.0f" % [c, str(Game.state), moved, float(_data["worst_us"]) / 1000.0])
				if c == 4:
					_snap("after_5")
				c += 1
				_data["c"] = c
				_stage = 1 if c < 5 else 7
				_t = 0.0
		7:
			_finish()


# --- go in a building and finish its job the way a phone player does (the interior bot: stick, look, USE) --------------------------------------

const InteriorBot := preload("res://tests/interior_bot.gd")
var _ibot
var _task_done := false


func _task_log(s: String) -> void:
	print("DR task t=%.0f %s | prompt '%s' status '%s' line '%s'" % [_t, s, InteriorGameplay.prompt, InteriorGameplay.status_line, InteriorGameplay.hud_line])


func _act_task(_dt: float) -> void:
	if _stage == 0:
		_stage = 1
		_t = 0.0
		_next_snap = 0.5
		_audit.camp.abort()
		_audit.camp.enabled = false
		Encounters.current.enabled = false
		var tree := Engine.get_main_loop() as SceneTree
		_ibot = InteriorBot.new()
		_ibot.host = tree.root
		_ibot.p = _p
		_ibot.ig = InteriorGameplay.instance
		_ibot.tc = _hud.touch
		_ibot.prog = Game.progress
		_task_done = false
		_task_run()
		return
	Game.state = &"play"
	_tick_snap("task", 2.5)
	if _task_done or _t > 200.0:
		if not _task_done:
			print("DR task TIMEOUT after %.0f s, still inside=%s" % [_t, str(InteriorGameplay.active)])
		_ibot.release()
		_finish()


func _task_run() -> void:
	var b = _ibot
	var ig: InteriorGameplay = InteriorGameplay.instance
	var types: Array[StringName] = [&"lobby"]
	for type in types:
		var ok: bool = await b.enter_door(type)
		_task_log("entered %s ok=%s" % [str(type), str(ok)])
		if not ok:
			continue
		var m: InteriorMissions = ig.missions
		await _snap("inside_%s" % str(type))
		_task_log("job kind %s state %s" % [str(m.kind), str(m.state)])
		var n := 0
		while is_instance_valid(m.puzzles) and not m.puzzles.next_gate().is_empty() and n < 4:
			var g: Dictionary = m.puzzles.next_gate()
			var at: Vector3 = m.puzzles.at(float(g["depth"]) + 2.2)
			var arrived: bool = await b.walk_to(at, 1.4, 30.0)
			_task_log("gate walk arrived=%s %s" % [str(arrived), b.last_fail])
			await b.use()
			await b.frames(4)
			n += 1
		var reach := 2.0
		if m.kind == &"safe":
			reach = InteriorMissions.SAFE_REACH - 0.4
		var arrived2: bool = await b.walk_to(m.target_pos, reach)
		_task_log("walk to the job arrived=%s %s" % [str(arrived2), b.last_fail])
		await _snap("job_prompt")
		var lbl: String = await b.use_label()
		_task_log("USE button says '%s'" % lbl)
		var used: bool = await b.use()
		_task_log("used=%s state %s" % [str(used), str(m.state)])
		var t := 0.0
		while t < 25.0 and m.state != &"complete":
			await b.frames(6)
			t += 6.0 * ig.get_physics_process_delta_time()
		_task_log("job state %s after %.0f s progress %.2f" % [str(m.state), t, m.progress])
		await b.frames(12)
		await _snap("job_done")
		Game.heat = 0.0
		var out: bool = await b.leave_by_door()
		_task_log("left by the door ok=%s %s" % [str(out), b.last_fail])
		await b.frames(10)
		await _snap("outside")
	_task_done = true
