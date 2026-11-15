class_name SnakeHolds
extends RefCounted
## ENEMIES UNDER SNAKE CONTROL (wave 115, combat side): everything that grips, drags, wraps or nets an enemy goes through here, so every enemy type (drones, troopers, specialists, aliens, roster foes)
## behaves the same and the snakes drawn round it are always the ones the rules say. A record per enemy:
##   kind  &"wrap"   coils round the body: it cannot move or shoot, takes crush damage per second (COIL BOMB, CONSTRICTOR MINE, SNAKE TRAP)
##         &"net"    like wrap, plus the gun is gone (SNAKE NET: the shot timer is pushed out while it lasts)
##         &"snare"  held still without damage (the short hold at the end of a pull, a flare's blind)
##         &"drag"   pulled along a straight line to a point (SNAKE PULL), then a short snare
##         &"lift"   carried by the grab verb (the verb places the body; this keeps it stunned and wrapped)
## Bosses are never held (they are only hurt); big enemies (brutes, heavies) are held for half the time. Every hold stuns with Drone.disable / AlienCreature.disable (the same call the blasts use),
## so the AI of the enemy needs no knowledge of snakes. Counters (tests wait on these): wraps, nets, drags, snares, lifts, crush_damage.

const MAX_RECS := 24
const BOSS_RESIST := 0.0
const HEAVY_RESIST := 0.5
const STUN_REFRESH := 0.22

var war: SnakeWar
var recs: Dictionary = {}                      ## instance id -> record
var wraps := 0
var nets := 0
var drags := 0
var snares := 0
var lifts := 0
var disarms := 0
var crush_damage := 0.0
var _rq := PhysicsRayQueryParameters3D.new()


func _init(owner_war: SnakeWar = null) -> void:
	war = owner_war
	_rq.collision_mask = Game.L_WORLD


func count() -> int:
	return recs.size()


func is_held(en: Node) -> bool:
	return en != null and is_instance_valid(en) and recs.has(en.get_instance_id())


func kind_of(en: Node) -> StringName:
	return StringName((recs[en.get_instance_id()] as Dictionary)["kind"]) if is_held(en) else &""


func clear() -> void:
	for k: Variant in recs.keys():
		_end(recs[k] as Dictionary, false)
	recs.clear()


## The seconds a hold lasts on this enemy (0 = it cannot be held: a boss).
func hold_time(en: Node, secs: float) -> float:
	if SnakeAim.is_boss(en):
		return 0.0
	secs += SkillTree.snakewar_grip()
	if SnakeAim.heavy(en):
		secs *= HEAVY_RESIST
	return secs


## Wraps, nets or snares `en` for `secs` (+ the TIGHT GRIP skill, halved for the big ones). opts: dps (crush damage per second), kind, coils (snakes drawn round it), color, disarm. False when it cannot be held.
func hold(en: Node3D, secs: float, opts: Dictionary = {}) -> bool:
	if not SnakeAim.is_live_enemy(en):
		return false
	var t := hold_time(en, secs)
	if t <= 0.0:
		_hit_react(en)
		return false
	var key := en.get_instance_id()
	var rec: Dictionary = recs.get(key, {})
	if rec.is_empty():
		if recs.size() >= MAX_RECS:
			return false
		rec = {"node": en, "kind": &"snare", "left": 0.0, "dps": 0.0, "acc": 0.0, "refresh": 0.0, "bodies": [], "disarm": false, "pulse": 0.0}
		recs[key] = rec
	rec["left"] = maxf(float(rec["left"]), t)
	rec["dps"] = maxf(float(rec["dps"]), float(opts.get("dps", 0.0)))
	var kind := StringName(opts.get("kind", &"wrap"))
	if kind == &"net" or StringName(rec["kind"]) == &"snare" or StringName(rec["kind"]) == &"drag":
		rec["kind"] = kind
	rec["disarm"] = bool(rec["disarm"]) or bool(opts.get("disarm", false))
	var color: Color = opts.get("color", SnakeRows.VIOLET)
	rec["color"] = color
	_stun(en, t)
	match kind:
		&"net":
			nets += 1
		&"snare":
			snares += 1
		_:
			wraps += 1
	_coils(rec, en, int(opts.get("coils", 2)), color, t)
	return true


