class_name WorldSteps
extends RefCounted
## The campaign step kinds of the big world (wave 107; the runner is scripts/missions/campaign_runner.gd, the recipes WorldMissions, the data campaign_steps.gd):
##   reach + `veh`      the ring only counts while the hero sits in the right KIND of vehicle: air (any aircraft), heli, plane, boat, ground (car, bike, quad, hover, tank). `provide` leaves such a
##                      vehicle waiting at `provide_at` (heading `provide_h`) from the moment the step begins; `land` makes an aircraft finish only when it stands down and slow inside the ring.
##   gates              fly or drive through the 3D gates of `pts` in order (radius `radius`, metres, 3D for aircraft): GateMarks draws the current ring and the next one. `veh` as above.
##   pursuit            a scripted vehicle (`target`: pickup / boat / jetski / ...) runs along `route` (a polyline Vector3 array: a mountain road, a river) at `cruise` m/s. It EASES OFF when
##                      the hero falls behind and waits when he is far, so it is always catchable. Done when it is wrecked, when the hero stays within `catch` metres for BOX_HOLD seconds ("boxed in",
##                      the target stops), or when the hero takes it over. A target stuck against something is put back on its line (never a stuck mission).
## One instance per CampaignRunner (`runner.ws`). All state is reset at every step begin; nothing is allocated per frame.

const BOX_HOLD := 2.2                     ## seconds within `catch` metres that box a pursuit target in
const STUCK_SECONDS := 3.0
const WAIT_FAR := 190.0
const CLASSES := {
	&"air": [&"heli", &"plane"], &"heli": [&"heli"], &"plane": [&"plane"], &"boat": [&"boat"],
}
const NEED_TEXT := {
	&"air": "GET IN AN AIRCRAFT", &"heli": "GET IN THE HELICOPTER", &"plane": "GET IN THE PLANE", &"boat": "GET IN A BOAT", &"ground": "GET IN A CAR",
}
const LAND_SPEED := 5.0
const LAND_AGL := 2.5

var r: CampaignRunner
var gates: Array[Vector3] = []
var gi := 0
var marks: GateMarks
var target: Vehicle
var path: PathFollow
var box_t := 0.0
var target_down := false
var done_flag := false
var provided: Array[Vehicle] = []
var gates_taken := 0                       ## gates passed in the running step (tests, HUD)
var _stuck_t := 0.0
var _last_hero := Vector3.INF
var _arrived := false


func _init(runner: CampaignRunner) -> void:
	r = runner


# --- the vehicle the hero is in ---------------------------------------------------------------------------------------------------

static func hero_vehicle() -> Vehicle:
	var pl := Game.player
	if not is_instance_valid(pl):
		return null
	var v: Variant = pl.get(&"vehicle")
	return v as Vehicle if v is Vehicle and is_instance_valid(v) else null


static func class_ok(v: Vehicle, need: StringName) -> bool:
	if need == &"":
		return true
	if v == null or v.dead or v.wreck:
		return false
	if need == &"ground":
		return not (v.cls == &"heli" or v.cls == &"plane" or v.cls == &"boat")
	return (CLASSES.get(need, []) as Array).has(v.cls)


static func need_of(step: Dictionary) -> StringName:
	return StringName(str(step.get("veh", "")))


static func is_air(need: StringName) -> bool:
	return need == &"air" or need == &"heli" or need == &"plane"


static func need_text(need: StringName) -> String:
	return String(NEED_TEXT.get(need, ""))


## True when `v` is an aircraft standing on the ground and slow (a landing).
static func landed(v: Vehicle) -> bool:
	if v == null or v.craft == null:
		return false
	return not v.craft.airborne and v.craft.agl < LAND_AGL and absf(v.speed) < LAND_SPEED


static func _d3(a: Vector3, b: Vector3) -> float:
	return a.distance_to(b)


