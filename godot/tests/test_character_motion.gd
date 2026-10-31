extends RefCounted
## Character motion tests (headless): the character draws exactly one body mesh (no stationary duplicate), and the procedural gait plants its feet.
##   hero and trooper: the visible MeshInstance3D count (one skinned body; the rig's rest-pose twin is on no render layer; flash cards only while a shot flashes), no
##   reflection copy of a skinned model; Locomotion: the planted sole of a foot does not move in the world while the body walks, strafes, backs up and turns
##   (under 3 cm), the stride lengthens with the speed, the pelvis stays above the legs' reach, a jump lands with a squash that recovers, the three death variants of the
##   trooper lie on the floor, a hit from the right rolls the torso away from it.
## Run: tools/test.sh tests/test_character_motion.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")

var e := Env.new()
var p: Player


## Meshes that would be drawn by the camera: in the tree, visible, on at least one render layer, with a mesh.
static func drawn_meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.is_visible_in_tree() and mi.layers != 0:
			out.append(mi)
	return out


func run(host: Node) -> void:
	await e.setup(host)
	p = e.p
	await _hero_meshes()
	await _hero_gait()
	await _hero_air_and_hit()
	await _trooper()
	await e.teardown()


func _hero_meshes() -> void:
	await e.prep(Vector3(0.0, 0.0, 0.0))
	var b := p.body
	TestLib.check(b.rig != null and b.loco != null, "the hero uses the articulated model and a Locomotion")
	var meshes := drawn_meshes(p)
	var names := PackedStringArray()
	for m in meshes:
		names.append(String(p.get_path_to(m)))
	TestLib.check(meshes.size() == 1, "the hero draws exactly ONE mesh at rest (got %d: %s)" % [meshes.size(), ", ".join(names)])
	TestLib.check(b.rig.rest_mesh.layers == 0, "the rest-pose twin of the body is on no render layer (layers %d): it is never drawn" % b.rig.rest_mesh.layers)
	TestLib.check(drawn_meshes(b._reflection).is_empty(), "a skinned hero has no reflection copy (a second, stationary body)")
	b.fire_flash(1.0)
	await e.frames(2)
	TestLib.check(drawn_meshes(p).size() == 1 + 3, "while a shot flashes the muzzle adds 3 flash cards (got %d)" % drawn_meshes(p).size())
	await e.secs(0.3)
	TestLib.check(drawn_meshes(p).size() == 1, "and they are gone again (got %d)" % drawn_meshes(p).size())


func _sole(k: int) -> Vector3:
	var rg := p.body.rig
	var mv := rg.bone_move(CharacterRig.FOOT_L if k == 0 else CharacterRig.FOOT_R)
	return rg.model.global_transform * (mv * rg.sole_rest(k))


## Walks the hero in a direction for `secs` seconds and returns the worst slide (cm) of a planted sole over any ground contact, and the strides seen.
func _slide_run(actions: Array[StringName], secs: float, look_rate := 0.0) -> Vector2:
	await e.prep(Vector3(0.0, 0.0, 0.0), -PI * 0.5, 0.0, 12)
	for a in actions:
		Input.action_press(a)
	var worst := 0.0
	var strides := 0
	var start := [Vector3.ZERO, Vector3.ZERO]
	var active := [false, false]
	var mx := [0.0, 0.0]
	var t := 0.0
	var lc := p.body.loco
	while t < secs:
		await e.frames(1)
		t += 1.0 / 60.0
		if look_rate != 0.0:
			p.camera_rig.add_look(look_rate / 60.0, 0.0)
		if t < 0.8:
			continue
		for k in 2:
			var prog := lc.stance_progress(k)
			if prog >= 0.0 and (lc.speed > 0.4 or absf(lc.yaw_rate) > 0.7):
				var w := _sole(k)
				if not active[k]:
					active[k] = true
					start[k] = w
					mx[k] = 0.0
				else:
					var dv: Vector3 = w - (start[k] as Vector3)
					mx[k] = maxf(mx[k], Vector2(dv.x, dv.z).length())
			elif active[k]:
				active[k] = false
				worst = maxf(worst, mx[k] * 100.0)
				strides += 1
	Fixture.release_inputs()
	return Vector2(worst, strides)


