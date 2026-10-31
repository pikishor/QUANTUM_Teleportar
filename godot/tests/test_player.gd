extends RefCounted
## Player module tests, part 1 (headless): everything in the module contract in a compact run.
## Spawn, gravity and landing, walk / sprint / aim speed, jump apex, wall collision, ammo and reload timing, hitscan (14 damage, 30 on a crit,
## collider-less targets), spread, damage / regeneration pause / death exactly once / invulnerability, lifecycle resets, vehicle mode,
## teleport_to and get_aim. Part 2 (tests/test_player_polish.gd) checks the finer points: coyote time, buffering, curbs, camera, recoil, pools...
## Runs against fixtures built here (floor, wall, dummy targets); no other module is needed.
## Run: tools/test.sh tests/test_player.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")

var e := Env.new()
var p: Player


func run(host: Node) -> void:
	await e.setup(host)
	p = e.p
	await _scene()
	await _spawn_gravity_landing()
	await _speeds()
	await _jump_apex()
	await _wall()
	await _rifle_ammo_reload()
	await _hitscan()
	await _spread()
	await _health()
	await _death_and_invulnerability()
	await _lifecycle()
	await _vehicle_mode()
	await _teleport_and_aim()
	await e.teardown()


func _scene() -> void:
	TestLib.check(p is CharacterBody3D, "Player is a CharacterBody3D")
	TestLib.check(p.is_in_group(&"player"), "Player is in group 'player'")
	TestLib.check(p.collision_layer == Game.L_PLAYER, "Player collision layer is 'player' (2)")
	TestLib.check(Game.player == p, "Game.player is the player")
	TestLib.check(Game.camera != null and Game.camera == p.camera_rig.camera, "Game.camera is the rig's camera")
	TestLib.check(p.camera_rig is CameraRig and p.camera_rig.arm is SpringArm3D and p.camera_rig.camera is Camera3D, "CameraRig holds a SpringArm3D and a Camera3D")
	TestLib.check(p.camera_rig.arm.shape is SphereShape3D, "the spring arm uses a sphere shape")
	TestLib.check(p.max_hp == 100.0 and p.max_energy == 100.0 and p.hp == 100.0 and p.energy == 100.0, "health and energy start at 100")
	TestLib.check(p.ammo == 30 and p.mag == 30 and not p.reloading and not p.aiming and not p.sprinting and p.vehicle == null, "rifle full (30/30), idle flags false, on foot")
	if p.quantum != null:
		TestLib.check(p.quantum.get_parent() == p, "the optional Quantum child hangs under the player")
	await e.frames(1)


func _spawn_gravity_landing() -> void:
	p.reset()
	await e.frames(20)
	var sp := p.global_position
	TestLib.check(absf(sp.x - Game.SPAWN.x) < 0.01 and absf(sp.z - Game.SPAWN.z) < 0.01, "spawns at Game.SPAWN (x/z), got %s" % str(sp))
	TestLib.check(sp.y > -0.05 and sp.y < 0.1 and p.is_on_floor(), "stands on the floor at spawn (y = %.3f)" % sp.y)
	# gravity: free fall from 4 m
	await e.prep(Vector3(-30.0, 4.0, 4.0), -PI * 0.5, -0.12, 0)
	TestLib.check(p.global_position.y > 3.9, "teleported 4 m up")
	var y0 := p.global_position.y
	await e.secs(0.3)
	TestLib.check(absf(p.velocity.y - (-22.0 * 0.3)) < 1.2, "gravity 22 m/s2: after 0.3 s the fall speed is about 6.6 (got %.2f)" % -p.velocity.y)
	var drop := y0 - p.global_position.y
	TestLib.check(absf(drop - 0.5 * 22.0 * 0.09) < 0.3, "fall distance after 0.3 s is about 1 m (got %.2f)" % drop)
	await e.secs(0.7)
	TestLib.check(p.is_on_floor() and absf(p.global_position.y) < 0.05, "lands and stands on the floor (y = %.3f)" % p.global_position.y)
	TestLib.check(absf(p.velocity.y) < 0.5, "vertical speed is zero after landing")


