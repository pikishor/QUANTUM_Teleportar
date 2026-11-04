class_name QuantumVerbs
extends Node
## Three more quantum verbs of the hero (a child of the Player, `player.qverbs`), plain names, energy through the existing ability energy (`HeroPower.cost`, `HeroPower.cd`):
##   PHASE SHIELD  (action `shield`, Y)  a short barrier in front of the hero for SHIELD_LIFE seconds. Enemy bolts that cross it are absorbed or REFLECTED back at the shooter
##                  (a reflected bolt hurts the first enemy it meets). Counters: snipers' bolts pass through it, heavy bolts are absorbed and drain the barrier twice as fast,
##                  strikers burst on it. The barrier has SHIELD_HP and breaks when it is spent.
##   TIME SLIP     (action `slip`, U)    a local slow-motion bubble around the hero for SLIP_LIFE seconds: enemies and enemy bolts inside move at SLIP_SCALE. The hero is not slowed.
##                  Counters: flankers and stalkers resist (SLIP_RESIST), bosses resist most.
##   ARC           (action `arc`, I)     auto-targeting chain strike: the hero teleport-slashes up to `arc_max()` enemies in a chain (nearest first, then the nearest to the last one),
##                  then snaps back to where the strike began. Counters: shield troops take ARC_RESIST fewer damage, brutes and bosses too.
## Slip and shield queries are static (`slip_scale`, `shield_hit`) so the enemy code needs no node lookup. Counters are what the test waits on. Only ticks in the play state.

signal used(id: StringName)

const IDS: Array[StringName] = [&"shield", &"slip", &"arc"]
const TITLES := {&"shield": "PHASE SHIELD", &"slip": "TIME SLIP", &"arc": "ARC"}
const SHORT := {&"shield": "SHIELD", &"slip": "SLIP", &"arc": "ARC"}
const COST := {&"shield": 20.0, &"slip": 30.0, &"arc": 30.0}
const CD := {&"shield": 6.0, &"slip": 12.0, &"arc": 6.0}
const LIFE := {&"shield": 4.0, &"slip": 5.0, &"arc": 0.0}
const COLOR := {&"shield": Color(0.35, 0.8, 1.0), &"slip": Color(0.75, 0.5, 1.0), &"arc": Color(1.0, 0.95, 0.5)}

const SHIELD_DIST := 2.4              ## metres in front of the hero
const SHIELD_W := 3.6
const SHIELD_H := 2.4
const SHIELD_HP := 120.0
const REFLECT_MULT := 2.5             ## reflected bolt damage multiplier
const REFLECT_MIN := 14.0
const SLIP_RADIUS := 10.0
const SLIP_SCALE := 0.3               ## game speed of enemies inside the bubble
const SLIP_RESIST := {&"flanker": 0.6, &"stalker": 0.6, &"pouncer": 0.5}   ## resisting roles run at this scale instead
const BOSS_SLIP := 0.75
const ARC_RANGE := 30.0
const ARC_HOP := 18.0
const ARC_STEP := 0.14                ## seconds per hop
const ARC_DMG := 55.0
const ARC_RESIST := 0.35              ## damage factor against shield troops, brutes and bosses
const ARC_BEAMS := 7

# static state read by the enemy code (one hero at a time)
static var shield_on := false
static var shield_xf := Transform3D.IDENTITY
static var slip_on := false
static var slip_center := Vector3.ZERO

var shield_left := 0.0
var shield_hp := 0.0
var slip_left := 0.0
var arc_left := 0.0                   ## > 0 while the strike chain is running
var uses := {}                        ## id -> times used
var absorbed := 0                     ## bolts the barrier took
var reflected := 0
var reflect_hits := 0                 ## enemies hurt by a reflected bolt
var slowed_ticks := 0                 ## enemy ticks scaled by the bubble
var arc_hops := 0                     ## hops landed, all strikes
var last_arc: Array[StringName] = []  ## enemy types hit by the latest strike
var last_denied: StringName = &""

var _p: Player
var _cd := {}
var _was := {}
var _shield_mi: MeshInstance3D
var _slip_mi: MeshInstance3D
var _slip_ring: MeshInstance3D
var _beams: Array[MeshInstance3D] = []
var _beam_t := PackedFloat32Array()
var _arc_targets: Array = []
var _arc_i := 0
var _arc_t := 0.0
var _arc_origin := Vector3.ZERO
var _arc_prev := Vector3.ZERO
var _clock := 0.0


func _ready() -> void:
	_p = get_parent() as Player
	Game.new_game.connect(reset)
	Game.respawn.connect(reset)


func _exit_tree() -> void:
	_clear_static()


static func _clear_static() -> void:
	shield_on = false
	slip_on = false


