extends RefCounted
## Vehicle quantum-realism paint: thin-film shimmer on hover / patrol, wear and phase-seam glow with damage, wet gloss, drift handling numbers.
## Run: tools/test.sh tests/test_vehicle_paint.gd

func run(host: Node) -> void:
	var sedan := VehicleVisual.new()
	var root := sedan.build(&"sedan", Color(0.2, 0.9, 1.0))
	host.add_child(root)
	sedan.set_paint(VehicleSpecs.COLORS[0])
	TestLib.check(not sedan.iridescent, "a sedan is not thin-film")
	var fresh := sedan.paint_state()                       # works for the older art (StandardMaterial3D) and for Cars v2 (shader parameters)
	TestLib.check(not fresh.is_empty(), "the sedan has a paint finish")
	sedan.set_damage_look(0.8)
	var hurt := sedan.paint_state()
	TestLib.check(float(hurt["roughness"]) > float(fresh["roughness"]) and float(hurt["clearcoat"]) < float(fresh["clearcoat"]), "damage scuffs the clear coat and dulls the paint")
	TestLib.check(float(hurt["glow"]) < float(fresh["glow"]) and (hurt["albedo"] as Color).v < (fresh["albedo"] as Color).v, "a badly hurt car is sooty and dull, it does not glow")
	sedan.set_damage_look(0.0)
	var r1 := float(sedan.paint_state()["roughness"])
	sedan.set_wet(1.0)
	TestLib.check(float(sedan.paint_state()["roughness"]) < r1, "wet paint is glossier")

	var hover := VehicleVisual.new()
	var hroot := hover.build(&"hover", Color(0.2, 0.9, 1.0))
	host.add_child(hroot)
	hover.set_paint(VehicleSpecs.COLORS[1])
	TestLib.check(hover.iridescent and float(hover.paint_state()["rim"]) > 0.0, "a hover car wears the iridescent film")
	hover.shimmer(0.0, 0.0)
	var e0: Color = hover.paint_state()["emission"]
	hover.shimmer(2.0, 30.0)
	TestLib.check((hover.paint_state()["emission"] as Color) != e0, "the film hue drifts with time and speed")
	var patrol := VehicleVisual.new()
	host.add_child(patrol.build(&"vael_patrol", Color(0.2, 0.9, 1.0)))
	patrol.set_paint(VehicleSpecs.COLORS[2])
	TestLib.check(patrol.iridescent, "a Vael patrol wears the film too")

	var flick := 0
	for i in 200:
		var v := VehicleVisual.new()
		v._kind = &"sedan"
		v._body_mat = StandardMaterial3D.new()
		v._setup_finish()
		if v.flicker_car:
			flick += 1
	TestLib.check(flick > 0 and flick < 60, "a few cars flicker to a second state (%d of 200)" % flick)

	TestLib.check(VehicleSpecs.DRIFT_RECOVER > 0.1 and VehicleSpecs.SMOKE_SLIP > 1.0, "drift constants exist")
	var car := Vehicle.new()
	host.add_child(car)
	car.setup(&"sport", null)
	car.activate(Vector3(0, 0, 0), 0.0)
	car.vel = -car.forward() * 20.0 + car.right() * 8.0
	car.step_drive(1.0 / 60.0, 1.0, 0.0, true)
	TestLib.check(car.drifting, "a hard slide with the handbrake smokes the tyres")
	car.queue_free()
	hroot.queue_free()
	root.queue_free()
