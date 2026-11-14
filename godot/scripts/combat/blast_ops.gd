class_name BlastOps
extends Node3D
## What happens between the trigger and the blast, and after it (wave 113). One shared node (created under the world on first use, `BlastOps.shared()`), ticking only while Game.is_playing():
##   projectiles   thrown grenades (they bounce, stick, open in the air, lure) and launched rounds (straight, lobbed, guided by lock / laser / wire / air, airburst, penetrating) of BlastRows: `deliver.mode` throw / launch
##   mines         placed charges and mines (proximity, tripwire, directional cone, gravity, timer, remote, bounce, EMP, naval): armed after `arm` seconds, set off by whoever steps near or by the DETONATE button
##   strikes       a marker lands, the ring of the true radius stays on the street, then the barrage / bombs / beam / smoke / supply crate arrives (`deliver.mode` mark)
##   ordnance      dropped bombs and shells (`drop`), the ammunition of tanks and aircraft (tank gun hook in VehicleWeapons, aircraft wave: BlastOps.drop)
##   ultimates     the hero's six (`cast`): unlocked by hero mode or the skill level, one cooldown each
##   zones         the areas a blast leaves: fire fields, smoke clouds, freeze bubbles, a well that pulls before it collapses (`pre`), supply pickups
##   bodies        knockback and lift of people (a short ballistic hop), cars shoved and tossed, burning, statuses (stun, blind, EMP, freeze, shock chains)
## Caps hold whatever the player does: MAX_ITEMS projectiles, MAX_MINES placed, MAX_ZONES areas, MAX_PENDING delayed blasts (the oldest goes first), pooled meshes only.
## Everything counts itself (the counters below): tests wait on counters, never on frames.

signal detonated(id: StringName, pos: Vector3)

const MAX_ITEMS := 26
const MAX_MINES := 12
const MAX_ZONES := 8
const MAX_PENDING := 48
const MAX_AIR := 16
const MAX_BURN := 24
const MAX_TOSS := 6
const GRAVITY := 22.0
const ZONE_TICK := 0.25
const AIR_TIME := 1.5
const ULT_COOLDOWN := 30.0
const ULT_COOLDOWN_HERO := 5.0
const MASK_FLY := 1 | 4 | 8                                         ## world, enemy, vehicle (Game.L_*)
const SHELL_IDS: Array[StringName] = [&"ord_tank_he", &"ord_tank_ap", &"ord_tank_cluster"]

static var instance: BlastOps = null
static var shell_index := 0                                         ## the tank's selected shell (cycled by the ammo type key while a tank is driven)
static var ult_ready_at: Dictionary = {}                            ## id -> engine seconds when the ultimate can be cast again

var detonations := 0
var launched_n := 0
var thrown_n := 0
var placed_n := 0
var triggered_n := 0
var strikes_called := 0
var strikes_landed := 0
var shells_n := 0
var bounces := 0
var stuck_n := 0
var casts := 0
var pulled_n := 0
var burned_n := 0
var frozen_n := 0
var emp_n := 0
var blinded_n := 0
var shocked_n := 0
var supply_n := 0
var tossed_n := 0
var last_detonation := Vector3.INF
var last_id: StringName = &""

var _items: Array[Dictionary] = []
var _zones: Array[Dictionary] = []
var _pending: Array[Dictionary] = []
var _air: Array[Dictionary] = []
var _burn: Dictionary = {}
var _toss: Array[Dictionary] = []
var _hold: Dictionary = {}                                           ## vehicles held still (freeze) or coasting to a stop (EMP): instance id -> {node, left, k}
var _pool: Array[MeshInstance3D] = []
var _meshes: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _tick := 0.0
var _remote_gap := 0.0
var _beams: Array[MeshInstance3D] = []


static func shared(tree: SceneTree = null) -> BlastOps:
	if is_instance_valid(instance):
		return instance
	var t: SceneTree = tree if tree != null else (Engine.get_main_loop() as SceneTree)
	if t == null:
		return null
	var parent: Node = Game.world if is_instance_valid(Game.world) else t.root
	var n := BlastOps.new()
	n.name = &"BlastOps"
	parent.add_child(n)
	return n


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_rng.randomize()
	Game.new_game.connect(reset)
	Game.respawn.connect(reset)
	if not InputMap.has_action(&"ultimate"):
		InputMap.add_action(&"ultimate")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_U
		InputMap.action_add_event(&"ultimate", ev)


func reset() -> void:
	for it in _items:
		_free_node(it)
	_items.clear()
	for z in _zones:
		_free_node(z)
	_zones.clear()
	_pending.clear()
	_air.clear()
	_burn.clear()
	_toss.clear()
	_hold.clear()
	for b in _beams:
		b.visible = false
	if BlastFx.instance != null:
		BlastFx.instance.reset()


# --- counts the tests and the HUD read ------------------------------------------------------------------------------------

func live_count() -> int:
	return _items.size()


func live_of(id: StringName) -> int:
	var n := 0
	for it in _items:
		if it["id"] == id:
			n += 1
	return n


func mines_live() -> int:
	var n := 0
	for it in _items:
		if StringName(it["kind"]) == &"mine":
			n += 1
	return n


func strikes_live() -> int:
	var n := 0
	for it in _items:
		if StringName(it["kind"]) == &"strike" or StringName(it["kind"]) == &"marker":
			n += 1
	return n


func zones_live() -> int:
	return _zones.size()


func zone_kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for z in _zones:
		out.append(StringName(z["kind"]))
	return out


func pending_count() -> int:
	return _pending.size()


func remote_live() -> int:
	var n := 0
	for it in _items:
		var dv: Dictionary = (it["e"] as Dictionary)["deliver"]
		var kind := StringName(it["kind"])
		if bool(dv.get("remote", false)) and (kind == &"mine" or (kind == &"proj" and StringName(it["state"]) == &"live")):         # a placed charge or a satchel that has landed
			n += 1
	return n


func air_count() -> int:
	return _air.size()


## Where the strikes and wells currently on the map are: [{pos, radius, color, left}] (the minimap and the HUD draw them).
func beacons() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in _items:
		if StringName(it["kind"]) == &"strike":
			out.append({"pos": it["pos"], "radius": float((it["e"] as Dictionary)["radius"]) * _spread_k(it), "color": BlastElements.color(StringName((it["e"] as Dictionary)["element"]), "ring"), "left": float(it["delay"])})
	for z in _zones:
		if StringName(z["kind"]) == &"pre":
			out.append({"pos": z["pos"], "radius": float(z["radius"]), "color": BlastElements.color(StringName((z["e"] as Dictionary)["element"]), "ring"), "left": float(z["left"])})
	return out


func _spread_k(it: Dictionary) -> float:
	var dv: Dictionary = (it["e"] as Dictionary)["deliver"]
	var spread := float(dv.get("spread", 0.0)) + float(dv.get("length", 0.0)) * 0.5
	var r := float((it["e"] as Dictionary)["radius"])
	return 1.0 + spread / maxf(r, 0.5)


# --- the tick -------------------------------------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if not Game.is_playing():
		return
	var t0 := PerfTimers.start()
	_tick += dt
	var i := _items.size() - 1
	while i >= 0:
		var it: Dictionary = _items[i]
		if _step_item(it, dt):
			_free_node(it)
			_items.remove_at(i)
		i -= 1
	_step_pending(dt)
	_step_zones(dt)
	_step_air(dt)
	_step_burn(dt)
	_step_toss(dt)
	_step_hold(dt)
	_poll_input()
	PerfTimers.stop(PerfTimers.EFFECTS, t0)


func _poll_input() -> void:
	if InputMap.has_action(&"ultimate") and Input.is_action_just_pressed(&"ultimate"):
		var order: Array[StringName] = BlastTable.ids_in(&"ultimate")
		for id in order:
			if unlocked(id) and ult_cooldown(id) <= 0.0:
				cast(id, Game.player)
				break


# --- delivery from the hero's weapon ---------------------------------------------------------------------------------------

## PlayerWeapon._throw hands every weapon with a `bid` over to this (the round is already paid for): aim, solve the arc, spawn the projectile / mine / marker.
static func weapon_fire(w: PlayerWeapon, yaw_off := 0.0, opts: Dictionary = {}) -> void:
	var ops := shared(w.get_tree())
	if ops != null:
		ops._weapon_fire(w, yaw_off, opts)


