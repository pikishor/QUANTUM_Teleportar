class_name WeaponMech
extends RefCounted
## The mechanics of the roster of wave 113 (scripts/player/weapon_defs_v3.gd): one per PlayerWeapon (`weapon.mech`), like EnergyArms. Every mechanic is a key of the weapon's def, so a weapon is
## data; this file is the code that reads them. PlayerWeapon calls in with one line each (grep "mech." there).
##   on a hit      hit_mult (opener, final round, ramp, mark, sunder, kill streak, fire mode) then on_hit (knock, pull, slow, mark, shock, freeze, dissolve, crit blast, ammo type effects)
##   after a shot  after_shot (pierce_n: through enemies; ricochet: off a wall into the next enemy), cone_fire (sonic cone), mist_puffs
##   on a kill     on_kill (p_refund, p_heal, p_hot)
##   alt-fires     alt (ub_nade, zoom, brace, mode, surge, spin, shove, throw_melee)
##   every frame   tick (the timers of the statuses; a slowed enemy is held back, a shocked one takes damage over time ...), spread_mult / kick_mult / interval_mult / burst_n
## Status effects work on any node that has the enemy contract (damage, stagger, disable, center, max_hp), the old drones and the alien creatures alike: slow holds the body back by moving it less than it
## wanted this frame, so no enemy script had to change. Counters (lifetime, for tests): knocks pulls slows marks_made zaps chills freezes dissolves ricochets pierces crit_blasts refunds heals openers finals
## cones ub_shots zoom_toggles braces spins shoves throws surges.

const OPENER_PAUSE := 1.0                     ## seconds without a shot before the first round counts as an opener
const RAMP_RESET := 1.2                       ## seconds on another target (or none) that end a ramp
const HOT_TIME := 4.0                         ## seconds a kill streak bonus lasts after the last kill
const HOT_MAX := 0.5
const STEADY_HOLD := 0.5                      ## seconds of aiming standing still for the full steady bonus
const BRACE_SPREAD := 0.55
const BRACE_KICK := 0.5
const ZAP_TICK := 0.25
const DISSOLVE_TICK := 0.5
const MARK_FX := 0.7
const CHILL_DECAY := 3.0                      ## seconds a stack of cold lasts without a new hit
const CHILL_SLOW := 0.2                       ## speed lost per stack of cold
const MAX_TRACKED := 20
const BIG_HP := 400.0                         ## bosses: knock / pull / freeze count for a third
const FX_PER_SECOND := 8.0                    ## the status effects share a budget of this many particle bursts a second (every live emitter is a draw)

var w: PlayerWeapon
var knocks := 0
var pulls := 0
var slows := 0
var marks_made := 0
var zaps := 0
var chills := 0
var freezes := 0
var dissolves := 0
var ricochets := 0
var pierces := 0
var crit_blasts := 0
var refunds := 0
var heals := 0
var openers := 0
var finals := 0
var cones := 0
var ub_shots := 0
var zoom_toggles := 0
var braces := 0
var spins := 0
var shoves := 0
var throws := 0
var surges := 0
var ramp_peak := 0
var hot_peak := 0.0

var _marks := {}                              ## instance id -> {node, left, bonus, fx}
var _chill := {}                              ## instance id -> {node, stacks, left}
var _zap := {}                                ## instance id -> {node, left, acc, dps, fx}
var _dis := {}                                ## instance id -> {node, left, acc, pct}
var _slow := {}                               ## instance id -> {node, left, k, last}
var _ramp_id := 0
var _ramp_n := 0
var _ramp_t := 0.0
var _hot := 0.0
var _hot_t := 0.0
var _idle := 99.0                             ## seconds since the last shot
var _opener_now := false                      ## the shot being fired is an opener
var _final_now := false                       ## ... the last round of the magazine
var _steady_t := 0.0
var _aiming := false
var _moving := false
var _brace := false
var _zoom_alt := false
var _mode_burst := false
var _surge_t := 0.0
var _surge_k := 1.0
var _fx_tokens := 4.0
var _ray := PhysicsRayQueryParameters3D.new()


func _init(weapon: PlayerWeapon) -> void:
	w = weapon
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true
	_ray.collision_mask = Game.L_WORLD


func reset() -> void:
	_marks.clear()
	_chill.clear()
	_zap.clear()
	_dis.clear()
	_slow.clear()
	_ramp_id = 0
	_ramp_n = 0
	_ramp_t = 0.0
	_hot = 0.0
	_hot_t = 0.0
	_idle = 99.0
	_steady_t = 0.0
	_surge_t = 0.0
	_surge_k = 1.0
	on_load()


