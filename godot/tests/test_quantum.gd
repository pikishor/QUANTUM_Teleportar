extends RefCounted
## Quantum module tests (headless): the real Quantum child of a real Player, a real EnemyManager and drones.
## BLINK (beacon placement on floor / next to a wall, teleport, costs, cooldowns, expiry, bit readout m1 -> X, m0 -> Z, vehicle / paused gating, input action),
## ENTANGLE (link rules, mirrored damage both ways, kill propagation, expiry, targeting failures, beams, tier cap), SUPERPOSITION (ghost, shared material,
## no lights, speed boost, expiry, collapse blast and damage, cooldown, player takes no damage), enemy <-> clone (targeting, bolt collapse), lifecycle
## resets, pausing, graphics tiers and node-count stability (pooling), and the HUD's view of the module.
## Time runs 4x (time_scale and tick rate together, see ARCHITECTURE.md); every wait is in ticks of 1/60 s of game time.
## Run: tools/test.sh tests/test_quantum.gd

const Env := preload("res://tests/player_env.gd")
const Stubs := preload("res://tests/enemies_stubs.gd")
const Fixture := preload("res://tests/player_fixture.gd")

const K := 4

var e := Env.new()
var p: Player
var q: Quantum
var mgr: EnemyManager
var root: Node3D
var stub_missions := Stubs.StubMissions.new()
var msgs: Array[String] = []
var _saved_quality := 1


func run(host: Node) -> void:
	seed(5)
	await e.setup(host)
	p = e.p
	root = e.root
	_saved_quality = Game.quality
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	p.max_hp = 1.0e6
	Game.message.connect(func(t: String, _s: float) -> void: msgs.append(t))
	root.add_child(stub_missions)
	Game.missions = stub_missions
	Game.world = null
	mgr = (load("res://scenes/enemy_manager.tscn") as PackedScene).instantiate() as EnemyManager
	root.add_child(mgr)
	await e.frames(3)
	await _attach()
	await _blink_place()
	await _blink_teleport()
	await _blink_rules()
	await _bits()
	await _entangle()
	await _entangle_rules()
	await _superposition()
	await _enemy_clone()
	await _lifecycle()
	await _tiers()
	await _pooling()
	await _hud_view()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Game.set_quality(_saved_quality)
	Game.missions = null
	Game.heat = 0.0
	Game.score = 0
	await e.teardown()


func _fresh(tier := 1) -> void:
	Game.set_quality(tier)
	mgr.clear()
	q.reset()
	Game.heat = 0.0
	Game.quiet = 0.0
	msgs.clear()
	await e.prep(Vector3(-5.0, 0.0, 4.0))
	p.energy = 100.0
	await _settle()


## Player.get_aim() is cached per RENDERED frame; at 4x time several physics ticks pass per rendered frame, so wait for fresh process frames too.
func _settle() -> void:
	await e.frames(2)
	await host_tree().process_frame
	await host_tree().process_frame


func host_tree() -> SceneTree:
	return e.host.get_tree()


func _has_msg(part: String) -> bool:
	for m in msgs:
		if m.contains(part):
			return true
	return false


func _spawn(type: StringName, pos: Vector3, aware := false) -> Drone:
	var d := mgr.spawn(type, pos, aware)
	TestLib.check(d != null, "spawned a %s" % type)
	return d


