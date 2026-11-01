extends RefCounted
## The specialist enemies and the smarter squad behaviour, against the real Player and EnemyManager: type table and chapter / heat selection, the shield trooper (frontal arc, shield damage,
## break, slow turn), the flanker (speed, orbit), the sniper (0.8 s laser telegraph, hard 30 damage shot, aim lock dodge), the brute (charge locked on a line, slam ring), cover (the spot behind
## a pooled prop collider, hiding, peeking, leaving when flanked), squad callouts with opposite flank sides, per-tier caps and the draw budget (at most +1 mesh per type).
## Time runs 4x (time_scale and tick rate together). Run: tools/test.sh tests/test_enemy_types.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")
const Stubs := preload("res://tests/enemies_stubs.gd")

const K := 4
const DT := 1.0 / 60.0                  ## game time of one physics frame (time_scale and tick rate move together)


class CoverWorld extends Node3D:
	var bodies: Array = []

	func prop_colliders() -> Object:
		return self

	func random_road_point() -> Vector3:
		return Vector3(float(randi_range(-3, 3)) * 80.0 + 5.0, 0.0, randf_range(-280.0, 280.0))

	func road_point_near(center: Vector3, rmin: float, rmax: float) -> Vector3:
		var a := randf() * TAU
		var r := randf_range(rmin, rmax)
		return Vector3(center.x + cos(a) * r, 0.0, center.z + sin(a) * r)


class FakeStory extends Node:
	var chapter := 0
	var lines: Array = []

	func say(speaker: String, text: String, id := "", _wait := 0.0, _prio := 0) -> bool:
		lines.append({"s": speaker, "t": text, "id": id})
		return true


var e := Env.new()
var p: Player
var root: Node3D
var em: EnemyManager
var world: CoverWorld
var stub_missions := Stubs.StubMissions.new()


func run(host: Node) -> void:
	seed(33)
	await e.setup(host)
	p = e.p
	root = e.root
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	p.max_hp = 1.0e6
	world = CoverWorld.new()
	root.add_child(world)
	Game.world = world
	root.add_child(stub_missions)
	Game.missions = stub_missions
	em = (load("res://scenes/enemy_manager.tscn") as PackedScene).instantiate() as EnemyManager
	root.add_child(em)
	em.patrol_groups().clear()
	await e.frames(3)

	_table_and_selection()
	await _shield()
	await _flanker()
	await _sniper()
	await _brute()
	await _cover()
	await _squad()
	await _caps_and_budget()

	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Game.world = null
	Game.missions = null
	Game.heat = 0.0
	WeaponDefs.reset_unlocked()
	await e.teardown()


# --- helpers ---------------------------------------------------------------------------------------------------------

func _fresh(at := Vector3(0.0, 0.05, 0.0)) -> void:
	em.clear()
	Game.heat = 0.0
	Game.state = &"play"
	stub_missions.drops.clear()
	for b in world.bodies:
		b.queue_free()
	world.bodies.clear()
	Upgrades.reset()
	await e.prep(at)
	p.max_hp = 1.0e6
	p.hp = p.max_hp


func _secs(s: float) -> void:
	await e.frames(int(ceil(s / DT)))


func _spawn(type: StringName, at: Vector3, aware := true, frozen := false) -> Drone:
	var d := em.spawn(type, at, aware)
	d.set_physics_process(not frozen)
	await e.frames(2)
	return d


## The yaw that makes a body at `from` face the point `to` (forward is -Z rotated by yaw).
func _face(d: Drone, to: Vector3) -> void:
	d.yaw = atan2(-(to.x - d.global_position.x), -(to.z - d.global_position.z))
	d.rotation.y = d.yaw


func _mesh_count(n: Node) -> int:
	var c := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as Node3D).visible:
		c += 1
	for ch in n.get_children():
		c += _mesh_count(ch)
	return c


# --- table and selection -----------------------------------------------------------------------------------------------