## The weapon in hand changed (or its parts): toggles of the alt-fires end.
func on_load() -> void:
	_brace = false
	_zoom_alt = false
	_mode_burst = false


## Is a status of this kind live on that enemy (tests).
func has_status(kind: StringName, target: Object) -> bool:
	if target == null:
		return false
	var id := target.get_instance_id()
	match kind:
		&"mark":
			return _marks.has(id)
		&"zap":
			return _zap.has(id)
		&"chill":
			return _chill.has(id)
		&"dissolve":
			return _dis.has(id)
		&"slow":
			return _slow.has(id)
	return false


func chill_stacks(target: Object) -> int:
	return int((_chill.get(target.get_instance_id(), {}) as Dictionary).get("stacks", 0)) if target != null else 0


# --- numbers the weapon reads every frame ----------------------------------------------------------------------------------------

func note_input(aiming: bool, moving: bool, dt: float) -> void:
	_aiming = aiming
	_moving = moving
	if aiming and not moving:
		_steady_t = minf(STEADY_HOLD, _steady_t + dt)
	else:
		_steady_t = 0.0
	if _brace and moving:
		_brace = false


## Dispersion multiplier: the steady perk (aiming still), the deployed bipod.
func spread_mult() -> float:
	var m := 1.0
	var st := float(w.def.get("steady", 0.0))
	if st > 0.0:
		m *= 1.0 - st * clampf(_steady_t / STEADY_HOLD, 0.0, 1.0)
	if _brace:
		m *= BRACE_SPREAD
	return m


func kick_mult() -> float:
	return BRACE_KICK if _brace else 1.0


## Fire interval multiplier: OVERDRIVE (faster), the burst mode of FIRE MODE (a burst takes longer).
func interval_mult() -> float:
	var m := 1.0
	if _surge_t > 0.0:
		m *= _surge_k
	if _mode_burst:
		m *= float(w.def.get("burst_mode_n", 3)) * 0.85
	return m


## Rounds per trigger pull: the def's burst, or the burst of FIRE MODE.
func burst_n() -> int:
	if _mode_burst:
		return int(w.def.get("burst_mode_n", 3))
	return int(w.def.get("burst", 1))


## Ammo types the weapon in hand can use (indices of WeaponDefs.AMMO_TYPES): the def's list, else the three classic ones.
func allowed_ammo() -> Array:
	var l: Variant = w.def.get("ammo_types", null)
	if l is Array and not (l as Array).is_empty():
		return l
	return [0, 1, 2]


func allows(index: int) -> bool:
	return allowed_ammo().has(index)


## The next allowed ammo type after `cur` (wraps).
func next_ammo(cur: int) -> int:
	var l := allowed_ammo()
	var at := l.find(cur)
	return int(l[(at + 1) % l.size()]) if at >= 0 else int(l[0])


# --- shots ----------------------------------------------------------------------------------------------------------------------

## A trigger pull (or a melee swing) starts: decides whether this one is an opener / the last round, then restarts the idle timer.
func on_shoot() -> void:
	var d := w.def
	_opener_now = d.has("opener") and _idle >= OPENER_PAUSE
	_final_now = d.has("final") and w.ammo == 1
	if _opener_now:
		openers += 1
	if _final_now:
		finals += 1
	_idle = 0.0
	_layer_sound()


## Extra layer of a shot (def "layer": a sound name played under the shot, tools/audio/make_weapons_v3.py).
func _layer_sound() -> void:
	var l: Variant = w.def.get("layer", null)
	if l != null and StringName(l) != &"":
		Sfx.play(StringName(l), float(w.def.get("layer_vol", -8.0)), randf_range(0.95, 1.05))


## Damage multiplier of one hit on `target` (before the weapon's own number): opener, last round, ramp, mark, sunder, kill streak, burst mode.
func hit_mult(target: Node) -> float:
	var d := w.def
	var m := 1.0
	if _opener_now:
		m *= float(d["opener"])
	if _final_now:
		m *= float(d["final"])
	if _mode_burst:
		m *= 1.1
	if d.has("ramp"):
		var id := target.get_instance_id()
		if id != _ramp_id or _ramp_t <= 0.0:
			_ramp_id = id
			_ramp_n = 0
		m *= 1.0 + float(d["ramp"]) * float(_ramp_n)
		_ramp_n = mini(_ramp_n + 1, int(d.get("ramp_max", 5)))
		_ramp_peak_update()
		_ramp_t = RAMP_RESET
	if not _marks.is_empty():
		var mk: Variant = _marks.get(target.get_instance_id(), null)
		if mk != null:
			m *= 1.0 + float((mk as Dictionary)["bonus"])
	if d.has("sunder") and _armoured(target):
		m *= 1.0 + float(d["sunder"])
	if _hot_t > 0.0:
		m *= 1.0 + _hot
	return m


