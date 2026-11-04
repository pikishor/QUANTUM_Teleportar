extends RefCounted
## Lighting and post FX 2 (PostFx2): district grade, tone by time of day, shadows per tier, shafts, ability kick, drips, menu switch, wired into the real scene.
## Run: tools/test.sh tests/test_post_fx2.gd (new class_name: tools/import.sh first)


const PostLayer := preload("res://scripts/fx/atmosphere_post.gd")


func run(host: Node) -> void:
	PostFx2.set_enabled(true)
	UiSettings.s_reduce_flash = false
	_test_tables()
	_test_env()
	_test_shader_source()
	await _test_live(host)
	PostFx2.set_enabled(true)


func _test_tables() -> void:
	TestLib.check(PostFx2.GRADES.size() == 4, "one grade per district")
	for n: StringName in PostFx2.DISTRICT_NAMES:
		TestLib.check(Sfx.DISTRICTS.has(n) and PostFx2.GRADES.has(n), "district %s known to audio and grade" % n)
	for i in 4:                                              # the centre of each quadrant gets (nearly) its own grade
		var pos := Vector3(100.0 if i % 2 == 1 else -100.0, 0.0, 100.0 if i >= 2 else -100.0)
		var w := PostFx2.district_weights(pos)
		TestLib.check(w[i] > 0.99 and absf(w[0] + w[1] + w[2] + w[3] - 1.0) < 0.001, "weights at quadrant %d" % i)
		TestLib.check(Sfx.district_at(pos) == i, "order matches Sfx.district_at (%d)" % i)
	var slums := PostFx2.district_grade(Vector3(-100, 0, 100))
	var towers := PostFx2.district_grade(Vector3(100, 0, 100))
	TestLib.check(float(slums["sat"]) < 0.9 and float(towers["sat"]) > 0.95, "slums are desaturated")
	TestLib.check((towers["gain"] as Vector3).z > (towers["gain"] as Vector3).x, "towers are cold")
	var mid := PostFx2.district_grade(Vector3(0, 0, 0))
	TestLib.check(float(mid["sat"]) > 0.82 and float(mid["sat"]) < 1.08, "border blends the grades")
	PostFx2.set_enabled(false)
	TestLib.check(float(PostFx2.district_grade(Vector3(-100, 0, 100))["sat"]) == 1.0 and PostFx2.shaft_amount(0.0, 0.0, 0.0) == 0.0, "switch off: neutral grade, no shafts")
	PostFx2.set_enabled(true)
	TestLib.check(PostFx2.shaft_amount(0.0, 0.0, 0.0) > PostFx2.shaft_amount(1.0, 0.0, 0.0), "shafts are stronger by day")
	TestLib.check(PostFx2.shaft_amount(0.0, 0.0, 1.0) < PostFx2.shaft_amount(0.0, 0.0, 0.0), "rain thins the shafts")
	TestLib.check(PostFx2.shaft_steps(0) == 0 and PostFx2.shaft_steps(1) > 0 and PostFx2.shaft_steps(2) > PostFx2.shaft_steps(1), "shaft steps per tier")
	TestLib.check(PostFx2.tone_white(0.0) < PostFx2.tone_white(1.0), "filmic shoulder rolls off earlier by day")
	TestLib.check(PostFx2.glow_threshold(0.9, 0.0) > PostFx2.glow_threshold(0.9, 1.0), "bloom starts higher by day")
	TestLib.check(not bool(PostFx2.SHADOW[0]["on"]) and bool(PostFx2.SHADOW[1]["on"]) and bool(PostFx2.SHADOW[2]["on"]), "shadows: off on LOW")
	TestLib.check(float(PostFx2.SHADOW[2]["dist"]) > float(PostFx2.SHADOW[1]["dist"]), "shadows reach further on HIGH")


func _test_env() -> void:
	var e := Environment.new()
	e.glow_hdr_threshold = 0.9
	PostFx2.apply_env(e, 0.0, 2)
	var day_white := e.tonemap_white
	var day_thr := e.glow_hdr_threshold
	PostFx2.apply_env(e, 1.0, 2)
	TestLib.check(e.tonemap_white > day_white and e.glow_hdr_threshold < day_thr, "env follows the time of day")
	TestLib.check(is_equal_approx(e.glow_hdr_threshold, 0.9), "night restores the base bloom threshold (no drift)")
	PostFx2.apply_env(e, 1.0, 0)
	TestLib.check(not e.ssao_enabled, "no AO on LOW")
	var sun := DirectionalLight3D.new()
	PostFx2.apply_shadow(sun, 0)
	TestLib.check(not sun.shadow_enabled, "LOW sun casts no shadow")
	PostFx2.apply_shadow(sun, 2)
	TestLib.check(sun.shadow_enabled and is_equal_approx(sun.directional_shadow_max_distance, 130.0), "HIGH shadow distance")
	sun.free()


