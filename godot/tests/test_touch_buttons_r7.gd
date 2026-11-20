extends RefCounted
## OWNER ROUND 7: "opening the map, no back button etc works" and "in demo mode I just keep on seeing weapons". Real scene, REAL finger events (InputEventScreenTouch through
## Input.parse_input_event, never a mouse and never a direct call): every side button and filter chip of the map answers a finger, CLOSE closes it, the watchdog's rescue BACK
## answers a finger, and the demo's 229 unlocks leave no reward card on screen or in the queue; a card that is on screen closes on a tap and never stays over a menu.
## Run: tools/test.sh tests/test_touch_buttons_r7.gd

const TIMEOUT_SECONDS := 120
var host: Node


func _tap(pos: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventScreenTouch.new()
		e.index = 0
		e.position = host.get_tree().root.get_final_transform() * pos      # window coordinates, as a real finger arrives
		e.pressed = down
		Input.parse_input_event(e)
		await TestLib.frames(host, 2)


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 10)
	Game.state = &"play"
	var ms := host.get_tree().root.find_child("MapScreen", true, false) as MapScreen
	TestLib.check(ms != null and host.get_tree().root.get_node_or_null("TouchButtons") != null, "the scene has a map and the touch-button node")
	if ms == null:
		return
	# --- the map: each button by a finger
	ms.open()
	await TestLib.frames(host, 30)
	TestLib.check(MapScreen.up, "the map is open")
	var zoom := ms.find_child("Zoom", true, false) as Button
	var z0 := zoom.text
	await _tap(zoom.get_global_rect().get_center())
	TestLib.check(zoom.text != z0, "a finger on ZOOM changes the zoom (%s -> %s)" % [z0, zoom.text])
	var rm := ms.find_child("RouteMode", true, false) as Button
	var r0 := rm.text
	await _tap(rm.get_global_rect().get_center())
	TestLib.check(rm.text != r0, "a finger on GPS changes the route mode (%s -> %s)" % [r0, rm.text])
	var chip := ms.find_child("F_shop", true, false) as Button
	if chip == null:
		for c in ms.find_children("F_*", "Button", true, false):
			if (c as Button).is_visible_in_tree():
				chip = c as Button
				break
	var on0 := chip.button_pressed
	var wp0 := str(ms.get("selected"))
	await _tap(chip.get_global_rect().get_center())
	TestLib.check(chip.button_pressed != on0, "a finger on a filter chip toggles it")
	TestLib.check(str(ms.get("selected")) == wp0, "the tap on a chip did not also land on the map under it")
	var cls := ms.find_child("Close", true, false) as Button
	await _tap(cls.get_global_rect().get_center())
	TestLib.check(not MapScreen.up and Game.state == &"play", "a finger on CLOSE closes the map and the game runs (state %s)" % Game.state)
	# --- the rescue BACK of the watchdog
	ms.open()
	await TestLib.frames(host, 30)
	var wd := host.get_tree().root.find_child("ScreenWatchdog", true, false) as ScreenWatchdog
	wd.force_idle(60.0)
	await TestLib.frames(host, 4)
	var wb := wd.find_child("WatchdogBack", true, false) as Button
	TestLib.check(wb != null and wb.is_visible_in_tree(), "the rescue BACK is up over a trapped map")
	if wb != null and wb.is_visible_in_tree():
		await _tap(wb.get_global_rect().get_center())
		TestLib.check(not MapScreen.up, "a finger on the rescue BACK closes the map")
	if MapScreen.up:
		ms.close_screen()
	# --- reward cards
	var prog := host.get_tree().root.find_child("Progress", true, false) as Progress
	var s0 := CrateReveal.started
	CrateReveal._quiet = 0                                   # as on a phone: cards are allowed
	DemoMode._grant_all(prog)
	await TestLib.frames(host, 4)
	TestLib.check(not CrateReveal.is_showing() and CrateReveal._queue.is_empty() and CrateReveal.started == s0, "the demo's unlock of every weapon shows and queues no reward card (started %d)" % (CrateReveal.started - s0))
	for i in 6:
		CrateReveal.request(WeaponDefs.IDS[i + 3], "MISSION REWARD", true)
	TestLib.check(CrateReveal._queue.size() <= CrateReveal.MAX_QUEUE, "at most %d cards wait in line (%d)" % [CrateReveal.MAX_QUEUE, CrateReveal._queue.size()])
	CrateReveal._queue.clear()
	await TestLib.frames(host, 30)
	TestLib.check(CrateReveal.is_showing(), "a reward card is on screen")
	await _tap(Vector2(40, 40))
	await TestLib.frames(host, 3)
	TestLib.check(not CrateReveal.is_showing(), "a tap closes the card")
	CrateReveal.request(WeaponDefs.IDS[4], "MISSION REWARD", true)
	await TestLib.frames(host, 3)
	Game.state = &"paused"
	await TestLib.frames(host, 4)
	TestLib.check(not CrateReveal.is_showing(), "no card stays over the pause menu")
	CrateReveal._quiet = -1
	Game.state = &"menu"
	Game.force_touch = false
	main.queue_free()
	await TestLib.frames(host, 2)
