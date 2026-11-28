extends RefCounted
## Wave 129 AIRFIELD fixes (w129-airdraws; owner request: inside a vehicle on the airfield over budget, plus the small airfield errors). Real main scene at a 20:9 phone window,
## touch HUD on, reward cards ON (CrateReveal._quiet = 0); the hero moves by REAL FINGERS (tests/w116_fingers.gd: InputEventScreenTouch / Drag through Input.parse_input_event).
##   doors     the hero walks up to HANGAR A and ARMY SHELTER 1 with the left thumb until the door is open: no door panel reaches past the side walls
##   animals   with the hero on the apron the wildlife fills its ring: no land animal (zebras, coyotes ...) stands on the airport pad, and a herd put there is refused
##   picker    the hero walks into HANGAR A by the thumb: a PLANES chip shows; a finger on it lists the planes that fit through the door, a finger on a name rolls that plane
##             out onto the apron in front of the door, and a finger on ENTER boards it
##   cockpit   boarded by a finger on ENTER, VIEW tapped to the helicopter cockpit, the left thumb on the move pad: no cockpit shape is painted over the pad, the panel starts
##             right of it, and every number shows once (no ALT / ROTOR row on the plate, no speed plate, no ALT / HDG label beside the horizon: the gauges carry them);
##             in the chase view the plate drops its ALT row (the horizon's altitude label carries it)
## W129A_OLD=1 runs the wave 128 airfield (AirDraws.old): every [old fails] check must then fail.      W129_PARTS=doors,animals   a subset
## Run: tools/test.sh tests/test_airfield_w129.gd

const TIMEOUT_SECONDS := 140
const Fingers := preload("res://tests/w116_fingers.gd")
var host: Node
var fg: Fingers
var p: Player
var vm: VehicleManager


func _f(n: int) -> void:
	await TestLib.frames(host, n)


func _until(cond: Callable, frames: int) -> bool:
	for i in frames:
		if cond.call():
			return true
		await _f(1)
	return cond.call()


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	var win_size := host.get_window().size
	host.get_window().size = Vector2i(1200, 540)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await _f(20)
	Game.state = &"play"
	CrateReveal._quiet = 0
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	fg = Fingers.new(host)
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	TestMode.god = true
	p.max_hp = 1.0e6
	p.hp = 1.0e6
	TestLib.check(fg.tc != null and fg.tc.controls_on, "the touch HUD is on")
	var parts := OS.get_environment("W129_PARTS").split(",", false)
	for part: String in ["doors", "animals", "picker", "cockpit"]:
		if parts.is_empty() or parts.has(part):
			await call("_" + part)
	fg.up_all()
	CrateReveal._quiet = -1
	host.get_window().size = win_size
	Game.force_touch = false
	main.queue_free()
	await _f(2)


## Puts the hero `back` m out in front of a door, facing it (setup), then walks him in with the left thumb until the door is fully open.
func _walk_to_door(id: StringName, back: float) -> float:
	var s := Hangars.site(id)
	var df := Hangars.door_frame(s)
	var c: Vector3 = df["c"]
	var out: Vector3 = df["out"]
	var st := Airport.to_world(c + out * back)
	st.y = TerrainHeight.height_at(st.x, st.z) + 0.3
	var tw := Airport.to_world(c)
	p.teleport_to(st)
	var d := tw - st
	p.camera_rig.reset_view(atan2(-d.x, -d.z), -0.1)
	await _f(30)
	TestLib.check(Hangars.Doors.open_of(id) < 0.05, "%s: the door is shut while the hero stands %.0f m away" % [s["name"], back])
	fg.stick(Vector2(0.0, -1.0))
	var opened := await _until(func() -> bool: return Hangars.Doors.open_of(id) >= 0.999, 900)
	fg.stick(Vector2.ZERO)
	var walked := Vector2(p.global_position.x - st.x, p.global_position.z - st.z).length()
	TestLib.check(opened, "%s: walking up by the thumb opens the door (open %.2f, walked %.0f m)" % [s["name"], Hangars.Doors.open_of(id), walked])
	return float(df["span"]) * 0.5


func _doors() -> void:
	for id: StringName in [&"hangar_a", &"shelter_1"]:
		var half := await _walk_to_door(id, 48.0)
		var ext := Hangars.leaf_extent(id)
		TestLib.check(ext.size() == 2, "%s: the door panels are found" % id)
		if ext.size() == 2:
			var past := maxf(-float(ext[0]) - half, float(ext[1]) - half)
			TestLib.check(past <= 0.01, "[old fails] %s open: no door panel reaches past the side walls (panels %.1f .. %.1f m, walls at +-%.1f m: %.1f m past)" % [id, ext[0], ext[1], half, maxf(past, 0.0)])
			var s := Hangars.site(id)
			# the opening stays clear enough for the planes inside: at most 0.6 m of panel over each side of the opening
			var dw := float(s["dw"])
			var inner := 1.0e9
			var d := Hangars.Doors.instance
			for i in d._leaf.size():
				var l: Dictionary = d._leaf[i]
				if (l["site"] as Dictionary)["id"] != id:
					continue
				var xf := d.leaf_xf(i)
				var a := (xf.origin - (Hangars.door_frame(s)["c"] as Vector3)).dot(Hangars.door_frame(s)["along"])
				inner = minf(inner, absf(a) - xf.basis.x.length() * 0.5)
			TestLib.check(inner >= dw * 0.5 - 0.6, "%s open: the opening is clear (panels from %.1f m, the opening ends at %.1f m)" % [id, inner, dw * 0.5])