func _ramp_peak_update() -> void:
	ramp_peak = maxi(ramp_peak, _ramp_n)


static func _armoured(target: Node) -> bool:
	if target.has_method(&"shield_blocks"):
		return true
	var sh: Variant = target.get(&"shield_hp")
	if (sh is float or sh is int) and float(sh) > 0.0:
		return true
	var pl: Variant = target.get(&"plates")
	return (pl is float or pl is int) and float(pl) > 0.0


## After a hit landed on `target` at `hit`: knock, pull, the statuses of the def and of the ammo type, a crit blast.
func on_hit(target: Node, hit: Vector3, crit: bool) -> void:
	if not (target is Node3D):
		return
	var d := w.def
	var am := w.ammo_info()
	if crit and d.has("crit_blast"):                                              # a headshot bursts into shards, also the one that kills
		crit_blasts += 1
		w.arms.blast(hit, float(d["crit_blast"]), float(d.get("crit_blast_dmg", 20.0)), 30.0, &"plasma", true)
	if am.has("splash") and w.shots_fired % 2 == 0:
		w.arms.blast(hit, float(am["splash"]), float(am.get("splash_dmg", 10.0)), 20.0, &"fire", true)
	if PlayerWeapon._is_dead(target):
		return
	var big := _is_big(target)
	if d.has("knock"):
		_push(target, float(d["knock"]) * (0.33 if big else 1.0))
	if d.has("pull"):
		_pull(target, float(d["pull"]) * (0.33 if big else 1.0))
	if d.has("slow"):
		_add_slow(target, float(d["slow"]), float(d.get("slow_k", 0.5)))
	if d.has("mark"):
		_add_mark(target, float(d["mark"]), float(d.get("mark_time", 6.0)))
	if d.has("zap"):
		_add_zap(target, float(d["zap"]), float(d.get("zap_time", 2.0)), int(d.get("zap_chain", 0)))
	if d.has("chill"):
		_add_chill(target, int(d["chill"]), int(d.get("chill_max", 3)), float(d.get("freeze_time", 2.0)))
	if d.has("dissolve"):
		_add_dissolve(target, float(d["dissolve"]), float(d.get("dissolve_time", 3.0)))
	if am.has("burn"):
		w._ignite_ex(target, float(am["burn"]) * _dmg_mult(), float(am.get("burn_time", 2.5)))
	if am.has("zap"):
		_add_zap(target, float(am["zap"]), float(am.get("zap_time", 1.5)), int(am.get("zap_chain", 0)))
	if am.has("dissolve"):
		_add_dissolve(target, float(am["dissolve"]), float(am.get("dissolve_time", 2.5)))


## A kill: refund rounds, heal, start or feed the kill streak.
func on_kill(target: Node) -> void:
	var d := w.def
	if d.has("p_refund"):
		var n := int(d["p_refund"])
		var before := w.ammo
		w.ammo = mini(w.mag, w.ammo + n)
		if w.ammo > before:
			refunds += 1
	if d.has("p_heal") and w._player != null and w._player.has_method(&"heal"):
		w._player.call(&"heal", float(d["p_heal"]))
		heals += 1
	if d.has("p_hot"):
		_hot = minf(HOT_MAX, _hot + float(d["p_hot"]))
		_hot_t = HOT_TIME
		hot_peak = maxf(hot_peak, _hot)
	_marks.erase(target.get_instance_id())


# --- after a shot ---------------------------------------------------------------------------------------------------------------

## The shot just resolved (`ls` = PlayerWeapon.last_shot): pierce_n carries it through more enemies, ricochet bounces a wall hit to the nearest enemy.
func after_shot(ls: Dictionary, k: float) -> void:
	var d := w.def
	if ls.is_empty():
		return
	var origin: Vector3 = ls["origin"]
	var dir: Vector3 = ls["dir"]
	var hit: Vector3 = ls["hit"]
	var target: Object = ls.get("target", null)
	if d.has("pierce_n") and target != null and is_instance_valid(target):
		_pierce(origin, dir, hit, int(d["pierce_n"]), float(d.get("pierce_k", 0.7)), k, target)
	if d.has("ricochet") and (target == null or not is_instance_valid(target)) and not bool(ls.get("civ", false)):
		var dist := float(ls.get("dist", 0.0))
		if dist < float(d["range"]) - 0.5:
			_ricochet(hit - dir * 0.3, float(d["ricochet"]), float(d.get("ricochet_k", 0.7)) * k)


