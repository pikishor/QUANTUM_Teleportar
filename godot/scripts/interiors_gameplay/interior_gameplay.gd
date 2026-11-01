class_name InteriorGameplay
extends Node
## Enterable interiors on top of the interior generator (docs/interiors_interface.md): glowing doors on the shopfronts (Game.world.doors, scripts/world/city_doors.gd), a USE prompt
## (touch USE button or F), fades, the player's state carried through (hp, energy, weapons, ammo and HEAT: heat does not decay inside, hunters may follow through the door), vendors,
## civilians, Vael guards (cap 3..5 actors), four interior missions, interior radio lines, the minimap layout, saving inside an interior and a safe respawn at the door.
##
## Where the room lives: one interior at a time at ORIGIN, street level in the strip east of the city grid (x 310..345, no lot, no prop). While one is active the city is hidden
## (Game.world.visible = false: ground, props, traffic, mirror cost nothing), the cars are frozen and hidden, rain is 0, the street's enemies are stored (positions, hp, awareness) and
## put back on exit, and unspawned patrol groups are held back. `City.is_inside_building` consults `blocks()` east of x = EAST_STRIP so enemy steps stop at the interior's walls.
## Static state for the other modules (read-only for them): `active`, `vendor_open`, `prompt` (HUD / touch USE), `hud_line` (HUD priority line).
## Simulates only while Game.is_playing(); resets on new_game / respawn / next_sector; the node is added by main.gd after the world and before the test menu.

signal entered(door: Dictionary)
signal exited(door: Dictionary)

const GEN_PATH := "res://scripts/interiors/interior_gen.gd"
const ORIGIN := Vector3(327.5, 0.0, 0.0)
const EAST_STRIP := 305.0
const REACH_DOOR := 2.8
const REACH_VENDOR := 3.2
const REACH_EXIT := 2.2
const FADE := 0.26
const SAVE_PATH := "user://interiors.cfg"
const FOLLOW_RADIUS := 30.0
const FOLLOW_MAX := 2
const EXIT_FOLLOW_RADIUS := 14.0
const SCAN_EVERY := 0.1

static var instance: InteriorGameplay
static var active := false
static var vendor_open := false
static var prompt := ""
static var hud_line := ""
static var _walls: Array[Rect2] = []
static var _bounds := Rect2()

var interior: Node3D
var door: Dictionary = {}
var actors: InteriorActors
var missions: InteriorMissions
var markers: DoorMarkers
var vendor_screen: VendorScreen
var done := {}                               ## door id -> true (interior missions finished this campaign)
var hinted := {}                             ## door id -> true (a rumour pointed at it)
var rumour_index := 0
var autosave := false
var save_path := SAVE_PATH
var use_generator := true                    ## false: always the stub room (tests)
var test_doors: Array[Dictionary] = []        ## tests without a city: the doors to use
var busy := false
var enter_count := 0
var exit_count := 0
var last_radio := ""

var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _trans := ""                              ## "" | "out" | "in"
var _trans_t := 0.0
var _trans_action := ""
var _trans_door: Dictionary = {}
var _scan_t := 0.0
var _near_door: Dictionary = {}
var _stash: Array[Dictionary] = []
var _groups_saved: Array[bool] = []
var _hidden_cars: Array[Node3D] = []
var _weather := Vector2(-1.0, -1.0)
var _doors_key := -1
var _resume_door := -1
var _resume_t := 0.0
var _saved_inside := false
var _saved_door := -1


func _ready() -> void:
	name = "InteriorGameplay"
	instance = self
	add_to_group(&"interior_gameplay")
	process_mode = Node.PROCESS_MODE_ALWAYS
	autosave = not Game.autostart
	markers = DoorMarkers.new()
	markers.name = "DoorMarkers"
	add_child(markers)
	actors = InteriorActors.new()
	add_child(actors)
	missions = InteriorMissions.new()
	add_child(missions)
	missions.completed.connect(_on_mission_completed)
	vendor_screen = VendorScreen.new()
	add_child(vendor_screen)
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 60
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.modulate.a = 0.0
	_fade_rect.visible = false
	_fade_layer.add_child(_fade_rect)
	Game.new_game.connect(_on_new_game)
	Game.respawn.connect(_on_respawn)
	Game.next_sector.connect(_on_next_sector)
	Game.state_changed.connect(_on_state)
	Game.quality_changed.connect(_on_quality)
	if autosave:
		load_state()
	_sync_doors()


