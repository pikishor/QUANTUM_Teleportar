extends RefCounted
## Player module tests, part 2 (headless): the finer points of feel and robustness.
## Coyote time and jump buffering, curbs (step-up), camera (hip / ADS / sprint FOV, shoulder, pull-in against walls, interpolation, look API,
## kick compensation), rifle details (tap, empty magazine, occlusion, bullet holes, pooling, muzzle-flash lights), spread and recoil, health extras,
## the vehicle chase camera, the body (facing, leg swing, primitive fallback, death pose), get_aim variants and the cinematic cameras.
## Run: tools/test.sh tests/test_player_polish.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")

var e := Env.new()
var p: Player


func run(host: Node) -> void:
	var real_quantum_path := Player.quantum_path
	Player.quantum_path = "res://tests/player_dummy_quantum.gd"          # exercise the optional Quantum child with a stand-in
	await e.setup(host)
	Player.quantum_path = real_quantum_path
	p = e.p
	TestLib.check(p.quantum != null and p.quantum.get_parent() == p and p.quantum.get("player_at_ready") == p, "the optional Quantum child is added in _ready and exposed as player.quantum")
	await _coyote_and_buffer()
	await _curb_and_block()
	await _camera()
	await _look_api()
	await _rifle_details()
	await _occlusion_effects_pools()
	await _spread_and_recoil()
	await _health_extras()
	await _vehicle_chase()
	await _body()
	await _aim_variants()
	await _cinematic_cameras()
	await e.teardown()


func _coyote_and_buffer() -> void:
	# coyote time: walk off the edge of a 3 m platform and press jump a tick later
	var plat := Fixture.add_box(e.root, Vector3(-40.0, 1.5, -30.0), Vector3(6.0, 3.0, 6.0))      # top at y = 3, x in [-43, -37]
	await e.prep(Vector3(-41.0, 3.0, -30.0))
	Input.action_press(&"move_forward")
	var guard := 0
	while p.is_on_floor() and guard < 120:
		await e.frames(1)
		guard += 1
	TestLib.check(not p.is_on_floor(), "walked off the platform edge")
	var y_leave := p.global_position.y
	Input.action_press(&"jump")
	await e.frames(4)
	TestLib.check(p.velocity.y > 3.0 or p.global_position.y > y_leave + 0.05, "coyote time: jump still works just after leaving the edge (vy %.2f)" % p.velocity.y)
	Input.action_release(&"jump")
	Input.action_release(&"move_forward")
	# a late press (0.25 s after leaving the edge) must not jump
	await e.prep(Vector3(-41.0, 3.0, -30.0))
	Input.action_press(&"move_forward")
	guard = 0
	while p.is_on_floor() and guard < 120:
		await e.frames(1)
		guard += 1
	Input.action_release(&"move_forward")
	await e.secs(0.25)
	Input.action_press(&"jump")
	await e.frames(3)
	TestLib.check(p.velocity.y < 0.0, "no air jump after the coyote window (vy %.2f)" % p.velocity.y)
	Input.action_release(&"jump")
	plat.queue_free()
	# jump buffering: a press about 0.1 s before landing jumps on touchdown
	await e.prep(Vector3(-30.0, 0.8, 4.0), -PI * 0.5, -0.12, 0)
	guard = 0
	while p.global_position.y > 0.45 and guard < 120:
		await e.frames(1)
		guard += 1
	Input.action_press(&"jump")
	await e.frames(2)
	Input.action_release(&"jump")
	await e.frames(14)
	TestLib.check(p.global_position.y > 0.3, "jump buffering: a press about 0.1 s before landing jumps on touchdown (y %.2f)" % p.global_position.y)
	# ... but a press long before landing is forgotten
	await e.prep(Vector3(-30.0, 0.8, 4.0), -PI * 0.5, -0.12, 0)
	Input.action_press(&"jump")
	await e.frames(2)
	Input.action_release(&"jump")
	await e.secs(0.6)
	TestLib.check(p.is_on_floor() and p.global_position.y < 0.05, "an early jump press (outside the 0.12 s buffer) is forgotten (y %.2f)" % p.global_position.y)
	# teleporting does not leave the stale floor flag that would allow a jump in mid-air
	await e.prep(Vector3(-30.0, 5.0, 4.0), -PI * 0.5, -0.12, 0)
	Input.action_press(&"jump")
	await e.frames(3)
	Input.action_release(&"jump")
	TestLib.check(p.velocity.y < 0.0, "no jump in mid-air right after a teleport (vy %.2f)" % p.velocity.y)
	await e.secs(0.5)