func _weapon_fire(w: PlayerWeapon, yaw_off: float, _opts: Dictionary) -> void:
	var p := w._player
	var d := w.def
	var id := StringName(d["bid"])
	var e := BlastTable.entry(id)
	if e.is_empty() or not is_instance_valid(p):
		return
	var dv: Dictionary = e["deliver"]
	var mode := StringName(dv["mode"])
	var ar := w._aim_ray(0.0)
	var origin: Vector3 = ar[0]
	var dir: Vector3 = ar[1]
	var space := p.get_world_3d().direct_space_state
	w._ray_b.from = origin
	w._ray_b.to = origin + dir * float(d["range"])
	var res := space.intersect_ray(w._ray_b)
	var aim_pt: Vector3 = res["position"] if not res.is_empty() else origin + dir * 40.0
	var locked: Node3D = null
	if w._launch != null and is_instance_valid(w._launch.target) and not PlayerWeapon._is_dead(w._launch.target) and yaw_off == 0.0:
		locked = w._launch.target
		aim_pt = w._launch.landing
	var from: Vector3 = p.body.muzzle.global_position
	if bool(d.get("launch", false)):
		Sfx.play(StringName(d.get("snd", &"shot")), float(d.get("vol", -2.0)), randf_range(float(d["pitch_lo"]), float(d["pitch_hi"])))
	else:
		Sfx.play(&"blink", -6.0, 1.6)
	p.body.fire_flash(0.8 if mode == &"launch" else 0.3)
	w._recoil(false)
	p.fired.emit()
	var ctx := {"from": from, "aim": aim_pt, "dir": dir, "origin": origin, "yaw": yaw_off, "locked": locked, "hit": res}
	match mode:
		&"throw", &"launch":
			var n := int(dv.get("salvo", 1))
			for k in n:
				var c2 := ctx.duplicate()
				c2["slot"] = k
				c2["of"] = n
				spawn_projectile(id, p, c2)
		&"place":
			place(id, p, ctx)
		&"mark":
			throw_marker(id, p, ctx)


# --- projectiles ----------------------------------------------------------------------------------------------------------

func _entry_of(id: StringName) -> Dictionary:
	return BlastTable.entry(id)


## Throws or launches the blast `id` along ctx {from, aim, dir, yaw, locked, slot, of}; returns the item (empty when the id is unknown).
func spawn_projectile(id: StringName, source: Variant, ctx: Dictionary) -> Dictionary:
	var e := _entry_of(id)
	if e.is_empty():
		return {}
	var dv: Dictionary = e["deliver"]
	var mode := StringName(dv["mode"])
	_make_room(&"proj")
	var from: Vector3 = ctx["from"]
	var aim: Vector3 = ctx["aim"]
	var yaw := float(ctx.get("yaw", 0.0))
	var slot := int(ctx.get("slot", 0))
	var of := int(ctx.get("of", 1))
	var speed := float(dv.get("speed", 20.0))
	var grav := float(dv.get("grav", 22.0))
	var delta := aim - from
	if yaw != 0.0:
		delta = delta.rotated(Vector3.UP, yaw)
	if of > 1:                                                         # a salvo fans out around the aim point
		var ang := TAU * float(slot) / float(of) + 0.4
		delta += Vector3(cos(ang), 0.0, sin(ang)) * (2.5 + 2.0 * float(slot % 3)) * clampf(delta.length() / 40.0, 0.4, 1.4)
	var flat := Vector2(delta.x, delta.z).length()
	var guide := StringName(dv.get("guide", &"none"))
	var vel: Vector3
	var fuse := -1.0
	if guide != &"none":
		var look: Vector3 = delta.normalized() if delta.length() > 0.1 else (ctx["dir"] as Vector3)
		vel = look * speed
		if of > 1:
			vel = (look + Vector3(randf_range(-0.12, 0.12), randf_range(0.02, 0.2), randf_range(-0.12, 0.12))).normalized() * speed
	else:
		var air_h := float(dv.get("airburst", 0.0))
		if air_h > 0.0 and air_h < 20.0:
			delta.y += air_h
		var t: float = clampf(flat / speed, 0.8, 3.2) if bool(dv.get("lob", false)) else clampf(flat / speed, 0.3, 2.0)
		vel = Vector3(delta.x / t, delta.y / t + 0.5 * grav * t, delta.z / t)
		if air_h > 0.0:
			fuse = t * 0.985
	var it := _new_item(&"proj", id, e, source, from, vel)
	it["grav"] = grav
	it["state"] = &"fly"
	var own_fuse := float(dv.get("fuse", -1.0))
	if own_fuse <= 0.0 and (bool(dv.get("impact", false)) or bool(dv.get("remote", false))):
		own_fuse = -1.0                                                      # goes off on impact (or when DETONATE is pressed), not on a timer
	it["fuse"] = own_fuse if fuse < 0.0 else fuse
	it["aim"] = aim
	it["guide"] = guide
	it["target"] = ctx.get("locked", null)
	if guide == &"lock" and it["target"] == null:
		it["target"] = _pick_target(from, vel.normalized(), 120.0, 0.45, slot)
	it["mode"] = mode
	it["life"] = float(dv.get("life", 6.0))
	it["bounce"] = float(dv.get("bounce", 0.0))
	it["bounces"] = 0
	it["lure"] = float(dv.get("lure", 0.0))
	it["tick"] = 0.0
	it["dir"] = (ctx["dir"] as Vector3)
	thrown_n += 1
	last_id = id
	_style_node(it)
	_place(it)
	return it


func _new_item(kind: StringName, id: StringName, e: Dictionary, source: Variant, pos: Vector3, vel: Vector3) -> Dictionary:
	var it := {"kind": kind, "id": id, "e": e, "src": source, "pos": pos, "vel": vel, "t": 0.0, "state": &"fly", "node": _take_node(), "stuck": null, "off": Vector3.ZERO, "alive": true}
	_items.append(it)
	return it


## Keeps the caps: when the list is full the oldest of that class goes quietly (a projectile detonates where it is, a mine fizzles).
func _make_room(cls: StringName) -> void:
	if cls == &"mine":
		if mines_live() < MAX_MINES:
			return
		for k in _items.size():
			if StringName(_items[k]["kind"]) == &"mine":
				_free_node(_items[k])
				_items.remove_at(k)
				return
		return
	if _items.size() < MAX_ITEMS:
		return
	for k in _items.size():
		var it: Dictionary = _items[k]
		if StringName(it["kind"]) == &"proj":
			_detonate(it, it["pos"])
			_free_node(it)
			_items.remove_at(k)
			return
	_free_node(_items[0])
	_items.remove_at(0)


func _pick_target(from: Vector3, dir: Vector3, reach: float, cone: float, skip: int) -> Node3D:
	var cands: Array[Node3D] = []
	for g: StringName in [&"enemy", &"vehicle"]:
		for n: Node in get_tree().get_nodes_in_group(g):
			var nn := n as Node3D
			if nn == null or PlayerWeapon._is_dead(nn) or nn == Game.player:
				continue
			if g == &"vehicle" and nn.get(&"driver_is_player") == true:
				continue
			var c := nn.global_position + Vector3(0.0, 1.0, 0.0)
			var dist := from.distance_to(c)
			if dist < 4.0 or dist > reach:
				continue
			if dir.angle_to((c - from).normalized()) > cone:
				continue
			cands.append(nn)
	if cands.is_empty():
		return null
	cands.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_to(from) < b.global_position.distance_to(from))
	return cands[skip % cands.size()]


func _step_item(it: Dictionary, dt: float) -> bool:
	var kind := StringName(it["kind"])
	match kind:
		&"proj", &"bomb":
			return _step_proj(it, dt)
		&"mine":
			return _step_mine(it, dt)
		&"marker":
			return _step_marker(it, dt)
		&"strike":
			return _step_strike(it, dt)
		&"crate":
			return _step_crate(it, dt)
	return true


func _ray(a: Vector3, b: Vector3, mask: int = MASK_FLY) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, mask)
	return get_world_3d().direct_space_state.intersect_ray(q)