func _exit_tree() -> void:
	if active:
		_restore_outside(false)
	active = false
	vendor_open = false
	prompt = ""
	hud_line = ""
	_walls = []
	_bounds = Rect2()
	if instance == self:
		instance = null


# --- statics for other modules --------------------------------------------------------------------------------------

## True when an enemy / civilian step to `p` is blocked: outside the interior's bounds or inside one of its wall / furniture rects. False while no interior is active.
static func blocks(p: Vector3) -> bool:
	if not active:
		return false
	var v := Vector2(p.x, p.z)
	if not _bounds.has_point(v):
		return true
	for r in _walls:
		if r.has_point(v):
			return true
	return false


## The first `n` anchors of `kind` as {pos, yaw}. Missing ones are made up from the walkable floor (deterministic for the seed), so any generator output works.
static func anchor_points(room: Node3D, kind: StringName, n: int, seed_value: int) -> Array:
	var out: Array = []
	if room.has_method(&"anchors"):
		for a in room.call(&"anchors", kind):
			if a is Dictionary and (a as Dictionary).has("pos"):
				out.append({"pos": a["pos"], "yaw": float(a.get("yaw", 0.0))})
	if out.size() >= n:
		return out
	var rects: Array = room.get("floor_rects") if room.get("floor_rects") != null else []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 131 + str(kind).hash()
	var tries := 0
	while out.size() < n and tries < 60:
		tries += 1
		var r: Rect2 = rects[rng.randi() % rects.size()] if not rects.is_empty() else (room.get("bounds") as Rect2)
		var q := Vector3(rng.randf_range(r.position.x + 1.5, r.end.x - 1.5), ORIGIN.y, rng.randf_range(r.position.y + 1.5, r.end.y - 1.5))
		if r.size.x < 3.5 or r.size.y < 3.5:
			q = Vector3(r.get_center().x, ORIGIN.y, r.get_center().y)
		var clear := true
		for w: Rect2 in room.get("wall_rects"):
			if w.grow(0.5).has_point(Vector2(q.x, q.z)):
				clear = false
				break
		if clear or tries > 50:
			out.append({"pos": q, "yaw": rng.randf() * TAU})
	return out


static func _rects_of(arr: Variant) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if arr is Array:
		for r in arr as Array:
			if r is Rect2:
				out.append(r)
	return out


## One radio line through the story layer (also recorded in Story.shown like the story's own groups). Falls back to the HUD message line without a story.
static func radio(speaker: String, text: String, id: String, wait := 0.0, prio := 0) -> bool:
	var st: Object = Game.story if is_instance_valid(Game.story) else null
	if st == null or not st.has_method(&"say"):
		Game.say(text, 3.0)
		return false
	var ok: bool = st.call(&"say", speaker, text, id, wait, prio)
	if ok and st.get(&"shown") is Array:
		(st.get(&"shown") as Array).append(id)
	return ok


static func exit_point(room: Node3D) -> Vector3:
	var p = room.get("exit_pos")
	return p if p is Vector3 else ORIGIN


# --- doors ------------------------------------------------------------------------------------------------------------

func doors() -> Array[Dictionary]:
	if not test_doors.is_empty():
		return test_doors
	var w: Object = Game.world if is_instance_valid(Game.world) else null
	var d: Variant = w.get("doors") if w != null else null
	var out: Array[Dictionary] = []
	if d is Array:
		for e in d as Array:
			out.append(e)
	return out


func door_by_id(id: int) -> Dictionary:
	for d in doors():
		if int(d["id"]) == id:
			return d
	return {}


## Doors of an interior type, nearest to `from` first.
func doors_of(type: StringName, from := Vector3.ZERO) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in doors():
		if d["type"] == type:
			out.append(d)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["pos"] as Vector3).distance_to(from) < (b["pos"] as Vector3).distance_to(from))
	return out