func _curb_and_block() -> void:
	var curb := Fixture.add_box(e.root, Vector3(-26.0, 0.075, 30.0), Vector3(1.2, 0.15, 12.0))
	var block := Fixture.add_box(e.root, Vector3(-21.0, 0.35, 30.0), Vector3(2.0, 0.7, 12.0))     # x in [-22, -20]
	await e.prep(Vector3(-29.0, 0.0, 30.0))
	Input.action_press(&"move_forward")
	var max_y := 0.0
	for i in 40:
		await e.frames(1)
		max_y = maxf(max_y, p.global_position.y)
	TestLib.check(p.global_position.x > -26.4, "walks onto a 15 cm curb instead of stopping at it (x = %.2f, curb face at -26.6)" % p.global_position.x)
	TestLib.check(max_y > 0.1 and max_y < 0.3, "is lifted onto the curb, not launched (max y %.2f)" % max_y)
	await e.secs(0.5)
	TestLib.check(p.global_position.x > -24.8 and p.global_position.y < 0.02, "...and carries on over it to the street (x = %.2f, y = %.3f)" % [p.global_position.x, p.global_position.y])
	await e.secs(0.5)
	TestLib.check(p.global_position.x > -22.5 and p.global_position.x < -22.2, "a 70 cm block is not climbed (x = %.2f, face at -22)" % p.global_position.x)
	Input.action_release(&"move_forward")
	# stepping down off the curb keeps contact with the ground
	await e.prep(Vector3(-26.0, 0.15, 30.0), PI * 0.5)
	Input.action_press(&"move_forward")
	var min_y := 9.0
	var air_max := 0.0
	for i in 30:
		await e.frames(1)
		min_y = minf(min_y, p.global_position.y)
		air_max = maxf(air_max, p.air_time)
	Input.action_release(&"move_forward")
	TestLib.check(min_y > -0.01 and p.global_position.y < 0.01 and p.is_on_floor(), "walking down a curb ends on the street without sinking or bouncing (y %.3f)" % p.global_position.y)
	TestLib.check(air_max < 0.2, "rolling off the curb is a short slide, not a fall (%.2f s without floor contact)" % air_max)
	curb.queue_free()
	block.queue_free()
	# sliding along a wall: walk diagonally into it
	await e.prep(Vector3(-14.0, 0.0, 0.0), -PI * 0.25)
	Input.action_press(&"move_forward")
	await e.secs(0.85)
	Input.action_release(&"move_forward")
	TestLib.check(p.global_position.x < -10.5 and p.global_position.z < -0.5, "walking diagonally into the wall slides along it (pos %s)" % str(p.global_position))


