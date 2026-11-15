class_name SnakeVerbs
extends RefCounted
## THE TEN SNAKE VERBS (wave 115, combat side; owned by SnakeWar, numbers in SnakeRows.VERBS). Every verb starts at the hero's hand with a SnakeTendril (the one snake visual), reaches its target in a
## fraction of a second and ends in an effect that is visible at once:
##   SNAKE PULL   (ALT = ZIP TO)  yanks an enemy, a pickup or a prop to the hero; a heavy target (a car, a brute, a boss) pulls the HERO to it instead and the landing kicks it
##   SNAKE GRAB   (hold FIRE)     lifts an enemy, a car or a prop into a snake cradle in front of the hero, release throws it (a table blast where it lands, `sv_slam`); ALT puts it down
##   SNAKE DISARM                 snatches the gun out of a hand (the weapon flies to the hero along the snake); the enemy stops shooting; the hero fires the same gun for twelve seconds
##   YANK COVER                   tears a car or a prop away from in front of the enemy: it is flung at the enemies behind it and they are left standing in the open
##   SNAKE NET                    a net of snakes over an area: everyone in it is wrapped, drops the gun and cannot move
##   SNAKE LASH   (hold FIRE)     snake whips at the nearest enemy, three hits and a finisher, chains to a second enemy, a stunned enemy goes down at once (a takedown)
##   SNAKE SHIELD                 three snakes circle the hero, stop shots (a pool of damage) and bite anyone who comes close
##   SNAKE DECOY                  a coil of snakes that stands where the crosshair is and draws the enemies' fire
##   SNAKE TRAP                   a coil on the ground that catches the first enemy who steps in
##   SNAKE GUARD                  three snakes fight for twelve seconds: they hunt the nearest enemy and bite
## `press(id, force)` casts a verb; `handle(...)` is the armed input; `shield_absorb(amount, from)` is the hook of Player.damage; the decoy is read by EnemyManager.get_clone (SnakeWar.decoy_node).
## Counters (tests wait on these): pulls, zips, grabs, throws, slams, disarms, yanks, nets, lashes, finishers, takedowns, shields, blocks, bites, decoys, decoy_hits, traps, trap_catches, guards, guard_bites.

const LASH_RANGE := 7.5
const LASH_COMBO_GAP := 1.15
const LOAN_SECONDS := 12.0
const GRAB_MAX := 6.0
const GRAB_DRAIN := 3.0                                ## energy units a second while an enemy hangs in the snakes
const THROW_SPEED := 26.0
const THROW_GRAVITY := 22.0
const SHIELD_SECONDS := 8.0
const SHIELD_POOL := 160.0
const DECOY_SECONDS := 6.0
const DECOY_POOL := 140.0
const GUARD_SECONDS := 12.0
const TRAP_LIFE := 45.0
const LOAN_BY_TYPE := {&"operative": &"battle", &"flanker": &"flux", &"heavy": &"lmg", &"sniper": &"bolt", &"brute": &"breacher", &"shield": &"mpistol", &"commander": &"magnum", &"medic": &"vector"}
const TRAP_CAP := [2, 3, 4]
const GUARD_CAP := [3, 4, 6]

static var decoy_ref: Node3D

var war: SnakeWar
var p: Player
var pulls := 0
var zips := 0
var grabs := 0
var throws := 0
var slams := 0
var disarms := 0
var yanks := 0
var nets := 0
var lashes := 0
var finishers := 0
var takedowns := 0
var shields := 0
var blocks := 0
var bites := 0
var decoys := 0
var decoy_hits := 0
var traps := 0
var trap_catches := 0
var guards := 0
var guard_bites := 0
var loans := 0

var shield: Dictionary = {}                            ## {left, hp, bodies, bite_t}
var decoy: Dictionary = {}                             ## {node, left, hp, bodies}
var trap_list: Array[Dictionary] = []
var guard_list: Array[SnakeSwarm.Body] = []
var guard_left := 0.0
var loan: Dictionary = {}                              ## {id, left, prev, owned}
var _grab: Dictionary = {}
var _flights: Array[Dictionary] = []
var _pickups: Array[Dictionary] = []
var _kick: Dictionary = {}                             ## a pending landing kick after a pull to a heavy target {node, left}
var _lash_cd := 0.0
var _lash_step := 0
var _lash_t := 0.0
var _lash_side := 1
var _proxy: MeshInstance3D
var _rq := PhysicsRayQueryParameters3D.new()
var _fire_hold := false


func _init(w: SnakeWar = null) -> void:
	war = w
	p = w.p if w != null else null
	_rq.collision_mask = Game.L_WORLD


# --- helpers ---------------------------------------------------------------------------------------------------------------------------

func _hand(side: int) -> Callable:
	return p.snake.hand_callable(side)


func _tendril(side: int, target: Variant, opts: Dictionary) -> SnakeTendril:
	var o := {"host": p, "wriggle": 0.4, "thickness": 0.07, "tension": 0.7, "color": SnakeRows.CYAN}
	o.merge(opts, true)
	return SnakeTendril.fire(_hand(side), target, o)


func _center_fn(en: Node3D) -> Callable:
	var last := [en.global_position + Vector3(0.0, 0.9, 0.0)]
	return func() -> Vector3:
		if is_instance_valid(en) and en.is_inside_tree():
			last[0] = SnakeAim.center_of(en)
		return last[0]


func _fwd() -> Vector3:
	var yaw := p.camera_rig.yaw
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _front(dist: float) -> Vector3:
	return p.global_position + _fwd() * dist


func _dmg(base: float) -> float:
	return TestMode.damage(base * war.dmg_mult())


func _hurt(en: Node3D, amount: float, marker := true) -> void:
	if not is_instance_valid(en) or bool(en.get(&"dead")):
		return
	en.call(&"damage", amount)
	BlastCredit.dealt(en, amount, Vector3.INF, marker)


func _swarm() -> SnakeSwarm:
	return war.swarm


func _level_msg(text: String) -> void:
	Game.say(text, 1.0)


func reset() -> void:
	cancel_holds()
	_end_shield(false)
	_end_decoy(false)
	for t in trap_list:
		_drop_trap(t)
	trap_list.clear()
	_end_guard()
	_end_loan(true)
	for f in _flights:
		_land_node(f)
	_flights.clear()
	_pickups.clear()
	_kick.clear()
	_lash_step = 0
	_lash_cd = 0.0
	if _proxy != null and is_instance_valid(_proxy):
		_proxy.visible = false


func cancel_holds() -> void:
	if not _grab.is_empty():
		_grab_release(true)
	_fire_hold = false


func is_grabbing() -> bool:
	return not _grab.is_empty()


func grab_node() -> Node3D:
	return _grab.get("node") as Node3D


func grab_position() -> Vector3:
	return _grab_pos(_grab) if not _grab.is_empty() else Vector3.ZERO


## A rifleman shot the snake that holds the body: it drops.
func cut_grab() -> void:
	if not _grab.is_empty():
		var tn := _grab.get("tendril") as SnakeTendril
		if tn != null:
			tn.kill()
		_grab_release(true)