## Pulls `en` along a straight line to `to` in `dur` seconds, then snares it for `after` seconds. False when it cannot be moved (a boss).
func drag(en: Node3D, to: Vector3, dur: float, after := 1.2) -> bool:
	if not SnakeAim.is_live_enemy(en) or SnakeAim.is_boss(en):
		return false
	var key := en.get_instance_id()
	var rec: Dictionary = recs.get(key, {})
	if rec.is_empty():
		if recs.size() >= MAX_RECS:
			return false
		rec = {"node": en, "kind": &"drag", "left": 0.0, "dps": 0.0, "acc": 0.0, "refresh": 0.0, "bodies": [], "disarm": false, "pulse": 0.0}
		recs[key] = rec
	rec["kind"] = &"drag"
	rec["from"] = en.global_position
	rec["to"] = to
	rec["t"] = 0.0
	rec["dur"] = maxf(dur, 0.08)
	rec["after"] = after
	rec["left"] = dur + after
	drags += 1
	_stun(en, dur + after)
	return true


## The grab verb carries `en`: the verb moves the body, this keeps it stunned and wrapped until `release`.
func lift(en: Node3D, color: Color = SnakeRows.MAGENTA) -> bool:
	if not SnakeAim.is_live_enemy(en) or SnakeAim.is_boss(en):
		return false
	var key := en.get_instance_id()
	var rec: Dictionary = {"node": en, "kind": &"lift", "left": 8.0, "dps": 0.0, "acc": 0.0, "refresh": 0.0, "bodies": [], "disarm": false, "pulse": 0.0}
	recs[key] = rec
	lifts += 1
	_stun(en, 0.6)
	_coils(rec, en, 2, color, 8.0)
	return true


func release(en: Node, keep_secs := 0.0) -> void:
	if en == null or not is_instance_valid(en):
		return
	var key := en.get_instance_id()
	if not recs.has(key):
		return
	var rec: Dictionary = recs[key]
	if keep_secs > 0.0:
		rec["kind"] = &"snare"
		rec["left"] = keep_secs
		return
	_end(rec, true)
	recs.erase(key)


## The gun is out of the hand: its shot timer is pushed out for `secs` (the net does it for as long as it holds).
func disarm(en: Node3D, secs: float) -> void:
	if not SnakeAim.is_live_enemy(en):
		return
	disarms += 1
	var key := en.get_instance_id()
	var rec: Dictionary = recs.get(key, {})
	if rec.is_empty():
		if recs.size() >= MAX_RECS:
			return
		rec = {"node": en, "kind": &"disarm", "left": secs, "dps": 0.0, "acc": 0.0, "refresh": 0.0, "bodies": [], "disarm": true, "pulse": 0.0}
		recs[key] = rec
	rec["disarm"] = true
	rec["left"] = maxf(float(rec["left"]), secs)
	_push_shot_timer(en)
	_stun(en, minf(secs, 0.9))


func _hit_react(en: Node3D) -> void:
	if en.has_method(&"stagger"):
		en.call(&"stagger", 1.0)


func _stun(en: Node3D, secs: float) -> void:
	if en.has_method(&"disable"):
		en.call(&"disable", secs + 0.15)
	if en.has_method(&"stagger"):
		en.call(&"stagger", 1.1)
	if en.get(&"aware") == false:
		en.set(&"aware", true)


func _push_shot_timer(en: Node3D) -> void:
	var f: Variant = en.get(&"_fire_t")
	if f is float:
		en.set(&"_fire_t", maxf(float(f), 1.0))


