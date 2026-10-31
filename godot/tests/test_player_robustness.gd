extends RefCounted
## Player module tests, part 3 (headless): robustness, the findings of the independent review.
##   camera squeezed against a wall (never closer than the floor, slides to the shoulder that has room), pooled particle emitters (hidden while idle, shown while
##   alive, no shadows, so finished emitters stop costing draw calls), out-of-play behaviour (a pause freezes the body, a dead or victorious body stops running and
##   slides to a stop, a player killed in mid-air falls to the ground), the corpse lying ON the floor, a vehicle that is freed while it is driven, and the chase
##   camera staying glued to a vehicle that is moved in physics ticks.
## Run: tools/test.sh tests/test_player_robustness.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")

var e := Env.new()
var p: Player


## Moves a node in the physics tick, like a vehicle module does.
class Driver extends Node:
	var car: Node3D

	func _physics_process(delta: float) -> void:
		car.call(&"drive", delta)


## Reads the position of a vehicle relative to the camera after every other _process, i.e. what the frame draws.
class Sampler extends Node:
	var rig: CameraRig
	var car: Node3D
	var zs: Array[float] = []

	func _ready() -> void:
		process_priority = 1000

	func _process(_delta: float) -> void:
		var rel := rig.camera.global_basis.inverse() * (car.global_position + Vector3(0.0, 0.65, 0.0) - rig.camera.global_position)
		zs.append(rel.z)


func run(host: Node) -> void:
	await e.setup(host)
	p = e.p
	await _wall_squeeze()
	await _particle_pools()
	await _pause_dead_and_victory()
	await _death_in_the_air_and_the_corpse()
	await _freed_vehicle()
	await _chase_lockstep()
	await e.teardown()


# ---------------------------------------------------------------------------------------------------------------------

func _bearing_of_head(rig: CameraRig) -> float:
	var local := rig.camera.global_basis.inverse() * (rig.get_pivot_position() - rig.camera.global_position)
	return atan2(local.x, -local.z)


func _wall_squeeze() -> void:
	var rig := p.camera_rig
	# the wall (x in [-10.5, -9.5]) is right behind the player, who stands 0.4 m from its east face
	var worst := 99.0
	for x in [-9.1, -9.3, -9.6]:
		await e.prep(Vector3(x, 0.0, 4.0), -PI * 0.5, -0.1, 0)
		await e.secs(0.5)
		worst = minf(worst, rig.camera.global_position.distance_to(rig.get_pivot_position()))
	TestLib.check(worst >= CameraRig.MIN_ARM - 0.03, "wall right behind the player: the camera keeps at least %.2f m from the head, as the prototype does (%.2f m)" % [CameraRig.MIN_ARM, worst])
	TestLib.check(rig.is_obstructed(), "...and the rig reports it is obstructed")
	var to_cam := rig.camera.global_position - rig.get_pivot_position()
	TestLib.check(to_cam.dot(rig.camera.global_basis.x) > 0.35, "squeezed against the wall the camera slides to the right shoulder (%.2f m right of the head)" % to_cam.dot(rig.camera.global_basis.x))
	TestLib.check(_bearing_of_head(rig) < -0.4, "...so the character is off to the left and leaves the crosshair line clear (bearing %.0f deg)" % rad_to_deg(_bearing_of_head(rig)))
	# the wall on the right-hand side: the camera slides to the other shoulder instead of into the wall (yaw 0 looks along -Z, so +X is the right)
	await e.prep(Vector3(-11.0, 0.0, 4.0), 0.0, -0.1, 0)
	await e.secs(0.5)
	to_cam = rig.camera.global_position - rig.get_pivot_position()
	var lateral := to_cam.dot(rig.camera.global_basis.x)
	TestLib.check(lateral < 0.05 and rig.is_obstructed(), "wall on the right-hand side: the camera slides to the left shoulder (%.2f m right of the head)" % lateral)
	# open ground: no squeeze, no slide
	await e.prep(Vector3(-30.0, 0.0, 4.0), -PI * 0.5, -0.1, 0)
	await e.secs(0.5)
	to_cam = rig.camera.global_position - rig.get_pivot_position()
	TestLib.check(not rig.is_obstructed() and absf(to_cam.dot(rig.camera.global_basis.x) - 0.8) < 0.05, "open ground: the usual shoulder offset, no slide (%.2f m)" % to_cam.dot(rig.camera.global_basis.x))
	# the rig runs after the nodes it follows
	TestLib.check(rig.process_priority > 0 and rig.process_physics_priority > 0, "the camera rig runs late (priority %d), after the vehicle it follows" % rig.process_priority)