func nearest_door(pos: Vector3, max_dist := REACH_DOOR) -> Dictionary:
	var best := {}
	var bd := max_dist
	for d in doors():
		var p: Vector3 = d["pos"]
		var dd := Vector2(p.x - pos.x, p.z - pos.z).length()
		if dd < bd:
			bd = dd
			best = d
	return best


func _sync_doors() -> void:
	var list := doors()
	var key := hash([list.size(), is_instance_valid(Game.world)])
	if key != _doors_key or markers.mmi == null and not list.is_empty():
		_doors_key = key
		markers.build(list)
		_refresh_markers()


func _refresh_markers() -> void:
	var open := {}
	for d in doors():
		if InteriorData.mission_for(d["type"]) != &"" and not done.has(int(d["id"])):
			open[int(d["id"])] = true
	markers.refresh(open, hinted)


# --- enter / exit -------------------------------------------------------------------------------------------------------

## Why the player cannot go through a door right now ("" = can).
func block_reason() -> String:
	var p := Game.player as Player
	if p == null or not Game.is_playing():
		return "NOT NOW"
	if active or busy:
		return "BUSY"
	if p.vehicle != null:
		return "LEAVE THE VEHICLE"
	if p.is_dead():
		return "DEAD"
	var em := Game.enemies as EnemyManager
	if em != null:
		for e in em.list:
			if e.active and not e.dead and e.type == &"overseer":
				return "OVERSEER ON THE STREET"
	return ""


## Go through `d` (a door of Game.world.doors). With `instant` there is no fade (tests, test menu, resume). Returns false when blocked.
func enter(d: Dictionary, instant := false) -> bool:
	if d.is_empty() or block_reason() != "":
		return false
	if instant:
		_apply_enter(d)
		return true
	busy = true
	_trans = "out"
	_trans_t = 0.0
	_trans_action = "enter"
	_trans_door = d
	_fade_rect.visible = true
	Sfx.play(&"car_door", -6.0)
	return true


func leave(instant := false) -> bool:
	if not active or busy:
		return false
	if instant:
		_apply_exit()
		return true
	busy = true
	_trans = "out"
	_trans_t = 0.0
	_trans_action = "exit"
	_fade_rect.visible = true
	Sfx.play(&"car_door", -6.0)
	return true


func _process(delta: float) -> void:
	if _trans == "":
		return
	var real := delta / maxf(Engine.time_scale, 0.05)
	_trans_t += real
	var a := clampf(_trans_t / FADE, 0.0, 1.0)
	if _trans == "out":
		_fade_rect.modulate.a = a
		if a >= 1.0:
			if _trans_action == "enter":
				_apply_enter(_trans_door)
			else:
				_apply_exit()
			_trans = "in"
			_trans_t = 0.0
	else:
		_fade_rect.modulate.a = 1.0 - a
		if a >= 1.0:
			_trans = ""
			busy = false
			_fade_rect.visible = false
			_fade_rect.modulate.a = 0.0


func is_fading() -> bool:
	return _trans != ""


func _build_room(type: StringName, seed_value: int) -> Node3D:
	if use_generator and ResourceLoader.exists(GEN_PATH):
		var gen: Variant = load(GEN_PATH)
		if gen != null:
			var r: Variant = gen.build(type, seed_value, ORIGIN, Game.quality)
			if r is Node3D and _valid_room(r as Node3D):
				return r as Node3D
			elif r is Node:
				(r as Node).free()
			push_warning("InteriorGameplay: the generator returned an invalid interior, using the stub")
	return InteriorStub.build(type, seed_value, ORIGIN, Game.quality)


static func _valid_room(r: Node3D) -> bool:
	return r.get("door_pos") is Vector3 and r.get("bounds") is Rect2 and r.get("exit_pos") is Vector3 and r.get("wall_rects") != null and r.get("floor_rects") != null \
			and r.has_method(&"anchors")