func _test_shader_source() -> void:
	var src := FileAccess.get_file_as_string("res://assets/shaders/post_film.gdshader")
	for u in ["d_gain", "d_lift", "d_sat", "ability_amount", "shaft_amount", "shaft_steps", "sun_uv", "drip_amount", "drip_layer"]:
		TestLib.check(src.contains(u), "post shader has %s" % u)
	for k: StringName in [&"d_gain", &"d_lift", &"d_sat", &"ability_amount", &"shaft_amount", &"drip_amount"]:
		TestLib.check(PostLayer.DEFAULTS.has(k), "post defaults carry %s" % k)
	TestLib.check(float(PostLayer.TIER_MASK[0][&"shaft_amount"]) == 0.0 and float(PostLayer.TIER_MASK[0][&"drip_amount"]) == 0.0, "LOW pays for none of it")


func _test_live(host: Node) -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 3)
	for i in 600:
		if Game.state == &"play" and is_instance_valid(Game.player):
			break
		await TestLib.frames(host, 1)
	var atm := Game.atmosphere as Atmosphere
	var p: Node3D = Game.player
	if atm == null or p == null:
		TestLib.check(false, "atmosphere and player present in the main scene")
		return
	Game.set_quality(2)
	atm.set_quality(2)
	atm.post.visible = true
	# district grade follows the hero
	p.global_position = Vector3(-100, 1, 100)
	atm._look_acc = 1.0
	atm._look_step(0.2)
	TestLib.check(is_equal_approx(float(atm.post.get_param(&"d_sat")), float(PostFx2.GRADES[&"slums"]["sat"])), "slums grade applied to the post pass")
	p.global_position = Vector3(100, 1, 100)
	atm._look_acc = 1.0
	atm._look_step(0.2)
	TestLib.check(is_equal_approx(float(atm.post.get_param(&"d_sat")), float(PostFx2.GRADES[&"towers"]["sat"])), "towers grade applied after moving")
	# ability pulse
	atm.ability_level = 0.0
	PostFx2.pulse(1.0)
	TestLib.check(atm.ability_level > 0.9, "ability pulse reaches the atmosphere")
	atm._look_step(0.05)
	TestLib.check(float(atm.post.effective(&"ability_amount")) > 0.5, "ability film kick on HIGH")
	atm.set_quality(1)
	TestLib.check(float(atm.post.effective(&"drip_amount")) == 0.0 and float(atm.post.effective(&"ability_amount")) > 0.0, "MED: kick yes, drips no")
	atm.set_quality(2)
	TestLib.check(float(atm.post.effective(&"drip_amount")) > 0.0 and float(atm.post.effective(&"lens_amount")) > 0.0, "HIGH: lens drops and drips")
	for i in 400:                                            # decays by itself, in simulated time
		atm._look_step(0.05)
		if atm.ability_level <= 0.0:
			break
	TestLib.check(atm.ability_level == 0.0 and float(atm.post.get_param(&"ability_amount")) == 0.0, "kick fades out")
	UiSettings.s_reduce_flash = true
	PostFx2.pulse(1.0)
	TestLib.check(atm.ability_level == 0.0, "reduce-flash drops the kick")
	UiSettings.s_reduce_flash = false
	# the real verb fires the pulse
	var q = p.get("quantum")
	if q != null and p.get("energy") != null:
		p.energy = p.max_energy
		p.global_position = Vector3(0, 1, 0)
		var before := atm.ability_level
		var tp = q.call("blink")
		if tp:
			q.call("blink")
		TestLib.check(atm.ability_level > before or tp == false, "QUANTUM TELEPORT kicks the film")
	# menu switch
	TestLib.check(TestMode.set_post_fx2(false) != "" and not PostFx2.enabled, "test menu switches the look off")
	TestMode.set_post_fx2(true)
	TestLib.check(PostFx2.enabled, "and on again")
	# the day/night apply carries the env changes
	var city := Game.world
	var dn = city.get("day_night") if city != null else null
	if dn != null:
		dn.set_hour(12.0)
		var env: Environment = dn.env_owner.get("env")
		var wd := env.tonemap_white
		dn.set_hour(0.0)
		TestLib.check(env.tonemap_white > wd, "DayNight drives the tone-mapping white point")
	main.queue_free()
