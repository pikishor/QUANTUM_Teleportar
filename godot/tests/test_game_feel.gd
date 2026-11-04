extends RefCounted
## Game feel in the REAL scene: event profiles, shake / FOV kick / hit-stop / blur / haptic hooks, reduce-motion and reduce-flash, low-health heartbeat, taller-hero aim cone.
## Run: tools/test.sh tests/test_game_feel.gd


func run(host: Node) -> void:
	UiSettings.s_reduce_motion = false
	UiSettings.s_reduce_flash = false
	Engine.time_scale = 1.0
	# pure table
	TestLib.check(GameFeel.is_heavy_kill(true, &"carbine") and GameFeel.is_heavy_kill(false, &"lance") and not GameFeel.is_heavy_kill(false, &"carbine"), "heavy kill = crit or heavy weapon")
	TestLib.check(float(GameFeel.effective(&"slam")["shake"]) > float(GameFeel.effective(&"hurt")["shake"]), "slam shakes harder than a hit")
	TestLib.check(GameFeel.heartbeat_period(0.5) == 0.0 and GameFeel.heartbeat_period(0.05) < GameFeel.heartbeat_period(0.25), "heartbeat faster at lower health")
	UiSettings.s_reduce_motion = true
	var rm := GameFeel.effective(&"slam")
	TestLib.check(float(rm["shake"]) == 0.0 and float(rm["fov"]) == 0.0 and float(rm["stop"]) == 0.0 and float(rm["blur"]) == 0.0, "reduce-motion drops shake, fov, stop, blur")
	TestLib.check(int(rm["buzz"]) > 0, "haptics stay under reduce-motion")
	UiSettings.s_reduce_motion = false
	UiSettings.s_reduce_flash = true
	TestLib.check(float(GameFeel.effective(&"teleport")["blur"]) == 0.0 and float(GameFeel.effective(&"teleport")["fov"]) > 0.0, "reduce-flash drops only the blur")
	TestLib.check(Hud.vignette_alpha(10.0, 0.1, true, 0.0) == Hud.vignette_alpha(10.0, 0.1, true, 0.3), "reduce-flash: steady low-health vignette")
	UiSettings.s_reduce_flash = false
	TestLib.check(Hud.vignette_alpha(10.0, 0.1, true, 0.0) > 0.0, "low health shows the vignette")

	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 3)
	var p: Player = Game.player
	if p == null or p.camera_rig == null:
		TestLib.check(false, "player with camera rig present")
		return
	for i in 600:
		if Game.state == &"play":
			break
		await TestLib.frames(host, 1)
	var rig := p.camera_rig
	var n0 := GameFeel.fired
	FX.shake_amount = 0.0
	GameFeel.fire(&"slam")
	TestLib.check(GameFeel.fired == n0 + 1 and GameFeel.last == &"slam", "fire is counted")
	TestLib.check(FX.shake_amount > 0.5, "slam shakes the camera")
	TestLib.check(rig._fov_punch > 1.0, "slam kicks the FOV")
	for i in 600:
		if rig._stop_left <= 0.0 and is_equal_approx(Engine.time_scale, 1.0):
			break
		await TestLib.frames(host, 1)
	TestLib.check(is_equal_approx(Engine.time_scale, 1.0), "hit-stop restores the time scale")
	GameFeel.fire(&"teleport")
	TestLib.check(rig.blur > 0.5, "teleport sets the motion-blur-lite")
	for i in 600:
		if rig.blur <= 0.0:
			break
		await TestLib.frames(host, 1)
	TestLib.check(rig.blur == 0.0, "blur decays")
	# reduce-motion: nothing moves
	UiSettings.s_reduce_motion = true
	FX.shake_amount = 0.0
	var fp: float = rig._fov_punch
	rig.hit_stop(0.05)
	TestLib.check(rig._stop_left == 0.0 and is_equal_approx(Engine.time_scale, 1.0), "no hit-stop under reduce-motion")
	GameFeel.fire(&"slam")
	TestLib.check(FX.shake_amount == 0.0 and rig._fov_punch <= fp + 0.001, "no shake or FOV kick under reduce-motion")
	UiSettings.s_reduce_motion = false
	# low health heartbeat in the live game
	var hb: int = rig.heartbeats
	p.hp = p.max_hp * 0.1
	for i in 900:
		if rig.heartbeats > hb:
			break
		await TestLib.frames(host, 1)
	TestLib.check(rig.heartbeats > hb, "low health pulses the haptic heartbeat")
	p.hp = p.max_hp
	# a real hit goes through the profile table
	var n1 := GameFeel.fired
	p.invuln = 0.0
	p.damage(10.0, p.global_position + Vector3(0, 0, -5))
	TestLib.check(GameFeel.fired > n1, "a hit on the hero fires feel")
	# taller hero keeps a wider aim cone, never narrower
	TestLib.check(AimAssist.cone_scale() >= 1.0 and AimAssist.cone_scale() <= 1.3, "aim cone scale stays in range")
	Engine.time_scale = 1.0
