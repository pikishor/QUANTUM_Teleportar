class_name SideMissions
extends Node
## Side missions (Game.missions.sides): ten fixed jobs on a board in the pause shop (SideBoard), beyond the procedural contracts. Each job is a chain of stages built from five
## primitives: `goto` (reach a waypoint, optional `car` = in a vehicle), `dwell` (stay inside a ring for N s), `photo` (stand within range of a landmark and look at it),
## `kill` (N confirmed kills) and a mission clock (`limit`). Waypoints are placed around the player when the job starts (seeded per job so a retry gives the same route).
## Progress is save-compatible: `Progress.side_done` (id -> completions) and `side_best` (id -> best time) live in an optional [side] section of SAVE_VERSION 1.
## Pure rules are static (def, unlocked, reward, build_route); the node holds the running job. Simulates only while Game.state == play; tick() is callable by tests.

signal started(id: StringName)
signal stage_changed(index: int)
signal finished(id: StringName, ok: bool, reason: String)

const ORDER: Array[StringName] = [&"courier", &"photo", &"relay", &"rescue", &"car_drop", &"turf", &"rooftop", &"heist", &"hunt", &"smuggler",
	&"bounty", &"sniper", &"swarm", &"car_theft", &"hostage", &"blackout", &"data_courier", &"arena", &"demolition", &"anomaly"]
