class_name StealthRunner
extends Node
## The four stealth missions (Game.missions.stealth, wave 69): data and rules in stealth_scripts.gd. A run plays inside an interior (InteriorGameplay) and watches its Vael guards:
## any guard that becomes ALERTED (Drone.aware) fails the run (SPOTTED), a clock that runs out fails it (TIME OUT), leaving the interior before the job is done ends it quietly (LEFT).
## Live wiring: entering a door of the matching interior type (teleporter hall, warehouse, server room, cargo bay) offers the job automatically (once per door, sector-gated like the
## side missions); the DEMO menu STEALTH tab starts any of them at once (enters the nearest such door, or a test room). Pay: Economy.STEALTH_PAY via StealthScripts.reward.
## The HUD shows the line (hud_line) and an alert meter (meter), the interior minimap the objective (markers), the room a disc + pillar on it. Simulates only while Game.is_playing();
## tick() is callable by tests. API: can_start(id) · start(id) · abort(reason) · tick(dt) · hud_line() · meter() · markers() · state (&"idle" &"running") · result (last run)

signal started(id: StringName)
signal phase_changed(id: StringName, phase: StringName)
signal finished(id: StringName, ok: bool, reason: String)

var id: StringName = &""
var def: Dictionary = {}
var state: StringName = &"idle"
var phase: StringName = &"approach"     ## approach | work | exit (route: approach only)
var clock := 0.0
var progress := 0.0                     ## plant / copy fill 0..1
var target_pos := Vector3.ZERO          ## the objective of the current phase (world)
var takedowns_done := 0
var takedowns_total := 0
var alert_frac := 0.0                   ## 0 unaware .. 1 alerted: the HUD meter
var result: Dictionary = {}             ## {id, ok, reason, reward, bonus, time, kills}
var done := {}                          ## door id -> true (finished this session; DEMO MODE ignores it)
var auto_offer := true                  ## false: only start() runs a mission (tests that walk interiors)

var _ig: InteriorGameplay
var _door_id := -1
var _alerts0 := 0
var _guards: Array[Drone] = []
var _kills := 0
var _seen_enter := -1
var _t := 0.0
var _disc: MeshInstance3D
var _pillar: MeshInstance3D
var _mat: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"stealth_missions")
	set_physics_process(true)
	Game.new_game.connect(abort.bind("RESET"))
	Game.respawn.connect(abort.bind("DOWN"))


func _exit_tree() -> void:
	_hide_marker()


func is_running() -> bool:
	return state == &"running"


func _gameplay() -> InteriorGameplay:
	if _ig == null or not is_instance_valid(_ig):
		_ig = InteriorGameplay.instance
	return _ig


func _chapter() -> int:
	return int(Game.story.get("chapter")) if is_instance_valid(Game.story) else 0


# --- starting ---------------------------------------------------------------------------------------------------------------

## True when `id` could start now: nothing else of ours runs, the player stands in a position to enter or is inside the right interior with unaware guards.
func can_start(sid: StringName) -> bool:
	if is_running() or not StealthScripts.DEFS.has(sid) or not is_instance_valid(Game.player):
		return false
	var ig := _gameplay()
	if ig == null or ig.busy:
		return false
	if ig.active:
		return StringName(ig.door.get("type", &"")) == StringName(StealthScripts.DEFS[sid]["interior"]) and _room_ready(ig)
	var m := Game.missions as Missions
	if m != null:
		if m.campaign != null and m.campaign.is_running():
			return false
		if m.sides != null and m.sides.active:
			return false
		if m.chases != null and m.chases.is_running():
			return false
		if m.contracts != null and bool(m.contracts.is_active()):
			return false
	return true


## The interior is built, the guards are all unaware and nobody hunts the player from the street.
func _room_ready(ig: InteriorGameplay) -> bool:
	if ig.actors == null or ig.interior == null or not ig.actors._follow_types.is_empty() or not ig.actors.followers.is_empty():
		return false
	if ig.missions != null and ig.missions.is_active():
		return false
	var n := 0
	for g in ig.actors.guards:
		if is_instance_valid(g) and g.active and not g.dead:
			n += 1
			if g.aware:
				return false
	return n > 0


