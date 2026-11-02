extends RefCounted
## Vehicle quantum-realism paint: thin-film shimmer on hover / patrol, wear and phase-seam glow with damage, wet gloss, drift handling numbers.
## Run: tools/test.sh tests/test_vehicle_paint.gd

func run(host: Node) -> void:
	var sedan := VehicleVisual.new()
	var root := sedan.build(&"sedan", Color(0.2, 0.9, 1.0))
	host.add_child(root)
	sedan.set_paint(VehicleSpecs.COLORS[0])
	TestLib.check(not sedan.iridescent, "a sedan is not thin-film")
	var r0 := sedan._body_mat.roughness
	var c0 := sedan._body_mat.clearcoat
	sedan.set_damage_look(0.8)
	TestLib.check(sedan._body_mat.roughness > r0 and sedan._body_mat.clearcoat < c0, "damage scuffs the clear coat and dulls the paint")
	TestLib.check(sedan._body_mat.emission_energy_multiplier > 0.4, "a badly hurt car glows along its phase seams")
	sedan.set_damage_look(0.0)
	var r1 := sedan._body_mat.roughness
	sedan.set_wet(1.0)
	TestLib.check(sedan._body_mat.roughness < r1, "wet paint is glossier")

	var hover := VehicleVisual.new()
	var hroot := hover.build(&"hover", Color(0.2, 0.9, 1.0))
	host.add_child(hroot)
	hover.set_paint(VehicleSpecs.COLORS[1])
	TestLib.check(hover.iridescent and hover._body_mat.rim_enabled, "a hover car wears the iridescent film")
	hover.shimmer(0.0, 0.0)
	var e0 := hover._body_mat.emission
	hover.shimmer(2.0, 30.0)
	TestLib.check(hover._body_mat.emission != e0, "the film hue drifts with time and speed")
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