func reset() -> void:
	_cd.clear()
	shield_left = 0.0
	shield_hp = 0.0
	slip_left = 0.0
	arc_left = 0.0
	_arc_targets.clear()
	_clear_static()
	_hide_all()


func _hide_all() -> void:
	for n: Node in [_shield_mi, _slip_mi, _slip_ring]:
		if n != null:
			(n as Node3D).visible = false
	for b in _beams:
		b.visible = false


# --- queries ---------------------------------------------------------------------------------------------------------------

func clear_cooldown(id: StringName) -> void:
	_cd.erase(id)


func cooldown(id: StringName) -> float:
	return float(_cd.get(id, 0.0))


func active(id: StringName) -> bool:
	match id:
		&"shield":
			return shield_left > 0.0
		&"slip":
			return slip_left > 0.0
		&"arc":
			return arc_left > 0.0
	return false


## HUD / touch state: ready (affordable and cooled down), active, cd (0..1 of the cooldown left), left (seconds of the effect).
func ui_state(id: StringName) -> Dictionary:
	var cd := cooldown(id)
	var full := maxf(HeroPower.cd(float(CD[id])), 0.01)
	var cost := HeroPower.cost(float(COST[id]))
	var left := shield_left if id == &"shield" else (slip_left if id == &"slip" else arc_left)
	return {"ready": cd <= 0.0 and _p != null and _p.energy >= cost, "active": active(id), "cd": clampf(cd / full, 0.0, 1.0), "left": left}


func arc_max() -> int:
	return clampi(2 + HeroPower.hops(), 3, 6)


## Enemy speed factor at `pos` for an enemy of this type / role (1.0 outside the bubble). `boss` enemies resist most.
static func slip_scale(pos: Vector3, role: StringName, boss := false) -> float:
	if not slip_on:
		return 1.0
	var d := Vector2(pos.x - slip_center.x, pos.z - slip_center.z).length()
	if d > SLIP_RADIUS:
		return 1.0
	if boss:
		return BOSS_SLIP
	return float(SLIP_RESIST.get(role, SLIP_SCALE))


## Bolt scale for bolts (they have no role).
static func slip_bolt(pos: Vector3) -> float:
	return slip_scale(pos, &"")


## Bolt `prev -> cur` crosses the barrier? Returns true when it does (inside the SHIELD_W x SHIELD_H panel).
static func shield_hit(prev: Vector3, cur: Vector3) -> bool:
	if not shield_on:
		return false
	var inv := shield_xf.affine_inverse()
	var a := inv * prev
	var b := inv * cur
	if (a.z > 0.0) == (b.z > 0.0):
		return false
	var t := a.z / (a.z - b.z)
	var q := a.lerp(b, t)
	return absf(q.x) <= SHIELD_W * 0.5 and q.y >= -0.1 and q.y <= SHIELD_H


## Enemy bolt types that the barrier cannot stop (they see through it) / that drain it faster.
static func pierces(type: StringName) -> bool:
	return type == &"sniper"


static func overloads(type: StringName) -> bool:
	return type == &"heavy"


static func arc_factor(d: Drone) -> float:
	if d == null:
		return 1.0
	var role: StringName = d.cfg.get("role", &"")
	if d is Overseer or d is VerbBoss or role == &"brute":
		return ARC_RESIST
	if d is Specialist and role == &"shield" and float((d as Specialist).shield_hp) > 0.0:
		return ARC_RESIST
	return 1.0


## Called by EnemyManager when a bolt of `type` and damage `dmg` crosses the barrier. Returns 0 pass-through, 1 absorbed, 2 reflected.
func shield_block(type: StringName, dmg: float) -> int:
	if shield_left <= 0.0:
		return 0
	if pierces(type):
		return 0
	shield_hp -= dmg * (2.0 if overloads(type) else 1.0)
	absorbed += 1
	if shield_hp <= 0.0:
		shield_left = 0.0
		FX.burst(shield_xf.origin + Vector3(0, 1.2, 0), COLOR[&"shield"], 14, 7.0, 0.5, 2.0)
		return 1
	if overloads(type):
		return 1
	reflected += 1
	return 2


# --- use -------------------------------------------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if not Game.is_playing() or _p == null:
		return
	_clock += dt
	for id: StringName in _cd.keys():
		_cd[id] = maxf(0.0, float(_cd[id]) - dt)
	var foot := not is_instance_valid(_p.vehicle)
	for id: StringName in IDS:
		var want := foot and Input.is_action_pressed(id)
		if want and not bool(_was.get(id, false)):
			use(id)
		_was[id] = want
	_tick_shield(dt)
	_tick_slip(dt)
	_tick_arc(dt)
	_tick_beams(dt)