## A jammer: every snake that is not in the hero's hand fades.
func jam_drop() -> void:
	_end_shield(true)
	_end_guard()


# --- the input of an armed verb -----------------------------------------------------------------------------------------------------

func handle(id: StringName, pressed: bool, held: bool, released: bool, alt_pressed: bool, dt: float) -> void:
	match id:
		&"sv_grab":
			if pressed and _grab.is_empty():
				war.cast(id)
			if not _grab.is_empty() and (released or not held):
				_grab_release(false)
			if alt_pressed and not _grab.is_empty():
				_grab_release(true)
		&"sv_lash":
			if held or pressed:
				_lash(alt_pressed)
		&"sv_pull":
			if pressed:
				war.cast(id)
			elif alt_pressed:
				_pull(true)
		_:
			if pressed:
				war.cast(id)


## Casts verb `id` (the checks are done by SnakeWar.cast). True when it went off.
func press(id: StringName, force := false) -> bool:
	match id:
		&"sv_pull": return _pull(false, force)
		&"sv_grab": return _grab_start(force)
		&"sv_disarm": return _disarm(force)
		&"sv_yank": return _yank(force)
		&"sv_net": return _net(force)
		&"sv_lash": return _lash(false, force)
		&"sv_shield": return _shield(force)
		&"sv_decoy": return _decoy(force)
		&"sv_trap": return _trap(force)
		&"sv_guard": return _guard(force)
	return false


## What the crosshair is on for the armed verb (the lock bracket reads it).
func preview_target(id: StringName) -> Dictionary:
	var reach := float(SnakeRows.row(id).get("range", 30.0))
	match id:
		&"sv_pull": return SnakeAim.pick(p, reach, [&"enemy", &"pickup", &"prop", &"car"])
		&"sv_grab": return SnakeAim.pick(p, reach, [&"enemy", &"car", &"prop"])
		&"sv_disarm", &"sv_lash": return SnakeAim.pick(p, reach, [&"enemy"], 0.3)
		&"sv_yank": return SnakeAim.pick(p, reach, [&"car", &"prop"])
	return {}


# --- SNAKE PULL ------------------------------------------------------------------------------------------------------------------------

func _pull(zip_to: bool, force := false) -> bool:
	if zip_to and not war.can_cast(&"sv_pull", force):
		return false
	var row := SnakeRows.row(&"sv_pull")
	var t := SnakeAim.pick(p, float(row["range"]), [&"enemy", &"pickup", &"prop", &"car"])
	if t.is_empty():
		var pt := SnakeAim.point(p, 18.0)
		_tendril(1, pt, {"travel": 0.1, "life": 0.05, "tension": 0.3, "color": Color(0.5, 0.6, 0.7)})
		war.note_whiff(&"sv_pull", "NOTHING TO PULL")
		return false
	var kind: StringName = t["kind"]
	var node := t["node"] as Node3D
	var pos: Vector3 = t["pos"]
	war.commit(&"sv_pull", pos)
	pulls += 1
	Sfx.play(&"snw_pull", -3.0)
	var hero_goes := zip_to or kind == &"car" or (kind == &"enemy" and SnakeAim.heavy(node))
	if kind == &"enemy" and not hero_goes:
		var to := _front(2.3)
		to.y = p.global_position.y
		var en := node
		var tn := _tendril(1, _center_fn(en), {"travel": 0.08, "life": 0.0, "tension": 0.95, "thickness": 0.085, "color": SnakeRows.CYAN})
		tn.user["keep"] = true
		war.holds.drag(en, to, 0.34, 1.5)
		_hurt(en, _dmg(14.0))
		var tref := tn
		_after(0.5, func() -> void:
			if tref != null and tref.is_alive():
				tref.retract(0.15))
	elif hero_goes:
		_zip_to(t)
	elif kind == &"pickup":
		var slot: Dictionary = {}
		for s: Variant in Game.missions.pickups:
			if s is Dictionary and (s as Dictionary).get("pos") == pos:
				slot = s as Dictionary
		if not slot.is_empty():
			_pickups.append({"slot": slot, "from": pos, "t": 0.0})
		_tendril(1, pos, {"travel": 0.08, "life": 0.2, "tension": 0.9, "color": SnakeRows.GOLD})
	elif kind == &"prop":
		_tear_prop(int(t["idx"]), true)
		_tendril(1, pos, {"travel": 0.08, "life": 0.2, "tension": 0.9, "color": SnakeRows.GREEN})
	FX.burst(pos, SnakeRows.CYAN, 6, 4.0, 0.3, 2.0, 0.9)
	return true


## The hero rides a snake to a heavy target and lands in front of it (the kick of the landing hurts it).
func _zip_to(t: Dictionary) -> void:
	var node := t["node"] as Node3D
	var target: Vector3 = t["pos"]
	var from := p.global_position
	var away := Vector3(from.x - target.x, 0.0, from.z - target.z)
	away = away.normalized() if away.length() > 0.1 else -_fwd()
	var stand := 2.4 if t["kind"] == &"car" else 1.9
	var dest := Vector3(target.x, node.global_position.y if node != null else target.y, target.z) + away * stand
	var hit := {"kind": &"ground", "pos": target, "dest": dest, "normal": Vector3.UP, "node": node}
	zips += 1
	if p.snake.has_method(&"_start_zip"):
		p.snake.call(&"_start_zip", hit)
		_kick = {"node": node, "left": 2.0, "kind": t["kind"]}
	else:
		p.global_position = dest


func _on_zip_landed() -> void:
	var n := _kick.get("node") as Node3D
	_kick.clear()
	if n == null or not is_instance_valid(n) or bool(n.get(&"dead")):
		return
	if n.is_in_group(&"vehicle"):
		n.call(&"damage", _dmg(60.0))
		var ops := BlastOps.shared(p.get_tree())
		if ops != null:
			ops.shove_vehicle(n, (n.global_position - p.global_position).normalized() * Vector3(1, 0, 1), 6.0, 1.5, p.global_position)
	else:
		_hurt(n, _dmg(55.0))
		if n.has_method(&"stagger"):
			n.call(&"stagger", 1.5)
		war.holds.hold(n, 1.4, {"kind": &"snare", "coils": 1})
	FX.burst(n.global_position + Vector3(0.0, 1.0, 0.0), SnakeRows.CYAN, 10, 6.0, 0.4, 3.0, 1.1)
	Sfx.play_at(&"snw_slam", n.global_position, -8.0)
	FX.shake(0.25)


func on_drag_done(en: Node3D) -> void:
	if is_instance_valid(en):
		FX.burst(en.global_position + Vector3(0.0, 0.9, 0.0), SnakeRows.CYAN, 6, 4.0, 0.3, 1.0, 0.9)


# props and pickups ----------------------------------------------------------------------------------------------------------------------

