class_name RoamRuns
extends Node
## LANDMARK RACES AND STUNT JUMPS of the free-roam world (wave 111).
##   RACES   five races along the real outskirt roads (`RoamData.races()`: CITY TO DUST WELLS, CITY TO THE COAST, CITY TO PINE HOLLOW, THE MOUNTAIN PASS, SUMMIT CLIMB). A gold ring marks the
##           start while the hero is within 520 m; drive into it in any ground vehicle that is under way and the race starts by itself: a checkpoint about every 300 m, the finish at the end of the
##           road, a par time at 22 m/s and a limit of 2.4 x par. The first finish is a discovery and pays 360-420 plus 5 per second under par; a repeat pays half. Leaving the vehicle for 8 s ends it.
##   STUNTS  five ramps on straight, level stretches of the roads (`RoamData.stunts()`): take one at 14 m/s or more in a car, truck, bike or quad and the car clears 32 m, whatever its speed, and
##           comes down in a landing ring. The first landing in the ring is a discovery; a repeat pays 35. (The same fake-lift flight as the city's stunt ramps in `Jobs`.)
## `poll(dt, hero)` is driven by RoamWorld; `start_race(id)` and `launch(i)` let tests start them directly.

signal race_started(id: StringName)
signal race_finished(id: StringName, ok: bool, secs: float, pay: int)
signal stunt_landed(id: StringName, ok: bool, err: float)

const START_R := 22.0
const SEE_START := 520.0
const GATE_R := 20.0
const LEAVE_GRACE := 8.0
const COOLDOWN := 5.0
const SEE_RAMP := 300.0
const REPEAT_STUNT := 35

var world: RoamWorld
var prompt := ""
var active: StringName = &""               ## the running race
var gate_i := 0
var elapsed := 0.0
var last_pay := 0
var attempts := 0                          ## stunt launches
var marks: GateMarks

var _gates: Array[Vector3] = []
var _race: Dictionary = {}
var _off_t := 0.0
var _last := Vector3.INF
var _cool := 0.0
var _prompt_t := 0.0
var _ramp_nodes: Array[MeshInstance3D] = []
# stunt flight
var _air_car: Vehicle
var _air_i := -1
var _air_t := 0.0
var _air_T := 1.0
var _lifted: Vehicle


func _init(w: RoamWorld = null) -> void:
	world = w
	name = "RoamRuns"


func reset() -> void:
	cancel_race("")
	_cancel_air()
	attempts = 0


func in_air() -> bool:
	return _air_car != null


func _ground_vehicle() -> Vehicle:
	var v := WorldSteps.hero_vehicle()
	return v if v != null and WorldSteps.class_ok(v, &"ground") else null


func poll(dt: float, hero: Vector3) -> void:
	_cool = maxf(0.0, _cool - dt)
	var busy := world != null and world.busy()
	_tick_ramps(dt, hero)
	if active != &"":
		_tick_race(dt, hero, busy)
	elif not busy and _air_car == null:
		_idle(hero)
	else:
		prompt = ""
	_last = hero


# --- races ----------------------------------------------------------------------------------------------------------------------------

func race(id: StringName) -> Dictionary:
	for r in RoamData.races():
		if r["id"] == id:
			return r
	return {}


func _idle(hero: Vector3) -> void:
	prompt = ""
	var v := _ground_vehicle()
	for r in RoamData.races():
		var s: Vector3 = r["start"]
		var d := RoamWorld.flat(s, hero)
		if d < START_R * 1.6 and v != null and _cool <= 0.0 and not _hero_blocked():
			prompt = "RACE  %s  DRIVE THROUGH THE RING" % String(r["name"])
		if _cool <= 0.0 and v != null and d < START_R and absf(hero.y - s.y) < 40.0 and (absf(v.speed) > 3.0) and not _hero_blocked():
			start_race(r["id"])
			return


func _hero_blocked() -> bool:
	var wr := WorldRoam.instance
	return (wr != null and wr.active != &"") or _air_car != null


## Begins race `id` (the hero drove into its ring; tests call it directly). False when it does not exist or another race runs.
func start_race(id: StringName) -> bool:
	if active != &"":
		return false
	var r := race(id)
	if r.is_empty():
		return false
	active = id
	_race = r
	_gates = r["gates"] as Array[Vector3]
	gate_i = 0
	elapsed = 0.0
	_off_t = 0.0
	_last = Vector3.INF
	if marks == null:
		marks = GateMarks.new()
		add_child(marks)
	marks.show_gate(_gates, 0, GATE_R, true)
	Game.say("%s  GO  %d CHECKPOINTS" % [String(r["name"]), _gates.size()], 2.8)
	Sfx.play(&"mission_start")
	race_started.emit(id)
	return true


func cancel_race(why: String) -> void:
	if active == &"":
		return
	var id := active
	active = &""
	if marks != null:
		marks.hide_all()
	_cool = COOLDOWN
	if why != "":
		Game.say("%s ENDED  %s" % [String(_race.get("name", "RACE")), why], 2.5)
	race_finished.emit(id, false, elapsed, 0)