func _step_proj(it: Dictionary, dt: float) -> bool:
	var e: Dictionary = it["e"]
	var dv: Dictionary = e["deliver"]
	it["t"] = float(it["t"]) + dt
	var t: float = it["t"]
	var pos: Vector3 = it["pos"]
	var state := StringName(it["state"])
	if state == &"live":                                        # landed: stuck to a carrier, counting its fuse
		if it.has("go"):                                        # DETONATE was pressed for a landed satchel
			it["go"] = float(it["go"]) - dt
			if float(it["go"]) < 0.0:
				_detonate(it, pos)
				return true
		var host: Variant = it["stuck"]
		if host != null and is_instance_valid(host) and not PlayerWeapon._is_dead(host):
			pos = (host as Node3D).global_position + (it["off"] as Vector3)
			it["pos"] = pos
			_place(it)
		it["left"] = float(it["left"]) - dt
		if float(it["lure"]) > 0.0:
			it["tick"] = float(it["tick"]) - dt
			if float(it["tick"]) <= 0.0:
				it["tick"] = 0.5
				_lure(pos, float(it["lure"]))
		if bool(dv.get("remote", false)) and float(it["left"]) > 0.0 and float(dv.get("fuse", 0.0)) <= 0.0:
			return false                                          # a satchel waits for DETONATE
		if float(it["left"]) <= 0.0:
			if host != null and is_instance_valid(host) and (host as Node).has_method(&"damage") and bool(dv.get("stick", false)):
				(host as Node).call(&"damage", float((e["dmg"] as Dictionary)["vehicle"]) * 0.4 if (host as Node).is_in_group(&"vehicle") else float((e["dmg"] as Dictionary)["enemy"]) * 0.4)
			_detonate(it, pos)
			return true
		_pulse(it)
		return false
	# --- in flight
	var vel: Vector3 = it["vel"]
	var guide := StringName(it["guide"])
	if guide != &"none":
		vel = _steer(it, vel, dt)
	vel.y -= float(it["grav"]) * dt
	var nxt := pos + vel * dt
	var prox := float(dv.get("proximity", 0.0))
	if prox > 0.0 and _near_air_target(nxt, prox):
		_detonate(it, nxt)
		return true
	var hit := _ray(pos, nxt)
	var fuse_t := float(it["fuse"])
	if not hit.is_empty():
		var hp: Vector3 = hit["position"]
		var hn: Vector3 = hit["normal"]
		var collider := hit["collider"] as Node
		var mode := StringName(it["mode"])
		if mode == &"throw" and not bool(dv.get("impact", false)):
			var tgt: Node = PlayerWeapon._damageable_of(collider) if collider != null else null
			if bool(dv.get("stick", false)):
				_land(it, hp + hn * 0.12, tgt)
				stuck_n += 1
				Sfx.play_at(&"plasma_stick", hp, -4.0)
				return false
			if float(it["bounce"]) > 0.05 and vel.length() > 5.0 and int(it["bounces"]) < 3:
				vel = vel.bounce(hn) * float(it["bounce"])
				nxt = hp + hn * 0.14
				it["bounces"] = int(it["bounces"]) + 1
				bounces += 1
				Sfx.play_at(&"impact_metal", hp, -12.0, 1.8)
			else:
				_land(it, hp + hn * 0.14, null)
				return false
		else:
			var pen := float(dv.get("pen", 0.0))
			if pen > 0.0 and collider != null and not (collider.is_in_group(&"enemy") or collider.is_in_group(&"vehicle")):
				var through := hp + vel.normalized() * pen
				it["pos"] = through
				_place(it)
				it["mode"] = &"throw"
				it["vel"] = Vector3.ZERO
				it["state"] = &"live"
				it["left"] = float(dv.get("delay", 0.4))
				it["pen"] = true
				FX.burst(hp, Color(0.8, 0.7, 0.5), 10, 6.0, 0.4, 6.0, 1.2)
				return false
			var at: Vector3 = hp + hn * 0.25 if collider != null and not collider.is_in_group(&"enemy") else hp
			_detonate(it, at, collider)
			return true
	it["vel"] = vel
	it["pos"] = nxt
	_place(it)
	if fuse_t >= 0.0 and t >= fuse_t:
		_detonate(it, nxt)
		return true
	var life := float(it["life"])
	if t >= life:
		_detonate(it, nxt)
		return true
	if StringName(it["kind"]) == &"bomb" and float(dv.get("airburst", 0.0)) >= 20.0:
		var down := _ray(nxt, nxt + Vector3(0.0, -float(dv["airburst"]), 0.0), 1)
		if not down.is_empty():
			_detonate(it, nxt)
			return true
	return false


func _land(it: Dictionary, at: Vector3, host: Node) -> void:
	var e: Dictionary = it["e"]
	var dv: Dictionary = e["deliver"]
	it["state"] = &"live"
	it["pos"] = at
	it["vel"] = Vector3.ZERO
	it["left"] = maxf(0.0, float(it["fuse"]) - float(it["t"])) if float(it["fuse"]) >= 0.0 else 0.0
	if float(dv.get("fuse", 0.0)) <= 0.0 and not bool(dv.get("remote", false)):
		it["left"] = 0.05
	if bool(dv.get("remote", false)):
		it["left"] = 1.0e9                                                   # a satchel waits for DETONATE
	if host != null and host is Node3D:
		it["stuck"] = host
		it["off"] = at - (host as Node3D).global_position
	_place(it)


func _steer(it: Dictionary, vel: Vector3, dt: float) -> Vector3:
	var e: Dictionary = it["e"]
	var dv: Dictionary = e["deliver"]
	var speed := vel.length()
	if speed < 0.5:
		return vel
	var pos: Vector3 = it["pos"]
	var want_pt: Vector3 = it["aim"]
	var guide := StringName(it["guide"])
	if guide == &"laser" or guide == &"wire":
		var src: Variant = it["src"]
		if src is Player and is_instance_valid(src):
			want_pt = ((src as Player).get_aim() as Dictionary)["hit"]
	elif guide == &"air":
		var tgt: Variant = it["target"]
		if tgt == null or not is_instance_valid(tgt) or PlayerWeapon._is_dead(tgt):
			tgt = _nearest_air_target(pos, vel.normalized())
			it["target"] = tgt
		if tgt != null:
			want_pt = (tgt as Node3D).global_position + Vector3(0.0, 1.0, 0.0)
	elif guide == &"lock":
		var tg: Variant = it["target"]
		if tg != null and is_instance_valid(tg) and not PlayerWeapon._is_dead(tg):
			want_pt = (tg as Node3D).global_position + Vector3(0.0, 1.0, 0.0)
	var want := (want_pt - pos).normalized()
	var cur := vel / speed
	var ang := cur.angle_to(want)
	if ang > 0.001:
		var step := minf(ang, float(dv.get("turn", 2.5)) * dt)
		var axis := cur.cross(want)
		if axis.length() > 0.0001:
			cur = cur.rotated(axis.normalized(), step)
	return cur * speed


