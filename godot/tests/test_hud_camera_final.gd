extends RefCounted
## HUD AND CAMERA FINAL in the real scene (main.tscn, touch layout forced), at 844x390 and 2400x1080:
##  1 the combat HUD shows only stick, look, FIRE, AIM, JUMP, RELOAD, the ABILITY and WEAPON buttons (MORE folds the rest), pause, the minimap, two slim status bars and one objective line
##    (no captions, no faction plate, no FPS box); every touch button is at least 64 px across and no two buttons, the pause button or the minimap overlap, nothing leaves the screen;
##    the contextual USE / ENTER sits clear of everything; the ability and weapon wheels are radial and their discs never overlap and stay on the screen.
##  2 the camera at doors: a hero with a facade right at his back keeps the lens THROUGH_ARM from his head (behind the facade, whose culled back faces show the street), widens the view
##    and stays visible; inside a room the lens is never inside a wall or a door frame at a dozen spots and angles.
##  3 the hero is never planted: FIRE held with the stick untouched side-steps him, the camera yaw turns by the angle the step moves the muzzle so the crosshair stays on its target;
##    ADS, the stick, a tap, reduce-motion and a wall beside him stand it down.
##  4 the standing hero is alive: breathing, weight shift and a glance move the rig over a few seconds without a single input.
## Waits on state and counters, never on frame counts; user:// state is reset.
## Run: tools/test.sh tests/test_hud_camera_final.gd

const SAVE := "user://test_hud_camera_final.cfg"
const SETTINGS := "user://test_hud_camera_final_settings.cfg"
const SIZES: Array[Vector2i] = [Vector2i(844, 390), Vector2i(2400, 1080)]
## What the combat frame may hold (visible_controls ids); `interact`, `grab`, `takedown`, `toast`, `subtitle` and `wanted` appear only when they apply.
const ALLOWED: Array[StringName] = [&"stick", &"fire", &"aim", &"jump", &"reload", &"ability", &"swap", &"more", &"pause", &"minimap", &"status", &"objective"]
## Buttons that share a spot or a state on purpose (never on screen together).
const EXCLUSIVE: Array = [[&"swap", &"veh_view"], [&"grab", &"radio_next"], [&"takedown", &"radio_next"], [&"reload", &"crouch"], [&"aim", &"aim"]]       # DOWN (the aircraft's second vertical button) takes RELOAD's place while flying   # AIM on foot and ROCKET in an armed aircraft share a spot (wave 106)

var host: Node
var main: Node
var hud: Hud
var tc: TouchControls
var p: Player
var rig: CameraRig


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func _until(cond: Callable, max_secs: float) -> bool:
	var n := int(max_secs * 60.0)
	while n > 0 and not cond.call():
		await frames(1)
		n -= 1
	return cond.call()


func _cleanup() -> void:
	for f: String in [SAVE, SETTINGS]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	_cleanup()
	TestMode.reset_toggles()
	var was_touch := Game.force_touch
	Game.force_touch = true
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	p = Game.player as Player
	hud = main.find_child("Hud", true, false) as Hud
	var prog := Game.progress as Progress
	TestLib.check(p != null and hud != null and prog != null and hud.touch != null, "main.tscn composes the player, the HUD and the touch controls")
	if p == null or hud == null or prog == null or hud.touch == null:
		Game.force_touch = was_touch
		return
	tc = hud.touch
	rig = p.camera_rig
	prog.autosave_enabled = false
	prog.path = SAVE
	prog.new_campaign()
	hud.settings = UiSettings.new(SETTINGS)
	hud.settings.publish(false)
	(Game.enemies as EnemyManager).clear()
	var enc := Encounters.current
	if enc != null:
		enc.enabled = false
	Game.heat = 0.0
	Game.state = &"play"
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	tc.controls_on = true
	tc.perf_shown = false
	tc.more_open = false
	tc.release_all()
	hud.message_left = 0.0
	hud.toast.clear()
	for id: StringName in WeaponDefs.IDS:
		WeaponDefs.unlock(id)
	var win := host.get_window()
	var old := win.size
	for size: Vector2i in SIZES:
		win.size = size
		await frames(4)
		Game.state = &"play"
		await _combat_frame(size)
		_button_layout(size)
		await _wheels(size)
	win.size = old
	await frames(3)
	await _camera_doors()
	await _camera_rooms()
	await _idle_alive()
	await _combat_step()
	Input.action_release(&"fire")
	_cleanup()
	main.queue_free()
	await frames(5)
	Game.force_touch = was_touch
	Game.state = &"menu"