func _speeds() -> void:
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	Input.action_press(&"move_forward")
	await e.secs(0.6)
	var walk := e.flat_speed()
	TestLib.check(absf(walk - 6.2) < 0.15, "walk speed is 6.2 m/s while move_forward is held (got %.2f)" % walk)
	TestLib.check(p.velocity.x > 6.0, "moves along +X when looking along +X")
	Input.action_press(&"sprint")
	await e.secs(0.5)
	var sprint := e.flat_speed()
	TestLib.check(absf(sprint - 6.2 * 1.6) < 0.25 and p.sprinting, "sprint is x1.6 = 9.92 m/s (got %.2f)" % sprint)
	Input.action_release(&"sprint")
	Input.action_press(&"aim")
	await e.secs(0.5)
	var aim := e.flat_speed()
	TestLib.check(absf(aim - 3.4) < 0.15 and p.aiming, "aim walk speed is 3.4 m/s (got %.2f)" % aim)
	Input.action_release(&"aim")
	Input.action_release(&"move_forward")


func _jump_apex() -> void:
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	var base := p.global_position.y
	Input.action_press(&"jump")
	var apex := base
	var left_ground := false
	for i in 62:
		await e.frames(1)
		apex = maxf(apex, p.global_position.y)
		left_ground = left_ground or not p.is_on_floor()
		if i == 2:
			Input.action_release(&"jump")
	TestLib.check(left_ground, "jump leaves the ground")
	TestLib.check(absf((apex - base) - 7.6 * 7.6 / (2.0 * 22.0)) < 0.06, "jump apex is v2/2g = 1.31 m (got %.3f)" % (apex - base))
	TestLib.check(p.is_on_floor(), "lands again after the jump")


func _wall() -> void:
	await e.prep(Vector3(-15.0, 0.0, 4.0))
	Input.action_press(&"move_forward")
	await e.secs(1.4)
	var x := p.global_position.x
	TestLib.check(x < Env.WALL_FACE_X and x > -11.4, "the wall at x = -10.5 stops the player (x = %.2f, radius 0.35)" % x)
	TestLib.check(e.flat_speed() < 0.5, "no speed left when pushing into a wall (%.2f)" % e.flat_speed())
	Input.action_release(&"move_forward")


func _rifle_ammo_reload() -> void:
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	var fired := [0]
	var cb := func() -> void: fired[0] += 1
	p.fired.connect(cb)
	Input.action_press(&"fire")
	await e.secs(0.7)
	Input.action_release(&"fire")
	var shots := p.weapon.shots_fired
	TestLib.check(shots >= 6 and shots <= 8, "fire interval 0.11 s: %d shots in 0.7 s of holding fire" % shots)
	TestLib.check(p.ammo == 30 - shots, "ammo counts down: %d rounds left after %d shots" % [p.ammo, shots])
	TestLib.check(fired[0] == shots, "the 'fired' signal is emitted once per shot (%d / %d)" % [fired[0], shots])
	p.fired.disconnect(cb)
	Input.action_press(&"reload")
	await e.frames(3)
	Input.action_release(&"reload")
	TestLib.check(p.reloading and p.ammo < 30, "reload action starts the reload; the magazine is not refilled instantly")
	var mid_shots := p.weapon.shots_fired
	Input.action_press(&"fire")
	await e.secs(0.5)
	Input.action_release(&"fire")
	TestLib.check(p.reloading and p.weapon.shots_fired == mid_shots, "cannot fire while reloading")
	await e.secs(0.6)
	TestLib.check(p.reloading, "still reloading after about 1.2 s")
	await e.secs(0.3)
	TestLib.check(not p.reloading and p.ammo == 30, "reload completes after 1.3 s with 30 rounds (ammo %d)" % p.ammo)


func _hitscan() -> void:
	# a dummy with a collider on the enemy layer, 7 m ahead
	var d := Fixture.add_dummy(e.root, Vector3(-23.0, 0.0, 4.0), 1.0, true)
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	await e.shoot_dummy(d, -0.3, 1.0)
	TestLib.check(d.hits.size() == 1, "a body shot hits the dummy (%d hits)" % d.hits.size())
	TestLib.check(d.hits.size() == 1 and absf(d.hits[0].x - 14.0) < 0.001 and d.hits[0].y == 0.0, "body shot deals 14 damage, no crit")
	TestLib.check(p.last_hit_time > PlayerUtil.now() - 0.6 and not p.last_hit_kill and not p.last_hit_crit, "last_hit_time is fresh, no kill, no crit")
	p.weapon.reset()
	await e.shoot_dummy(d, 0.7, 1.0)
	TestLib.check(d.hits.size() == 2 and absf(d.hits[1].x - 30.0) < 0.001 and d.hits[1].y == 1.0, "a hit in the upper part of the target is a crit for 30 (%s)" % str(d.hits))
	TestLib.check(p.last_hit_crit, "last_hit_crit is set on a crit")
	d.hp = 10.0
	p.weapon.reset()
	await e.shoot_dummy(d, -0.3, 1.0)
	TestLib.check(d.dead and p.last_hit_kill, "the killing shot sets last_hit_kill")
	d.queue_free()
	# a collider-less target exposing center() / radius: the prototype's ray-sphere test
	var g := Fixture.add_dummy(e.root, Vector3(-23.0, 0.0, 4.0), 1.0, false)
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	await e.shoot_dummy(g, -0.3, 1.0)
	TestLib.check(g.hits.size() == 1 and absf(g.hits[0].x - 14.0) < 0.001, "collider-less targets are hit through center() / radius, 14 damage")
	p.weapon.reset()
	await e.shoot_dummy(g, 0.7, 1.0)
	TestLib.check(g.hits.size() == 2 and absf(g.hits[1].x - 30.0) < 0.001, "crit on a collider-less target too (30)")
	g.queue_free()
	await e.frames(2)