func _pierce(origin: Vector3, dir: Vector3, from_hit: Vector3, n: int, pk: float, k0: float, first: Object) -> void:
	var cands: Array = []
	for e: Node in w.get_tree().get_nodes_in_group(&"enemy"):
		if e == first or not (e is Node3D) or PlayerWeapon._is_dead(e):
			continue
		var zh := HitZones.of(e, origin, dir)
		if zh.is_empty():
			continue
		var t := float(zh["t"])
		if t <= origin.distance_to(from_hit) + 0.05 or t > float(w.def["range"]):
			continue
		cands.append([t, e, zh["zone"]])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var done := 0
	var at := from_hit
	var kk := k0 * pk
	for c: Array in cands:
		if done >= n:
			break
		var e: Node = c[1]
		var pt := origin + dir * float(c[0])
		if _blocked(at, pt):
			continue
		FX.tracer(at, pt, w.def["tracer"])
		w._hit_target(e, pt, -dir, kk, c[2])
		pierces += 1
		done += 1
		at = pt
		kk *= pk


func _ricochet(from: Vector3, radius: float, k: float) -> void:
	var best: Node = null
	var best_d := radius
	for e: Node in w.get_tree().get_nodes_in_group(&"enemy"):
		if not (e is Node3D) or not e.has_method(&"center") or PlayerWeapon._is_dead(e):
			continue
		var c: Vector3 = e.call(&"center")
		var dist := c.distance_to(from)
		if dist < best_d and not _blocked(from, c):
			best_d = dist
			best = e
	if best == null:
		return
	var c2: Vector3 = best.call(&"center")
	FX.tracer(from, c2, w.def["tracer"])
	FX.burst(from, w.def["tracer"], 4, 3.0, 0.25, 0.0, 0.8)
	ricochets += 1
	w._hit_target(best, c2, (from - c2).normalized(), k, HitZones.BODY)


## Is the straight line a -> b blocked by the world?
func _blocked(a: Vector3, b: Vector3) -> bool:
	if a.distance_to(b) < 0.2:
		return false
	_ray.from = a
	_ray.to = b
	_ray.exclude = w._exclude_base
	return not w._player.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()


## SONIC CANNON / KINETIC REPULSOR: a cone of force instead of a ray: every enemy inside the cone and the range takes the damage (falling off with distance), is shoved back and staggered.
func cone_fire() -> void:
	var d := w.def
	var p := w._player
	var cam := p.camera_rig.camera.global_basis
	var fwd := -cam.z
	var from := p.body.muzzle.global_position
	var reach := float(d.get("cone_range", 12.0))
	var cos_a := cos(clampf(float(d["cone"]), 0.1, 1.4))
	cones += 1
	var col: Color = d["tracer"]
	for i in 3:
		FX.burst(from + fwd * (reach * (0.25 + 0.3 * float(i))), col, 5, 3.0 + 2.0 * float(i), 0.3, 0.0, 1.0 + 0.5 * float(i))
	FX.tracer(from, from + fwd * reach, col)
	FX.shake(0.05)
	for e: Node in w.get_tree().get_nodes_in_group(&"enemy"):
		if not (e is Node3D) or not e.has_method(&"center") or PlayerWeapon._is_dead(e):
			continue
		var c: Vector3 = e.call(&"center")
		var off := c - from
		var dist := off.length() - PlayerWeapon._radius_of(e)
		if dist > reach or off.normalized().dot(fwd) < cos_a:
			continue
		if _blocked(from, c):
			continue
		var fall := lerpf(1.0, 0.4, clampf(dist / reach, 0.0, 1.0))
		w._hit_target(e, c, -fwd, fall, HitZones.BODY)
	var city := Game.world as City
	if city != null and city.ambient != null and Game.civilian_casualties:
		city.ambient.blast_civilians(from + fwd * reach * 0.5, reach * 0.4, true, float(d["damage"]) * 0.5, &"sonic")


