extends RefCounted
## Lighting polish (headless). Run: tools/test.sh tests/test_lighting_polish.gd

func run(host: Node) -> void:
	var ev := LightingPolish.window_mood(20.0)
	var dp := LightingPolish.window_mood(3.5)
	var dy := LightingPolish.window_mood(12.0)
	TestLib.check(ev.r > ev.b + 0.15, "evening windows are warm")
	TestLib.check(dp.b > dp.r, "pre-dawn windows are cool")
	TestLib.check(dp.a < ev.a - 0.1 and dp.a >= 0.3, "small hours thin out lit windows (%.2f < %.2f)" % [dp.a, ev.a])
	TestLib.check(ev.a > 0.95 and dy.a > 0.0, "evening is fully lit")
	var lo := 9.0
	var hi := 0.0
	var drops := 0
	for i in 400:
		var f := LightingPolish.flicker(float(i) * 0.125, 0.37)
		lo = minf(lo, f)
		hi = maxf(hi, f)
		if f < 0.3:
			drops += 1
	TestLib.check(hi <= 1.0 and lo >= 0.0 and hi - lo > 0.1, "neon flickers (%.2f .. %.2f)" % [lo, hi])
	TestLib.check(drops < 20, "dropouts are rare")
	TestLib.check(LightingPolish.glow_for(1.0, 1) > LightingPolish.glow_for(0.0, 1) + 0.2, "bloom is weaker by day")
	TestLib.check(LightingPolish.glow_for(1.0, 0) <= LightingPolish.glow_for(1.0, 2), "LOW blooms no more than HIGH")

	var heads: Array = [Vector3(0, 7, 0), Vector3(20, 7, 5), Vector3(-9, 7, 14)]
	var mesh := LightingPolish.build_cones(heads)
	TestLib.check(mesh.get_surface_count() == 1, "all cones merge into one surface")
	var arr := mesh.surface_get_arrays(0)
	TestLib.check((arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() == 3 * LightingPolish.CONE_SIDES * 3, "6 triangles per lamp")

	var scene := load("res://scenes/world.tscn") as PackedScene
	TestLib.check(scene != null, "world scene loads")
	if scene == null:
		return
	var w := scene.instantiate()
	host.add_child(w)
	await host.get_tree().process_frame
	var city := w as City
	TestLib.check(city != null and city.lamp_cones != null, "city owns merged lamp cones")
	if city != null and city.lamp_cones != null:
		city.set_quality(0)
		TestLib.check(not city.lamp_cones.visible, "no cones on LOW")
		city.set_quality(1)
		TestLib.check(city.lamp_cones.visible, "cones on MED")
		var n := 0
		for c in city.get_children():
			if c.name == "LampCones":
				n += 1
		TestLib.check(n == 1, "exactly one cone draw")
		city.day_night.set_hour(3.5)
		var m: Color = city.day_night.mood
		TestLib.check(m.a < 0.9 and m.b > m.r, "DayNight pushes the small-hours mood (a=%.2f)" % m.a)
	w.queue_free()
