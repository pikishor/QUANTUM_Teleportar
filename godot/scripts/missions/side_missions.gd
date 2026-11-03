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

const ORDER: Array[StringName] = [&"courier", &"photo", &"relay", &"rescue", &"car_drop", &"turf", &"rooftop", &"heist", &"hunt", &"smuggler"]
## title, one-line brief, base reward (credits), reputation, chapter needed, time limit (0 = none), stage recipe.
## Stage recipe items: ["goto", dist, radius, car], ["dwell", secs, radius], ["photo", dist], ["kill", n].
const DEFS := {
	&"courier": {"title": "COURIER", "brief": "Deliver the package across the district before the timer ends.", "pay": 220, "rep": 3, "chapter": 0, "limit": 80.0, "stages": [["goto", 90.0, 7.0, false], ["goto", 140.0, 7.0, false]]},
	&"photo": {"title": "PHOTO CAPTURE", "brief": "Photograph three landmarks: get close and keep them in frame.", "pay": 260, "rep": 3, "chapter": 0, "limit": 0.0, "stages": [["photo", 80.0], ["photo", 120.0], ["photo", 160.0]]},
	&"relay": {"title": "DRONE RELAY HACK", "brief": "Reach the relay and hold the ring while it uploads.", "pay": 320, "rep": 4, "chapter": 0, "limit": 120.0, "stages": [["goto", 110.0, 8.0, false], ["dwell", 18.0, 9.0]]},
	&"rescue": {"title": "RESCUE", "brief": "Reach the stranded civilian, then bring them back to the start.", "pay": 300, "rep": 6, "chapter": 1, "limit": 110.0, "stages": [["goto", 100.0, 6.0, false], ["goto", 0.0, 8.0, false]]},
	&"car_drop": {"title": "CAR DELIVERY", "brief": "Drive the car to the drop-off point.", "pay": 380, "rep": 3, "chapter": 1, "limit": 90.0, "stages": [["goto", 220.0, 10.0, true]]},
	&"turf": {"title": "TURF DEFENCE", "brief": "Hold your block: stay in the ring and take down four intruders.", "pay": 420, "rep": 5, "chapter": 2, "limit": 150.0, "stages": [["dwell", 20.0, 16.0], ["kill", 4]]},
	&"rooftop": {"title": "ROOFTOP RACE", "brief": "Hit four checkpoints in order against a tight clock.", "pay": 440, "rep": 4, "chapter": 2, "limit": 70.0, "stages": [["goto", 50.0, 7.0, false], ["goto", 100.0, 7.0, false], ["goto", 100.0, 7.0, false], ["goto", 90.0, 7.0, false]]},
	&"heist": {"title": "INTERIOR HEIST", "brief": "Reach the three vault nodes in the order shown, then crack the lock.", "pay": 520, "rep": 6, "chapter": 3, "limit": 140.0, "stages": [["goto", 60.0, 6.0, false], ["goto", 70.0, 6.0, false], ["goto", 70.0, 6.0, false], ["dwell", 8.0, 7.0]]},
	&"hunt": {"title": "BOSS-LITE HUNT", "brief": "Hunt down the marked lieutenant's squad: eight confirmed kills.", "pay": 600, "rep": 8, "chapter": 4, "limit": 150.0, "stages": [["kill", 8]]},
	&"smuggler": {"title": "SMUGGLER CHASE", "brief": "Run the contraband through two checkpoints by car.", "pay": 680, "rep": 6, "chapter": 4, "limit": 100.0, "stages": [["goto", 150.0, 10.0, true], ["goto", 200.0, 10.0, true]]},
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


func _ready() -> void:
	add_to_group(&"side_missions")
	set_physics_process(true)
	Game.new_game.connect(abort.bind("RESET"))
	Game.respawn.connect(abort.bind("DOWN"))


# --- pure rules ---------------------------------------------------------------------------------------------------------

static func def(mid: StringName) -> Dictionary:
	return DEFS.get(mid, {})


static func unlocked(mid: StringName, chapter: int) -> bool:
	return DEFS.has(mid) and chapter >= int(DEFS[mid]["chapter"])


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
			"kill":
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
	return unlocked(mid, _chapter())


func start(mid: StringName, from := Vector3.INF) -> bool:
	if not can_start(mid):
		return false
	var p := Game.player
	origin = from if from.is_finite() else (p.global_position if is_instance_valid(p) else Vector3.ZERO)
	var prog := Game.progress as Progress
	var n := int(prog.side_done.get(mid, 0)) if prog != null else 0
	id = mid
	stages = build_route(mid, origin, n)
	stage = 0
	clock = 0.0
	progress_val = 0.0
	limit = float(DEFS[mid]["limit"])
	active = true
	_hook_kills()
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
	if done:
		_next_stage()


func _physics_process(delta: float) -> void:
	if not active or Game.state != &"play" or not is_instance_valid(Game.player):
		return
	var fwd := -Game.camera.global_transform.basis.z if is_instance_valid(Game.camera) else Vector3.RIGHT
	tick(delta, Game.player.global_position, fwd, (Game.player as Player).vehicle != null)
	_update_marker()


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
	_update_marker()


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
	var t := "" if limit <= 0.0 else "   %d s" % int(ceilf(maxf(limit - clock, 0.0)))
	return "%s  %d/%d  %s%s" % [DEFS[id]["title"], stage + 1, stages.size(), what, t]


## Current waypoint (Vector3.INF when none or the stage has no place, e.g. a kill stage).
func waypoint() -> Vector3:
	if not active or String(stages[stage]["kind"]) == "kill":
		return Vector3.INF
	return stages[stage]["pos"]


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
