class_name SnakeMissionDirector
extends Node
## What happens around the QUANTUM SNAKE missions and the first hours of the traversal (a child of the Player, made by SnakeTraversal.bind):
##   * the COURIER of ROOFTOP CHASE: a real sentinel drone (EnemyManager.spawn) that hovers over the roof of the current step and hops to the next roof when the hero finishes the step, a snake
##     (SnakeTendril) from the drone to the new roof for the jump; at the last roof the CampaignRunner's own kill_target drone takes over (the courier is dismissed). He is held with Drone.disable.
##   * SWING ACROSS THE CITY finished = the tutorial flag (SnakeMissions.mark_tutorial_done): the board stops forcing it.
##   * one-line hints, each once per profile (saved in user://snake_traversal.cfg): TAP SNAKE TO ZIP UP, HOLD SNAKE TO SWING, TAP SNAKE TO CLIMB, TAP FLY TO FLY. Plain words, no lessons.
## Counters for the tests: hops, hints_shown.

const HINT_DELAY := 14.0                    ## play seconds before the first hint
const HINT_GAP := 18.0                      ## seconds between two hints
const HOP_TIME := 1.7
const COURIER_HOVER := 4.0

var st: SnakeTraversal
var courier: Drone
var hops := 0
var hints_shown: Array[StringName] = []
var current_mission := ""
var _t := 0.0
var _tick_t := 0.0
var _hop_t := -1.0
var _hop_from := Vector3.ZERO
var _hop_to := Vector3.ZERO
var _hop_index := 0
var _hint_t := 0.0
var _play_t := 0.0
var _seen := {}
var _camp: CampaignRunner
var _hooked := false


func _ready() -> void:
	name = "SnakeDirector"
	var cf := ConfigFile.new()
	if cf.load(SnakeMissions.SAVE) == OK and cf.has_section("hints"):
		for k in cf.get_section_keys("hints"):
			_seen[k] = bool(cf.get_value("hints", k, false))


func _process(delta: float) -> void:
	if st == null or st.p == null:
		return
	var dt := minf(delta, 0.1)
	if _hop_t >= 0.0 and is_instance_valid(courier):
		_hop_t += dt
		var k := clampf(_hop_t / HOP_TIME, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		var pos := _hop_from.lerp(_hop_to, e)
		pos.y += sin(k * PI) * 9.0
		courier.global_position = pos
		courier.disable(0.3)
		if k >= 1.0:
			_hop_t = -1.0
	elif is_instance_valid(courier) and courier.active and not courier.dead:
		courier.disable(0.3)
		courier.global_position.y += sin(_t * 2.4) * 0.004
	_t += dt
	_tick_t -= dt
	if _tick_t > 0.0:
		return
	_tick_t = 0.25
	_tick_missions()
	_tick_hints(0.25)


func _runner() -> CampaignRunner:
	if _camp == null or not is_instance_valid(_camp):
		var m := Game.missions as Missions
		_camp = m.campaign if m != null else null
	if _camp != null and not _hooked:
		_hooked = true
		_camp.step_completed.connect(_on_step_completed)
		_camp.chapter_completed.connect(_on_chapter_completed)
	return _camp


func _tick_missions() -> void:
	var camp := _runner()
	var mission := ""
	if camp != null and (camp.state == &"active" or camp.state == &"retry"):
		mission = str(camp.step.get("snake_mission", ""))
	if mission != "":
		current_mission = mission
	if mission == "roof_chase":
		_ensure_courier(camp)
	else:
		_dismiss_courier()
		if mission == "":
			_hop_index = 0


func _ensure_courier(camp: CampaignRunner) -> void:
	var hop_pts: Array = camp.step.get("hops", [])
	if hop_pts.size() < 2:
		return
	if camp.target != null and is_instance_valid(camp.target):                  # the last step: the runner's own drone is the target
		_dismiss_courier()
		return
	if is_instance_valid(courier) and courier.active and not courier.dead:
		return
	var idx := clampi(camp.step_index, 0, hop_pts.size() - 1)
	var em := Game.enemies as EnemyManager
	if em == null:
		return
	var at: Vector3 = (hop_pts[idx] as Vector3) + Vector3(0.0, COURIER_HOVER, 0.0)
	courier = em.spawn(&"sentinel", at, false)
	if courier != null:
		courier.global_position = at
		courier.home = at
		courier.max_hp = 1.0e5                                                   # the courier cannot be shot down before the last roof
		courier.hp = courier.max_hp
		_hop_index = idx


func _dismiss_courier() -> void:
	if is_instance_valid(courier):
		if courier.has_method(&"deactivate"):
			courier.call(&"deactivate")
		else:
			courier.queue_free()
	courier = null
	_hop_t = -1.0


func _on_step_completed(_chapter: int, index: int, kind: StringName) -> void:
	if current_mission != "roof_chase" or not is_instance_valid(courier) or kind != &"reach":
		return
	var camp := _runner()
	if camp == null:
		return
	var hop_pts: Array = camp.step.get("hops", [])
	var nxt := index + 1
	if nxt >= hop_pts.size():
		return
	_hop_from = courier.global_position
	_hop_to = (hop_pts[nxt] as Vector3) + Vector3(0.0, COURIER_HOVER, 0.0)
	_hop_t = 0.0
	_hop_index = nxt
	hops += 1
	courier.home = _hop_to
	var tgt := _hop_to
	var c := SnakeTendril.fire(courier, tgt, {"travel": 0.25, "wriggle": 0.6, "tension": 0.5, "thickness": 0.12, "life": HOP_TIME - 0.3, "color": Color(1.0, 0.35, 0.8), "host": st.p})
	c.user["keep"] = false
	FX.burst(courier.global_position, Color(1.0, 0.4, 0.85), 10, 6.0, 0.5, 0.0, 1.2)
	Sfx.play_at(&"snk_fire", courier.global_position, -2.0)


func _on_chapter_completed(_chapter: int) -> void:
	if current_mission == "swing_city":
		SnakeMissions.mark_tutorial_done()
	current_mission = ""
	_dismiss_courier()


# --- hints --------------------------------------------------------------------------------------------------------------------------------

func _tick_hints(dt: float) -> void:
	if Game.state != &"play" or st.p == null or st.p.is_dead() or not st.button_shown():
		return
	_play_t += dt
	_hint_t = maxf(0.0, _hint_t - dt)
	if _play_t < HINT_DELAY or _hint_t > 0.0 or current_mission != "":
		return
	var p := st.p
	if st.mode != SnakeTraversal.Mode.NONE:
		return
	var air := p.air_time > 0.4
	if not air and st.hint == &"climb" and st.climbs == 0:
		_hint(&"climb", "TAP SNAKE TO CLIMB THE WALL")
	elif not air and st.hint == &"zip" and st.zips == 0 and st.swings == 0:
		_hint(&"zip", "TAP SNAKE TO ZIP UP")
	elif air and st.hint == &"swing" and st.swings == 0:
		_hint(&"swing", "HOLD SNAKE TO SWING")
	elif air and st.fly_button_shown() and st.flights == 0 and st.swings > 0:
		_hint(&"fly", "TAP FLY TO FLY")


func _hint(id: StringName, text: String) -> void:
	if bool(_seen.get(id, false)):
		return
	_seen[id] = true
	hints_shown.append(id)
	_hint_t = HINT_GAP
	Game.say(text, 3.0)
	SnakeMissions.save_flags({id: true})