func _tick_race(dt: float, hero: Vector3, busy: bool) -> void:
	if busy:
		cancel_race("MISSION STARTED")
		return
	elapsed += dt
	var v := _ground_vehicle()
	if v == null:
		_off_t += dt
		_last = Vector3.INF
		if _off_t > LEAVE_GRACE:
			cancel_race("LEFT THE VEHICLE")
		return
	_off_t = 0.0
	if elapsed > float(_race["limit"]):
		var nm := String(_race["name"])
		var rid := active
		active = &""
		marks.hide_all()
		_cool = COOLDOWN
		Game.say("%s  TIME UP" % nm, 3.0)
		race_finished.emit(rid, false, elapsed, 0)
		return
	_prompt_t -= dt
	if _prompt_t <= 0.0:
		_prompt_t = 0.5
		prompt = "RACE  CHECKPOINT %d/%d  %s  %d M" % [gate_i + 1, _gates.size(), _clock(float(_race["limit"]) - elapsed), roundi(RoamWorld.flat(_gates[gate_i], hero))]
	var g := _gates[gate_i]
	var a2 := Vector3(_last.x, 0.0, _last.z) if _last.is_finite() else Vector3(hero.x, 0.0, hero.z)
	var hit := WorldSteps.seg_dist(a2, Vector3(hero.x, 0.0, hero.z), Vector3(g.x, 0.0, g.z)) < GATE_R
	if not hit:
		return
	gate_i += 1
	Sfx.play(&"ui_contract_accept")
	if gate_i >= _gates.size():
		_finish_race()
		return
	Game.say("CHECKPOINT %d OF %d" % [gate_i + 1, _gates.size()], 1.0)
	marks.show_gate(_gates, gate_i, GATE_R, true)


static func _clock(secs: float) -> String:
	var s := maxi(int(secs), 0)
	return "%d:%02d" % [s / 60, s % 60]


func _finish_race() -> void:
	var id := active
	var r := _race
	active = &""
	marks.hide_all()
	_cool = COOLDOWN
	prompt = ""
	var first := world != null and not world.races_done.has(id)
	var pay := RoamData.race_pay(int(r["pay"]), float(r["par"]), elapsed)
	if not first:
		pay = int(pay * 0.5)
	last_pay = pay
	if world != null:
		var prev := float(world.races_done.get(id, 0.0))
		if prev <= 0.0 or elapsed < prev:
			world.races_done[id] = elapsed
		if first:
			world.note(&"race", id, "RACE  %s  %s" % [String(r["name"]), _clock(elapsed)], pay)
		else:
			var prog := Game.progress as Progress
			if prog != null:
				prog.add_credits(pay)
				prog.bonus_score(pay)
			Game.say("%s  %s  +%d" % [String(r["name"]), _clock(elapsed), pay], 3.0)
			world.save_now()
	race_finished.emit(id, true, elapsed, pay)


# --- stunt jumps ----------------------------------------------------------------------------------------------------------------------

func _ramps() -> Array[Dictionary]:
	return RoamData.stunts()


func _tick_ramps(dt: float, hero: Vector3) -> void:
	_show_ramps(hero)
	if _air_car != null:
		if not is_instance_valid(_air_car) or _air_car.dead or not _air_car.active:
			_cancel_air()
		else:
			_air_t += dt
			var k := clampf(_air_t / _air_T, 0.0, 1.0)
			_set_lift(_air_car, 4.0 * FreedomData.JUMP_APEX * k * (1.0 - k))
			if k >= 1.0:
				_land()
		return
	var car := _ground_vehicle()
	if car == null or (world != null and world.busy()):
		if _lifted != null:
			if is_instance_valid(_lifted):
				_set_lift(_lifted, 0.0)
			_lifted = null
		return
	var q := car.global_position
	var on_any := false
	var list := _ramps()
	for i in list.size():
		var r := list[i]
		var dir: Vector3 = r["dir"]
		var local := q - (r["pos"] as Vector3)
		var along := local.x * dir.x + local.z * dir.z
		var across := absf(local.x * -dir.z + local.z * dir.x)
		if along < 0.0 or along > FreedomData.RAMP_LEN or across > FreedomData.RAMP_WID * 0.5 + 0.8:
			continue
		on_any = true
		_set_lift(car, FreedomData.RAMP_H * along / FreedomData.RAMP_LEN)
		_lifted = car
		if along >= FreedomData.RAMP_LEN - 1.6 and car.speed >= FreedomData.STUNT_MIN_SPEED and car.forward().dot(dir) > 0.7:
			launch(i, car)
		break
	if not on_any and _lifted != null:
		if is_instance_valid(_lifted):
			_set_lift(_lifted, 0.0)
		_lifted = null