## Uses one verb. False when in a vehicle, cooling down, short of energy, or (arc) with no target.
func use(id: StringName) -> bool:
	if _p == null or not Game.is_playing() or not COST.has(id) or is_instance_valid(_p.vehicle) or _p.is_dead():
		return false
	if cooldown(id) > 0.0 or active(&"arc"):
		return false
	var cost := HeroPower.cost(float(COST[id]))
	if _p.energy < cost:
		last_denied = id
		return false
	var ok := false
	match id:
		&"shield":
			ok = _raise_shield()
		&"slip":
			ok = _open_slip()
		&"arc":
			ok = _start_arc()
	if not ok:
		last_denied = id
		return false
	_p.energy = maxf(0.0, _p.energy - cost)
	_cd[id] = HeroPower.cd(float(CD[id]))
	uses[id] = int(uses.get(id, 0)) + 1
	used.emit(id)
	FX.qvfx.verb_used(id)
	PostFx2.pulse(0.7)
	Game.say(String(TITLES[id]), 0.8)
	return true


func _aim_yaw() -> float:
	return _p.yaw


# --- phase shield ----------------------------------------------------------------------------------------------------------

func _raise_shield() -> bool:
	var yaw := _aim_yaw()
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var pos := _p.global_position + fwd * SHIELD_DIST
	shield_xf = Transform3D(Basis(Vector3.UP, yaw), pos)
	shield_left = float(LIFE[&"shield"])
	shield_hp = SHIELD_HP
	shield_on = true
	if _shield_mi == null:
		_shield_mi = MeshInstance3D.new()
		_shield_mi.top_level = true
		_shield_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var q := QuadMesh.new()
		q.size = Vector2(SHIELD_W, SHIELD_H)
		_shield_mi.mesh = q
		_shield_mi.material_override = Gear.fx_material(Color(COLOR[&"shield"], 0.22))
		add_child(_shield_mi)
	_shield_mi.global_transform = Transform3D(shield_xf.basis, pos + Vector3(0, SHIELD_H * 0.5, 0))
	_shield_mi.visible = true
	FX.burst(pos + Vector3(0, 1.2, 0), COLOR[&"shield"], 10, 4.0, 0.4, 1.0)
	return true


func _tick_shield(dt: float) -> void:
	if shield_left <= 0.0:
		if shield_on:
			shield_on = false
			if _shield_mi != null:
				_shield_mi.visible = false
		return
	shield_left -= dt
	if shield_left <= 0.0:
		shield_on = false
		_shield_mi.visible = false
		return
	var pulse := 0.16 + 0.08 * sin(_clock * 9.0) + 0.1 * clampf(shield_hp / SHIELD_HP, 0.0, 1.0)
	(_shield_mi.material_override as StandardMaterial3D).albedo_color = Color(COLOR[&"shield"], pulse)
	# strikers burst on the barrier
	var mgr := Game.enemies as EnemyManager
	if mgr == null:
		return
	var inv := shield_xf.affine_inverse()
	for d: Drone in mgr.list:
		if d.dead or not d.active or not bool(d.cfg.get("kamikaze", false)):
			continue
		var l := inv * d.center()
		if absf(l.z) < 1.4 and absf(l.x) < SHIELD_W * 0.5 + 0.8 and l.y < SHIELD_H + 0.8:
			FX.burst(d.center(), Color(1.0, 0.63, 0.23), 12, 6.0, 0.4, 2.0)
			d.damage(d.hp + 1.0, false, true)


# --- time slip ---------------------------------------------------------------------------------------------------------------

func _open_slip() -> bool:
	slip_left = float(LIFE[&"slip"])
	slip_on = true
	slip_center = _p.global_position
	if _slip_mi == null:
		_slip_mi = MeshInstance3D.new()
		_slip_mi.top_level = true
		_slip_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 24
		s.rings = 12
		_slip_mi.mesh = s
		_slip_mi.material_override = Gear.fx_material(Color(COLOR[&"slip"], 0.07))
		add_child(_slip_mi)
		_slip_ring = MeshInstance3D.new()
		_slip_ring.top_level = true
		_slip_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var t := TorusMesh.new()
		t.inner_radius = 0.97
		t.outer_radius = 1.0
		t.rings = 40
		t.ring_segments = 6
		_slip_ring.mesh = t
		_slip_ring.material_override = Gear.fx_material(Color(COLOR[&"slip"], 0.8))
		add_child(_slip_ring)
	_slip_mi.visible = true
	_slip_ring.visible = true
	return true


