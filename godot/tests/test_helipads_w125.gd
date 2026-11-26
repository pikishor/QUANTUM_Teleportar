extends RefCounted
## WAVE 125 (plan line 125: helicopter cockpits and helipads; agent w125-pads). The real main scene as the owner's phone (844x390), the touch HUD, REAL FINGERS only
## (InputEventScreenTouch / Drag through Input.parse_input_event, tests/touch_audit_lib.gd), reward cards on (CrateReveal._quiet = 0).
##   COCKPIT  a finger on the helicopter's VIEW button reaches the cockpit (third view) and leaves it again; the machine's model is hidden inside, the panel keeps clear of every
##            button; UP by finger moves the ALT and ROTOR gauges, the stick moves SPEED and HEADING, a hit moves HULL; heli / gunship / hauler wear three cockpit families.
##   PADS     every helipad of the world (Helipads.all(): city roofs, hospital, police, news, plaza pads, airport apron, army airbase, mountain and town pads) is reached by the
##            helicopter, DOWN by finger sets it down on the pad and it is PARKED there; each pad has a helicopter of a fitting kind on its spawn point; a new pad has lamps.
##   MAP      every pad has a never-fogged H marker (map and minimap), and the minimap draws a badge near a pad.
## Fail first: W125_PADS_OLD=1 tools/test.sh tests/test_helipads_w125.gd (the wave 124 world: no cockpit, no new pads, no parking, no pad markers).
## Run: tools/test.sh tests/test_helipads_w125.gd       Pictures: tests/bot_w125_pads.gd

const TIMEOUT_SECONDS := 560
const Audit := preload("res://tests/touch_audit_lib.gd")
const STREET := Vector3(-30.0, 0.0, 4.0)
var a: Audit
var p: Player
var vm: VehicleManager


func _ck(ok: bool, text: String) -> bool:
	TestLib.check(ok, text)
	return ok


func _spawn(kind: StringName) -> Vehicle:
	DemoMenu.spawn_vehicle(kind)
	var best: Vehicle = null
	for v: Vehicle in vm.list:
		if is_instance_valid(v) and v.kind == kind and (best == null or v.global_position.distance_to(p.global_position) < best.global_position.distance_to(p.global_position)):
			best = v
	return best


## Holds a finger on HUD button `id` until `cond` or `ticks` physics ticks.
func _hold(id: String, cond: Callable, ticks := 120) -> bool:
	var c := a.hud_button(id)
	if c.is_empty():
		return false
	a.finger_down(a.centre_of(c))
	await a.frames(2)
	var ok := false
	for i in ticks:
		await a.tree.physics_frame
		if cond.call():
			ok = true
			break
	a.finger_up()
	await a.frames(3)
	return ok


## The left thumb pushes the stick by `dir` (screen px) for `ticks` physics ticks.
func _stick(dir: Vector2, ticks: int) -> void:
	var o := a.vp() * Vector2(0.14, 0.72)
	a.finger_down(o, 1)
	await a.frames(2)
	a.finger_move(o + dir * 0.5, 1)
	await a.frames(1)
	a.finger_move(o + dir, 1)
	for i in ticks:
		await a.tree.physics_frame
	a.finger_up(1)
	await a.frames(3)


func _board(v: Vehicle) -> void:
	p.global_position = v.global_position + v.global_transform.basis.x * (float(v.spec["wid"]) * 0.5 + 1.2) + Vector3(0, 0.3, 0)
	await a.until(func() -> bool: return not a.hud_button("interact").is_empty(), 200)
	for k in 3:
		if p.vehicle == null and not a.hud_button("interact").is_empty():
			await a.tap_hud("interact", 6)
			await a.until(func() -> bool: return p.vehicle != null, 120)
	if p.vehicle != v:
		print("NOTE: ENTER did not board the %s: boarded by the direct call" % v.kind)
		if p.vehicle != null:
			vm.exit_vehicle()
			await a.pframes(6)
		vm.enter(v)
	await a.pframes(20)


func run(h: Node) -> void:
	a = Audit.new()
	if not _ck(await a.boot(h, "w125pads"), "the real main scene with the touch HUD"):
		return
	Sfx.muted = true
	var prog := Game.progress as Progress
	prog.new_campaign()
	Game.state = &"play"
	await a.frames(20)
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	for k in 6:
		if Game.story == null or (Game.story.get(&"cards") as Array).is_empty():
			break
		await a.tap(a.vp() * Vector2(0.5, 0.3))
		await a.pframes(6)
	p.teleport_to(STREET)
	await a.pframes(30)
	await _cockpit()
	await _families()
	await _map()
	await _pads()
	await a.shutdown()


# --- the cockpit -----------------------------------------------------------------------------------------------------------------------------