# --- 1 -------------------------------------------------------------------------------------------------------------------------

func _combat_frame(size: Vector2i) -> void:
	var tag := "%dx%d" % [size.x, size.y]
	tc.more_open = false
	tc._use_near = false
	tc._grab_near = false
	hud.toast.clear()
	hud.message_left = 0.0
	await frames(6)
	var ids := hud.visible_controls()
	var extra: Array[StringName] = []
	for id: StringName in ids:
		if not ALLOWED.has(id):
			extra.append(id)
	TestLib.check(extra.is_empty(), "%s: the combat frame holds only the final controls (extra: %s)" % [tag, str(extra)])
	for need: StringName in ALLOWED:
		TestLib.check(ids.has(need), "%s: the combat frame has %s" % [tag, need])
	# the words on the HUD layer: one objective line, no bar captions, no faction plate
	hud._text_t = 0.0
	hud.scan_log.clear()
	hud.scan_hud = true
	hud.scan_text = true
	hud._hud.queue_redraw()
	await _until(func() -> bool: return not hud.scan_log.is_empty(), 1.0)
	hud.scan_text = false
	hud.scan_hud = false
	var vp := host.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var banned := ["INTEGRITY", "COHERENCE", "NEUTRAL", "HOSTILE", "ALLIED"]
	var bad := ""
	var off := ""
	var screen := Rect2(Vector2.ZERO, vp).grow(2.0)
	var blockers := _blockers(vp, s)
	var clash := ""
	for e: Dictionary in hud.scan_log:
		var t := String(e["text"]).to_upper()
		for w: String in banned:
			if t.contains(w):
				bad = t
		var r: Rect2 = e["rect"]
		if r.size.x > 0.0 and not screen.encloses(r):
			off = t
		for b: Dictionary in blockers:
			if r.size.x > 0.0 and (b["rect"] as Rect2).intersects(r.grow(-1.0)):
				clash = "%s over %s" % [t, b["id"]]
	TestLib.check(bad == "", "%s: no bar captions or faction plate on the phone HUD (%s)" % [tag, bad])
	TestLib.check(off == "", "%s: every HUD text stays on the screen (%s)" % [tag, off])
	TestLib.check(clash == "", "%s: no HUD text sits on a button, the pause button or the minimap (%s)" % [tag, clash])
	# a slim status plate: the two bars together are a small block
	var plate_h := (6.0 + Hud.SLIM_PITCH + Hud.SLIM_H + 7.0) * s
	TestLib.check(plate_h <= 0.12 * vp.y and Hud.SLIM_W * s <= 0.3 * vp.x, "%s: health and energy are two slim bars (%.0f x %.0f px)" % [tag, Hud.SLIM_W * s, plate_h])
	for b: Dictionary in blockers:
		if b["id"] == &"status":
			TestLib.check(not (b["rect"] as Rect2).intersects(_minimap(vp, s)) and not (b["rect"] as Rect2).intersects(_pause_disc_rect(vp, s)), "%s: the status bars clear the minimap and the pause button" % tag)
	# the contextual USE / ENTER: shown next to a car, clear of every other button
	tc._use_near = true
	tc._use_t = 5.0
	await frames(3)
	var with_use := hud.visible_controls()
	TestLib.check(with_use.has(&"interact"), "%s: ENTER shows when a car is in reach" % tag)
	tc._use_near = false
	tc._use_t = 0.0