func _all_emitters() -> Array[CPUParticles3D]:
	var list: Array[CPUParticles3D] = []
	for c in p.sparks.get_children():
		if c is CPUParticles3D:
			list.append(c)
	return list


func _visible_count(list: Array[CPUParticles3D]) -> int:
	var n := 0
	for c in list:
		if c.visible:
			n += 1
	return n


func _particle_pools() -> void:
	await e.prep(Vector3(-16.0, 0.0, 4.0))
	var list := _all_emitters()
	TestLib.check(list.size() >= 10, "the spark and puff pools exist (%d emitters)" % list.size())
	var all_off := true
	for c in list:
		all_off = all_off and c.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	TestLib.check(all_off, "no particle emitter casts shadows (each shadow pass would draw it again)")
	await e.secs(0.3)
	TestLib.check(_visible_count(list) == 0 and p.sparks.active_count() == 0, "idle: every emitter is hidden, so it costs no draw call (%d visible)" % _visible_count(list))
	# use every emitter once
	for i in list.size():
		p.sparks.impact_world(Vector3(-12.0 + i * 0.2, 1.0, 4.0), Vector3.UP)
	await e.frames(2)
	var shown := _visible_count(list)
	var emitting := 0
	for c in list:
		if c.visible and c.emitting:
			emitting += 1
	TestLib.check(shown == list.size() and emitting == list.size(), "launched emitters are shown and emitting (%d shown, %d emitting of %d)" % [shown, emitting, list.size()])
	await e.secs(1.4)
	TestLib.check(_visible_count(list) == 0 and p.sparks.active_count() == 0, "...and hidden again once their lifetime is over (%d still visible)" % _visible_count(list))
	# an emitter that is used again comes back
	p.sparks.impact_world(Vector3(-12.0, 1.0, 4.0), Vector3.UP)
	await e.frames(2)
	TestLib.check(_visible_count(list) > 0, "a hidden emitter is shown again when it is reused")
	await e.secs(1.4)
	# the bullet-hole MultiMesh draws nothing while it is empty
	var holes := p.decals.get_node("Holes") as MultiMeshInstance3D
	p.decals.clear()
	TestLib.check(not holes.visible, "an empty bullet-hole ring is hidden (no draw call)")
	p.decals.add(Vector3(-10.5, 1.0, 4.0), Vector3(1.0, 0.0, 0.0))
	TestLib.check(holes.visible, "...and shown with the first hole")
	p.decals.clear()
	TestLib.check(not holes.visible, "...and hidden again when cleared")
	# sustained fire at the wall, then a quiet moment: nothing is left drawing
	await e.prep(Vector3(-16.0, 0.0, 4.0))
	Input.action_press(&"fire")
	await e.secs(0.8)
	Input.action_release(&"fire")
	await e.secs(1.6)
	TestLib.check(_visible_count(list) == 0, "after a burst and 1.6 s of quiet every emitter is hidden again (%d visible)" % _visible_count(list))
	p.decals.clear()
	p.weapon.reset()


func _leg_angle() -> float:
	return p.body.leg_l.basis.get_rotation_quaternion().get_angle()