## title, one-line brief, base reward (credits), reputation, chapter needed, time limit (0 = none), stage recipe.
## Stage recipe items: ["goto", dist, radius, car], ["dwell", secs, radius], ["photo", dist], ["kill", n], ["smash", n] (break n props). Optional job keys: `heat` (heat added at start), `dark` (night vision overlay).
const DEFS := {
	&"courier": {"title": "COURIER", "brief": "Deliver the package across the district before the timer ends.", "pay": 220, "rep": 3, "chapter": 0, "limit": 80.0, "stages": [["goto", 90.0, 7.0, false], ["goto", 140.0, 7.0, false]]},
	&"photo": {"title": "PHOTO CAPTURE", "brief": "Photograph three landmarks: get close and keep them in frame.", "pay": 290, "rep": 3, "chapter": 0, "limit": 0.0, "stages": [["photo", 80.0], ["photo", 120.0], ["photo", 160.0]]},
	&"relay": {"title": "DRONE RELAY HACK", "brief": "Reach the relay and hold the ring while it uploads.", "pay": 320, "rep": 4, "chapter": 0, "limit": 120.0, "stages": [["goto", 110.0, 8.0, false], ["dwell", 18.0, 9.0]]},
	&"rescue": {"title": "RESCUE", "brief": "Reach the stranded civilian, then bring them back to the start.", "pay": 300, "rep": 6, "chapter": 1, "limit": 110.0, "stages": [["goto", 100.0, 6.0, false], ["goto", 0.0, 8.0, false]]},
	&"car_drop": {"title": "CAR DELIVERY", "brief": "Drive the car to the drop-off point.", "pay": 380, "rep": 3, "chapter": 1, "limit": 90.0, "stages": [["goto", 220.0, 10.0, true]]},
	&"turf": {"title": "TURF DEFENCE", "brief": "Hold your block: stay in the ring and take down four intruders.", "pay": 420, "rep": 5, "chapter": 2, "limit": 150.0, "stages": [["dwell", 20.0, 16.0], ["kill", 4]]},
	&"rooftop": {"title": "ROOFTOP RACE", "brief": "Hit four checkpoints in order against a tight clock.", "pay": 410, "rep": 4, "chapter": 2, "limit": 70.0, "stages": [["goto", 50.0, 7.0, false], ["goto", 100.0, 7.0, false], ["goto", 100.0, 7.0, false], ["goto", 90.0, 7.0, false]]},
	&"heist": {"title": "INTERIOR HEIST", "brief": "Reach the three vault nodes in the order shown, then crack the lock.", "pay": 520, "rep": 6, "chapter": 3, "limit": 140.0, "stages": [["goto", 60.0, 6.0, false], ["goto", 70.0, 6.0, false], ["goto", 70.0, 6.0, false], ["dwell", 8.0, 7.0]]},
	&"hunt": {"title": "BOSS-LITE HUNT", "brief": "Hunt down the marked lieutenant's squad: eight confirmed kills.", "pay": 560, "rep": 8, "chapter": 4, "limit": 150.0, "stages": [["kill", 8]]},
	&"smuggler": {"title": "SMUGGLER CHASE", "brief": "Run the contraband through two checkpoints by car.", "pay": 500, "rep": 6, "chapter": 4, "limit": 100.0, "stages": [["goto", 150.0, 10.0, true], ["goto", 200.0, 10.0, true]]},
	&"bounty": {"title": "BOUNTY HUNT", "brief": "Track the roaming elite to the marked block and take down its escort.", "pay": 360, "rep": 5, "chapter": 1, "limit": 130.0, "stages": [["goto", 120.0, 12.0, false], ["kill", 3]]},
	&"sniper": {"title": "ROOFTOP DEFENCE", "brief": "Hold the rooftop ring and pick off five attackers.", "pay": 400, "rep": 5, "chapter": 2, "limit": 140.0, "stages": [["dwell", 15.0, 10.0], ["kill", 5]]},
	&"swarm": {"title": "DRONE SWARM", "brief": "Reach the swarm nest and clear ten drones.", "pay": 460, "rep": 5, "chapter": 2, "limit": 140.0, "stages": [["goto", 70.0, 10.0, false], ["kill", 10]]},
	&"car_theft": {"title": "VEHICLE THEFT", "brief": "Take the car to the drop with the patrols on your tail.", "pay": 500, "rep": 5, "chapter": 3, "limit": 110.0, "heat": 1.5, "stages": [["goto", 40.0, 8.0, true], ["goto", 200.0, 10.0, true]]},
	&"hostage": {"title": "HOSTAGE RESCUE", "brief": "Clear the captors, free the hostage, bring them back.", "pay": 540, "rep": 7, "chapter": 3, "limit": 150.0, "stages": [["goto", 80.0, 7.0, false], ["kill", 3], ["goto", 0.0, 8.0, false]]},
	&"blackout": {"title": "BLACKOUT DISTRICT", "brief": "The lights are out: night vision on, reach the grid and restore it.", "pay": 540, "rep": 6, "chapter": 3, "limit": 130.0, "dark": true, "stages": [["goto", 80.0, 7.0, false], ["dwell", 12.0, 8.0], ["goto", 120.0, 8.0, false]]},
	&"data_courier": {"title": "DATA COURIER", "brief": "Carry the drive through three districts before it expires.", "pay": 330, "rep": 4, "chapter": 1, "limit": 120.0, "stages": [["goto", 180.0, 8.0, false], ["goto", 220.0, 8.0, false], ["goto", 160.0, 8.0, false]]},
	&"arena": {"title": "ARENA DUEL", "brief": "Step into the ring, hold it and defeat six challengers.", "pay": 600, "rep": 8, "chapter": 4, "limit": 150.0, "stages": [["dwell", 10.0, 14.0], ["kill", 6]]},
	&"demolition": {"title": "TIMED DEMOLITION", "brief": "Break eight props before the clock runs out.", "pay": 280, "rep": 3, "chapter": 0, "limit": 80.0, "stages": [["smash", 8]]},
	&"anomaly": {"title": "PHOTOGRAPH ANOMALIES", "brief": "Photograph four rifts: get close and keep them in frame.", "pay": 420, "rep": 4, "chapter": 2, "limit": 0.0, "stages": [["photo", 70.0], ["photo", 110.0], ["photo", 150.0], ["photo", 190.0]]},
}