func _camera() -> void:
	var rig := p.camera_rig
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	await e.secs(0.6)
	TestLib.check(absf(rig.camera.fov - 72.0) < 0.6, "hip FOV is 72 (got %.2f)" % rig.camera.fov)
	var pivot := rig.get_pivot_position()
	var hip_dist := rig.camera.global_position.distance_to(pivot)
	TestLib.check(absf(hip_dist - sqrt(0.8 * 0.8 + 3.6 * 3.6)) < 0.12, "hip camera sits 3.6 m behind and 0.8 m beside the pivot (distance %.2f)" % hip_dist)
	var to_cam := rig.camera.global_position - pivot
	TestLib.check(to_cam.dot(rig.camera.global_basis.x) > 0.6 and to_cam.dot(rig.camera.global_basis.z) > 3.0, "over the right shoulder: camera right of and behind the head")
	TestLib.check(absf(pivot.y - 1.55) < 0.05, "pivot at 1.55 m eye height (%.2f)" % pivot.y)
	Input.action_press(&"aim")
	await e.secs(0.6)
	TestLib.check(absf(rig.camera.fov - 50.0) < 0.8, "ADS FOV settles at 50 (got %.2f)" % rig.camera.fov)
	var ads_dist := rig.camera.global_position.distance_to(rig.get_pivot_position())
	TestLib.check(absf(ads_dist - sqrt(0.55 * 0.55 + 2.0 * 2.0)) < 0.12, "ADS camera comes in to 2.0 m / 0.55 m (distance %.2f)" % ads_dist)
	Input.action_release(&"aim")
	var fov_prev := rig.camera.fov
	var max_step := 0.0
	var mid_seen := false
	for i in 30:
		await e.frames(1)
		max_step = maxf(max_step, absf(rig.camera.fov - fov_prev))
		fov_prev = rig.camera.fov
		mid_seen = mid_seen or (rig.camera.fov > 56.0 and rig.camera.fov < 66.0)
	TestLib.check(mid_seen and max_step < 5.0, "the ADS release is animated (max FOV step %.2f per tick)" % max_step)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await e.secs(0.8)
	TestLib.check(rig.camera.fov > 76.0, "sprinting opens the FOV toward 78 (got %.2f)" % rig.camera.fov)
	Fixture.release_inputs()
	# wall pull-in: the wall stands between the camera and the player
	await e.prep(Vector3(-8.0, 0.0, 4.0))
	TestLib.check(rig.camera.global_position.x > -9.5, "the camera is pulled in against the wall instead of passing through it (cam x %.2f)" % rig.camera.global_position.x)
	TestLib.check(rig.is_obstructed() and rig.camera.global_position.distance_to(rig.get_pivot_position()) < 2.4, "the rig reports it is obstructed, distance %.2f" % rig.camera.global_position.distance_to(rig.get_pivot_position()))
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	TestLib.check(not rig.is_obstructed(), "open ground: not obstructed")
	# interpolation: the camera moves on every rendered frame while running
	Input.action_press(&"move_forward")
	await e.secs(0.3)
	var last_x := rig.camera.global_position.x
	var stalled := 0
	for i in 60:
		await e.host.get_tree().process_frame
		var xx := rig.camera.global_position.x
		if absf(xx - last_x) < 1e-6:
			stalled += 1
		last_x = xx
	Input.action_release(&"move_forward")
	TestLib.check(stalled <= 4, "the camera moves every rendered frame while running (%d stalled of 60)" % stalled)
	TestLib.check(rig.top_level and p.body.top_level, "rig and body are top-level: rendered from the interpolated physics state")
	# landing dips the camera
	await e.prep(Vector3(-30.0, 8.0, 4.0), -PI * 0.5, -0.12, 0)
	var y_min := 99.0
	var base_h := 0.0
	for i in 70:
		await e.frames(1)
		if p.is_on_floor() and base_h == 0.0:
			base_h = rig.camera.global_position.y
		if base_h > 0.0:
			y_min = minf(y_min, rig.camera.global_position.y)
	await e.secs(0.15)
	TestLib.check(base_h > 0.0 and y_min < base_h - 0.03, "a hard landing dips the camera (%.3f below the landing height)" % (base_h - y_min))


func _look_api() -> void:
	var rig := p.camera_rig
	await e.prep(Vector3(-30.0, 0.0, 4.0), 0.0, 0.0)
	rig.add_look(0.1, 0.0)
	TestLib.check(absf(rig.yaw - (-0.1)) < 1e-5, "add_look(+yaw) turns the view right (yaw decreases): %.3f" % rig.yaw)
	rig.add_look(0.0, 0.2)
	TestLib.check(absf(rig.pitch - (-0.2)) < 1e-5, "add_look(+pitch) tilts the view down: %.3f" % rig.pitch)
	rig.add_look(0.0, -9.0)
	TestLib.check(absf(rig.pitch - 0.85) < 1e-5, "pitch is clamped at +0.85 looking up (got %.3f)" % rig.pitch)
	rig.add_look(0.0, 9.0)
	TestLib.check(absf(rig.pitch - (-1.0)) < 1e-5, "pitch is clamped at -1.0 looking down (got %.3f)" % rig.pitch)
	TestLib.check(rig.free_look > 1.0, "manual look starts the free-look timer")
	rig.reset_view(0.0, 0.0)
	rig.kick(0.1, 0.0)
	TestLib.check(absf(rig.recoil_pitch - 0.1) < 1e-6, "kick adds recoil pitch")
	rig.add_look(0.0, 0.04)
	TestLib.check(absf(rig.recoil_pitch - 0.06) < 1e-5 and absf(rig.pitch) < 1e-6, "pulling down against the kick consumes it (recoil %.3f, pitch %.3f)" % [rig.recoil_pitch, rig.pitch])
	await e.secs(1.1)
	TestLib.check(rig.recoil_pitch < 0.004, "the kick settles by itself (%.4f)" % rig.recoil_pitch)
	# the movement direction follows the look yaw: yaw 0 looks along -Z
	rig.reset_view(0.0, 0.0)
	Input.action_press(&"move_forward")
	await e.secs(0.5)
	Input.action_release(&"move_forward")
	TestLib.check(p.velocity.z < -3.0 and absf(p.velocity.x) < 0.5, "yaw 0 walks along -Z (v %s)" % str(p.velocity))
	# move_right strafes to the right of the look direction, and diagonals are not faster
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	Input.action_press(&"move_forward")
	Input.action_press(&"move_right")
	await e.secs(0.5)
	TestLib.check(absf(e.flat_speed() - 6.2) < 0.2, "diagonal movement is not faster than straight (%.2f m/s)" % e.flat_speed())
	TestLib.check(p.velocity.z > 2.0 and p.velocity.x > 2.0, "move_right strafes right of the look direction (+Z when looking along +X)")
	Fixture.release_inputs()
	# smooth acceleration: two ticks after a key press the player is far from full speed
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	Input.action_press(&"move_forward")
	await e.frames(2)
	TestLib.check(e.flat_speed() > 0.3 and e.flat_speed() < 5.0, "acceleration is smooth: %.2f m/s two ticks after the key press" % e.flat_speed())
	Input.action_release(&"move_forward")


