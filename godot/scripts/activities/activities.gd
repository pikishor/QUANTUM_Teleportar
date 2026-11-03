class_name Activities
extends Node
## F8: four arcade side activities with entry markers: TARGET RANGE (shoot popping targets), ROOFTOP RUN (timed parkour over roof checkpoints),
## DRIFT COURSE (timed gate loop in a car, leaderboard of the 5 best times) and ARENA (survival waves). Stepping on a marker starts it.
## Best scores live in their own file (save_path), so Progress is untouched. Logic is driven by step(dt), called from _physics_process only while Game.is_playing().
## Draws: ONE MultiMesh for the four entry markers plus ONE beacon for the current checkpoint; the range adds <= TARGETS bodies while it runs.

signal started(id: StringName)
signal finished(id: StringName, score: float, record: bool)

const RANGE := &"range"
const PARKOUR := &"parkour"
const DRIFT := &"drift"
const ARENA := &"arena"
const IDS: Array[StringName] = [RANGE, PARKOUR, DRIFT, ARENA]
const NAMES := {RANGE: "TARGET RANGE", PARKOUR: "ROOFTOP RUN", DRIFT: "DRIFT COURSE", ARENA: "ARENA"}
const ENTRY_RADIUS := 3.0
const GATE_RADIUS := 12.0
const ROOF_RADIUS := 4.0
const RANGE_TIME := 45.0
const PARKOUR_TIME := 150.0
const DRIFT_TIME := 120.0
const TARGETS := 5
const BOARD_SIZE := 5
const REWARD := {RANGE: Economy.ACTIVITY_REWARD[&"range"], PARKOUR: Economy.ACTIVITY_REWARD[&"parkour"], DRIFT: Economy.ACTIVITY_REWARD[&"drift"], ARENA: Economy.ACTIVITY_REWARD[&"arena"]}   ## credits: per hit (range) / on finish / per wave (arena)
const ARENA_WAVES := 5               ## clearing this many waves finishes the arena
const ARENA_CLEAR_BONUS := Economy.ARENA_CLEAR_BONUS
const LEAVE_RADIUS := 70.0          ## range / arena end quietly when the player walks this far from the marker
const COOLDOWN := 3.0
const CHECK := 0.1

class Target extends StaticBody3D:
	var radius := 0.7
	var dead := false
	var hp := 1.0
	signal shot
	func damage(_amount: float, _crit := false) -> void:
		if not dead:
			dead = true
			shot.emit()

var save_path := "user://activities.cfg"
var best := {RANGE: 0.0, PARKOUR: 0.0, DRIFT: 0.0, ARENA: 0.0}   ## range: hits, parkour: seconds (0 = none), arena: waves
var board: Array[float] = []                                       ## drift: best times ascending
var active: StringName = &""
var elapsed := 0.0
var progress_i := 0          ## checkpoint index (parkour / drift) or wave number (arena)
var hits := 0
var auto_enter := true
var require_car := true
var _car_run := false
var _cool := 0.0
var _check := 0.0
var _mmi: MultiMeshInstance3D
var _beacon: MeshInstance3D
var _targets: Array[Target] = []
var _foes: Array = []
var _course: Array[Vector3] = []


## Entry marker ground positions (pure data, from the fixed city grid).
static func entries() -> Dictionary:
	var rc := CityLayout.road_center
	var o := Vector3(7.0, 0.0, 7.0)
	return {
		RANGE: Vector3(rc.call(4), 0.0, rc.call(4)) + o,
		PARKOUR: Vector3(rc.call(3), 0.0, rc.call(5)) + o,
		DRIFT: Vector3(rc.call(1), 0.0, rc.call(1)) + o,
		ARENA: Vector3(rc.call(6), 0.0, rc.call(6)) + o,
	}


## Arena spawn points: on the two roads crossing at the arena junction (never inside a building), 20-34 m from the marker.
static func arena_spawns() -> Array[Vector3]:
	var j: Vector3 = entries()[ARENA] - Vector3(7.0, 0.0, 7.0)
	var out: Array[Vector3] = []
	for d in [-34.0, -20.0, 20.0, 34.0]:
		out.append(j + Vector3(d, 0.0, -5.0))
		out.append(j + Vector3(5.0, 0.0, d))
	return out