func _apply_enter(d: Dictionary) -> void:
	var p := Game.player as Player
	if p == null or active:
		busy = false
		return
	door = d
	var type: StringName = d["type"]
	var seed_value := int(d["id"])
	_stash_street(Vector3(d["pos"]))
	var followers := _pick_followers(Vector3(d["pos"]))
	_hide_street()
	interior = _build_room(type, seed_value)
	add_child(interior)
	_walls = _rects_of(interior.get("wall_rects"))
	_bounds = (interior.get("bounds") as Rect2).grow(0.5)
	active = true
	prompt = ""
	markers.visible = false
	p.teleport_to(interior.get("door_pos"))
	var yaw := float(interior.get("door_yaw"))
	p.yaw = yaw
	p.camera_rig.reset_view(yaw, p.camera_rig.pitch)
	p.camera_rig.snap()
	var plan := InteriorData.plan(type, followers.size())
	var kind := InteriorData.mission_for(type)
	actors.populate(interior, type, plan, followers, kind if not done.has(int(d["id"])) else &"", seed_value)
	if kind != &"" and not done.has(int(d["id"])):
		missions.begin(interior, kind, int(d["id"]), actors)
	enter_count += 1
	_radio_enter(type, seed_value, followers.size() > 0)
	Game.say("%s  %s" % [InteriorData.title(type), str(d["name"])], 2.2)
	if autosave:
		save_state()
	entered.emit(d)


func _apply_exit() -> void:
	if not active:
		busy = false
		return
	var d := door
	var out_types: Array[StringName] = []
	for list: Array in [actors.guards, actors.followers]:
		for g: Drone in list:
			if is_instance_valid(g) and g.active and not g.dead and g.aware and out_types.size() < FOLLOW_MAX \
					and Vector2(g.global_position.x - exit_point(interior).x, g.global_position.z - exit_point(interior).z).length() < EXIT_FOLLOW_RADIUS:
				out_types.append(g.type)
	_restore_outside(true)
	var p := Game.player as Player
	if p != null:
		p.teleport_to(d["pos"])
		var fy := float(d["face_yaw"])
		p.yaw = fy
		p.camera_rig.reset_view(fy, p.camera_rig.pitch)
		p.camera_rig.snap()
	var em := Game.enemies as EnemyManager
	if em != null:
		for t in out_types:
			em.spawn(t, Vector3(d["pos"]) + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)), true)
	exit_count += 1
	if enter_count % 3 == 1:
		radio("ORACLE", str((InteriorData.RADIO[&"exit"] as Array)[0][1]), "int_exit", 0.5, 0)
	if autosave:
		save_state()
	exited.emit(d)


## Tear the interior down and bring the street back. `with_stash`: put the stored enemies back (false on new game / next sector, where the manager rebuilds its patrols).
func _restore_outside(with_stash: bool) -> void:
	if is_instance_valid(actors):
		actors.clear()
	if is_instance_valid(missions):
		missions.reset()
	if is_instance_valid(interior):
		remove_child(interior)
		interior.queue_free()
	interior = null
	active = false
	prompt = ""
	hud_line = ""
	_walls = []
	_bounds = Rect2()
	markers.visible = true
	if is_instance_valid(Game.world):
		Game.world.visible = true
	for v in _hidden_cars:
		if is_instance_valid(v):
			v.visible = true
	_hidden_cars.clear()
	if is_instance_valid(Game.vehicles):
		Game.vehicles.set_physics_process(true)
	if is_instance_valid(Game.atmosphere) and _weather.x >= 0.0:
		Game.atmosphere.call(&"set_weather", _weather.x, _weather.y)
	_weather = Vector2(-1.0, -1.0)
	var em := Game.enemies as EnemyManager
	if em != null:
		var groups := em.patrol_groups()
		for i in mini(groups.size(), _groups_saved.size()):
			(groups[i] as Dictionary)["spawned"] = _groups_saved[i]
		if with_stash:
			for s in _stash:
				var e := em.spawn(s["type"], s["pos"], s["aware"], s["reinforce"])
				if e != null:
					e.hp = minf(float(s["hp"]), e.max_hp)
	_groups_saved.clear()
	_stash.clear()
	if is_instance_valid(Game.world) and Game.world.has_method(&"update_streaming") and is_instance_valid(Game.player):
		var pp := Game.player.global_position
		Game.world.call(&"update_streaming", Vector2(pp.x, pp.z), true)