func _nearest_air_target(from: Vector3, dir: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := 1.0e9
	for n: Node in get_tree().get_nodes_in_group(&"vehicle"):
		var v := n as Node3D
		if v == null or PlayerWeapon._is_dead(v) or not v.has_method(&"is_aloft") or not bool(v.call(&"is_aloft")):
			continue
		var d := v.global_position.distance_to(from)
		if d < best_d and d < 160.0 and dir.angle_to((v.global_position - from).normalized()) < 0.9:
			best_d = d
			best = v
	return best


func _near_air_target(p: Vector3, radius: float) -> bool:
	for n: Node in get_tree().get_nodes_in_group(&"vehicle"):
		var v := n as Node3D
		if v != null and not PlayerWeapon._is_dead(v) and v.has_method(&"is_aloft") and bool(v.call(&"is_aloft")) and v.global_position.distance_to(p) < radius:
			return true
	return false


func _lure(pos: Vector3, radius: float) -> void:
	for en in Gear.living_enemies(get_tree()):
		if en.global_position.distance_to(pos) < radius and en.has_method(&"hear"):
			en.call(&"hear", pos, 0.4)


func _detonate(it: Dictionary, at: Vector3, _collider: Node = null) -> void:
	var id := StringName(it["id"])
	var src: Variant = it["src"]
	detonations += 1
	last_detonation = at
	last_id = id
	var opts := {}
	var e: Dictionary = it["e"]
	if float(e.get("cone", 0.0)) > 0.0 and it.has("face"):
		opts["dir"] = it["face"]
	BlastTable.apply(id, at, src, opts)
	detonated.emit(id, at)
	it["alive"] = false


# --- mines and charges ----------------------------------------------------------------------------------------------------

## Places mine / charge `id` where ctx {origin, dir, from} points within the entry's reach (on a wall, a car, a person, or at the end of the line on the street).
func place(id: StringName, source: Variant, ctx: Dictionary) -> Dictionary:
	var e := _entry_of(id)
	if e.is_empty():
		return {}
	var dv: Dictionary = e["deliver"]
	_make_room(&"mine")
	var origin: Vector3 = ctx["origin"]
	var dir: Vector3 = ctx["dir"]
	var reach := float(dv.get("reach", 14.0))
	var hit := _ray(origin, origin + dir * reach)
	var pos: Vector3
	var normal := Vector3.UP
	var host: Node = null
	if hit.is_empty():
		pos = origin + dir * minf(reach * 0.5, 8.0)
		var g := _ray(pos + Vector3.UP * 2.0, pos + Vector3.DOWN * 8.0, 1)
		pos = (g["position"] as Vector3) + Vector3(0.0, 0.08, 0.0) if not g.is_empty() else Vector3(pos.x, 0.1, pos.z)
	else:
		normal = hit["normal"]
		pos = (hit["position"] as Vector3) + normal * 0.08
		var c := hit["collider"] as Node
		while c != null:
			if (c.is_in_group(&"vehicle") or c.is_in_group(&"enemy")) and c is Node3D:
				host = c
				break
			c = c.get_parent()
	var it := _new_item(&"mine", id, e, source, pos, Vector3.ZERO)
	it["armed"] = false
	it["go"] = -1.0
	it["normal"] = normal
	var flat := Vector3(dir.x, 0.0, dir.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
	var face := flat if normal.y > 0.7 else Vector3(normal.x, 0.0, normal.z).normalized()
	it["face"] = face
	if bool(dv.get("stick", true)) and host != null:
		it["stuck"] = host
		it["off"] = pos - (host as Node3D).global_position
	placed_n += 1
	last_id = id
	_style_node(it)
	_place(it)
	Sfx.play_at(&"ui_tap", pos, -2.0)
	FX.burst(pos, BlastElements.color(StringName(e["element"]), "mid"), 4, 2.0, 0.25, 0.0)
	return it


func _step_mine(it: Dictionary, dt: float) -> bool:
	var e: Dictionary = it["e"]
	var dv: Dictionary = e["deliver"]
	it["t"] = float(it["t"]) + dt
	var t: float = it["t"]
	var host: Variant = it["stuck"]
	if host != null:
		if is_instance_valid(host) and (host as Node).is_inside_tree() and not PlayerWeapon._is_dead(host):
			it["pos"] = (host as Node3D).global_position + (it["off"] as Vector3)
			_place(it)
		else:
			it["stuck"] = null
	var pos: Vector3 = it["pos"]
	# hop of a bounce mine
	if it.has("hop_t"):
		it["hop_t"] = float(it["hop_t"]) + dt
		var u := float(it["hop_t"]) / 0.3
		var base: Vector3 = it["hop_from"]
		it["pos"] = base + Vector3(0.0, float(dv.get("hop", 1.6)) * sin(minf(u, 1.0) * PI * 0.5), 0.0)
		_place(it)
		if u >= 1.0:
			_trigger_mine(it, it["pos"])
			return true
		return false
	if float(it["go"]) >= 0.0:
		it["go"] = float(it["go"]) - dt
		if float(it["go"]) < 0.0:
			_trigger_mine(it, pos)
			return true
		return false
	var timer := float(dv.get("timer", 0.0))
	if timer > 0.0 and t >= timer:
		_trigger_mine(it, pos)
		return true
	if t >= float(dv.get("life", 120.0)):
		return true
	if not bool(it["armed"]):
		if t >= float(dv.get("arm", 0.8)):
			it["armed"] = true
			Sfx.play_at(&"ui_tap", pos, -6.0, 1.6)
		else:
			return false
	_pulse(it)
	if bool(dv.get("remote", false)):
		return false
	var who := _triggered_by(it, pos, dv)
	if who:
		triggered_n += 1
		if float(dv.get("hop", 0.0)) > 0.0:
			it["hop_t"] = 0.0
			it["hop_from"] = pos
			Sfx.play_at(&"blink", pos, -2.0, 1.3)
			return false
		_trigger_mine(it, pos)
		return true
	return false


func _triggered_by(it: Dictionary, pos: Vector3, dv: Dictionary) -> bool:
	var wire := float(dv.get("wire", 0.0))
	var trig := float(dv.get("trigger", 2.6))
	var cone := float(dv.get("cone", 0.0))
	var face: Vector3 = it["face"]
	var cands: Array[Node3D] = []
	for en in Gear.living_enemies(get_tree()):
		cands.append(en)
	var own_car: Variant = Game.player.get(&"vehicle") if is_instance_valid(Game.player) else null
	for n: Node in get_tree().get_nodes_in_group(&"vehicle"):
		var v := n as Node3D
		if v != null and not PlayerWeapon._is_dead(v) and (v != own_car or Difficulty.current >= 2):
			cands.append(v)
	if Difficulty.current >= 2 and is_instance_valid(Game.player):
		cands.append(Game.player)                                 # on HARD and QUANTUM your own mines know no friends
	var host: Variant = it["stuck"]
	for c in cands:
		if c == host:
			continue
		var cp := c.global_position + Vector3(0.0, 0.8, 0.0)
		if wire > 0.0:
			var end := pos + face * wire + Vector3(0.0, 0.15, 0.0)
			if Throwables._seg_dist(pos, end, cp) < 0.7:
				return true
			continue
		var d := cp.distance_to(pos)
		if d <= trig and absf(cp.y - pos.y) < 2.6:
			if cone > 0.0:
				var flat := Vector3(cp.x - pos.x, 0.0, cp.z - pos.z)
				if flat.length() > 0.5 and face.angle_to(flat.normalized()) > cone:
					continue
			return true
	return false


func _trigger_mine(it: Dictionary, pos: Vector3) -> void:
	_detonate(it, pos)


## DETONATE: every remote charge goes off, a fraction of a second apart. Returns how many were armed to go.
func detonate_remote() -> int:
	var n := 0
	var gap := 0.0
	for it in _items:
		var kind := StringName(it["kind"])
		if not bool(((it["e"] as Dictionary)["deliver"] as Dictionary).get("remote", false)):
			continue
		if (kind == &"mine" and float(it["go"]) < 0.0) or (kind == &"proj" and StringName(it["state"]) == &"live" and not it.has("go")):
			it["go"] = gap
			gap += 0.14
			n += 1
	return n


# --- strikes ---------------------------------------------------------------------------------------------------------------

func throw_marker(id: StringName, source: Variant, ctx: Dictionary) -> Dictionary:
	var e := _entry_of(id)
	if e.is_empty():
		return {}
	var dv: Dictionary = e["deliver"]
	_make_room(&"proj")
	var from: Vector3 = ctx["from"]
	var aim: Vector3 = ctx["aim"]
	var delta := aim - from
	var flat := Vector2(delta.x, delta.z).length()
	var speed := float(dv.get("speed", 24.0))
	var grav := float(dv.get("grav", 16.0))
	var t := clampf(flat / speed, 0.3, 2.0)
	var vel := Vector3(delta.x / t, delta.y / t + 0.5 * grav * t, delta.z / t)
	var it := _new_item(&"marker", id, e, source, from, vel)
	it["grav"] = grav
	it["aim"] = aim
	it["origin"] = ctx.get("origin", from)
	strikes_called += 1
	last_id = id
	_style_node(it)
	_place(it)
	return it


func _step_marker(it: Dictionary, dt: float) -> bool:
	it["t"] = float(it["t"]) + dt
	var pos: Vector3 = it["pos"]
	var vel: Vector3 = it["vel"]
	vel.y -= float(it["grav"]) * dt
	var nxt := pos + vel * dt
	var hit := _ray(pos, nxt)
	if not hit.is_empty() or float(it["t"]) > 4.0:
		var at: Vector3 = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * 0.1 if not hit.is_empty() else nxt
		start_strike(it, at)
		return false
	it["vel"] = vel
	it["pos"] = nxt
	_place(it)
	return false


## The marker has landed (or a test calls this directly): the strike starts counting down at `at`.
func start_strike(it: Dictionary, at: Vector3) -> void:
	var e: Dictionary = it["e"]
	var dv: Dictionary = e["deliver"]
	it["kind"] = &"strike"
	it["pos"] = at
	it["vel"] = Vector3.ZERO
	it["delay"] = float(dv.get("delay", 3.5))
	it["delay0"] = float(dv.get("delay", 3.5))
	it["ring_t"] = 0.0
	it["jet_done"] = false
	it["state"] = &"count"
	_style_node(it, true)
	_place(it)
	FX.burst(at + Vector3(0.0, 0.3, 0.0), BlastElements.color(StringName(e["element"]), "mid"), 8, 3.0, 0.6, 0.0, 1.2)
	Sfx.play_at(&"link", at, -3.0, 0.7)


func _step_strike(it: Dictionary, dt: float) -> bool:
	var e: Dictionary = it["e"]
	var dv: Dictionary = e["deliver"]
	var pos: Vector3 = it["pos"]
	it["delay"] = float(it["delay"]) - dt
	var left := float(it["delay"])
	var k := 1.0 - clampf(left / maxf(float(it["delay0"]), 0.1), 0.0, 1.0)
	it["ring_t"] = float(it["ring_t"]) - dt
	if float(it["ring_t"]) <= 0.0 and left > 0.0:
		it["ring_t"] = 0.5
		var fx := BlastFx.shared()
		fx.beacon_tick(pos, float(e["radius"]) * _spread_k(it), BlastElements.color(StringName(e["element"]), "ring"), k)
	if bool(dv.get("jet", false)) and not bool(it["jet_done"]) and left <= 1.6:
		it["jet_done"] = true
		var d: Vector3 = _strike_dir(it)
		BlastFx.shared().flyover(pos, d, maxf(left, 0.4))
		Sfx.play_at(&"engine_jet_high", pos, -2.0, 1.1)
	if left > 0.0:
		return false
	strikes_landed += 1
	_strike_fire(it)
	return true


func _strike_dir(it: Dictionary) -> Vector3:
	var o: Vector3 = it.get("origin", Vector3.INF)
	var pos: Vector3 = it["pos"]
	if o != Vector3.INF:
		var d := Vector3(pos.x - o.x, 0.0, pos.z - o.z)
		if d.length() > 1.0:
			return d.normalized()
	return Vector3(1.0, 0.0, 0.3).normalized()


## The barrage arrives: the pattern of the entry's `deliver` laid around the marker, one delayed blast per shell.
func _strike_fire(it: Dictionary) -> void:
	var e: Dictionary = it["e"]
	var dv: Dictionary = e["deliver"]
	var pos: Vector3 = it["pos"]
	var count := maxi(1, int(dv.get("count", 1)))
	var pattern := StringName(dv.get("pattern", &"single"))
	var gap := float(dv.get("gap", 0.5))
	var spread := float(dv.get("spread", 0.0))
	var length := float(dv.get("length", 0.0))
	var dir := _strike_dir(it)
	var side := Vector3(-dir.z, 0.0, dir.x)
	if bool(dv.get("supply", false)):
		_drop_crate(it)
		return
	for i in count:
		var p := pos
		match pattern:
			&"scatter":
				var ang := TAU * float(i) / float(count) + _rng.randf() * 0.7
				p = pos + Vector3(cos(ang), 0.0, sin(ang)) * spread * (0.2 if i == 0 else _rng.randf_range(0.5, 1.0))
			&"ring":
				var ang2 := TAU * float(i) / float(count)
				p = pos + Vector3(cos(ang2), 0.0, sin(ang2)) * spread
			&"line", &"carpet":
				var u := (float(i) / float(maxi(count - 1, 1)) - 0.5) if count > 1 else 0.0
				p = pos + dir * u * length + side * _rng.randf_range(-0.8, 0.8)
		var g := _ray(p + Vector3.UP * 30.0, p + Vector3.DOWN * 60.0, 1)
		if not g.is_empty():
			p = (g["position"] as Vector3) + Vector3(0.0, 0.3, 0.0)
		if _pending.size() >= MAX_PENDING:
			_pending.remove_at(0)
		_pending.append({"id": StringName(it["id"]), "pos": p, "t": gap * float(i), "src": it["src"], "quiet": (i % 3 != 0) and count > 4, "e": e})


func _drop_crate(it: Dictionary) -> void:
	var pos: Vector3 = it["pos"]
	var crate := _new_item(&"crate", StringName(it["id"]), it["e"], it["src"], pos + Vector3(0.0, 45.0, 0.0), Vector3.ZERO)
	crate["land"] = pos
	crate["state"] = &"fall"
	crate["fall_t"] = 0.0
	_style_node(crate)
	_place(crate)


func _step_crate(it: Dictionary, dt: float) -> bool:
	var land: Vector3 = it["land"]
	if StringName(it["state"]) == &"fall":
		it["fall_t"] = float(it["fall_t"]) + dt
		var u := clampf(float(it["fall_t"]) / 1.4, 0.0, 1.0)
		it["pos"] = land + Vector3(0.0, 45.0 * (1.0 - u * u * 0.4 - u * 0.6), 0.0)
		_place(it)
		if u >= 1.0:
			it["pos"] = land
			it["state"] = &"pickup"
			it["t"] = 0.0
			_detonate(it, land + Vector3(0.0, 0.3, 0.0))
			supply_n += 1
			_place(it)
		return false
	it["t"] = float(it["t"]) + dt
	var p := Game.player as Player
	if is_instance_valid(p) and p.global_position.distance_to(land) < 3.0:
		p.weapon.restock(1.0)
		p.hp = minf(p.max_hp, p.hp + 40.0)
		Game.say("SUPPLY DROP  AMMO AND HEALTH", 1.6)
		Sfx.play(&"pickup_ammo", -2.0)
		return true
	return float(it["t"]) > 60.0


# --- ordnance: bombs, shells, mines at sea ---------------------------------------------------------------------------------

## Drops / fires ordnance `id` from `from` with the starting velocity `vel` (aircraft bombs fall with the plane's speed, tank shells leave the barrel): the aircraft and tank hooks call this.
func drop(id: StringName, from: Vector3, vel: Vector3, source: Variant = null, target: Node3D = null) -> Dictionary:
	var e := _entry_of(id)
	if e.is_empty():
		return {}
	var dv: Dictionary = e["deliver"]
	if float(dv.get("trigger", 0.0)) > 0.0:                                 # a naval mine floats where it is dropped and waits for a hull
		_make_room(&"mine")
		var mine := _new_item(&"mine", id, e, source, from, Vector3.ZERO)
		mine["armed"] = false
		mine["go"] = -1.0
		mine["normal"] = Vector3.UP
		mine["face"] = Vector3.FORWARD
		placed_n += 1
		last_id = id
		_style_node(mine)
		_place(mine)
		return mine
	_make_room(&"proj")
	var it := _new_item(&"bomb", id, e, source, from, vel)
	it["grav"] = float(dv.get("grav", 22.0))
	it["state"] = &"fly"
	it["fuse"] = float(dv.get("fuse", -1.0))
	it["guide"] = StringName(dv.get("guide", &"none"))
	it["aim"] = from + vel.normalized() * 60.0
	it["target"] = target
	it["mode"] = &"drop"
	it["life"] = 14.0
	it["bounce"] = 0.0
	it["lure"] = 0.0
	it["tick"] = 0.0
	shells_n += 1
	last_id = id
	_style_node(it)
	_place(it)
	return it


## A tank shell of the selected kind (HE, AP, cluster) from the muzzle along `dir`: the VehicleWeapons hook (the tank's gun is a ray, so the blast lands at `at` at once).
func shell_blast(car: Node, at: Vector3, kind_id: StringName = &"") -> void:
	var id := kind_id if kind_id != &"" else SHELL_IDS[shell_index % SHELL_IDS.size()]
	shells_n += 1
	detonations += 1
	last_detonation = at
	last_id = id
	BlastTable.apply(id, at, car)
	detonated.emit(id, at)


## Cycles the selected tank shell (HE, AP, CLUSTER) and says so.
func cycle_shell() -> StringName:
	shell_index = (shell_index + 1) % SHELL_IDS.size()
	var e := BlastTable.entry(SHELL_IDS[shell_index])
	Game.say("SHELL  %s" % String(e["name"]).replace("TANK SHELL ", ""), 1.0)
	return SHELL_IDS[shell_index]


static func selected_shell() -> StringName:
	return SHELL_IDS[shell_index % SHELL_IDS.size()]


## The cannons that fire the shells of the blast table (the main battle tank and the light tank).
static func is_shell_gun(kind: StringName) -> bool:
	return kind == &"tank" or kind == &"ltank"


# --- the hero's ultimates ---------------------------------------------------------------------------------------------------

## True when the hero may cast at least one ultimate (the touch button shows only then).
static func ultimates_open() -> bool:
	return WeaponDefs.hero_mode or SkillTree.level() >= 5


## Unlocked by hero mode, or by the hero's skill level (the n-th ultimate at level 5 x n).
func unlocked(id: StringName) -> bool:
	if WeaponDefs.hero_mode:
		return true
	var e := BlastTable.entry(id)
	if e.is_empty():
		return false
	return SkillTree.level() >= 5 * maxi(1, int(e["unlock"]))


func ult_cooldown(id: StringName) -> float:
	return maxf(0.0, float(ult_ready_at.get(id, 0.0)) - Time.get_ticks_msec() * 0.001)


## Casts ultimate `id` for `source` (the hero). False while locked or cooling down (a test can pass `force`).
func cast(id: StringName, source: Variant, force := false) -> bool:
	var e := BlastTable.entry(id)
	if e.is_empty() or StringName(e["cat"]) != &"ultimate":
		return false
	if not force and (not unlocked(id) or ult_cooldown(id) > 0.0):
		return false
	var p := Game.player as Player
	if p == null:
		return false
	var dv: Dictionary = e["deliver"]
	var cd := ULT_COOLDOWN_HERO if WeaponDefs.hero_mode else ULT_COOLDOWN
	ult_ready_at[id] = Time.get_ticks_msec() * 0.001 + cd
	casts += 1
	last_id = id
	var pos := p.global_position + Vector3(0.0, 0.2, 0.0)
	var reach := float(dv.get("range", 0.0))
	var aim_pt: Vector3 = pos
	if reach > 0.0:
		aim_pt = (p.get_aim() as Dictionary)["hit"]
		var off := Vector3(aim_pt.x - pos.x, 0.0, aim_pt.z - pos.z)
		if off.length() > reach:
			aim_pt = pos + off.normalized() * reach
	var fx := StringName(e.get("fx", &"default"))
	Game.say(String(e["name"]), 1.2)
	GameFeel.fire(&"slam")
	match fx:
		&"mega", &"bubble":
			var at := pos
			BlastTable.apply(id, at, source, {"by_hero": true})
			detonations += 1
		&"storm":
			_start_storm(e, pos, source)
		&"meteor":
			BlastFx.shared().meteor(aim_pt, float(dv.get("delay", 2.0)), BlastElements.color(StringName(e["element"]), "mid"))
			_pending.append({"id": id, "pos": aim_pt, "t": float(dv.get("delay", 2.0)), "src": source, "quiet": false, "e": e, "by_hero": true})
		_:
			var delay := float(dv.get("delay", 0.0))
			if delay > 0.0:
				_pending.append({"id": id, "pos": aim_pt, "t": delay, "src": source, "quiet": false, "e": e, "by_hero": true})
			else:
				BlastTable.apply(id, aim_pt, source, {"by_hero": true})
				detonations += 1
	return true


func _start_storm(e: Dictionary, pos: Vector3, source: Variant) -> void:
	var dv: Dictionary = e["deliver"]
	var zone := {"kind": &"storm", "pos": pos, "radius": float(e["radius"]), "left": float(e["hold"]), "tick": 0.0, "e": e, "src": source, "node": null,
			"n": int(dv.get("strikes", 12)), "made": 0, "span": float(e["hold"])}
	_add_zone(zone)
	BlastTable.apply(StringName(e["id"]), pos, source, {"by_hero": true, "quiet": true})                       # the field itself: a jolt of lightning through everyone in it, the bolts follow
	detonations += 1
	detonated.emit(StringName(e["id"]), pos)
	BlastFx.shared().screen_flash(0.18, 0.4)


# --- zones: what a blast leaves behind -------------------------------------------------------------------------------------

func _add_zone(z: Dictionary) -> void:
	if _zones.size() >= MAX_ZONES:
		_zones.remove_at(0)
	_zones.append(z)


func fire_field(pos: Vector3, radius: float, secs: float, dps: float, source: Variant) -> void:
	var z := {"kind": &"fire", "pos": pos, "radius": radius, "left": secs, "tick": 0.0, "dps": dps, "src": source, "e": {}, "node": null}
	_add_zone(z)
	FX.blast_marks(pos, radius * 0.8, BlastElements.FIRE)
	BlastFx.shared().flames(pos, radius, 8)


## Zones a blast keeps while it holds (smoke, a freeze bubble, a lure): called by BlastTable after the damage.
func start_zone(e: Dictionary, pos: Vector3, source: Variant, opts: Dictionary, radius: float) -> void:
	var st: Dictionary = e["status"]
	var kind := StringName(st.get("kind", &"hold"))
	if kind != &"smoke" and kind != &"freeze":
		kind = &"hold"
	var z := {"kind": kind, "pos": pos, "radius": radius, "left": float(e["hold"]), "tick": 0.0, "e": e, "src": source, "opts": opts, "node": null, "puff": 0.0}
	_add_zone(z)


## The blast waits `pre` seconds while the area pulls everything in (a well, a collapse, a black hole), then the damage phase runs with opts.final.
func start_pre(e: Dictionary, pos: Vector3, source: Variant, opts: Dictionary, radius: float) -> void:
	var o := opts.duplicate()
	o["final"] = true
	var z := {"kind": &"pre", "pos": pos, "radius": radius, "left": float(e["pre"]), "tick": 0.0, "e": e, "src": source, "opts": o, "node": null, "total": float(e["pre"])}
	_add_zone(z)
	Sfx.play_at(&"superpos", pos, -3.0, 0.7)


func note_blast(_e: Dictionary, _pos: Vector3, _radius: float) -> void:
	pass


func cluster(e: Dictionary, pos: Vector3, source: Variant, opts: Dictionary) -> void:
	var cl: Dictionary = e["cluster"]
	var n := int(cl["n"])
	var spread := float(cl["spread"])
	var gap := float(cl["gap"])
	for i in range(1, n):
		var ang := TAU * float(i) / float(n) + _rng.randf() * 0.6
		var r := spread * (0.35 + 0.65 * float((i * 7) % n) / float(maxi(1, n - 1)))
		var p := pos + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var g := _ray(p + Vector3.UP * 4.0, p + Vector3.DOWN * 12.0, 1)
		if not g.is_empty():
			p = (g["position"] as Vector3) + Vector3(0.0, 0.3, 0.0)
		if _pending.size() >= MAX_PENDING:
			_pending.remove_at(0)
		_pending.append({"id": StringName(e["id"]), "pos": p, "t": gap * float(i), "src": source, "quiet": i % 2 == 0, "e": e, "no_cluster": true, "by_hero": bool(opts.get("by_hero", false))})


func _step_pending(dt: float) -> void:
	var i := _pending.size() - 1
	while i >= 0:
		var pb: Dictionary = _pending[i]
		pb["t"] = float(pb["t"]) - dt
		if float(pb["t"]) <= 0.0:
			_pending.remove_at(i)
			var o := {"quiet": bool(pb.get("quiet", false)), "no_cluster": bool(pb.get("no_cluster", false)), "by_hero": bool(pb.get("by_hero", false))}
			detonations += 1
			last_detonation = pb["pos"]
			last_id = StringName(pb["id"])
			BlastTable.apply(StringName(pb["id"]), pb["pos"], pb["src"], o)
			detonated.emit(StringName(pb["id"]), pb["pos"])
		i -= 1


func _step_zones(dt: float) -> void:
	var i := _zones.size() - 1
	while i >= 0:
		var z: Dictionary = _zones[i]
		z["left"] = float(z["left"]) - dt
		z["tick"] = float(z["tick"]) - dt
		var kind := StringName(z["kind"])
		var done := float(z["left"]) <= 0.0
		match kind:
			&"pre":
				_tick_pre(z, dt)
			&"fire":
				if float(z["tick"]) <= 0.0:
					z["tick"] = 0.5
					_tick_fire(z)
			&"smoke":
				if float(z["tick"]) <= 0.0:
					z["tick"] = ZONE_TICK
					_tick_smoke(z)
			&"freeze":
				if float(z["tick"]) <= 0.0:
					z["tick"] = ZONE_TICK
					_tick_freeze(z)
			&"storm":
				_tick_storm(z)
		if done:
			_free_node(z)
			if kind == &"pre":
				var e: Dictionary = z["e"]
				pulled_n += 1
				BlastTable.apply(StringName(e["id"]), z["pos"], z["src"], z["opts"])
				detonations += 1
				last_detonation = z["pos"]
				last_id = StringName(e["id"])
				detonated.emit(StringName(e["id"]), z["pos"])
			_zones.remove_at(i)
		i -= 1


func _tick_pre(z: Dictionary, dt: float) -> void:
	var e: Dictionary = z["e"]
	var pos: Vector3 = z["pos"]
	var radius := float(z["radius"])
	var total := float(z["total"])
	var k := 1.0 - clampf(float(z["left"]) / maxf(total, 0.05), 0.0, 1.0)
	var power := float((e["status"] as Dictionary).get("power", 8.0))
	if float(z["tick"]) <= 0.0:
		z["tick"] = 0.4
		BlastFx.shared().pre_tick(e, pos, radius, k, not z.has("seen"))
		z["seen"] = true
	for en in Gear.living_enemies(get_tree()):
		var to := Vector3(pos.x - en.global_position.x, 0.0, pos.z - en.global_position.z)
		var d := to.length()
		if d < radius and d > 1.0:
			if en.has_method(&"break_shield"):
				en.call(&"break_shield")
			if en.has_method(&"disable"):
				en.call(&"disable", 0.35)
			en.global_position += to / d * minf(power * (0.45 + 0.55 * (1.0 - d / radius)) * dt, d - 0.9)
	for n: Node in get_tree().get_nodes_in_group(&"vehicle"):
		var v := n as Node3D
		if v == null or PlayerWeapon._is_dead(v) or v == Game.player.get(&"vehicle") or not v.has_method(&"apply_impulse"):
			continue
		var tov := Vector3(pos.x - v.global_position.x, 0.0, pos.z - v.global_position.z)
		var dv := tov.length()
		if dv < radius and dv > 2.0:
			v.call(&"apply_impulse", tov / dv * power * 160.0 * dt * (0.5 + 0.5 * (1.0 - dv / radius)), v.global_position)


func _tick_fire(z: Dictionary) -> void:
	var pos: Vector3 = z["pos"]
	var radius := float(z["radius"])
	var dps := float(z["dps"])
	BlastFx.shared().flames(pos, radius, 4)
	for en in Gear.living_enemies(get_tree()):
		if en.global_position.distance_to(pos) < radius:
			burn(en, dps, 2.0)
	for n: Node in get_tree().get_nodes_in_group(&"vehicle"):
		var v := n as Node3D
		if v != null and not PlayerWeapon._is_dead(v) and v.global_position.distance_to(pos) < radius + 1.5 and v.has_method(&"damage"):
			v.call(&"damage", dps * 0.5 * 0.5)
	if Game.civilian_casualties and is_instance_valid(Game.world) and Game.world.get(&"ambient") != null:
		Game.world.ambient.crowd.scare_from(pos, radius * 2.0)


func _tick_smoke(z: Dictionary) -> void:
	var pos: Vector3 = z["pos"]
	var radius := float(z["radius"])
	z["puff"] = float(z["puff"]) + 1.0
	if int(z["puff"]) % 2 == 1:
		BlastFx.shared().smoke_tick(pos, radius, float(z["left"]))
	var hero := Game.player as Player
	var hero_in := is_instance_valid(hero) and hero.global_position.distance_to(pos) < radius
	for en in Gear.living_enemies(get_tree()):
		var ep := en.global_position
		var inside := ep.distance_to(pos) < radius
		var through := hero_in and Throwables._seg_dist(ep, hero.global_position, pos) < radius
		if inside or through:
			if bool(en.get(&"aware")):
				en.set(&"aware", false)
				blinded_n += 1
			if en.get(&"suspicion") != null:
				en.set(&"suspicion", 0.0)


func _tick_freeze(z: Dictionary) -> void:
	var pos: Vector3 = z["pos"]
	var radius := float(z["radius"])
	for en in Gear.living_enemies(get_tree()):
		if en.global_position.distance_to(pos) < radius and en.has_method(&"disable"):
			en.call(&"disable", 0.5)
			frozen_n += 1
	for n: Node in get_tree().get_nodes_in_group(&"vehicle"):
		var v := n as Node3D
		if v != null and not PlayerWeapon._is_dead(v) and v != Game.player.get(&"vehicle") and v.global_position.distance_to(pos) < radius:
			_hold[v.get_instance_id()] = {"node": v, "left": 0.6, "k": 1.0}


func _tick_storm(z: Dictionary) -> void:
	var span := float(z["span"])
	var n := int(z["n"])
	var due := int(floorf((1.0 - clampf(float(z["left"]) / maxf(span, 0.1), 0.0, 1.0)) * float(n)))
	while int(z["made"]) < due:
		z["made"] = int(z["made"]) + 1
		var pos: Vector3 = z["pos"]
		var radius := float(z["radius"])
		var foes := Gear.living_enemies(get_tree())
		var target := pos + Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized() * radius * _rng.randf_range(0.3, 1.0)
		if not foes.is_empty() and _rng.randf() < 0.8:
			var f: Node3D = foes[_rng.randi() % foes.size()]
			if f.global_position.distance_to(pos) < radius * 1.2:
				target = f.global_position
		var g := _ray(target + Vector3.UP * 30.0, target + Vector3.DOWN * 60.0, 1)
		if not g.is_empty():
			target = g["position"]
		if FX.qvfx != null:
			FX.qvfx.bolt(target + Vector3(_rng.randf_range(-3.0, 3.0), 70.0, _rng.randf_range(-3.0, 3.0)), target + Vector3(0.0, 0.5, 0.0), Color(0.75, 0.9, 1.0))
		if _pending.size() >= MAX_PENDING:
			_pending.remove_at(0)
		_pending.append({"id": &"ult_storm_bolt", "pos": target + Vector3(0.0, 0.4, 0.0), "t": 0.06, "src": z["src"], "quiet": (int(z["made"]) % 2 == 0), "e": BlastTable.entry(&"ult_storm_bolt"), "by_hero": true})


# --- bodies: knockback, lift, statuses, burning -----------------------------------------------------------------------------

## Throws a person away: a short ballistic hop with a tumble; `vec` = horizontal launch (m/s), `lift` = vertical (m/s). False for a boss or one already in the air.
func launch_body(en: Node3D, vec: Vector3, lift: float) -> bool:
	if not is_instance_valid(en) or _air.size() >= MAX_AIR:
		return false
	var cfg: Variant = EnemyTypes.TYPES.get(en.get(&"type"))
	if cfg is Dictionary and bool((cfg as Dictionary).get("boss", false)):
		return false
	for a in _air:
		if a["n"] == en:
			return false
	if en.has_method(&"disable"):
		en.call(&"disable", AIR_TIME + 0.4)
	if en.has_method(&"stagger"):
		en.call(&"stagger", 1.6)
	_air.append({"n": en, "vel": vec + Vector3.UP * maxf(lift, 1.2), "t": 0.0, "y0": en.global_position.y, "spin": _rng.randf_range(2.5, 4.5) * (1.0 if _rng.randf() < 0.5 else -1.0), "dir": vec.normalized() if vec.length() > 0.1 else Vector3.FORWARD})
	return true


func _step_air(dt: float) -> void:
	var i := _air.size() - 1
	while i >= 0:
		var a: Dictionary = _air[i]
		var n := a["n"] as Node3D
		if not is_instance_valid(n) or PlayerWeapon._is_dead(n):
			_air.remove_at(i)
			i -= 1
			continue
		a["t"] = float(a["t"]) + dt
		var vel: Vector3 = a["vel"]
		vel.y -= GRAVITY * dt
		a["vel"] = vel
		var pos := n.global_position
		var step := vel * dt
		var wall := _ray(pos + Vector3(0.0, 0.9, 0.0), pos + Vector3(0.0, 0.9, 0.0) + Vector3(step.x, 0.0, step.z).normalized() * 0.7, 1) if Vector2(step.x, step.z).length() > 0.001 else {}
		if not wall.is_empty():
			step.x = 0.0
			step.z = 0.0
			a["vel"] = Vector3(0.0, vel.y, 0.0)
		var nxt := pos + step
		var y0 := float(a["y0"])
		var done := false
		if nxt.y <= y0 and float(a["t"]) > 0.1:
			nxt.y = y0
			done = true
		if float(a["t"]) >= AIR_TIME:
			done = true
		n.global_position = nxt
		if not done:
			n.rotation.x = wrapf(float(a["spin"]) * float(a["t"]), -PI, PI)
		else:
			n.rotation.x = 0.0
			_air.remove_at(i)
		i -= 1


## Applies the status of entry `e` to an enemy hit with falloff share `f`. True when something was applied.
func status(en: Node3D, e: Dictionary, f: float, source: Variant, pos: Vector3) -> bool:
	var st: Dictionary = e["status"]
	if st.is_empty() or not is_instance_valid(en):
		return false
	var kind := StringName(st["kind"])
	var secs := float(st["time"])
	var power := float(st["power"])
	match kind:
		&"burn":
			burn(en, power * (0.6 + 0.4 * f), secs)
			return true
		&"stun":
			if en.has_method(&"disable"):
				en.call(&"disable", secs)
			if en.has_method(&"stagger"):
				en.call(&"stagger", 1.2)
			return true
		&"blind":
			if en.has_method(&"disable"):
				en.call(&"disable", secs * (0.5 + 0.5 * f))
			if bool(en.get(&"aware")):
				en.set(&"aware", false)
			if en.get(&"suspicion") != null:
				en.set(&"suspicion", 0.0)
			blinded_n += 1
			return true
		&"emp":
			if en.has_method(&"disable"):
				en.call(&"disable", secs)
				emp_n += 1
				FX.burst(en.global_position + Vector3(0.0, 1.0, 0.0), Color(0.5, 0.85, 1.0), 6, 4.0, 0.4, 0.0, 1.0)
			return true
		&"freeze":
			if en.has_method(&"disable"):
				en.call(&"disable", secs)
				frozen_n += 1
			return true
		&"shock":
			_chain(en, e, power, f)
			return true
	return false


## Lightning jumps from `from` to up to three neighbours within 7 m: `power` of the centre damage each, arcs drawn with the quantum bolts.
func _chain(from: Node3D, e: Dictionary, power: float, f: float) -> void:
	var base := float((e["dmg"] as Dictionary)["enemy"]) * power * maxf(f, 0.4)
	var hit := 0
	var origin := from.global_position + Vector3(0.0, 1.0, 0.0)
	for en in Gear.living_enemies(get_tree()):
		if en == from or hit >= 3:
			continue
		var c := en.global_position + Vector3(0.0, 1.0, 0.0)
		if c.distance_to(origin) > 7.0:
			continue
		hit += 1
		shocked_n += 1
		en.call(&"damage", TestMode.damage(base))
		if en.has_method(&"stagger"):
			en.call(&"stagger", 0.8)
		if FX.qvfx != null:
			FX.qvfx.bolt(origin, c, Color(0.7, 0.9, 1.0))
	if hit == 0 and FX.qvfx != null:
		FX.qvfx.bolt(origin, origin + Vector3(_rng.randf_range(-2.0, 2.0), 1.5, _rng.randf_range(-2.0, 2.0)), Color(0.7, 0.9, 1.0))


func burn(en: Node3D, dps: float, secs: float) -> void:
	var key := en.get_instance_id()
	if not _burn.has(key) and _burn.size() >= MAX_BURN:
		return
	var b: Dictionary = _burn.get(key, {"node": en, "dps": dps, "left": secs, "acc": 0.0, "fx": 0.0})
	b["dps"] = maxf(float(b["dps"]), dps)
	b["left"] = maxf(float(b["left"]), secs)
	if not _burn.has(key):
		burned_n += 1
	_burn[key] = b


func burning_count() -> int:
	return _burn.size()


func _step_burn(dt: float) -> void:
	for key: int in _burn.keys():
		var b: Dictionary = _burn[key]
		var n := b["node"] as Node3D
		if not is_instance_valid(n) or PlayerWeapon._is_dead(n):
			_burn.erase(key)
			continue
		b["left"] = float(b["left"]) - dt
		b["acc"] = float(b["acc"]) + dt
		b["fx"] = float(b["fx"]) + dt
		if float(b["acc"]) >= 0.5:
			var dmg := float(b["dps"]) * float(b["acc"])
			b["acc"] = 0.0
			n.call(&"damage", TestMode.damage(dmg))
		if float(b["fx"]) >= 0.35:
			b["fx"] = 0.0
			FX.burst(n.global_position + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.45, 0.1), 3, 1.5, 0.5, -2.0, 1.4)
		if float(b["left"]) <= 0.0:
			_burn.erase(key)


## A car is shoved (impulse by its own mass in Vehicle.apply_impulse) and, when the blast is strong enough, tossed: it rises and rolls over before it settles.
func shove_vehicle(v: Node3D, away: Vector3, knock: float, lift: float, pos: Vector3) -> void:
	if absf(knock) > 0.01:
		v.call(&"apply_impulse", away * knock * 900.0, v.global_position - away * 0.8)
	if lift >= 4.0 and _toss.size() < MAX_TOSS and v.get(&"visual") != null and (v.get(&"cls") == &"car" or v.get(&"cls") == &"hover"):
		for t in _toss:
			if t["v"] == v:
				return
		var side := Vector3(-away.z, 0.0, away.x)
		_toss.append({"v": v, "t": 0.0, "dur": 0.7 + 0.045 * lift, "h": clampf(lift * 0.12, 0.5, 1.8), "roll": clampf(lift / 8.0, 0.4, 1.0) * TAU * 0.5, "side": signf(side.dot(Vector3(pos.x - v.global_position.x, 0.0, pos.z - v.global_position.z))) if side.length() > 0.1 else 1.0})
		tossed_n += 1


func _step_toss(dt: float) -> void:
	var i := _toss.size() - 1
	while i >= 0:
		var t: Dictionary = _toss[i]
		var v := t["v"] as Node3D
		if not is_instance_valid(v) or v.get(&"visual") == null:
			_toss.remove_at(i)
			i -= 1
			continue
		t["t"] = float(t["t"]) + dt
		var u := clampf(float(t["t"]) / float(t["dur"]), 0.0, 1.0)
		var model := (v.get(&"visual") as Object).get(&"model") as Node3D
		if model != null:
			var h := float(t["h"]) * 4.0 * u * (1.0 - u)
			var roll := float(t["roll"]) * float(t["side"]) * (1.0 - pow(1.0 - u, 3.0))
			if u >= 1.0:
				roll = 0.0
			model.position = Vector3(0.0, h, 0.0)
			model.rotation = Vector3(model.rotation.x, 0.0, roll)
		if u >= 1.0:
			_toss.remove_at(i)
		i -= 1


func status_vehicle(v: Node3D, e: Dictionary, f: float) -> void:
	var st: Dictionary = e["status"]
	var kind := StringName(st["kind"])
	var secs := float(st["time"])
	if kind == &"emp":
		_hold[v.get_instance_id()] = {"node": v, "left": secs, "k": 0.35 + 0.4 * (1.0 - f)}
		emp_n += 1
	elif kind == &"freeze":
		_hold[v.get_instance_id()] = {"node": v, "left": secs, "k": 1.0}
		frozen_n += 1


func _step_hold(dt: float) -> void:
	for key: int in _hold.keys():
		var h: Dictionary = _hold[key]
		var v := h["node"] as Node3D
		if not is_instance_valid(v) or PlayerWeapon._is_dead(v):
			_hold.erase(key)
			continue
		h["left"] = float(h["left"]) - dt
		var k := clampf(float(h["k"]), 0.0, 1.0)
		var vel: Variant = v.get(&"vel")
		if vel is Vector3:
			v.set(&"vel", (vel as Vector3) * maxf(0.0, 1.0 - (2.0 + 4.0 * k) * dt))
			v.set(&"speed", float(v.get(&"speed")) * maxf(0.0, 1.0 - (2.0 + 4.0 * k) * dt))
		if float(h["left"]) <= 0.0:
			_hold.erase(key)


func shove_hero(away: Vector3, knock: float, lift: float) -> void:
	var p := Game.player as Player
	if p == null:
		return
	var a := Vector3(away.x, 0.0, away.z)
	a = a.normalized() if a.length() > 0.1 else Vector3.ZERO
	p.velocity += a * knock * 0.45 + Vector3.UP * maxf(lift, 0.0) * 0.45
	p.camera_rig.bump(clampf(absf(knock) / 20.0 + lift / 30.0, 0.1, 0.7))


func status_hero(e: Dictionary, f: float, _pos: Vector3) -> void:
	var st: Dictionary = e["status"]
	if StringName(st["kind"]) == &"blind" and not BlastTable.hero_immune():
		BlastFx.shared().screen_flash(clampf(f, 0.2, 1.0), 1.6)


# --- pooled nodes ---------------------------------------------------------------------------------------------------------

func _mesh(kind: StringName) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var m: Mesh
	match kind:
		&"ball":
			var s := SphereMesh.new()
			s.radius = 0.13
			s.height = 0.26
			s.radial_segments = 10
			s.rings = 5
			m = s
		&"rocket":
			var c := CapsuleMesh.new()
			c.radius = 0.1
			c.height = 0.9
			c.radial_segments = 8
			c.rings = 3
			m = c
		&"shell":
			var c2 := CapsuleMesh.new()
			c2.radius = 0.07
			c2.height = 0.55
			c2.radial_segments = 8
			c2.rings = 3
			m = c2
		&"bomb":
			var c3 := CapsuleMesh.new()
			c3.radius = 0.22
			c3.height = 1.4
			c3.radial_segments = 10
			c3.rings = 4
			m = c3
		&"puck":
			var cy := CylinderMesh.new()
			cy.top_radius = 0.32
			cy.bottom_radius = 0.34
			cy.height = 0.1
			cy.radial_segments = 14
			m = cy
		&"brick":
			var b := BoxMesh.new()
			b.size = Vector3(0.36, 0.14, 0.26)
			m = b
		&"crate":
			var b2 := BoxMesh.new()
			b2.size = Vector3(1.0, 0.8, 1.0)
			m = b2
		_:
			var s2 := SphereMesh.new()
			s2.radius = 0.12
			s2.height = 0.24
			m = s2
	_meshes[kind] = m
	return m


func _take_node() -> MeshInstance3D:
	for c in _pool:
		if not c.visible:
			c.visible = true
			return c
	var n := MeshInstance3D.new()
	n.top_level = true
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.material_override = Gear.fx_material(Color(1.0, 0.6, 0.2, 0.95), true)
	add_child(n)
	_pool.append(n)
	n.visible = true
	return n


func _free_node(it: Dictionary) -> void:
	var n: Variant = it.get("node")
	if n is MeshInstance3D and is_instance_valid(n):
		(n as MeshInstance3D).visible = false


func _style_node(it: Dictionary, beacon := false) -> void:
	var n := it["node"] as MeshInstance3D
	if n == null:
		return
	var e: Dictionary = it["e"]
	var dv: Dictionary = e["deliver"]
	var col: Color = BlastElements.color(StringName(e["element"]), "mid")
	var kind := StringName(it["kind"])
	var mesh_kind := &"ball"
	match kind:
		&"proj":
			mesh_kind = &"rocket" if StringName(dv.get("mode", &"throw")) == &"launch" and float(dv.get("speed", 0.0)) >= 36.0 else &"ball"
			if StringName(dv.get("mode", &"throw")) == &"launch" and float(dv.get("speed", 0.0)) < 36.0 and not bool(dv.get("lob", false)):
				mesh_kind = &"rocket"
		&"bomb":
			mesh_kind = &"bomb" if float(e["radius"]) >= 9.0 else &"shell"
		&"mine":
			mesh_kind = &"puck" if float(dv.get("wire", 0.0)) <= 0.0 and not bool(dv.get("remote", false)) else &"brick"
		&"marker":
			mesh_kind = &"ball"
		&"strike":
			mesh_kind = &"puck"
		&"crate":
			mesh_kind = &"crate"
	n.mesh = _mesh(mesh_kind)
	var mat := n.material_override as StandardMaterial3D
	mat.albedo_color = Color(col.r, col.g, col.b, 0.95)
	var s := 1.0
	if kind == &"strike":
		s = 1.4
	n.scale = Vector3.ONE * s
	it["mesh_kind"] = mesh_kind
	it["col"] = col
	n.visible = true


func _place(it: Dictionary) -> void:
	var n := it["node"] as MeshInstance3D
	if n == null or not is_instance_valid(n):
		return
	var pos: Vector3 = it["pos"]
	var kind := StringName(it["kind"])
	var mk := StringName(it.get("mesh_kind", &"ball"))
	if mk == &"rocket" or mk == &"shell" or mk == &"bomb":
		var vel: Vector3 = it["vel"]
		if vel.length() > 0.5:
			var y := vel.normalized()
			var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
			var z := x.cross(y)
			n.global_transform = Transform3D(Basis(x, y, z), pos)
			return
	if kind == &"mine" and it.has("normal"):
		var up: Vector3 = it["normal"]
		var x2 := up.cross(Vector3.FORWARD if absf(up.z) < 0.95 else Vector3.RIGHT).normalized()
		var z2 := x2.cross(up)
		n.global_transform = Transform3D(Basis(x2, up, z2), pos)
		return
	n.global_position = pos


func _pulse(it: Dictionary) -> void:
	var n := it["node"] as MeshInstance3D
	if n == null or not is_instance_valid(n):
		return
	var mat := n.material_override as StandardMaterial3D
	var col: Color = it.get("col", Color(1.0, 0.5, 0.2))
	var b := 0.45 + 0.55 * (0.5 + 0.5 * sin(float(it["t"]) * 9.0))
	mat.albedo_color = Color(col.r * b + 0.2, col.g * b, col.b * b, 0.95)