func _hero_gait() -> void:
	var cases := {"forward": [&"move_forward"] as Array[StringName], "sprint": [&"move_forward", &"sprint"] as Array[StringName],
			"strafe": [&"move_right"] as Array[StringName], "backpedal": [&"move_back"] as Array[StringName],
			"aim walk": [&"aim", &"move_forward"] as Array[StringName]}
	for name in cases:
		var r := await _slide_run(cases[name], 2.2)
		TestLib.check(r.y >= 3.0, "%s: %d ground contacts measured" % [name, int(r.y)])
		TestLib.check(r.x < 3.0, "%s: planted foot slide %.2f cm per contact (target < 3 cm)" % [name, r.x])
	var rt := await _slide_run([] as Array[StringName], 1.6, 3.5)
	TestLib.check(rt.x < 3.0, "turning in place: planted foot slide %.2f cm over %d contacts (< 3 cm)" % [rt.x, int(rt.y)])
	# the stride lengthens with the speed: footfalls per metre fall as the speed rises
	await e.prep(Vector3(0.0, 0.0, 0.0), -PI * 0.5, 0.0, 12)
	var lc := p.body.loco
	Input.action_press(&"aim")
	Input.action_press(&"move_forward")
	await e.secs(1.0)
	var f0 := lc.footfalls
	var x0 := p.global_position.x
	await e.secs(1.5)
	var slow := float(lc.footfalls - f0) / maxf(absf(p.global_position.x - x0), 0.1)
	Input.action_release(&"aim")
	Input.action_press(&"sprint")
	await e.secs(1.0)
	f0 = lc.footfalls
	x0 = p.global_position.x
	await e.secs(1.5)
	var fast := float(lc.footfalls - f0) / maxf(absf(p.global_position.x - x0), 0.1)
	Fixture.release_inputs()
	TestLib.check(fast < slow * 0.85, "the stride lengthens with speed: %.2f footfalls per metre aiming, %.2f sprinting" % [slow, fast])
	# the pelvis never drops under what the legs reach, nothing is NaN
	var rg := p.body.rig
	var hips := rg.bone_move(CharacterRig.HIPS) * Vector3(0.0, rg._hips_rest_y, 0.0)
	TestLib.check(is_finite(hips.y) and hips.y > 0.5 and hips.y < 1.25, "pelvis height is sane (%.2f m)" % hips.y)


func _hero_air_and_hit() -> void:
	await e.prep(Vector3(0.0, 0.0, 0.0), -PI * 0.5, 0.0, 12)
	var rg := p.body.rig
	Input.action_press(&"jump")
	await e.frames(3)
	Input.action_release(&"jump")
	var air_seen := 0.0
	var squash_peak := 0.0
	for i in 90:
		await e.frames(1)
		air_seen = maxf(air_seen, rg.air)
		squash_peak = maxf(squash_peak, rg.squash)
	TestLib.check(air_seen > 0.8, "a jump shows the airborne pose (air %.2f)" % air_seen)
	TestLib.check(squash_peak > 0.05, "landing squashes the pelvis (%.3f m)" % squash_peak)
	await e.secs(0.8)
	TestLib.check(absf(rg.squash) < 0.02, "and the squash recovers (%.3f)" % rg.squash)
	# a hit from the right (the player faces -x: his right is -z ... the body works it out from the position)
	await e.prep(Vector3(0.0, 0.0, 0.0), -PI * 0.5, 0.0, 12)
	var right := Vector3(cos(p.yaw), 0.0, -sin(p.yaw))
	p.damage(15.0, p.global_position + right * 3.0 + Vector3(0.0, 1.0, 0.0))
	await e.frames(2)
	TestLib.check(rg.flinch_dir.x > 0.5, "a hit from the right is registered as coming from the right (dir %s)" % str(rg.flinch_dir))
	var tor := rg.skeleton.get_bone_pose(rg.skeleton.find_bone("Torso")).basis.get_euler()
	TestLib.check(absf(tor.z) > 0.02, "and rolls the torso (roll %.3f)" % tor.z)
	await e.secs(0.8)


func _trooper() -> void:
	var mgr := EnemyManager.new()
	e.root.add_child(mgr)
	Game.enemies = mgr
	mgr.patrol_groups().clear()
	var o := mgr.spawn(&"operative", Vector3(12.0, 0.0, 4.0), false) as Operative
	TestLib.check(o != null and o.rig != null and o.loco != null, "a trooper spawns with the articulated model and a Locomotion")
	await e.frames(4)
	var meshes := drawn_meshes(o)
	TestLib.check(meshes.size() == 1, "the trooper draws exactly ONE mesh (got %d)" % meshes.size())
	TestLib.check(o.rig.rest_mesh.layers == 0, "the trooper's rest-pose twin is on no render layer")
	# the three death variants end on the floor
	for kind in 3:
		var t := mgr.spawn(&"operative", Vector3(20.0 + 4.0 * kind, 0.0, 4.0), true) as Operative
		t.damage(1000.0, true)
		t._death_kind = kind
		await e.secs(1.6)
		var low := t.rig.lowest_world_y()
		TestLib.check(t.dead and absf(low - t.global_position.y) < 0.12, "death kind %d: the corpse rests on the floor (lowest point %.3f m above it)" % [kind, low - t.global_position.y])
		var lying := maxf(absf(t.model.rotation.x), absf(t.model.rotation.z))
		TestLib.check(absf(lying - PI * 0.5) < 0.1, "death kind %d: the body lies down (%.2f rad)" % [kind, lying])
	mgr.queue_free()
	Game.enemies = null
	await e.frames(2)