## Range target positions: floating over the road the range marker stands on.
static func target_pos(k: int) -> Vector3:
	var b: Vector3 = entries()[RANGE]
	return Vector3(b.x - 18.0 + 6.0 * (k % 7), 1.4 + 0.7 * (k % 3), b.z - 10.0 + 3.0 * (k % 3))


## Gate loop of the drift course: the ring of junctions (1,1)-(3,3), returning to the start.
static func drift_gates() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for g: Vector2i in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3), Vector2i(2, 3), Vector2i(1, 3), Vector2i(1, 2), Vector2i(1, 1)]:
		out.append(Vector3(CityLayout.road_center(g.x), 1.0, CityLayout.road_center(g.y)))
	return out


## Rooftop run checkpoints: the 5 rooftop shards nearest the entry, chained nearest-first.
static func parkour_points() -> Array[Vector3]:
	var from: Vector3 = entries()[PARKOUR]
	var pool: Array[Vector3] = []
	for i in range(Collectibles.COUNT - Collectibles.ROOF_COUNT, Collectibles.COUNT):
		pool.append(Collectibles.spots()[i])
	var out: Array[Vector3] = []
	var cur := from
	while out.size() < 5 and not pool.is_empty():
		var bi := 0
		for k in pool.size():
			if Vector2(pool[k].x - cur.x, pool[k].z - cur.z).length() < Vector2(pool[bi].x - cur.x, pool[bi].z - cur.z).length():
				bi = k
		cur = pool[bi]
		out.append(cur)
		pool.remove_at(bi)
	return out


func _ready() -> void:
	name = "Activities"
	add_to_group(&"activities")
	load_scores()
	_build_visual()
	Game.player_died.connect(_on_died)
	Game.respawn.connect(stop)
	Game.new_game.connect(stop)


func _physics_process(delta: float) -> void:
	if Game.is_playing():
		step(delta)


func step(dt: float) -> void:
	_cool = maxf(_cool - dt, 0.0)
	_check += dt
	if _check < CHECK and active == &"":
		return
	var p := Game.player
	if not is_instance_valid(p):
		return
	if active == &"":
		if auto_enter and _cool <= 0.0:
			var e := entries()
			for id: StringName in IDS:
				var d := Vector2(p.global_position.x - e[id].x, p.global_position.z - e[id].z).length()
				if d <= ENTRY_RADIUS and absf(p.global_position.y - e[id].y) < 4.0:
					start(id)
					break
		_check = 0.0
		return
	elapsed += dt
	var e2: Vector3 = entries()[active]
	if (active == RANGE or active == ARENA) and Vector2(p.global_position.x - e2.x, p.global_position.z - e2.z).length() > LEAVE_RADIUS:
		Game.say("%s  LEFT" % NAMES[active], 1.5)
		stop()
		return
	if active == DRIFT and _car_run and p.get(&"vehicle") == null:
		Game.say("DRIFT COURSE  LEFT THE CAR", 1.5)
		stop()
		return
	match active:
		RANGE: _step_range()
		PARKOUR: _step_course(ROOF_RADIUS, PARKOUR_TIME, true)
		DRIFT: _step_course(GATE_RADIUS, DRIFT_TIME, false)
		ARENA: _step_arena()
	if active == RANGE and elapsed >= RANGE_TIME:
		_finish(true)
	_check = 0.0