## Coil snakes drawn round the body (they follow the enemy node, so a drag or a throw carries them along).
func _coils(rec: Dictionary, en: Node3D, n: int, color: Color, secs: float) -> void:
	var sw := war.swarm if war != null else null
	if sw == null:
		return
	var bodies: Array = rec["bodies"]
	for b in bodies.duplicate():
		if b == null or (b as SnakeSwarm.Body).dead:
			bodies.erase(b)
	var want := clampi(n, 0, 4 if Game.quality > 0 else 2)
	var radius := clampf(float(en.get(&"radius") if en.get(&"radius") != null else 0.5) * 0.85, 0.5, 1.1)
	var top := clampf(float(en.get(&"center_y") if en.get(&"center_y") != null else 0.9) * 1.95, 1.4, 2.6)
	while bodies.size() < want:
		var k := bodies.size()
		var b := sw.spawn(&"coil", en.global_position, {"anchor": en, "radius": radius, "y0": 0.08 + 0.12 * float(k), "y1": top * (0.78 + 0.1 * float(k)), "turns": 2.2 + 0.4 * float(k % 2),
				"spin": 2.2 + 0.5 * float(k), "phase": TAU * float(k) / float(maxi(want, 1)), "color": color, "thick": 0.1 + 0.015 * float(k % 2), "len": top * 3.2, "life": secs, "prio": 2, "head": 1.0})
		if b == null:
			break
		bodies.append(b)
	for b in bodies:
		var body := b as SnakeSwarm.Body
		if body != null and not body.dead:
			body.life = maxf(body.life, body.age + secs)


func tick(dt: float) -> void:
	if recs.is_empty():
		return
	for key: Variant in recs.keys():
		var rec: Dictionary = recs[key]
		var en := rec["node"] as Node3D
		if en == null or not is_instance_valid(en) or not en.is_inside_tree() or bool(en.get(&"dead")) or (en.get(&"active") != null and not bool(en.get(&"active"))):
			_end(rec, false)
			recs.erase(key)
			continue
		var kind: StringName = rec["kind"]
		rec["left"] = float(rec["left"]) - dt
		rec["refresh"] = float(rec["refresh"]) - dt
		if kind == &"drag":
			_tick_drag(rec, en, dt)
		if float(rec["refresh"]) <= 0.0 and kind != &"disarm":
			rec["refresh"] = STUN_REFRESH
			if en.has_method(&"disable"):
				en.call(&"disable", STUN_REFRESH + 0.2)
		if bool(rec["disarm"]):
			_push_shot_timer(en)
		var dps := float(rec["dps"])
		if dps > 0.0 and kind != &"drag":
			rec["acc"] = float(rec["acc"]) + dt
			if float(rec["acc"]) >= 0.5:
				var amount := TestMode.damage(dps * 0.5 * war.dmg_mult())
				rec["acc"] = 0.0
				crush_damage += amount
				en.call(&"damage", amount)
				rec["pulse"] = float(rec["pulse"]) + 1.0
				BlastCredit.dealt(en, amount, Vector3.INF, int(rec["pulse"]) % 2 == 0)
				FX.burst(SnakeAim.center_of(en), Color(rec.get("color", SnakeRows.VIOLET)), 3, 2.5, 0.25, 0.0, 0.6)
		if float(rec["left"]) <= 0.0 and kind != &"lift":
			_end(rec, true)
			recs.erase(key)


func _tick_drag(rec: Dictionary, en: Node3D, dt: float) -> void:
	var t := float(rec["t"]) + dt
	rec["t"] = t
	var dur := float(rec["dur"])
	if t > dur + 0.02:
		if StringName(rec["kind"]) == &"drag":
			rec["kind"] = &"snare"
			rec["left"] = float(rec.get("after", 1.0))
			_stun(en, float(rec["left"]))
			if war != null:
				war.verbs.on_drag_done(en)
		return
	var k := clampf(t / dur, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	var from: Vector3 = rec["from"]
	var to: Vector3 = rec["to"]
	var want := from.lerp(to, k)
	var cur := en.global_position
	_rq.from = cur + Vector3(0.0, 0.9, 0.0)
	_rq.to = want + Vector3(0.0, 0.9, 0.0)
	var hit := en.get_world_3d().direct_space_state.intersect_ray(_rq)
	if not hit.is_empty():
		rec["t"] = dur + 0.05                          # a wall: the pull ends where it stands
		return
	en.global_position = want


func _end(rec: Dictionary, fade: bool) -> void:
	for b in rec["bodies"]:
		var body := b as SnakeSwarm.Body
		if body != null and not body.dead:
			if fade:
				body.life = body.age + SnakeSwarm.FADE
			else:
				body.dead = true
	(rec["bodies"] as Array).clear()
