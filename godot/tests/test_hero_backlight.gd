extends RefCounted
## Hero lighting follows the ACTIVE camera (root cause of the flaky visual-QA 'hero blends in' shot: the lights followed the orbit yaw, not the cinematic camera, so a hero seen from
## behind got the key on his far side). In the REAL game scene: a camera in front of, beside and behind the hero -> the key light travels from the camera towards him, the rim light
## towards the camera, the trim backlight lifts when the camera is behind him (and only then). Waits on state, not frame counts.
## Run: tools/test.sh tests/test_hero_backlight.gd


func _until(host: Node, cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await TestLib.frames(host, 1)
	return cond.call()


func run(host: Node) -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	var p: Player = Game.player
	if p == null or p.body == null:
		TestLib.check(false, "the real game has a player body")
		return
	(Game.progress as Progress).autosave_enabled = false
	Game.state = &"play"
	for n in host.find_children("*", "Stability", true, false):
		n.set_process(false)
	var b: PlayerBody = p.body
	await _until(host, func() -> bool: return b._key_light != null and b._rim_light != null, 60)
	b.character_light = true
	b.set_quality(1)
	var cam := Camera3D.new()
	host.add_child(cam)
	cam.make_current()
	await TestLib.frames(host, 10)
	var hero := b.global_position
	var fwd := Vector3(-b.global_basis.z.x, 0.0, -b.global_basis.z.z).normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var cases := {"front": fwd * 3.4, "behind": -fwd * 3.4, "side": right * 3.4}
	var back_vals := {}
	for k in cases:
		hero = b.global_position
		cam.global_position = hero + cases[k] + Vector3(0.0, 1.3, 0.0)
		cam.look_at(hero + Vector3(0.0, 1.0, 0.0), Vector3.UP)
		for i in 40:
			b.update_character_lights()
			await TestLib.frames(host, 1)
		var view := (b.global_position - cam.global_position)
		view.y = 0.0
		view = view.normalized()
		var key_dir := -b._key_light.global_basis.z
		var rim_dir := -b._rim_light.global_basis.z
		key_dir.y = 0.0
		rim_dir.y = 0.0
		TestLib.check(key_dir.normalized().dot(view) > 0.8, "%s: the key light travels from the camera towards the hero (%.2f)" % [k, key_dir.normalized().dot(view)])
		TestLib.check(rim_dir.normalized().dot(view) < -0.7, "%s: the rim light comes from behind the hero (%.2f)" % [k, rim_dir.normalized().dot(view)])
		back_vals[k] = b._back
	TestLib.check(float(back_vals["behind"]) > 0.9, "the trim backlight is on seen from behind (%.2f)" % back_vals["behind"])
	TestLib.check(float(back_vals["front"]) < 0.1, "and off seen from the front (%.2f)" % back_vals["front"])
	var cost := b._key_light.shadow_enabled or b._rim_light.shadow_enabled
	TestLib.check(not cost, "budget-neutral: the two character lights stay unshadowed, and no light was added")
	var dirs := 0
	for n in b.find_children("*", "DirectionalLight3D", true, false):
		dirs += 1
	TestLib.check(dirs == 2, "the hero still owns exactly two directional lights (%d)" % dirs)
	cam.queue_free()
	main.queue_free()

