extends RefCounted
## Wave 129 AIRFIELD fixes (w129-airdraws; owner request: inside a vehicle on the airfield over budget, plus the small airfield errors). Real main scene at a 20:9 phone window,
## touch HUD on, reward cards ON (CrateReveal._quiet = 0); the hero moves by REAL FINGERS (tests/w116_fingers.gd: InputEventScreenTouch / Drag through Input.parse_input_event).
##   doors     the hero walks up to HANGAR A and ARMY SHELTER 1 with the left thumb until the door is open: no door panel reaches past the side walls
##   animals   with the hero on the apron the wildlife fills its ring: no land animal (zebras, coyotes ...) stands on the airport pad, and a herd put there is refused
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
	for part: String in ["doors", "animals"]:
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