func _animals() -> void:
	var ww := WildlifeWorld.instance
	TestLib.check(ww != null, "the wildlife runs")
	if ww == null:
		return
	ww.clear()
	var spot := Airport.to_world(Vector3(1290.0, 0.0, -560.0))                     # the east strip beside the runway (the plane line, the heli line)
	spot.y = TerrainHeight.height_at(spot.x, spot.z)
	p.teleport_to(spot + Vector3(0.0, 0.3, 0.0))
	await _f(10)
	var on_pad := 0
	var seen := 0
	for round in 3:
		ww.rng.seed = 1290 + round
		ww.settle(spot, 60)
		for c: Critter in ww.critters:
			if c.cls == AnimalSpecies.LAND or c.cls == AnimalSpecies.SMALL:
				seen += 1
				if Airport.inside(c.position.x, c.position.z, 0.0):
					on_pad += 1
		ww.clear()
	print("animals: %d land / small bodies spawned round the east strip, %d on the pad" % [seen, on_pad])
	TestLib.check(on_pad == 0, "[old fails] round the airfield the wildlife fills its ring and no land animal stands on the airport pad (%d of %d)" % [on_pad, seen])
	var herd := ww.spawn_group(&"zebra", spot + Vector3(6.0, 0.0, 0.0), 4)
	ww.clear()
	TestLib.check(herd == 0, "[old fails] a zebra herd put on the apron is refused (%d spawned)" % herd)
	# away from the airfield the herds still come (the rule is local)
	var far := Vector3(1750.0, 0.0, 850.0)
	far.y = TerrainHeight.height_at(far.x, far.z)
	ww.rng.seed = 77
	ww.settle(far, 60)
	var land := ww.census(far, 200.0, AnimalSpecies.LAND).size()
	ww.clear()
	TestLib.check(land > 0, "out on the outskirts land animals still spawn (%d)" % land)


func _tap(action: StringName) -> bool:
	if not fg.press(2, action):
		return false
	await _f(4)
	fg.up(2)
	await _f(6)
	return true


func _cockpit() -> void:
	var at := Airport.to_world(Vector3(1240.0, 0.0, -700.0))
	at.y = TerrainHeight.height_at(at.x, at.z) + 0.3
	p.teleport_to(at)
	await _f(10)
	vm._fixed_n += 1
	var hv := vm.spawn_parked(&"h_police", at + Vector3(0.0, 0.0, -9.0), 0.0)      # setup: a helicopter beside the hero
	if hv != null:
		hv.set_meta(&"hold", true)
	vm._count_fixed()
	TestLib.check(hv != null, "a police helicopter stands 9 m from the hero")
	if hv == null:
		return
	var d := hv.global_position - p.global_position
	p.camera_rig.reset_view(atan2(-d.x, -d.z), -0.1)
	await _f(3)
	fg.stick(Vector2(0.0, -1.0))
	await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 400)
	fg.stick(Vector2.ZERO)
	await _f(3)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == hv, 90)
	TestLib.check(p.vehicle == hv, "a finger on ENTER boards the helicopter")
	if p.vehicle != hv:
		return
	await _f(20)
	# the chase view: the altitude is beside the horizon, the plate does not repeat it
	var rows := " | ".join(AirDraws.last_rows.map(func(r: Dictionary) -> String: return String(r["text"])))
	var alt_label := FlightHud.labels.any(func(t: String) -> bool: return t.ends_with(" M") and not t.begins_with("RWY"))
	TestLib.check(alt_label and not rows.contains("ALT "), "[old fails] chase view: the altitude shows once, beside the horizon (labels %s; plate: %s)" % [str(FlightHud.labels), rows])
	for i in 3:
		if p.camera_rig.veh_view == 2:
			break
		await _tap(&"veh_view")
	await _until(func() -> bool: return HeliCockpit.active(), 30)
	TestLib.check(HeliCockpit.active(), "VIEW tapped by a finger reaches the cockpit (view %d)" % p.camera_rig.veh_view)
	fg.stick(Vector2(0.0, -0.3))                                                 # the left thumb rests on the move pad
	await _f(12)
	var hc := HeliCockpit.instance
	var z := hc.stick_zone()
	TestLib.check(z.size() == 2, "the move pad is on screen")
	for win: Vector2i in [Vector2i(1280, 720), Vector2i(1200, 540)]:          # a 16:9 phone and the 20:9 one: the pad must stay clear on both
		host.get_window().size = win
		await _f(6)
		await _pad_clear(hc, hv, win)
	rows = " | ".join(AirDraws.last_rows.map(func(r: Dictionary) -> String: return String(r["text"])))
	var labels := str(FlightHud.labels)
	var rx := RegEx.create_from_string("ROTOR \\d+ %")
	TestLib.check(not rows.contains("ALT ") and rx.search(rows) == null, "[old fails] cockpit: the plate does not repeat ALT or the ROTOR %% (the gauges show them): %s" % rows)
	TestLib.check(not AirDraws.speedo_drawn, "[old fails] cockpit: no speed plate under the SPEED gauge")
	TestLib.check(not labels.contains("HDG") and not FlightHud.labels.any(func(t: String) -> bool: return t.ends_with(" M") and not t.begins_with("RWY")), "[old fails] cockpit: no ALT / HDG label beside the horizon (%s)" % labels)
	fg.stick(Vector2.ZERO)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == null, 90)