func _spread() -> void:
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	await e.secs(0.2)
	var idle := p.spread
	Input.action_press(&"fire")
	await e.secs(0.25)
	var mid := p.spread
	await e.secs(0.4)
	var late := p.spread
	Input.action_release(&"fire")
	TestLib.check(mid > idle + 0.002 and late > mid, "spread grows while firing (%.4f -> %.4f -> %.4f rad)" % [idle, mid, late])
	TestLib.check(late <= 0.014 + 0.03 + 0.001, "...and is capped (%.4f)" % late)


func _health() -> void:
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	var hurts := []
	var cb := func(a: float) -> void: hurts.append(a)
	p.hurt.connect(cb)
	p.damage(30.0, Vector3(5.0, 1.0, 5.0))
	p.hurt.disconnect(cb)
	TestLib.check(absf(p.hp - 70.0) < 0.001, "damage(30) reduces hp to 70 (hp %.2f)" % p.hp)
	TestLib.check(hurts.size() == 1 and absf(hurts[0] - 30.0) < 0.001, "the 'hurt' signal carries the amount")
	await e.secs(1.0)
	TestLib.check(absf(p.hp - 70.0) < 0.001, "no regeneration in the first second after a hit (hp %.2f, since_hurt %.2f)" % [p.hp, p.since_hurt])
	TestLib.check(absf(p.since_hurt - 1.0) < 0.1, "the regeneration timer counts real time (%.2f s)" % p.since_hurt)
	p.since_hurt = 4.8                       # skip ahead to just before the 5 s mark and watch the boundary in real time
	await e.secs(0.1)
	TestLib.check(absf(p.hp - 70.0) < 0.001, "still paused at 4.9 s (hp %.2f)" % p.hp)
	await e.secs(0.5)
	var regen := p.hp - 70.0
	TestLib.check(regen > 3.0 and regen < 9.0, "regeneration resumes after 5 s at 14 hp/s (+%.1f hp in the 0.4 s after the mark)" % regen)
	p.damage(10.0)
	var after := p.hp
	await e.secs(0.5)
	TestLib.check(absf(p.hp - after) < 0.001, "a new hit restarts the 5 s pause")


func _death_and_invulnerability() -> void:
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	e.died_count = 0
	p.hp = 20.0
	p.damage(15.0)
	TestLib.check(e.died_count == 0 and Game.state == &"play", "survives a hit that leaves 5 hp")
	p.damage(50.0)
	TestLib.check(p.hp == 0.0 and Game.state == &"dead", "hp reaches 0 and Game.die() puts the game in the dead state")
	TestLib.check(e.died_count == 1, "Game.die() ran exactly once (player_died emitted %d times)" % e.died_count)
	p.damage(50.0)
	Game.state = &"play"                     # even if something forces play back without a respawn
	p.damage(50.0)
	await e.frames(3)
	TestLib.check(e.died_count == 1, "a dead player cannot die twice (%d)" % e.died_count)
	# respawn: 1.5 s of invulnerability
	Game.do_respawn()
	await e.frames(3)
	TestLib.check(Game.state == &"play" and p.hp == 100.0 and p.invuln > 1.3, "do_respawn restores a living player (invulnerability %.2f s left)" % p.invuln)
	p.damage(40.0)
	await e.secs(1.0)
	p.damage(40.0)
	TestLib.check(p.hp == 100.0, "damage is ignored for the first 1.5 s (hp %.1f, %.2f s left)" % [p.hp, p.invuln])
	await e.secs(0.6)
	TestLib.check(p.invuln == 0.0, "the invulnerability window ends after 1.5 s")
	p.damage(40.0)
	TestLib.check(absf(p.hp - 60.0) < 0.001, "damage works again afterwards (hp %.1f)" % p.hp)