## Street enemies: remember them, release them (the interior has the whole actor cap), hold unspawned patrol groups back.
func _stash_street(door_pos: Vector3) -> void:
	_stash.clear()
	_groups_saved.clear()
	var em := Game.enemies as EnemyManager
	if em == null:
		return
	for e in em.list:
		if e.active and not e.dead:
			_stash.append({"type": e.type, "pos": e.global_position, "hp": e.hp, "aware": e.aware, "reinforce": e.reinforce, "d": e.global_position.distance_to(door_pos)})
	for g in em.patrol_groups():
		_groups_saved.append(bool((g as Dictionary)["spawned"]))
		(g as Dictionary)["spawned"] = true


## The nearest aware hunters (at most FOLLOW_MAX) leave the stash and come in after the player.
func _pick_followers(door_pos: Vector3) -> Array[StringName]:
	var out: Array[StringName] = []
	var cand: Array[Dictionary] = []
	for s in _stash:
		if s["aware"] and float(s["d"]) < FOLLOW_RADIUS and s["type"] != &"overseer":
			cand.append(s)
	cand.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	for s in cand:
		if out.size() >= FOLLOW_MAX:
			break
		out.append(s["type"])
		_stash.erase(s)
	var em := Game.enemies as EnemyManager
	if em != null:
		em.clear()
	return out


func _hide_street() -> void:
	if is_instance_valid(Game.world):
		Game.world.visible = false
	if is_instance_valid(Game.vehicles):
		Game.vehicles.set_physics_process(false)
		var lst: Variant = Game.vehicles.get("list")
		if lst is Array:
			for v in lst as Array:
				if v is Node3D and (v as Node3D).visible:
					(v as Node3D).visible = false
					_hidden_cars.append(v)
	var atm: Object = Game.atmosphere if is_instance_valid(Game.atmosphere) else null
	if atm != null:
		_weather = Vector2(float(atm.get("rain_target")), float(atm.get("wetness_target")))
		atm.call(&"set_weather", 0.0, _weather.y)


## Leave without a fade (death respawn, new game, the title screen). `to_door`: put the player at the street door, otherwise leave the player alone;
## `with_stash`: put the street's enemies back.
func force_exit(to_door: bool, with_stash := to_door) -> void:
	if not active:
		return
	var d := door
	_restore_outside(with_stash)
	busy = false
	_trans = ""
	_fade_rect.visible = false
	_fade_rect.modulate.a = 0.0
	if to_door and Game.player != null:
		(Game.player as Player).teleport_to(d["pos"])
		(Game.player as Player).yaw = float(d["face_yaw"])
	if is_instance_valid(vendor_screen):
		vendor_screen.close()


# --- game lifecycle -----------------------------------------------------------------------------------------------------

func _on_new_game() -> void:
	var resume := _resume_flag()
	if active:
		force_exit(false)
	if resume and _saved_inside and _saved_door >= 0:
		_resume_door = _saved_door
		_resume_t = 0.5
	else:
		done.clear()
		hinted.clear()
		rumour_index = 0
		_refresh_markers()
		_saved_inside = false
		if autosave:
			save_state()


func _resume_flag() -> bool:
	var prog := Game.progress
	return prog != null and prog.get(&"_continue_pending") == true


func _on_respawn() -> void:
	if active:
		force_exit(true)


func _on_next_sector() -> void:
	if active:
		force_exit(false)
	_resume_door = -1


func _on_state(s: StringName) -> void:
	if s == &"menu" and active:
		force_exit(false)             # the title screen shows the city; the last save keeps "inside" so CONTINUE returns to the interior
	if (s == &"paused" or s == &"dead") and autosave and not vendor_open:
		save_state()


func _on_quality(level: int) -> void:
	if is_instance_valid(interior) and interior.has_method(&"set_quality"):
		interior.call(&"set_quality", level)


func _on_mission_completed(_kind: StringName, id: int, _reward: Dictionary) -> void:
	done[id] = true
	_refresh_markers()
	if autosave:
		save_state()