## Start `sid`: go into the nearest door of its interior (or a test room) when not inside already, then begin.
func start(sid: StringName) -> bool:
	if not can_start(sid):
		return false
	var ig := _gameplay()
	var want := StringName(StealthScripts.DEFS[sid]["interior"])
	if not ig.active:
		_seen_enter = -2                      # the entry below is ours: the automatic offer must not start it a second time
		ig.test_enter(want)
		if not ig.active:
			return false
	elif StringName(ig.door.get("type", &"")) != want:
		return false
	_seen_enter = ig.enter_count
	return _begin(sid, ig)


## The automatic offer: called when the player stands in an interior he just entered through a door.
func _offer(ig: InteriorGameplay) -> void:
	if not auto_offer or is_running() or ig.door.is_empty():
		return
	var sid := StealthScripts.for_interior(StringName(ig.door.get("type", &"")))
	if sid == &"" or not StealthScripts.unlocked(sid, _chapter()):
		return
	if done.has(int(ig.door.get("id", -1))) and not DemoMode.active:
		return
	if _room_ready(ig):
		_begin(sid, ig)


func _begin(sid: StringName, ig: InteriorGameplay) -> bool:
	if not _room_ready(ig):
		return false
	id = sid
	def = StealthScripts.def(sid)
	_ig = ig
	_door_id = int(ig.door.get("id", -1))
	_alerts0 = Stealth.alerts
	_guards.clear()
	for g in ig.actors.guards:
		if is_instance_valid(g) and g.active and not g.dead:
			_guards.append(g)
	_kills = 0
	takedowns_done = 0
	takedowns_total = _guards.size() if StealthScripts.mode_of(sid) == &"route" else 0
	clock = 0.0
	progress = 0.0
	alert_frac = 0.0
	result = {}
	state = &"running"
	phase = &"approach"
	target_pos = _objective(ig)
	_show_marker()
	Game.say("%s  %s" % [StealthScripts.title(sid), String(def["brief"])], 4.0)
	Sfx.play(&"mission_start")
	started.emit(sid)
	return true


## The objective of the current phase: the anchor of its kind farthest from the door, or the way out.
func _objective(ig: InteriorGameplay) -> Vector3:
	if phase == &"exit":
		return InteriorGameplay.exit_point(ig.interior)
	if StealthScripts.mode_of(id) == &"route":
		var g := _nearest_guard(Game.player.global_position)
		return g.global_position if g != null else InteriorGameplay.exit_point(ig.interior)
	var door_at: Vector3 = ig.interior.get("door_pos")
	var list: Array = InteriorGameplay.anchor_points(ig.interior, StringName(def["terminal"]), 3, int(ig.interior.get("seed")))
	var best: Vector3 = list[0]["pos"]
	for a: Dictionary in list:
		if (a["pos"] as Vector3).distance_to(door_at) > best.distance_to(door_at):
			best = a["pos"]
	return Vector3(best.x, 0.0, best.z)


func _nearest_guard(from: Vector3) -> Drone:
	var best: Drone
	var bd := INF
	for g in _guards:
		if is_instance_valid(g) and g.active and not g.dead:
			var d := Vector2(g.global_position.x - from.x, g.global_position.z - from.z).length()
			if d < bd:
				bd = d
				best = g
	return best


func abort(reason := "ABANDONED") -> void:
	if is_running():
		_end(false, reason)


