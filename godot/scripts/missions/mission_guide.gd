class_name MissionGuide
extends RefCounted
## "What do I do?" and "I am stuck" for the scripted campaign (owner round 3). One guide per CampaignRunner (`camp.guide`, ticked by `CampaignRunner.tick`). It does four things:
##  1. ALWAYS ONE OBJECTIVE: `line()` is the HUD line of the running step, and while the next step is armed (or the player stands inside a building the next street step cannot start in) it
##     says what comes next: "NEXT  HACK THE LEDGER NODE" or "LEAVE THE BUILDING TO CONTINUE". `waypoint()` points the HUD diamond and the compass at the goal in those states too (the way
##     out of a building, the next goal).
##  2. A GENTLE REMINDER: a player who is not getting closer to the goal (no enemy fight, no car chase) hears "NEXT: GO TO THE VAULT, 420 M" every WANDER_EVERY seconds.
##  3. STUCK DETECTION: a step that shows no progress (progress bar, distance to the goal, foes, step change) for STUCK_OFFER seconds offers SKIP STEP (HUD button / K); after
##     STUCK_RECOVER seconds more the game recovers the step by itself (`recover()`: the goal is re-anchored beside the player, else the step is completed), so no task can hard-lock.
##  4. Counters for the mission audit (tests/mission_audit.gd): `recoveries`, `offers`, `last_reason`.
## Pure rules (`phrase`, `compass_bearing`) are static so tests can call them without a scene.

const STUCK_OFFER := 90.0              ## seconds without progress before SKIP STEP is offered
const STUCK_RECOVER := 60.0            ## seconds after the offer before the game recovers the step by itself
const WANDER_AFTER := 24.0             ## seconds without getting closer before the first reminder
const WANDER_EVERY := 40.0
const CLOSER := 6.0                    ## metres closer to the goal that count as progress
const PROGRESS_STEP := 0.01
const ARMED_STUCK := 45.0              ## armed (waiting) this long inside a building: the way out is forced open
const FIGHT_RANGE := 45.0              ## aware enemies this close excuse a standstill (a firefight is play, not wandering)

static var hud_on := true              ## false: line() / waypoint() / the compass / the SKIP STEP offer stay off the HUD (the "before" frames of the look-fix loops, tests/bot_mission_guide.gd)

var camp: CampaignRunner
var offering := false                  ## SKIP STEP is on offer (the HUD shows the button)
var recoveries := 0                    ## steps the game recovered by itself
var offers := 0
var skips := 0                         ## SKIP STEP taps
var reminders := 0
var last_reason := ""
var idle_seconds := 0.0                ## seconds without progress in the running step

var _key := ""
var _best_dist := INF
var _last_progress := -1.0
var _last_foes := -1
var _wander_t := 0.0
var _remind_cd := 0.0
var _armed_t := 0.0
var _announced := false


func _init(runner: CampaignRunner) -> void:
	camp = runner


# --- the objective line and the waypoint ---------------------------------------------------------------------------

## The HUD line while the step runner has nothing of its own to say ("" when no chapter runs): the next objective, or the way out of a building.
func line() -> String:
	if not hud_on or camp == null or camp.state != &"armed" or camp.step_index >= camp.steps.size():
		return ""
	if InteriorGameplay.active and _blocked_inside():
		return "LEAVE THE BUILDING TO CONTINUE"
	return "NEXT  %s" % str(camp.steps[camp.step_index].get("text", "")).to_upper()


## {pos, color} of the goal to point at while the step is armed (the exit of the building the player stands in, else the next goal), {} when unknown.
func waypoint() -> Dictionary:
	if not hud_on or camp == null or camp.state != &"armed" or camp.step_index >= camp.steps.size():
		return {}
	if InteriorGameplay.active and _blocked_inside():
		var ig := InteriorGameplay.instance
		if ig != null and is_instance_valid(ig) and ig.interior != null:
			return {"pos": InteriorGameplay.exit_point(ig.interior), "color": ContractTypes.AMBER}
		return {}
	var g := camp.goal_for(camp.step_index)
	if g.is_finite():
		return {"pos": g, "color": ContractTypes.CYAN}
	return {}


func _blocked_inside() -> bool:
	return camp._inside_blocks_step()


## The goal the player is walking to now (waypoint of the running step, or the armed step's), Vector3.INF when none.
func goal() -> Vector3:
	var w := camp.waypoint()
	if w.is_empty():
		w = waypoint()
	return w["pos"] if w.has("pos") else Vector3.INF


## Short imperative text of a step for the reminder: "HACK THE LEDGER NODE" -> "HACK THE LEDGER NODE" (upper case), with the distance: "NEXT: HACK THE LEDGER NODE, 420 M".
static func phrase(text: String, metres: float) -> String:
	var t := text.strip_edges().to_upper()
	if metres >= 1.0:
		return "NEXT: %s, %d M" % [t, roundi(metres)]
	return "NEXT: %s" % t