## A mist instead of a tracer: cold or toxic puffs along the line (the sprayers).
func mist_puffs(mz: Vector3, hit: Vector3) -> void:
	var col: Color = w.def["tracer"]
	var dv := hit - mz
	var n := 2 if Game.quality == 0 else 3
	for i in n:
		var t := (float(i) + randf()) / float(n)
		FX.burst(mz + dv * t, col.lerp(Color.WHITE, 0.25 * (1.0 - t)), 3, 2.0 + 1.5 * t, 0.4 + 0.2 * t, -0.5, 1.0 + 1.6 * t)


# --- statuses -------------------------------------------------------------------------------------------------------------------

func _dmg_mult() -> float:
	return Upgrades.damage_mult() * HeroPower.f("dmg")


static func _is_big(target: Node) -> bool:
	var hpmax: Variant = target.get(&"max_hp")
	return (hpmax is float or hpmax is int) and float(hpmax) > BIG_HP


func _fx_ok() -> bool:
	if _fx_tokens >= 1.0:
		_fx_tokens -= 1.0
		return true
	return false


func _track_ok(table: Dictionary, id: int) -> bool:
	return table.has(id) or table.size() < MAX_TRACKED


## Shove `target` `metres` away from the hero along the ground; a wall stops it short.
func _push(target: Node, metres: float) -> void:
	var n3 := target as Node3D
	if n3 == null or metres <= 0.0:
		return
	var p := w._player
	var dir := n3.global_position - p.global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.05 else -p.camera_rig.camera.global_basis.z
	var c := n3.global_position + Vector3(0.0, 1.0, 0.0)
	var free := metres
	_ray.from = c
	_ray.to = c + dir * (metres + 0.6)
	_ray.exclude = w._exclude_base
	var res := w._player.get_world_3d().direct_space_state.intersect_ray(_ray)
	if not res.is_empty():
		free = maxf(0.0, c.distance_to(res["position"]) - 0.7)
	n3.global_position += dir * free
	_resync(target)
	if target.has_method(&"stagger"):
		target.call(&"stagger", 1.2)
	knocks += 1
	if _fx_ok():
		FX.burst(n3.global_position + Vector3(0.0, 1.0, 0.0), w.def["tracer"], 5, 3.0, 0.25, 0.0, 0.9)


func _pull(target: Node, metres: float) -> void:
	var n3 := target as Node3D
	if n3 == null or metres <= 0.0:
		return
	var p := w._player
	var off := p.global_position - n3.global_position
	off.y = 0.0
	var dist := off.length()
	if dist < 2.4:
		return
	n3.global_position += off / dist * minf(metres, dist - 2.0)
	_resync(target)
	if target.has_method(&"stagger"):
		target.call(&"stagger", 1.0)
	pulls += 1
	if _fx_ok():
		FX.tracer(p.body.muzzle.global_position, n3.global_position + Vector3(0.0, 1.0, 0.0), w.def["tracer"])


## A displacement of ours must not count as the enemy's own movement of the slow.
func _resync(target: Node) -> void:
	var e: Variant = _slow.get(target.get_instance_id(), null)
	if e != null and target is Node3D:
		(e as Dictionary)["last"] = (target as Node3D).global_position


func _add_slow(target: Node, secs: float, k: float) -> void:
	var id := target.get_instance_id()
	if not _track_ok(_slow, id) or not (target is Node3D):
		return
	var e: Dictionary = _slow.get(id, {"node": target, "k": 1.0, "left": 0.0, "last": (target as Node3D).global_position})
	e["k"] = minf(float(e["k"]), k) if float(e["left"]) > 0.0 else k
	e["left"] = maxf(float(e["left"]), secs * (0.4 if _is_big(target) else 1.0))
	if not _slow.has(id):
		slows += 1
	_slow[id] = e


func _add_mark(target: Node, bonus: float, secs: float) -> void:
	var id := target.get_instance_id()
	if not _track_ok(_marks, id):
		return
	var fresh := not _marks.has(id)
	_marks[id] = {"node": target, "left": secs, "bonus": maxf(bonus, float((_marks.get(id, {}) as Dictionary).get("bonus", 0.0))), "fx": 0.0}
	if fresh:
		marks_made += 1
		if _fx_ok() and target is Node3D:
			FX.burst((target as Node3D).global_position + Vector3(0.0, 2.2, 0.0), Color(1.0, 0.35, 0.85), 6, 2.0, 0.4, 0.0, 1.0)


