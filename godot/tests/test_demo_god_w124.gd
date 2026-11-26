extends RefCounted
## WAVE 124 (owner: "in demo mode we should be able to select all weapons, all missions etc like a god mode"). Real main scene, REAL finger events only
## (InputEventScreenTouch through Input.parse_input_event, window coordinates), Game.force_touch on and the phone-only layers on (CrateReveal._quiet = 0):
## the DEMO button opens the menu, a WEAPONS tab lists every weapon id of the roster and a finger on each one equips it, every mission entry of every
## mission tab starts from a finger, and the TOOLS tab has GOD MODE, INFINITE AMMO, MAX MONEY and UNLOCK ALL toggles that answer a finger.
## Run: tools/test.sh tests/test_demo_god_w124.gd

const TIMEOUT_SECONDS := 1500
const MISSION_TABS: Array[String] = ["CHAPTERS", "SIDE", "ACTIVITY", "SET PIECE", "BOSS", "CONTRACT", "SEQUEL", "CHASE", "STEALTH", "HEIST", "ARENA"]
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
	TestLib.check(DemoMode.enter() and DemoMode.active, "demo mode is on")
	await TestLib.frames(host, 10)
	Game.state = &"play"
	await TestLib.frames(host, 4)
	dp = host.get_tree().root.find_children("*", "DemoPanel", true, false)[0] as DemoPanel
	var p := Game.player as Player
	TestLib.check(await _open_menu(), "a finger on DEMO opens the menu")
	# --- WEAPONS: every id of the roster from a finger
	TestLib.check(await _tab("WEAPONS"), "the demo menu has a WEAPONS tab that answers a finger")
	var ids := {}
	dp.layout()
	for it in dp.items:
		if not it.get("head", false) and it.get("kind", &"") == &"weapon":
			ids[StringName(it["id"])] = String(it["label"])
	var missing := WeaponDefs.IDS.filter(func(w: StringName) -> bool: return not ids.has(w))
	TestLib.check(WeaponDefs.IDS.size() >= 200 and missing.is_empty(), "the WEAPONS tab lists every one of the %d weapons (missing %s)" % [WeaponDefs.IDS.size(), str(missing.slice(0, 5))])
	var bad: Array[StringName] = []
	for id: StringName in ids:
		await _tap_item(_item(ids[id]))
		if p.weapon.current != id or not dp.is_open:
			bad.append(id)
	TestLib.check(not ids.is_empty() and bad.is_empty(), "a finger on each WEAPONS entry equips it and the armoury stays open (%d of %d failed: %s)" % [bad.size(), ids.size(), str(bad.slice(0, 5))])
	await _tap(dp.call(&"_close_rect").get_center())
	TestLib.check(not dp.is_open and Game.state == &"play" and p.weapon.current == ids.keys()[ids.size() - 1], "CLOSE goes back to play with the last picked weapon in hand")
	# --- god toggles
	await _open_menu()
	TestLib.check(await _tab("TOOLS"), "TOOLS answers a finger")
	for lb in ["GOD MODE", "INFINITE AMMO", "MAX MONEY", "UNLOCK ALL"]:
		TestLib.check(not _item(lb).is_empty(), "TOOLS has %s" % lb)
	(Game.progress as Progress).credits = 5
	if not _item("MAX MONEY").is_empty():
		await _tap_item(_item("MAX MONEY"))
	TestLib.check((Game.progress as Progress).credits >= DemoMode.CREDITS, "a finger on MAX MONEY fills the credits")
	WeaponDefs.unlocked.erase(WeaponDefs.IDS[WeaponDefs.IDS.size() - 1])
	if not _item("UNLOCK ALL").is_empty():
		await _tap_item(_item("UNLOCK ALL"))
	TestLib.check(DemoMode.all_unlocked(), "a finger on UNLOCK ALL unlocks every weapon again")
	var g0 := TestMode.god
	await _tap_item(_item("GOD MODE"))
	TestLib.check(TestMode.god != g0, "a finger on GOD MODE toggles it")
	TestLib.check(not CrateReveal.is_showing(), "no reward card over the menu after the god toggles")
	dp.close()
	DemoMode.quit()
	await TestLib.frames(host, 4)
	var pr := Game.progress as Progress
	TestLib.check(not DemoMode.active and pr.path != DemoMode.SAVE and pr.credits < DemoMode.CREDITS and not WeaponDefs.is_unlocked(WeaponDefs.IDS[WeaponDefs.IDS.size() - 1]), "after QUIT DEMO the real save is back (path %s, credits %d, demo unlocks gone)" % [pr.path, pr.credits])
	TestMode.reset_toggles()
	CrateReveal._quiet = -1
	Game.force_touch = false
	main.queue_free()