# --- per-tick -------------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not Game.is_playing():
		prompt = ""
		return
	if _resume_door >= 0:
		_resume_t -= delta
		if _resume_t <= 0.0:
			var rd := door_by_id(_resume_door)
			_resume_door = -1
			if not rd.is_empty():
				enter(rd, true)
	if active:
		_tick_inside(delta)
	else:
		_tick_outside(delta)


func _tick_outside(delta: float) -> void:
	hud_line = ""
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_EVERY
		_sync_doors()
		var p := Game.player
		_near_door = {}
		prompt = ""
		if is_instance_valid(p) and not busy and p.global_position.y < 3.0 and p.get(&"vehicle") == null:
			var d := nearest_door(p.global_position)
			var cars_near := is_instance_valid(Game.vehicles) and Game.vehicles.has_method(&"nearest") and Game.vehicles.call(&"nearest", p.global_position, 4.2) != null
			if not d.is_empty() and not cars_near:
				_near_door = d
				var why := block_reason()
				prompt = ("ENTER  %s" % str(d["name"])) if why == "" else why
	if Input.is_action_just_pressed(&"interact") and not _near_door.is_empty() and prompt.begins_with("ENTER"):
		enter(_near_door)


func _tick_inside(delta: float) -> void:
	Game.quiet = 0.0                        # heat does not decay inside: the observers still count the minutes
	actors.tick(delta)
	missions.tick(delta)
	hud_line = missions.hud_line()
	var p := Game.player
	if not is_instance_valid(p):
		return
	var pp: Vector3 = p.global_position
	if pp.distance_to(ORIGIN) > 60.0:      # the player left by other means (test menu teleport, rescue): close the interior quietly
		force_exit(false, true)
		return
	var nv := _vendor_near(pp)
	var mp := missions.prompt_for(pp)
	var ex := Vector2(pp.x - exit_point(interior).x, pp.z - exit_point(interior).z).length() < REACH_EXIT
	prompt = ""
	var action := ""
	if mp != "":
		prompt = mp
		action = "mission"
	elif nv != null:
		prompt = "TALK  %s" % InteriorData.title(actors.type)
		action = "vendor"
	elif ex:
		prompt = "LEAVE  %s" % str(door.get("name", ""))
		action = "exit"
	if busy or vendor_open:
		return
	if Input.is_action_just_pressed(&"interact"):
		match action:
			"mission": missions.interact(pp)
			"vendor": vendor_screen.open(actors.type)
			"exit": leave()


func _vendor_near(pp: Vector3) -> InteriorCivilian:
	var v := actors.vendor
	if v != null and v.active and Vector2(v.global_position.x - pp.x, v.global_position.z - pp.z).length() < REACH_VENDOR:
		return v
	return null


# --- rumours, radio, minimap -----------------------------------------------------------------------------------------------------

## The bar's rumour: story line first, then every other one comes with a hint (the nearest open mission door glows brighter on the street and the minimap).
func tell_rumour() -> String:
	var i := rumour_index
	rumour_index += 1
	var text: String = InteriorData.RUMOURS[i % InteriorData.RUMOURS.size()]
	if i % 2 == 1:
		var best := {}
		var bd := INF
		var from := Vector3.ZERO if not is_instance_valid(Game.player) or active else Game.player.global_position
		if not door.is_empty():
			from = door["pos"]
		for d in doors():
			var id := int(d["id"])
			if InteriorData.mission_for(d["type"]) != &"" and not done.has(id) and not hinted.has(id):
				var dd := (d["pos"] as Vector3).distance_to(from)
				if dd < bd:
					bd = dd
					best = d
		if not best.is_empty():
			hinted[int(best["id"])] = true
			text += "  [%s MARKED]" % str(best["name"])
			_refresh_markers()
	radio("ORACLE", text.get_slice("  [", 0), "int_rumour_%d" % i, 0.0, 1)
	return text


func _radio_enter(type: StringName, id: int, hunted: bool) -> void:
	var lines: Array = InteriorData.RADIO.get(type, [])
	if hunted:
		lines = InteriorData.RADIO[&"heat"]
	if lines.is_empty():
		return
	var pair: Array = lines[(id + enter_count) % lines.size()]
	last_radio = str(pair[1])
	radio(str(pair[0]), str(pair[1]), "int_%s_%d" % [str(type), (id + enter_count) % lines.size()], 0.8, 0)