## The car leaves ramp `i` (the ramp's own check calls this; tests call it directly with a car on the ramp).
func launch(i: int, car: Vehicle = null) -> bool:
	if _air_car != null or i < 0 or i >= _ramps().size():
		return false
	if car == null:
		car = _ground_vehicle()
	if car == null:
		return false
	_air_car = car
	_air_i = i
	_air_t = 0.0
	_air_T = clampf(FreedomData.JUMP_DIST / maxf(car.speed, 1.0), 0.9, 2.2)
	attempts += 1
	FX.burst(car.global_position + Vector3(0.0, 0.5, 0.0), Color(0.3, 0.9, 1.0), 10, 5.0, 0.4, 1.0)
	Sfx.play(&"blink", -6.0, 1.2)
	Game.say("STUNT JUMP", 0.9)
	return true


func _land() -> void:
	var car := _air_car
	var i := _air_i
	_set_lift(car, 0.0)
	_air_car = null
	_air_i = -1
	_lifted = null
	var r := _ramps()[i]
	var land: Vector3 = r["land"]
	var err := RoamWorld.flat(car.global_position, land)
	FX.burst(car.global_position + Vector3(0.0, 0.3, 0.0), Color(0.7, 0.7, 0.75), 8, 4.0, 0.5, 2.0)
	FX.shake(0.3)
	Sfx.play_at(&"hit", car.global_position, -6.0)
	var ok := err <= RoamData.STUNT_RING
	if not ok:
		Game.say("STUNT JUMP  MISSED THE RING", 1.4)
	elif world != null:
		var id: StringName = r["id"]
		var first := not world.stunts.has(id)
		world.stunts[id] = minf(float(world.stunts.get(id, 999.0)), err)
		if first:
			world.note(&"stunt", id, "STUNT JUMP  %s" % String(r["name"]))
		else:
			var prog := Game.progress as Progress
			if prog != null:
				prog.add_credits(REPEAT_STUNT)
			Game.say("STUNT JUMP  %s  +%d" % [String(r["name"]), REPEAT_STUNT], 1.8)
			world.save_now()
	stunt_landed.emit(StringName(r["id"]), ok, err)


func _set_lift(car: Vehicle, h: float) -> void:
	if car == null or car.visual == null or car.visual.model == null:
		return
	car.visual.model.position.y = h + (car.bob if car.cls == &"hover" else 0.0)


func _cancel_air() -> void:
	if _air_car != null and is_instance_valid(_air_car):
		_set_lift(_air_car, 0.0)
	_air_car = null
	_air_i = -1
	if _lifted != null and is_instance_valid(_lifted):
		_set_lift(_lifted, 0.0)
	_lifted = null


## The ramp meshes (one small node each, the five of them) are visible only while the hero is within SEE_RAMP of one.
func _show_ramps(hero: Vector3) -> void:
	var list := _ramps()
	if _ramp_nodes.is_empty() and not list.is_empty():
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.55
		mat.metallic = 0.4
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.emission_enabled = true
		mat.emission = Color(0.05, 0.22, 0.28)
		var mesh := Jobs.ramp_mesh()
		mesh.surface_set_material(0, mat)
		for r in list:
			var n := MeshInstance3D.new()
			n.mesh = mesh
			n.name = "Ramp_%s" % String(r["id"])
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.top_level = true
			n.visible = false
			add_child(n)
			n.global_transform = Transform3D(Basis(Vector3.UP, float(r["yaw"])), r["pos"])
			_ramp_nodes.append(n)
	for i in _ramp_nodes.size():
		_ramp_nodes[i].visible = RoamWorld.flat(list[i]["pos"], hero) < SEE_RAMP


func ramp_visible_count() -> int:
	var n := 0
	for r in _ramp_nodes:
		if r.visible:
			n += 1
	return n


## Rings: the nearest race start (gold, with a column) in `slot`, the nearest stunt's landing ring in slot + 1.
func show_mark(m: RoamMarks, slot: int, hero: Vector3) -> void:
	if active == &"":
		var best := {}
		var bd := SEE_START
		for r in RoamData.races():
			var d := RoamWorld.flat(r["start"], hero)
			if d < bd:
				bd = d
				best = r
		if not best.is_empty():
			m.show_at(slot, best["start"], START_R, Color(1.0, 0.72, 0.25), true, false, 0.8)
	var sb := {}
	var sd := SEE_RAMP + 40.0
	for s in RoamData.stunts():
		var d2 := RoamWorld.flat(s["land"], hero)
		if d2 < sd:
			sd = d2
			sb = s
	if not sb.is_empty():
		m.show_at(slot + 1, sb["land"], RoamData.STUNT_RING, Color(0.3, 0.9, 1.0), true, false, 0.8)


func markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if active != &"" and gate_i < _gates.size():
		out.append({"pos": _gates[gate_i], "color": Color(1.0, 0.8, 0.3), "radius": 14.0, "goal": true, "label": String(_race.get("name", "RACE")), "kind": &"job"})
	return out