# --- simulation -------------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if not Game.is_playing():
		return
	var ig := _gameplay()
	if ig == null:
		return
	_t += delta
	if not is_running():
		if ig.active and auto_offer and ig.enter_count != _seen_enter:
			_seen_enter = ig.enter_count
			_offer(ig)
		return
	if not ig.active:
		if phase == &"exit":
			_end(true, "")
		else:
			_end(false, "LEFT")
		return
	clock += delta
	_watch_guards()
	if not is_running():
		return
	var pp: Vector3 = Game.player.global_position if is_instance_valid(Game.player) else Vector3.ZERO
	var tl := float(def["time"])
	if tl > 0.0 and clock >= tl:
		_end(false, "TIME OUT")
		return
	match StealthScripts.mode_of(id):
		&"reach":
			if _flat(pp, target_pos) < StealthScripts.REACH:
				_end(true, "")
		&"plant":
			_tick_plant(delta, pp, ig)
		&"data":
			if _flat(pp, target_pos) < StealthScripts.REACH + 0.3:
				progress = minf(1.0, progress + delta / StealthScripts.FILL_S)
			else:
				progress = maxf(0.0, progress - delta * StealthScripts.FILL_DECAY / StealthScripts.FILL_S)
			if progress >= 1.0:
				_end(true, "")
		&"route":
			target_pos = _objective(ig)
			if takedowns_done >= takedowns_total:
				_end(true, "")
	_move_marker()


func _tick_plant(delta: float, pp: Vector3, ig: InteriorGameplay) -> void:
	if phase == &"approach":
		if _flat(pp, target_pos) < StealthScripts.REACH:
			_set_phase(&"work", ig)
	elif phase == &"work":
		if _flat(pp, target_pos) < StealthScripts.REACH + 0.3:
			progress = minf(1.0, progress + delta / StealthScripts.PLANT_S)
		else:
			progress = maxf(0.0, progress - delta * 0.25)
		if progress >= 1.0:
			_set_phase(&"exit", ig)
	elif phase == &"exit":
		if _flat(pp, target_pos) < InteriorGameplay.REACH_EXIT:
			_end(true, "")


func _set_phase(p: StringName, ig: InteriorGameplay) -> void:
	phase = p
	target_pos = _objective(ig) if p != &"work" else target_pos
	Sfx.play(&"ui_tap")
	phase_changed.emit(id, p)
	_move_marker()


## Alert detection and the meter. A dead guard is a takedown (route) or a kill (bonus lost); an ALERTED living guard ends the run.
func _watch_guards() -> void:
	var worst := 0.0
	var dead_now := 0
	for g in _guards:
		if not is_instance_valid(g) or not g.active:
			dead_now += 1
			continue
		if g.dead:
			dead_now += 1
			continue
		if g.aware:
			worst = 1.0
		else:
			worst = maxf(worst, clampf(g.suspicion, 0.0, 0.99))
			if g.search_t > 0.0:
				worst = maxf(worst, 0.7)
	_kills = dead_now
	takedowns_done = dead_now if StealthScripts.mode_of(id) == &"route" else 0
	alert_frac = worst
	if worst >= 1.0 or Stealth.alerts > _alerts0:
		alert_frac = 1.0
		_end(false, "SPOTTED")


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- ending -----------------------------------------------------------------------------------------------------------------

func _end(ok: bool, reason: String) -> void:
	var sid := id
	var bonus := false
	var pay := 0
	var prog := Game.progress as Progress
	if ok:
		bonus = clock <= StealthScripts.PAR if StealthScripts.mode_of(sid) == &"route" else _kills == 0
		var rep := prog.reputation if prog != null else 0
		pay = StealthScripts.reward(sid, _chapter(), rep, bonus)
		if prog != null:
			prog.add_credits(pay)
			prog.bonus_score(pay)
			prog.add_reputation(int(def["rep"]))
			prog.contracts_done += 1
		else:
			Game.add_score(pay)
		if not DemoMode.active:
			done[_door_id] = true
	elif reason != "RESET" and reason != "LEFT" and prog != null:
		prog.add_reputation(StealthScripts.FAIL_REP)
	result = {"id": sid, "ok": ok, "reason": reason, "reward": pay, "bonus": bonus, "time": clock, "kills": _kills}
	state = &"idle"
	id = &""
	_hide_marker()
	Sfx.play(&"ui_contract_complete" if ok else &"ui_contract_fail")
	if ok:
		Game.say("%s COMPLETE  +%d CREDITS%s" % [StealthScripts.title(sid), pay, ("  " + StealthScripts.bonus_name(sid)) if bonus else ""], 4.0)
	else:
		Game.say("%s FAILED  %s" % [StealthScripts.title(sid), reason], 4.0)
	finished.emit(sid, ok, reason)