func _rifle_details() -> void:
	var w := p.weapon
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	Input.action_press(&"fire")
	await e.frames(2)
	Input.action_release(&"fire")
	await e.secs(0.2)
	TestLib.check(p.ammo == 29, "a short tap fires exactly one round (ammo %d)" % p.ammo)
	Input.action_press(&"reload")
	await e.frames(3)
	Input.action_release(&"reload")
	await e.secs(0.1)
	TestLib.check(p.reloading, "reload with one round missing")
	await e.secs(1.4)
	Input.action_press(&"reload")
	await e.frames(3)
	Input.action_release(&"reload")
	TestLib.check(not p.reloading and p.ammo == 30, "no reload with a full magazine")
	# an empty magazine reloads by itself on the next trigger pull
	p.ammo = 2
	w.shots_fired = 0
	Input.action_press(&"fire")
	await e.secs(0.5)
	TestLib.check(w.shots_fired == 2 and p.reloading and p.ammo == 0, "an empty magazine auto-reloads on the next trigger pull (shots %d, ammo %d)" % [w.shots_fired, p.ammo])
	await e.secs(1.3)
	Input.action_release(&"fire")
	TestLib.check(w.shots_fired > 2 and p.ammo > 0, "firing resumes after the automatic reload (shots %d, ammo %d)" % [w.shots_fired, p.ammo])
	w.reset()
	# vehicles take 9 damage per hit and never count as kills
	var car := Fixture.add_vehicle(e.root, Vector3(-23.0, 0.0, 4.0), Vector3(2.0, 1.4, 4.5), true)
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	p.camera_rig.aim_at(car.global_position + Vector3(0.0, 0.8, 0.0))
	await e.frames(1)
	Input.action_press(&"fire")
	await e.frames(2)
	Input.action_release(&"fire")
	await e.secs(0.15)
	TestLib.check(car.hits.size() == 1 and absf(car.hits[0] - 9.0) < 0.001 and not p.last_hit_kill, "a vehicle takes 9 damage per hit and a hit on it is never a kill (%s)" % str(car.hits))
	car.queue_free()
	# a dead target no longer blocks or takes hits: bullets pass through
	var d := Fixture.add_dummy(e.root, Vector3(-23.0, 0.0, 4.0), 1.0, true)
	d.hp = 5.0
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	await e.shoot_dummy(d, -0.3, 1.0)
	var hits_after: int = d.hits.size()
	var kills := [0]
	var cb := func(kill: bool, _crit: bool) -> void:
		if kill:
			kills[0] += 1
	p.hit_confirmed.connect(cb)
	w.reset()
	await e.shoot_dummy(d, -0.3, 1.0)
	p.hit_confirmed.disconnect(cb)
	TestLib.check(d.dead and d.hits.size() == hits_after and kills[0] == 0, "a dead target takes no further hits (%d)" % d.hits.size())
	d.queue_free()
	# a miss does not hit
	var g := Fixture.add_dummy(e.root, Vector3(-23.0, 0.0, 4.0), 1.0, false)
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	p.camera_rig.aim_at(g.center() + Vector3(0.0, 0.0, 5.0))
	await e.frames(1)
	Input.action_press(&"fire")
	await e.frames(2)
	Input.action_release(&"fire")
	await e.secs(0.1)
	TestLib.check(g.hits.is_empty(), "a shot 5 m wide of the target misses")
	g.queue_free()
	w.reset()


