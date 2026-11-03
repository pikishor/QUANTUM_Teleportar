extends RefCounted
## Day/night cycle (headless). Run: tools/test.sh tests/test_day_night.gd

const CityEnvScript := preload("res://scripts/world/city_env.gd")


func run(host: Node) -> void:
	TestLib.check(is_equal_approx(DayNight.CYCLE, 720.0), "the full cycle is 12 minutes")
	TestLib.check(DayNight.night_amount(2.0) > 0.99 and DayNight.night_amount(12.0) < 0.01, "night at 02:00, day at noon")
	var n1 := DayNight.night_amount(18.5)
	var n2 := DayNight.night_amount(19.0)
	TestLib.check(n1 > 0.0 and n2 > n1 and n2 < 1.0, "dusk darkens gradually (%.2f -> %.2f)" % [n1, n2])
	TestLib.check(DayNight.night_amount(5.0) > DayNight.night_amount(6.0), "dawn brightens")
	TestLib.check(DayNight.twilight(6.0) > 0.9 and DayNight.twilight(12.0) == 0.0, "twilight peaks at sunrise only")
	var dmin := 9.0
	var dmax := 0.0
	for i in 96:
		var d := DayNight.density_for(float(i) * 0.25)
		dmin = minf(dmin, d)
		dmax = maxf(dmax, d)
	TestLib.check(dmin >= 0.65 and dmax <= 1.2 and dmax - dmin > 0.15, "traffic density varies slightly by hour (%.2f .. %.2f)" % [dmin, dmax])
	TestLib.check(DayNight.clock_text(7.5) == "07:30" and DayNight.clock_text(24.0) == "00:00", "clock text")
	TestLib.check(DayNight.light_dir(12.0).y > DayNight.light_dir(7.0).y and DayNight.light_dir(0.0).y > 0.0, "light is highest at noon and never below the horizon")

	var root := Node3D.new()
	host.add_child(root)
	var ce := CityEnvScript.new()
	ce.build(root)
	var lights := 0
	for c in root.get_children():
		if c is DirectionalLight3D:
			lights += 1
	TestLib.check(lights == 1, "one directional light")
	var dn := DayNight.new()
	root.add_child(dn)
	dn.setup(ce, 0)
	dn.set_hour(1.0)
	var night_e: float = ce.sun.light_energy
	var night_c: Color = ce.sun.light_color
	var night_zen: Color = ce.sky_mat.get_shader_parameter(&"zenith_color")
	dn.set_hour(12.0)
	TestLib.check(ce.sun.light_energy > night_e + 0.2, "the sun is brighter than the moon (%.2f vs %.2f)" % [ce.sun.light_energy, night_e])
	TestLib.check(ce.sun.light_color.r > night_c.r + 0.2, "the sun is warmer than the moon")
	var day_zen: Color = ce.sky_mat.get_shader_parameter(&"zenith_color")
	TestLib.check(day_zen.b > night_zen.b + 0.2, "the sky is blue by day")
	TestLib.check(dn.night < 0.05, "night amount is ~0 at noon")
	dn.set_hour(23.0)
	TestLib.check(dn.night > 0.95, "night amount is ~1 at 23:00")
	# the clock advances in play, and stops when frozen or paused
	Game.state = &"play"
	dn.set_hour(10.0)
	dn._process(30.0)
	TestLib.check(absf(dn.hour - 11.0) < 0.01, "30 s advance one hour (%.2f)" % dn.hour)
	dn.frozen = true
	dn._process(30.0)
	TestLib.check(absf(dn.hour - 11.0) < 0.01, "frozen: the hour holds")
	dn.frozen = false
	UiSettings.s_freeze_time = true
	dn._process(30.0)
	TestLib.check(absf(dn.hour - 11.0) < 0.01, "the freeze setting holds the hour")
	UiSettings.s_freeze_time = false
	Game.state = &"menu"
	dn._process(30.0)
	TestLib.check(absf(dn.hour - 11.0) < 0.01, "no advance outside play")
	var cf := UiSettings.new("user://test_day_night_settings.cfg")
	cf.freeze_time = true
	cf.save()
	TestLib.check(UiSettings.new("user://test_day_night_settings.cfg").freeze_time, "the freeze setting persists")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_day_night_settings.cfg"))
	RenderingServer.global_shader_parameter_set(&"night", 1.0)
	root.queue_free()