func _pause_dead_and_victory() -> void:
	var b := p.body
	# a pause freezes the pose: the legs stop where they were
	await e.prep(Vector3(-40.0, 0.0, 30.0))
	Input.action_press(&"move_forward")
	await e.secs(0.7)
	Game.state = &"paused"
	await e.frames(2)
	var ph0: float = b._phase
	var lo := 9.0
	var hi := 0.0
	for i in 30:
		await e.frames(1)
		lo = minf(lo, _leg_angle())
		hi = maxf(hi, _leg_angle())
	TestLib.check(absf(b._phase - ph0) < 0.001 and hi - lo < 0.001, "pause: the body stops running on the spot (phase advanced %.3f, leg angle range %.4f)" % [b._phase - ph0, hi - lo])
	Game.state = &"play"
	await e.secs(0.15)
	TestLib.check(b._phase - ph0 > 0.3, "...and runs on after the pause (phase %.2f)" % (b._phase - ph0))
	Fixture.release_inputs()
	# killed at a sprint: the legs stop cycling, the body slides to a stop
	await e.prep(Vector3(-40.0, 0.0, 30.0))
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await e.secs(1.0)
	TestLib.check(e.flat_speed() > 9.0, "sprinting before the hit (%.2f m/s)" % e.flat_speed())
	p.damage(999.0)
	await e.frames(3)
	var ph1: float = b._phase
	var x0 := p.global_position
	var swings: Array[float] = []
	for i in 30:
		await e.frames(1)
		swings.append(b.leg_l.rotation.x)
	await e.secs(0.2)
	TestLib.check(absf(b._phase - ph1) < 0.05 and b._amp < 0.03, "dead: the legs do not run (phase advanced %.3f, amplitude %.3f)" % [b._phase - ph1, b._amp])
	# the legs go slack (a move into the lying pose), but they do not cycle: a sprint gait reverses the swing about 8 times in half a second
	var reversals := 0
	var last_dir := 0.0
	for i in range(1, swings.size()):
		var step := swings[i] - swings[i - 1]
		if absf(step) < 0.0015:
			continue
		if last_dir != 0.0 and signf(step) != last_dir:
			reversals += 1
		last_dir = signf(step)
	TestLib.check(reversals <= 2, "dead: no gait cycling in the first half second (the swing reverses %d times)" % reversals)
	await e.secs(0.4)
	TestLib.check(e.flat_speed() < 0.2, "dead: the body has slid to a stop (%.2f m/s)" % e.flat_speed())
	var slide := Vector2(p.global_position.x - x0.x, p.global_position.z - x0.z).length()
	TestLib.check(slide > 0.2 and slide < 2.5, "...after a short slide of %.2f m, not instantly and not forever" % slide)
	TestLib.check(not p.sprinting and not p.aiming, "dead: the sprint and aim flags are cleared")
	var key := b.get_node("KeyLight") as DirectionalLight3D
	TestLib.check(key.light_energy < 1.7 * 0.6, "the hero lighting dims on a dead body (key light %.2f)" % key.light_energy)
	Game.do_respawn()
	await e.frames(3)
	Fixture.release_inputs()
	# victory while running: the player is not left running on the spot or sliding forever
	await e.prep(Vector3(-40.0, 0.0, 30.0))
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await e.secs(1.0)
	Game.win()
	await e.frames(3)
	Fixture.release_inputs()
	await e.secs(0.9)
	TestLib.check(Game.state == &"win" and e.flat_speed() < 0.2, "victory: the player comes to a stop (%.2f m/s)" % e.flat_speed())
	TestLib.check(b._amp < 0.03 and _leg_angle() < 0.08, "victory: the legs are at rest (amplitude %.3f, angle %.3f)" % [b._amp, _leg_angle()])
	TestLib.check(not p.sprinting and b.global_basis.y.y > 0.99, "victory: the body stands upright and is not sprinting")
	Game.do_next_sector()
	await e.frames(3)


## The same for the articulated model: the hull points of the listed bones (CharacterRig.THIGH_L ..., all when empty) at the current pose.
func _bone_heights(b: PlayerBody, bones := PackedInt32Array()) -> Vector3:
	var lo := 1e9
	var hi := -1e9
	var above := 0
	var pts := b.rig.world_points(bones)
	for v in pts:
		lo = minf(lo, v.y)
		hi = maxf(hi, v.y)
		if v.y > 0.0:
			above += 1
	return Vector3(lo, hi, float(above) / maxf(1.0, float(pts.size())))


