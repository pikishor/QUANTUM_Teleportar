extends RefCounted
## Cover, crouch, slide and takedown (G4/A2/A3). Run: tools/test.sh tests/test_cover_takedown.gd

const Fixture := preload("res://tests/player_fixture.gd")


func _wait(host: Node, cond: Callable, max_frames := 240) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await TestLib.frames(host, 1)
	return cond.call()


func run(host: Node) -> void:
	# pure maths
	TestLib.check(PlayerCover.is_behind(Vector3(0, 0, -1), Vector3(0, 0, 2)), "behind an enemy that faces away")
	TestLib.check(not PlayerCover.is_behind(Vector3(0, 0, -1), Vector3(0, 0, -2)), "not behind when in front")
	TestLib.check(not PlayerCover.is_behind(Vector3(0, 0, -1), Vector3(2, 0, 0)), "not behind from the side")

	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 3)
	var p: Player = Game.player
	if p == null or p.cover == null:
		TestLib.check(false, "player owns a PlayerCover")
		return
	Game.state = &"play"
	var arena := Node3D.new()
	host.add_child(arena)
	var origin := Vector3(0, 150, 0)
	Fixture.add_box(arena, origin + Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	Fixture.add_box(arena, origin + Vector3(0, 1.5, -2.0), Vector3(10, 3, 0.5))        # a wall north of the player
	p.global_position = origin + Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	await TestLib.frames(host, 10)

	# crouch: shrinks, slows, stands up again
	Input.action_press(&"crouch")
	var ok := await _wait(host, func(): return p.cover.crouching and p.cover.height < PlayerCover.CROUCH_HEIGHT + 0.1)
	TestLib.check(ok, "crouch shrinks the capsule")
	TestLib.check(p.cover.speed_mult() < 0.9, "crouch slows the walk")
	Input.action_release(&"crouch")
	ok = await _wait(host, func(): return not p.cover.crouching and p.cover.height > PlayerCover.STAND_HEIGHT - 0.1)
	TestLib.check(ok, "stands up with headroom")

	# cover: crouch beside the wall snaps and hugs it, peek-fire stands up
	p.global_position = origin + Vector3(0, 0.05, -1.2)
	p.velocity = Vector3.ZERO
	Input.action_press(&"crouch")
	ok = await _wait(host, func(): return p.cover.in_cover)
	TestLib.check(ok, "crouching near a wall enters cover")
	await TestLib.frames(host, 40)
	var dist := absf(p.global_position.z - (origin.z - 2.0 + 0.25))
	TestLib.check(dist < PlayerCover.COVER_GAP + Player.CAPSULE_RADIUS + 0.2, "the body hugs the wall (%.2f)" % dist)
	TestLib.check(p.cover.cover_normal.z > 0.5, "cover normal points away from the wall")
	TestLib.check(is_equal_approx(p.cover.damage_mult(), PlayerCover.COVER_DAMAGE), "head down halves damage")
	Input.action_press(&"aim")
	ok = await _wait(host, func(): return p.cover.peeking)
	TestLib.check(ok, "aiming from cover peeks")
	TestLib.check(is_equal_approx(p.cover.damage_mult(), 1.0), "peeking is not covered")
	Input.action_release(&"aim")
	Input.action_release(&"crouch")
	await TestLib.frames(host, 20)

	# slide under a 1 m gap
	for c in arena.get_children():
		if c.name != "Floor" and c is StaticBody3D and (c as StaticBody3D).global_position.y > origin.y + 1.0:
			c.queue_free()
	await TestLib.frames(host, 2)
	Fixture.add_box(arena, origin + Vector3(0, 1.5 + 1.0, -14.0), Vector3(4, 3, 0.4))    # bottom face at 1.0 m above the floor (gap 1.0)
	p.global_position = origin + Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	p.camera_rig.yaw = 0.0
	p.yaw = 0.0
	await TestLib.frames(host, 10)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _wait(host, func(): return p.sprinting and p.global_position.z < origin.z - 11.8, 400)
	Input.action_press(&"crouch")
	ok = await _wait(host, func(): return p.cover.sliding)
	TestLib.check(ok, "crouch while sprinting slides")
	ok = await _wait(host, func(): return p.global_position.z < origin.z - 14.6, 200)
	TestLib.check(ok, "the slide goes under the 1 m obstacle (z %.1f)" % (p.global_position.z - origin.z))
	Input.action_release(&"crouch")
	Input.action_release(&"sprint")
	Input.action_release(&"move_forward")
	await TestLib.frames(host, 30)

	# takedown from behind
	p.global_position = origin + Vector3(10, 0.05, 0)
	p.velocity = Vector3.ZERO
	await TestLib.frames(host, 5)
	var front := Fixture.add_dummy(arena, p.global_position + Vector3(0, 0, -1.2), 0.5, false)
	front.rotation.y = PI                                   # faces +Z, toward the player: not a back
	await TestLib.frames(host, 2)
	TestLib.check(not p.cover.try_takedown(), "no takedown on an enemy that faces the player")
	front.queue_free()
	var back := Fixture.add_dummy(arena, p.global_position + Vector3(0, 0, -1.2), 0.5, false)
	back.rotation.y = 0.0                                   # faces -Z, away from the player
	await TestLib.frames(host, 2)
	TestLib.check(p.cover.target == back, "the unaware back is the takedown target")
	var n0 := p.cover.takedowns
	TestLib.check(p.cover.try_takedown(), "takedown from behind succeeds")
	TestLib.check(back.dead and p.cover.takedowns == n0 + 1, "the enemy is dead")
	TestLib.check(p.cover.strike > 0.5, "strike effect runs")
	TestLib.check(not p.cover.try_takedown(), "takedown has a cooldown")
	await TestLib.frames(host, 5)

	# touch hooks
	var tc := TouchControls.new()
	var names: Array = []
	for b: Dictionary in TouchControls.BUTTONS:
		names.append(b["action"])
	TestLib.check(&"crouch" in names and &"takedown" in names, "touch buttons for crouch and takedown")
	tc.free()
	TestLib.check(InputMap.has_action(&"crouch") and InputMap.has_action(&"takedown"), "keyboard actions exist")
	Fixture.release_inputs()
	arena.queue_free()
	main.queue_free()