## Markers for InteriorMinimap: {pos, color, kind (&"diamond" / &"disc" / &"target" / &"area" / &"zone"), size}.
func minimap_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if interior == null:
		return out
	out.append({"pos": exit_point(interior), "color": Color(0.4, 1.0, 0.6), "kind": &"diamond", "size": 4.0})
	if actors.vendor != null and actors.vendor.active:
		out.append({"pos": actors.vendor.global_position, "color": Color(1.0, 0.72, 0.25), "kind": &"diamond", "size": 4.2})
	for c in actors.civilians:
		if c.active and c.role != &"hostage":
			out.append({"pos": c.global_position, "color": Color(0.85, 0.9, 0.95, 0.9), "kind": &"disc", "size": 2.4})
	for list: Array in [actors.guards, actors.followers]:
		for g: Drone in list:
			if is_instance_valid(g) and g.active and not g.dead and g != actors.officer:
				out.append({"pos": g.global_position, "color": Color(1.0, 0.3, 0.32), "kind": &"disc", "size": 3.0})
	for m in missions.markers():
		out.append(m)
	return out


# --- save ---------------------------------------------------------------------------------------------------------------------

func save_state() -> bool:
	var cf := ConfigFile.new()
	cf.set_value("interiors", "inside", active)
	cf.set_value("interiors", "door", int(door.get("id", -1)) if active else -1)
	cf.set_value("interiors", "done", PackedInt32Array(_ids(done)))
	cf.set_value("interiors", "hinted", PackedInt32Array(_ids(hinted)))
	cf.set_value("interiors", "rumours", rumour_index)
	var ok := cf.save(save_path) == OK
	if ok:
		_saved_inside = active
		_saved_door = int(door.get("id", -1)) if active else -1
	return ok


func load_state() -> bool:
	var cf := ConfigFile.new()
	if cf.load(save_path) != OK:
		return false
	_saved_inside = bool(cf.get_value("interiors", "inside", false))
	_saved_door = int(cf.get_value("interiors", "door", -1))
	done.clear()
	for i: int in Array(cf.get_value("interiors", "done", PackedInt32Array())):
		done[i] = true
	hinted.clear()
	for i: int in Array(cf.get_value("interiors", "hinted", PackedInt32Array())):
		hinted[i] = true
	rumour_index = int(cf.get_value("interiors", "rumours", 0))
	return true


## Re-enter the interior the last save was made in (CONTINUE does this by itself after the run starts). Returns false without one.
func resume_saved() -> bool:
	if not _saved_inside or _saved_door < 0:
		return false
	return enter(door_by_id(_saved_door), true)


func saved_inside() -> bool:
	return _saved_inside


func _ids(d: Dictionary) -> Array:
	var out: Array = []
	for k in d:
		out.append(int(k))
	out.sort()
	return out


# --- test menu ----------------------------------------------------------------------------------------------------------------------

## Go straight into the nearest interior of `type` (the TEST menu's INTERIORS page). Returns a status line.
func test_enter(type: StringName) -> String:
	if active:
		leave(true)
	var from := Game.player.global_position if is_instance_valid(Game.player) else Vector3.ZERO
	var list := doors_of(type, from)
	var d: Dictionary = list[0] if not list.is_empty() else {}
	if d.is_empty():
		# no such door in this city (or no city): make one at the player's feet so the interior can still be visited
		d = {"id": 9000 + InteriorData.TYPES.find(type), "type": type, "name": "TEST %s" % InteriorData.title(type), "wall": from, "pos": from, "normal": Vector3.BACK, "yaw": 0.0, "face_yaw": 0.0, "width": 2.4}
	if not enter(d, true):
		return "CANNOT ENTER: %s" % block_reason()
	return "INSIDE  %s" % InteriorData.title(type)


func test_leave() -> String:
	if not active:
		return "NOT INSIDE"
	leave(true)
	return "BACK ON THE STREET"


func test_complete_mission() -> String:
	if not active or not missions.is_active():
		return "NO INTERIOR MISSION HERE"
	missions._finish()
	return "MISSION COMPLETE"
