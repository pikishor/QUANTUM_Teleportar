class_name CampaignRunner
extends Node
## The scripted objective step runner (child of Missions: Game.missions.campaign). A chapter is a chain of steps (dictionaries, documented in campaign_steps.gd); the runner plays
## them one after the other with the game's real systems: Contracts' street helpers and markers, InteriorGameplay doors, EnemyManager enemies, VehicleManager cars and the heat level.
##
## StepKinds (the contract with the story data; aliases "infiltrate" = enter_interior and "assassinate" = kill_target are accepted):
##   reach           walk or drive into a ring on the street
##   enter_interior  go through a door (by id, by interior type, or the nearest door) and, with `leave`, come back out
##   escort          lead a civilian along the street route to a destination while ambushes hit; it waits when you are far or enemies are close, and it can die
##   defend          stay inside a zone for `hold` seconds while waves of Vael attack it (leave it for 10 s and you lose it)
##   hack            hold a node's ring for `hold` seconds under drone pulses (progress fills inside, drains outside)
##   kill_target     one tougher Vael (an operative, a specialist or the Overseer) with guards; boss bar on the HUD
##   chase           wreck a fleeing car (it escapes beyond 120 m for 6 s)
##   escape          the heat jumps to `heat` stars: get `dist` metres away and lose them until the heat falls below `clear`. With `patrol` n > 0 (chapters 4 and 7 "Escape the Vael
##                   patrol") n Vael patrol vehicles (VehicleManager.spawn_patrol, the wave 14 hover chase and ram) are sent after the player at once and topped up while the heat
##                   stays up; the step also needs every chasing patrol more than PATROL_LOSE metres away
##   survive         outlast `hold` seconds against waves that come at you wherever you are
##   rift_hold       sequel: hold a collapse anomaly (ring) for `hold` seconds; the bar fills only while verbs keep feeding the rift, waves hit it and drain its integrity
##   heist           sequel: go in through a door, steal (the interior's mission), get out and lose the patrol vehicles that chase you (3 phases, one step)
##   convoy_intercept sequel: 1..3 traffic cars drive off in a line; ENTANGLE / COLLAPSE / damage stop each one, all stopped = done, one far away for 6 s = it got away
## The three sequel kinds live in the section "sequel mechanics" at the end of this file; their data keys are in campaign_steps.gd.
##
## Lifecycle: start_chapter(index) arms the chapter (state armed -> active), a step ends with a checkpoint (Progress.checkpoint, saved with the campaign: chapter, step, where the player
## stands, the next step's goal) and the next step begins after a short breath. A failure (time out, target lost, escort dead, zone lost ...) or the player's death restarts the SAME step
## from its checkpoint (the player is moved back to it) after RETRY_PAUSE seconds; nothing is lost but the progress inside that step. The last step ends the chapter: chapter_completed,
## then Game.win() (unless the chapter says "clears_sector": false), the usual sector-stabilized flow follows. While a chapter with steps runs, the cores are optional pickups (Missions.win_on_cores
## false) and random contract offers are held back.
## Auto start: when the story's chapter has steps (registry from set_chapters(), else scripts/story/campaign_data.gd CAMPAIGN, else StoryData.CHAPTERS[i].steps) the runner arms it by itself
## as soon as no card or tutorial is on screen. Everything simulates only while Game.is_playing(); nothing is allocated per frame except what the enemy and vehicle pools do.
## UI: hud_line / progress_fraction / boss / waypoint for the HUD, markers / marker_count / route_points for the minimap (the same shape as Contracts), world rings and beams through ContractVisuals.

signal chapter_started(chapter: int)
signal step_started(chapter: int, index: int, kind: StringName)
signal step_completed(chapter: int, index: int, kind: StringName)
signal step_failed(chapter: int, index: int, kind: StringName, reason: String)
signal chapter_completed(chapter: int)
signal checkpoint_reached(cp: Dictionary)

## The step kinds the runner understands. Add a kind here, to CampaignSteps.KIND_DATA and to the match blocks (_begin_step, _tick_active, _markers) together.
const StepKinds: Array[StringName] = [&"reach", &"enter_interior", &"escort", &"defend", &"hack", &"kill_target", &"chase", &"escape", &"survive", &"rift_hold", &"heist", &"convoy_intercept"]

const CAMPAIGN_DATA_PATH := "res://scripts/story/campaign_data.gd"
const START_DELAY := 1.5               ## seconds after a chapter is armed (no card, no tutorial) before its first step begins
const STEP_GAP := 1.6                  ## the breath between two steps
const RETRY_PAUSE := 4.0
const BEGIN_TRIES := 6                 ## spawn failures (an area crowded, a pool at its cap) before the step counts as failed
const ZONE_LEASH := 1.6                ## defend: the zone's leash is this many radii
const ZONE_LEASH_TIME := 10.0
const HACK_DECAY := 0.6
const HACK_PULSE := 11.0
const HOLD_HEAT_DECAY := 0.06          ## heat lost per second while the hero holds the ring: the step's own pulses are the action, they do not pile up into a manhunt
const HOLD_HEAT_CAP := 1.5             ## hack / defend: killing the step's own waves never lifts the heat to patrol cars and roadblocks (director review: a hack ended at 3 stars)
const PATROL_LOSE := 60.0              ## escape with patrols: a chasing Vael patrol vehicle this close keeps the step open
const PATROL_TOPUP := 4.0              ## seconds between the attempts to bring the chase back up to the step's patrol count while the heat is up
const ESCAPE_COOL := 0.3               ## escape: heat lost per second once the player is `dist` metres away (found by the mission audit: the heat climbed to 5 with 8 hunters in sight and never came down)
const CHASE_ESCAPE := 150.0
const CHASE_ESCAPE_TIME := 8.0
const CHASE_GRACE := 25.0              ## the target cannot get away before this many seconds (the player has to reach a car and get going first; found by the mission audit)
const TAKE_CAR_HINT := 20.0            ## seconds the HUD says TAKE THE CAR (and points at the car) while the player is still on foot
const CHASE_CAR_NEAR := 30.0           ## a car this close to the player counts as "one at hand"
const ESCORT_THREAT := 16.0            ## aware enemies this close make the escortee stop
const ESCORT_HURT := 7.0               ## enemies this close hurt the escortee ...
const ESCORT_DPS := 7.0                ## ... this many hit points per second each
const ESCORT_LEFT_TIME := 15.0
const ESCORT_PATIENCE := 14.0          ## seconds the escortee waits for hostiles near it before it walks on
const ESCORT_PUSH := 6.0
const MAX_ALIVE_WAVE := 12
const TARGET_HINT_FAR := 70.0
const TARGET_HINT_R := 34.0
const VERTICAL_REACH := 6.0
const BOSS_BEAT := 0.5                 ## an Overseer that just died stays the step's target this long, so the defeat scene (Cinematics, which only starts in the play state) can start before the win
const FEED_MAX := 9.0                  ## rift_hold: most seconds of feeding a rift banks
const RIFT_DECAY := 0.3                ## rift_hold: the bar drains at this fraction of the fill rate while the rift is not fed
const RIFT_DPS := 4.0                  ## rift_hold: integrity per second each aware enemy near the rift drains
const RIFT_REGEN := 1.5
const ENTANGLE_STOP := 8.0             ## convoy: ENTANGLE swaps you into the car's place, so a car this close to the player after the swap is stopped
const COLLAPSE_STOP := 16.0            ## convoy: the COLLAPSE shockwave radius (Quantum.WAVE_RADIUS)
const CONVOY_DISABLE := 0.35           ## convoy: a car at or below this fraction of its hit points is disabled (stopped)
const CONVOY_ESCAPE := 170.0
const CONVOY_ESCAPE_TIME := 8.0
const CONVOY_GAP := 14.0
const RETRY_DIST := 32.0               ## a retried fight step starts the player this far from its goal (see _retry_spot)
const WAIT_OUTSIDE := 1.0              ## a step that is armed while the player is inside a building begins this long after the player is back on the street

## Whether the runner starts chapters by itself (the story's chapter has steps) and whether Progress's CONTINUE / chapter select start it. Like autosave it is off under tools, tests and bots
## (Game.autostart) so they keep their exact old behaviour; a test turns it on (or calls start_chapter() directly, which always works).
var enabled := true
var state: StringName = &"idle"        ## idle | armed | active | retry | held (player dead) | done
var chapter_index := -1
var chapters: Array[Dictionary] = []   ## registry set by set_chapters(): index = chapter (an empty dictionary = fall back to the story data)
var steps: Array[Dictionary] = []      ## the current chapter's normalised steps
var step_index := 0
var step: Dictionary = {}
var kind: StringName = &""
var pos := Vector3.ZERO                ## the step's goal (ring centre, zone, target spawn, destination)
var time_left := 0.0
var time_total := 0.0
var progress := -1.0                   ## 0..1 of the running step, -1 without one
var inside := false                    ## hack / defend: the player is in the ring / zone
var fails := 0                         ## failures in this chapter run
var last_fail := ""
var steps_done := 0
var retry_left := 0.0
var wave := 0
var foes: Array = []
var target: Node3D                     ## kill_target
var car: Vehicle                       ## chase
var escortee: InteriorCivilian         ## escort (pooled: built at the first escort)
var escort_hp := 0.0
var escort_max := 0.0
var checkpoint: Dictionary = {}        ## the last checkpoint {chapter, step, pos, tp, goal?}
var visuals: ContractVisuals
var rng := RandomNumberGenerator.new()
var guide: MissionGuide                ## the objective line between steps, the wander reminder and the stuck handler (scripts/missions/mission_guide.gd)
var guide_enabled := true              ## false: no stuck offer / recovery (a test that idles a step on purpose)
var _kept := {}                        ## step index -> share of a hold / hack / defend / rift bar kept for the retry (half of what the player had reached)
var _threat_wait := 0.0
var _push_t := 0.0
var _reanchored := false
var _chase_car: Vehicle                ## chase: the car left beside the player when none is near ("take a car and cut it off" needs one)
var _chase_t := 0.0                    ## chase: seconds since the step began (the target cannot escape in the first CHASE_GRACE seconds on foot)               ## recover_step() already moved this step's goal once

