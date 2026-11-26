extends RefCounted
const TIMEOUT_SECONDS := 300
const Fingers := preload("res://tests/w116_fingers.gd")
func run(host: Node) -> void:
	Sfx.muted = true
	Game.force_touch = true
	CrateReveal._quiet = 0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 20)
	Game.state = &"menu"
	if OS.get_environment("NODEMO") != "1":
		DemoMode.enter()
	await TestLib.frames(host, 10)
	Game.state = &"play"
	await TestLib.frames(host, 4)
	var fg := Fingers.new(host)
	var p := Game.player as Player
	for id: StringName in [&"pistol", &"mpistol", &"f_cryo", &"mpistol", &"katana"]:
		if DemoMode.active:
			DemoMode.equip_weapon(id)
		await TestLib.frames(host, 6)
		var s0 := p.weapon.shots_fired
		print("PRE %s card=%s state=%s dead=%s can_fire=%s btn=%s" % [id, CrateReveal.is_showing(), Game.state, p.get(&"dead"), p.weapon.get(&"can_fire"), fg.button(&"fire")])
		fg.press(3, &"fire")
		var first := -1
		for i in 90:
			await TestLib.frames(host, 1)
			if i == 10:
				print("MID snake=%s swap=%.2f reload=%.2f pressed=%s state=%s vehicle=%s" % [SnakeWar.holding(), p.weapon.swap_t, p.weapon.reload_t, Input.is_action_pressed(&"fire"), Game.state, p.vehicle])
			if first < 0 and p.weapon.shots_fired > s0:
				first = i
		fg.up(3)
		await TestLib.frames(host, 20)
		print("FIRE %s first shot at frame %d shots %d ammo %d mag %d reload=%s" % [id, first, p.weapon.shots_fired - s0, p.weapon.ammo, p.weapon.mag, p.weapon.get(&"reloading")])
	main.queue_free()
	await TestLib.frames(host, 2)
