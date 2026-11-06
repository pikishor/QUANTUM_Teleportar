extends RefCounted
## Hero polish in the REAL game scene: the Blender rifle (within 3k triangles, glow seams) is part of the hero's one mesh, the weapon look rides on the hand bone mount (follows animations),
## finger poses (grip / relaxed / aim) are bone rotations, the corpse lies tuned for the long legs (stricter than before), idle legs rest (< 0.05 rad) and the quantum burst node exists
## before the first hit (created during warmup, so the first burst does not hitch). Waits are on state, never on frame counts alone.
## Run: tools/test.sh tests/test_hero_polish.gd


func _until(host: Node, cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await TestLib.frames(host, 1)
	return cond.call()


func run(host: Node) -> void:
	TestLib.check(HeroCharacter.available(&"male"), "the hero kit is imported")
	if not HeroCharacter.available(&"male"):
		return
	var arr := HeroCharacter._rifle_arrays()
	TestLib.check(not arr.is_empty(), "the Blender rifle model is imported")
	if not arr.is_empty():
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var glow := 0
		for c in cols:
			if c.g > 0.5:
				glow += 1
		TestLib.check(idx.size() / 3 <= 3000 and idx.size() / 3 > 800, "the rifle is a real model within 3k triangles (%d)" % (idx.size() / 3))
		TestLib.check(glow > 40 and glow < cols.size(), "glow seams are marked in the vertex colour (%d of %d vertices)" % [glow, cols.size()])
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	var p: Player = Game.player
	var prog := Game.progress as Progress
	if p == null or p.body == null or prog == null:
		TestLib.check(false, "the real game has a player body and progress")
		return
	prog.autosave_enabled = false
	prog.hero.reset()
	Game.state = &"play"
	for n in host.find_children("*", "Stability", true, false):
		n.set_process(false)
	var b: PlayerBody = p.body
	await _until(host, func() -> bool: return b.hero_mat != null and b.rig != null, 60)
	TestLib.check(b.hero_mat != null and b.rig != null, "the live hero is the superhero")
	if b.hero_mat == null or b.rig == null:
		return
	var info := b.hero_info
	TestLib.check(int(info["surfaces"]) == 1 and int(info["tris"]) <= HeroCharacter.BUDGET, "the hero with the new rifle is still one surface within budget (%s tris)" % str(info["tris"]))
	await TestLib.frames(host, 20)
	var idle_angle := b.leg_l.basis.get_rotation_quaternion().get_angle()
	TestLib.check(idle_angle < 0.05, "idle: the thigh is at rest (%.3f rad)" % idle_angle)

	# --- the burst node exists before the first hit
	if b._burst == null:
		await ShaderWarmup.run(host)                  # the warm-up of the live game creates it (the test scene may skip the warm-up)
	TestLib.check(b._burst != null and is_instance_valid(b._burst) and not b._burst.visible, "the quantum burst node is pre-created and hidden (no hitch on the first burst)")

	# --- the weapon rides the muzzle node (rifle bone) and its grip stays at the right hand through states
	b.set_weapon_look(&"scatter")
	await TestLib.frames(host, 6)
	var look := b._wp_mi
	TestLib.check(look != null and look.get_parent() == b.muzzle, "the weapon look is parented to the muzzle node")
	if look != null:
		var hand := b.rig.skeleton.global_transform * b.rig.skeleton.get_bone_global_pose(b.rig.skeleton.find_bone("hand_r")).origin
		var grip_at := WeaponModels.spec(&"scatter")["gr"] as Vector3
		var d0 := look.to_global(grip_at).distance_to(hand)
		for k in 3:
			p.sprinting = k == 1
			p.aiming = k == 2
			await TestLib.frames(host, 25)
			hand = b.rig.skeleton.global_transform * b.rig.skeleton.get_bone_global_pose(b.rig.skeleton.find_bone("hand_r")).origin
			TestLib.check(absf(look.to_global(grip_at).distance_to(hand) - d0) < 0.12 and d0 < 0.8, "state %d: the weapon's grip stays at the hand (%.3f vs %.3f m)" % [k, look.to_global(grip_at).distance_to(hand), d0])
		p.sprinting = false
		p.aiming = false

	# --- finger poses are bone rotations
	var sk := b.rig.skeleton
	var fi := sk.find_bone("index_02_r")
	TestLib.check(fi >= 0, "finger bones exist")
	if fi >= 0:
		HeroFingers.pose(sk, &"grip")
		var grip := sk.get_bone_pose(fi).basis.get_rotation_quaternion()
		HeroFingers.pose(sk, &"relaxed")
		var relaxed := sk.get_bone_pose(fi).basis.get_rotation_quaternion()
		HeroFingers.pose(sk, &"aim")
		var aim := sk.get_bone_pose(fi).basis.get_rotation_quaternion()
		TestLib.check(grip.angle_to(relaxed) > 0.2 and grip.angle_to(aim) > 0.05, "grip, relaxed and aim are different bone rotations (%.2f, %.2f rad)" % [grip.angle_to(relaxed), grip.angle_to(aim)])
		HeroFingers.pose(sk, &"grip")

	# --- the corpse
	p.invuln = 0.0
	p.damage(1.0e7, p.global_position + Vector3(2.0, 1.0, -3.0))
	var dead := await _until(host, func() -> bool: return b.rig.dead > 0.99 and b._dead_t > PlayerBody.FALL_TIME + PlayerBody.DEAD_SETTLE + 0.2, 600)
	TestLib.check(dead, "death: the limp pose")
	await TestLib.frames(host, 10)
	var legs := b.rig.world_points(PackedInt32Array([CharacterRig.SHIN_L, CharacterRig.FOOT_L]))
	var lo := 1e9
	for v in legs:
		lo = minf(lo, v.y)
	var floor_y := p.global_position.y
	print("PROBE corpse leg low %.3f up %s dt %.2f dead %.2f ply %.2f" % [lo - floor_y, str(b.global_basis.y), b._dead_t, b.rig.dead, p.global_position.y])
	TestLib.check(lo - floor_y < 0.2, "the corpse's left lower leg lies low (%.3f m above the floor)" % (lo - floor_y))
	var both := b.rig.world_points(PackedInt32Array([CharacterRig.THIGH_L, CharacterRig.SHIN_L, CharacterRig.FOOT_L, CharacterRig.THIGH_R, CharacterRig.SHIN_R, CharacterRig.FOOT_R]))
	var below := 0
	for v in both:
		if v.y < floor_y - 0.03:
			below += 1
	TestLib.check(below == 0, "no leg vertex is buried in the floor (%d of %d)" % [below, both.size()])
	TestLib.check(b._lowest_point() - floor_y < 0.06 and b._lowest_point() - floor_y > -0.03, "the corpse rests on the floor")
	Game.do_respawn()
	await TestLib.frames(host, 3)