var id: StringName = &""
var active := false
var stage := 0
var stages: Array = []                  ## built stages: {kind, pos, r, secs, n, car}
var clock := 0.0
var limit := 0.0
var progress_val := 0.0                 ## dwell seconds so far / kills so far in the current stage
var origin := Vector3.ZERO
var last_result: Dictionary = {}        ## {id, ok, reason, reward} of the last job
var _marker: MeshInstance3D
var _kills_hooked := false
var _smash_base := 0                    ## Breakables.break_total when the smash stage began
var _nv: ColorRect                      ## night-vision overlay (blackout job)
var _foes: Array = []                   ## enemies a kill stage spawned (the job's own intruders, topped up while kills are left)
var _top_t := 0.0
var _smash_t := 0.0
var _smash_pos := Vector3.INF           ## nearest unbroken prop (the waypoint of a smash stage)


func _ready() -> void:
	add_to_group(&"side_missions")
	set_physics_process(true)
	Game.new_game.connect(abort.bind("RESET"))
	Game.respawn.connect(abort.bind("DOWN"))


# --- pure rules ---------------------------------------------------------------------------------------------------------

static func def(mid: StringName) -> Dictionary:
	return DEFS.get(mid, {})


static func unlocked(mid: StringName, chapter: int) -> bool:
	return DEFS.has(mid) and (chapter >= int(DEFS[mid]["chapter"]) or DemoMode.active)      # DEMO MODE: every job from the start


## Credits for a completion: base x sector reward factor x reputation bonus, +25 % when finished with at least a third of the clock left, never below 1.
static func reward(mid: StringName, chapter: int, rep: int, time_left_frac: float) -> int:
	if not DEFS.has(mid):
		return 0
	var v := float(Economy.SIDE_PAY[mid]) * float(Progress.difficulty(chapter)["reward"]) * (1.0 + Progress.rep_bonus(rep))
	if time_left_frac >= 1.0 / 3.0:
		v *= 1.25
	return maxi(1, int(round(v / 5.0)) * 5)


## Waypoints for a job around `from`; the same (id, from, seed) always gives the same route. The final `goto` of `rescue` returns to `from`.
static func build_route(mid: StringName, from: Vector3, seed_val: int) -> Array:
	var out: Array = []
	if not DEFS.has(mid):
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(mid)) ^ seed_val
	var heading := rng.randf() * TAU
	var here := from
	for item: Array in DEFS[mid]["stages"]:
		var s := {"kind": StringName(item[0]), "pos": here, "r": 8.0, "secs": 0.0, "n": 0, "car": false}
		match String(item[0]):
			"goto":
				heading += rng.randf_range(-1.1, 1.1)
				var d := float(item[1])
				if d > 0.0:
					here = here + Vector3(cos(heading), 0.0, sin(heading)) * d
				else:
					here = from
				s["pos"] = here
				s["r"] = float(item[2])
				s["car"] = bool(item[3])
			"photo":
				heading += rng.randf_range(0.8, 2.2)
				here = from + Vector3(cos(heading), 0.0, sin(heading)) * float(item[1])
				s["pos"] = here
				s["r"] = 38.0
			"dwell":
				s["secs"] = float(item[1])
				s["r"] = float(item[2])
			"kill", "smash":
				s["n"] = int(item[1])
		out.append(s)
	return out


# --- running a job ------------------------------------------------------------------------------------------------------

func _chapter() -> int:
	return int(Game.story.get("chapter")) if is_instance_valid(Game.story) else 0


func can_start(mid: StringName) -> bool:
	if active or not DEFS.has(mid):
		return false
	var ct: Variant = Game.missions.get("contracts") if is_instance_valid(Game.missions) else null
	if ct != null and ct.get("state") == &"active":
		return false
	return unlocked(mid, _chapter()) and Factions.job_open(Game.progress, mid)       # closed while the job's client camp is hostile