## Every thing the HUD text must not sit on: the touch discs of the current frame, the pause disc and the minimap (and the slim status block).
func _blockers(vp: Vector2, s: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b: Dictionary in TouchControls.BUTTONS:
		if tc.button_visible(b):
			var c := tc._button_center(b)
			var r := float(b["r"]) * s * UiSettings.s_button_size
			out.append({"id": b["action"], "rect": Rect2(c - Vector2(r, r) * 0.9, Vector2(r, r) * 1.8)})
	out.append({"id": &"pause", "rect": _pause_disc_rect(vp, s)})
	out.append({"id": &"minimap", "rect": _minimap(vp, s)})
	var top := UiUtil.insets_v(vp).x + 6.0 * s
	var w := Hud.SLIM_W * s + 16.0 * s
	out.append({"id": &"status", "rect": Rect2(vp.x * 0.5 - w * 0.5, top, w, (6.0 + Hud.SLIM_PITCH + Hud.SLIM_H + 7.0) * s)})
	return out


func _minimap(_vp: Vector2, _s: float) -> Rect2:
	return tc._minimap_rect()


func _pause_disc_rect(_vp: Vector2, s: float) -> Rect2:
	var c := tc._pause_center()
	return Rect2(c - Vector2(36.0, 36.0) * s, Vector2(72.0, 72.0) * s)


func _button_layout(size: Vector2i) -> void:
	var tag := "%dx%d" % [size.x, size.y]
	var vp := host.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var screen := Rect2(Vector2.ZERO, vp)
	var overlap := ""
	var off := ""
	var small := ""
	for i in TouchControls.BUTTONS.size():
		var a: Dictionary = TouchControls.BUTTONS[i]
		var ca := tc._button_center(a)
		var ra := float(a["r"]) * s * UiSettings.s_button_size
		if float(a["r"]) * 2.0 < UiUtil.TOUCH_MIN:
			small = str(a["action"])
		if not screen.grow(-ra * 0.9).has_point(ca):
			off = str(a["action"])
		for j in range(i + 1, TouchControls.BUTTONS.size()):
			var b: Dictionary = TouchControls.BUTTONS[j]
			var skip := false
			for pair: Array in EXCLUSIVE:
				if (pair[0] == a["action"] and pair[1] == b["action"]) or (pair[1] == a["action"] and pair[0] == b["action"]):
					skip = true
			if skip:
				continue
			var rb := float(b["r"]) * s * UiSettings.s_button_size
			if ca.distance_to(tc._button_center(b)) < ra + rb - 1.0:
				overlap = "%s / %s" % [a["action"], b["action"]]
		var pr := _pause_disc_rect(vp, s)
		if pr.grow(-4.0 * s).intersects(Rect2(ca - Vector2(ra, ra), Vector2(ra, ra) * 2.0).grow(-ra * 0.3)):
			overlap = "%s / pause" % a["action"]
		if _minimap(vp, s).intersects(Rect2(ca - Vector2(ra, ra), Vector2(ra, ra) * 2.0).grow(-ra * 0.3)):
			overlap = "%s / minimap" % a["action"]
	TestLib.check(overlap == "", "%s: no touch button overlaps another, the pause button or the minimap (%s)" % [tag, overlap])
	TestLib.check(off == "", "%s: every touch button is on the screen (%s)" % [tag, off])
	TestLib.check(small == "", "%s: every touch button is at least %d px across (%s)" % [tag, int(UiUtil.TOUCH_MIN), small])


func _wheels(size: Vector2i) -> void:
	var tag := "%dx%d" % [size.x, size.y]
	var vp := host.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	for kind: StringName in [&"ability", &"weapon"]:
		tc._open_wheel(kind, -1, Vector2.ZERO)
		var n := tc.wheel.items.size()
		TestLib.check(tc.wheel.is_open and n >= 3, "%s: the %s wheel opens with %d discs" % [tag, kind, n])
		var worst := 1.0e9
		var inside := true
		var shown := tc.visible_ids().size()
		for i in n:
			var ci := tc.wheel.item_centre(i)
			inside = inside and Rect2(Vector2.ZERO, vp).grow(-RadialWheel.ITEM_R * s * 0.95).has_point(ci)
			for j in range(i + 1, n):
				worst = minf(worst, ci.distance_to(tc.wheel.item_centre(j)))
		TestLib.check(worst >= 2.0 * RadialWheel.ITEM_R * s - 1.0, "%s: the %s wheel discs never overlap (closest %.0f px, need %.0f)" % [tag, kind, worst, 2.0 * RadialWheel.ITEM_R * s])
		TestLib.check(inside, "%s: the %s wheel discs stay on the screen" % [tag, kind])
		TestLib.check(shown >= 0 and tc.wheel.span_deg > 90.0, "%s: the %s wheel is a radial fan (%.0f degrees)" % [tag, kind, tc.wheel.span_deg])
		tc.wheel.close()
		tc.release_all()


# --- 2 -------------------------------------------------------------------------------------------------------------------------

func _hero_to(pos: Vector3, yaw: float) -> void:
	p.teleport_to(pos)
	p.yaw = yaw
	rig.reset_view(yaw, -0.1)
	rig.snap()
	Input.action_release(&"fire")
	await frames(2)


func _camera_doors() -> void:
	var ig := InteriorGameplay.instance
	TestLib.check(ig != null and not ig.doors_of(&"weapons", Game.SPAWN).is_empty(), "the city has a shop door to test the camera at")
	if ig == null or ig.doors_of(&"weapons", Game.SPAWN).is_empty():
		return
	Game.state = &"play"
	var d := ig.doors_of(&"weapons", Game.SPAWN)[0]
	var n: Vector3 = d["normal"]
	var yaw := atan2(-n.x, -n.z)
	# in front of the shop, free arm behind him: the plain third-person view
	await _hero_to((d["wall"] as Vector3) + n * 5.0 + Vector3(0.0, 0.1, 0.0), yaw)
	await _until(func() -> bool: return not rig.is_obstructed(), 3.0)
	var open_d := rig.camera.global_position.distance_to(rig.get_pivot_position())
	TestLib.check(open_d > 2.5 and rig.door_tight < 0.2 and not rig.through_wall, "five metres out the arm is free (%.2f m, framing %.2f)" % [open_d, rig.door_tight])
	# the hero's back against the facade
	await _hero_to((d["wall"] as Vector3) + n * 0.8 + Vector3(0.0, 0.1, 0.0), yaw)
	var ok := await _until(func() -> bool: return rig.door_tight > 0.5 and rig.hero_fade < 0.5, 4.0)
	var dist := rig.camera.global_position.distance_to(rig.get_pivot_position())
	TestLib.check(ok, "a facade at his back: the door framing opens up (framing %.2f, hero fade %.2f)" % [rig.door_tight, rig.hero_fade])
	TestLib.check(rig.through_wall and dist >= CameraRig.THROUGH_ARM - 0.45, "...the lens keeps %.2f m from his head (not %.2f m) by sitting behind the facade (through %s)" % [dist, CameraRig.MIN_ARM, str(rig.through_wall)])
	TestLib.check(rig.camera.fov >= CameraRig.FOV_HIP + 5.0, "...and the picture is wider (%.0f degrees, %.0f on the open street)" % [rig.camera.fov, CameraRig.FOV_HIP])
	var head := rig.get_pivot_position()
	var local := rig.camera.global_basis.inverse() * (head - rig.camera.global_position)
	var ang := rad_to_deg(atan2(Vector2(local.x, local.y).length(), -local.z))
	TestLib.check(local.z < 0.0 and ang < 50.0, "...and his head stays inside the picture (%.0f degrees off the view axis)" % ang)
	# walking away from the wall hands the arm back without a jump
	var prev := dist
	var jump := 0.0
	for k in 12:
		p.teleport_to((d["wall"] as Vector3) + n * (0.8 + 0.4 * float(k + 1)) + Vector3(0.0, 0.1, 0.0))
		await frames(2)
		var dd := rig.camera.global_position.distance_to(rig.get_pivot_position())
		jump = maxf(jump, absf(dd - prev))
		prev = dd
	TestLib.check(jump < 0.7, "walking off the wall changes the arm smoothly (worst step %.2f m per 0.4 m of walking)" % jump)
	# the exit of a building puts the hero a little out, the camera starts with room
	var base_pos := Vector3(d["pos"])
	TestLib.check(InteriorGameplay.EXIT_PUSH > 0.2 and base_pos.distance_to((d["wall"] as Vector3)) > 0.5, "the exit spot is set out from the door by %.2f m" % InteriorGameplay.EXIT_PUSH)


## Inside a room: a dozen spots and angles, and the lens is never inside a wall, a door frame or a prop of the room.
func _camera_rooms() -> void:
	var ig := InteriorGameplay.instance
	if ig == null or ig.doors_of(&"weapons", Game.SPAWN).is_empty():
		return
	var d := ig.doors_of(&"weapons", Game.SPAWN)[0]
	ig.enter(d, true)
	await frames(10)
	TestLib.check(InteriorGameplay.active, "the hero is inside the shop")
	if not InteriorGameplay.active:
		return
	Game.state = &"play"
	var start := p.global_position
	var inside := 0
	var tried := 0
	var space := p.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for k in 14:
		var at := start + Vector3(rng.randf_range(-3.0, 3.0), 0.0, rng.randf_range(-3.0, 3.0))
		var yaw := rng.randf_range(-PI, PI)
		p.teleport_to(at + Vector3(0.0, 0.1, 0.0))
		p.yaw = yaw
		rig.reset_view(yaw, -0.1)
		rig.snap()
		await frames(8)
		tried += 1
		var q := PhysicsPointQueryParameters3D.new()
		q.position = rig.camera.global_position
		q.collision_mask = Game.L_WORLD
		if not space.intersect_point(q, 2).is_empty():
			inside += 1
	TestLib.check(inside == 0, "inside the shop the lens is never inside a wall, a door frame or a prop (%d of %d spots)" % [inside, tried])
	ig.leave(true)
	await frames(8)
	TestLib.check(not InteriorGameplay.active, "the hero is back in the street")
	var out_d := Vector3(d["pos"]) + Vector3(d.get("normal", Vector3.ZERO)) * InteriorGameplay.EXIT_PUSH
	TestLib.check(Vector2(p.global_position.x - out_d.x, p.global_position.z - out_d.z).length() < 1.5, "leaving puts the hero at the door, set out by EXIT_PUSH")


# --- 4 -------------------------------------------------------------------------------------------------------------------------

func _idle_alive() -> void:
	Game.state = &"play"
	Input.action_release(&"fire")
	await _hero_to(Game.SPAWN + Vector3(0.0, 0.1, 0.0), -PI * 0.5)
	await frames(30)
	var loco: Locomotion = p.body.loco if p.body != null else null
	TestLib.check(loco != null and loco.rig != null, "the hero has a living rig")
	if loco == null or loco.rig == null:
		return
	var c0: float = loco._clock
	var b_lo := 1.0e9
	var b_hi := -1.0e9
	var s_lo := 1.0e9
	var s_hi := -1.0e9
	var guard := 0
	while float(loco._clock) - c0 < 5.0 and guard < 3000:
		await frames(1)
		guard += 1
		b_lo = minf(b_lo, loco.rig.breathe)
		b_hi = maxf(b_hi, loco.rig.breathe)
		s_lo = minf(s_lo, loco.rig.sway)
		s_hi = maxf(s_hi, loco.rig.sway)
	TestLib.check(b_hi - b_lo >= 0.03, "standing still he breathes (%.3f swing over 5 s)" % (b_hi - b_lo))
	TestLib.check(s_hi - s_lo >= 0.012, "...and shifts his weight (%.3f sway swing over 5 s)" % (s_hi - s_lo))


# --- 3 -------------------------------------------------------------------------------------------------------------------------

func _combat_step() -> void:
	Game.state = &"play"
	var mgr := Game.enemies as EnemyManager
	mgr.clear()
	p.weapon.switch_to(&"carbine", true)
	p.weapon.ammo = 9999
	var cs := p.combat_step
	await _hero_to(Game.SPAWN + Vector3(0.0, 0.1, 0.0), -PI * 0.5)
	await frames(20)
	# a tap does not step
	cs.travelled = 0.0
	Input.action_press(&"fire")
	await frames(6)
	Input.action_release(&"fire")
	TestLib.check(cs.travelled < 0.01, "a tap of FIRE does not move the hero (%.2f m)" % cs.travelled)
	# held FIRE, stick untouched: the hero steps, the camera keeps the aim point
	var start := p.global_position
	var target := Vector3(start.x, 0.0, start.z) + _fwd(rig.yaw) * 25.0
	cs.travelled = 0.0
	var f0 := cs.flips
	Input.action_press(&"fire")
	var moved := await _until(func() -> bool: return cs.travelled >= 1.2, 6.0)
	var worst_err := 0.0
	for k in 20:
		await frames(2)
		worst_err = maxf(worst_err, absf(_bearing_error(target)))
	var lateral := (p.global_position - start).dot(Vector3(cos(rig.yaw), 0.0, -sin(rig.yaw)))
	Input.action_release(&"fire")
	TestLib.check(moved and cs.travelled >= 1.2, "FIRE held with the stick untouched: the hero steps (%.2f m)" % cs.travelled)
	TestLib.check((p.global_position - start).length() > 0.4 or cs.flips > f0, "...and really leaves his spot (%.2f m away, %.2f m sideways)" % [(p.global_position - start).length(), lateral])
	TestLib.check(worst_err < deg_to_rad(3.0), "...and the crosshair stays on the aim point 25 m ahead (worst %.1f degrees off)" % rad_to_deg(worst_err))
	TestLib.check(cs.active or cs.travelled > 0.0, "the combat step reports itself")
	await frames(30)
	# the stick wins
	cs.travelled = 0.0
	Input.action_press(&"fire")
	Input.action_press(&"move_forward", 1.0)
	await frames(40)
	var t_stick := cs.travelled
	Input.action_release(&"move_forward")
	Input.action_release(&"fire")
	TestLib.check(t_stick < 0.05, "a stick push turns the step off (%.2f m)" % t_stick)
	# ADS: precision, no step
	await frames(20)
	cs.travelled = 0.0
	Input.action_press(&"aim")
	Input.action_press(&"fire")
	await frames(45)
	var t_ads := cs.travelled
	Input.action_release(&"aim")
	Input.action_release(&"fire")
	TestLib.check(t_ads < 0.05, "aiming down the sights stands the step down (%.2f m)" % t_ads)
	# reduce motion
	await frames(20)
	UiSettings.s_reduce_motion = true
	cs.travelled = 0.0
	Input.action_press(&"fire")
	await frames(45)
	var t_rm := cs.travelled
	Input.action_release(&"fire")
	UiSettings.s_reduce_motion = false
	TestLib.check(t_rm < 0.05, "reduce-motion stands the step down (%.2f m)" % t_rm)
	# a wall beside him: never into it
	var ig := InteriorGameplay.instance
	if ig != null and not ig.doors_of(&"weapons", Game.SPAWN).is_empty():
		var d := ig.doors_of(&"weapons", Game.SPAWN)[0]
		var n: Vector3 = d["normal"]
		await _hero_to((d["wall"] as Vector3) + n * 1.0 + Vector3(0.0, 0.1, 0.0), atan2(-n.x, -n.z) + PI * 0.5)       # the wall is to his side
		await frames(20)
		var before := p.global_position
		Input.action_press(&"fire")
		await frames(90)
		Input.action_release(&"fire")
		var wall_d := (p.global_position - (d["wall"] as Vector3)).dot(n)
		TestLib.check(wall_d > 0.25, "firing beside a wall never steps him into it (%.2f m from the facade, moved %.2f m)" % [wall_d, (p.global_position - before).length()])
	await frames(5)


func _fwd(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## Horizontal angle between the camera's view and the line from the hero to `target`.
func _bearing_error(target: Vector3) -> float:
	var to := target - Vector3(p.global_position.x, 0.0, p.global_position.z)
	return wrapf(PlayerUtil.yaw_of(to) - rig.yaw, -PI, PI)