func _pad_clear(hc: HeliCockpit, hv: Vehicle, win: Vector2i) -> void:
	var z := hc.stick_zone()
	if z.size() != 2:
		TestLib.check(false, "%s: the move pad is on screen" % str(win))
		return
	var zc: Vector2 = z[0]
	var zr: float = z[1]
	var pr := hc.panel_rect()
	var gap := pr.position.x - (zc.x + zr) if zc.x < hc._vp().x * 0.5 else (zc.x - zr) - pr.end.x
	var over := hc.pad_overlaps()
	var sh := hc.frame_shapes(hv)
	if over > 0:
		for k: String in sh:
			if hc._hits_pad(sh[k]):
				print("  over the pad: %s %s (pad %s r %.0f, vp %s)" % [k, str(sh[k]), str(zc), zr, str(hc._vp())])
	var pl: PackedVector2Array = sh["pl"]
	TestLib.check(over == 0, "[old fails] %s: no cockpit shape (pillar, seat bolster, dash) lies over the move pad (%d do)" % [str(win), over])
	TestLib.check(pl[2].y - pl[1].y > 60.0 and sh.has("dash"), "%s: the canopy pillar and the dash are still there (pillar %.0f px long)" % [str(win), pl[2].y - pl[1].y])
	TestLib.check(gap >= 0.0, "%s: the instrument panel starts beside the move pad, not over it (gap %.0f px)" % [str(win), gap])


func _tap_at(pos: Vector2) -> void:
	fg.down(2, pos)
	await _f(3)
	fg.up(2)
	await _f(4)


func _picker() -> void:
	await _walk_to_door(&"hangar_a", 30.0)
	var site := Hangars.site(&"hangar_a")
	fg.stick(Vector2(0.0, -1.0))                                                # on through the open door, into the hangar
	var inside := await _until(func() -> bool: return HangarPicker.site_id() == &"hangar_a" or Hangars.inside(site, Airport.to_local(p.global_position)), 400)
	await _f(30)
	fg.stick(Vector2.ZERO)
	await _f(10)
	var hp := HangarPicker.instance
	TestLib.check(inside, "the hero walks into HANGAR A by the thumb")
	TestLib.check(hp != null and hp.chip.visible, "[old fails] inside the hangar the PLANES chip shows")
	if hp == null or not hp.chip.visible:
		return
	await _tap_at(hp.chip.get_global_rect().get_center())
	TestLib.check(hp.open and hp.panel.visible, "a finger on PLANES opens the list (%d planes fit HANGAR A)" % HangarPicker.kinds_for(site).size())
	var fits := HangarPicker.kinds_for(site)
	TestLib.check(fits.size() >= 8 and not fits.has(&"p_jumbo") and fits.has(&"p_cub"), "the list holds the planes that fit the 38 m door (%d, no jumbo)" % fits.size())
	if not hp.open or hp.grid.get_child_count() == 0:
		return
	var b := hp.grid.get_child(hp.grid.get_child_count() - 1) as Button
	await _f(2)
	var kind: StringName = b.get_meta(&"kind")
	await _tap_at(b.get_global_rect().get_center())
	await _f(10)
	var v: Vehicle = hp.picked.get(&"hangar_a")
	var door_w := Airport.to_world(Hangars.door_frame(site)["c"])
	TestLib.check(v != null and is_instance_valid(v) and v.kind == kind and Vector2(v.global_position.x - door_w.x, v.global_position.z - door_w.z).length() < 35.0 and not hp.open,
		"a finger on %s rolls it out in front of the door (%.0f m from it), the list closes" % [VehicleSpecs.name_of(kind), Vector2(v.global_position.x - door_w.x, v.global_position.z - door_w.z).length() if v != null else -1.0])
	if v == null:
		return
	var d := v.global_position - p.global_position
	p.camera_rig.reset_view(atan2(-d.x, -d.z), -0.1)
	await _f(3)
	fg.stick(Vector2(0.0, -1.0))
	await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 500)
	fg.stick(Vector2.ZERO)
	await _f(3)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == v, 90)
	TestLib.check(p.vehicle == v, "a finger on ENTER boards the picked %s" % VehicleSpecs.name_of(kind))
	if p.vehicle != null:
		await _tap(&"interact")
		await _until(func() -> bool: return p.vehicle == null, 90)