func _tear_prop(i: int, toward_hero: bool) -> void:
	var bk := Breakables.current
	if bk == null or i < 0 or i >= bk.positions.size() or bk.broken[i] != 0:
		return
	var kd: Dictionary = Breakables.KINDS[bk.kind_of[i]]
	var from: Vector3 = bk.positions[i]
	bk.take_prop(i)
	var target := p.global_position + Vector3(0.0, 0.2, 0.0) + _fwd() * 1.4
	var vel := (target - from) / 0.55 + Vector3(0.0, 0.5 * 22.0 * 0.55, 0.0) if toward_hero else (from - p.global_position).normalized() * 10.0 + Vector3.UP * 4.0
	bk.fling(from, vel, kd["color"], clampf((kd["size"] as Vector3).x, 0.3, 0.9))
	bk.fling(from + Vector3(0.0, 0.2, 0.0), vel * 0.8 + Vector3(randf_range(-1.5, 1.5), 1.0, randf_range(-1.5, 1.5)), kd["color"], 0.28)


func _tick_pickups(dt: float) -> void:
	var i := _pickups.size() - 1
	while i >= 0:
		var r := _pickups[i]
		var slot: Dictionary = r["slot"]
		r["t"] = float(r["t"]) + dt
		var k := clampf(float(r["t"]) / 0.45, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		var pos := (r["from"] as Vector3).lerp(p.global_position + Vector3(0.0, 0.9, 0.0), k)
		slot["pos"] = pos
		if slot.get("node") is Node3D and is_instance_valid(slot["node"]):
			(slot["node"] as Node3D).global_position = pos
		if k >= 1.0 or not Game.missions.pickups.has(slot):
			_pickups.remove_at(i)
		i -= 1


# --- SNAKE GRAB ------------------------------------------------------------------------------------------------------------------------

func _grab_start(force := false) -> bool:
	if not _grab.is_empty():
		return false
	var row := SnakeRows.row(&"sv_grab")
	var t := SnakeAim.pick(p, float(row["range"]), [&"enemy", &"car", &"prop"])
	if t.is_empty():
		war.note_whiff(&"sv_grab", "NOTHING TO GRAB")
		return false
	var node := t["node"] as Node3D
	if t["kind"] == &"enemy" and SnakeAim.is_boss(node):
		war.note_whiff(&"sv_grab", "TOO BIG TO LIFT")
		if node.has_method(&"stagger"):
			node.call(&"stagger", 1.0)
		return false
	war.commit(&"sv_grab", t["pos"])
	grabs += 1
	Sfx.play(&"snw_grab", -3.0)
	var g := {"node": node, "kind": t["kind"], "idx": int(t["idx"]), "lift": 0.0, "from": t["pos"], "t": 0.0, "layer": 0, "tendril": null, "coils": []}
	if t["kind"] == &"enemy":
		war.holds.lift(node)
	elif t["kind"] == &"car":
		g["layer"] = (node as CollisionObject3D).collision_layer
		(node as CollisionObject3D).collision_layer = 0
		_wrap_car(g, node)
	elif t["kind"] == &"prop":
		_take_prop_proxy(g)
	var cf: Callable = _center_fn(node) if node != null else (func() -> Vector3: return _hold_point())
	var tn := _tendril(1, (func() -> Vector3: return _grab_pos(g)), {"travel": 0.09, "tension": 0.95, "thickness": 0.095, "color": SnakeRows.MAGENTA, "life": 0.0})
	tn.user["keep"] = true
	g["tendril"] = tn
	_grab = g
	FX.burst(t["pos"], SnakeRows.MAGENTA, 8, 5.0, 0.35, 1.0, 1.0)
	return true


func _wrap_car(g: Dictionary, car: Node3D) -> void:
	var sw := _swarm()
	if sw == null:
		return
	for k in 2:
		var b := sw.spawn(&"coil", car.global_position, {"anchor": car, "radius": 1.25, "y0": 0.1, "y1": 1.4, "turns": 2.0, "spin": 2.0 + float(k), "phase": PI * float(k), "color": SnakeRows.MAGENTA, "thick": 0.1, "len": 9.0, "life": GRAB_MAX + 1.0, "prio": 2})
		if b != null:
			(g["coils"] as Array).append(b)


func _take_prop_proxy(g: Dictionary) -> void:
	var bk := Breakables.current
	var i := int(g["idx"])
	if bk == null or i < 0 or i >= bk.positions.size():
		return
	var kd: Dictionary = Breakables.KINDS[bk.kind_of[i]]
	bk.take_prop(i)
	if _proxy == null or not is_instance_valid(_proxy):
		_proxy = MeshInstance3D.new()
		_proxy.mesh = BoxMesh.new()
		_proxy.top_level = true
		_proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.emission_enabled = true
		m.emission = SnakeRows.MAGENTA
		m.emission_energy_multiplier = 0.5
		_proxy.material_override = m
		p.add_child(_proxy)
	(_proxy.material_override as StandardMaterial3D).albedo_color = kd["color"]
	_proxy.scale = kd["size"]
	_proxy.global_position = g["from"]
	_proxy.visible = true


func _hold_point() -> Vector3:
	var big: bool = not _grab.is_empty() and _grab["kind"] == &"car"
	return p.global_position + _fwd() * (4.6 if big else 2.7) + Vector3.UP * (2.0 + (1.1 if big else 0.0))


func _grab_pos(g: Dictionary) -> Vector3:
	var node := g.get("node") as Node3D
	if g["kind"] == &"prop":
		return _proxy.global_position if _proxy != null else _hold_point()
	if node != null and is_instance_valid(node):
		return SnakeAim.center_of(node)
	return _hold_point()


func _grab_tick(dt: float) -> void:
	var g := _grab
	g["t"] = float(g["t"]) + dt
	g["lift"] = minf(1.0, float(g["lift"]) + dt / 0.25)
	var k := float(g["lift"])
	k = k * k * (3.0 - 2.0 * k)
	var pos := (g["from"] as Vector3).lerp(_hold_point(), k)
	var node := g.get("node") as Node3D
	match g["kind"]:
		&"enemy":
			if node == null or not is_instance_valid(node) or bool(node.get(&"dead")):
				_grab_release(true)
				return
			node.global_position = pos - Vector3(0.0, 0.85, 0.0)
			node.rotation.z = sin(float(g["t"]) * 5.0) * 0.18
			if node.has_method(&"disable"):
				node.call(&"disable", 0.3)
		&"car":
			if node == null or not is_instance_valid(node):
				_grab_release(true)
				return
			node.global_position = pos - Vector3(0.0, 0.7, 0.0)
			if "ai_stun" in node:
				node.set("ai_stun", 1.0)
			if node is CharacterBody3D:
				(node as CharacterBody3D).velocity = Vector3.ZERO
			if node is RigidBody3D:
				(node as RigidBody3D).linear_velocity = Vector3.ZERO
		&"prop":
			if _proxy != null:
				_proxy.global_position = pos
				_proxy.rotation = Vector3(k * 1.3, float(g["t"]) * 1.4, 0.0)
	if not SnakePower.unlimited():
		p.snake.energy = maxf(0.0, p.snake.energy - SnakePower.cost(GRAB_DRAIN) * dt)
		if p.snake.energy <= 0.01:
			_grab_release(false)
			return
	if float(g["t"]) > GRAB_MAX:
		_grab_release(false)


## Let go: a throw along the crosshair (weak = put down).
func _grab_release(weak: bool) -> void:
	if _grab.is_empty():
		return
	var g := _grab
	_grab = {}
	var node := g.get("node") as Node3D
	var from := _grab_pos(g)
	var tn := g.get("tendril") as SnakeTendril
	if tn != null:
		tn.retract(0.2)
	for b in (g["coils"] as Array):
		if b != null and not (b as SnakeSwarm.Body).dead:
			(b as SnakeSwarm.Body).life = (b as SnakeSwarm.Body).age + SnakeSwarm.FADE
	if g["kind"] == &"enemy":
		war.holds.release(node, 0.0 if weak else 0.8)
	if node != null and is_instance_valid(node):
		node.rotation.z = 0.0
	var aim_dir: Vector3 = SnakeAim.ray(p)[1]
	var speed := THROW_SPEED * (0.62 if g["kind"] == &"car" else 1.0) * (0.05 if weak else 1.0)
	_flights.append({"node": node, "kind": g["kind"], "pos": from, "vel": aim_dir * speed + Vector3.UP * (2.5 if not weak else 0.0), "t": 0.0, "layer": g["layer"], "weak": weak})
	throws += 1
	if not weak:
		Sfx.play(&"snw_throw", -2.0)
		p.camera_rig.kick(0.04)
		FX.burst(from, SnakeRows.MAGENTA, 8, 7.0, 0.3, 1.0, 1.0)


func _flight_tick(dt: float) -> void:
	var i := _flights.size() - 1
	while i >= 0:
		if _fly(_flights[i], dt):
			_flights.remove_at(i)
		i -= 1
	if _flights.is_empty() and _grab.is_empty() and _proxy != null and is_instance_valid(_proxy) and _proxy.visible:
		_proxy.visible = false


func _fly(f: Dictionary, dt: float) -> bool:
	var kind: StringName = f["kind"]
	var node := f.get("node") as Node3D
	if kind != &"prop" and (node == null or not is_instance_valid(node)):
		return true
	var vel: Vector3 = f["vel"]
	vel.y -= THROW_GRAVITY * dt
	var pos: Vector3 = f["pos"]
	var next := pos + vel * dt
	f["t"] = float(f["t"]) + dt
	_rq.from = pos
	_rq.to = next + vel.normalized() * 0.4
	var hit := p.get_world_3d().direct_space_state.intersect_ray(_rq)
	var done := float(f["t"]) > 3.0
	if not hit.is_empty():
		next = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * 0.35
		done = true
	elif not bool(f["weak"]):
		for e: Node3D in Gear.living_enemies(p.get_tree()):
			if e != node and SnakeAim.center_of(e).distance_to(next) < 1.6:
				done = true
				break
	f["vel"] = vel
	f["pos"] = next
	match kind:
		&"prop":
			if _proxy != null:
				_proxy.global_position = next
				_proxy.rotation += Vector3(7.0, 5.0, 0.0) * dt
		&"enemy":
			node.global_position = next - Vector3(0.0, 0.85, 0.0)
			node.rotation.x += 6.0 * dt
		_:
			node.global_position = next - Vector3(0.0, 0.7, 0.0)
	if not done:
		return false
	_impact(f)
	return true


func _impact(f: Dictionary) -> void:
	var node := f.get("node") as Node3D
	var pos: Vector3 = f["pos"]
	var kind: StringName = f["kind"]
	if node != null and is_instance_valid(node):
		node.rotation.x = 0.0
		node.rotation.z = 0.0
	if not bool(f["weak"]):
		slams += 1
		BlastTable.apply(SnakeRows.SLAM, pos, p, {"by_hero": true, "dmg_mult": war.dmg_mult(), "radius_mult": war.radius_mult()})
		if node != null and is_instance_valid(node) and not bool(node.get(&"dead")):
			if kind == &"enemy":
				_hurt(node, _dmg(60.0))
				war.holds.hold(node, 1.8, {"kind": &"snare", "coils": 1})
			elif kind == &"car":
				node.call(&"damage", _dmg(90.0))
		Sfx.play_at(&"snw_slam", pos, -2.0)
		FX.shake(0.4)
	_land_node(f)


func _land_node(f: Dictionary) -> void:
	var node := f.get("node") as Node3D
	if f["kind"] == &"prop" or node == null or not is_instance_valid(node):
		return
	_rq.from = node.global_position + Vector3.UP * 1.0
	_rq.to = _rq.from + Vector3.DOWN * 60.0
	var r := p.get_world_3d().direct_space_state.intersect_ray(_rq)
	if not r.is_empty():
		node.global_position = (r["position"] as Vector3) + Vector3(0.0, 0.05, 0.0)
	if node.is_in_group(&"vehicle") and node is CollisionObject3D and (node as CollisionObject3D).collision_layer == 0:
		(node as CollisionObject3D).collision_layer = int(f["layer"]) if int(f["layer"]) != 0 else Game.L_VEHICLE


# --- SNAKE DISARM ------------------------------------------------------------------------------------------------------------------------

func _disarm(force := false) -> bool:
	var row := SnakeRows.row(&"sv_disarm")
	var t := SnakeAim.pick(p, float(row["range"]), [&"enemy"], 0.3)
	if t.is_empty():
		war.note_whiff(&"sv_disarm", "NO ONE TO DISARM")
		return false
	var en := t["node"] as Node3D
	var armed_foe := en is Operative or en.get(&"hanim") != null
	war.commit(&"sv_disarm", t["pos"])
	disarms += 1
	Sfx.play(&"snw_pull", -3.0)
	var hand := p.snake.hand_pos(1)
	var tn := _tendril(1, _center_fn(en), {"travel": 0.07, "life": 0.0, "tension": 0.9, "color": SnakeRows.AMBER, "thickness": 0.07})
	var wid: StringName = LOAN_BY_TYPE.get(en.get(&"type"), &"carbine")
	var en_ref := en
	tn.attached.connect(func() -> void:
		if is_instance_valid(en_ref):
			war.holds.disarm(en_ref, 10.0)
			_snatch_visual(en_ref, wid)
		tn.retract(0.18))
	if armed_foe:
		_begin_loan(wid)
	else:
		Game.say("NO GUN TO TAKE  STUNNED", 1.0)
		war.holds.hold(en, 1.6, {"kind": &"snare", "coils": 1, "color": SnakeRows.AMBER})
	return true


func _snatch_visual(en: Node3D, wid: StringName) -> void:
	var from := SnakeAim.center_of(en) + Vector3(0.0, 0.1, 0.0)
	var mesh: Mesh = WeaponModels.mesh(wid) if WeaponModels.has_model(wid) else null
	if mesh == null:
		FX.burst(from, SnakeRows.AMBER, 8, 5.0, 0.35, 1.0, 1.0)
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = WeaponModels.hand_material(wid)
	mi.top_level = true
	mi.scale = WeaponModels.look_scale(wid)
	p.add_child(mi)
	mi.global_position = from
	var tw := mi.create_tween()
	tw.tween_method(_snatch_step.bind(mi, from), 0.0, 1.0, 0.28)
	tw.tween_callback(mi.queue_free)
	FX.burst(from, SnakeRows.AMBER, 8, 5.0, 0.35, 1.0, 1.0)


func _snatch_step(k: float, mi: MeshInstance3D, from: Vector3) -> void:
	if is_instance_valid(mi):
		mi.global_position = from.lerp(p.snake.hand_pos(1), k * k * (3.0 - 2.0 * k))
		mi.rotation.y += 0.5


func _begin_loan(wid: StringName) -> void:
	if not WeaponDefs.DEFS.has(wid) or p.weapon == null:
		return
	var w := p.weapon
	if loan.is_empty():
		loan = {"id": wid, "left": LOAN_SECONDS, "prev": w.current, "owned": WeaponDefs.is_unlocked(wid)}
	else:
		loan["left"] = LOAN_SECONDS
	if not WeaponDefs.unlocked.has(wid):
		WeaponDefs.unlocked.append(wid)
	loans += 1
	war.disarm()
	w.switch_to(wid, true)
	Game.say("TOOK THEIR GUN  %s  %d S" % [WeaponDefs.title(wid), int(LOAN_SECONDS)], 1.8)


func _end_loan(quiet := false) -> void:
	if loan.is_empty():
		return
	var id: StringName = loan["id"]
	var prev: StringName = loan["prev"]
	var owned: bool = loan["owned"]
	loan = {}
	if not owned:
		WeaponDefs.unlocked.erase(id)
	if p != null and p.weapon != null and p.weapon.current == id:
		p.weapon.switch_to(prev if WeaponDefs.is_unlocked(prev) else &"carbine", true)
		if not quiet:
			Game.say("THE GUN CRUMBLES  BACK TO %s" % WeaponDefs.title(p.weapon.current), 1.4)


# --- YANK COVER --------------------------------------------------------------------------------------------------------------------------

func _yank(force := false) -> bool:
	var row := SnakeRows.row(&"sv_yank")
	var t := SnakeAim.pick(p, float(row["range"]), [&"car", &"prop"])
	if t.is_empty():
		war.note_whiff(&"sv_yank", "NO COVER TO TEAR")
		return false
	var pos: Vector3 = t["pos"]
	war.commit(&"sv_yank", pos)
	yanks += 1
	Sfx.play(&"snw_pull", -3.0)
	var tn := _tendril(-1, pos, {"travel": 0.08, "life": 0.0, "tension": 0.95, "thickness": 0.09, "color": SnakeRows.GREEN})
	var kind: StringName = t["kind"]
	var node := t["node"] as Node3D
	var idx := int(t["idx"])
	var from_hero := (pos - p.global_position)
	from_hero.y = 0.0
	from_hero = from_hero.normalized() if from_hero.length() > 0.1 else _fwd()
	tn.attached.connect(func() -> void:
		var foes: Array[Node3D] = []
		for e: Node3D in Gear.living_enemies(p.get_tree()):
			var c := SnakeAim.center_of(e)
			if c.distance_to(pos) <= 7.0 and (c - p.global_position).dot(from_hero) > (pos - p.global_position).dot(from_hero) - 2.0:
				foes.append(e)
		var dir := from_hero
		if not foes.is_empty():
			var d2 := SnakeAim.center_of(foes[0]) - pos
			d2.y = 0.0
			if d2.length() > 0.5:
				dir = d2.normalized()
		if kind == &"car" and node != null and is_instance_valid(node):
			var ops := BlastOps.shared(p.get_tree())
			if ops != null:
				ops.shove_vehicle(node, dir, 15.0, 5.0, pos)
			node.call(&"damage", _dmg(120.0))
		elif kind == &"prop":
			_tear_prop(idx, false)
			var bk := Breakables.current
			if bk != null:
				bk.fling(pos, dir * 14.0 + Vector3.UP * 3.0, Color(0.6, 0.62, 0.6), 0.5)
		for e in foes:
			_hurt(e, _dmg(38.0))
			if e.has_method(&"stagger"):
				e.call(&"stagger", 1.4)
			war.holds.hold(e, 1.2, {"kind": &"snare", "coils": 1, "color": SnakeRows.GREEN})
		Sfx.play_at(&"snw_slam", pos, -4.0)
		FX.burst(pos + Vector3(0.0, 0.6, 0.0), SnakeRows.GREEN, 12, 7.0, 0.4, 3.0, 1.2)
		FX.shake(0.3)
		tn.retract(0.2))
	return true


# --- SNAKE NET ---------------------------------------------------------------------------------------------------------------------------

func _net(force := false) -> bool:
	var row := SnakeRows.row(&"sv_net")
	var reach := float(row["range"])
	var t := SnakeAim.pick(p, reach, [&"enemy"], 0.3)
	var at: Vector3 = t["pos"] if not t.is_empty() else SnakeAim.point(p, reach)
	if not t.is_empty():
		at.y = (t["node"] as Node3D).global_position.y
	var radius := float(row["radius"]) * war.radius_mult()
	war.commit(&"sv_net", at)
	nets += 1
	Sfx.play(&"snw_net", -3.0)
	var tn := _tendril(1, at, {"travel": 0.16, "life": 0.0, "tension": 0.6, "thickness": 0.08, "color": SnakeRows.VIOLET})
	tn.attached.connect(func() -> void:
		_net_land(at, radius)
		tn.retract(0.2))
	return true


func _net_land(at: Vector3, radius: float) -> int:
	var sw := _swarm()
	if sw != null:
		for k in 2:
			sw.spawn(&"ring", at, {"radius": radius * (1.0 - 0.28 * float(k)), "thick": 0.07, "len": radius * 5.0, "color": SnakeRows.VIOLET, "life": 3.2, "spin": 1.6 if k == 0 else -1.9, "phase": float(k) * 1.7, "rise_t": 0.28, "prio": 1})
	var caught := 0
	for e: Node3D in Gear.living_enemies(p.get_tree()):
		if e.get(&"friendly") == true:
			continue
		var d := Vector2(e.global_position.x - at.x, e.global_position.z - at.z).length()
		if d <= radius and absf(e.global_position.y - at.y) < 6.0:
			if war.holds.hold(e, 4.5, {"kind": &"net", "dps": 5.0, "coils": 2, "color": SnakeRows.VIOLET, "disarm": true}):
				caught += 1
				_hurt(e, _dmg(10.0), false)
			elif e.has_method(&"stagger"):
				e.call(&"stagger", 1.0)
	FX.burst(at + Vector3(0.0, 0.3, 0.0), SnakeRows.VIOLET, 14, 7.0, 0.5, 2.0, 1.2)
	FX.shake(0.2)
	Sfx.play_at(&"snw_net", at, -4.0)
	return caught


# --- SNAKE LASH --------------------------------------------------------------------------------------------------------------------------

func _lash(alt := false, force := false) -> bool:
	if _lash_cd > 0.0:
		return false
	var target: Node3D = null
	var best := INF
	var o: Vector3 = SnakeAim.ray(p)[0]
	var d: Vector3 = SnakeAim.ray(p)[1]
	for e: Node3D in SnakeAim.enemies_near(p, LASH_RANGE):
		var c := SnakeAim.center_of(e)
		var ang := d.angle_to((c - o).normalized())
		if ang < 0.62 and ang < best:
			best = ang
			target = e
	if target == null:
		_lash_cd = 0.22
		_lash_whip()
		return false
	if not war.can_cast(&"sv_lash", force):
		return false
	war.commit(&"sv_lash", SnakeAim.center_of(target))
	war.cd.erase(&"sv_lash")
	_lash_cd = SnakePower.cd(0.3) + 0.07
	_lash_step = _lash_step + 1 if _lash_t > 0.0 else 1
	_lash_t = LASH_COMBO_GAP
	lashes += 1
	_lash_side = -_lash_side
	var step := _lash_step
	var finisher := step >= 4 or (alt and step >= 2)
	var en := target
	var tn := _tendril(_lash_side, _center_fn(en), {"travel": 0.05, "life": 0.0, "tension": 0.9, "thickness": 0.06 + 0.012 * float(mini(step, 4)), "wriggle": 0.25,
			"color": SnakeRows.CYAN if not finisher else SnakeRows.MAGENTA})
	Sfx.play(&"snw_lash", -4.0, 0.94 + 0.05 * float(mini(step, 4)))
	tn.attached.connect(func() -> void:
		_lash_hit(en, step, finisher)
		tn.retract(0.1))
	if _lash_step >= 4:
		_lash_step = 0
	return true


func _lash_whip() -> void:
	var pt: Vector3 = SnakeAim.point(p, 6.0)
	_lash_side = -_lash_side
	_tendril(_lash_side, pt, {"travel": 0.05, "life": 0.04, "tension": 0.3, "thickness": 0.05, "wriggle": 0.5})
	Sfx.play(&"snw_lash", -9.0, 0.8)


func _lash_hit(en: Node3D, step: int, finisher: bool) -> void:
	if not is_instance_valid(en) or bool(en.get(&"dead")):
		return
	var c := SnakeAim.center_of(en)
	var stunned: bool = en.has_method(&"is_disabled") and bool(en.call(&"is_disabled"))
	if (finisher and stunned and not SnakeAim.is_boss(en)) or (stunned and step >= 3 and not SnakeAim.is_boss(en)):
		takedowns += 1
		var hp := float(en.get(&"hp")) if en.get(&"hp") != null else 100.0
		_hurt(en, hp + 5.0)
		Game.say("SNAKE TAKEDOWN", 0.9)
		FX.burst(c, SnakeRows.MAGENTA, 14, 8.0, 0.5, 3.0, 1.3)
		Sfx.play_at(&"snw_slam", c, -5.0)
		return
	var base: float = [26.0, 30.0, 38.0, 70.0][clampi(step - 1, 0, 3)]
	_hurt(en, _dmg(base))
	bites += 1
	if en.has_method(&"stagger"):
		en.call(&"stagger", 0.9 + 0.3 * float(step))
	FX.burst(c, SnakeRows.CYAN, 6 + 2 * step, 5.0, 0.3, 1.0, 1.0)
	Sfx.play_at(&"snw_hit", c, -4.0, 0.9 + 0.06 * float(step))
	p.camera_rig.kick(0.012 + 0.006 * float(step))
	if finisher:
		finishers += 1
		BlastTable.apply(SnakeRows.LASH_FINISH, c, p, {"by_hero": true, "dmg_mult": war.dmg_mult(), "radius_mult": war.radius_mult(), "quiet": false})
		FX.shake(0.25)
	# the lash chains to a second enemy within 4.5 m for half the damage
	var best: Node3D = null
	var bd := 4.5
	for e: Node3D in SnakeAim.enemies_near(p, LASH_RANGE + 4.0):
		if e == en:
			continue
		var dd := SnakeAim.center_of(e).distance_to(c)
		if dd < bd:
			bd = dd
			best = e
	if best != null:
		_hurt(best, _dmg(base * 0.5), false)
		if best.has_method(&"stagger"):
			best.call(&"stagger", 0.8)
		if FX.qvfx != null:
			FX.qvfx.bolt(c, SnakeAim.center_of(best), SnakeRows.CYAN)


# --- SNAKE SHIELD ------------------------------------------------------------------------------------------------------------------------

func _shield(force := false) -> bool:
	war.commit(&"sv_shield")
	shields += 1
	Sfx.play(&"snw_shield_up", -3.0)
	_end_shield(false)
	var sw := _swarm()
	var bodies: Array = []
	if sw != null:
		for k in 3:
			var b := sw.spawn(&"orbit", p.global_position, {"anchor": p, "radius": 1.15, "y0": 0.45, "y1": 1.55, "spin": 3.4, "phase": TAU * float(k) / 3.0, "span": 2.0, "color": SnakeRows.CYAN, "thick": 0.08,
					"len": 2.5, "life": SHIELD_SECONDS, "prio": 3, "stick": true, "head": 1.0, "rate": 1.2})
			if b != null:
				bodies.append(b)
	shield = {"left": SHIELD_SECONDS, "hp": SHIELD_POOL * (1.0 if not SnakePower.unlimited() else 3.0), "bodies": bodies, "bite_t": 0.0, "flare": 0.0}
	FX.burst(p.global_position + Vector3(0.0, 1.0, 0.0), SnakeRows.CYAN, 14, 6.0, 0.5, 1.0, 1.1)
	return true


## Player.damage asks first: True = the hit is eaten by the snakes.
func shield_absorb(amount: float, from_pos: Vector3) -> bool:
	if shield.is_empty() or float(shield["hp"]) <= 0.0:
		return false
	shield["hp"] = float(shield["hp"]) - amount
	blocks += 1
	var chest := p.global_position + Vector3(0.0, 1.2, 0.0)
	var dir := (from_pos - chest) if from_pos != Vector3.ZERO else _fwd()
	dir = dir.normalized() if dir.length() > 0.1 else _fwd()
	FX.burst(chest + dir * 1.15, SnakeRows.CYAN, 9, 5.0, 0.3, 1.0, 1.1)
	Sfx.play_at(&"snw_shield_hit", chest + dir, -3.0)
	shield["flare"] = 0.25
	UiSettings.buzz(18)
	if float(shield["hp"]) <= 0.0:
		_end_shield(true)
		Game.say("SHIELD BROKEN", 0.9)
	return true


func _end_shield(burst: bool) -> void:
	if shield.is_empty():
		return
	for b in (shield["bodies"] as Array):
		if b != null and not (b as SnakeSwarm.Body).dead:
			(b as SnakeSwarm.Body).life = (b as SnakeSwarm.Body).age + SnakeSwarm.FADE
			(b as SnakeSwarm.Body).stick = false
	if burst and p != null:
		FX.burst(p.global_position + Vector3(0.0, 1.0, 0.0), SnakeRows.CYAN, 16, 8.0, 0.5, 2.0, 1.2)
	shield = {}


func _tick_shield(dt: float) -> void:
	if shield.is_empty():
		return
	shield["left"] = float(shield["left"]) - dt
	shield["bite_t"] = float(shield["bite_t"]) - dt
	if float(shield["left"]) <= 0.0:
		_end_shield(false)
		return
	if float(shield["bite_t"]) <= 0.0:
		for e: Node3D in SnakeAim.enemies_near(p, 3.4):
			shield["bite_t"] = 0.7
			bites += 1
			var c := SnakeAim.center_of(e)
			_hurt(e, _dmg(20.0))
			if e.has_method(&"stagger"):
				e.call(&"stagger", 1.0)
			FX.burst(c, SnakeRows.CYAN, 6, 4.0, 0.3, 1.0, 1.0)
			Sfx.play_at(&"snw_hit", c, -6.0)
			var tn := _tendril(1 if bites % 2 == 0 else -1, _center_fn(e), {"travel": 0.05, "life": 0.0, "tension": 0.8, "thickness": 0.06, "color": SnakeRows.CYAN})
			tn.attached.connect(func() -> void: tn.retract(0.08))
			break


# --- SNAKE DECOY ---------------------------------------------------------------------------------------------------------------------------

static func decoy_node() -> Node3D:
	return decoy_ref if is_instance_valid(decoy_ref) and decoy_ref.is_inside_tree() else null


## A bolt crossed the decoy's column (EnemyManager.hit_clone): True when the decoy took it.
static func decoy_hit(c: Node3D) -> bool:
	var war := SnakeWar.instance
	if war == null or c == null or c != decoy_ref:
		return false
	return war.verbs._hit_decoy()


func _hit_decoy() -> bool:
	if decoy.is_empty():
		return false
	decoy_hits += 1
	decoy["hp"] = float(decoy["hp"]) - 26.0
	FX.burst((decoy["node"] as Node3D).global_position + Vector3(0.0, 1.0, 0.0), SnakeRows.MAGENTA, 6, 4.0, 0.3, 1.0, 1.0)
	Sfx.play_at(&"snw_shield_hit", (decoy["node"] as Node3D).global_position, -6.0)
	if float(decoy["hp"]) <= 0.0:
		_end_decoy(true)
	return true


func _decoy(force := false) -> bool:
	var row := SnakeRows.row(&"sv_decoy")
	var at := SnakeAim.point(p, float(row["range"]))
	_rq.from = at + Vector3.UP * 2.0
	_rq.to = at + Vector3.DOWN * 8.0
	var g := p.get_world_3d().direct_space_state.intersect_ray(_rq)
	if not g.is_empty():
		at = g["position"]
	war.commit(&"sv_decoy", at)
	decoys += 1
	Sfx.play(&"snw_decoy", -3.0)
	_end_decoy(false)
	var node := Node3D.new()
	node.name = "SnakeDecoy"
	node.top_level = true
	p.add_child(node)
	node.global_position = at
	node.rotation.y = p.yaw
	var sw := _swarm()
	var bodies: Array = []
	if sw != null:
		for k in 3:
			var b := sw.spawn(&"coil", at, {"anchor": node, "radius": 0.38 + 0.07 * float(k % 2), "y0": 0.05, "y1": 1.72 - 0.08 * float(k), "turns": 3.0, "spin": 2.6 + 0.4 * float(k), "phase": TAU * float(k) / 3.0,
					"color": SnakeRows.MAGENTA, "thick": 0.075, "len": 7.0, "life": DECOY_SECONDS + SkillTree.snakewar_grip(), "prio": 2, "head": 1.0})
			if b != null:
				bodies.append(b)
		var r := sw.spawn(&"ring", at, {"radius": 0.95, "thick": 0.05, "len": 4.0, "color": SnakeRows.MAGENTA, "life": DECOY_SECONDS + SkillTree.snakewar_grip(), "spin": 1.4, "prio": 1})
		if r != null:
			bodies.append(r)
	decoy = {"node": node, "left": DECOY_SECONDS + SkillTree.snakewar_grip(), "hp": DECOY_POOL, "bodies": bodies}
	decoy_ref = node
	FX.burst(at + Vector3(0.0, 1.0, 0.0), SnakeRows.MAGENTA, 14, 6.0, 0.5, 1.0, 1.1)
	_tendril(1, at + Vector3(0.0, 1.0, 0.0), {"travel": 0.14, "life": 0.1, "tension": 0.6, "color": SnakeRows.MAGENTA})
	return true


func _end_decoy(burst: bool) -> void:
	if decoy.is_empty():
		return
	for b in (decoy["bodies"] as Array):
		if b != null and not (b as SnakeSwarm.Body).dead:
			(b as SnakeSwarm.Body).life = (b as SnakeSwarm.Body).age + SnakeSwarm.FADE
	var node := decoy["node"] as Node3D
	if burst and is_instance_valid(node):
		FX.burst(node.global_position + Vector3(0.0, 1.0, 0.0), SnakeRows.MAGENTA, 16, 8.0, 0.5, 2.0, 1.2)
	if is_instance_valid(node):
		node.queue_free()
	decoy = {}
	decoy_ref = null


# --- SNAKE TRAP ----------------------------------------------------------------------------------------------------------------------------

func _trap(force := false) -> bool:
	var row := SnakeRows.row(&"sv_trap")
	var at := SnakeAim.point(p, float(row["range"]))
	_rq.from = at + Vector3.UP * 2.0
	_rq.to = at + Vector3.DOWN * 8.0
	var g := p.get_world_3d().direct_space_state.intersect_ray(_rq)
	if not g.is_empty():
		at = g["position"]
	war.commit(&"sv_trap", at)
	traps += 1
	Sfx.play(&"snw_trap", -3.0)
	var radius := float(row["radius"]) * war.radius_mult()
	while trap_list.size() >= int(TRAP_CAP[clampi(Game.quality, 0, 2)]):
		_drop_trap(trap_list.pop_front())
	var sw := _swarm()
	var body: SnakeSwarm.Body = null
	if sw != null:
		body = sw.spawn(&"ring", at, {"radius": 0.85, "thick": 0.055, "len": 3.6, "color": SnakeRows.GREEN, "life": TRAP_LIFE, "spin": 0.9, "prio": 1, "tension": 0.3, "rise_t": 0.3})
	trap_list.append({"pos": at, "radius": radius, "left": TRAP_LIFE, "body": body, "arm": 0.5})
	_tendril(1, at, {"travel": 0.14, "life": 0.05, "tension": 0.5, "color": SnakeRows.GREEN})
	FX.burst(at + Vector3(0.0, 0.2, 0.0), SnakeRows.GREEN, 8, 4.0, 0.4, 1.0, 1.0)
	return true


func _drop_trap(t: Dictionary) -> void:
	var b := t.get("body") as SnakeSwarm.Body
	if b != null and not b.dead:
		b.life = b.age + SnakeSwarm.FADE


func _tick_traps(dt: float) -> void:
	var i := trap_list.size() - 1
	while i >= 0:
		var t := trap_list[i]
		t["left"] = float(t["left"]) - dt
		t["arm"] = float(t["arm"]) - dt
		var at: Vector3 = t["pos"]
		var spring := false
		if float(t["arm"]) <= 0.0:
			for e: Node3D in Gear.living_enemies(p.get_tree()):
				if e.get(&"friendly") == true:
					continue
				if Vector2(e.global_position.x - at.x, e.global_position.z - at.z).length() <= 1.9 and absf(e.global_position.y - at.y) < 2.5:
					spring = true
					break
		if spring:
			var caught := 0
			for e: Node3D in Gear.living_enemies(p.get_tree()):
				if Vector2(e.global_position.x - at.x, e.global_position.z - at.z).length() <= float(t["radius"]) and absf(e.global_position.y - at.y) < 2.5:
					if war.holds.hold(e, 4.5, {"kind": &"wrap", "dps": 9.0, "coils": 3, "color": SnakeRows.GREEN}):
						caught += 1
						_hurt(e, _dmg(30.0))
			trap_catches += maxi(caught, 1)
			FX.burst(at + Vector3(0.0, 0.5, 0.0), SnakeRows.GREEN, 16, 7.0, 0.5, 3.0, 1.2)
			Sfx.play_at(&"snw_net", at, -3.0)
			FX.shake(0.15)
			_drop_trap(t)
			trap_list.remove_at(i)
		elif float(t["left"]) <= 0.0:
			_drop_trap(t)
			trap_list.remove_at(i)
		i -= 1


# --- SNAKE GUARD ---------------------------------------------------------------------------------------------------------------------------

func _guard(force := false) -> bool:
	war.commit(&"sv_guard")
	guards += 1
	Sfx.play(&"snw_guard", -3.0)
	_end_guard()
	var sw := _swarm()
	if sw == null:
		return true
	var n := mini(3 + war.brood_extra(), int(GUARD_CAP[clampi(Game.quality, 0, 2)]) + war.brood_extra())
	guard_left = GUARD_SECONDS
	for k in n:
		var a := TAU * float(k) / float(n)
		var at := p.global_position + Vector3(cos(a), 0.0, sin(a)) * 1.6
		var b := sw.spawn(&"crawl", at, {"color": SnakeRows.GREEN, "thick": 0.13, "len": 2.8, "life": GUARD_SECONDS, "prio": 3, "stick": true, "head": 1.0, "heading": Vector3(cos(a), 0.0, sin(a)),
				"speed": 11.0, "amp": 0.2, "tick": _guard_tick, "user": {"k": k, "bite_t": 0.0, "foe": null}})
		if b != null:
			guard_list.append(b)
	FX.burst(p.global_position + Vector3(0.0, 0.4, 0.0), SnakeRows.GREEN, 14, 6.0, 0.5, 1.0, 1.1)
	return true


func _end_guard() -> void:
	for b in guard_list:
		if b != null and not b.dead:
			b.life = b.age + SnakeSwarm.FADE
			b.stick = false
	guard_list.clear()
	guard_left = 0.0


## One guard snake: hunt the nearest enemy within 25 m (no more than two snakes on one), bite it every 0.7 s, else glide around the hero.
func _guard_tick(b: SnakeSwarm.Body, dt: float) -> bool:
	var u := b.user
	u["bite_t"] = float(u["bite_t"]) - dt
	var foe := u.get("foe") as Node3D
	if foe == null or not SnakeAim.is_live_enemy(foe) or SnakeAim.center_of(foe).distance_to(p.global_position) > 32.0:
		foe = null
		var best := 25.0
		for e: Node3D in SnakeAim.enemies_near(p, 25.0):
			var taken := 0
			for g in guard_list:
				if g != b and g.user.get("foe") == e:
					taken += 1
			if taken >= 2:
				continue
			var d := e.global_position.distance_to(p.global_position)
			if d < best:
				best = d
				foe = e
		u["foe"] = foe
	var goal: Vector3
	if foe != null:
		goal = Vector3(foe.global_position.x, foe.global_position.y + 0.15, foe.global_position.z)
	else:
		var a := b.age * 0.9 + float(u["k"]) * 2.1
		goal = p.global_position + Vector3(cos(a), 0.0, sin(a)) * 2.4
	var rest := _swarm().crawl_to(b, goal, dt, b.speed if foe != null else 5.0)
	if foe != null and rest < 1.3 and float(u["bite_t"]) <= 0.0:
		u["bite_t"] = 0.7
		guard_bites += 1
		_hurt(foe, _dmg(24.0))
		if foe.has_method(&"stagger"):
			foe.call(&"stagger", 0.8)
		b.lift = 0.6
		FX.burst(SnakeAim.center_of(foe), SnakeRows.GREEN, 5, 4.0, 0.3, 1.0, 1.0)
		Sfx.play_at(&"snw_hit", SnakeAim.center_of(foe), -6.0, 1.1)
	return true


# --- the tick ----------------------------------------------------------------------------------------------------------------------------

func tick(dt: float) -> void:
	_lash_cd = maxf(0.0, _lash_cd - dt)
	_lash_t = maxf(0.0, _lash_t - dt)
	if _lash_t <= 0.0:
		_lash_step = 0
	if not _grab.is_empty():
		_grab_tick(dt)
	if not _flights.is_empty():
		_flight_tick(dt)
	if not _pickups.is_empty():
		_tick_pickups(dt)
	_tick_shield(dt)
	_tick_traps(dt)
	if not decoy.is_empty():
		decoy["left"] = float(decoy["left"]) - dt
		if float(decoy["left"]) <= 0.0:
			_end_decoy(true)
	if not guard_list.is_empty():
		guard_left -= dt
		var alive := 0
		for b in guard_list:
			if b != null and not b.dead:
				alive += 1
		if guard_left <= 0.0 or alive == 0:
			_end_guard()
	if not loan.is_empty():
		loan["left"] = float(loan["left"]) - dt
		if float(loan["left"]) <= 0.0:
			_end_loan()
	if not _kick.is_empty():
		_kick["left"] = float(_kick["left"]) - dt
		if not p.snake.zip.active and p.snake.mode != SnakeTraversal.Mode.ZIP:
			_on_zip_landed()
		elif float(_kick["left"]) <= 0.0:
			_kick.clear()


## A tiny scheduler: runs `fn` after `secs` of game time (the verbs use it for the retract of a long tendril).
func _after(secs: float, fn: Callable) -> void:
	var tree := p.get_tree()
	if tree == null:
		return
	var t := tree.create_timer(secs, false)
	t.timeout.connect(fn)