func _add_zap(target: Node, dps: float, secs: float, chain: int) -> void:
	var id := target.get_instance_id()
	if not _track_ok(_zap, id) or not (target is Node3D):
		return
	var fresh := not _zap.has(id)
	_zap[id] = {"node": target, "left": secs, "acc": float((_zap.get(id, {}) as Dictionary).get("acc", 0.0)), "dps": dps * _dmg_mult(), "fx": 0.0}
	if fresh:
		zaps += 1
		if target.has_method(&"stagger"):
			target.call(&"stagger", 0.8)
		if _fx_ok():
			FX.burst((target as Node3D).global_position + Vector3(0.0, 1.2, 0.0), Color(0.5, 0.95, 1.0), 6, 3.0, 0.3, 0.0, 0.9)
	if chain > 0 and fresh:
		var used: Array[Node] = [target]
		var prev: Vector3 = (target as Node3D).global_position + Vector3(0.0, 1.0, 0.0)
		for _j in chain:
			var best: Node = null
			var best_d := 9.0
			for e: Node in w.get_tree().get_nodes_in_group(&"enemy"):
				if used.has(e) or not (e is Node3D) or not e.has_method(&"center") or PlayerWeapon._is_dead(e):
					continue
				var dist: float = (e.call(&"center") as Vector3).distance_to(prev)
				if dist < best_d:
					best_d = dist
					best = e
			if best == null:
				break
			used.append(best)
			var c: Vector3 = best.call(&"center")
			FX.tracer(prev, c, Color(0.5, 0.95, 1.0))
			FX.qvfx.bolt(prev, c, Color(0.5, 0.95, 1.0))
			_add_zap(best, dps * 0.7, secs, 0)
			prev = c


func _add_chill(target: Node, stacks: int, need: int, freeze_secs: float) -> void:
	var id := target.get_instance_id()
	if not _track_ok(_chill, id) or not (target is Node3D):
		return
	var e: Dictionary = _chill.get(id, {"node": target, "stacks": 0, "left": 0.0})
	e["stacks"] = int(e["stacks"]) + stacks
	e["left"] = CHILL_DECAY
	chills += 1
	var col := Color(0.65, 0.9, 1.0)
	if int(e["stacks"]) >= need:
		e["stacks"] = 0
		freezes += 1
		if target.has_method(&"disable"):
			target.call(&"disable", freeze_secs * (0.33 if _is_big(target) else 1.0))
		FX.burst((target as Node3D).global_position + Vector3(0.0, 1.2, 0.0), col, 12, 3.5, 0.5, 0.0, 1.2)
		Sfx.play(&"impact_glass", -8.0, 1.3)
		_chill.erase(id)
		_add_slow(target, freeze_secs + 1.0, 0.45)
		return
	_chill[id] = e
	_add_slow(target, CHILL_DECAY, maxf(0.3, 1.0 - CHILL_SLOW * float(e["stacks"])))


func _add_dissolve(target: Node, pct: float, secs: float) -> void:
	var id := target.get_instance_id()
	if not _track_ok(_dis, id) or not (target is Node3D):
		return
	if not _dis.has(id):
		dissolves += 1
	_dis[id] = {"node": target, "left": secs, "acc": float((_dis.get(id, {}) as Dictionary).get("acc", 0.0)), "pct": pct}


# --- the frame --------------------------------------------------------------------------------------------------------------------

func tick(dt: float) -> void:
	_idle += dt
	_fx_tokens = minf(4.0, _fx_tokens + FX_PER_SECOND * dt)
	if _ramp_t > 0.0:
		_ramp_t -= dt
		if _ramp_t <= 0.0:
			_ramp_n = 0
	if _hot_t > 0.0:
		_hot_t -= dt
		if _hot_t <= 0.0:
			_hot = 0.0
	if _surge_t > 0.0:
		_surge_t -= dt
	if not _marks.is_empty():
		_tick_marks(dt)
	if not _slow.is_empty():
		_tick_slow(dt)
	if not _chill.is_empty():
		_tick_chill(dt)
	if not _zap.is_empty():
		_tick_dots(_zap, dt, ZAP_TICK, false)
	if not _dis.is_empty():
		_tick_dots(_dis, dt, DISSOLVE_TICK, true)


func _gone(e: Dictionary) -> bool:
	return not is_instance_valid(e["node"]) or PlayerWeapon._is_dead(e["node"] as Object)