var _clock := 0.0
var _sp_t := 0.0                       ## set piece phase: seconds into its hazard
var _sp_anchor := Vector3.INF          ## where the current hazard cycle was aimed (the player's position when it began)
var _sp_cycle := -1
var _sp_hit := -1                      ## cycle that already dealt damage
var sp_zones: Array[Vector3] = []      ## the strike zones of the running cycle while warning / hitting (markers)
var sp_hazard_state: StringName = &"idle"
var _beat_t := 0.0                     ## kill_target: seconds since an Overseer target died
var _win_pending := false              ## the last step ended while the game was not playing (the TEST menu on the pause screen): Game.win() follows in play
var _arm_t := 0.0
var _origin := Vector3.ZERO            ## where the current step's goal was generated from (the checkpoint position)
var _goals := {}                       ## step index -> goal pre-resolved at the checkpoint (kept through retries and saved)
var _pending_tp := Vector3.INF
var _begin_tries := 0
var _last_started := -1
var _contracts_were := true
var _flags_held := false
var _hold_t := 0.0
var _gap_t := 0.0
var _attack_t := 0.0
var _outside_t := 0.0
var _nag_t := 0.0
var _escape_t := 0.0
var _hint_off := Vector3.ZERO
var _door: Dictionary = {}
var _phase := 0                        ## enter_interior: 1 = going in, 2 = coming out
var _route := PackedVector3Array()
var _route_len := 0.0
var _esc_s := 0.0
var _ambush: Array = []
var _car_dead := false
var _heat0 := 3.0
var _patrol_want := 0                  ## escape: the patrol vehicles the step keeps after the player (0 = heat only)
var _patrol_t := 0.0
var _markers: Array[Dictionary] = []
var rift_hp := 0.0                     ## rift_hold: integrity of the anomaly
var rift_max := 0.0
var feed_left := 0.0                   ## rift_hold: seconds of feeding banked by verbs
var loot := false                      ## heist: the data is in hand
var convoy: Array[Vehicle] = []        ## convoy_intercept
var stopped: Array[Vehicle] = []       ## convoy_intercept: cars brought to a halt
var _grace_t := 0.0
var _demo_idx := -1
var _demo_prev: Dictionary = {}
var _loot_said := false
var _far_t := 0.0
var _verbs_from: Object
var _qverbs_from: Object
var _missions_from: Object
var _marker_n := 0


func _ready() -> void:
	add_to_group(&"campaign")
	guide = MissionGuide.new(self)
	enabled = not Game.autostart
	for i in 5:
		_markers.append({pos = Vector3.ZERO, color = Color.WHITE, kind = &"", radius = 0.0})
	Game.new_game.connect(_on_new_game)
	Game.next_sector.connect(_on_next_sector)
	Game.respawn.connect(_on_respawn)
	Game.player_died.connect(_on_died)


func _exit_tree() -> void:
	_cleanup(true)
	_release_flags()


# --- chapter data ------------------------------------------------------------------------------------------------------

## Registers chapter dictionaries (index = chapter). Wins over every other source for the indexes given.
func set_chapters(list: Array) -> void:
	chapters.clear()
	for c: Variant in list:
		chapters.append(c if c is Dictionary else {})


## The chapter dictionary for `index`: the registry, else scripts/story/campaign_data.gd (CAMPAIGN), else StoryData.CHAPTERS[index] when it has "steps". {} when none.
func chapter_data(index: int) -> Dictionary:
	if index >= 0 and index < chapters.size() and not chapters[index].is_empty():
		return chapters[index]
	var camp := _campaign_data()
	if index >= 0 and index < camp.size():
		return camp[index]
	if index >= 0 and index < StoryData.CHAPTERS.size():
		var sc: Dictionary = StoryData.CHAPTERS[index]
		if sc.has("steps"):
			return sc
	return {}


func has_steps(index: int) -> bool:
	return not CampaignSteps.normalize_chapter(chapter_data(index), index).is_empty()


## How many chapters the chapter select lists: the story's chapters, or more when a registry / the campaign data brings more.
static func chapter_count() -> int:
	var n := StoryData.FINAL + 1
	var camp := _campaign_data()
	return maxi(n, camp.size())


static func _campaign_data() -> Array:
	if not ResourceLoader.exists(CAMPAIGN_DATA_PATH):
		return []
	var sc := load(CAMPAIGN_DATA_PATH) as GDScript
	if sc == null:
		return []
	var consts := sc.get_script_constant_map()
	var c: Variant = consts.get("CAMPAIGN", [])
	return c as Array if c is Array else []


## Title of a chapter for the chapter select: the story's title, else the registry's, else "CHAPTER n".
static func chapter_title(index: int) -> String:
	if index >= 0 and index < StoryData.CHAPTERS.size():
		return str(StoryData.CHAPTERS[index].get("title", "CHAPTER %d" % (index + 1)))
	return "CHAPTER %d" % (index + 1)


func chapter() -> int:
	return int(Game.story.get("chapter")) if is_instance_valid(Game.story) else 0


# --- public API --------------------------------------------------------------------------------------------------------

func is_running() -> bool:
	return state == &"armed" or state == &"active" or state == &"retry" or state == &"held"


func is_active() -> bool:
	return state == &"active"


func has_marker() -> bool:
	return state == &"active" and visuals != null


## Arms chapter `index` from step `from_step`. `immediate`: no START_DELAY (tests, resume). Returns false for a chapter without usable steps.
func start_chapter(index: int, from_step := 0, immediate := false) -> bool:
	if index != _demo_idx:
		_drop_demo()
	var ch := chapter_data(index)
	var list := CampaignSteps.normalize_chapter(ch, index)
	if list.is_empty():
		return false
	_cleanup(true)
	chapter_index = index
	steps = SetPieces.splice(list, index)
	step_index = 0
	step_index = clampi(from_step, 0, steps.size() - 1)
	_sp_t = 0.0
	fails = 0
	steps_done = step_index
	last_fail = ""
	_goals.clear()
	_kept.clear()
	_pending_tp = Vector3.INF
	_win_pending = false
	_begin_tries = 0
	_origin = _ref_pos_or_spawn()
	_last_started = index
	_hold_flags()
	state = &"armed"
	_arm_t = 0.0 if immediate else START_DELAY
	var prog := Game.progress as Progress
	if prog != null:
		prog.unlock(index)
	_set_checkpoint(step_index, _origin, false)
	chapter_started.emit(index)
	return true


## Starts one of the sequel sandbox chapters (CampaignSteps.DEMO_IDS) as the current story chapter's steps; the registry entry goes away again with the run (abort, another chapter).
func start_demo(id: StringName) -> bool:
	return start_custom(CampaignSteps.demo_chapter(id))


## Runs a chapter dictionary that is not in the story data (sandbox chapters, the heists) as the current story chapter's steps; the registry entry goes away again with the run.
func start_custom(ch: Dictionary) -> bool:
	if ch.is_empty():
		return false
	_drop_demo()
	var idx := maxi(chapter(), 0)
	while chapters.size() <= idx:
		chapters.append({})
	_demo_prev = chapters[idx]
	_demo_idx = idx
	chapters[idx] = ch
	if start_chapter(idx, 0, true):
		return true
	_drop_demo()
	return false


func _drop_demo() -> void:
	if _demo_idx >= 0 and _demo_idx < chapters.size():
		chapters[_demo_idx] = _demo_prev
	_demo_idx = -1
	_demo_prev = {}


## Resumes from a saved checkpoint {chapter, step, pos, tp, goal?} (Progress.continue_game): the player goes back to it and the step begins at once. False when the data does not fit.
func resume(cp: Dictionary) -> bool:
	var ch := int(cp.get("chapter", -1))
	if ch < 0 or not has_steps(ch):
		return false
	var si := int(cp.get("step", 0))
	if not start_chapter(ch, si, true):
		return false
	var at: Variant = cp.get("pos", null)
	if at is Vector3 and (at as Vector3).is_finite():
		_origin = at
		if bool(cp.get("tp", false)):
			_teleport(at)
	var g: Variant = cp.get("goal", null)
	if g is Vector3 and (g as Vector3).is_finite():
		_goals[step_index] = g
	checkpoint = cp.duplicate()
	var prog := Game.progress as Progress
	if prog != null:
		prog.set_checkpoint(checkpoint)                      # start_chapter() above stored a fresh checkpoint (spawn position, regenerated goal): put the saved one back (and in the file)
	return true


## The goal of step `index` once it is known (resolved at the checkpoint before it, or when it began), Vector3.INF before that or for steps without a goal.
func goal_for(index: int) -> Vector3:
	return _goals.get(index, Vector3.INF)


## Retry the running step from its checkpoint now (the player moves back to it).
func retry() -> bool:
	if state != &"active" and state != &"retry" and state != &"held":
		return false
	_restart_step(true)
	return true


## Finishes the running step as if its objective was met (the TEST menu; pays the step's reward, saves its checkpoint). False when no step is active.
func skip_step() -> bool:
	if state != &"active":
		return false
	_complete_step(_ref_pos_or_spawn())
	return true


## The game's own way out of a stuck step (MissionGuide.recover): a goal nobody reached (reach, hack, defend, rift) moves to a street point beside the player once, an unreachable kill
## target is brought to the street beside the player, and a step that is still stuck (or of a kind with nothing to move) is completed like SKIP STEP. False when no step is active.
func recover_step() -> bool:
	if state != &"active":
		return false
	if not _reanchored and kind in [&"reach", &"hack", &"defend", &"rift_hold", &"kill_target"]:
		_reanchored = true
		var p := _ref_pos_or_spawn()
		var np := road_point(p, 14.0, 30.0)
		if kind == &"kill_target":
			if is_instance_valid(target):
				target.global_position = Vector3(np.x, _ground(np.x, np.z), np.z)
				return true
		else:
			pos = np
			_goals[step_index] = np
			visuals.show_marker(0, pos, float(step["radius"]), _step_color(), -1.0, true)
			if kind == &"reach":
				_route = CampaignSteps.street_route(p, pos)
				visuals.set_route(_route)
			return true
	_complete_step(_ref_pos_or_spawn())
	return true


## Stops the chapter without finishing it (the title screen, a new run).
func abort() -> void:
	_cleanup(true)
	_drop_demo()
	_release_flags()
	_win_pending = false
	state = &"idle"
	step = {}
	kind = &""
	progress = -1.0


## The saved-and-restored position data of the last checkpoint ({} before any).
func get_checkpoint() -> Dictionary:
	return checkpoint


## Advance by `delta` seconds (the physics process calls it while playing; tests call it directly).
func tick(delta: float) -> void:
	_clock += delta
	if guide != null and guide_enabled:
		guide.tick(delta)
	match state:
		&"idle":
			if enabled:
				_poll_start()
		&"armed":
			if _gate_open():
				if _inside_blocks_step():
					_arm_t = maxf(_arm_t, WAIT_OUTSIDE)           # the street steps wait for the player to come out of the building
				else:
					_arm_t -= delta
					if _arm_t <= 0.0:
						_begin_step()
		&"active":
			_tick_active(delta)
		&"done":
			if _win_pending and Game.is_playing():
				_win_pending = false
				Game.win()
		&"retry":
			retry_left -= delta
			if retry_left <= 0.0:
				_restart_step(true)


func _physics_process(delta: float) -> void:
	if not Game.is_playing():
		return
	tick(delta)


func _process(delta: float) -> void:
	if visuals != null and (not sp_zones.is_empty() or visuals.zones_visible() > 0):
		visuals.show_zones(sp_zones, float(step.get("hazard", {}).get("radius", 5.0)) if step is Dictionary else 5.0, sp_hazard_state == &"hit")
	if visuals != null and has_marker():
		visuals.animate(delta)


# --- HUD / minimap interface (the same shape as Contracts) -------------------------------------------------------------------

