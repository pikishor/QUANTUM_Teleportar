extends RefCounted
## w1242-critic DEMO review probe: 30 random weapons (finger: DEMO, WEAPONS, entry, CLOSE, then the FIRE button) and 15 random missions (finger) in the real main scene.
const TIMEOUT_SECONDS := 1400
const Fingers := preload("res://tests/w116_fingers.gd")
const TABS: Array[String] = ["CHAPTERS", "SIDE", "ACTIVITY", "SET PIECE", "BOSS", "CONTRACT", "SEQUEL", "CHASE", "STEALTH", "HEIST", "ARENA", "EVENT", "INTERIOR", "ALLY", "SAFEHOUSE"]
var host: Node
var dp: DemoPanel
func _tap(pos: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventScreenTouch.new()
		e.index = 0
		e.position = host.get_tree().root.get_final_transform() * pos
		e.pressed = down
		Input.parse_input_event(e)
		for i in 2:
			await host.get_tree().physics_frame
			await host.get_tree().process_frame


func _open_menu() -> bool:
	if dp.is_open:
		return true
	if Game.state != &"play":
		Game.state = &"play"
		await TestLib.frames(host, 2)
	await _tap(dp.entry_rect().get_center())
	return dp.is_open


func _tab(name: String) -> bool:
	var i := DemoPanel.TABS.find(name)
	if i < 0:
		return false
	await _tap(dp.call(&"_tab_rects")[i].get_center())
	return dp.page == i


## Scrolls the page so the item is in view (a finger drag), then taps its centre.
func _tap_item(it: Dictionary) -> void:
	var r: Rect2 = it["rect"]
	var top := float(dp.call(&"_top"))
	var vis_h := dp._canvas.size.y - top - 20.0 if dp._canvas.size.y > 0.0 else 400.0
	var want := clampf(r.position.y - 10.0, 0.0, float(dp.call(&"_max_scroll")))
	var guard := 0
	while (r.position.y - dp.scroll < 0.0 or r.end.y - dp.scroll > vis_h) and guard < 12:
		guard += 1
		var step := clampf(dp.scroll - want, -vis_h * 0.6, vis_h * 0.6)
		if absf(step) < 20.0:
			step = 20.0 * signf(step) if step != 0.0 else -20.0       # drag down (positive) scrolls up
		var x := r.get_center().x
		var y0 := top + vis_h * 0.5 - step * 0.5
		await _drag(Vector2(x, y0), Vector2(x, y0 + step))
	await _tap(Vector2(r.get_center().x, r.get_center().y + top - dp.scroll))


func _drag(a: Vector2, b: Vector2) -> void:
	var xf := host.get_tree().root.get_final_transform()
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = xf * a
	t.pressed = true
	Input.parse_input_event(t)
	await host.get_tree().process_frame
	for k in range(1, 7):
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = xf * a.lerp(b, float(k) / 6.0)
		Input.parse_input_event(d)
		await host.get_tree().process_frame
	t = InputEventScreenTouch.new()
	t.index = 0
	t.position = xf * b
	t.pressed = false
	Input.parse_input_event(t)
	await host.get_tree().process_frame
	await host.get_tree().process_frame


func _item(label: String) -> Dictionary:
	dp.layout()
	for it in dp.items:
		if not it.get("head", false) and String(it["label"]) == label:
			return it
	return {}


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	CrateReveal._quiet = 0
	TestMode.reset_toggles()
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 20)
	Game.state = &"menu"
	DemoMode.enter()
	await TestLib.frames(host, 10)
	Game.state = &"play"
	await TestLib.frames(host, 4)
	dp = host.get_tree().root.find_children("*", "DemoPanel", true, false)[0] as DemoPanel
	var fg := Fingers.new(host)
	var p := Game.player as Player
	var rng := RandomNumberGenerator.new()
	rng.seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1242
	await _open_menu()
	await _tab("WEAPONS")
	dp.layout()
	var wl: Array = []
	for it in dp.items:
		if not it.get("head", false) and it.get("kind", &"") == &"weapon":
			wl.append(String(it["label"]))
	dp.close()
	for n in 30:
		var lb: String = wl[rng.randi() % wl.size()]
		await _open_menu()
		await _tab("WEAPONS")
		await _tap_item(_item(lb))
		var id := p.weapon.current
		await _tap(dp.call(&"_close_rect").get_center())
		await TestLib.frames(host, 6)
		var s0 := p.weapon.shots_fired
		var a0 := p.weapon.ammo
		var can := fg.press(3, &"fire")
		await TestLib.frames(host, 30)
		fg.up(3)
		await TestLib.frames(host, 30)
		print("DEMOW %s id=%s fire_btn=%s shots=%d ammo %d->%d open=%s card=%s state=%s btn=%s" % [lb, id, can, p.weapon.shots_fired - s0, a0, p.weapon.ammo, dp.is_open, CrateReveal.is_showing(), Game.state, fg.button_label(&"fire")])
	for n in 15:
		var tab: String = TABS[rng.randi() % TABS.size()]
		await _open_menu()
		if not await _tab(tab):
			print("DEMOM tab %s no tab" % tab)
			continue
		var labels := dp.labels()
		if labels.is_empty():
			print("DEMOM tab %s empty" % tab)
			continue
		var lb: String = labels[rng.randi() % labels.size()]
		dp.status = ""
		await _tap_item(_item(lb))
		await TestLib.frames(host, 2)
		var st := dp.status
		var open := dp.is_open
		if open:
			dp.close()
		await TestLib.frames(host, 180)
		var guide: Variant = (Game.missions as Missions).get(&"guide") if Game.missions != null else null
		var line := ""
		if guide != null and guide.has_method(&"line"):
			line = str(guide.call(&"line"))
		print("DEMOM %s / %s status='%s' open=%s state=%s card=%s guide='%s' pos=%s" % [tab, lb, st, open, Game.state, CrateReveal.is_showing(), line, p.global_position.snapped(Vector3.ONE)])
	DemoMode.quit()
	TestMode.reset_toggles()
	CrateReveal._quiet = -1
	Game.force_touch = false
	main.queue_free()
	await TestLib.frames(host, 2)