## Height of every vertex of the body's parts in world space, as Vector3(lowest, highest, share of vertices above the floor (y > 0)).
func _vertex_heights(meshes: Array) -> Vector3:
	var lo := 1e9
	var hi := -1e9
	var above := 0
	var total := 0
	for mi: MeshInstance3D in meshes:
		var xf := mi.global_transform
		for v in mi.mesh.get_faces():
			var y := (xf * v).y
			lo = minf(lo, y)
			hi = maxf(hi, y)
			total += 1
			if y > 0.0:
				above += 1
	return Vector3(lo, hi, float(above) / maxf(1.0, float(total)))


func _death_in_the_air_and_the_corpse() -> void:
	var b := p.body
	await e.prep(Vector3(-40.0, 0.0, 30.0))
	Input.action_press(&"jump")
	await e.frames(4)
	Input.action_release(&"jump")
	await e.secs(0.25)
	var y_death := p.global_position.y
	p.damage(999.0)
	await e.secs(1.6)
	TestLib.check(y_death > 0.8 and p.global_position.y < 0.05 and p.is_on_floor(), "killed in mid-air (y %.2f): the body falls to the ground (y %.3f, on floor %s)" % [y_death, p.global_position.y, str(p.is_on_floor())])
	# the corpse lies on the floor: nothing buried, nothing floating, no limb missing under the asphalt
	TestLib.check(b.global_basis.y.y < 0.25, "the corpse lies down (up axis %s)" % str(b.global_basis.y))
	TestLib.check(b.rig != null, "the hero is the articulated model")
	var legs := _bone_heights(b, PackedInt32Array([CharacterRig.THIGH_L, CharacterRig.SHIN_L, CharacterRig.FOOT_L, CharacterRig.THIGH_R, CharacterRig.SHIN_R, CharacterRig.FOOT_R]))
	var parts := _bone_heights(b)
	TestLib.check(parts.x > -0.03 and parts.x < 0.06, "the corpse rests on the floor: its lowest point is at y = %.3f (floor top at 0)" % parts.x)
	TestLib.check(legs.z > 0.99 and legs.x > -0.03, "the legs are not buried in the ground (%.0f %% of their vertices above the floor, lowest %.3f)" % [legs.z * 100.0, legs.x])
	TestLib.check(parts.y < 1.25, "the corpse is not standing or propped up: highest point %.2f m" % parts.y)
	var left := _bone_heights(b, PackedInt32Array([CharacterRig.SHIN_L, CharacterRig.FOOT_L]))
	TestLib.check(left.x < 0.2, "a leg lies on the ground instead of floating above it (lowest vertex of the lower leg at %.3f)" % left.x)
	Game.do_respawn()
	await e.frames(3)
	TestLib.check(b.global_basis.y.y > 0.99 and not p.is_dead(), "respawn: the body stands up again")
	# the same on the primitive body (no model)
	PlayerBody.force_primitive = true
	var old_body := p.body
	var fb := PlayerBody.new()
	fb.name = "Body2"
	p.add_child(fb)
	p.body = fb
	old_body.visible = false
	await e.prep(Vector3(-40.0, 0.0, 30.0))
	p.damage(999.0)
	await e.secs(1.6)
	var fparts := _vertex_heights(fb._parts)
	var flegs := _vertex_heights([fb.leg_l, fb.leg_r])
	TestLib.check(fparts.x > -0.03 and fparts.x < 0.06 and flegs.z > 0.99, "the primitive body also lies on the floor (lowest %.3f, legs %.0f %% above the floor)" % [fparts.x, flegs.z * 100.0])
	Game.do_respawn()
	await e.frames(3)
	p.body = old_body
	old_body.visible = true
	fb.queue_free()
	PlayerBody.force_primitive = false
	await e.frames(2)