# --- display ----------------------------------------------------------------------------------------------------------------

## HUD plate line ("" when no stealth mission runs).
func hud_line() -> String:
	if not is_running():
		return ""
	var head := StealthScripts.title(id)
	match StealthScripts.mode_of(id):
		&"reach":
			return "%s  REACH THE TERMINAL" % head
		&"plant":
			match phase:
				&"approach": return "%s  REACH THE CRATES" % head
				&"work": return "%s  PLANTING  %d%%" % [head, int(progress * 100.0)]
				_: return "%s  GET OUT" % head
		&"data":
			var left := maxi(0, int(ceilf(float(def["time"]) - clock)))
			return "%s  COPYING  %d%%  %d s" % [head, int(progress * 100.0), left]
		&"route":
			return "%s  TAKEDOWNS  %d/%d" % [head, takedowns_done, takedowns_total]
	return head


## The HUD alert meter: {frac 0..1, label} while a run is on, empty otherwise.
func meter() -> Dictionary:
	if not is_running():
		return {}
	var label := "UNSEEN"
	if alert_frac >= 1.0:
		label = "ALERTED"
	elif alert_frac >= 0.7:
		label = "SEARCHING"
	elif alert_frac > 0.05:
		label = "SUSPICIOUS"
	return {"frac": alert_frac, "label": label}


## Interior minimap markers: {pos, color, kind, radius}.
func markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_running():
		return out
	var col := Color(0.45, 0.95, 1.0) if phase != &"exit" else Color(0.4, 1.0, 0.6)
	if StealthScripts.mode_of(id) == &"route":
		var g := _nearest_guard(Game.player.global_position) if is_instance_valid(Game.player) else null
		if g != null:
			out.append({"pos": g.global_position, "color": Color(1.0, 0.72, 0.25), "kind": &"target", "radius": 1.0})
		return out
	out.append({"pos": target_pos, "color": col, "kind": &"zone" if phase == &"work" or StealthScripts.mode_of(id) == &"data" else &"target", "radius": StealthScripts.REACH})
	return out


func marker_visible() -> bool:
	return _disc != null and _disc.visible


func _make_marker() -> void:
	if _disc != null:
		return
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disc = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = StealthScripts.REACH * 0.5
	cm.bottom_radius = StealthScripts.REACH * 0.5
	cm.height = 0.03
	cm.radial_segments = 20
	cm.rings = 1
	_disc.mesh = cm
	_disc.material_override = _mat
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disc.top_level = true
	add_child(_disc)
	_pillar = MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.06
	pm.bottom_radius = 0.06
	pm.height = 3.0
	pm.radial_segments = 6
	pm.rings = 1
	_pillar.mesh = pm
	_pillar.material_override = _mat
	_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pillar.top_level = true
	add_child(_pillar)


func _show_marker() -> void:
	_make_marker()
	_disc.visible = true
	_pillar.visible = true
	_move_marker()


func _hide_marker() -> void:
	if _disc != null:
		_disc.visible = false
		_pillar.visible = false


func _move_marker() -> void:
	if _disc == null or not _disc.visible:
		return
	var col := Color(0.45, 0.95, 1.0) if phase != &"exit" else Color(0.4, 1.0, 0.6)
	if StealthScripts.mode_of(id) == &"route":
		col = Color(1.0, 0.72, 0.25)
	_mat.albedo_color = Color(col.r * 1.4, col.g * 1.4, col.b * 1.4, 0.5 + 0.25 * sin(_t * 5.0))
	_disc.global_position = Vector3(target_pos.x, target_pos.y + 0.04, target_pos.z)
	_pillar.global_position = Vector3(target_pos.x, target_pos.y + 1.5, target_pos.z)