func _occlusion_effects_pools() -> void:
	var w := p.weapon
	# a dummy behind the wall cannot be shot; the wall takes the bullets and shows holes
	var d := Fixture.add_dummy(e.root, Vector3(-4.0, 0.0, 4.0), 1.0, true)
	await e.prep(Vector3(-16.0, 0.0, 4.0))
	p.camera_rig.aim_at(d.center())
	await e.frames(1)
	p.decals.clear()
	Input.action_press(&"fire")
	await e.secs(0.5)
	TestLib.check(d.hits.is_empty(), "a target behind the wall is not hit (%d hits)" % d.hits.size())
	TestLib.check(p.decals.active_count() >= 3, "bullet holes are added where shots land on the world (%d decals)" % p.decals.active_count())
	d.free()
	# pools: sustained fire creates no nodes
	var nodes_before := e.host.get_tree().get_node_count()
	await e.secs(0.8)
	Input.action_release(&"fire")
	var nodes_after := e.host.get_tree().get_node_count()
	TestLib.check(nodes_after == nodes_before, "firing creates no nodes: flash, tracers, sparks and decals are pooled (%d -> %d)" % [nodes_before, nodes_after])
	TestLib.check(p.decals.active_count() <= ImpactDecals.CAPACITY, "the decal ring never exceeds its capacity (%d)" % p.decals.active_count())
	# the decal ring recycles the oldest hole
	p.decals.clear()
	for i in ImpactDecals.CAPACITY + 10:
		p.decals.add(Vector3(-10.5, 1.0 + i * 0.01, 4.0), Vector3(-1.0, 0.0, 0.0))
	TestLib.check(p.decals.active_count() == ImpactDecals.CAPACITY, "the decal ring recycles the oldest hole when full (%d)" % p.decals.active_count())
	p.decals.clear()
	TestLib.check(p.decals.active_count() == 0, "decals can be cleared")
	# muzzle flash lights pulse and switch off again
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	var lights: Array[OmniLight3D] = []
	for c in p.body.muzzle.get_children():
		if c is OmniLight3D:
			lights.append(c)
	TestLib.check(lights.size() >= 2, "a small pool of muzzle-flash OmniLight3D exists (%d)" % lights.size())
	Input.action_press(&"fire")
	await e.frames(1)
	Input.action_release(&"fire")
	var lit := false
	for l in lights:
		lit = lit or (l.visible and l.light_energy > 0.1)
	TestLib.check(lit, "a muzzle-flash light pulses on the shot")
	await e.secs(0.25)
	var still := false
	for l in lights:
		still = still or l.visible
	TestLib.check(not still, "the flash lights switch off again")
	w.reset()