## "2/3  HACK THE LEDGER NODE  62%  1:20" and the like: the HUD's priority line ("" when no step runs).
func hud_line() -> String:
	if state == &"retry":
		return "MISSION FAILED  %s  RETRY IN %d" % [last_fail, ceili(retry_left)]
	if state != &"active" or step.is_empty():
		return ""
	var head := "%d/%d  %s" % [step_index + 1, steps.size(), str(step["text"]).to_upper()]
	var clock := "  " + _clock_text(time_left) if time_total > 0.0 else ""
	match kind:
		&"reach", &"kill_target":
			return "%s%s  %d M" % [head, clock, roundi(distance_to_goal())]
		&"chase":
			if _take_the_car():
				return "%d/%d  TAKE THE CAR  %d M" % [step_index + 1, steps.size(), roundi(_hdist(_ref_pos(), _chase_car.global_position))]
			return "%s%s  %d M" % [head, clock, roundi(distance_to_goal())]
		&"enter_interior":
			if _phase == 2:
				return "%d/%d  LEAVE THE BUILDING" % [step_index + 1, steps.size()]
			return "%s%s  %d M" % [head, clock, roundi(distance_to_goal())]
		&"escort":
			return "%s%s  %d M  ESCORT %d%%" % [head, clock, roundi(distance_to_goal()), roundi(100.0 * escort_hp / maxf(escort_max, 1.0))]
		&"defend":
			return "%s  %d%%%s%s" % [head, roundi(maxf(progress, 0.0) * 100.0), clock, "" if inside else "  RETURN TO THE ZONE"]
		&"hack":
			return "%s  %d%%%s%s" % [head, roundi(maxf(progress, 0.0) * 100.0), clock, "" if inside else "  RETURN TO THE RING"]
		&"escape":
			return "%s%s  HEAT %.1f  %d M%s" % [head, clock, Game.heat, roundi(_origin_dist()), "  PATROL" if _patrol_want > 0 and _patrols_chasing() > 0 else ""]
		&"survive":
			return "%s  %s" % [head, _clock_text(maxf(float(step["hold"]) - _hold_t, 0.0))]
		&"rift_hold":
			var tail := "  USE A VERB" if inside and feed_left <= 0.0 else ("" if inside else "  RETURN TO THE RIFT")
			return "%s  %d%%  RIFT %d%%%s%s" % [head, roundi(maxf(progress, 0.0) * 100.0), roundi(100.0 * rift_hp / maxf(rift_max, 1.0)), clock, tail]
		&"heist":
			match _phase:
				1: return "%s%s  %d M" % [head, clock, roundi(distance_to_goal())]
				2: return "%d/%d  %s" % [step_index + 1, steps.size(), "GET OUT WITH THE DATA" if loot else "STEAL THE DATA"]
			return "%d/%d  GETAWAY%s  HEAT %.1f  %d M%s" % [step_index + 1, steps.size(), clock, Game.heat, roundi(_origin_dist()), "  PATROL" if _patrol_want > 0 and _patrols_chasing() > 0 else ""]
		&"convoy_intercept":
			if _take_the_car():
				return "%d/%d  TAKE THE CAR  %d M" % [step_index + 1, steps.size(), roundi(_hdist(_ref_pos(), _chase_car.global_position))]
			return "%s  STOPPED %d/%d%s" % [head, _stopped_count(), convoy.size(), clock]
	return head


## Horizontal metres from the player to the waypoint the HUD points at.
func distance_to_goal() -> float:
	var p := _ref_pos()
	var w := waypoint()
	if not p.is_finite() or not w.has("pos"):
		return 0.0
	var g: Vector3 = w["pos"]
	return Vector2(g.x - p.x, g.z - p.z).length()


## 0..1 for the HUD's thin bar, -1 without one.
func progress_fraction() -> float:
	return progress if state == &"active" else -1.0


## {name, frac} of a kill_target's health for the HUD's boss bar, {} otherwise.
func boss() -> Dictionary:
	if state == &"active" and kind == &"kill_target" and is_instance_valid(target):
		var d := target as Drone
		if d != null and not d.dead:
			var b := {"name": str(step.get("name", "VAEL TARGET")), "frac": clampf(d.hp / maxf(d.max_hp, 1.0), 0.0, 1.0)}
			if d is VerbBoss:
				b["hint"] = (d as VerbBoss).hint()
			return b
	return {}


## The one world point the HUD's edge waypoint and the distance line point at: {pos, color} or {} when there is none (hidden inside an interior).
func waypoint() -> Dictionary:
	if state != &"active" or _inside_hides():
		return {}
	var c := _step_color()
	if _take_the_car():
		return {"pos": _chase_car.global_position, "color": ContractTypes.AMBER}
	match kind:
		&"kill_target", &"chase":
			var t: Node3D = target if kind == &"kill_target" else car
			if is_instance_valid(t):
				return {"pos": t.global_position, "color": c}
		&"escort":
			var p := _ref_pos()
			if is_instance_valid(escortee) and p.is_finite() and Vector2(escortee.global_position.x - p.x, escortee.global_position.z - p.z).length() > float(step["leash"]) * 0.6:
				return {"pos": escortee.global_position, "color": ContractTypes.CYAN}      # fell behind: the asset first, then the destination
			return {"pos": pos, "color": ContractTypes.AMBER}
		&"escape", &"survive":
			return {}                                    # nothing to walk to: the minimap ring shows how far to get away
		&"heist":
			if _phase == 3:
				return {}
		&"convoy_intercept":
			var near := _nearest_moving_car()
			if near != null:
				return {"pos": near.global_position, "color": c}
			return {}
	return {"pos": pos, "color": c}


## Minimap markers (reused entries): [{pos, color, kind (&"target" &"zone" &"dest" &"area"), radius}]. Call marker_count() for the valid ones; never keep the array.
func markers() -> Array[Dictionary]:
	_marker_n = 0
	if state != &"active" or _inside_hides():
		return _markers
	match kind:
		&"reach":
			_add_marker(pos, _step_color(), &"dest", 0.0)
		&"enter_interior":
			_add_marker(pos, ContractTypes.CYAN, &"dest", 0.0)
		&"hack":
			_add_marker(pos, ContractTypes.CYAN, &"zone", float(step["radius"]))
		&"defend":
			_add_marker(pos, ContractTypes.CYAN, &"zone", float(step["radius"]))
		&"kill_target":
			if is_instance_valid(target):
				var tp := target.global_position
				var p := _ref_pos()
				if p.is_finite() and Vector2(tp.x - p.x, tp.z - p.z).length() > TARGET_HINT_FAR:
					_add_marker(tp + _hint_off, ContractTypes.RED, &"area", TARGET_HINT_R)
				else:
					_add_marker(tp, ContractTypes.RED, &"target", 0.0)
		&"chase":
			if is_instance_valid(car):
				_add_marker(car.global_position, ContractTypes.AMBER, &"target", 0.0)
		&"escort":
			if is_instance_valid(escortee):
				_add_marker(escortee.global_position, ContractTypes.CYAN, &"target", 0.0)
			_add_marker(pos, ContractTypes.AMBER, &"dest", 0.0)
		&"escape":
			_escape_markers()
		&"rift_hold":
			_add_marker(pos, ContractTypes.CYAN, &"zone", float(step["radius"]))
		&"heist":
			if _phase == 3:
				_escape_markers()
			else:
				_add_marker(pos, ContractTypes.AMBER, &"dest", 0.0)
		&"convoy_intercept":
			for c: Vehicle in convoy:
				if is_instance_valid(c) and not stopped.has(c) and not c.dead:
					_add_marker(c.global_position, ContractTypes.RED, &"target", 0.0)
	for z in sp_zones:
		_add_marker(z, ContractTypes.RED, &"area", float(step.get("hazard", {}).get("radius", 5.0)))
	return _markers


func marker_count() -> int:
	return _marker_n


func _escape_markers() -> void:
	if _origin_dist() < float(step["dist"]):
		_add_marker(_origin, ContractTypes.RED, &"area", float(step["dist"]))
	if _patrol_want > 0:
		for v: Vehicle in _chasing_patrols():
			_add_marker(v.global_position, ContractTypes.RED, &"target", 0.0)


## True while the player is inside a building and the step's hints would sit in the interior's own coordinates.
func _inside_hides() -> bool:
	return InteriorGameplay.active and not (kind == &"enter_interior" and _phase == 2)


func _add_marker(p: Vector3, c: Color, k: StringName, r: float) -> void:
	if _marker_n >= _markers.size():
		return
	var m := _markers[_marker_n]
	m.pos = p
	m.color = c
	m.kind = k
	m.radius = r
	_marker_n += 1


## The street route of an escort or a reach step (the minimap draws it as one line); empty otherwise.
func route_points() -> PackedVector3Array:
	if state == &"active" and (kind == &"escort" or kind == &"reach") and not InteriorGameplay.active:
		return _route
	return PackedVector3Array()


# --- lifecycle signals --------------------------------------------------------------------------------------------------------

func _on_new_game() -> void:
	abort()
	_last_started = -1
	checkpoint = {}


func _on_next_sector() -> void:
	abort()
	checkpoint = {}


func _on_died() -> void:
	if state == &"active":
		_keep_progress()
	if state == &"active" or state == &"retry" or state == &"armed":
		_cleanup(true)
		state = &"held"
		_arm_t = 0.0


func _on_respawn() -> void:
	if state == &"held":
		_restart_step(true)


## Idle: arm the story chapter when it has steps and nothing covers the screen.
func _poll_start() -> void:
	if not Game.is_playing() or not is_instance_valid(Game.player) or not _gate_open():
		return
	var ch := chapter()
	if ch == _last_started or not has_steps(ch):
		return
	start_chapter(ch)


## False while a card, the tutorial or a cutscene owns the screen.
func _gate_open() -> bool:
	if not Game.is_playing():
		return false
	var st: Object = Game.story if is_instance_valid(Game.story) else null
	if st != null:
		if st.has_method(&"cards_active") and bool(st.call(&"cards_active")):
			return false
		var tut: Variant = st.get("tutorial")
		if tut != null and (tut as Object).get("active") == true:
			return false
	return true


## True while the player is inside a building (or in the fade through its door) and the armed step is not the one that wants the door: it would be built in the interior's
## coordinates (an escort asset, a target, waves), which sit far from the street.
func _inside_blocks_step() -> bool:
	if step_index >= steps.size() or steps[step_index]["kind"] == &"enter_interior" or steps[step_index]["kind"] == &"heist":
		return false
	var ig := InteriorGameplay.instance
	return InteriorGameplay.active or (ig != null and is_instance_valid(ig) and ig.busy)


# --- step flow ---------------------------------------------------------------------------------------------------------------

func _begin_step() -> void:
	if step_index >= steps.size():
		_complete_chapter()
		return
	step = steps[step_index]
	kind = step["kind"]
	_clean_runtime()
	_reanchored = false
	var ch_id := str(chapter_data(chapter_index).get("id", chapter_index))
	rng.seed = hash("%s|%d|%d" % [ch_id, step_index, _begin_tries])
	if _pending_tp.is_finite():
		_teleport(_pending_tp)
		_pending_tp = Vector3.INF
	pos = _goals[step_index] if _goals.has(step_index) else _resolve_goal(step, _origin, step_index)
	_goals[step_index] = pos
	_ensure_visuals()
	visuals.hide_all()
	var ok := false
	match kind:
		&"reach": ok = _begin_reach()
		&"enter_interior": ok = _begin_interior()
		&"escort": ok = _begin_escort()
		&"defend": ok = _begin_defend()
		&"hack": ok = _begin_hack()
		&"kill_target": ok = _begin_kill()
		&"chase": ok = _begin_chase()
		&"escape": ok = _begin_escape()
		&"survive": ok = _begin_survive()
		&"rift_hold": ok = _begin_rift()
		&"heist": ok = _begin_heist()
		&"convoy_intercept": ok = _begin_convoy()
	if not ok:
		_cleanup(true)
		_begin_tries += 1
		if _begin_tries >= BEGIN_TRIES:
			_begin_tries = 0
			_fail("AREA CROWDED")
		else:
			_arm_t = 1.0
		return
	_begin_tries = 0
	time_total = float(step["time"])
	if time_total > 0.0 and fails > 0 and (kind == &"chase" or kind == &"convoy_intercept"):
		time_total *= 1.0 + 0.25 * float(mini(fails, 3))               # every failed run gives the next one more time
	time_left = time_total
	progress = 0.0 if progress < 0.0 else progress
	var heat := float(step["heat"])
	if heat > 0.0 and kind != &"escape" and kind != &"heist":
		Game.add_heat(heat)
	state = &"active"
	_begin_set_piece_phase()
	step_started.emit(chapter_index, step_index, kind)
	Sfx.play(&"ui_contract_accept")
	Game.say(str(step["text"]).to_upper(), 2.5)
	_radio("start")