func _freed_vehicle() -> void:
	# freeing the vehicle that is being driven puts the player back on foot at once (a freed Object compares equal to null in Godot 4.6)
	for how in ["free", "queue_free"]:
		var car := Fixture.add_vehicle(e.root, Vector3(-20.0, 0.0, 24.0), Vector3(1.9, 1.3, 4.5), true)
		await e.prep(Vector3(-30.0, 0.0, 24.0))
		p.vehicle = car
		await e.frames(5)
		TestLib.check(p.vehicle == car and not p.body.visible and p.collision_layer == 0, "driving (%s test): the player is in the vehicle" % how)
		if how == "free":
			car.free()
		else:
			car.queue_free()
		await e.frames(3)
		TestLib.check(p.vehicle == null and p.body.visible and p.camera_rig.mode == &"foot", "the vehicle was %sd: the player is on foot again, body shown, camera back in foot mode" % how)
		TestLib.check(p.collision_layer == Game.L_PLAYER and p.camera_rig.follow_target == p, "...with the collider back on the player layer and the camera following the player")
		await e.secs(0.6)
		TestLib.check(p.is_on_floor() and p.global_position.y > -0.1, "...standing on the floor, not falling through the world (y %.2f)" % p.global_position.y)
		var hp := p.hp
		p.damage(10.0)
		TestLib.check(absf(p.hp - (hp - 10.0)) < 0.001, "...and damage hurts the player again (hp %.1f)" % p.hp)
		p.vehicle = null                                        # a no-op, and no error
		await e.frames(2)
		TestLib.check(p.vehicle == null and p.body.visible, "assigning null afterwards changes nothing")
		# a new vehicle can be entered right away
		var car2 := Fixture.add_vehicle(e.root, Vector3(-27.0, 0.0, 24.0))
		p.vehicle = car2
		await e.frames(3)
		TestLib.check(p.vehicle == car2 and not p.body.visible, "a new vehicle can be entered after that")
		p.vehicle = null
		car2.queue_free()
		await e.frames(2)


func _swing(a: Array[float]) -> float:
	var lo := 1e9
	var hi := -1e9
	for z in a:
		lo = minf(lo, z)
		hi = maxf(hi, z)
	return hi - lo


func _chase_lockstep() -> void:
	# a vehicle moved once per physics tick at 30 m/s (0.5 m per tick): on screen it must not saw back and forth against the chase camera
	var host := e.host
	var rig := p.camera_rig
	var car := Fixture.add_vehicle(e.root, Vector3(-60.0, 0.0, 24.0), Vector3(1.9, 1.3, 4.5), false, true)
	car.heading = -PI * 0.5
	car.rotation.y = car.heading
	car.speed = 30.0
	var driver := Driver.new()
	driver.car = car
	host.add_child(driver)                                        # after the player in tree order, so the car moves after the player's physics
	var sampler := Sampler.new()
	sampler.rig = rig
	sampler.car = car
	host.add_child(sampler)
	await e.prep(Vector3(-70.0, 0.0, 24.0))
	p.vehicle = car
	await e.secs(1.5)
	sampler.zs.clear()
	var at_frame: Array[float] = []
	for i in 180:
		await host.get_tree().process_frame                         # after the physics ticks, before any _process: what a raycast or get_aim() would see
		var rel := rig.camera.global_basis.inverse() * (car.global_position + Vector3(0.0, 0.65, 0.0) - rig.camera.global_position)
		at_frame.append(rel.z)
	var drawn := _swing(sampler.zs)
	var between := _swing(at_frame)
	TestLib.check(drawn < 0.05, "chase camera: a vehicle moved in physics ticks at 30 m/s holds still in the drawn frame (swing %.3f m, 0.5 m per tick)" % drawn)
	TestLib.check(between < 0.05, "...and between the physics tick and the frame, where a raycast or get_aim() looks (swing %.3f m)" % between)
	p.vehicle = null
	driver.queue_free()
	sampler.queue_free()
	car.queue_free()
	await e.frames(2)
