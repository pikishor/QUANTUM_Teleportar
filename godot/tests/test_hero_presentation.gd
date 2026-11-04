extends RefCounted
## Hero presentation: camera scaling for a tall hero, hand-bone mounts on a 65-bone style skeleton, shadow proxy and mirror rules, quantum bursts on hit and death in the real scene.
## Run: tools/test.sh tests/test_hero_presentation.gd

func run(host: Node) -> void:
	# camera profile
	var ref := HeroPresentation.camera_scale(1.8)
	TestLib.check(is_equal_approx(float(ref["eye"]), 1.0) and is_equal_approx(float(ref["dist"]), 1.0), "reference height leaves the camera as tuned")
	var tall := HeroPresentation.camera_scale(2.1)
	TestLib.check(float(tall["eye"]) > 1.05 and float(tall["dist"]) > 1.0 and float(tall["dist"]) < float(tall["eye"]) and float(tall["shoulder"]) > 1.0, "a taller hero raises the eye and widens the arm a little")
	var huge := HeroPresentation.camera_scale(9.0)
	TestLib.check(float(huge["eye"]) <= HeroPresentation.SCALE_MAX + 0.001, "scale is clamped")
	HeroPresentation.set_height(-3.0)
	TestLib.check(HeroPresentation.height == HeroPresentation.REF_HEIGHT, "nonsense height falls back")

	TestLib.check(HeroPresentation.scale_factor(1.9) == 1.0, "near-reference heights keep the tuned camera")

	# hand bones on a synthetic skeleton (names of the contract and of a Mixamo / Unreal style rig)
	var sk := Skeleton3D.new()
	host.add_child(sk)
	for n: String in ["Hips", "HandR", "hand_l", "Rifle"]:
		sk.add_bone(n)
	TestLib.check(HeroPresentation.hand_bone(sk, &"r") == 1 and HeroPresentation.hand_bone(sk, &"l") == 2, "hand_r / hand_l found by name variants")
	var m := HeroPresentation.hand_mount(sk, &"r")
	TestLib.check(m != null and m.bone_name == "HandR" and HeroPresentation.hand_mount(sk, &"r") == m, "hand mount is a bone attachment, reused")
	var empty := Skeleton3D.new()
	empty.add_bone("Spine")
	TestLib.check(HeroPresentation.hand_mount(empty, &"r") == null and HeroPresentation.hand_bone(null, &"l") == -1, "no hand bone gives null")
	sk.queue_free()
	empty.free()

	# the real scene
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	var p: Player = Game.player
	if p == null or p.body == null:
		TestLib.check(false, "real game has a player body")
		return
	var b: PlayerBody = p.body
	Game.state = &"play"
	TestLib.check(b.get_node_or_null("QuantumBurst") == null, "no idle burst emitter before the first hit (draw budget)")
	if b.rig != null:
		TestLib.check(b.reflection_free(), "skinned hero is not mirrored by the unskinned proxy")
		var sh: MeshInstance3D = b.rig.shadow
		if sh != null:
			TestLib.check(sh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and sh.skin != null, "shadow proxy shares the skin and only casts shadows")
		TestLib.check(b.muzzle != null and b.muzzle.get_parent() != null, "muzzle node exists on the model")
	b.flinch(1.0)
	var burst := b.get_node("QuantumBurst") as CPUParticles3D
	TestLib.check(burst.emitting, "a hit emits quantum motes")
	burst.emitting = false
	b.set_dead(true)
	TestLib.check(burst.emitting and burst.amount == HeroPresentation.DEATH_MOTES, "death emits the full burst")
	b.set_dead(false)
	b.reset_pose()
	p.queue_free()