func _complete_step(cp_pos: Vector3) -> void:
	var idx := step_index
	var k := kind
	var st := step
	_kept.erase(idx)
	_end_set_piece_phase(st)
	_cleanup(true)
	steps_done += 1
	var rew: Variant = st.get("reward", {})
	var prog := Game.progress as Progress
	if rew is Dictionary and prog != null:
		if int((rew as Dictionary).get("credits", 0)) != 0:
			prog.add_credits(int((rew as Dictionary)["credits"]))
		if int((rew as Dictionary).get("rep", 0)) != 0:
			prog.add_reputation(int((rew as Dictionary)["rep"]))
	if prog != null:
		prog.bonus_score(100)
	else:
		Game.add_score(100)
	Sfx.play(&"ui_contract_complete")
	Game.say("OBJECTIVE COMPLETE", 1.8)
	_radio("done")
	step_completed.emit(chapter_index, idx, k)
	step_index += 1
	_begin_tries = 0
	if bool(st.get("checkpoint", true)) and step_index < steps.size():
		_set_checkpoint(step_index, cp_pos, true)
	elif step_index < steps.size():
		_origin = cp_pos                                  # no checkpoint here, but the next goal is still generated from where the player is now
		var g := _resolve_goal(steps[step_index], cp_pos, step_index)
		if g.is_finite():
			_goals[step_index] = g
	if step_index >= steps.size():
		_complete_chapter()
	else:
		state = &"armed"
		_arm_t = STEP_GAP


func _complete_chapter() -> void:
	var done := chapter_index
	var ch := chapter_data(done)
	state = &"done"
	step = {}
	kind = &"none"
	progress = -1.0
	_release_flags()
	checkpoint = {}
	var prog := Game.progress as Progress
	if prog != null:
		prog.clear_checkpoint()
	chapter_completed.emit(done)
	if bool(ch.get("clears_sector", true)):
		if Game.is_playing():
			Game.win()
		else:
			_win_pending = true


func _keep_progress() -> void:
	if kind in [&"hack", &"defend", &"rift_hold", &"survive"] and progress > 0.05:
		_kept[step_index] = clampf(progress * 0.5, 0.0, 0.6)


func _fail(reason: String) -> void:
	_keep_progress()
	if step.has("set_piece"):
		sp_zones.clear()
		sp_hazard_state = &"idle"
		if bool(step.get("optional", false)) and fails + 1 >= SetPieces.SKIP_AFTER_FAILS:
			fails += 1
			_cleanup(true)
			Game.say("SET PIECE DROPPED", 2.5)
			_skip_to(SetPieces.end_index(steps, step_index))
			return
	var k := kind
	var idx := step_index
	last_fail = reason
	fails += 1
	_cleanup(true)
	Game.say("MISSION FAILED  %s" % reason, 3.0)
	Sfx.play(&"hurt")
	Sfx.play(&"ui_contract_fail")
	_radio("fail")
	state = &"retry"
	retry_left = RETRY_PAUSE
	step_failed.emit(chapter_index, idx, k, reason)


## Begin the same step again from its checkpoint: foes and visuals go, the player is moved back to the checkpoint (not out of a vehicle or an interior), the step re-arms.
func _restart_step(teleport: bool) -> void:
	_cleanup(true)
	_begin_tries = 0
	var pl := Game.player as Player
	if is_instance_valid(pl) and not pl.is_dead():
		pl.hp = maxf(pl.hp, pl.max_hp * Difficulty.mult("cp"))
	var cp_pos: Variant = checkpoint.get("pos", null)
	var spot := _retry_spot()
	if teleport and spot.is_finite():
		_pending_tp = spot                                # a fight step restarts at the fight, not a block away at the old checkpoint
	elif teleport and bool(checkpoint.get("tp", false)) and cp_pos is Vector3 and (cp_pos as Vector3).is_finite():
		_pending_tp = cp_pos
	state = &"armed"
	_arm_t = 0.6
	progress = -1.0


## Where a retry of the running step starts the player (owner round 3: "retry right at the step"): hack, defend, rift hold and kill steps restart on the street RETRY_DIST metres from
## the step's goal, on the side of the old checkpoint. Everything else (a walk, a chase, an escort, an escape) restarts at the checkpoint. Vector3.INF = use the checkpoint.
func _retry_spot() -> Vector3:
	if not (kind in [&"hack", &"defend", &"rift_hold", &"kill_target"]) or InteriorGameplay.active:
		return Vector3.INF
	var g: Variant = _goals.get(step_index, null)
	if not (g is Vector3) or not (g as Vector3).is_finite():
		return Vector3.INF
	var goal := g as Vector3
	var from := _origin if _origin.is_finite() else _ref_pos_or_spawn()
	var dir := Vector3(from.x - goal.x, 0.0, from.z - goal.z)
	dir = dir.normalized() if dir.length() > 1.0 else Vector3.RIGHT
	var q := PlayerUtil.nearest_street(goal + dir * RETRY_DIST)
	return Vector3(q.x, 0.0, q.z)


func _teleport(at: Vector3) -> void:
	var p := Game.player as Player
	if p == null or not is_instance_valid(p) or p.vehicle != null or InteriorGameplay.active:
		return
	p.teleport_to(at)


func _set_checkpoint(next_index: int, at: Vector3, tp: bool) -> void:
	var cp := {"chapter": chapter_index, "step": next_index, "pos": at, "tp": tp}
	_origin = at
	if next_index < steps.size():
		var g := _resolve_goal(steps[next_index], at, next_index)
		if g.is_finite():
			_goals[next_index] = g
			cp["goal"] = g
	checkpoint = cp
	var prog := Game.progress as Progress
	if prog != null:
		prog.set_checkpoint(cp)
	checkpoint_reached.emit(cp)


func _hold_flags() -> void:
	if _flags_held:
		return
	_flags_held = true
	var k: Variant = _contracts()
	if k != null:
		_contracts_were = bool(k.get("enabled"))
		k.set("enabled", false)
	var m := Game.missions
	if is_instance_valid(m) and m.get("win_on_cores") != null:
		m.set("win_on_cores", false)


func _release_flags() -> void:
	if not _flags_held:
		return
	_flags_held = false
	var k: Variant = _contracts()
	if k != null:
		k.set("enabled", _contracts_were)
	var m := Game.missions
	if is_instance_valid(m) and m.get("win_on_cores") != null:
		m.set("win_on_cores", true)


func _contracts() -> Object:
	var m := Game.missions
	if not is_instance_valid(m):
		return null
	return m.get("contracts") as Object


# --- goals -------------------------------------------------------------------------------------------------------------------

## The step's goal point: its own `pos`, the door of an interior step, or a street point `dist` metres from `origin` (seeded by chapter and step, so a retry or a resume lands on the
## same spot). Vector3.INF for steps without a goal (survive, escape).
func _resolve_goal(st: Dictionary, origin: Vector3, idx: int) -> Vector3:
	var k: StringName = st["kind"]
	if k == &"survive" or k == &"escape":
		return Vector3.INF
	var p: Vector3 = st["pos"]
	if p.is_finite():
		return p
	if k == &"enter_interior" or k == &"heist":
		var d := _find_door(st, origin)
		if not d.is_empty():
			return d["pos"]
	var dd: Array = CampaignSteps.KIND_DATA[k]["dist"]
	var ch_id := str(chapter_data(chapter_index).get("id", chapter_index))
	rng.seed = hash("%s|%d|goal" % [ch_id, idx])
	return road_point(origin, float(dd[0]), float(dd[1]), true)


## A street position between rmin and rmax of `center`: with `junction` a junction of the city picked with the seeded rng (the same answer for the same seed, which goals need to survive a
## save and a load), else the world's road query; a junction list of a test world or a point on a circle when the city has neither.
func road_point(center: Vector3, rmin: float, rmax: float, junction := false) -> Vector3:
	var w := Game.world
	if is_instance_valid(w):
		if junction and "intersections" in w:
			var near: Array[Vector3] = []
			for q: Vector3 in w.intersections:
				var d := Vector2(q.x - center.x, q.z - center.z).length()
				if d >= rmin and d <= rmax:
					near.append(q)
			if not near.is_empty():
				var q1 := near[rng.randi() % near.size()]
				return Vector3(q1.x, 0.0, q1.z)
		if w.has_method(&"road_point_near"):
			var p: Vector3 = w.call(&"road_point_near", center, rmin, rmax)
			if p.is_finite():
				return Vector3(p.x, 0.0, p.z)
		if "intersections" in w:
			var list: Array[Vector3] = []
			for q: Vector3 in w.intersections:
				var d := Vector2(q.x - center.x, q.z - center.z).length()
				if d >= rmin and d <= rmax:
					list.append(q)
			if not list.is_empty():
				var q2 := list[rng.randi() % list.size()]
				return Vector3(q2.x, 0.0, q2.z)
	var a := rng.randf() * TAU
	return Vector3(center.x + cos(a) * (rmin + rmax) * 0.5, 0.0, center.z + sin(a) * (rmin + rmax) * 0.5)


func _find_door(st: Dictionary, origin: Vector3) -> Dictionary:
	var ig := InteriorGameplay.instance
	if ig == null or not is_instance_valid(ig):
		return {}
	var id := int(st.get("door", -1))
	if id >= 0:
		var d := ig.door_by_id(id)
		if not d.is_empty():
			return d
	var type := StringName(str(st.get("interior", "")))
	if type != &"":
		var l := ig.doors_of(type, origin)
		if not l.is_empty():
			return l[0]
	var best := {}
	var bd := INF
	for d in ig.doors():
		var dp: Vector3 = d["pos"]
		var dist := Vector2(dp.x - origin.x, dp.z - origin.z).length()
		if dist >= 40.0 and dist < bd:
			bd = dist
			best = d
	return best


func _ref_pos() -> Vector3:
	var p := Game.player
	if not is_instance_valid(p):
		return Vector3.INF
	var veh := p.get(&"vehicle") as Node3D
	if veh != null and is_instance_valid(veh):
		return veh.global_position
	return p.global_position


func _ref_pos_or_spawn() -> Vector3:
	var p := _ref_pos()
	return p if p.is_finite() else Game.SPAWN


