extends RefCounted
## Dev probe of the Arsenal screens (wave 114): opens a screen in the real scene and prints the scanned texts with their rects. Not a test.
##   ARS_SIZE=844x390 ARS_STEPS=wheel_g_bulwark tools/test.sh tests/dev_arsenal_probe.gd

var host: Node


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	var hud := main.find_children("*", "Hud", true, false)[0] as Hud
	WeaponDefs.hero_mode = true
	var sz := OS.get_environment("ARS_SIZE")
	if sz != "":
		var p := sz.split("x")
		host.get_window().size = Vector2i(int(p[0]), int(p[1]))
		await TestLib.frames(host, 4)
	Game.state = &"play"
	Game.state = &"paused"
	hud._on_state(&"paused")
	hud.screen_age = 5.0
	hud._sub_t = 5.0
	hud._layout_key = ""
	hud._ensure_layout()
	var steps := OS.get_environment("ARS_STEPS").split(",", false)
	for id in steps:
		hud.press_button(StringName(id))
		hud._layout_key = ""
		hud._ensure_layout()
	hud.scan_log.clear()
	hud.scan_text = true
	hud._screen.queue_redraw()
	for i in 60:
		await TestLib.frames(host, 1)
		if not hud.scan_log.is_empty():
			break
	await TestLib.frames(host, 1)
	hud.scan_text = false
	var vp := hud.get_viewport().get_visible_rect().size
	print("PROBE vp ", vp, " s ", UiUtil.ui_scale(vp), " texts ", hud.scan_log.size(), " buttons ", hud.buttons.size())
	var seen := {}
	var log: Array[Dictionary] = []
	for e0: Dictionary in hud.scan_log:
		var key := "%s|%s" % [e0["text"], e0["rect"]]
		if not seen.has(key):
			seen[key] = true
			log.append(e0)
	for e: Dictionary in log:
		print("PROBE text '", e["text"], "' rect ", e["rect"], " size ", e["size"], " over ", e["over"])
	for i in log.size():
		for j in range(i + 1, log.size()):
			var a: Rect2 = log[i]["rect"]
			var b: Rect2 = log[j]["rect"]
			var inter := a.intersection(b)
			if inter.has_area() and inter.get_area() > 0.25 * minf(a.get_area(), b.get_area()):
				print("PROBE OVERLAP '", log[i]["text"], "' ", a, " / '", log[j]["text"], "' ", b)
	for b: Dictionary in hud.buttons:
		print("PROBE btn ", b["id"], " ", b["rect"])
	WeaponDefs.hero_mode = false
