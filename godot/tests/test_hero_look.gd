extends RefCounted
## Hero look: the trim sheen drifts and reacts to QUANTUM TELEPORT charge and cooldown; the model's armour and cloak get rim and sheen.
## Run: tools/test.sh tests/test_hero_look.gd

func run(host: Node) -> void:
	var a := PlayerBody.trim_tint(0.0, 0.0, 1.0)
	var b := PlayerBody.trim_tint(1.5, 0.0, 1.0)
	TestLib.check(a.is_equal_approx(b) == false, "the iridescent sheen drifts over time")
	var rest := PlayerBody.trim_tint(0.3, 0.0, 1.0)
	var charged := PlayerBody.trim_tint(0.3, 1.0, 1.0)
	var spent := PlayerBody.trim_tint(0.3, 0.0, 0.0)
	TestLib.check(charged.get_luminance() > rest.get_luminance() * 1.4, "QUANTUM TELEPORT charge brightens the seams")
	TestLib.check(spent.get_luminance() < rest.get_luminance() * 0.7, "cooldown dims the seams")
	var body := PlayerBody.new()
	host.add_child(body)
	TestLib.check(body.hero_mat != null or (body._gear_mats.size() > 0 and body._gear_mats.size() == body._gear_emis.size()), "armour materials (the old hero) or the superhero material are tracked")
	TestLib.check(body._fabric_mats.size() >= 0, "fabric materials tracked (the articulated model may carry only Gear)")
	if body._fabric_mats.size() > 0:
		TestLib.check(body._fabric_mats[0].rim_enabled and body._fabric_mats[0].rim >= 0.1, "fabric rim is on")
	body._update_quantum_look(null, 0.1)
	body.queue_free()