func _hdist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _origin_dist() -> float:
	var p := _ref_pos()
	return _hdist(p, _origin) if p.is_finite() else 0.0


func _step_color() -> Color:
	match str(CampaignSteps.KIND_DATA.get(kind, {}).get("color", "cyan")):
		"red": return ContractTypes.RED
		"amber": return ContractTypes.AMBER
	return ContractTypes.CYAN


func _ensure_visuals() -> void:
	if visuals == null:
		visuals = ContractVisuals.new()
		visuals.name = "CampaignVisuals"
		add_child(visuals)


func _ground(x: float, z: float) -> float:
	var w := Game.world
	if is_instance_valid(w) and w.has_method(&"ground_height"):
		return float(w.call(&"ground_height", x, z, 4.0))
	return 0.0


# --- spawning helpers ------------------------------------------------------------------------------------------------------

func _spawn(type: StringName, at: Vector3, aware := false) -> Drone:
	var em := Game.enemies as EnemyManager
	if em == null:
		return null
	var d := em.spawn(type, at, aware)
	if d == null and _make_room(em):                      # the street's own patrols filled the tier's enemy cap: the step has priority (found by the mission audit: AREA CROWDED forever)
		d = em.spawn(type, at, aware)
	if d != null:
		foes.append(d)
	return d


## Sends the enemy farthest from the player that does not belong to the step back to the pool (EnemyManager.make_room), so a step can always spawn its target and waves.
func _make_room(em: EnemyManager) -> bool:
	var keep: Array = foes.duplicate()
	if is_instance_valid(target):
		keep.append(target)
	return em.make_room(keep, _ref_pos())


func foes_alive() -> int:
	var n := 0
	for f: Variant in foes:
		var d := f as Drone
		if d != null and is_instance_valid(d) and d.active and not d.dead and not d.remove:
			n += 1
	return n


func _prune_foes() -> void:
	var i := foes.size() - 1
	while i >= 0:
		var d := foes[i] as Drone
		if d == null or not is_instance_valid(d) or not d.active:
			foes.remove_at(i)
		i -= 1


## `n` enemies of the step's `types` (default: a sector mix by wave) around `center`, `rmin`..`rmax` away, all aware.
func _spawn_wave(center: Vector3, rmin: float, rmax: float, n: int, w: int, types: Array) -> void:
	var ch := chapter_index
	for i in n:
		if foes_alive() >= MAX_ALIVE_WAVE:
			return
		var type := &"sentinel"
		if not types.is_empty():
			type = StringName(str(types[i % types.size()]))
		else:
			var roll := rng.randi() % 4
			if w == 0:
				type = &"operative" if roll == 0 else &"sentinel"
			else:
				type = &"operative" if roll < 2 else (&"striker" if roll == 2 else &"sentinel")
			if ch >= 2 and w >= 2 and i == n - 1:
				type = &"heavy"
		_spawn(type, road_point(center, rmin, rmax), true)


func _wave_size(w: int) -> int:
	var n := int(step.get("count", 0))
	return n if n > 0 else ContractTypes.count(&"survive", chapter_index, w)


# --- starting each kind ------------------------------------------------------------------------------------------------------

func _begin_reach() -> bool:
	var p := _ref_pos_or_spawn()
	visuals.show_marker(0, pos, float(step["radius"]), _step_color(), -1.0, true)
	_route = CampaignSteps.street_route(p, pos)
	visuals.set_route(_route)
	return true


func _begin_interior() -> bool:
	_phase = 1
	_door = _find_door(step, _origin)
	if not _door.is_empty():
		pos = _door["pos"]
	visuals.show_marker(0, pos, float(step["radius"]), ContractTypes.CYAN, -1.0, true)
	return true


func _begin_escort() -> bool:
	var from: Vector3 = step["from"]
	if not from.is_finite():
		from = _ref_pos_or_spawn()
		from = Vector3(from.x + 3.0, 0.0, from.z)
	from.y = 0.0
	var dest := Vector3(pos.x, 0.0, pos.z)
	_route = CampaignSteps.street_route(from, dest)
	_route_len = CampaignSteps.route_length(_route)
	_esc_s = 0.0
	escort_max = float(step["hp"])
	escort_hp = escort_max
	if escortee == null:
		escortee = InteriorCivilian.new()
		escortee.name = "Escortee"
		add_child(escortee)
		escortee.setup(4242)
	escortee.activate(&"vendor", Vector3(from.x, _ground(from.x, from.z), from.z), 0.0, ContractTypes.CYAN)
	_ambush.clear()
	for a: Variant in step.get("ambush", []):
		if a is Dictionary:
			_ambush.append({"at": clampf(float((a as Dictionary).get("at", 0.5)), 0.05, 0.95), "n": int((a as Dictionary).get("n", -1)),
				"types": (a as Dictionary).get("types", []), "done": false})
	_nag_t = 0.0
	_outside_t = 0.0
	visuals.show_marker(0, escortee.global_position, 1.8, ContractTypes.CYAN, -1.0, false)
	visuals.show_marker(1, dest, float(step["radius"]), ContractTypes.AMBER, -1.0, true)
	visuals.set_route(_route)
	return true


func _begin_defend() -> bool:
	_hold_t = float(step["hold"]) * float(_kept.get(step_index, 0.0))
	wave = 0
	_gap_t = 2.0
	_outside_t = 0.0
	inside = true
	visuals.show_marker(0, pos, float(step["radius"]), ContractTypes.CYAN, 0.0, true)
	return true


func _begin_hack() -> bool:
	_hold_t = 0.0
	progress = float(_kept.get(step_index, 0.0))
	_attack_t = 8.0
	_nag_t = 0.0
	inside = true
	visuals.show_marker(0, pos, float(step["radius"]), ContractTypes.CYAN, 0.0, true)
	return true


func _begin_kill() -> bool:
	var type: StringName = step["enemy"]
	if type == &"":
		type = EnemyTypes.specialist_for(chapter_index, 2.0, 0.0, rng.randf())
		if type == &"operative":
			type = &"sentinel" if chapter_index < 1 else &"flanker"
	var t := _spawn(type, pos, false)
	if t == null:
		return false
	var hp := t.max_hp * float(step["hp_mult"])
	t.max_hp = hp
	t.hp = hp
	if t.model != null and type != &"overseer" and not t is VerbBoss:
		t.model.scale = t.model.scale * 1.18
	target = t
	var guards := int(step["guards"])
	if guards < 0:
		guards = ContractTypes.count(&"officer", chapter_index)
	for i in guards:
		var a := TAU * (float(i) + rng.randf()) / float(maxi(guards, 1))
		_spawn(&"operative" if i % 2 == 0 or chapter_index < 2 else &"sentinel", pos + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(5.0, 9.0), false)
	var ang := rng.randf() * TAU
	_hint_off = Vector3(cos(ang), 0.0, sin(ang)) * rng.randf_range(10.0, 18.0)
	Game.add_heat(1.0 if (type == &"overseer" or t is VerbBoss) else 0.5)
	visuals.show_marker(0, pos, 2.0, ContractTypes.RED, -1.0, true)
	return true


func _begin_chase() -> bool:
	var vm := Game.vehicles
	if not is_instance_valid(vm) or not vm.has_method(&"spawn_traffic"):
		return false
	var at := pos
	var axis := rng.randi() % 2
	var dir := 1 if rng.randf() < 0.5 else -1
	var road_i: int = VehicleSpecs.road_index(at.z if axis == 0 else at.x)
	var along := at.x if axis == 0 else at.z
	var c: Vehicle = vm.call(&"spawn_traffic", &"sedan", axis, road_i, dir, along)
	if c == null:
		_free_a_car(vm)
		c = vm.call(&"spawn_traffic", &"sedan", axis, road_i, dir, along)
	if c == null:
		return false
	c.max_hp = float(step["hp"]) * maxf(1.0 - 0.2 * float(mini(fails, 3)), 0.4)       # every failed run makes the target a little easier to wreck
	c.hp = c.max_hp
	var cruise := float(step["cruise"])
	c.ai_cruise = cruise if cruise > 0.0 else minf(15.0 + 1.2 * float(chapter_index), 24.0)
	c.set_meta(&"hold", true)
	_car_dead = false
	if not c.exploded.is_connected(_on_car_exploded):
		c.exploded.connect(_on_car_exploded)
	car = c
	pos = c.global_position
	_escape_t = 0.0
	_chase_t = 0.0
	_ensure_chase_car(vm)
	visuals.show_marker(0, pos, 3.0, ContractTypes.AMBER, -1.0, true)
	Game.add_heat(0.1)
	return true


## "Take a car and cut it off": when the player is on foot and no car is at hand, a fast one is left beside them, nose toward the target, and the HUD says TAKE THE CAR.
func _ensure_chase_car(vm: Node) -> void:
	_chase_car = null
	var p := _ref_pos()
	if not p.is_finite() or not vm.has_method(&"spawn_parked"):
		return
	var pl := Game.player as Player
	if is_instance_valid(pl) and pl.vehicle != null:
		return
	var list: Array = vm.get("list")
	var nearest: Vehicle = null
	var nd := CHASE_CAR_NEAR
	for v: Vehicle in list:
		if v != car and not convoy.has(v) and not v.dead and v.active and not v.wreck and _hdist(v.global_position, p) < nd:
			nd = _hdist(v.global_position, p)
			nearest = v
	if nearest != null:
		_chase_car = nearest                                  # a car is at hand: the HUD points at it (TAKE THE CAR)
		return
	var spot := _chase_car_spot(p)
	var c: Vehicle = vm.call(&"spawn_parked", &"sport", spot["pos"], spot["heading"])
	if c == null:
		_free_a_car(vm)
		c = vm.call(&"spawn_parked", &"sport", spot["pos"], spot["heading"])
	_chase_car = c


## Where the chase car stands: in the right-hand lane of the street the player is on, nose toward the target (a car left across a kerb or a wall could not drive away).
func _chase_car_spot(p: Vector3) -> Dictionary:
	var ox := CityLayout.road_offset(p.x)
	var oz := CityLayout.road_offset(p.z)
	var on_z_road := absf(ox) <= absf(oz)                    # the street runs along z: x is the road's coordinate
	var axis := 1 if on_z_road else 0
	var toward := (pos.z - p.z) if on_z_road else (pos.x - p.x)
	var dir := 1 if toward >= 0.0 else -1
	var line := VehicleSpecs.road_center(VehicleSpecs.road_index(p.x if on_z_road else p.z)) + VehicleSpecs.lane_offset(axis, dir, Game.LANE)
	var along := p.z if on_z_road else p.x
	var at := Vector3(line, 0.0, along + float(dir) * 4.0) if on_z_road else Vector3(along + float(dir) * 4.0, 0.0, line)
	return {"pos": at, "heading": VehicleSpecs.heading_for(axis, dir)}


func _take_the_car() -> bool:
	var pl := Game.player as Player
	return state == &"active" and (kind == &"chase" or kind == &"convoy_intercept") and _chase_t < TAKE_CAR_HINT and stopped.is_empty() and _chase_car != null and is_instance_valid(_chase_car) and not _chase_car.dead and is_instance_valid(pl) and pl.vehicle == null


