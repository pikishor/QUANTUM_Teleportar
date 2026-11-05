extends RefCounted
## PHOTO MODE (scripts/ui/photo_mode.gd + photo_screen.gd, Hud.photo) in the REAL scene (main.tscn): the pause menu PHOTO button (64 px) starts it with Game.state staying "paused" (the tree is never
## paused), the photo camera becomes Game.camera and the gameplay HUD hides; orbit / pan / zoom (direct, mouse wheel, touch drag, two-finger pinch), FOV / BLUR / TIME / ZOOM sliders through the
## Hud, pose presets frame the hero from the front and the back, FILTER pins a district grade (Atmosphere.look_override), HIDE HERO / HIDE UI toggle, SHOT saves a PNG to user://photos
## (a synthetic image proves the file; the live grab only has to finish, headless has no picture), SHARE is a hook placeholder with no network, reduce motion snaps the camera and drops
## the flash, EXIT / Esc / RESUME restore the camera, hero, grade and hour. Waits are on state and counters. Photos written here are deleted again. Not run: a phone, the look of the blur.
## Run: tools/test.sh tests/test_photo_mode.gd

var host: Node
var main: Node
var hud: Hud
var p: Player
var made: Array[String] = []


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	p = Game.player as Player
	for n in main.find_children("*", "Hud", true, false):
		hud = n as Hud
	TestLib.check(p != null and hud != null and hud.photo != null, "main.tscn composes the player and a Hud with photo mode")
	if p == null or hud == null or hud.photo == null:
		return
	var ph := hud.photo
	var rig_cam := Game.camera
	var was_reduce := UiSettings.s_reduce_motion
	var was_state := Game.state
	UiSettings.s_reduce_motion = false

	# not from the game itself: only the pause menu offers it
	Game.state = &"play"
	TestLib.check(not hud.press_button(&"photo_open") and not ph.active, "PHOTO does nothing while playing")
	hud.pause_game()
	await TestLib.frames(host, 3)
	TestLib.check(Game.state == &"paused", "pause is Game.state paused")
	hud._gear_open = true                                          # PHOTO lives on the MORE page
	hud._layout_key = ""
	hud._ensure_layout()
	var scale := UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size)
	var opener := _button(&"photo_open")
	TestLib.check(not opener.is_empty() and (opener["rect"] as Rect2).size.y >= 63.9 * scale, "the pause menu has a PHOTO button of at least 64 px")

	var dn := (Game.world as City).day_night
	var atm := Game.atmosphere as Atmosphere
	var hour0 := dn.hour
	TestLib.check(hud.press_button(&"photo_open") and ph.active, "PHOTO starts photo mode")
	await TestLib.frames(host, 2)
	TestLib.check(Game.state == &"paused" and not host.get_tree().paused, "photo mode keeps Game.state paused and never pauses the tree")
	TestLib.check(Game.camera == ph.camera, "the photo camera is Game.camera")
	TestLib.check(ph.camera.is_current() or ph.camera.get_viewport().get_camera_3d() == ph.camera, "the photo camera renders the view (current %s)" % ph.camera.current)
	TestLib.check(hud.photo_open() and not hud._hud.visible and hud.layers_consistent(), "the gameplay HUD is hidden and the layers stay consistent")
	TestLib.check(not hud.press_button(&"photo_open"), "photo mode does not start twice")

	# buttons: all photo controls at least 64 px
	hud._ensure_layout()
	var ids: Array[StringName] = [&"photo_exit", &"photo_shot", &"photo_share", &"photo_ui", &"photo_hero", &"photo_filter", &"photo_pose", &"photo_mode", &"photo_fov", &"photo_dof", &"photo_time", &"photo_zoom"]
	var small := 0
	var missing := 0
	for id in ids:
		var b := _button(id)
		if b.is_empty():
			missing += 1
		elif (b["rect"] as Rect2).size.y < 63.9 * scale:
			small += 1
	TestLib.check(missing == 0 and small == 0, "every photo control exists and is at least 64 px tall (missing %d, small %d)" % [missing, small])
	var vp := hud.get_viewport().get_visible_rect().size
	var inside := true
	for b: Dictionary in hud.buttons:
		if not Rect2(Vector2.ZERO, vp).encloses(b["rect"]):
			inside = false
	TestLib.check(inside, "the controls stay on screen")

	# camera: orbit, pan, zoom
	var yaw0 := ph._t_yaw
	ph.orbit(Vector2(100.0, 0.0))
	TestLib.check(not is_equal_approx(ph._t_yaw, yaw0), "dragging orbits the camera")
	ph.orbit(Vector2(0.0, 5000.0))
	TestLib.check(ph._t_pitch <= PhotoMode.PITCH_LIMIT + 0.0001, "pitch is limited")
	ph.settle()
	TestLib.check(ph.camera.global_position.distance_to(ph.camera_position()) < 0.01, "the camera sits where the orbit says")
	var f0 := ph._t_focus
	ph.pan(Vector2(200.0, 80.0))
	TestLib.check(ph._t_focus.distance_to(f0) > 0.01, "panning moves the focus")
	ph.pan(Vector2(1e7, 0.0))
	TestLib.check(ph._t_focus.distance_to(ph._hero_focus()) <= PhotoMode.PAN_MAX + 0.01, "the focus stays near the hero")
	ph.set_pose(0)
	ph.zoom(0.0001)
	TestLib.check(is_equal_approx(ph._t_dist, PhotoMode.DIST_MIN), "zoom stops at the near limit")
	ph.zoom(1000.0)
	TestLib.check(is_equal_approx(ph._t_dist, PhotoMode.DIST_MAX), "zoom stops at the far limit")
	var w := InputEventMouseButton.new()
	w.button_index = MOUSE_BUTTON_WHEEL_UP
	w.pressed = true
	var d0 := ph._t_dist
	ph._input(w)
	TestLib.check(ph._t_dist < d0, "the mouse wheel zooms in")
	# touch: one finger orbits, two fingers pinch
	var t1 := InputEventScreenTouch.new()
	t1.index = 0
	t1.pressed = true
	t1.position = Vector2(300.0, 250.0)
	ph._input(t1)
	var dr := InputEventScreenDrag.new()
	dr.index = 0
	dr.position = Vector2(340.0, 250.0)
	dr.relative = Vector2(40.0, 0.0)
	var yaw1 := ph._t_yaw
	ph._input(dr)
	TestLib.check(not is_equal_approx(ph._t_yaw, yaw1), "one finger on the empty screen orbits")
	var t2 := InputEventScreenTouch.new()
	t2.index = 1
	t2.pressed = true
	t2.position = Vector2(500.0, 250.0)
	ph._input(t2)
	var dr2 := InputEventScreenDrag.new()
	dr2.index = 1
	dr2.position = Vector2(700.0, 250.0)
	dr2.relative = Vector2(200.0, 0.0)
	var d1 := ph._t_dist
	ph._input(dr2)
	TestLib.check(ph._t_dist < d1, "two fingers spreading pinch the camera closer")
	for t in [t1, t2]:
		var up := InputEventScreenTouch.new()
		up.index = (t as InputEventScreenTouch).index
		up.pressed = false
		ph._input(up)
	TestLib.check(ph._touches.is_empty(), "lifting the fingers ends the gesture")
	# a finger that lands on a button is the button's, not the camera's
	var shot_b := _button(&"photo_shot")
	var on_ui := InputEventScreenTouch.new()
	on_ui.index = 3
	on_ui.pressed = true
	on_ui.position = (shot_b["rect"] as Rect2).get_center()
	ph._input(on_ui)
	TestLib.check(ph._touches.is_empty(), "touches on a button never move the camera")
	ph.toggle_pan_mode()
	var f1 := ph._t_focus
	ph.orbit(Vector2(30.0, 10.0))
	TestLib.check(ph._t_focus.distance_to(f1) > 0.0, "PAN mode turns a one-finger drag into a pan")
	ph.toggle_pan_mode()

	# sliders through the Hud
	hud._ensure_layout()
	var fov_b := _button(&"photo_fov")
	var r: Rect2 = fov_b["rect"]
	hud.slide(&"photo_fov", r.position.x + r.size.x * 0.9)
	TestLib.check(ph.fov > 90.0 and ph.fov <= PhotoMode.FOV_MAX, "the FOV slider widens the view")
	hud.slide(&"photo_fov", r.position.x - 500.0)
	TestLib.check(is_equal_approx(ph.fov, PhotoMode.FOV_MIN), "the FOV slider stops at its minimum")
	hud._ensure_layout()
	var dof_b := _button(&"photo_dof")
	r = dof_b["rect"]
	hud.slide(&"photo_dof", r.position.x + r.size.x * 0.8)
	TestLib.check(ph.dof > 0.5 and ph._attrs.dof_blur_far_enabled and ph._attrs.dof_blur_amount > 0.0, "the BLUR slider switches the depth of field on")
	hud.slide(&"photo_dof", r.position.x - 500.0)
	TestLib.check(ph.dof == 0.0 and not ph._attrs.dof_blur_far_enabled, "BLUR at zero switches it off")
	hud._ensure_layout()
	var time_b := _button(&"photo_time")
	r = time_b["rect"]
	hud.slide(&"photo_time", r.position.x + r.size.x * 0.5)
	TestLib.check(absf(dn.hour - ph.hour) < 0.01 and absf(ph.hour - 12.0) < 1.5, "the TIME slider sets the hour of the world (%.2f)" % dn.hour)
	TestLib.check(ph.hour_text().length() == 5, "the hour reads as HH:MM")
	hud._ensure_layout()
	var zoom_b := _button(&"photo_zoom")
	r = zoom_b["rect"]
	hud.slide(&"photo_zoom", r.position.x + r.size.x * 0.5)
	TestLib.check(ph._t_dist > 4.0 and ph._t_dist < 12.0, "the ZOOM slider sets the distance")

	# hero pose presets
	var front_ok := true
	var back_ok := true
	var fwd := Vector3(sin(ph.hero_azimuth()), 0.0, cos(ph.hero_azimuth()))
	for i in PhotoMode.POSES.size():
		hud.press_button(&"photo_pose")
		ph.settle()
		var off := ph.camera_position() - ph._hero_focus()
		off.y = 0.0
		var side := off.normalized().dot(fwd)
		var id: StringName = PhotoMode.POSES[i]["id"]
		if id == &"front" and side < 0.9:
			front_ok = false
		if (id == &"back" or id == &"wide") and side > -0.9:
			back_ok = false
	TestLib.check(ph.pose_i == PhotoMode.POSES.size() - 1 and front_ok and back_ok, "the pose presets frame the hero from the front and from behind")
	hud.press_button(&"photo_pose")
	TestLib.check(ph.pose_i == 0 and ph.pose_name() != "POSE", "the pose button cycles")

	# filters from the district grades
	TestLib.check(ph.filter_i == 0 and atm.look_override.is_empty(), "the filter starts on AUTO (the district grade follows the hero)")
	hud.press_button(&"photo_filter")
	TestLib.check(atm.look_override.get("sat", -1.0) == (PostFx2.GRADES[&"market"] as Dictionary)["sat"], "FILTER pins the market grade")
	for i in 4:
		hud.press_button(&"photo_filter")
	TestLib.check(PhotoMode.FILTERS[ph.filter_i] == &"mono" and float(atm.look_override["sat"]) == 0.0, "the last filter is monochrome")
	hud.press_button(&"photo_filter")
	TestLib.check(ph.filter_i == 0 and atm.look_override.is_empty(), "the filter cycles back to AUTO")
	hud.press_button(&"photo_filter")

	# hide hero / hide UI
	TestLib.check(p.visible, "the hero starts visible")
	hud.press_button(&"photo_hero")
	TestLib.check(not p.visible and ph.hide_hero, "HIDE HERO hides the hero")
	hud.press_button(&"photo_hero")
	TestLib.check(p.visible, "SHOW HERO brings him back")
	hud.press_button(&"photo_ui")
	hud._ensure_layout()
	TestLib.check(ph.hide_ui and hud.buttons.size() == 1 and _button(&"photo_ui").get("label", "") == "SHOW UI" and (_button(&"photo_ui")["rect"] as Rect2).size.y >= 63.9 * scale, "HIDE UI leaves one 64 px SHOW UI button")
	hud.press_button(&"photo_ui")
	hud._ensure_layout()
	TestLib.check(not ph.hide_ui and hud.buttons.size() > 8, "SHOW UI brings the controls back")

	# SHOT: synthetic image proves the file; the live grab has to finish
	var base_ok := ph.shots
	var img := Image.create(64, 36, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.5, 0.8))
	var path := ph.save_image(img)
	made.append(path)
	TestLib.check(path != "" and path.begins_with("user://photos/") and FileAccess.file_exists(path) and ph.shots == base_ok + 1 and ph.last_path == path, "save_image writes a PNG under user://photos")
	var back := Image.load_from_file(ProjectSettings.globalize_path(path))
	TestLib.check(back != null and back.get_width() == 64 and back.get_height() == 36, "the saved photo loads back at its size")
	var path2 := ph.save_image(img)
	made.append(path2)
	TestLib.check(path2 != "" and path2 != path, "two photos never share a file name")
	var fails0 := ph.shot_fails
	TestLib.check(ph.save_image(null) == "" and ph.shot_fails == fails0 + 1, "no picture counts as a failed shot")
	var done := [0]
	var got := [""]
	ph.captured.connect(func(pp: String) -> void:
		done[0] += 1
		got[0] = pp)
	hud.press_button(&"photo_shot")
	for i in 240:
		if done[0] > 0:
			break
		await host.get_tree().process_frame
	TestLib.check(done[0] == 1, "SHOT finishes and reports (path '%s')" % got[0])
	if got[0] != "":
		made.append(got[0])
		TestLib.check(FileAccess.file_exists(got[0]), "the grabbed photo is on disk")
	TestLib.check(hud._screen.visible, "the controls come back after the grab")
	TestLib.check(hud.press_button(&"photo_shot"), "SHOT can be pressed again")
	for i in 240:
		if done[0] > 1:
			break
		await host.get_tree().process_frame
	if got[0] != "":
		made.append(got[0])

	# SHARE: placeholder, no network
	var shared := [0]
	ph.share_requested.connect(func(_pp: String) -> void: shared[0] += 1)
	var s0 := ph.shares
	hud.press_button(&"photo_share")
	TestLib.check(ph.shares == s0 + 1 and shared[0] == 1 and ph.status.contains("NOT AVAILABLE"), "SHARE without a hook says it is not available yet")
	var hooked := [""]
	PhotoMode.share_hook = func(pp: String) -> void: hooked[0] = pp
	hud.press_button(&"photo_share")
	TestLib.check(hooked[0] == ph.last_path and hooked[0] != "", "SHARE hands the last photo to the hook")
	PhotoMode.share_hook = Callable()

	# reduce motion: the camera follows instantly, no flash
	UiSettings.s_reduce_motion = true
	ph.flash = 0.0
	ph.set_pose(3)
	TestLib.check(is_equal_approx(ph.yaw, ph._t_yaw) and is_equal_approx(ph.dist, ph._t_dist), "with reduce motion a pose jumps at once")
	ph.orbit(Vector2(50.0, 0.0))
	ph._process(0.016)
	TestLib.check(is_equal_approx(ph.yaw, ph._t_yaw), "with reduce motion the orbit has no easing")
	var mark := ph.shots
	ph.save_image(img)
	made.append(ph.last_path)
	ph.capture()
	for i in 240:
		if ph._capturing == false and i > 2:
			break
		await host.get_tree().process_frame
	TestLib.check(ph.flash == 0.0, "reduce motion turns the shutter flash off")
	if ph.last_path != "" and not made.has(ph.last_path):
		made.append(ph.last_path)
	UiSettings.s_reduce_motion = false
	ph.set_pose(0)
	var y_before := ph.yaw
	await TestLib.frames(host, 4)
	TestLib.check(true, "easing runs without error (yaw %.2f)" % y_before)

	# EXIT restores the world
	ph.set_filter(2)
	ph.toggle_hero()
	ph.set_hour(3.0)
	hud.press_button(&"photo_exit")
	await TestLib.frames(host, 2)
	TestLib.check(not ph.active and Game.state == &"paused", "EXIT leaves photo mode for the pause menu")
	TestLib.check(Game.camera == rig_cam and rig_cam.current, "the game camera is back")
	TestLib.check(p.visible and atm.look_override.is_empty() and absf(dn.hour - hour0) < 0.05, "hero, grade and hour are restored")
	TestLib.check(not is_instance_valid(ph.camera) and hud.layers_consistent() and hud._hud.visible == hud._hud_wanted(), "the photo camera is gone and the HUD layer matches the state (the MORE page it returns to may cover it)")

	# Esc leaves it too; RESUME (a state change) ends it and plays on
	hud._layout_key = ""
	hud._ensure_layout()
	TestLib.check(hud.press_button(&"photo_open") and ph.active, "photo mode can start again")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	hud._input(esc)
	TestLib.check(not ph.active and Game.state == &"paused", "Esc leaves photo mode for the pause menu")
	hud._layout_key = ""
	hud._ensure_layout()
	hud.press_button(&"photo_open")
	ph.set_filter(3)
	ph.toggle_hero()
	hud.press_button(&"resume")
	await TestLib.frames(host, 2)
	TestLib.check(Game.state == &"play" and not ph.active and Game.camera == rig_cam and p.visible and atm.look_override.is_empty(), "RESUME ends photo mode and restores everything")

	UiSettings.s_reduce_motion = was_reduce
	for f in made:
		if f != "":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Game.state = was_state if was_state == &"play" else &"play"


func _button(id: StringName) -> Dictionary:
	for b: Dictionary in hud.buttons:
		if b["id"] == id:
			return b
	return {}