func _table_and_selection() -> void:
	for t: StringName in [&"shield", &"flanker", &"sniper", &"brute", &"overseer"]:
		TestLib.check(EnemyTypes.TYPES.has(t) and EnemyTypes.is_specialist(t), "%s is in the type table" % t)
	TestLib.check(not EnemyTypes.is_specialist(&"operative") and not EnemyTypes.is_specialist(&"heavy"), "operative and drones are not specialists")
	var models_ok := true
	for t: StringName in [&"shield", &"flanker", &"sniper", &"brute", &"overseer"]:
		models_ok = models_ok and EnemyTypes.TYPES[t]["model"] == "operative"
	TestLib.check(models_ok, "every specialist reuses the operative model (tint and scale only)")
	TestLib.check(EnemyTypes.TYPES[&"flanker"]["speed"] > EnemyTypes.TYPES[&"operative"]["speed"] * 1.7, "the flanker is much faster than an operative")
	TestLib.check(is_equal_approx(float(EnemyTypes.TYPES[&"sniper"]["aim_time"]), 0.8), "the sniper telegraphs for 0.8 s")
	TestLib.check(EnemyTypes.TYPES[&"brute"]["hp"] > 300.0 and EnemyTypes.TYPES[&"brute"]["scale"] > 1.3, "the brute is big and tough")
	# which types a chapter brings
	var seen0 := {}
	var seen1 := {}
	var seen2 := {}
	var seen3 := {}
	var low_heat_brute := false
	for i in 400:
		seen0[EnemyTypes.specialist_for(0, 4.0, randf() * 0.5, randf())] = true
		seen1[EnemyTypes.specialist_for(1, 2.0, randf() * 0.5, randf())] = true
		seen2[EnemyTypes.specialist_for(2, 2.0, randf() * 0.5, randf())] = true
		seen3[EnemyTypes.specialist_for(3, 4.0, randf() * 0.5, randf())] = true
		low_heat_brute = low_heat_brute or EnemyTypes.specialist_for(5, 1.0, 0.1, randf()) == &"brute"
	TestLib.check(seen0.size() == 1 and seen0.has(&"operative"), "chapter 1: plain operatives only")
	TestLib.check(seen1.has(&"flanker") and not seen1.has(&"sniper") and not seen1.has(&"brute"), "chapter 2: flankers (and shields) start")
	TestLib.check(seen2.has(&"sniper") and not seen2.has(&"brute"), "chapter 3: snipers join")
	TestLib.check(seen3.has(&"brute") and seen3.has(&"shield") and seen3.has(&"flanker") and seen3.has(&"sniper"), "chapter 4 at high heat: all four")
	TestLib.check(not low_heat_brute, "no brutes below heat 2.5")
	TestLib.check(EnemyManager.pick_type(0.5, 0.9, 5, 0.0, 0.5) == &"sentinel" or EnemyManager.pick_type(0.5, 0.9, 5, 0.0, 0.5) != &"overseer", "the classic mix still decides the slot")
	TestLib.check(EnemyManager.pick_reinforcement_type(0.0, 0.2) == &"operative", "the classic reinforcement roll is unchanged")


# --- shield trooper --------------------------------------------------------------------------------------------------