func _tick_marks(dt: float) -> void:
	for id: int in _marks.keys():
		var e: Dictionary = _marks[id]
		e["left"] = float(e["left"]) - dt
		if _gone(e) or float(e["left"]) <= 0.0:
			_marks.erase(id)
			continue
		e["fx"] = float(e["fx"]) - dt
		if float(e["fx"]) <= 0.0 and _fx_ok():
			e["fx"] = MARK_FX
			var n3 := e["node"] as Node3D
			FX.burst(n3.global_position + Vector3(0.0, 2.3, 0.0), Color(1.0, 0.35, 0.85), 2, 0.6, 0.35, 0.0, 0.8)


func _tick_slow(dt: float) -> void:
	for id: int in _slow.keys():
		var e: Dictionary = _slow[id]
		e["left"] = float(e["left"]) - dt
		if _gone(e) or float(e["left"]) <= 0.0:
			_slow.erase(id)
			continue
		var n3 := e["node"] as Node3D
		var last: Vector3 = e["last"]
		var cur := n3.global_position
		var delta := cur - last
		delta.y = 0.0
		if delta.length() > 6.0:                                      # a teleport or a big shove of someone else: not walking
			e["last"] = cur
			continue
		var held := last + delta * float(e["k"])
		held.y = cur.y
		n3.global_position = held
		e["last"] = held


func _tick_chill(dt: float) -> void:
	for id: int in _chill.keys():
		var e: Dictionary = _chill[id]
		e["left"] = float(e["left"]) - dt
		if _gone(e) or float(e["left"]) <= 0.0:
			_chill.erase(id)


func _tick_dots(table: Dictionary, dt: float, step: float, percent: bool) -> void:
	for id: int in table.keys():
		var e: Dictionary = table[id]
		e["left"] = float(e["left"]) - dt
		if _gone(e) or float(e["left"]) <= 0.0:
			table.erase(id)
			continue
		e["acc"] = float(e["acc"]) + dt
		if float(e["acc"]) < step:
			continue
		e["acc"] = float(e["acc"]) - step
		var tn := e["node"] as Node
		var amount := 0.0
		if percent:
			var hpmax: Variant = tn.get(&"max_hp")
			var mh := float(hpmax) if (hpmax is float or hpmax is int) else 100.0
			amount = minf(float(e["pct"]) * mh * step, 60.0 * _dmg_mult())
			amount = TestMode.damage(amount)
		else:
			amount = TestMode.damage(float(e["dps"]) * step)
		tn.call(&"damage", amount, false)
		var col := Color(0.7, 0.45, 1.0) if percent else Color(0.5, 0.95, 1.0)
		if _fx_ok() and tn is Node3D:
			if percent:
				FX.burst((tn as Node3D).global_position + Vector3(0.0, 1.0, 0.0), col, 4, 2.0, 0.5, -1.0, 1.1)
			else:
				var base := (tn as Node3D).global_position
				FX.qvfx.bolt(base + Vector3(randf_range(-0.4, 0.4), 0.4, randf_range(-0.4, 0.4)), base + Vector3(randf_range(-0.4, 0.4), 1.7, randf_range(-0.4, 0.4)), col)
		if PlayerWeapon._is_dead(tn):
			table.erase(id)
			on_kill(tn)


# --- alt-fires --------------------------------------------------------------------------------------------------------------------

## The alt-fire kinds that are not in PlayerWeapon / EnergyArms. `start` = the rounds before the alt-fire (the cost is taken from it). True when it did something.
func alt(kind: String, a: Dictionary, aiming: bool, start: int) -> bool:
	match kind:
		"ub_nade":
			w._throw(0.0, false, {"wid": StringName(a["proj"])})
			w.ammo = maxi(0, start - int(a["cost"]))
			ub_shots += 1
			return true
		"zoom":
			_zoom_alt = not _zoom_alt
			if w._player != null and w._player.camera_rig != null:
				var base_zoom := float(w.def["zoom"])
				w._player.camera_rig.ads_fov = float(w.def.get("zoom_alt", base_zoom * 0.55)) if _zoom_alt else base_zoom
			zoom_toggles += 1
			Sfx.play(&"ui_tap", -4.0, 1.4 if _zoom_alt else 1.1)
			return true
		"brace":
			_brace = not _brace
			braces += 1
			Sfx.play(&"reload", -10.0, 0.6 if _brace else 0.9)
			return true
		"mode":
			_mode_burst = not _mode_burst
			Sfx.play(&"ui_tap", -4.0, 0.9 if _mode_burst else 1.2)
			return true
		"surge":
			_surge_t = float(a.get("time", 3.0))
			_surge_k = 1.0 / float(a.get("rate", 1.6))
			surges += 1
			Sfx.play(&"overheat", -10.0, 1.6)
			return true
		"spin":
			return _spin(float(a.get("radius", 3.4)), float(a.get("mult", 1.6)), aiming)
		"shove":
			return _shove(float(a.get("radius", 3.2)), float(a.get("push", 6.0)), float(a.get("mult", 0.8)))
		"throw_melee":
			return _throw_melee(float(a.get("range", 28.0)), float(a.get("mult", 1.8)))
	return false