func _free_a_car(vm: Node) -> void:
	var list: Array = vm.get("list")
	var p := _ref_pos()
	var far: Vehicle = null
	var far_d := -1.0
	for v: Vehicle in list:
		if v == vm.get("starter") or v.driver_is_player or v.has_meta(&"hold"):
			continue
		var d := v.global_position.distance_to(p)
		if d > far_d:
			far_d = d
			far = v
	if far != null:
		vm.call(&"_release", far)


func _on_car_exploded(_v: Vehicle) -> void:
	_car_dead = true


func _begin_escape() -> bool:
	_origin = _ref_pos_or_spawn()
	_heat0 = maxf(float(step["heat"]), float(step["clear"]) + 0.5)
	_patrol_want = int(step.get("patrol", 0))
	if _patrol_want > 0:
		_heat0 = maxf(_heat0, VehicleSpecs.PATROL_HEAT)            # a patrol chase needs the heat the Vael patrols answer to
	if Game.heat < _heat0:
		Game.add_heat(_heat0 - Game.heat)
	Game.quiet = 0.0
	visuals.show_marker(0, _origin, float(step["dist"]), ContractTypes.RED, -1.0, false)
	progress = 0.0
	_patrol_t = 0.0
	if _patrol_want > 0:
		_send_patrols()                                           # the chase starts now, not at the vehicle manager's next patrol attempt
	return true


## The Vael patrol vehicles that are chasing the player right now (VehicleManager's pool; empty without a manager).
func _chasing_patrols() -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	var vm := Game.vehicles
	if not is_instance_valid(vm):
		return out
	var list: Variant = vm.get("list")
	if list is Array:
		for v: Variant in list:
			var car := v as Vehicle
			if car != null and car.patrol and car.chasing and car.active and not car.dead and not car.driver_is_player:
				out.append(car)
	return out


func _patrols_chasing() -> int:
	return _chasing_patrols().size()


## Bring the chase up to the step's patrol count (within the tier's patrol cap: the car and draw budget of the vehicle module). A spot that cannot be found is simply tried again
## at the next top-up; it never fails the step.
func _send_patrols() -> void:
	var vm := Game.vehicles
	if not is_instance_valid(vm) or not vm.has_method(&"spawn_patrol"):
		return
	var want := mini(_patrol_want, int(vm.call(&"patrol_cap")))
	var have := _patrols_chasing()
	while have < want:
		if vm.call(&"spawn_patrol") == null:
			break
		have += 1


func _patrol_near(p: Vector3) -> bool:
	if not p.is_finite():
		return false
	for v: Vehicle in _chasing_patrols():
		if Vector2(v.global_position.x - p.x, v.global_position.z - p.z).length() < PATROL_LOSE:
			return true
	return false


func _begin_survive() -> bool:
	_hold_t = float(step["hold"]) * float(_kept.get(step_index, 0.0))
	wave = 0
	_gap_t = 2.0
	return true


# --- ticking an active step --------------------------------------------------------------------------------------------------

func _tick_active(delta: float) -> void:
	if InteriorGameplay.active and kind != &"enter_interior" and kind != &"heist":
		return                                           # inside a building the street's objectives wait (enemies are stored, the clock stops)
	if time_total > 0.0:
		time_left -= delta
	var p := _ref_pos()
	_tick_set_piece(delta, p)
	if state != &"active":
		return
	match kind:
		&"reach": _tick_reach(p)
		&"enter_interior": _tick_interior(p)
		&"escort": _tick_escort(delta, p)
		&"defend": _tick_defend(delta, p)
		&"hack": _tick_hack(delta, p)
		&"kill_target": _tick_kill(delta)
		&"chase": _tick_chase(delta, p)
		&"escape": _tick_escape(delta, p)
		&"survive": _tick_survive(delta, p)
		&"rift_hold": _tick_rift(delta, p)
		&"heist": _tick_heist(delta, p)
		&"convoy_intercept": _tick_convoy(delta, p)
	if state != &"active":
		return
	if time_total > 0.0 and time_left <= 0.0 and _beat_t <= 0.0:
		_fail("TIME OUT")


func _in_ring(p: Vector3, center: Vector3, radius: float) -> bool:
	return p.is_finite() and _hdist(p, center) < radius and absf(p.y - center.y) < VERTICAL_REACH


func _tick_reach(p: Vector3) -> void:
	var start_d := maxf(_hdist(_origin, pos), 1.0)
	progress = clampf(1.0 - _hdist(p, pos) / start_d, 0.0, 1.0) if p.is_finite() else progress
	if _in_ring(p, pos, float(step["radius"])):
		_complete_step(pos)


func _tick_interior(p: Vector3) -> void:
	if _door.is_empty():                                  # a city without doors: the step degrades to reaching the spot
		if _in_ring(p, pos, maxf(float(step["radius"]), 4.0)):
			_complete_step(pos)
		return
	var ig := InteriorGameplay.instance
	var in_ok := InteriorGameplay.active and ig != null and is_instance_valid(ig) and _door_matches(ig.door)
	if _phase == 1:
		progress = clampf(1.0 - _hdist(p, pos) / maxf(_hdist(_origin, pos), 1.0), 0.0, 0.95) if p.is_finite() and not InteriorGameplay.active else progress
		if in_ok:
			if bool(step["leave"]):
				_phase = 2
				progress = 0.5
				Game.say("NOW GET OUT", 2.0)
			else:
				_complete_step(_door["pos"])
	elif _phase == 2 and not InteriorGameplay.active and ig != null and not ig.busy:
		_complete_step(_door["pos"])


func _door_matches(d: Dictionary) -> bool:
	var id := int(step["door"])
	if id >= 0:
		return int(d.get("id", -2)) == id
	var type: StringName = step["interior"]
	if type != &"":
		return StringName(str(d.get("type", ""))) == type
	return int(d.get("id", -2)) == int(_door.get("id", -3))


func _tick_escort(delta: float, p: Vector3) -> void:
	if not is_instance_valid(escortee):
		_fail("ESCORT LOST")
		return
	var npc_pos := escortee.global_position
	var dist_player := _hdist(p, npc_pos) if p.is_finite() else 0.0
	var threats := 0
	var em := Game.enemies as EnemyManager
	if em != null:
		for e in em.list:
			if not e.active or e.dead:
				continue
			var d := _hdist(e.global_position, npc_pos)
			if e.aware and d < ESCORT_THREAT:
				threats += 1
			if e.aware and d < ESCORT_HURT:
				escort_hp -= ESCORT_DPS * (2.0 if e.type == &"heavy" or e.type == &"brute" else 1.0) * delta
	if escort_hp <= 0.0:
		_fail("ESCORT LOST")
		return
	var leash := float(step["leash"])
	# the escortee waits while hostiles are near, but not forever (found by the mission audit: two aware enemies that never closed in held it for four minutes): after ESCORT_PATIENCE seconds
	# of waiting for them it walks on for ESCORT_PUSH seconds, with the player or without
	if threats > 0:
		_threat_wait += delta
		if _threat_wait > ESCORT_PATIENCE:
			_push_t = ESCORT_PUSH
			_threat_wait = 0.0
	else:
		_threat_wait = maxf(_threat_wait - delta, 0.0)
	_push_t = maxf(_push_t - delta, 0.0)
	var waiting := dist_player > leash or (threats > 0 and _push_t <= 0.0)
	if dist_player > leash:
		_nag_t -= delta
		if _nag_t <= 0.0:
			_nag_t = 5.0
			Game.say("STAY CLOSE TO THE ESCORT", 1.6)
	if dist_player > float(step["abandon"]):
		_outside_t += delta
		if _outside_t > ESCORT_LEFT_TIME:
			_fail("ESCORT LEFT BEHIND")
			return
	else:
		_outside_t = 0.0
	if not waiting:
		_esc_s = minf(_esc_s + float(step["speed"]) * delta, _route_len)
	var pt := CampaignSteps.point_along(_route, _esc_s)
	var np: Vector3 = pt["pos"]
	np.y = _ground(np.x, np.z)
	var dir: Vector3 = pt["dir"]
	escortee.global_position = np
	escortee.rotation.y = atan2(-dir.x, -dir.z)
	visuals.move_marker(0, np)
	progress = clampf(_esc_s / maxf(_route_len, 1.0), 0.0, 1.0)
	for a: Dictionary in _ambush:
		if not a["done"] and progress >= float(a["at"]):
			a["done"] = true
			var n := int(a["n"])
			if n < 0:
				n = 2 + ContractTypes.count(&"hack", chapter_index)
			_spawn_wave(np, 26.0, 44.0, n, 1, a["types"] as Array)
			Game.say("AMBUSH", 1.6)
	_prune_foes()
	if _esc_s >= _route_len - 0.4 and _hdist(np, pos) < 3.0:
		_complete_step(Vector3(pos.x, 0.0, pos.z))


func _tick_defend(delta: float, p: Vector3) -> void:
	Game.heat = maxf(minf(Game.heat, HOLD_HEAT_CAP) - HOLD_HEAT_DECAY * delta, 0.0)
	var radius := float(step["radius"])
	var d := _hdist(p, pos) if p.is_finite() else 0.0
	inside = d < radius * ZONE_LEASH
	if inside:
		_outside_t = 0.0
		_hold_t += delta
	else:
		_outside_t += delta
		_nag_t -= delta
		if _nag_t <= 0.0:
			_nag_t = 3.0
			Game.say("RETURN TO THE ZONE", 1.5)
		if _outside_t > ZONE_LEASH_TIME:
			_fail("ZONE LOST")
			return
	_gap_t -= delta
	if _gap_t <= 0.0:
		_gap_t = float(step["gap"])
		_spawn_wave(pos, radius + 6.0, radius + 28.0, _wave_size(wave), wave, step.get("types", []) as Array)
		wave += 1
	_prune_foes()
	var hold := maxf(float(step["hold"]), 0.1)
	progress = clampf(_hold_t / hold, 0.0, 1.0)
	visuals.set_progress(0, progress)
	if _hold_t >= hold:
		_complete_step(p if p.is_finite() else pos)


func _tick_hack(delta: float, p: Vector3) -> void:
	Game.heat = maxf(minf(Game.heat, HOLD_HEAT_CAP) - HOLD_HEAT_DECAY * delta, 0.0)
	var d := _hdist(p, pos) if p.is_finite() else INF
	inside = d < float(step["radius"]) and absf(p.y - pos.y) < VERTICAL_REACH
	var rate := delta / maxf(float(step["hold"]), 1.0)
	progress = clampf(progress + (rate if inside else -rate * HACK_DECAY), 0.0, 1.0)
	visuals.set_progress(0, progress)
	_nag_t -= delta
	if not inside and _nag_t <= 0.0:
		_nag_t = 4.0
		Game.say("RETURN TO THE RING", 1.5)
	_attack_t -= delta
	if _attack_t <= 0.0:
		_attack_t = HACK_PULSE
		var n := int(step.get("count", 0))
		if n <= 0:
			n = ContractTypes.count(&"hack", chapter_index)
		for i in n:
			var type := &"sentinel"
			if i % 3 == 2:
				type = &"striker"
			elif chapter_index >= 2 and i % 2 == 1:
				type = &"operative"
			_spawn(type, road_point(pos, 34.0, 56.0), true)
		_prune_foes()
	if progress >= 1.0:
		_complete_step(p if p.is_finite() else pos)