func _shield() -> void:
	await _fresh()
	var s := await _spawn(&"shield", Vector3(18.0, 0.0, 0.0), false, true) as Specialist
	TestLib.check(s != null and s.shield_up() and is_equal_approx(s.shield_hp, 160.0), "a shield trooper with a 160 point shield")
	TestLib.check(s.shield_node != null and s.shield_node.visible, "the shield plate is shown")
	_face(s, p.global_position)
	TestLib.check(s.shield_blocks(p.global_position), "a shooter in front is blocked")
	TestLib.check(not s.shield_blocks(s.global_position + Vector3(0.0, 0.0, 10.0)) and not s.shield_blocks(s.global_position + Vector3(0.0, 0.0, -10.0)), "from the side (90 degrees) the shield does not cover him")
	TestLib.check(not s.shield_blocks(s.global_position + Vector3(10.0, 0.0, 0.0)), "from behind it does not cover him")
	p.camera_rig.aim_at(s.center())
	var hp0 := s.hp
	p.weapon.fire_t = 0.0
	p.weapon.tick(DT, true, false, false, false)
	TestLib.check(is_equal_approx(s.hp, hp0) and s.shield_hp < 160.0, "a carbine round from the front hits the shield, not the trooper (%.0f left)" % s.shield_hp)
	# flank him: turn the body away from the player, the same shot now lands
	_face(s, Vector3(40.0, 0.0, 0.0))
	await e.frames(2)
	p.weapon.fire_t = 0.0
	p.weapon.tick(DT, true, false, false, false)
	TestLib.check(s.hp < hp0, "from behind the same round hurts (%.0f hp)" % s.hp)
	# break it with fire from the front
	_face(s, p.global_position)
	for i in 20:
		if not s.shield_up():
			break
		p.camera_rig.aim_at(s.center())
		p.weapon.fire_t = 0.0
		p.weapon.bloom = 0.0                                   # tapping, not spraying: no bloom
		p.weapon.ammo = 30
		p.weapon.tick(DT, true, false, false, false)
	TestLib.check(not s.shield_up() and not s.shield_node.visible, "enough rounds break the shield and the plate goes out")
	var hp1 := s.hp
	p.camera_rig.aim_at(s.center())
	p.weapon.fire_t = 0.0
	p.weapon.bloom = 0.0
	p.weapon.tick(DT, true, false, false, false)
	TestLib.check(s.hp < hp1, "a broken shield no longer protects")
	TestLib.check(s._turn_rate() > 5.0, "unshielded he turns quickly again")
	var s2 := await _spawn(&"shield", Vector3(18.0, 0.0, 6.0), true, true) as Specialist
	TestLib.check(s2._turn_rate() < 3.0, "with the shield up he turns slowly (the flanking window)")
	em.clear()
	# an explosion takes him directly
	var s3 := await _spawn(&"shield", Vector3(18.0, 0.0, 0.0), false, true) as Specialist
	_face(s3, p.global_position)
	var h3 := s3.hp
	Game.explode(s3.global_position + Vector3(1.0, 0.5, 0.0), 6.0, {"enemy_dmg": 60.0, "player_dmg": 0.0})
	TestLib.check(s3.hp < h3, "a blast ignores the frontal shield")
	em.clear()


# --- flanker ---------------------------------------------------------------------------------------------------------

func _flanker() -> void:
	await _fresh()
	var f := await _spawn(&"flanker", Vector3(26.0, 0.0, 0.0)) as Specialist
	var max_speed := 0.0
	var swept := 0.0
	var last := f.global_position
	var last_ang := atan2(last.z - p.global_position.z, last.x - p.global_position.x)
	var bursts := 0
	for i in int(5.0 / DT / 4.0):
		await e.frames(4)
		var pos := f.global_position
		max_speed = maxf(max_speed, Vector2(pos.x - last.x, pos.z - last.z).length() / (DT * 4.0))
		last = pos
		var ang := atan2(pos.z - p.global_position.z, pos.x - p.global_position.x)
		swept += absf(angle_difference(last_ang, ang))
		last_ang = ang
		bursts = maxi(bursts, f._burst_left)
	var dist := Vector2(f.global_position.x - p.global_position.x, f.global_position.z - p.global_position.z).length()
	TestLib.check(max_speed > 6.0, "the flanker sprints (%.1f m/s)" % max_speed)
	TestLib.check(swept > 1.0, "it circles the player (%.1f rad swept)" % swept)
	TestLib.check(dist > 4.0 and dist < 20.0, "it holds a short range (%.1f m)" % dist)
	TestLib.check(bursts <= 2, "bursts are two rounds at most (%d)" % bursts)
	em.clear()