func start(mid: StringName, from := Vector3.INF) -> bool:
	if not can_start(mid):
		return false
	var p := Game.player
	origin = from if from.is_finite() else (p.global_position if is_instance_valid(p) else Vector3.ZERO)
	var prog := Game.progress as Progress
	var n := int(prog.side_done.get(mid, 0)) if prog != null else 0
	id = mid
	stages = build_route(mid, origin, n)
	_snap_to_streets(origin)
	stage = 0
	clock = 0.0
	progress_val = 0.0
	limit = _fit_limit(float(DEFS[mid]["limit"]))
	active = true
	_hook_kills()
	_smash_base = Breakables.current.break_total if Breakables.current != null else 0
	if float(DEFS[mid].get("heat", 0.0)) > 0.0:
		Game.add_heat(float(DEFS[mid]["heat"]))
	_set_night_vision(bool(DEFS[mid].get("dark", false)))
	_stage_begins()
	_update_marker()
	started.emit(mid)
	Game.message.emit("%s: %s" % [DEFS[mid]["title"], DEFS[mid]["brief"]], 5.0)
	return true


func abort(reason := "ABANDONED") -> void:
	if active:
		_end(false, reason)


## Advance by `delta` s. `ppos` player position, `look` camera forward (flat or 3D), `in_car` the player drives. Production calls it from _physics_process.
func tick(delta: float, ppos: Vector3, look: Vector3, in_car: bool) -> void:
	if not active:
		return
	clock += delta
	if limit > 0.0 and clock >= limit:
		_end(false, "TIME UP")
		return
	var s: Dictionary = stages[stage]
	var flat := Vector2(ppos.x - float(s["pos"].x), ppos.z - float(s["pos"].z)).length()
	var done := false
	match String(s["kind"]):
		"goto":
			done = flat <= float(s["r"]) and (in_car or not bool(s["car"]))
		"dwell":
			if flat <= float(s["r"]):
				progress_val += delta
			else:
				progress_val = maxf(0.0, progress_val - delta * 0.5)        # slips back at half speed outside the ring
			done = progress_val >= float(s["secs"])
		"photo":
			var to := Vector2(float(s["pos"].x) - ppos.x, float(s["pos"].z) - ppos.z)
			var fwd := Vector2(look.x, look.z)
			if flat <= float(s["r"]) and to.length() > 0.01 and fwd.length() > 0.01:
				done = absf(fwd.angle_to(to)) <= deg_to_rad(28.0)
		"kill":
			done = progress_val >= float(s["n"])
		"smash":
			done = progress_val >= float(s["n"])
	if done:
		_next_stage()
		return
	if String(s["kind"]) == "kill":
		_top_t -= delta
		if _top_t <= 0.0:
			_top_t = 1.5
			_topup_foes()
	elif String(s["kind"]) == "smash":
		_smash_t -= delta
		if _smash_t <= 0.0:
			_smash_t = 0.6
			_smash_pos = _nearest_prop(ppos)


func _nearest_prop(from: Vector3) -> Vector3:
	var b := Breakables.current
	if b == null:
		return Vector3.INF
	var best := Vector3.INF
	var bd := INF
	for i in b.positions.size():
		if b.broken[i] == 1:
			continue
		var d := Vector2(b.positions[i].x - from.x, b.positions[i].z - from.z).length_squared()
		if d < bd:
			bd = d
			best = b.positions[i]
	return best


func _physics_process(delta: float) -> void:
	if not active or Game.state != &"play" or not is_instance_valid(Game.player):
		return
	var fwd := -Game.camera.global_transform.basis.z if is_instance_valid(Game.camera) else Vector3.RIGHT
	var b := Breakables.current
	if b != null:
		var d := b.break_total - _smash_base
		_smash_base = b.break_total
		for i in maxi(d, 0):
			on_smash()
	tick(delta, Game.player.global_position, fwd, (Game.player as Player).vehicle != null)
	_update_marker()


## One prop broken (live: polled from Breakables.break_total in _physics_process).
func on_smash() -> void:
	if active and String(stages[stage]["kind"]) == "smash":
		progress_val += 1.0


func on_kill() -> void:
	if active and String(stages[stage]["kind"]) == "kill":
		progress_val += 1.0


func _hook_kills() -> void:
	if _kills_hooked or not is_instance_valid(Game.player) or not Game.player.has_signal(&"hit_confirmed"):
		return
	_kills_hooked = true
	Game.player.connect(&"hit_confirmed", func(kill: bool, _crit: bool) -> void:
		if kill:
			on_kill())