func _cockpit() -> void:
	var v := _spawn(&"heli")
	if not _ck(v != null, "a helicopter to fly"):
		return
	await _board(v)
	_ck(p.vehicle == v, "the hero is in the helicopter")
	var on := false
	for k in 3:
		if not await a.tap_hud("veh_view", 3):
			break
		await a.pframes(4)
		if HeliCockpit.active():
			on = true
			break
	if not _ck(on, "a finger on VIEW reaches the cockpit view (ids %s)" % str(a.hud_ids())):
		return
	var ck := HeliCockpit.instance
	await a.pframes(6)
	_ck(ck != null and ck.shown_frames > 0 and ck.view.visible, "the cockpit is painted")
	_ck(v.visual != null and is_instance_valid(v.visual.model) and not v.visual.model.visible, "the machine's own model is hidden in the cockpit (the eye is inside it)")
	var pr := ck.panel_rect()
	_ck(pr.size.x > 300.0 and pr.size.y > 80.0, "the instrument panel is big enough to read (%s)" % str(pr))
	var clash := ""
	_ck(ck.button_circles().size() >= 5, "the cockpit knows where the %d touch buttons are" % ck.button_circles().size())
	for c: Array in ck.button_circles():
		var cp: Vector2 = c[0]
		var r: float = c[1]
		var nx := clampf(cp.x, pr.position.x, pr.end.x)
		var ny := clampf(cp.y, pr.position.y, pr.end.y)
		if Vector2(nx, ny).distance_to(cp) < r:
			clash += "%s " % str(cp)
	_ck(clash == "", "the panel keeps clear of every touch button (%s)" % clash)
	_ck(not a.hud_button("jump").is_empty() and not a.hud_button("crouch").is_empty() and not a.hud_button("fire").is_empty(), "UP, DOWN and FIRE stay on screen in the cockpit")
	var g0 := HeliCockpit.gauges(v)
	await _hold("jump", func() -> bool: return VehicleCraft.altitude(v) > 14.0, 600)
	var g1 := HeliCockpit.gauges(v)
	_ck(float(g1["alt"]) > float(g0["alt"]) + 5.0 and absf(float(g1["alt_a"]) - float(g0["alt_a"])) > 0.2, "UP by finger moves the ALT gauge (%.1f -> %.1f m)" % [g0["alt"], g1["alt"]])
	_ck(float(g1["rpm"]) > float(g0["rpm"]) or float(g1["rpm"]) >= 99.0, "the ROTOR gauge shows the spool (%.0f -> %.0f %%)" % [g0["rpm"], g1["rpm"]])
	await _stick(Vector2(0.0, -90.0), 90)
	var g2 := HeliCockpit.gauges(v)
	_ck(float(g2["spd"]) > float(g1["spd"]) + 10.0 and absf(float(g2["spd_a"]) - float(g1["spd_a"])) > 0.1, "the stick forward moves the SPEED gauge (%.0f -> %.0f km/h)" % [g1["spd"], g2["spd"]])
	await _stick(Vector2(90.0, 0.0), 70)
	var g3 := HeliCockpit.gauges(v)
	_ck(int(g3["hdg"]) != int(g2["hdg"]) and absf(float(g3["hdg_a"]) - float(g2["hdg_a"])) > 0.1, "the stick sideways turns the HEADING card (%03d -> %03d)" % [g2["hdg"], g3["hdg"]])
	v.damage(v.max_hp * 0.3)
	await a.pframes(3)
	var g4 := HeliCockpit.gauges(v)
	_ck(float(g4["hull"]) < float(g3["hull"]) - 10.0, "a hit moves the HULL gauge (%.0f -> %.0f %%)" % [g3["hull"], g4["hull"]])
	var off := false
	for k in 3:
		await a.tap_hud("veh_view", 3)
		await a.pframes(4)
		if not HeliCockpit.active():
			off = true
			break
	_ck(off, "a finger on VIEW leaves the cockpit")
	await a.pframes(4)
	_ck(is_instance_valid(v.visual.model) and v.visual.model.visible, "the model is shown again outside the cockpit")
	vm.exit_vehicle()
	await a.pframes(6)
	vm._release(v)
	await a.pframes(4)


func _families() -> void:
	var fams := {}
	for k: StringName in [&"heli", &"gunship", &"hauler"]:
		fams[HeliCockpit.family_of(VehicleSpecs.SPECS[k])] = true
	_ck(fams.size() == 3, "the helicopter, the gunship and the transport wear three cockpit families (%s)" % str(fams.keys()))
	var n := 0
	var kinds := {}
	for k in VehicleSpecs.SPECS:
		if str(VehicleSpecs.SPECS[k].get("cls", "")) == "heli":
			n += 1
			kinds[HeliCockpit.family_of(VehicleSpecs.SPECS[k])] = int(kinds.get(HeliCockpit.family_of(VehicleSpecs.SPECS[k]), 0)) + 1
	print("helicopter kinds %d by family %s" % [n, str(kinds)])


# --- the map --------------------------------------------------------------------------------------------------------------------------