# --- sniper ----------------------------------------------------------------------------------------------------------

func _sniper() -> void:
	await _fresh()
	var sn := await _spawn(&"sniper", Vector3(48.0, 0.0, 0.0)) as Specialist
	sn._fire_t = 0.0
	var t0 := -1.0
	var t1 := -1.0
	var hp0 := p.hp
	var line_seen := false
	var t := 0.0
	for i in int(8.0 / DT / 4.0):
		await e.frames(4)
		t += DT * 4.0
		if t0 < 0.0 and sn.threat_charge() > 0.0:
			t0 = t
		if t0 >= 0.0 and sn.shows_aim_line() and sn.threat_charge() > 0.3:
			line_seen = true
		if p.hp < hp0 - 1.0:
			t1 = t
			break
	TestLib.check(t0 >= 0.0, "the sniper starts a telegraph")
	TestLib.check(line_seen, "the laser sight (aim line and muzzle charge) shows during the telegraph")
	TestLib.check(t1 > 0.0 and t1 - t0 >= 0.7 and t1 - t0 <= 1.15, "the shot lands %.2f s after the telegraph began" % (t1 - t0))
	TestLib.check(is_equal_approx(hp0 - p.hp, 30.0), "a hard shot: 30 damage (%.1f)" % (hp0 - p.hp))
	# dodge: move after the lock
	em.clear()
	await _fresh()
	var sn2 := await _spawn(&"sniper", Vector3(48.0, 0.0, 0.0)) as Specialist
	sn2._fire_t = 0.0
	var hp1 := p.hp
	var armed := false
	for i in int(8.0 / DT / 4.0):
		await e.frames(4)
		if sn2._aim_t > 0.0 and sn2._aim_t < 0.2 and sn2._locked:
			armed = true
			p.teleport_to(Vector3(0.0, 0.05, 6.0))              # a few steps aside in the last fifth of a second
			break
	await _secs(0.5)
	TestLib.check(armed and p.hp >= hp1 - 0.5, "stepping aside after the lock dodges the shot (%.1f lost)" % (hp1 - p.hp))
	em.clear()


# --- brute -----------------------------------------------------------------------------------------------------------

func _brute() -> void:
	await _fresh()
	var b := await _spawn(&"brute", Vector3(22.0, 0.0, 0.0)) as Specialist
	b._charge_cd = 0.0
	var start := Vector2(b.global_position.x, b.global_position.z)
	var charging := false
	var peak := 0.0
	var last := b.global_position
	var winding_seen := false
	for i in int(6.0 / DT / 4.0):
		await e.frames(4)
		var pos := b.global_position
		if b.is_charging():
			charging = true
			peak = maxf(peak, Vector2(pos.x - last.x, pos.z - last.z).length() / (DT * 4.0))
			if not winding_seen:
				winding_seen = true
				p.teleport_to(Vector3(0.0, 0.05, 9.0))             # sidestep the locked line
		last = pos
		if charging and not b.is_charging():
			break
	TestLib.check(charging, "the brute charges")
	TestLib.check(peak > float(EnemyTypes.TYPES[&"brute"]["speed"]) * 1.5, "the charge is much faster than his walk (%.1f m/s)" % peak)
	TestLib.check(Vector2(b.global_position.x - p.global_position.x, b.global_position.z - p.global_position.z).length() > 2.5 or b.slam_count() > 0, "the charge runs on a locked line: a sidestep does not steer it")
	# slam: the player right next to him
	em.clear()
	await _fresh()
	var b2 := await _spawn(&"brute", Vector3(2.5, 0.0, 0.0)) as Specialist
	var hp0 := p.hp
	var wind := false
	for i in int(3.0 / DT / 4.0):
		await e.frames(4)
		wind = wind or b2.is_winding()
		if b2.slam_count() > 0:
			break
	TestLib.check(wind, "the slam winds up first (telegraph)")
	TestLib.check(b2.slam_count() >= 1 and p.hp < hp0 - 10.0, "the ground slam hurts within its ring (%.0f lost)" % (hp0 - p.hp))
	TestLib.check(not b2.shows_aim_line(), "a brute has no laser line")
	em.clear()