func _tick_slip(dt: float) -> void:
	if slip_left <= 0.0:
		if slip_on:
			slip_on = false
			if _slip_mi != null:
				_slip_mi.visible = false
				_slip_ring.visible = false
		return
	slip_left -= dt
	if slip_left <= 0.0:
		slip_on = false
		_slip_mi.visible = false
		_slip_ring.visible = false
		return
	slip_center = _p.global_position
	var fade := clampf(slip_left, 0.0, 1.0)                         # last second fades out
	var sc := SLIP_RADIUS * (0.6 + 0.4 * minf(1.0, (float(LIFE[&"slip"]) - slip_left) * 4.0))
	_slip_mi.global_transform = Transform3D(Basis.from_scale(Vector3(sc, sc, sc)), slip_center + Vector3(0, 0.9, 0))
	_slip_ring.global_transform = Transform3D(Basis.from_scale(Vector3(sc, sc, sc)), slip_center + Vector3(0, 0.08, 0))
	(_slip_ring.material_override as StandardMaterial3D).albedo_color = Color(COLOR[&"slip"], 0.55 * fade + 0.1 * sin(_clock * 6.0))


# --- arc ---------------------------------------------------------------------------------------------------------------------

func _gather() -> Array:
	var mgr := Game.enemies as EnemyManager
	var out: Array = []
	if mgr == null:
		return out
	var pool: Array[Drone] = []
	for d: Drone in mgr.list:
		if d.active and not d.dead:
			pool.append(d)
	var from := _p.global_position
	var range_now := ARC_RANGE
	var cap := arc_max()
	while out.size() < cap:
		var best: Drone = null
		var bd := range_now
		for d: Drone in pool:
			if out.has(d):
				continue
			var dist := from.distance_to(d.global_position)
			if dist < bd:
				bd = dist
				best = d
		if best == null:
			break
		out.append(best)
		from = best.global_position
		range_now = ARC_HOP
	return out


func _start_arc() -> bool:
	var t := _gather()
	if t.is_empty():
		return false
	_arc_targets = t
	_arc_i = 0
	_arc_t = 0.0
	_arc_origin = _p.global_position
	_arc_prev = _arc_origin + Vector3(0, 1.0, 0)
	arc_left = ARC_STEP * float(t.size() + 1)
	last_arc.clear()
	_p.invuln = maxf(_p.invuln, arc_left + 0.3)
	return true


func _tick_arc(dt: float) -> void:
	if arc_left <= 0.0:
		return
	if _p.is_dead():
		arc_left = 0.0
		_arc_targets.clear()
		return
	_arc_t -= dt
	if _arc_t > 0.0:
		return
	_arc_t = ARC_STEP
	if _arc_i >= _arc_targets.size():           # chain over: snap back to the start
		arc_left = 0.0
		_p.teleport_to(_arc_origin)
		_beam(_arc_prev, _arc_origin + Vector3(0, 1.0, 0))
		_arc_targets.clear()
		return
	var d: Drone = _arc_targets[_arc_i]
	_arc_i += 1
	if not is_instance_valid(d) or d.dead or not d.active:
		return
	var tp := d.global_position
	var dir := (_arc_prev - tp)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.BACK
	var spot := tp + dir * 1.6
	_p.teleport_to(spot)
	var hit := d.center()
	_beam(_arc_prev, hit)
	_arc_prev = hit
	var dmg := ARC_DMG * HeroPower.f("dmg") * arc_factor(d)
	last_arc.append(d.type)
	arc_hops += 1
	d.stagger(1.0)
	d.damage(dmg, true)
	FX.burst(hit, COLOR[&"arc"], 12, 7.0, 0.35, 1.0)
	Sfx.play(&"blink")


func _beam(a: Vector3, b: Vector3) -> void:
	var i := -1
	for k in _beams.size():
		if _beam_t[k] <= 0.0:
			i = k
			break
	if i < 0:
		if _beams.size() >= ARC_BEAMS:
			return
		var mi := MeshInstance3D.new()
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var c := CylinderMesh.new()
		c.top_radius = 0.035
		c.bottom_radius = 0.035
		c.height = 1.0
		c.radial_segments = 5
		c.rings = 1
		mi.mesh = c
		mi.material_override = Gear.fx_material(Color(COLOR[&"arc"], 0.9))
		add_child(mi)
		_beams.append(mi)
		_beam_t.append(0.0)
		i = _beams.size() - 1
	var len := a.distance_to(b)
	if len < 0.05:
		return
	var up := (b - a) / len
	var ax := up.cross(Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT).normalized()
	var az := ax.cross(up).normalized()
	var mid := (a + b) * 0.5
	_beams[i].global_transform = Transform3D(Basis(ax, up * len, az), mid)
	_beams[i].visible = true
	_beam_t[i] = 0.35


func _tick_beams(dt: float) -> void:
	for i in _beams.size():
		if _beam_t[i] > 0.0:
			_beam_t[i] -= dt
			if _beam_t[i] <= 0.0:
				_beams[i].visible = false