## The visible mesh instances under the module's effect root (the beacon, the ghost, the beams).
func _visible_meshes(under: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in under.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.is_visible_in_tree():
			out.append(m)
	return out


func _attach() -> void:
	q = p.quantum as Quantum
	TestLib.check(q != null and q.get_parent() == p, "the player created the real Quantum module as its child")
	TestLib.check(not q.has_beacon and q.clone == null and q.links.is_empty() and q.cd_blink == 0.0 and q.cd_link == 0.0 and q.cd_super == 0.0, "idle state: no beacon, clone, links or cooldowns")
	TestLib.check(q.fx_root != null and q.fx_root.top_level, "the effects live under one top-level root")
	TestLib.check(_visible_meshes(q.fx_root).is_empty(), "idle: nothing of the module is drawn")
	TestLib.check(q.find_children("*", "Light3D", true, false).is_empty(), "the module owns no lights")


func _blink_place() -> void:
	await _fresh()
	TestLib.check(q.blink(), "blink throws a beacon")
	TestLib.check(q.has_beacon, "has_beacon is set")
	var dir := (q.beacon_pos - p.global_position)
	TestLib.check(dir.x > 8.0 and absf(dir.z) < 6.0, "the beacon is out in front along the aim (+x), %.1f m away" % dir.x)
	TestLib.check(absf(q.beacon_pos.y) < 0.05, "the beacon is dropped onto the floor (y %.3f)" % q.beacon_pos.y)
	TestLib.check(absf(p.energy - 85.0) < 0.5, "a beacon costs 15 energy (%.1f left)" % p.energy)
	TestLib.check(q.cd_blink > 0.25 and q.cd_blink <= 0.3, "cooldown starts at 0.3 s (%.2f)" % q.cd_blink)
	TestLib.check(absf(q.beacon_left - 8.0) < 0.1, "the beacon lives 8 s (%.2f)" % q.beacon_left)
	TestLib.check(_has_msg("TELEPORT MARKER SET"), "the HUD message names the beacon")
	await e.frames(3)
	var shown := _visible_meshes(q.fx_root)
	TestLib.check(shown.size() >= 4, "the beacon draws pillar, ring(s), core and glow (%d meshes)" % shown.size())
	# it is not a teleport yet
	TestLib.check(p.global_position.distance_to(Vector3(-5.0, 0.0, 4.0)) < 1.0, "the player stays where he is")
	# the beacon counts down and expires
	await e.secs(1.0)
	TestLib.check(absf(q.beacon_left - 7.0) < 0.2, "the beacon timer runs (%.2f)" % q.beacon_left)
	q.beacon_left = 0.1
	await e.secs(0.3)
	TestLib.check(not q.has_beacon and _visible_meshes(q.fx_root).is_empty(), "an expired beacon disappears")
	# aiming at a wall stops 0.6 m short of it
	await _fresh()
	p.camera_rig.reset_view(PI * 0.5, 0.0)
	p.yaw = PI * 0.5
	await _settle()
	q.blink()
	TestLib.check(q.beacon_pos.x > Env.WALL_FACE_X + 0.1 and q.beacon_pos.x < Env.WALL_FACE_X + 3.0, "aimed at the wall the beacon stops short of it (x %.2f)" % q.beacon_pos.x)
	# far aim at the sky is capped at 48 m from the camera and dropped to the floor
	await _fresh()
	p.camera_rig.reset_view(-PI * 0.5, 0.35)
	p.yaw = -PI * 0.5
	await _settle()
	q.blink()
	var far := q.beacon_pos - p.camera_rig.camera.global_position
	TestLib.check(q.has_beacon and Vector2(far.x, far.z).length() <= 49.0, "a beacon never lands further than 48 m (%.1f)" % Vector2(far.x, far.z).length())
	TestLib.check(absf(q.beacon_pos.y) < 0.05, "a beacon aimed at the sky still lands on the floor")


func _blink_teleport() -> void:
	await _fresh()
	q.blink()
	var target := q.beacon_pos
	await e.secs(0.35)
	msgs.clear()
	var energy := p.energy
	TestLib.check(q.blink(), "the second press teleports")
	TestLib.check(p.global_position.distance_to(target + Vector3(0.0, 0.05, 0.0)) < 0.2, "the player stands on the beacon (%.2f m off)" % p.global_position.distance_to(target))
	TestLib.check(not q.has_beacon, "the beacon is used up")
	TestLib.check(p.energy >= energy - 0.01, "the teleport itself is free")
	TestLib.check(q.cd_blink > 0.35 and q.cd_blink <= 0.4, "teleport cooldown 0.4 s (%.2f)" % q.cd_blink)
	TestLib.check(p.velocity.length() < 0.01, "the player's velocity is cleared")
	var m := ""
	for t in msgs:
		if t.begins_with("QUANTUM TELEPORT"):
			m = t
	TestLib.check(m != "", "the teleport message is shown")
	TestLib.check(m == "QUANTUM TELEPORT", "message reads QUANTUM TELEPORT: " + m)
	q._slow_end()
	TestLib.check(q.bits_left > 4.5 and q.last_fix != "", "the HUD readout stays up for about 5 s (%.1f)" % q.bits_left)
	await e.secs(0.1)
	TestLib.check(not q.blink(), "no new beacon during the 0.4 s cooldown")
	await e.secs(0.4)
	TestLib.check(q.blink() and q.has_beacon, "a new beacon after the cooldown")
	await e.secs(5.5)
	TestLib.check(q.bits_left == 0.0, "the readout times out")


func _blink_rules() -> void:
	await _fresh()
	p.energy = 14.0
	TestLib.check(not q.blink() and not q.has_beacon, "14 energy is not enough for a beacon")
	TestLib.check(_has_msg("NOT ENOUGH COHERENCE") and absf(p.energy - 14.0) < 0.5, "it says so and costs nothing")
	p.energy = 15.0
	TestLib.check(q.blink(), "exactly 15 energy is enough")
	q.reset()
	# in a vehicle
	await _fresh()
	var veh := Fixture.add_vehicle(root, Vector3(-5.0, 0.0, 4.0))
	p.vehicle = veh
	await e.frames(2)
	TestLib.check(not q.blink() and _has_msg("QUANTUM TELEPORT OFFLINE IN VEHICLE"), "blink is offline in a vehicle")
	TestLib.check(not q.superpose() and _has_msg("SUPERPOSITION OFFLINE IN VEHICLE"), "superposition is offline in a vehicle")
	p.teleport_to(Vector3(-5.0, 0.0, 4.0))
	p.vehicle = null
	veh.queue_free()
	await e.frames(3)
	# the real input action, polled by the module while playing
	await _fresh()
	Input.action_press(&"blink")
	await e.frames(3)
	Input.action_release(&"blink")
	await e.frames(3)
	TestLib.check(q.has_beacon, "pressing the blink action throws a beacon")
	Input.action_press(&"blink")
	await e.frames(3)
	Input.action_release(&"blink")
	await e.frames(3)
	TestLib.check(not q.has_beacon and p.global_position.distance_to(Vector3(-5.0, 0.0, 4.0)) > 5.0, "pressing it again teleports")
	# paused: nothing runs, nothing is read
	await _fresh()
	q.blink()
	var left := q.beacon_left
	Game.state = &"paused"
	Input.action_press(&"superpose")
	await e.secs(0.5)
	Input.action_release(&"superpose")
	TestLib.check(q.clone == null and absf(q.beacon_left - left) < 0.001, "paused: inputs are ignored and timers stand still")
	TestLib.check(not q.blink() and not q.link_drones() and not q.superpose(), "paused: the abilities refuse to fire")
	Game.state = &"play"
	await e.frames(2)
	TestLib.check(q.beacon_left < left, "playing again: the timers run on")


func _bits() -> void:
	TestLib.check(Quantum.fix_for(0, 0) == "NOTHING", "bits 00: no correction")
	TestLib.check(Quantum.fix_for(0, 1) == "X", "m1 = 1 alone: X")
	TestLib.check(Quantum.fix_for(1, 0) == "Z", "m0 = 1 alone: Z")
	TestLib.check(Quantum.fix_for(1, 1) == "X THEN Z", "both bits: X then Z")
	await _fresh()
	var seen := {}
	for i in 40:
		q.cd_blink = 0.0
		q.blink()
		q.teleport()
		seen["%d%d" % [q.last_m0, q.last_m1]] = true
		if q.last_fix != Quantum.fix_for(q.last_m0, q.last_m1):
			TestLib.check(false, "the shown correction follows the bits")
			break
		p.energy = 100.0
	TestLib.check(seen.size() == 4, "all four bit pairs occur over 40 teleports (%d)" % seen.size())


func _link_pair(ax: Vector3, bx: Vector3) -> Array[Drone]:
	var a := _spawn(&"sentinel", ax)
	var b := _spawn(&"sentinel", bx)
	return [a, b]


func _aim_at(d: Drone) -> void:
	p.camera_rig.aim_at(d.center())
	await _settle()


func _entangle() -> void:
	await _fresh()
	var pair := _link_pair(Vector3(15.0, 0.0, 4.0), Vector3(20.0, 0.0, 10.0))
	var a := pair[0]
	var b := pair[1]
	var far := _spawn(&"sentinel", Vector3(15.0, 0.0, 70.0))
	await _aim_at(a)
	TestLib.check(q.link_drones(), "entangle links the aimed drone")
	TestLib.check(a.linked == b and b.linked == a, "A and its nearest free neighbour B are linked both ways")
	TestLib.check(far.linked == null, "the far drone is left alone")
	TestLib.check(a.aware and b.aware, "both drones become aware")
	TestLib.check(q.links.size() == 1, "links lists the pair")
	TestLib.check(absf(p.energy - 75.0) < 0.5, "a link costs 25 energy (%.1f)" % p.energy)
	TestLib.check(q.cd_link > 0.7 and q.cd_link <= 0.8, "link cooldown 0.8 s (%.2f)" % q.cd_link)
	TestLib.check(_has_msg("ENTANGLED"), "the HUD message names it")
	await e.frames(3)
	TestLib.check(_visible_meshes(q.fx_root).size() >= 2, "two beams join the pair")
	# damage to one mirrors to the other, both ways, without bouncing back
	var hp_a := a.hp
	var hp_b := b.hp
	a.damage(10.0)
	TestLib.check(absf(a.hp - (hp_a - 10.0)) < 0.01 and absf(b.hp - (hp_b - 10.0)) < 0.01, "10 damage to A also hits B (A %.0f, B %.0f)" % [a.hp, b.hp])
	b.damage(7.0)
	TestLib.check(absf(a.hp - (hp_a - 17.0)) < 0.01 and absf(b.hp - (hp_b - 17.0)) < 0.01, "7 damage to B also hits A (A %.0f, B %.0f)" % [a.hp, b.hp])
	TestLib.check(far.hp == far.max_hp, "the unlinked drone is untouched")
	# killing one kills the other and the link ends
	a.damage(9999.0)
	await e.frames(3)
	TestLib.check(a.dead and b.dead, "a lethal hit on A kills B as well")
	TestLib.check(q.links.is_empty(), "the link is gone when its drones die")
	await _fresh()
	# expiry after 9 s and the beams go with it
	pair = _link_pair(Vector3(15.0, 0.0, 4.0), Vector3(20.0, 0.0, 10.0))
	await _aim_at(pair[0])
	q.link_drones()
	await e.secs(1.0)
	TestLib.check(absf(float(q.links[0]["t"]) - 8.0) < 0.2, "a link lasts 9 s (%.2f left after 1 s)" % float(q.links[0]["t"]))
	q.links[0]["t"] = 0.1
	await e.secs(0.3)
	TestLib.check(q.links.is_empty() and pair[0].linked == null and pair[1].linked == null, "an expired link frees both drones")
	TestLib.check(_visible_meshes(q.fx_root).is_empty(), "and hides its beams")
	var hp := pair[1].hp
	pair[0].damage(5.0)
	TestLib.check(pair[1].hp == hp, "damage no longer mirrors after the link ended")
	# a linked drone is not picked again
	await _fresh()
	pair = _link_pair(Vector3(15.0, 0.0, 4.0), Vector3(20.0, 0.0, 10.0))
	var third := _spawn(&"sentinel", Vector3(25.0, 0.0, 4.0))
	await _aim_at(pair[0])
	q.link_drones()
	q.cd_link = 0.0
	await _aim_at(pair[0])
	TestLib.check(not q.link_drones() and q.links.size() == 1, "an already linked drone cannot be linked again")
	TestLib.check(third.linked == null, "nothing else gets linked")


func _entangle_rules() -> void:
	await _fresh()
	var a := _spawn(&"sentinel", Vector3(15.0, 0.0, 4.0))
	await _aim_at(a)
	p.energy = 24.0
	TestLib.check(not q.link_drones() and _has_msg("NOT ENOUGH COHERENCE"), "24 energy is not enough for a link")
	p.energy = 100.0
	msgs.clear()
	TestLib.check(not q.link_drones() and _has_msg("NEED A SECOND TARGET WITHIN 45 m"), "a single drone cannot be linked")
	TestLib.check(absf(p.energy - 100.0) < 0.5 and q.cd_link == 0.0, "a failed link costs nothing and starts no cooldown")
	var b := _spawn(&"sentinel", Vector3(15.0, 0.0, 60.0))
	TestLib.check(not q.link_drones() and b.linked == null, "a partner 56 m away is out of range")
	b.deactivate() if b.has_method(&"deactivate") else mgr.clear()
	await _fresh()
	_spawn(&"sentinel", Vector3(15.0, 0.0, 4.0))
	_spawn(&"sentinel", Vector3(20.0, 0.0, 4.0))
	p.camera_rig.reset_view(-PI * 0.5, 0.6)         # looking at the sky
	await _settle()
	TestLib.check(not q.link_drones() and _has_msg("NO TARGET IN SIGHT"), "aiming at nothing finds no target")
	# a wall between the player and the drone blocks the aim (the ray stops at the wall)
	await _fresh()
	p.teleport_to(Vector3(-15.0, 0.0, 4.0))
	p.camera_rig.reset_view(-PI * 0.5, 0.0)
	await _settle()
	var behind := _spawn(&"sentinel", Vector3(-3.0, 0.0, 4.0))
	_spawn(&"sentinel", Vector3(0.0, 0.0, 8.0))
	TestLib.check(behind != null and not q.link_drones(), "a drone behind a wall cannot be targeted")


func _superposition() -> void:
	await _fresh()
	var boost0 := p.speed_boost
	TestLib.check(boost0 == 1.0, "normal speed to begin with")
	var pos := p.global_position
	TestLib.check(q.superpose(), "superpose leaves a clone")
	TestLib.check(q.clone != null and q.clone.is_in_group(&"clone"), "the clone exists and is in group clone")
	TestLib.check(q.clone.global_position.distance_to(pos) < 0.05, "it stands where the player stood")
	TestLib.check(absf(p.energy - 65.0) < 0.5, "superposition costs 35 (%.1f)" % p.energy)
	TestLib.check(p.speed_boost == 1.3, "speed boost 1.3 while the clone lives")
	TestLib.check(absf(q.clone_left - 6.0) < 0.1, "the clone lives 6 s")
	TestLib.check(_has_msg("SUPERPOSITION"), "the HUD message names it")
	await e.frames(3)
	TestLib.check(mgr.get_clone() == q.clone, "the enemy manager finds the clone through player.quantum.clone")
	var meshes := _visible_meshes(q.clone)
	TestLib.check(meshes.size() >= 1 and meshes.size() <= 18, "the ghost is a handful of meshes (%d draws)" % meshes.size())
	var one_material := true
	for m in meshes:
		one_material = one_material and m.material_override == Quantum._mat_ghost
	TestLib.check(one_material and Quantum._mat_ghost != null, "every ghost mesh shares one hologram material")
	TestLib.check(q.find_children("*", "Light3D", true, false).is_empty() and q.clone.find_children("*", "Light3D", true, false).is_empty(), "the ghost adds no lights")
	# the player walks away; the ghost stays
	p.teleport_to(pos + Vector3(8.0, 0.0, 0.0))
	await e.secs(0.5)
	TestLib.check(q.clone.global_position.distance_to(pos) < 0.05, "the ghost stays behind")
	# pressing again collapses it into a blast that damages enemies, not the player
	var heavy := _spawn(&"heavy", pos + Vector3(3.0, 0.0, 0.0))
	p.teleport_to(pos + Vector3(0.0, 0.0, 0.0))
	await e.frames(2)
	var hp0 := p.hp
	var hv0 := heavy.hp
	TestLib.check(q.superpose(), "pressing again collapses the clone")
	TestLib.check(q.clone == null and not q.is_in_group(&"clone"), "the clone is gone")
	var lost := hv0 - heavy.hp
	TestLib.check(lost > 50.0 and lost < 70.0, "the blast hurts a drone 3 m away by 70 minus falloff (%.1f)" % lost)
	TestLib.check(p.hp >= hp0 - 0.01, "the blast does not hurt the player")
	TestLib.check(p.speed_boost == 1.0, "speed boost ends with the clone")
	TestLib.check(q.cd_super > 1.4 and q.cd_super <= 1.5, "collapse cooldown 1.5 s (%.2f)" % q.cd_super)
	TestLib.check(_has_msg("WAVEFUNCTION COLLAPSE"), "the HUD message names the collapse")
	TestLib.check(not q.superpose(), "no new clone during the cooldown")
	await e.secs(1.6)
	TestLib.check(q.superpose() and q.clone != null, "a new clone after the cooldown")
	# expiry collapses it as well
	var d2 := _spawn(&"sentinel", q.clone.global_position + Vector3(1.0, 0.0, 0.0))
	q.clone_left = 0.1
	await e.secs(0.3)
	TestLib.check(q.clone == null and (d2.dead or d2.hp < d2.max_hp), "an expired clone collapses with a small pulse that hurts a nearby sentinel")
	await e.secs(1.6)
	# energy gate
	p.energy = 34.0
	TestLib.check(not q.superpose() and _has_msg("NOT ENOUGH COHERENCE"), "34 energy is not enough for a clone")
	await _fresh()
	q.superpose()
	await e.secs(5.2)
	TestLib.check(q.clone != null and q.clone.visible in [true, false], "the clone is still out 5.2 s in")


func _enemy_clone() -> void:
	await _fresh()
	q.superpose()
	p.teleport_to(Vector3(-40.0, 0.0, 4.0))
	var clone_pos := q.clone.global_position
	var d := _spawn(&"sentinel", Vector3(15.0, 0.0, 4.0), true)
	var seen := false
	for i in 1500:
		await e.frames(1)
		seen = seen or d._tgt_clone
		if q.clone != null:
			q.clone_left = maxf(q.clone_left, 30.0)  # keep the clone alive on slow runners
		if seen or q.clone == null:
			break
	TestLib.check(seen, "an aware drone picks the real clone as a target")
	await _fresh()
	q.superpose()
	var cp := q.clone.global_position
	mgr.bolt(cp + Vector3(8.0, 1.0, 0.0), cp + Vector3(0.0, 1.0, 0.0), &"sentinel")
	await e.secs(0.8)
	TestLib.check(q.clone == null, "an enemy bolt that hits the clone collapses it through the real module")
	TestLib.check(q.cd_super > 0.0 and p.speed_boost == 1.0, "the collapse started the cooldown and ended the speed boost")
	TestLib.check(mgr.get_clone() == null, "enemies have no clone afterwards")
	TestLib.check(clone_pos.distance_to(Vector3(-5.0, 0.0, 4.0)) < 0.1, "the clone stood where the player cast it")


func _lifecycle() -> void:
	for sig in [&"respawn", &"new_game", &"next_sector"]:
		await _fresh()
		var pair := _link_pair(Vector3(15.0, 0.0, 4.0), Vector3(20.0, 0.0, 10.0))
		await _aim_at(pair[0])
		q.link_drones()
		q.blink()
		q.superpose()
		TestLib.check(q.has_beacon and q.clone != null and q.links.size() == 1, "%s: beacon, clone and link are out" % sig)
		Game.call(&"do_respawn" if sig == &"respawn" else (&"start_new_game" if sig == &"new_game" else &"do_next_sector"))
		await e.frames(2)
		TestLib.check(not q.has_beacon and q.clone == null and q.links.is_empty(), "%s resets beacon, clone and links" % sig)
		TestLib.check(q.cd_blink == 0.0 and q.cd_link == 0.0 and q.cd_super == 0.0 and p.speed_boost == 1.0, "%s clears cooldowns and the speed boost" % sig)
		TestLib.check(pair[0].linked == null and pair[1].linked == null, "%s frees the drones" % sig)
		TestLib.check(_visible_meshes(q.fx_root).is_empty(), "%s hides every visual" % sig)
	# death: nothing is read, nothing runs
	await _fresh()
	q.blink()
	Game.state = &"dead"
	var left := q.beacon_left
	await e.secs(0.3)
	TestLib.check(absf(q.beacon_left - left) < 0.001 and not q.superpose(), "dead: the module is frozen")
	Game.state = &"play"


func _tiers() -> void:
	# LOW: one link at a time, no glow sprite, no second ring, no ghost ring, one beam per link
	await _fresh(0)
	var drones: Array[Drone] = []
	for i in 4:
		drones.append(_spawn(&"sentinel", Vector3(15.0, 0.0, -12.0 + i * 10.0 + (i % 2) * 0.0)))
	await _aim_at(drones[0])
	q.link_drones()
	q.cd_link = 0.0
	TestLib.check(Quantum.MAX_LINKS == [1, 2, 3], "caps are LOW 1, MED 2, HIGH 3 links")
	await _aim_at(drones[2])
	q.link_drones()
	TestLib.check(q.links.size() == 1, "LOW keeps one link at a time (%d)" % q.links.size())
	TestLib.check(drones[0].linked == null or drones[2].linked != null, "the older link made room for the new one")
	q.blink()
	q.superpose()
	await e.frames(3)
	TestLib.check(not q._glow.visible and not q._ring2.visible and not q._ghost_ring.visible, "LOW draws no glow, no second ring, no ghost ring")
	TestLib.check(q._beams.size() >= 2 and not q._beams[1].visible, "LOW draws one beam per link")
	var low := _visible_meshes(q.fx_root).size()
	# HIGH: all of it
	await _fresh(2)
	drones.clear()
	for i in 6:
		drones.append(_spawn(&"sentinel", Vector3(15.0, 0.0, -30.0 + i * 12.0)))
	for i in [0, 2, 4]:
		await _aim_at(drones[i])
		q.cd_link = 0.0
		q.link_drones()
	TestLib.check(q.links.size() == 3, "HIGH keeps three links (%d)" % q.links.size())
	p.energy = 100.0
	q.blink()
	q.superpose()
	await e.frames(3)
	TestLib.check(q._glow.visible and q._ring2.visible and q._ghost_ring.visible, "HIGH draws glow, second ring and ghost ring")
	var high := _visible_meshes(q.fx_root).size()
	TestLib.check(high > low, "HIGH draws more than LOW (%d vs %d meshes)" % [high, low])
	# dropping the tier while links are out trims them
	Game.set_quality(0)
	TestLib.check(q.links.size() == 1, "switching to LOW trims the links to one (%d)" % q.links.size())
	await e.frames(3)
	TestLib.check(not q._glow.visible and not q._ghost_ring.visible, "switching to LOW hides the glow and the ghost ring")
	Game.set_quality(1)


func _pooling() -> void:
	await _fresh()
	var drones: Array[Drone] = []
	for i in 2:
		drones.append(_spawn(&"sentinel", Vector3(15.0, 0.0, 4.0 + i * 6.0)))
	await _aim_at(drones[0])
	# one full cycle first (builds the pools), then the node count must not grow
	q.link_drones()
	q.blink()
	q.teleport()
	q.superpose()
	q.collapse()
	await e.secs(1.6)
	var children := q.fx_root.get_child_count()
	var total := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	for i in 8:
		q.cd_blink = 0.0
		q.cd_link = 0.0
		q.cd_super = 0.0
		p.energy = 100.0
		for d in drones:
			d.linked = null
		q.reset()
		q.blink()
		q.teleport()
		q.link_drones()
		q.superpose()
		await e.frames(3)
		q.collapse()
	TestLib.check(q.fx_root.get_child_count() == children, "repeated use creates no new effect nodes (%d children)" % children)
	TestLib.check(Performance.get_monitor(Performance.OBJECT_NODE_COUNT) <= total + 2, "the node count stays flat over repeated use")


func _hud_view() -> void:
	await _fresh()
	var info_blink: Dictionary = UiUtil.ABILITIES[0]
	var info_link: Dictionary = UiUtil.ABILITIES[1]
	var info_super: Dictionary = UiUtil.ABILITIES[2]
	var st := UiUtil.ability_state(p, info_blink)
	TestLib.check(st["on"] and st["ready"] and not st["active"], "HUD: blink is ready when the module exists and there is energy")
	q.blink()
	st = UiUtil.ability_state(p, info_blink)
	TestLib.check(st["active"], "HUD: blink shows active while a beacon is out")
	q.reset()
	p.energy = 10.0
	TestLib.check(UiUtil.ability_state(p, info_blink)["low"], "HUD: blink shows low energy")
	p.energy = 100.0
	q.superpose()
	TestLib.check(UiUtil.ability_state(p, info_super)["active"], "HUD: superposition shows active while the clone lives")
	TestLib.check(UiUtil.ability_state(p, info_super)["left"] > 5.0, "HUD: it reports the seconds left")
	q.collapse()
	TestLib.check(UiUtil.ability_state(p, info_super)["cd"] > 0.9, "HUD: the cooldown after the collapse is shown")
	q.cd_link = 0.0
	TestLib.check(not UiUtil.ability_state(p, info_link)["active"], "HUD: link is idle without links")
	var hud := (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	await e.frames(3)
	TestLib.check(hud.has_method(&"quantum_readout"), "the HUD exposes the blink readout")
	q.cd_blink = 0.0
	q.blink()
	q.teleport()
	await e.frames(3)
	var ro: Dictionary = hud.call(&"quantum_readout")
	TestLib.check(ro["visible"] and ro["m0"] == q.last_m0 and ro["m1"] == q.last_m1 and ro["fix"] == q.last_fix, "the HUD readout shows Alice's bits and Bob's correction")
	q.bits_left = 0.0
	TestLib.check(not hud.call(&"quantum_readout")["visible"], "and goes away when the time is up")
	hud.queue_free()
	await e.frames(2)