func is_zoom_alt() -> bool:
	return _zoom_alt


func is_braced() -> bool:
	return _brace


func is_burst_mode() -> bool:
	return _mode_burst


func surge_left() -> float:
	return maxf(_surge_t, 0.0)


## SPIN SWEEP: every enemy around the hero takes a heavy hit (the finisher of the weapon).
func _spin(radius: float, mult: float, _aiming: bool) -> bool:
	var p := w._player
	var origin := p.global_position
	var n := 0
	for e: Node in w.get_tree().get_nodes_in_group(&"enemy"):
		if not (e is Node3D) or not e.has_method(&"center") or PlayerWeapon._is_dead(e):
			continue
		var c: Vector3 = e.call(&"center")
		var off := Vector3(c.x - origin.x, 0.0, c.z - origin.z)
		if off.length() - PlayerWeapon._radius_of(e) > radius:
			continue
		w._melee_hit(e, c, mult, true)
		n += 1
	var city := Game.world as City
	if city != null and city.ambient != null and Game.civilian_casualties:
		city.ambient.blast_civilians(origin, radius * 0.6, true, float(w.def["damage"]) * mult * 0.9, &"melee")
	var col: Color = w.def["tracer"]
	for i in 6:
		var a := TAU * float(i) / 6.0
		FX.burst(origin + Vector3(cos(a), 1.1, sin(a)) * radius * 0.7, col, 3, 3.0, 0.3, 0.0, 1.0)
	FX.shake(0.1)
	spins += 1
	w.shots_fired += 1
	return true


## SHOVE: a short cone in front of the hero: a light hit and a big push (a doorway cleared).
func _shove(radius: float, push: float, mult: float) -> bool:
	var p := w._player
	var fwd := -p.camera_rig.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var origin := p.global_position
	var n := 0
	for e: Node in w.get_tree().get_nodes_in_group(&"enemy"):
		if not (e is Node3D) or not e.has_method(&"center") or PlayerWeapon._is_dead(e):
			continue
		var c: Vector3 = e.call(&"center")
		var off := Vector3(c.x - origin.x, 0.0, c.z - origin.z)
		var dist := off.length() - PlayerWeapon._radius_of(e)
		if dist > radius or (dist > 1.0 and off.normalized().dot(fwd) < 0.2):
			continue
		w._melee_hit(e, c, mult, false)
		if not PlayerWeapon._is_dead(e):
			_push(e, push * (0.33 if _is_big(e) else 1.0))
		n += 1
	FX.burst(origin + fwd * radius * 0.6 + Vector3(0.0, 1.1, 0.0), w.def["tracer"], 8, 4.0, 0.3, 0.0, 1.3)
	FX.shake(0.06)
	shoves += 1
	w.shots_fired += 1
	return true


## THROW: the weapon flies at the enemy under the crosshair (a straight line, `range` metres at most) and hits like a swing times `mult`; the hands are empty for the cooldown.
func _throw_melee(range_m: float, mult: float) -> bool:
	var p := w._player
	var ar := w._aim_ray(0.0)
	var origin: Vector3 = ar[0]
	var dir: Vector3 = ar[1]
	var best := range_m
	var target: Node = null
	var zone: StringName = HitZones.BODY
	for e: Node in w.get_tree().get_nodes_in_group(&"enemy"):
		if not (e is Node3D) or PlayerWeapon._is_dead(e):
			continue
		var zh := HitZones.of(e, origin, dir)
		if zh.is_empty():
			continue
		var t := float(zh["t"])
		if t < best:
			best = t
			target = e
			zone = zh["zone"]
	var mz := p.body.muzzle.global_position
	var end := origin + dir * best
	FX.tracer(mz, end, w.def["tracer"])
	Sfx.play(&"whizz", -4.0, 1.2)
	throws += 1
	w.shots_fired += 1
	if target != null and not _blocked(origin, end):
		w._hit_target(target, end, -dir, mult, zone)
	return true