func _next_stage() -> void:
	stage += 1
	progress_val = 0.0
	if stage >= stages.size():
		_end(true, "")
		return
	stage_changed.emit(stage)
	_stage_begins()
	_update_marker()


## Waypoints are picked at a distance and a heading from the start, which lands inside a building as often as not (found by the mission audit: a courier job whose marker stood in a
## tower). A goto / photo / dwell point that is not the start itself moves to the nearest street point, so every job can be walked.
func _snap_to_streets(from: Vector3) -> void:
	for st: Dictionary in stages:
		var at: Vector3 = st["pos"]
		if at.is_equal_approx(from) or String(st["kind"]) in ["kill", "smash"]:
			continue
		var q := PlayerUtil.nearest_street(at)
		st["pos"] = Vector3(q.x, from.y, q.z)
	var here := from
	for st: Dictionary in stages:                           # the kill / smash stages keep the place of the stage before them
		if String(st["kind"]) in ["kill", "smash"]:
			st["pos"] = here
		else:
			here = st["pos"]


## A timed job must be possible: the clock is at least 25 s plus the way (street legs at 5 m/s on foot, 9 m/s by car; a smash stage walks to the nearest props) so a job whose markers
## landed far apart is not lost before it begins (found by the mission audit: TIMED DEMOLITION and SMUGGLER CHASE ran out of time for a bot that drove straight).
func _fit_limit(base: float) -> float:
	if base <= 0.0:
		return 0.0
	var need := 25.0
	var here := origin
	for st: Dictionary in stages:
		match String(st["kind"]):
			"goto":
				need += (Vector2(st["pos"].x - here.x, st["pos"].z - here.z).length() * 1.3) / (9.0 if bool(st["car"]) else 5.0)
				here = st["pos"]
			"smash":
				var b := Breakables.current
				if b != null:
					var left := int(st["n"])
					var from := here
					var used := {}
					while left > 0:
						var best := -1
						var bd := INF
						for i in b.positions.size():
							if b.broken[i] == 1 or used.has(i):
								continue
							var d := Vector2(b.positions[i].x - from.x, b.positions[i].z - from.z).length()
							if d < bd:
								bd = d
								best = i
						if best < 0:
							break
						used[best] = true
						need += bd * 1.3 / 5.0 + 2.0
						from = b.positions[best]
						left -= 1
	return maxf(base, need)


## A kill stage needs enemies: the job brings its own intruders (aware, on the streets around the ring) and tops them up while kills are left; a smash stage points at the nearest prop.
func _stage_begins() -> void:
	_release_foes()
	_top_t = 0.0
	_smash_t = 0.0
	if not active:
		return
	if String(stages[stage]["kind"]) == "kill":
		_topup_foes(true)


func _kills_left() -> int:
	return maxi(int(stages[stage]["n"]) - int(progress_val), 0)


func _alive_foes() -> int:
	var n := 0
	for f: Variant in _foes:
		var d := f as Drone
		if d != null and is_instance_valid(d) and d.active and not d.dead:
			n += 1
	return n


func _topup_foes(first := false) -> void:
	var em := Game.enemies as EnemyManager
	var pl := Game.player as Player
	if em == null or not is_instance_valid(pl):
		return
	var want := mini(_kills_left(), 4)
	var tries := 0
	while _alive_foes() < want and tries < 6:
		tries += 1
		var a := randf() * TAU
		var center: Vector3 = stages[stage]["pos"] if first else pl.global_position
		var q := PlayerUtil.nearest_street(center + Vector3(cos(a), 0.0, sin(a)) * randf_range(22.0, 40.0))
		var d := em.spawn(&"operative" if (_foes.size() % 2 == 0) else &"sentinel", Vector3(q.x, 0.0, q.z), true)
		if d == null:                                       # the street's own patrols filled the tier's cap: the job comes first
			if em.make_room(_foes, pl.global_position):
				continue
			break
		_foes.append(d)