## Starts an activity. False when one is running, the id is unknown or a car is needed (drift) and the player is on foot.
func start(id: StringName, ignore_car := false) -> bool:
	if active != &"" or not IDS.has(id) or not is_instance_valid(Game.player):
		return false
	if id == DRIFT and require_car and not ignore_car and Game.player.get(&"vehicle") == null:
		if _cool <= 0.0:
			Game.say("DRIFT COURSE  GET IN A CAR", 2.0)
			_cool = COOLDOWN
		return false
	if id == ARENA and not is_instance_valid(Game.enemies):
		return false
	active = id
	_car_run = Game.player.get(&"vehicle") != null
	elapsed = 0.0
	progress_i = 0
	hits = 0
	_course = parkour_points() if id == PARKOUR else drift_gates() if id == DRIFT else ([] as Array[Vector3])
	if id == RANGE:
		_spawn_targets()
	elif id == ARENA:
		progress_i = 0
		_next_wave()
	_place_beacon()
	Game.say("%s  GO" % NAMES[id], 1.5)
	started.emit(id)
	return true


func _on_died() -> void:
	if active == ARENA:
		_finish(false)      # the waves reached still count
	else:
		stop()


## HUD data: {visible, title, time, score, best}.
func readout() -> Dictionary:
	if active == &"":
		return {"visible": false}
	var t := "%d" % ceili(maxf(RANGE_TIME - elapsed, 0.0)) if active == RANGE else "%.1f" % elapsed
	var sc := ""
	var b := float(best[active])
	match active:
		RANGE: sc = "HITS %d" % hits
		ARENA: sc = "WAVE %d / %d" % [progress_i, ARENA_WAVES]
		_: sc = "GATE %d / %d" % [mini(progress_i + 1, _course.size()), _course.size()]
	var bs := "BEST --" if b <= 0.0 else "BEST " + _fmt(active, b)
	return {"visible": true, "title": NAMES[active], "time": t, "score": sc, "best": bs}


## Ends the running activity without a result (death, respawn, new game, leaving).
func stop() -> void:
	if active == &"":
		return
	_cleanup()
	active = &""
	_cool = COOLDOWN


func _step_range() -> void:
	for t in _targets:
		if is_instance_valid(t) and t.dead:
			hits += 1
			Game.add_score(10)
			var prog := Game.progress as Progress
			if prog != null:
				prog.add_credits(int(REWARD[RANGE]))
			_respawn_target(t)


func _step_course(radius: float, limit: float, vertical: bool) -> void:
	if elapsed >= limit:
		Game.say("%s  TIME UP" % NAMES[active], 2.0)
		stop()
		return
	var p := Game.player.global_position
	var c := _course[progress_i]
	var d := Vector2(p.x - c.x, p.z - c.z).length()
	if d <= radius and (not vertical or absf(p.y - c.y) < 4.0):
		progress_i += 1
		if progress_i >= _course.size():
			_finish(true)
		else:
			Sfx.play(&"pickup")
			_place_beacon()


func _step_arena() -> void:
	var alive := 0
	for f in _foes:
		if is_instance_valid(f) and not bool(f.get(&"dead")) and bool(f.get(&"active")) != false:
			alive += 1
	if alive == 0:
		var prog := Game.progress as Progress
		if prog != null:
			prog.add_credits(int(REWARD[ARENA]) * progress_i)
		if progress_i >= ARENA_WAVES:
			if prog != null:
				prog.add_credits(ARENA_CLEAR_BONUS)
			progress_i += 1         # waves cleared = progress_i - 1
			_finish(true)
			return
		_next_wave()


func _next_wave() -> void:
	progress_i += 1
	_foes.clear()
	var types: Array[StringName] = [&"operative", &"sentinel", &"striker", &"heavy"]
	var n := mini(progress_i + 1, 6)
	var spots := arena_spawns()
	for k in n:
		var d: Variant = Game.enemies.call(&"spawn", types[(k + progress_i) % types.size() if progress_i > 2 else 0], spots[k % spots.size()], true)
		if d != null:
			_foes.append(d)
	Game.say("ARENA  WAVE %d" % progress_i, 1.5)


## Arena ends only by failure (death / stop): the score is the last wave reached.
func end_arena() -> void:
	if active == ARENA:
		_finish(true)