func _tick_kill(delta: float) -> void:
	var d := target as Drone
	if d == null or not is_instance_valid(d):
		_fail("TARGET LOST")
		return
	if d.dead or d.hp <= 0.0:
		if d is Overseer or d is VerbBoss:
			_beat_t += maxf(delta, 0.001)                   # hold the step open: Cinematics notices the dead boss in _process and plays the slow-motion defeat (the game state leaves play, so this waits for it)
			if _beat_t < BOSS_BEAT:
				return
		var at := d.global_position
		_target_down(d)
		_complete_step(Vector3(at.x, 0.0, at.z))
		return
	if not d.active or d.remove:
		_fail("TARGET LOST")
		return
	d.set(&"_bar_t", 6.0)
	progress = 1.0 - clampf(d.hp / maxf(d.max_hp, 1.0), 0.0, 1.0)
	visuals.move_marker(0, d.global_position)


func target_name_for(d: Drone) -> String:
	return str(step.get("name", "BOSS"))


## An Overseer down counts as the chapter's boss: the contracts do not offer it again.
func _target_down(d: Drone) -> void:
	if d is VerbBoss:
		var vp := Game.progress as Progress
		if vp != null and not chapter_index in vp.bosses_cleared:
			vp.bosses_cleared.append(chapter_index)
			vp.add_reputation(10)
		Game.say(str(target_name_for(d)) + " DOWN", 3.0)
	elif d is Overseer:
		var prog := Game.progress as Progress
		if prog != null and not chapter_index in prog.bosses_cleared:
			prog.bosses_cleared.append(chapter_index)
			prog.add_reputation(10)
		Game.say("OVERSEER DOWN", 3.0)


func _tick_chase(delta: float, p: Vector3) -> void:
	if car == null or not is_instance_valid(car):
		_fail("TARGET LOST")
		return
	if _car_dead or car.dead:
		var at := car.global_position
		_complete_step(Vector3(at.x, 0.0, at.z))
		return
	if not car.active:
		_fail("TARGET LOST")
		return
	var d := _hdist(car.global_position, p) if p.is_finite() else 0.0
	_chase_t += delta
	var pl := Game.player as Player
	var driving := is_instance_valid(pl) and pl.vehicle != null
	if d > CHASE_ESCAPE and _chase_t > CHASE_GRACE:
		_escape_t += delta
		if _escape_t > CHASE_ESCAPE_TIME:
			_fail("TARGET ESCAPED")
			return
	else:
		_escape_t = 0.0
	progress = 1.0 - clampf(car.hp / maxf(car.max_hp, 1.0), 0.0, 1.0)
	pos = car.global_position
	visuals.move_marker(0, car.global_position)
	# the target eases off when the player falls behind (a chase must be catchable): full speed within 40 m, 55 % from 90 m, 40 % while the player is still on foot
	var base := (float(step["cruise"]) if float(step["cruise"]) > 0.0 else minf(15.0 + 1.2 * float(chapter_index), 24.0)) * maxf(1.0 - 0.1 * float(mini(fails, 3)), 0.7)
	var ease_k := clampf((d - 40.0) / 50.0, 0.0, 1.0)
	car.ai_cruise = base * (0.4 if not driving else lerpf(1.0, 0.55, ease_k))


func _tick_escape(delta: float, p: Vector3) -> void:
	if _patrol_want > 0 and Game.heat >= VehicleSpecs.PATROL_STAND_DOWN:
		_patrol_t -= delta
		if _patrol_t <= 0.0:
			_patrol_t = PATROL_TOPUP
			_send_patrols()
	var dist := float(step["dist"])
	var clear := float(step["clear"])
	var d := _origin_dist()
	Game.heat = minf(Game.heat, _heat0 + 0.01)                  # the pursuit does not escalate while the step runs
	if d >= dist and Game.heat > 0.0:
		Game.heat = maxf(0.0, Game.heat - ESCAPE_COOL * delta)  # far enough: the hunters lose the trail
	var far_part := clampf(d / maxf(dist, 1.0), 0.0, 1.0)
	var heat_part := 1.0 - clampf((Game.heat - clear) / maxf(_heat0 - clear, 0.1), 0.0, 1.0)
	progress = clampf(0.5 * far_part + 0.5 * heat_part, 0.0, 0.99)
	if d >= dist and Game.heat <= clear and not (_patrol_want > 0 and _patrol_near(p)):
		_complete_step(p if p.is_finite() else _origin)


func _tick_survive(delta: float, p: Vector3) -> void:
	_hold_t += delta
	_gap_t -= delta
	if _gap_t <= 0.0 and p.is_finite():
		_gap_t = float(step["gap"])
		_spawn_wave(p, 36.0, 58.0, _wave_size(wave), wave, step.get("types", []) as Array)
		wave += 1
	_prune_foes()
	var hold := maxf(float(step["hold"]), 0.1)
	progress = clampf(_hold_t / hold, 0.0, 1.0)
	if _hold_t >= hold:
		_complete_step(p if p.is_finite() else _origin)


# --- cleanup, radio ----------------------------------------------------------------------------------------------------------

func _clean_runtime() -> void:
	_patrol_want = 0
	_patrol_t = 0.0
	_beat_t = 0.0
	progress = -1.0
	inside = false
	wave = 0
	_hold_t = 0.0
	_gap_t = 0.0
	_attack_t = 0.0
	_outside_t = 0.0
	_nag_t = 0.0
	_escape_t = 0.0
	_phase = 0
	_door = {}
	_route = PackedVector3Array()
	_route_len = 0.0
	_esc_s = 0.0
	_ambush.clear()
	_car_dead = false
	_chase_car = null
	_chase_t = 0.0
	_threat_wait = 0.0
	_push_t = 0.0
	rift_hp = 0.0
	feed_left = 0.0
	loot = false
	_loot_said = false
	_grace_t = 0.0
	_far_t = 0.0


## Hide the visuals, release the car's hold and the escortee, and (when `release_foes`) send what the step spawned back to the pool.
func _cleanup(release_foes: bool) -> void:
	if visuals != null:
		visuals.hide_all()
	if car != null and is_instance_valid(car):
		car.remove_meta(&"hold")
		if car.exploded.is_connected(_on_car_exploded):
			car.exploded.disconnect(_on_car_exploded)
	car = null
	_release_convoy()
	if escortee != null and is_instance_valid(escortee):
		escortee.deactivate()
	if release_foes:
		var em := Game.enemies as EnemyManager
		var ov := target as Overseer
		if em != null and ov != null and is_instance_valid(ov):
			for s in ov.summoned.duplicate():
				if is_instance_valid(s) and s.active:
					em.release(s)
			Sfx.boss_active = false
		var vb := target as VerbBoss
		if em != null and vb != null and is_instance_valid(vb):
			for s in vb.summoned.duplicate():
				if is_instance_valid(s) and s.active:
					em.release(s)
			Sfx.boss_active = false
		if em != null:
			for f: Variant in foes:
				var d := f as Drone
				if d != null and is_instance_valid(d) and d.active:
					em.release(d)
		foes.clear()
	target = null
	progress = -1.0
	inside = false


## A line of the step's `radio` through the story layer: {s, t} said at the start, or {start, done, fail}.
func _radio(key: String) -> void:
	var r: Variant = step.get("radio", null)
	if not (r is Dictionary):
		return
	var rd := r as Dictionary
	var line: Variant = null
	if rd.has("t"):
		line = rd if key == "start" else null
	else:
		line = rd.get(key, null)
	if not (line is Dictionary) or (line as Dictionary).is_empty():
		return
	var l := line as Dictionary
	var id := "campaign.%d.%d.%s" % [chapter_index, step_index, key]
	var st: Object = Game.story if is_instance_valid(Game.story) else null
	if st != null and st.has_method(&"say"):
		st.call(&"say", str(l.get("s", StoryData.O)), str(l.get("t", "")), id, 0.0, 1)
	else:
		Game.say(str(l.get("t", "")), 3.0)