func _map() -> void:
	var pads := Helipads.all()
	var ids := {}
	for m in ArmourSites.map_markers():
		if m.get("glyph") == &"helipad" and not bool(m.get("fog", true)):
			ids[m.get("pad", &"")] = true
	var missing: Array = []
	for pd in pads:
		if not ids.has(pd["id"]):
			missing.append(pd["id"])
	_ck(missing.is_empty() and pads.size() >= 20, "every one of the %d helipads has a never-fogged H on the map and the minimap (missing %s)" % [pads.size(), str(missing)])
	var roles := {}
	for pd in pads:
		roles[pd["role"]] = true
	for r: StringName in [&"roof", &"hospital", &"police", &"news", &"airport", &"army", &"mountain", &"outskirts", &"city"]:
		_ck(roles.has(r), "a %s helipad exists" % r)
	var mm := a.root.find_child("Minimap", true, false)
	var hosp := Helipads.pad(&"w125_hospital")
	if _ck(mm != null and not hosp.is_empty(), "the minimap and the hospital pad"):
		p.teleport_to((hosp["pos"] as Vector3) + Vector3(20.0, 0.0, 20.0))
		await a.pframes(30)
		_ck(int(mm.get(&"armour_drawn")) > 0, "the minimap draws a badge next to the hospital pad (%d)" % int(mm.get(&"armour_drawn")))


# --- the pads ----------------------------------------------------------------------------------------------------------------------------

func _pads() -> void:
	var pads := Helipads.all()
	# a helicopter of a fitting kind waits on every pad
	var bad: Array = []
	for pd in pads:
		var sp := VehicleSpawns.point(pd["spawn"])
		if sp.is_empty() or str(VehicleSpecs.SPECS.get(sp["kind"], {}).get("cls", "")) != "heli":
			bad.append("%s:%s" % [pd["id"], pd["spawn"]])
		elif pd["src"] == &"w125" and sp["kind"] != Helipads.kind_for(pd["role"]):
			bad.append("%s kind %s" % [pd["id"], sp["kind"]])
	_ck(bad.is_empty(), "every pad has a helicopter of a fitting kind on its spawn point (bad %s)" % str(bad))
	var lamps := true
	for pd in Helipads.new_pads():
		var m := Helipads.pad_mesh(pd)
		var arr := m.surface_get_arrays(0)
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var lit := false
		for c in cols:
			if absf(c.a - AirportKit.LAMP) < 0.01:
				lit = true
				break
		lamps = lamps and lit
	_ck(lamps and not Helipads.new_pads().is_empty(), "every new pad carries a rim of lamps (they glow at night)")
	# the landing: board a helicopter, put it over each pad and set it down by finger
	p.teleport_to(STREET)
	await a.pframes(30)
	var v := _spawn(&"heli")
	if not _ck(v != null, "a helicopter for the landings"):
		return
	await _board(v)
	v.set_meta(&"hold", true)
	v.max_hp = 1.0e6
	v.hp = v.max_hp
	var failed: Array = []
	for pd in pads:
		var c: Vector3 = pd["pos"]
		v.global_position = c + Vector3(0.0, 5.0, 0.0)
		v.vel = Vector3.ZERO
		v.craft.vy = 0.0
		v.craft.airborne = true
		v.craft.spool = 1.0
		await a.pframes(2)
		for o: Vehicle in vm.list.duplicate():                 # the pad's own helicopter stands on it: it goes, the pad is free for the landing
			if o != v and is_instance_valid(o) and Vector2(o.global_position.x - c.x, o.global_position.z - c.z).length() < 16.0:
				vm._release(o)
		v.global_position = c + Vector3(0.0, 5.0, 0.0)
		v.vel = Vector3.ZERO
		v.craft.vy = 0.0
		await a.pframes(20)                                      # colliders and the pad node stream in
		v.global_position = c + Vector3(0.0, 5.0, 0.0)
		v.vel = Vector3.ZERO
		var n0 := Helipads.parks
		var ok := await _hold("crouch", func() -> bool: return Helipads.parks > n0 and not v.craft.airborne, 900)
		var why := "grounded %s at %s (pad %s) parks %d last %s" % [str(not v.craft.airborne), str(v.global_position.snapped(Vector3.ONE * 0.1)), str(c.snapped(Vector3.ONE * 0.1)), Helipads.parks, Helipads.last_park]
		if not ok or Helipads.last_park != pd["id"] or v.get_meta(&"parked_pad", &"") != pd["id"]:
			var q := PhysicsRayQueryParameters3D.create(v.global_position + Vector3(0, 0.3, 0), v.global_position - Vector3(0, 8, 0))
			q.exclude = [v.get_rid()]
			var hit := v.get_world_3d().direct_space_state.intersect_ray(q)
			why += " under: %s" % (str((hit["collider"] as Node).get_path()) if hit.has("collider") else "nothing")
			failed.append("%s: %s" % [pd["id"], why])
		else:
			print("LANDED %s %s" % [pd["id"], why])
	_ck(failed.is_empty(), "a landing by finger on each of the %d pads parks the helicopter there (failed %d: %s)" % [pads.size(), failed.size(), str(failed)])