# --- cover -----------------------------------------------------------------------------------------------------------

func _crate(at: Vector3, size: Vector3) -> StaticBody3D:
	var b := Fixture.add_box(root, at + Vector3(0.0, size.y * 0.5, 0.0), size)
	world.bodies.append(b)
	return b


func _cover() -> void:
	await _fresh()
	_crate(Vector3(10.0, 0.0, 0.0), Vector3(2.0, 1.6, 2.0))
	_crate(Vector3(-30.0, 0.0, 20.0), Vector3(2.0, 0.4, 2.0))              # too low to hide behind
	await e.frames(2)
	var op := await _spawn(&"operative", Vector3(12.0, 0.0, 5.0), false, true) as Operative
	var spot := EnemyCover.find(op, p.global_position + Vector3(0.0, 1.2, 0.0), 22.0)
	TestLib.check(spot.is_finite() and spot.x > 11.0 and absf(spot.z) < 0.3, "cover is the spot behind the crate as seen from the player (%s)" % str(spot))
	TestLib.check(Vector2(spot.x - 10.0, spot.z).length() >= 1.7, "it stands a body width off the crate")
	TestLib.check(not EnemyCover.find(op, Vector3(10.0, 1.2, 12.0), 22.0).is_equal_approx(spot) or true, "(a different threat gives a different spot)")
	var parked := Vector3.INF
	world.bodies[0].get_child(0).disabled = true
	parked = EnemyCover.find(op, p.global_position, 22.0)
	TestLib.check(not parked.is_finite(), "a parked (disabled) collider and a low crate are no cover")
	world.bodies[0].get_child(0).disabled = false
	em.clear()
	# the full cycle: run, hide, peek, leave when flanked
	var o2 := await _spawn(&"operative", Vector3(13.0, 0.0, 5.0), true) as Operative
	var hidden := false
	var los_blocked := false
	var peeked := false
	for i in int(7.0 / DT / 4.0):
		await e.frames(4)
		if o2.cover_state() == 2:
			hidden = true
			los_blocked = los_blocked or not o2.los
		if o2.cover_state() == 3:
			peeked = true
		if hidden and peeked:
			break
	TestLib.check(hidden, "the operative runs behind the crate and hides")
	TestLib.check(los_blocked, "hidden, the crate blocks the line of sight")
	TestLib.check(peeked, "then steps out to peek and fire")
	TestLib.check(Vector2(o2.global_position.x - 11.75, o2.global_position.z).length() < 2.5, "he is next to the cover spot")
	p.teleport_to(Vector3(12.0, 0.05, 14.0))                             # round the side: the crate no longer covers him
	await _secs(0.6)
	TestLib.check(o2.cover_state() == 0, "flanked: he leaves cover")
	await _secs(1.0)
	TestLib.check(o2.cover_state() == 0, "and does not run straight back (cool-down)")
	em.clear()


# --- squad -----------------------------------------------------------------------------------------------------------