func _spread_and_recoil() -> void:
	var rig := p.camera_rig
	await e.prep(Vector3(-30.0, 0.0, 4.0), -PI * 0.5, 0.0)
	await e.secs(0.1)
	var idle := p.spread
	TestLib.check(absf(idle - 0.014) < 0.001, "hip spread at rest is 0.014 rad (%.4f)" % idle)
	Input.action_press(&"aim")
	await e.secs(0.2)
	TestLib.check(absf(p.spread - 0.004) < 0.001, "aimed spread at rest is 0.004 rad (%.4f)" % p.spread)
	Input.action_release(&"aim")
	Input.action_press(&"move_forward")
	await e.secs(0.35)
	TestLib.check(p.spread > idle + 0.007, "moving adds spread (%.4f)" % p.spread)
	Input.action_release(&"move_forward")
	await e.secs(0.4)
	var pitch0 := rig.pitch
	Input.action_press(&"fire")
	await e.secs(0.65)
	var kicked := rig.recoil_pitch
	TestLib.check(kicked > 0.03, "sustained fire kicks the view up (recoil %.3f rad)" % kicked)
	TestLib.check(rig.get_aim_pitch() > pitch0 + 0.03, "the aim itself climbs with the kick (%.3f -> %.3f)" % [pitch0, rig.get_aim_pitch()])
	TestLib.check(p.spread > idle + 0.01, "spread has grown during the burst (%.4f)" % p.spread)
	Input.action_release(&"fire")
	await e.secs(1.0)
	TestLib.check(p.spread < idle + 0.003, "spread recovers after the burst (%.4f)" % p.spread)
	TestLib.check(rig.recoil_pitch < 0.004 and absf(rig.pitch - pitch0) < 0.001, "the view settles back to where it was aimed (recoil %.4f)" % rig.recoil_pitch)
	# recoil is weaker when aiming
	p.weapon.reset()
	rig.reset_view(-PI * 0.5, 0.0)
	Input.action_press(&"aim")
	await e.secs(0.3)
	Input.action_press(&"fire")
	await e.secs(0.65)
	var kick_ads := rig.recoil_pitch
	Input.action_release(&"fire")
	Input.action_release(&"aim")
	TestLib.check(kick_ads < kicked, "recoil is lower while aiming (%.3f < %.3f)" % [kick_ads, kicked])
	p.weapon.reset()


func _health_extras() -> void:
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	p.hp = 50.0
	p.heal(30.0)
	TestLib.check(absf(p.hp - 80.0) < 0.001, "heal(30) adds 30 hp")
	p.heal(500.0)
	TestLib.check(absf(p.hp - 100.0) < 0.001, "heal is capped at max_hp")
	p.hp = 97.0
	await e.secs(0.4)
	TestLib.check(absf(p.hp - 100.0) < 0.001, "regeneration stops at max_hp (%.2f)" % p.hp)
	p.energy = 10.0
	p.add_energy(35.0)
	TestLib.check(absf(p.energy - 45.0) < 0.001, "add_energy(35) adds 35")
	p.add_energy(999.0)
	TestLib.check(absf(p.energy - 100.0) < 0.001, "add_energy is capped at max_energy")
	p.add_energy(-250.0)
	TestLib.check(p.energy == 0.0, "energy never goes below 0")
	await e.secs(0.5)
	TestLib.check(absf(p.energy - 4.0) < 0.8, "energy regenerates at 8/s on foot (%.2f after 0.5 s)" % p.energy)
	p.damage(-5.0)
	p.damage(0.0)
	TestLib.check(absf(p.hp - 100.0) < 0.001, "zero or negative damage is ignored")
	Game.state = &"paused"
	p.damage(10.0)
	Game.state = &"play"
	TestLib.check(absf(p.hp - 100.0) < 0.001, "no damage while paused")
	# the Quantum superposition speed boost (+30 %), both readings of the value
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	p.speed_boost = 1.3
	Input.action_press(&"move_forward")
	await e.secs(0.5)
	TestLib.check(absf(e.flat_speed() - 6.2 * 1.3) < 0.2, "speed_boost 1.3 gives +30 %% (%.2f m/s)" % e.flat_speed())
	p.speed_boost = 0.3
	await e.secs(0.3)
	TestLib.check(absf(e.flat_speed() - 6.2 * 1.3) < 0.2, "speed_boost 0.3 is read as +30 %% too (%.2f m/s)" % e.flat_speed())
	Fixture.release_inputs()
	p.speed_boost = 1.0
	# a lifecycle reset while driving puts the player back on foot
	var car := Fixture.add_vehicle(e.root, Vector3(0.0, 0.0, 40.0))
	p.vehicle = car
	await e.frames(3)
	Game.respawn.emit()
	await e.frames(3)
	TestLib.check(p.vehicle == null and p.body.visible and p.camera_rig.mode == &"foot", "a respawn ends vehicle mode")
	car.queue_free()


