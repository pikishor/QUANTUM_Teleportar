extends RefCounted
## Radio UI: the RADIO touch button (shown only while driving, one tap = Game.vehicles.radio.cycle()) and the HUD radio_text label.
## Run: tools/test.sh tests/test_radio_ui.gd

class StubPlayer extends Node3D:
	var camera_rig: Node
	var quantum: Node
	var vehicle: Node3D


class StubRadio extends Node:
	var on := false
	var station := 0
	var cycles := 0
	func cycle() -> bool:
		cycles += 1
		if not on:
			on = true
			station = 0
		elif station < 2:
			station += 1
		else:
			on = false
		return on


class StubVehicles extends Node:
	var radio: Node
	func nearest(_pos: Vector3, _r := 4.2) -> Node3D:
		return null


func run(host: Node) -> void:
	CarRadio.ensure_action()
	Game.force_touch = true
	Game.state = &"play"
	var player := StubPlayer.new()
	host.add_child(player)
	Game.player = player
	var tc := (load("res://scenes/touch_controls.tscn") as PackedScene).instantiate() as TouchControls
	host.add_child(tc)
	await TestLib.frames(host, 2)
	var radio_b := {}
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == &"radio_next":
			radio_b = b
	TestLib.check(not radio_b.is_empty(), "a RADIO button is defined")
	TestLib.check(not tc.button_visible(radio_b), "RADIO is hidden without a vehicle module")
	var vehicles := StubVehicles.new()
	var radio := StubRadio.new()
	vehicles.radio = radio
	host.add_child(vehicles)
	vehicles.add_child(radio)
	Game.vehicles = vehicles
	TestLib.check(not tc.button_visible(radio_b), "RADIO is hidden on foot")
	tc.touch_down(1, tc.call("_button_center", radio_b))
	tc.touch_up(1)
	TestLib.check(radio.cycles == 0, "a hidden RADIO button does nothing")
	var car := Node3D.new()
	host.add_child(car)
	player.vehicle = car
	TestLib.check(not tc.button_visible(radio_b), "RADIO stays out of the driving frame until MORE is opened (director round 2: a car shows DRIFT, EXIT, VIEW and MORE)")
	tc.more_open = true
	TestLib.check(tc.button_visible(radio_b), "RADIO shows while driving once MORE is open")
	# no overlap with other visible buttons (centres farther apart than the radii)
	var s := host.get_viewport().get_visible_rect().size.y / 720.0
	var rc: Vector2 = tc.call("_button_center", radio_b)
	for b: Dictionary in TouchControls.BUTTONS:
		if b != radio_b:
			var d := rc.distance_to(tc.call("_button_center", b))
			TestLib.check(d > (float(b["r"]) + float(radio_b["r"])) * s, "RADIO does not overlap %s" % b["label"])
	tc.touch_down(1, rc)
	tc.touch_up(1)
	TestLib.check(radio.cycles == 1 and radio.on and radio.station == 0, "tap cycles the radio on")
	TestLib.check(not Input.is_action_pressed(&"radio_next"), "the tap leaves no action pressed")
	tc.touch_down(1, rc)
	tc.touch_up(1)
	TestLib.check(radio.station == 1, "second tap goes to the next station")

	# HUD label
	var hud := (load("res://scenes/hud.tscn") as PackedScene).instantiate() if ResourceLoader.exists("res://scenes/hud.tscn") else null
	if hud != null:
		host.add_child(hud)
		await TestLib.frames(host, 2)
		TestLib.check(hud.call("radio_text") == "RADIO  " + CarRadio.station_name(1), "HUD label names the station (%s)" % hud.call("radio_text"))
		radio.on = false
		TestLib.check(hud.call("radio_text") == "RADIO OFF", "HUD label says RADIO OFF")
		player.vehicle = null
		TestLib.check(hud.call("radio_text") == "", "HUD label is empty on foot")
		player.vehicle = car
		Game.vehicles = null
		TestLib.check(hud.call("radio_text") == "", "HUD label is empty without a vehicle module")
		hud.queue_free()
	else:
		TestLib.check(false, "hud scene exists")
	player.vehicle = null
	Game.vehicles = null
	Game.player = null
	Game.force_touch = false
	tc.queue_free()
	player.queue_free()
	vehicles.queue_free()
	car.queue_free()
	await TestLib.frames(host, 2)