static func _clock_text(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d" % [s / 60, s % 60]


# --- boss set pieces (scripts/missions/set_pieces.gd) -----------------------------------------------------------------------------

## The running step belongs to an optional set piece.
func in_optional_set_piece() -> bool:
	return state in [&"armed", &"active", &"retry"] and step_index < steps.size() and bool(steps[step_index].get("optional", false))


## Drops the optional set piece the chapter is at (the remaining steps carry on). False for anything else.
func skip_set_piece() -> bool:
	if not in_optional_set_piece():
		return false
	_cleanup(true)
	sp_zones.clear()
	_skip_to(SetPieces.end_index(steps, step_index))
	return true


func _skip_to(i: int) -> void:
	_begin_tries = 0
	step_index = i
	if step_index >= steps.size():
		_complete_chapter()
	else:
		state = &"armed"
		_arm_t = STEP_GAP


func _begin_set_piece_phase() -> void:
	_sp_t = 0.0
	_sp_anchor = Vector3.INF
	_sp_cycle = -1
	_sp_hit = -1
	sp_zones.clear()
	sp_hazard_state = &"idle"
	if bool(step.get("sp_first", false)) and fails == 0 and Cinematics.instance != null and Game.is_playing():
		Cinematics.instance.play(&"sp_in", {"set_piece": step["set_piece"]})


func _end_set_piece_phase(st: Dictionary) -> void:
	sp_zones.clear()
	sp_hazard_state = &"idle"
	if bool(st.get("sp_last", false)) and Cinematics.instance != null and Game.is_playing():
		Cinematics.instance.play(&"sp_out", {"set_piece": st["set_piece"]})


func _tick_set_piece(delta: float, p: Vector3) -> void:
	var h: Variant = step.get("hazard", null)
	if not (h is Dictionary) or not p.is_finite():
		return
	_sp_t += delta
	var hz := h as Dictionary
	var cyc := SetPieces.cycle_of(hz, _sp_t)
	if cyc != _sp_cycle:
		_sp_cycle = cyc
		_sp_anchor = p
		sp_zones.clear()
	sp_hazard_state = SetPieces.hazard_state(hz, _sp_t)
	if sp_hazard_state == &"idle":
		sp_zones.clear()
		return
	if sp_zones.is_empty():
		sp_zones = SetPieces.zones(hz, cyc, _sp_anchor)
	if sp_hazard_state == &"hit" and _sp_hit != cyc:
		var dmg := SetPieces.damage_at(hz, _sp_t, _sp_anchor, p)
		_sp_hit = cyc
		var pl := Game.player as Player
		if dmg > 0.0 and pl != null and is_instance_valid(pl):
			pl.damage(dmg, _sp_anchor)


# --- sequel mechanics: rift hold, quantum heist, convoy intercept --------------------------------------------------------------
# The three kinds only use existing systems: waves (EnemyManager), traffic cars (VehicleManager), interior doors and missions (InteriorGameplay), patrol vehicles and heat (the escape
# step's own code). Verbs reach them through Quantum.verb_used (ENTANGLE, SUPERPOSITION, COLLAPSE, link) and QuantumVerbs.used (SHIELD, SLIP, ARC).

## Listen to the player's verbs (idempotent; also follows a new player instance).
func _hook_verbs() -> void:
	var pl := Game.player
	if not is_instance_valid(pl):
		return
	var q: Object = pl.get(&"quantum")
	if q != null and is_instance_valid(q) and q != _verbs_from and q.has_signal(&"verb_used"):
		q.connect(&"verb_used", _on_verb)
		_verbs_from = q
	var qv: Object = pl.get(&"qverbs")
	if qv != null and is_instance_valid(qv) and qv != _qverbs_from and qv.has_signal(&"used"):
		qv.connect(&"used", _on_verb)
		_qverbs_from = qv


## A verb fired (`id`: &"entangle", &"collapse", &"superposition", &"link", or a QuantumVerbs id).
func _on_verb(id: StringName) -> void:
	if state != &"active":
		return
	var p := _ref_pos()
	if not p.is_finite():
		return
	match kind:
		&"rift_hold":
			if _hdist(p, pos) < float(step["radius"]) * ZONE_LEASH:
				feed_left = minf(feed_left + float(step["feed"]), FEED_MAX)
				FX.burst(pos + Vector3(0.0, 1.5, 0.0), ContractTypes.CYAN, 14, 4.0, 0.5, 0.0)
		&"convoy_intercept":
			for c: Vehicle in convoy:
				if not is_instance_valid(c) or c.dead or stopped.has(c):
					continue
				var d := _hdist(c.global_position, p)
				if id == &"entangle" and d < ENTANGLE_STOP:
					_stop_car(c)
				elif id == &"collapse" and d < COLLAPSE_STOP:
					c.damage(c.max_hp * 0.3)
					if is_instance_valid(c) and not c.dead:
						_stop_car(c)


# rift hold ------------------------------------------------------------------------------------------------------------------

func _begin_rift() -> bool:
	_hook_verbs()
	_hold_t = float(step["hold"]) * float(_kept.get(step_index, 0.0))
	feed_left = 0.0
	wave = 0
	_gap_t = 3.0
	_outside_t = 0.0
	_nag_t = 4.0
	inside = true
	rift_max = maxf(float(step["integrity"]), 1.0)
	rift_hp = rift_max
	visuals.show_marker(0, pos, float(step["radius"]), ContractTypes.CYAN, 0.0, true)
	return true


func _tick_rift(delta: float, p: Vector3) -> void:
	var radius := float(step["radius"])
	var d := _hdist(p, pos) if p.is_finite() else 0.0
	inside = d < radius * ZONE_LEASH
	feed_left = maxf(feed_left - delta, 0.0)
	var hold := maxf(float(step["hold"]), 0.1)
	if inside:
		_outside_t = 0.0
		if feed_left > 0.0:
			_hold_t = minf(_hold_t + delta, hold)
		else:
			_hold_t = maxf(_hold_t - delta * RIFT_DECAY, 0.0)
			_nag_t -= delta
			if _nag_t <= 0.0:
				_nag_t = 5.0
				Game.say("USE A VERB TO FEED THE RIFT", 1.6)
	else:
		_hold_t = maxf(_hold_t - delta * RIFT_DECAY, 0.0)
		_outside_t += delta
		_nag_t -= delta
		if _nag_t <= 0.0:
			_nag_t = 3.0
			Game.say("RETURN TO THE RIFT", 1.5)
		if _outside_t > ZONE_LEASH_TIME:
			_fail("ZONE LOST")
			return
	_gap_t -= delta
	if _gap_t <= 0.0:
		_gap_t = float(step["gap"])
		_spawn_wave(pos, radius + 6.0, radius + 28.0, _wave_size(wave), wave, step.get("types", []) as Array)
		wave += 1
	var drain := 0
	var em := Game.enemies as EnemyManager
	if em != null:
		for e in em.list:
			if e.active and not e.dead and e.aware and _hdist(e.global_position, pos) < radius + 4.0:
				drain += 1
	if drain > 0:
		rift_hp -= RIFT_DPS * float(drain) * delta
	else:
		rift_hp = minf(rift_hp + RIFT_REGEN * delta, rift_max)
	if rift_hp <= 0.0:
		rift_hp = 0.0
		_fail("RIFT LOST")
		return
	_prune_foes()
	progress = clampf(_hold_t / hold, 0.0, 1.0)
	visuals.set_progress(0, progress)
	if _hold_t >= hold:
		_complete_step(p if p.is_finite() else pos)


# quantum heist --------------------------------------------------------------------------------------------------------------

func _begin_heist() -> bool:
	_door = _find_door(step, _origin)
	if not _door.is_empty():
		pos = _door["pos"]
	loot = false
	_loot_said = false
	_grace_t = 0.0
	_hold_t = 0.0
	_phase = 1
	var ig := InteriorGameplay.instance
	if ig != null and is_instance_valid(ig):
		if ig.missions != null and ig.missions != _missions_from:
			ig.missions.completed.connect(_on_heist_mission)
			_missions_from = ig.missions
		if InteriorGameplay.active and (_door.is_empty() or _door_matches(ig.door)):
			_phase = 2                                        # already inside the right building (a retry)
	visuals.show_marker(0, pos, float(step["radius"]), ContractTypes.AMBER, -1.0, true)
	return true


func _on_heist_mission(_k: StringName, _id: int, _reward: Dictionary) -> void:
	if state == &"active" and kind == &"heist" and _phase == 2 and not loot:
		loot = true


func _tick_heist(delta: float, p: Vector3) -> void:
	var ig := InteriorGameplay.instance
	var ig_ok := ig != null and is_instance_valid(ig)
	match _phase:
		1:
			if _door.is_empty():                              # a city without doors: reaching the spot is the theft
				if _in_ring(p, pos, maxf(float(step["radius"]), 4.0)):
					loot = true
					_start_getaway()
				return
			progress = clampf(1.0 - _hdist(p, pos) / maxf(_hdist(_origin, pos), 1.0), 0.0, 0.3) if p.is_finite() and not InteriorGameplay.active else progress
			if ig_ok and InteriorGameplay.active and _door_matches(ig.door):
				_phase = 2
				_grace_t = 0.0
				progress = 0.33
				Game.say("TAKE THE DATA", 2.0)
		2:
			if not InteriorGameplay.active:
				if ig_ok and ig.busy:
					return
				if loot:
					_start_getaway()
				else:
					_phase = 1
					progress = 0.1
					Game.say("THE DATA IS STILL INSIDE", 2.0)
				return
			if ig_ok and not loot and not ig.busy and not ig.missions.is_active():
				_grace_t += delta                             # a room with nothing to crack: the data is simply there
				if _grace_t >= float(step["grace"]):
					loot = true
			if loot:
				progress = 0.66
				if not _loot_said:
					_loot_said = true
					Game.say("DATA TAKEN  GET OUT", 2.5)
		3:
			_hold_t += delta
			if _hold_t > float(step["escape_time"]):
				_fail("NOT LOST")
				return
			var prev := progress
			_tick_escape(delta, p)
			if state == &"active":
				progress = maxf(progress, prev if prev > 0.66 else 0.66)


## Phase 3: the escape step's own start (heat, patrol vehicles, the ring), anchored at the door the player just came out of.
func _start_getaway() -> void:
	_phase = 3
	_hold_t = 0.0
	visuals.hide_all()
	_begin_escape()
	progress = 0.66
	Game.say("GETAWAY", 2.0)


# convoy intercept -----------------------------------------------------------------------------------------------------------

func _begin_convoy() -> bool:
	var vm := Game.vehicles
	if not is_instance_valid(vm) or not vm.has_method(&"spawn_traffic"):
		return false
	_hook_verbs()
	_release_convoy()
	var axis := rng.randi() % 2
	var dir := 1 if rng.randf() < 0.5 else -1
	var road_i: int = VehicleSpecs.road_index(pos.z if axis == 0 else pos.x)
	var along := pos.x if axis == 0 else pos.z
	for i in int(step["cars"]):
		var at := along - float(dir) * CONVOY_GAP * float(i)
		var c: Vehicle = vm.call(&"spawn_traffic", &"sedan", axis, road_i, dir, at)
		if c == null:
			_free_a_car(vm)
			c = vm.call(&"spawn_traffic", &"sedan", axis, road_i, dir, at)
		if c == null:
			break
		c.max_hp = float(step["hp"])
		c.hp = c.max_hp
		c.ai_cruise = float(step["cruise"])
		c.set_meta(&"hold", true)
		convoy.append(c)
	if convoy.is_empty():
		return false
	pos = convoy[0].global_position
	_far_t = 0.0
	_chase_t = 0.0
	_ensure_chase_car(vm)
	visuals.show_marker(0, pos, 3.0, ContractTypes.RED, -1.0, true)
	Game.add_heat(0.2)
	return true


func _stopped_count() -> int:
	var n := 0
	for c: Vehicle in convoy:
		if not is_instance_valid(c) or c.dead or stopped.has(c):
			n += 1
	return n


func _nearest_moving_car() -> Vehicle:
	var p := _ref_pos()
	var best: Vehicle = null
	var bd := INF
	for c: Vehicle in convoy:
		if is_instance_valid(c) and not c.dead and not stopped.has(c):
			var d := _hdist(c.global_position, p) if p.is_finite() else 0.0
			if d < bd:
				bd = d
				best = c
	return best


func _stop_car(c: Vehicle) -> void:
	if stopped.has(c):
		return
	stopped.append(c)
	c.ai_stun = 1.0e6
	Sfx.play(&"ui_contract_accept")
	Game.say("CAR STOPPED  %d/%d" % [_stopped_count(), convoy.size()], 1.4)


func _tick_convoy(delta: float, p: Vector3) -> void:
	var far := false
	_chase_t += delta
	var pl := Game.player as Player
	var driving := is_instance_valid(pl) and pl.vehicle != null
	for c: Vehicle in convoy:
		if not is_instance_valid(c) or (not c.active and not c.dead):
			_fail("CONVOY LOST")
			return
		if c.dead or stopped.has(c):
			continue
		if c.hp <= c.max_hp * CONVOY_DISABLE:
			_stop_car(c)
			continue
		if p.is_finite():
			var cd := _hdist(c.global_position, p)
			var ease_k := clampf((cd - 40.0) / 50.0, 0.0, 1.0)
			c.ai_cruise = float(step["cruise"]) * maxf(1.0 - 0.15 * float(mini(fails, 3)), 0.55) * (0.4 if not driving else lerpf(1.0, 0.55, ease_k))       # the convoy eases off when the player falls behind (catchable on foot and in a car)
			if cd > CONVOY_ESCAPE and _chase_t > CHASE_GRACE:
				far = true
	for c: Vehicle in stopped:
		if is_instance_valid(c):
			c.ai_stun = 1.0e6
	var total := maxi(convoy.size(), 1)
	progress = float(_stopped_count()) / float(total)
	var near := _nearest_moving_car()
	if near == null:
		var last := convoy[convoy.size() - 1].global_position
		_complete_step(Vector3(last.x, 0.0, last.z))
		return
	pos = near.global_position
	visuals.move_marker(0, near.global_position)
	if far:
		_far_t += delta
		if _far_t > CONVOY_ESCAPE_TIME:
			_fail("CONVOY GOT AWAY")
	else:
		_far_t = 0.0


## Lift the hold on the convoy cars (a stopped one drives on after a few seconds) and forget them.
func _release_convoy() -> void:
	for c: Vehicle in convoy:
		if is_instance_valid(c):
			c.remove_meta(&"hold")
			if not c.dead:
				c.ai_stun = 3.0
	convoy.clear()
	stopped.clear()