func _vehicle_chase() -> void:
	var rig := p.camera_rig
	var car := Fixture.add_vehicle(e.root, Vector3(-20.0, 0.0, 24.0), Vector3(1.9, 1.3, 4.5), false)
	await e.prep(Vector3(-30.0, 0.0, 24.0))
	p.energy = 0.0
	p.vehicle = car
	await e.frames(3)
	TestLib.check(p.collision_layer == 0 and p.collision_mask == 0, "the player collider is switched off in vehicle mode")
	TestLib.check(p.chest_position().distance_to(Vector3(-20.0, 1.1, 24.0)) < 0.05, "chest_position() is the cabin of the vehicle (%s)" % str(p.chest_position()))
	var e0 := p.energy
	await e.secs(0.5)
	TestLib.check(absf((p.energy - e0) - 1.5) < 0.4, "energy regenerates at 3/s while driving (+%.2f in 0.5 s)" % (p.energy - e0))
	await e.secs(0.2)
	var cam_d := rig.camera.global_position.distance_to(rig.get_pivot_position())
	TestLib.check(absf(cam_d - 7.5) < 0.4, "chase camera sits 7.5 m from its pivot (%.2f)" % cam_d)
	TestLib.check(absf(rig.get_pivot_position().y - 1.6) < 0.05, "chase pivot is 1.6 m above the vehicle origin")
	car.rotation.y = 1.0
	car.heading = 1.0
	car.speed = 12.0
	await e.secs(1.3)
	TestLib.check(absf(angle_difference(rig.yaw, 1.0)) < 0.1, "the chase camera swings behind the vehicle heading (yaw %.2f, heading 1.0)" % rig.yaw)
	var fwd_cam := -rig.camera.global_basis.z
	var fwd_car := -car.global_basis.z
	TestLib.check(Vector2(fwd_cam.x, fwd_cam.z).normalized().dot(Vector2(fwd_car.x, fwd_car.z).normalized()) > 0.97, "the camera looks along the vehicle's forward direction")
	TestLib.check(rig.camera.fov > 77.0, "speed opens the FOV in the chase camera (%.1f at 12 m/s)" % rig.camera.fov)
	rig.add_look(1.0, 0.0)
	var yaw_look := rig.yaw
	await e.secs(0.6)
	TestLib.check(absf(angle_difference(rig.yaw, yaw_look)) < 0.02, "manual look holds the chase camera still (free look)")
	await e.secs(1.6)
	TestLib.check(absf(angle_difference(rig.yaw, 1.0)) < 0.15, "...and it eases back once the player stops looking (yaw %.2f)" % rig.yaw)
	# the player's own damage and firing rules inside the vehicle were checked in part 1; here the exit position
	p.vehicle = null
	p.global_position = Vector3(8.0, 0.0, 24.0)           # the vehicle module places the player next to the car
	await e.secs(0.3)
	TestLib.check(p.is_on_floor() and p.global_position.distance_to(Vector3(8.0, 0.0, 24.0)) < 0.1, "the player stands where the vehicle module put it")
	p.energy = 0.0
	await e.secs(0.4)
	TestLib.check(absf(p.energy - 3.2) < 0.7, "energy regenerates at 8/s again on foot (%.2f)" % p.energy)
	car.queue_free()