func _finish(ok: bool) -> void:
	var id := active
	var score := 0.0
	var record := false
	match id:
		RANGE:
			score = float(hits)
			record = score > float(best[id])
		PARKOUR:
			score = elapsed
			record = float(best[id]) <= 0.0 or score < float(best[id])
		DRIFT:
			score = elapsed
			record = board.size() < BOARD_SIZE or score < board[board.size() - 1]
			board.append(score)
			board.sort()
			board = board.slice(0, BOARD_SIZE)
			best[id] = board[0]
		ARENA:
			score = float(maxi(progress_i - 1, 0))
			record = score > float(best[id])
	if record and id != DRIFT:
		best[id] = score
	var prog := Game.progress as Progress
	if ok and prog != null and REWARD[id] != null and (id == PARKOUR or id == DRIFT):
		prog.add_credits(int(REWARD[id]))
	_cleanup()
	active = &""
	_cool = COOLDOWN
	save_scores()
	Game.say("%s  %s%s" % [NAMES[id], _fmt(id, score), "  NEW BEST" if record else ""], 3.0)
	finished.emit(id, score, record)


static func _fmt(id: StringName, v: float) -> String:
	return "%d HITS" % int(v) if id == RANGE else "%d WAVES" % int(v) if id == ARENA else "%.1f S" % v


func _cleanup() -> void:
	for t in _targets:
		if is_instance_valid(t):
			t.queue_free()
	_targets.clear()
	for f in _foes:
		if is_instance_valid(f) and is_instance_valid(Game.enemies) and bool(f.get(&"active")) and not bool(f.get(&"dead")):
			Game.enemies.call(&"release", f)
	_foes.clear()
	_course = []
	if _beacon != null:
		_beacon.visible = false


func _spawn_targets() -> void:
	for k in TARGETS:
		var t := Target.new()
		t.collision_layer = Game.L_ENEMY
		t.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.7
		cs.shape = sh
		t.add_child(cs)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.6
		sm.height = 1.2
		sm.radial_segments = 12
		sm.rings = 6
		mi.mesh = sm
		mi.material_override = _glow(Color(1.0, 0.35, 0.2))
		t.add_child(mi)
		add_child(t)
		t.position = target_pos(k)
		_targets.append(t)


func _respawn_target(t: Target) -> void:
	t.dead = false
	t.position = target_pos(randi() % 7)


func target_count() -> int:
	return _targets.size()


func _place_beacon() -> void:
	if _beacon == null:
		return
	if active == PARKOUR or active == DRIFT:
		_beacon.global_position = _course[progress_i] + Vector3(0.0, 0.0 if active == PARKOUR else -0.8, 0.0)
		_beacon.scale = Vector3.ONE * (1.0 if active == PARKOUR else 2.6)
		_beacon.visible = true
	else:
		_beacon.visible = false


func _build_visual() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = ENTRY_RADIUS * 0.8
	mesh.bottom_radius = ENTRY_RADIUS * 0.8
	mesh.height = 6.0
	mesh.radial_segments = 16
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = IDS.size()
	var e := entries()
	for i in IDS.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, e[IDS[i]] + Vector3(0.0, 3.0, 0.0)))
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = mm
	_mmi.material_override = _glow(Color(0.2, 0.9, 1.0), 0.35)
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	_beacon = MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 1.2
	bm.bottom_radius = 1.2
	bm.height = 8.0
	bm.radial_segments = 12
	bm.rings = 1
	bm.cap_top = false
	bm.cap_bottom = false
	_beacon.mesh = bm
	_beacon.material_override = _glow(Color(1.0, 0.8, 0.3), 0.4)
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon.visible = false
	add_child(_beacon)


static func _glow(c: Color, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func save_scores() -> void:
	var cf := ConfigFile.new()
	for id: StringName in IDS:
		cf.set_value("best", String(id), float(best[id]))
	cf.set_value("drift", "board", board)
	cf.save(save_path)


func load_scores() -> void:
	var cf := ConfigFile.new()
	if cf.load(save_path) != OK:
		return
	for id: StringName in IDS:
		best[id] = float(cf.get_value("best", String(id), 0.0))
	board.clear()
	for v in cf.get_value("drift", "board", []):
		board.append(float(v))
	board.sort()