func _release_foes() -> void:
	var em := Game.enemies as EnemyManager
	if em != null:
		for f: Variant in _foes:
			var d := f as Drone
			if d != null and is_instance_valid(d) and d.active:
				em.release(d)
	_foes.clear()


func _end(ok: bool, reason: String) -> void:
	var mid := id
	var left := 0.0 if limit <= 0.0 else clampf(1.0 - clock / limit, 0.0, 1.0)
	var pay := 0
	var prog := Game.progress as Progress
	if ok:
		pay = reward(mid, _chapter(), prog.reputation if prog != null else 0, left)
		if prog != null:
			prog.complete_side(mid, pay, DEFS[mid]["rep"], clock)
	elif prog != null:
		prog.add_reputation(-1)
	last_result = {"id": mid, "ok": ok, "reason": reason, "reward": pay, "time": clock}
	active = false
	stages = []
	_release_foes()
	_set_night_vision(false)
	_update_marker()
	Game.message.emit(("%s COMPLETE  +%d" % [DEFS[mid]["title"], pay]) if ok else ("%s FAILED  %s" % [DEFS[mid]["title"], reason]), 4.0)
	finished.emit(mid, ok, reason)


## HUD line while a job runs ("" when idle): title, stage x of n, what to do, clock.
func status_line() -> String:
	if not active:
		return ""
	var s: Dictionary = stages[stage]
	var what := ""
	match String(s["kind"]):
		"goto": what = "GO TO MARKER" + ("  (IN A CAR)" if bool(s["car"]) else "")
		"dwell": what = "HOLD  %d / %d s" % [int(progress_val), int(s["secs"])]
		"photo": what = "PHOTO  LOOK AT LANDMARK"
		"kill": what = "TAKE DOWN  %d / %d" % [int(progress_val), int(s["n"])]
		"smash": what = "BREAK PROPS  %d / %d" % [int(progress_val), int(s["n"])]
	var t := "" if limit <= 0.0 else "   %d s" % int(ceilf(maxf(limit - clock, 0.0)))
	return "%s  %d/%d  %s%s" % [DEFS[id]["title"], stage + 1, stages.size(), what, t]


## Current waypoint (Vector3.INF when none or the stage has no place, e.g. a kill stage).
func waypoint() -> Vector3:
	if not active:
		return Vector3.INF
	match String(stages[stage]["kind"]):
		"kill":
			var best := Vector3.INF
			var bd := INF
			var pp := Game.player.global_position if is_instance_valid(Game.player) else Vector3.ZERO
			for f: Variant in _foes:
				var d := f as Drone
				if d != null and is_instance_valid(d) and d.active and not d.dead:
					var dist := d.global_position.distance_to(pp)
					if dist < bd:
						bd = dist
						best = d.global_position
			return best
		"smash":
			return _smash_pos
	return stages[stage]["pos"]


## Blackout: a cheap full-screen green multiply tint (one canvas rect, no 3D cost).
func _set_night_vision(on: bool) -> void:
	if on and _nv == null:
		var layer := CanvasLayer.new()
		layer.layer = 5
		_nv = ColorRect.new()
		_nv.color = Color(0.45, 1.0, 0.55)
		_nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_nv.set_anchors_preset(Control.PRESET_FULL_RECT)
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		_nv.material = mat
		layer.add_child(_nv)
		add_child(layer)
	if _nv != null:
		_nv.get_parent().visible = on


func night_vision_on() -> bool:
	return _nv != null and _nv.get_parent().visible


func _update_marker() -> void:
	var w := waypoint()
	if not w.is_finite():
		if _marker != null:
			_marker.visible = false
		return
	if _marker == null:
		_marker = MeshInstance3D.new()
		var m := CylinderMesh.new()
		m.top_radius = 0.6
		m.bottom_radius = 0.6
		m.height = 80.0
		m.radial_segments = 8
		m.rings = 1
		_marker.mesh = m
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(1.0, 0.72, 0.25, 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_marker.material_override = mat
		_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_marker)
		_marker.top_level = true
	_marker.visible = true
	_marker.global_position = Vector3(w.x, 40.0, w.z)