## Bearing of `to` as seen from `from`, in radians relative to a camera yaw `yaw` (Node3D convention, positive turns left): 0 straight ahead, positive to the RIGHT, -PI..PI.
static func compass_bearing(from: Vector3, to: Vector3, yaw: float) -> float:
	var d := to - from
	var target_yaw := atan2(-d.x, -d.z)
	return -wrapf(target_yaw - yaw, -PI, PI)


# --- ticking ----------------------------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	if camp == null or not Game.is_playing():
		return
	_remind_cd = maxf(_remind_cd - delta, 0.0)
	match camp.state:
		&"armed":
			_tick_armed(delta)
		&"active":
			_armed_t = 0.0
			_tick_active(delta)
		_:
			_reset_step()
			_armed_t = 0.0


func _reset_step() -> void:
	offering = false
	idle_seconds = 0.0
	_key = ""
	_best_dist = INF
	_last_progress = -1.0
	_last_foes = -1
	_wander_t = 0.0
	_announced = false


## Armed: the player is waiting for the next step. Inside a building that blocks it: say so, and force the door open after ARMED_STUCK seconds.
func _tick_armed(delta: float) -> void:
	offering = false
	if InteriorGameplay.active and _blocked_inside():
		_armed_t += delta
		if not _announced and _armed_t > 4.0:
			_announced = true
			_say("LEAVE THE BUILDING TO CONTINUE", 3.0)
		if _armed_t > ARMED_STUCK:
			_armed_t = 0.0
			recoveries += 1
			last_reason = "armed inside a building"
			var ig := InteriorGameplay.instance
			if ig != null and is_instance_valid(ig):
				ig.force_exit(true)
			_say("BACK ON THE STREET", 2.0)
	else:
		_armed_t = 0.0
		_announced = false


func _tick_active(delta: float) -> void:
	if InteriorGameplay.active and camp.kind != &"enter_interior" and camp.kind != &"heist":
		return                                              # the street's objectives wait while the player is indoors: not a standstill
	var key := "%d/%d" % [camp.chapter_index, camp.step_index]
	if key != _key:
		_reset_step()
		_key = key
	var p := camp._ref_pos()
	var progressed := false
	if camp.progress >= 0.0 and absf(camp.progress - _last_progress) >= PROGRESS_STEP:
		progressed = true
	_last_progress = camp.progress
	var foes := camp.foes_alive()
	if _last_foes >= 0 and foes != _last_foes:
		progressed = true
	_last_foes = foes
	var g := goal()
	var dist := INF
	if g.is_finite() and p.is_finite():
		dist = Vector2(g.x - p.x, g.z - p.z).length()
		if dist < _best_dist - CLOSER:
			_best_dist = dist
			progressed = true
			_wander_t = 0.0
	if progressed:
		idle_seconds = 0.0
		if offering:
			offering = false
	else:
		idle_seconds += delta
	# a gentle reminder when the player is not getting closer and nothing else is going on
	if g.is_finite() and not _fighting(p):
		_wander_t += delta
		if _wander_t > WANDER_AFTER and _remind_cd <= 0.0 and dist > 12.0:
			_remind_cd = WANDER_EVERY
			reminders += 1
			_say(phrase(str(camp.step.get("text", "")), dist), 3.0)
	else:
		_wander_t = maxf(_wander_t - delta, 0.0)
	# stuck: offer SKIP STEP, then recover by itself
	if idle_seconds >= STUCK_OFFER and not offering:
		offering = true
		offers += 1
		_say("STUCK?  SKIP STEP", 4.0)
	if idle_seconds >= STUCK_OFFER + STUCK_RECOVER:
		recover()


func _fighting(p: Vector3) -> bool:
	var em := Game.enemies as EnemyManager
	if em == null or not p.is_finite():
		return false
	for e in em.list:
		if e.active and not e.dead and e.aware and Vector2(e.global_position.x - p.x, e.global_position.z - p.z).length() < FIGHT_RANGE:
			return true
	return false


func _say(text: String, seconds: float) -> void:
	Game.say(text, seconds)


# --- recovery ---------------------------------------------------------------------------------------------------------

## SKIP STEP (the HUD button and K): finishes the running step as if its objective was met. False when the offer is not up.
func skip_step() -> bool:
	if not offering or camp == null or camp.state != &"active":
		return false
	skips += 1
	last_reason = "skipped by the player"
	offering = false
	idle_seconds = 0.0
	return camp.skip_step()


## The game's own way out of a stuck step. First the goal is re-anchored beside the player (a goal nobody can reach becomes a street point near them); a step that is still
## stuck afterwards (target lost, a wave that does not spawn) is completed. Called by tick after STUCK_OFFER + STUCK_RECOVER idle seconds, by the audit bot and by tests.
func recover() -> bool:
	if camp == null or camp.state != &"active":
		return false
	recoveries += 1
	last_reason = "no progress on %s for %.0f s" % [str(camp.kind), idle_seconds]
	offering = false
	idle_seconds = 0.0
	Game.say("STEP RECOVERED", 2.5)
	camp.recover_step()
	return true
