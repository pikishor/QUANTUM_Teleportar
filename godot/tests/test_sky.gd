extends RefCounted
## Sky and atmosphere (headless). Run: tools/test.sh tests/test_sky.gd

const CityEnvScript := preload("res://scripts/world/city_env.gd")


func run(host: Node) -> void:
	var noon := DayNight.sky_look(12.0, &"clear", 1)
	var night := DayNight.sky_look(1.0, &"clear", 1)
	var storm := DayNight.sky_look(1.0, &"storm", 1)
	TestLib.check(noon["day"] > 0.95 and night["day"] < 0.05, "day factor follows the hour")
	TestLib.check(night["aurora_amount"] > 0.5 and noon["aurora_amount"] == 0.0, "quantum ribbons only at night")
	TestLib.check(storm["aurora_amount"] < night["aurora_amount"] and storm["star_amount"] < night["star_amount"], "storm hides ribbons and stars")
	TestLib.check(DayNight.sky_look(1.0, &"clear", 0)["aurora_amount"] == 0.0 and DayNight.sky_look(1.0, &"clear", 0)["lod"] == 0.0, "LOW has no ribbons and a cheaper sky")
	TestLib.check(night["planet_amount"] > 0.5 and noon["planet_amount"] == 0.0, "planet silhouette at night only")
	TestLib.check(DayNight.sky_look(6.0, &"clear", 1)["twilight_amount"] > 0.9, "dawn twilight")
	TestLib.check(storm["cloud_cover"] > night["cloud_cover"], "weather thickens the clouds")

	var root := Node3D.new()
	host.add_child(root)
	var ce := CityEnvScript.new()
	ce.build(root)
	var dn := DayNight.new()
	root.add_child(dn)
	dn.setup(ce, 1)
	var prev: StringName = Weather.current
	Weather.current = &"clear"
	var fogs := []
	for h in [5.5, 12.0, 18.5, 1.0]:
		dn.set_hour(h)
		var sm: ShaderMaterial = ce.sky_mat
		TestLib.check(absf(float(sm.get_shader_parameter(&"day")) - (1.0 - DayNight.night_amount(h))) < 0.01, "sky day uniform at %.1f" % h)
		fogs.append(ce.env.fog_light_color)
	TestLib.check(not fogs[1].is_equal_approx(fogs[3]), "fog colour differs between noon and night")
	dn.set_hour(12.0)
	var clear_fog: Color = ce.env.fog_light_color
	Weather.current = &"storm"
	dn.apply()
	TestLib.check(ce.env.fog_light_color.s < clear_fog.s + 0.001 and float(ce.sky_mat.get_shader_parameter(&"overcast")) > 0.9, "storm greys the fog and overcasts the sky")
	Weather.current = prev
	var sh: Shader = ce.sky_mat.shader
	TestLib.check(sh.code.contains("aurora_amount") and sh.code.contains("skyline_amount"), "shader has the new layers")
	root.queue_free()