func _body() -> void:
	var b := p.body
	TestLib.check(b.upper != null and b.muzzle != null and b.leg_l != null and b.leg_r != null, "the body exposes upper, muzzle, leg_l and leg_r")
	TestLib.check(b.uses_model == ResourceLoader.exists("res://assets/models/player.glb"), "uses Game.load_model('player') when the model exists")
	await e.prep(Vector3(-30.0, 0.0, 4.0), 0.0, 0.0)
	p.camera_rig.add_look(-1.2, 0.0)
	await e.secs(0.6)
	TestLib.check(absf(angle_difference(p.yaw, p.camera_rig.get_aim_yaw())) < 0.06, "the body faces the aim direction (yaw %.2f vs aim %.2f)" % [p.yaw, p.camera_rig.get_aim_yaw()])
	TestLib.check(absf(angle_difference(p.rotation.y, p.yaw)) < 0.001, "the player node's rotation.y is the body yaw")
	var m := b.muzzle.global_position - p.global_position
	var fwd := Vector3(-sin(p.yaw), 0.0, -cos(p.yaw))
	TestLib.check(m.dot(fwd) > 0.7 and m.y > 1.0 and m.y < 1.6, "the muzzle is ahead of the body at rifle height (%s)" % str(m))
	var idle_angle := b.leg_l.basis.get_rotation_quaternion().get_angle()
	Input.action_press(&"move_forward")
	var max_angle := 0.0
	for i in 40:
		await e.frames(1)
		max_angle = maxf(max_angle, b.leg_l.basis.get_rotation_quaternion().get_angle())
	TestLib.check(idle_angle < 0.05, "legs are at rest when idle (%.3f rad)" % idle_angle)
	TestLib.check(max_angle > 0.3, "legs swing when running (max %.2f rad)" % max_angle)
	Fixture.release_inputs()
	await e.secs(0.6)
	TestLib.check(b.leg_l.basis.get_rotation_quaternion().get_angle() < 0.1, "legs return to rest after stopping")
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	Input.action_press(&"move_back")
	var swing_back := 0.0
	for i in 40:
		await e.frames(1)
		swing_back = maxf(swing_back, b.leg_l.basis.get_rotation_quaternion().get_angle())
	Fixture.release_inputs()
	TestLib.check(swing_back > 0.3, "legs swing when backing up as well")
	# the primitive fallback builds the same parts
	PlayerBody.force_primitive = true
	var fb := PlayerBody.new()
	e.root.add_child(fb)
	TestLib.check(not fb.uses_model and fb.upper != null and fb.muzzle != null and fb.leg_l != null and fb.leg_r != null, "primitive fallback body builds upper, muzzle and both legs")
	var tris := 0
	for mi in fb.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(si)
			if arrays[Mesh.ARRAY_INDEX] != null:
				tris += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			else:
				tris += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	TestLib.check(tris > 800 and tris < 40000, "primitive body is a real humanoid, not a handful of boxes (%d triangles)" % tris)
	TestLib.check(fb.muzzle.position.z < -0.5, "primitive muzzle points forward (-Z)")
	fb.queue_free()
	PlayerBody.force_primitive = false
	# death pose
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	b.set_dead(true)
	await e.secs(0.9)
	TestLib.check(absf(b.rotation.x) > 1.2, "the dead body has fallen over (%.2f rad)" % b.rotation.x)
	b.set_dead(false)
	await e.frames(3)
	TestLib.check(absf(b.rotation.x) < 0.01, "and stands up again on reset")


func _aim_variants() -> void:
	var rig := p.camera_rig
	await e.prep(Vector3(-20.0, 0.0, 4.0), -PI * 0.5, 0.0)
	TestLib.check(p.get_aim() == p.get_aim(), "get_aim() caches within a frame")
	rig.reset_view(-PI * 0.5, -0.5)
	await e.frames(2)
	var down := p.get_aim()
	TestLib.check(absf((down["hit"] as Vector3).y) < 0.05, "looking down the aim hit is on the floor (y %.2f)" % (down["hit"] as Vector3).y)
	# geometry between the camera and the player does not block the aim ray
	await e.prep(Vector3(-8.0, 0.0, 4.0), -PI * 0.5, 0.0)
	await e.frames(2)
	var behind := p.get_aim()
	TestLib.check((behind["hit"] as Vector3).x > -9.0, "the wall behind the player is ignored by the aim ray (hit x %.1f)" % (behind["hit"] as Vector3).x)
	TestLib.check(p.chest_position().is_equal_approx(p.global_position + Vector3(0.0, 1.2, 0.0)), "chest_position() is 1.2 m above the feet")


func _cinematic_cameras() -> void:
	var rig := p.camera_rig
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	# menu: the camera slowly orbits the player
	Game.state = &"menu"
	await e.secs(0.3)
	var y0 := rig.yaw
	var d0 := rig.camera.global_position.distance_to(rig.get_pivot_position())
	await e.secs(0.5)
	TestLib.check(absf(angle_difference(rig.yaw, y0)) > 0.02, "the title screen camera orbits the player (yaw moved %.3f)" % absf(angle_difference(rig.yaw, y0)))
	TestLib.check(d0 < 5.0 and d0 > 3.0, "...at a close, cinematic distance (%.2f m)" % d0)
	Game.state = &"play"
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	await e.secs(0.6)
	TestLib.check(absf(rig.camera.fov - 72.0) < 2.5, "back in play the camera returns to the gameplay FOV (%.1f)" % rig.camera.fov)
	# death: the camera pulls back and looks down at the fallen body
	p.hp = 1.0
	p.damage(10.0)
	await e.secs(1.0)
	TestLib.check(rig.camera.global_position.distance_to(rig.get_pivot_position()) > 4.0 and rig.get_aim_pitch() < -0.2, "the death camera pulls back and looks down at the body")
	Game.do_respawn()
	await e.secs(0.1)
	TestLib.check(Game.state == &"play" and not p.is_dead(), "and respawn returns control")