func _lifecycle() -> void:
	for sig_name: String in ["new_game", "respawn", "next_sector"]:
		await e.prep(Vector3(25.0, 0.0, -20.0))
		p.hp = 33.0
		p.energy = 12.0
		p.ammo = 3
		p.weapon.start_reload()
		Signal(Game, sig_name).emit()
		await e.frames(3)
		TestLib.check(p.hp == 100.0 and p.energy == 100.0 and p.ammo == 30 and not p.reloading, "%s: full hp, energy and ammo" % sig_name)
		TestLib.check(absf(p.global_position.x - Game.SPAWN.x) < 0.05 and absf(p.global_position.z - Game.SPAWN.z) < 0.05, "%s: back at the spawn point (%s)" % [sig_name, str(p.global_position)])
		TestLib.check(p.invuln > 1.3, "%s: 1.5 s invulnerability (%.2f)" % [sig_name, p.invuln])


func _vehicle_mode() -> void:
	var car := Fixture.add_vehicle(e.root, Vector3(-20.0, 0.0, 24.0), Vector3(1.9, 1.3, 4.5), false)
	await e.prep(Vector3(-30.0, 0.0, 24.0))
	p.vehicle = car
	await e.secs(0.3)
	TestLib.check(p.vehicle == car and not p.body.visible, "vehicle mode hides the body")
	TestLib.check(p.camera_rig.mode == &"vehicle" and p.camera_rig.follow_target == car, "the camera rig follows the vehicle in vehicle mode")
	TestLib.check(Vector2(p.global_position.x, p.global_position.z).distance_to(Vector2(-20.0, 24.0)) < 0.05, "the player follows the vehicle position (%s)" % str(p.global_position))
	car.global_position = Vector3(5.0, 0.0, 24.0)
	await e.frames(3)
	TestLib.check(Vector2(p.global_position.x, p.global_position.z).distance_to(Vector2(5.0, 24.0)) < 0.05, "...and keeps following when the vehicle moves")
	var hp := p.hp
	p.damage(10.0)
	TestLib.check(car.hits.size() == 1 and absf(car.hits[0] - 6.0) < 0.001 and p.hp == hp, "damage while driving goes to the vehicle at 60 %% and spares the driver (%s)" % str(car.hits))
	var shots := p.weapon.shots_fired
	Input.action_press(&"fire")
	await e.secs(0.2)
	Input.action_release(&"fire")
	TestLib.check(p.weapon.shots_fired == shots, "the rifle is not fired from inside a vehicle")
	p.vehicle = null
	await e.frames(3)
	TestLib.check(p.body.visible and p.camera_rig.mode == &"foot" and p.camera_rig.follow_target == p, "leaving the vehicle shows the body and returns the camera to foot mode")
	car.queue_free()


func _teleport_and_aim() -> void:
	var rig := p.camera_rig
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	p.teleport_to(Vector3(30.0, 0.0, 30.0))
	TestLib.check(p.global_position.is_equal_approx(Vector3(30.0, 0.0, 30.0)) and p.velocity == Vector3.ZERO, "teleport_to moves the player and clears the velocity")
	TestLib.check(rig.get_pivot_position().distance_to(Vector3(30.0, 1.55, 30.0)) < 0.05, "the camera pivot is on the player right after the teleport (no streak)")
	await e.secs(0.4)
	TestLib.check(p.is_on_floor() and p.global_position.distance_to(Vector3(30.0, 0.0, 30.0)) < 0.2, "the player stands at the teleport target")
	# get_aim looking at the wall
	await e.prep(Vector3(-20.0, 0.0, 4.0), -PI * 0.5, 0.0)
	var aim := p.get_aim()
	TestLib.check(aim.has("origin") and aim.has("dir") and aim.has("hit"), "get_aim() returns origin, dir and hit")
	var dir: Vector3 = aim["dir"]
	TestLib.check(absf(dir.length() - 1.0) < 0.001 and dir.dot(-rig.camera.global_basis.z) > 0.9999 and dir.x > 0.9, "aim dir is the unit forward of the camera (%s)" % str(dir))
	TestLib.check((aim["origin"] as Vector3).is_equal_approx(rig.camera.global_position), "aim origin is the camera position")
	TestLib.check(absf((aim["hit"] as Vector3).x - Env.WALL_FACE_X) < 0.08, "aim hit is the wall face at x = -10.5 (got %.2f)" % (aim["hit"] as Vector3).x)
	rig.reset_view(-PI * 0.5, 0.6)
	await e.frames(2)
	var sky := p.get_aim()
	TestLib.check((sky["hit"] as Vector3).distance_to(sky["origin"] as Vector3) > 200.0, "nothing in the way: hit is a far point")