static func _h(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Shortest distance between the segment a-b and the point c (3D): a fast aircraft cannot skip a gate between two frames.
static func seg_dist(a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return a.distance_to(c)
	return a.lerp(b, clampf((c - a).dot(ab) / l2, 0.0, 1.0)).distance_to(c)


# --- reach with a vehicle ----------------------------------------------------------------------------------------------------

## A reach step that names a vehicle begins: the vehicle it provides is left waiting.
func begin_reach() -> void:
	var prov := str(r.step.get("provide", ""))
	if prov == "":
		return
	var at: Variant = r.step.get("provide_at", r.pos)
	provide(StringName(prov), at as Vector3 if at is Vector3 else r.pos, float(r.step.get("provide_h", 0.0)))


## Leaves a vehicle of `kind` at `at` (an existing parked one of that kind within 40 m is taken, so a retry does not pile them up). It is held (never streamed away) until the step ends.
func provide(kind: StringName, at: Vector3, heading: float) -> Vehicle:
	var vm := Game.vehicles
	if not is_instance_valid(vm) or not vm.has_method(&"spawn_parked"):
		return null
	for v: Vehicle in (vm.get("list") as Array):
		if v.kind == kind and v.active and not v.dead and not v.wreck and not v.driver_is_player and not v.ai and _h(v.global_position, at) < 40.0:
			v.set_meta(&"hold", true)
			if not provided.has(v):
				provided.append(v)
			return v
	var c: Vehicle = vm.call(&"spawn_parked", kind, at, heading)
	if c == null:
		r._free_a_car(vm)
		c = vm.call(&"spawn_parked", kind, at, heading)
	if c != null:
		c.set_meta(&"hold", true)
		provided.append(c)
	return c


## The ring of a reach step with `veh` is reached: in the right vehicle, inside the radius (3D for an aircraft that need not land), and down and slow when the step says `land`.
func reach_ok(p: Vector3) -> bool:
	var need := need_of(r.step)
	var v := hero_vehicle()
	if not class_ok(v, need):
		return false
	var rad := float(r.step["radius"])
	if bool(r.step.get("land", false)):
		return _h(p, r.pos) < rad and landed(v)
	if is_air(need) and v.craft != null and v.craft.airborne:
		return _d3(p, Vector3(r.pos.x, maxf(r.pos.y, TerrainHeight.height_at(r.pos.x, r.pos.z)), r.pos.z)) < rad + 25.0
	return _h(p, r.pos) < rad and absf(p.y - r.pos.y) < (CampaignRunner.VERTICAL_REACH if not is_air(need) else 60.0)


func reach_hint() -> String:
	var need := need_of(r.step)
	var v := hero_vehicle()
	if not class_ok(v, need):
		return need_text(need)
	if bool(r.step.get("land", false)) and v != null and v.craft != null:
		return "LAND IT" if not landed(v) else ""
	return ""


# --- gates ----------------------------------------------------------------------------------------------------------------------

func begin_gates() -> bool:
	gates.clear()
	var raw: Variant = r.step.get("pts", [])
	for q: Variant in raw as Array:
		if q is Vector3:
			gates.append(q as Vector3)
	if gates.is_empty():
		return false
	gi = 0
	gates_taken = 0
	_last_hero = Vector3.INF
	_ensure_marks()
	var flat := not is_air(need_of(r.step))
	marks.show_gate(gates, gi, float(r.step["radius"]), flat)
	r.pos = gates[0]
	r.progress = 0.0
	return true


func _ensure_marks() -> void:
	if marks == null or not is_instance_valid(marks):
		marks = GateMarks.new()
		if r.visuals != null:
			r.visuals.add_child(marks)
		else:
			r.add_child(marks)


func tick_gates(_delta: float, p: Vector3) -> void:
	if gi >= gates.size():
		return
	var need := need_of(r.step)
	var v := hero_vehicle()
	if not class_ok(v, need):
		_last_hero = Vector3.INF
		return
	var rad := float(r.step["radius"])
	var g := gates[gi]
	var hit := false
	if is_air(need):
		hit = (seg_dist(_last_hero, p, g) if _last_hero.is_finite() else _d3(p, g)) < rad
	else:
		var a2 := Vector3(_last_hero.x, 0.0, _last_hero.z) if _last_hero.is_finite() else Vector3(p.x, 0.0, p.z)
		hit = seg_dist(a2, Vector3(p.x, 0.0, p.z), Vector3(g.x, 0.0, g.z)) < rad
	_last_hero = p
	if not hit:
		return
	gi += 1
	gates_taken += 1
	r.progress = clampf(float(gi) / float(gates.size()), 0.0, 1.0)
	Sfx.play(&"ui_contract_accept")
	if gi >= gates.size():
		marks.hide_all()
		r._complete_step(p)
		return
	Game.say("GATE %d OF %d" % [gi + 1, gates.size()], 1.2)
	r.pos = gates[gi]
	marks.show_gate(gates, gi, rad, not is_air(need))


# --- pursuit --------------------------------------------------------------------------------------------------------------------

func begin_pursuit() -> bool:
	var route: Variant = r.step.get("route", null)
	if not (route is PackedVector3Array) or (route as PackedVector3Array).size() < 2:
		return false
	var vm := Game.vehicles
	if not is_instance_valid(vm) or not vm.has_method(&"spawn_parked"):
		return false
	path = PathFollow.new(route as PackedVector3Array)
	var lead := float(r.step.get("lead", 70.0))
	var at := path.point_at(lead)
	var d := path.dir_at(lead)
	var h := atan2(-d.x, -d.z)
	var kind := StringName(str(r.step.get("target", "pickup")))
	var c: Vehicle = vm.call(&"spawn_parked", kind, at, h)
	if c == null:
		r._free_a_car(vm)
		c = vm.call(&"spawn_parked", kind, at, h)
	if c == null:
		return false
	var fails := maxi(r.fails, 0)
	c.max_hp = float(r.step.get("hp", 220.0)) * maxf(1.0 - 0.2 * float(mini(fails, 3)), 0.4)      # every failed run makes it a little easier to wreck
	c.hp = c.max_hp
	c.scripted = true
	c.script_thr = 0.0
	c.script_steer = 0.0
	c.set_meta(&"hold", true)
	if not c.exploded.is_connected(_on_exploded):
		c.exploded.connect(_on_exploded)
	target = c
	target_down = false
	done_flag = false
	box_t = 0.0
	_stuck_t = 0.0
	_arrived = false
	path.s = lead
	path._i = 0
	path.advance(at)
	r.pos = c.global_position
	r.visuals.show_marker(0, r.pos, 4.0, ContractTypes.RED, -1.0, true)
	r.progress = 0.0
	Game.add_heat(0.05)
	return true


func _on_exploded(_v: Vehicle) -> void:
	target_down = true


func tick_pursuit(delta: float, p: Vector3) -> void:
	if target == null or not is_instance_valid(target):
		r._fail("TARGET LOST")
		return
	var t := target
	if t.dead or t.wreck or target_down:
		done_flag = true
		r._complete_step(p)
		return
	if t.driver_is_player:
		done_flag = true
		r._complete_step(p)
		return
	var tp := t.global_position
	var d := _h(p, tp) if p.is_finite() else 999.0
	var cruise := float(r.step.get("cruise", 15.0))
	var f := clampf(1.6 - d / 120.0, 0.0, 1.0)
	if d > WAIT_FAR:
		f = 0.0
	var want := cruise * f
	path.drive(t, want, delta)
	if path.remaining() < 8.0:
		_arrived = true
	# stuck on something: back on the line a few metres ahead
	if want > 3.0 and absf(t.speed) < 0.8 and not _arrived:
		_stuck_t += delta
		if _stuck_t > STUCK_SECONDS:
			_stuck_t = 0.0
			_put_back(t)
	else:
		_stuck_t = maxf(_stuck_t - delta, 0.0)
	# boxed in
	var catch_d := float(r.step.get("catch", 15.0))
	if d < catch_d:
		box_t += delta
	else:
		box_t = maxf(box_t - delta * 0.5, 0.0)
	r.progress = clampf(box_t / BOX_HOLD, 0.0, 1.0)
	r.pos = tp
	r.visuals.move_marker(0, Vector3(tp.x, tp.y + 1.0, tp.z))
	if box_t >= BOX_HOLD:
		t.scripted = false
		t.speed = 0.0
		t.ai_stun = 30.0
		Game.say("BOXED IN", 1.6)
		done_flag = true
		r._complete_step(p)


func _put_back(t: Vehicle) -> void:
	var s2 := path.s + 7.0
	var q := path.point_at(s2)
	var dir := path.dir_at(s2)
	var y := t.global_position.y
	if t.cls != &"boat":
		y = TerrainHeight.height_at(q.x, q.z) + t.base_y
	else:
		y = q.y - float(t.spec.get("draft", 0.35))
	t.global_position = Vector3(q.x, y, q.z)
	t.heading = atan2(-dir.x, -dir.z)
	t.rotation.y = t.heading
	t.speed = 0.0
	t.vel = Vector3.ZERO
	path.s = s2


# --- text and markers -----------------------------------------------------------------------------------------------------------

func hud_tail() -> String:
	match r.kind:
		&"gates":
			var need := need_of(r.step)
			if not class_ok(hero_vehicle(), need):
				return "  " + need_text(need)
			return "  GATE %d/%d  %d M" % [mini(gi + 1, gates.size()), gates.size(), roundi(_h(r._ref_pos(), r.pos))]
		&"pursuit":
			var d := _h(r._ref_pos(), r.pos) if is_instance_valid(target) else 0.0
			return "  %d M  %s" % [roundi(d), "STAY CLOSE" if box_t > 0.1 else "CLOSE IN"]
	return ""


## Release what a step held: the provided vehicles go back to the streaming rules, the pursuit target too (and a target that was not caught or wrecked goes back to the pool).
func clean() -> void:
	for v: Vehicle in provided:
		if is_instance_valid(v):
			v.remove_meta(&"hold")
	provided.clear()
	if target != null and is_instance_valid(target):
		target.scripted = false
		target.remove_meta(&"hold")
		if target.exploded.is_connected(_on_exploded):
			target.exploded.disconnect(_on_exploded)
		var vm := Game.vehicles
		if not done_flag and is_instance_valid(vm) and vm.has_method(&"_release") and not target.driver_is_player and not target.dead:
			vm.call(&"_release", target)
	target = null
	path = null
	target_down = false
	done_flag = false
	box_t = 0.0
	gates.clear()
	gi = 0
	_last_hero = Vector3.INF
	_arrived = false
	if marks != null and is_instance_valid(marks):
		marks.hide_all()
