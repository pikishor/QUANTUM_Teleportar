extends RefCounted
## Touch controls: the move stick and its sprint threshold, the look drag, buttons, quality cycling from the perf readout, respawn on tap.
## Run: tools/test.sh tests/test_touch.gd

class StubRig extends Node:
	var looked := Vector2.ZERO
	func add_look(dy: float, dp: float) -> void:
		looked += Vector2(dy, dp)


class StubPlayer extends Node3D:
	var camera_rig: Node
	var quantum: Node
	var vehicle: Node3D


class StubVehicles extends Node:
	var near: Node3D
	func nearest(_pos: Vector3, _r := 4.2) -> Node3D:
		return near


func run(host: Node) -> void:
	Game.force_touch = true
	Game.state = &"play"
	var rig := StubRig.new()
	var player := StubPlayer.new()
	player.camera_rig = rig
	host.add_child(player)
	player.add_child(rig)
	Game.player = player
	var tc := (load("res://scenes/touch_controls.tscn") as PackedScene).instantiate() as TouchControls
	host.add_child(tc)
	await TestLib.frames(host, 2)
	TestLib.check(tc.controls_on and tc.perf_on, "touch controls and perf readout are on with force_touch")
	var vp := host.get_viewport().get_visible_rect().size
	var s := vp.y / 720.0

	# move stick: a floating origin, strengths follow the drag, a full push sprints
	tc.touch_down(0, Vector2(200, vp.y - 150))
	tc.touch_move(0, Vector2(200, vp.y - 150 - 60 * s), Vector2(0, -60))
	TestLib.check(Input.get_action_strength(&"move_forward") > 0.5 and Input.get_action_strength(&"move_forward") < 0.7, "a 60 px push forward is about 0.6 (%.2f)" % Input.get_action_strength(&"move_forward"))
	TestLib.check(not Input.is_action_pressed(&"sprint"), "no sprint below the threshold")
	tc.touch_move(0, Vector2(200, vp.y - 150 - 130 * s), Vector2(0, -70))
	TestLib.check(Input.get_action_strength(&"move_forward") > 0.99 and Input.is_action_pressed(&"sprint"), "a full push forward is 1.0 and sprints")
	tc.touch_move(0, Vector2(200 + 90 * s, vp.y - 150 - 130 * s), Vector2(90, 0))
	TestLib.check(Input.get_action_strength(&"move_right") > 0.3, "the stick also strafes (right %.2f)" % Input.get_action_strength(&"move_right"))
	tc.touch_up(0)
	TestLib.check(not Input.is_action_pressed(&"move_forward") and not Input.is_action_pressed(&"move_right") and not Input.is_action_pressed(&"sprint"), "releasing the stick releases every move action")

	# look drag on the right half, scaled by LOOK_SENS
	tc.touch_down(1, Vector2(vp.x * 0.6, vp.y * 0.4))
	tc.touch_move(1, Vector2(vp.x * 0.6 + 100, vp.y * 0.4 + 40), Vector2(100, 40))
	TestLib.check(is_equal_approx(rig.looked.x, 100.0 * TouchControls.LOOK_SENS) and is_equal_approx(rig.looked.y, 40.0 * TouchControls.LOOK_SENS), "a drag turns the view by the look sensitivity (%s)" % str(rig.looked))
	tc.touch_up(1)
	var before := rig.looked
	tc.touch_move(1, Vector2(10, 10), Vector2(50, 50))
	TestLib.check(rig.looked == before, "a finger that is not down does not look")

	# buttons press and release their actions; a finger on FIRE can also look
	var fire := _button(tc, &"fire")
	tc.touch_down(2, tc.call("_button_center", fire))
	TestLib.check(Input.is_action_pressed(&"fire"), "FIRE presses the fire action")
	tc.touch_move(2, Vector2(vp.x - 100, vp.y - 300), Vector2(0, -30))
	TestLib.check(rig.looked != before, "dragging from FIRE turns the view as well")
	tc.touch_up(2)
	TestLib.check(not Input.is_action_pressed(&"fire"), "lifting the finger releases fire")
	for a: StringName in [&"aim", &"jump", &"reload"]:
		tc.touch_down(3, tc.call("_button_center", _button(tc, a)))
		TestLib.check(Input.is_action_pressed(a), "%s button presses its action" % a)
		tc.touch_up(3)
		TestLib.check(not Input.is_action_pressed(a), "%s button releases its action" % a)

	# the perf readout cycles the graphics tier through Game.set_quality
	var q0 := Game.quality
	var box: Rect2 = tc.call("_perf_box")
	TestLib.check(not tc.perf_visible(), "the readout is hidden until a long press")
	tc.show_perf(true)
	TestLib.check(tc.perf_visible(), "the readout shows while playing once it is on")
	tc.touch_down(4, box.get_center())
	tc.touch_up(4)
	TestLib.check(Game.quality == (q0 + 1) % 3, "tapping the readout cycles the tier (%d -> %d)" % [q0, Game.quality])
	Game.set_quality(1)

	# the powers and USE appear only when their module exists
	var ability := _button(tc, &"ability")
	var use := _button(tc, &"interact")
	TestLib.check(not tc.button_visible(ability) and not tc.button_visible(use), "ABILITY and USE are hidden without the quantum and vehicle modules")
	tc.touch_down(8, tc.call("_button_center", ability))
	TestLib.check(not tc.wheel.is_open and not Input.is_action_pressed(&"blink"), "a hidden ABILITY button opens nothing")
	tc.touch_up(8)
	player.quantum = Node.new()
	TestLib.check(tc.button_visible(ability), "ABILITY shows once player.quantum exists; the verbs live in its wheel")
	tc.touch_down(8, tc.call("_button_center", ability))
	TestLib.check(tc.wheel.is_open and tc.wheel.kind == &"ability", "pressing ABILITY opens the wheel")
	tc.touch_up(8)
	TestLib.check(tc.wheel.is_open and tc.wheel.sticky, "a quick tap leaves the wheel open")
	var wi := -1
	for i in tc.wheel.items.size():
		if tc.wheel.item_id(i) == &"blink":
			wi = i
	TestLib.check(wi >= 0, "the wheel lists QUANTUM TELEPORT")
	tc.touch_down(8, tc.wheel.item_centre(wi))
	TestLib.check(Input.is_action_pressed(&"blink") and not tc.wheel.is_open, "tapping a disc presses its action and closes the wheel")
	tc.touch_up(8)
	await TestLib.frames(host, 14)
	TestLib.check(not Input.is_action_pressed(&"blink"), "the pick lets go of the action again")
	var vehicles := StubVehicles.new()
	host.add_child(vehicles)
	Game.vehicles = vehicles
	await TestLib.frames(host, 12)
	TestLib.check(not tc.button_visible(use), "USE stays hidden with no vehicle in reach")
	var car := Node3D.new()
	host.add_child(car)
	vehicles.near = car
	await TestLib.frames(host, 14)
	TestLib.check(tc.button_visible(use), "USE appears with a vehicle in reach")
	tc.touch_down(9, tc.call("_button_center", use))
	TestLib.check(Input.is_action_pressed(&"interact"), "USE presses interact")
	tc.touch_up(9)
	vehicles.near = null
	player.vehicle = car
	await TestLib.frames(host, 14)
	TestLib.check(tc.button_visible(use), "USE stays while driving (to get out)")
	player.vehicle = null
	Game.vehicles = null
	vehicles.queue_free()
	car.queue_free()
	player.quantum.free()
	player.quantum = null
	# the pause button asks the HUD to pause
	var asked := [0]
	tc.pause_requested.connect(func() -> void: asked[0] += 1)
	tc.touch_down(10, tc.call("_pause_center"))
	TestLib.check(asked[0] == 1, "the pause button emits pause_requested")
	tc.touch_up(10)

	# state changes release held input; nothing here respawns (the HUD's dead screen does that)
	tc.touch_down(5, tc.call("_button_center", fire))
	Game.state = &"paused"
	TestLib.check(not Input.is_action_pressed(&"fire"), "a state change releases held buttons")
	Game.state = &"dead"
	tc.touch_down(6, Vector2(vp.x * 0.5, vp.y * 0.5))
	TestLib.check(Game.state == &"dead", "the touch layer leaves the dead screen to the HUD")
	Game.state = &"play"

	# nothing is pressed while the game is not playing
	Game.state = &"paused"
	tc.touch_down(7, tc.call("_button_center", fire))
	TestLib.check(not Input.is_action_pressed(&"fire"), "no input while paused")
	Game.state = &"play"

	tc.queue_free()
	player.queue_free()
	await TestLib.frames(host, 2)
	TestLib.check(Game.player == null or not is_instance_valid(Game.player) or Game.player != player, "cleanup")
	Game.player = null
	Game.force_touch = false


func _button(tc: TouchControls, action: StringName) -> Dictionary:
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == action:
			return b
	return {}