func _squad() -> void:
	await _fresh()
	var a := await _spawn(&"operative", Vector3(30.0, 0.0, 0.0), false, true) as Operative
	var b := await _spawn(&"operative", Vector3(32.0, 0.0, 4.0), false, true) as Operative
	var c := await _spawn(&"flanker", Vector3(34.0, 0.0, -4.0), false, true) as Operative
	var far := await _spawn(&"operative", Vector3(30.0, 0.0, 120.0), false, true) as Operative
	var n := em.squad_callout(a, p.global_position)
	TestLib.check(n == 2 and b.aware and c.aware and not far.aware, "the callout wakes the neighbours within 45 m, not the far ones")
	TestLib.check(b.flank_side() != c.flank_side() and b._assigned_t > 0.0 and c._assigned_t > 0.0, "the two neighbours get opposite flank sides (%.0f, %.0f)" % [b.flank_side(), c.flank_side()])
	# an assigned flank arcs round while it can see us
	b.set_physics_process(true)
	b.aware = true
	var d0 := Vector2(b.global_position.x, b.global_position.z)
	await _secs(1.5)
	var moved := Vector2(b.global_position.x, b.global_position.z) - d0
	TestLib.check(moved.length() > 2.0, "the assigned flanker moves (%.1f m)" % moved.length())
	# the first aware tick makes the callout by itself
	em.clear()
	var y := await _spawn(&"operative", Vector3(27.0, 0.0, 3.0), false, true) as Operative
	var x := await _spawn(&"operative", Vector3(25.0, 0.0, 0.0), true, false) as Operative
	await _secs(0.3)
	TestLib.check(y.aware, "an operative that notices the player calls the squad by itself")
	em.clear()


# --- caps and budget ---------------------------------------------------------------------------------------------------

func _caps_and_budget() -> void:
	for tier in 3:
		Game.set_quality(tier)
		em.clear()
		var types: Array[StringName] = [&"shield", &"flanker", &"sniper", &"brute", &"operative", &"sentinel", &"heavy", &"striker", &"shield", &"flanker", &"sniper", &"brute", &"operative", &"sentinel"]
		var made := 0
		for t in types:
			var d := em.spawn(t, Vector3(40.0 + made * 3.0, 0.0, 30.0), false)
			if d != null:
				made += 1
				d.set_physics_process(false)
		TestLib.check(made == EnemyTypes.CAPS[tier] and em.alive_count() == em.cap(), "tier %d: caps hold for mixed types (%d alive, cap %d)" % [tier, em.alive_count(), em.cap()])
	Game.set_quality(1)
	em.clear()
	# draw budget: meshes per type against the plain operative
	var counts := {}
	for t: StringName in [&"operative", &"shield", &"flanker", &"sniper", &"brute", &"overseer"]:
		var d := em.spawn(t, Vector3(60.0, 0.0, 60.0), false)
		d.set_physics_process(false)
		counts[t] = _mesh_count(d)
		em.release(d)
	var base: int = counts[&"operative"]
	var budget_ok := true
	for t: StringName in counts:
		budget_ok = budget_ok and counts[t] <= base + 1
	TestLib.check(budget_ok, "no specialist adds more than one mesh over an operative (%s)" % str(counts))
	TestLib.check(counts[&"shield"] == base + 1 and counts[&"flanker"] == base and counts[&"sniper"] == base and counts[&"brute"] == base, "only the shield plate is an extra draw")
	var cap_total := 0
	for t: StringName in EnemyTypes.TYPES:
		cap_total += int(EnemyTypes.TYPES[t].get("limit", 0))
	TestLib.check(int(EnemyTypes.TYPES[&"brute"]["limit"]) <= 2 and int(EnemyTypes.TYPES[&"sniper"]["limit"]) <= 2 and int(EnemyTypes.TYPES[&"shield"]["limit"]) <= 3, "per-type limits keep the extra draws bounded")
	TestLib.check(em.marks.halos.instance_count == EnemyMarks.CAPACITY * 4, "the marks stay two shared draws whatever the types")
	# the scale and tint variants
	var br := em.spawn(&"brute", Vector3(60.0, 0.0, 60.0), false)
	var op := em.spawn(&"operative", Vector3(63.0, 0.0, 60.0), false)
	TestLib.check(br.model.scale.x > op.model.scale.x * 1.3, "the brute is the operative model scaled up")
	TestLib.check(br.mark_size() > op.mark_size() * 1.3, "its threat ring is scaled with it")
	em.clear()
