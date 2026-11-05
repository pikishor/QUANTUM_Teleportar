class_name PhotoMode
extends Node
## PHOTO MODE (pause menu PHOTO button): a pause-like free camera. The game stays in Game.state == &"paused" (never get_tree().paused); Hud owns this node (`Hud.photo`), hides the
## gameplay HUD while it is active and draws the controls (scripts/ui/photo_screen.gd). Leaving it (EXIT, Esc, or any state change) restores the camera, the hero, the grade and the hour.
##  * camera: its own Camera3D (Game.camera while active) orbiting a focus point near the hero: orbit / pan / zoom by mouse (left drag, right or middle drag, wheel) or touch (one finger orbit
##    or pan, two fingers pinch + drag), FOV, depth-of-field-lite (CameraAttributesPractical far + near blur, only while active), pose presets that frame the hero.
##  * look: FILTER = a district's grade pinned through Atmosphere.look_override (MED / HIGH; LOW has no post pass), TIME slider = DayNight.set_hour, HIDE UI, HIDE HERO.
##  * SHOT saves a PNG to user://photos (UI hidden for the grab), SHARE is a placeholder hook (`share_hook`, no network): it emits `share_requested` and says so on screen.
##  * reduce motion: the camera follows its targets instantly and the shutter flash is off.

signal captured(path: String)          ## "" when the grab failed (headless runs have no picture)
signal share_requested(path: String)
signal ended

const DIR := "user://photos"
const FOV_MIN := 35.0
const FOV_MAX := 110.0
const DIST_MIN := 1.0
const DIST_MAX := 16.0
const PAN_MAX := 30.0                  ## metres the focus may drift from the hero (the streamed city stays around him)
const ORBIT_RAD_PER_PX := 0.006
const PITCH_LIMIT := 1.25
const DOF_MAX := 0.12
const FOCUS_HEIGHT := 1.1
const FILTERS: Array[StringName] = [&"auto", &"market", &"foundry", &"slums", &"towers", &"mono"]
const MONO := {"gain": Vector3(1.04, 1.04, 1.04), "lift": Vector3.ZERO, "sat": 0.0}
## Hero pose presets: the camera angle relative to the way the hero faces (0 = in front of him), pitch, distance and FOV.
const POSES: Array[Dictionary] = [
	{"id": &"front", "name": "FRONT", "a": 0.0, "pitch": 0.05, "dist": 3.2, "fov": 70.0},
	{"id": &"three_quarter", "name": "THREE QUARTER", "a": 0.7, "pitch": 0.08, "dist": 3.6, "fov": 72.0},
	{"id": &"side", "name": "SIDE", "a": PI * 0.5, "pitch": 0.02, "dist": 3.6, "fov": 70.0},
	{"id": &"back", "name": "BACK", "a": PI, "pitch": 0.1, "dist": 4.0, "fov": 80.0},
	{"id": &"low", "name": "LOW HERO", "a": 0.4, "pitch": -0.28, "dist": 4.2, "fov": 78.0},
	{"id": &"wide", "name": "WIDE CITY", "a": PI, "pitch": 0.2, "dist": 10.0, "fov": 96.0},
]

## SHARE hook placeholder: a platform layer may set a Callable(path: String) -> bool here later. Nothing in this project touches the network.
static var share_hook := Callable()

var active := false
var hide_ui := false
var hide_hero := false
var pan_mode := false                  ## one finger / left drag pans instead of orbiting
var filter_i := 0
var pose_i := -1
var shots := 0                         ## saved photos this run of the game (a counter tests wait on)
var shot_fails := 0
var shares := 0
var last_path := ""
var status := ""                       ## one line shown on the photo screen (saved / failed / share note)
var status_left := 0.0
var flash := 0.0                       ## 0..1 shutter flash, off with reduce motion / reduce flash
var camera: Camera3D
var focus := Vector3.ZERO
var yaw := 0.0                         ## camera azimuth around the focus: offset = (sin yaw, 0, cos yaw) * dist
var pitch := 0.0
var dist := 4.0
var fov := 78.0
var dof := 0.0
var hour := 21.0

var _t_focus := Vector3.ZERO
var _t_yaw := 0.0
var _t_pitch := 0.0
var _t_dist := 4.0
var _t_fov := 78.0
var _prev_cam: Camera3D
var _prev_hero_visible := true
var _prev_hour := 21.0
var _prev_override := {}
var _attrs: CameraAttributesPractical
var _hero_pos := Vector3.ZERO
var _touches := {}                     ## finger index -> position (fingers that started on empty screen)
var _mouse_drag := 0                   ## 1 left, 2 right / middle, 0 none
var _capturing := false
var _hud: Hud


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hud = get_parent() as Hud


func _exit_tree() -> void:
	if active:
		end()


## Starts photo mode from the paused game. False when it cannot (not paused, no hero or camera).
func begin() -> bool:
	if active or Game.state != &"paused" or not is_instance_valid(Game.player) or not (Game.player is Node3D):
		return false
	var rig_cam := Game.camera
	if rig_cam == null or not rig_cam.is_inside_tree():
		return false
	var p := Game.player as Node3D
	_prev_cam = rig_cam
	_prev_hero_visible = p.visible
	_hero_pos = p.global_position
	camera = Camera3D.new()
	camera.name = "PhotoCamera"
	camera.top_level = true
	camera.keep_aspect = rig_cam.keep_aspect
	camera.near = rig_cam.near
	camera.far = rig_cam.far
	add_child(camera)
	focus = _hero_focus()
	var off := rig_cam.global_position - focus
	dist = clampf(off.length(), DIST_MIN, DIST_MAX)
	yaw = atan2(off.x, off.z)
	pitch = clampf(asin(clampf(off.y / maxf(off.length(), 0.001), -1.0, 1.0)), -PITCH_LIMIT, PITCH_LIMIT)
	fov = clampf(rig_cam.fov, FOV_MIN, FOV_MAX)
	dof = 0.0
	hide_ui = false
	hide_hero = false
	pan_mode = false
	filter_i = 0
	pose_i = -1
	status = ""
	status_left = 0.0
	flash = 0.0
	_t_focus = focus
	_t_yaw = yaw
	_t_pitch = pitch
	_t_dist = dist
	_t_fov = fov
	_attrs = CameraAttributesPractical.new()
	camera.attributes = _attrs
	var atm := Game.atmosphere as Atmosphere
	_prev_override = atm.look_override.duplicate() if atm != null else {}
	var dn := _day_night()
	hour = dn.hour if dn != null else 21.0
	_prev_hour = hour
	active = true
	_apply_camera()
	camera.make_current()
	Game.camera = camera
	if _hud != null:
		_hud.photo_layers()
	return true


## Back to the game camera, hero, grade and hour. Game.state is left alone (the pause menu comes back; a state change that ended it keeps its new state).
func end() -> void:
	if not active:
		return
	active = false
	_touches.clear()
	_mouse_drag = 0
	var atm := Game.atmosphere as Atmosphere
	if atm != null:
		atm.look_override = _prev_override
	if is_instance_valid(Game.player) and Game.player is Node3D:
		(Game.player as Node3D).visible = _prev_hero_visible
	var dn := _day_night()
	if dn != null:
		dn.set_hour(_prev_hour)
	if is_instance_valid(_prev_cam) and _prev_cam.is_inside_tree():
		_prev_cam.make_current()
		Game.camera = _prev_cam
	elif Game.camera == camera:
		Game.camera = null
	if camera != null:
		camera.queue_free()
		camera = null
	_prev_cam = null
	_attrs = null
	if _hud != null:
		_hud.photo_layers()
	ended.emit()


func _day_night() -> DayNight:
	var w := Game.world as City
	return w.day_night if w != null else null


func _hero_focus() -> Vector3:
	return (Game.player as Node3D).global_position + Vector3(0.0, FOCUS_HEIGHT, 0.0)


## The way the hero faces, as a camera azimuth (the azimuth of a camera standing in front of him).
func hero_azimuth() -> float:
	var p := Game.player as Node3D
	var n: Node3D = p
	if p.get("body") is Node3D:
		n = p.get("body") as Node3D
	var f := -n.global_basis.z
	return atan2(f.x, f.z)


# ---------------------------------------------------------------------------------------------------------------------
# camera
# ---------------------------------------------------------------------------------------------------------------------

func camera_position() -> Vector3:
	var o := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	var pos := focus + o
	pos.y = maxf(pos.y, 0.4)
	return pos


func _apply_camera() -> void:
	if camera == null:
		return
	var pos := camera_position()
	if pos.distance_to(focus) > 0.05:
		camera.look_at_from_position(pos, focus, Vector3.UP)
	camera.fov = fov
	if _attrs != null:
		var on := dof > 0.01
		_attrs.dof_blur_far_enabled = on
		_attrs.dof_blur_near_enabled = on
		_attrs.dof_blur_amount = dof * DOF_MAX
		_attrs.dof_blur_far_distance = dist + 4.0
		_attrs.dof_blur_far_transition = dist * 2.0 + 8.0
		_attrs.dof_blur_near_distance = maxf(dist - 1.5, 0.3)
		_attrs.dof_blur_near_transition = maxf(dist * 0.4, 0.5)


## Jumps the camera to its targets (reduce motion does this every frame).
func settle() -> void:
	focus = _t_focus
	yaw = _t_yaw
	pitch = _t_pitch
	dist = _t_dist
	fov = _t_fov
	_apply_camera()


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.05)
	status_left = maxf(status_left - real, 0.0)
	flash = maxf(flash - real * 3.0, 0.0)
	if not active:
		return
	if UiSettings.s_reduce_motion:
		settle()
		return
	var k := 1.0 - exp(-12.0 * real)
	focus = focus.lerp(_t_focus, k)
	yaw = lerp_angle(yaw, _t_yaw, k)
	pitch = lerpf(pitch, _t_pitch, k)
	dist = lerpf(dist, _t_dist, k)
	fov = lerpf(fov, _t_fov, k)
	_apply_camera()


## Drag in pixels: orbit around the focus (or pan in PAN mode).
func orbit(d: Vector2) -> void:
	if not active:
		return
	if pan_mode:
		pan(d)
		return
	_t_yaw -= d.x * ORBIT_RAD_PER_PX
	_t_pitch = clampf(_t_pitch + d.y * ORBIT_RAD_PER_PX, -PITCH_LIMIT, PITCH_LIMIT)
	pose_i = -1


## Drag in pixels: slides the focus along the camera's right and up, kept near the hero.
func pan(d: Vector2) -> void:
	if not active or camera == null:
		return
	var b := camera.global_basis
	var k := _t_dist * 0.0016
	_t_focus += (-b.x * d.x + b.y * d.y) * k
	var off := _t_focus - _hero_focus()
	if off.length() > PAN_MAX:
		_t_focus = _hero_focus() + off.normalized() * PAN_MAX
	_t_focus.y = maxf(_t_focus.y, 0.3)
	pose_i = -1


## Multiplies the orbit distance (f < 1 comes closer).
func zoom(f: float) -> void:
	if not active:
		return
	_t_dist = clampf(_t_dist * f, DIST_MIN, DIST_MAX)


func set_fov(v: float) -> void:
	_t_fov = clampf(v, FOV_MIN, FOV_MAX)
	fov = _t_fov


func set_dof(v: float) -> void:
	dof = clampf(v, 0.0, 1.0)
	_apply_camera()


func set_dist(v: float) -> void:
	_t_dist = clampf(v, DIST_MIN, DIST_MAX)
	dist = _t_dist
	_apply_camera()


func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)
	var dn := _day_night()
	if dn != null:
		dn.set_hour(hour)


func set_filter(i: int) -> void:
	filter_i = posmod(i, FILTERS.size())
	var atm := Game.atmosphere as Atmosphere
	if atm == null:
		return
	var id := FILTERS[filter_i]
	var g := {}
	if id == &"mono":
		g = MONO.duplicate()
	elif PostFx2.GRADES.has(id):
		g = (PostFx2.GRADES[id] as Dictionary).duplicate()
	atm.look_override = g
	if atm.post != null and not g.is_empty():
		var gg: Dictionary = g
		atm.post.set_param(&"d_gain", gg["gain"])
		atm.post.set_param(&"d_lift", gg["lift"])
		atm.post.set_param(&"d_sat", gg["sat"])


func filter_name() -> String:
	return "AUTO" if FILTERS[filter_i] == &"auto" else String(FILTERS[filter_i]).to_upper()


func set_pose(i: int) -> void:
	if not active:
		return
	pose_i = posmod(i, POSES.size())
	var d: Dictionary = POSES[pose_i]
	_t_focus = _hero_focus()
	_t_yaw = hero_azimuth() + float(d["a"])
	_t_pitch = float(d["pitch"])
	_t_dist = float(d["dist"])
	_t_fov = float(d["fov"])
	if UiSettings.s_reduce_motion:
		settle()


func pose_name() -> String:
	return "POSE" if pose_i < 0 else String((POSES[pose_i] as Dictionary)["name"])


func toggle_ui() -> void:
	hide_ui = not hide_ui
	if _hud != null:
		_hud.photo_layers()


func toggle_hero() -> void:
	hide_hero = not hide_hero
	if is_instance_valid(Game.player) and Game.player is Node3D:
		(Game.player as Node3D).visible = (not hide_hero) and _prev_hero_visible


func toggle_pan_mode() -> void:
	pan_mode = not pan_mode


# ---------------------------------------------------------------------------------------------------------------------
# sliders of the photo screen
# ---------------------------------------------------------------------------------------------------------------------

func fraction(id: StringName) -> float:
	match id:
		&"photo_fov": return clampf((_t_fov - FOV_MIN) / (FOV_MAX - FOV_MIN), 0.0, 1.0)
		&"photo_dof": return dof
		&"photo_time": return hour / 24.0
		&"photo_zoom": return clampf((_t_dist - DIST_MIN) / (DIST_MAX - DIST_MIN), 0.0, 1.0)
	return 0.0


func set_fraction(id: StringName, f: float) -> void:
	f = clampf(f, 0.0, 1.0)
	match id:
		&"photo_fov": set_fov(lerpf(FOV_MIN, FOV_MAX, f))
		&"photo_dof": set_dof(snappedf(f, 0.05))
		&"photo_time": set_hour(snappedf(f * 24.0, 0.25))
		&"photo_zoom": set_dist(lerpf(DIST_MIN, DIST_MAX, f))


func hour_text() -> String:
	var m := int(round(hour * 60.0)) % 1440
	return "%02d:%02d" % [m / 60, m % 60]


# ---------------------------------------------------------------------------------------------------------------------
# SHOT and SHARE
# ---------------------------------------------------------------------------------------------------------------------

func say(text: String, seconds := 2.5) -> void:
	status = text
	status_left = seconds


## Hides the controls, grabs the picture, saves it to user://photos and says what happened. Counters `shots` / `shot_fails` change when it is done; `captured` fires.
func capture() -> void:
	if not active or _capturing:
		return
	_capturing = true
	if _hud != null:
		_hud.photo_grab(true)
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var img: Image = null
	if DisplayServer.get_name() != "headless":                      # the dummy renderer has no picture (and logs an error when asked)
		var tex := get_viewport().get_texture()
		if tex != null:
			img = tex.get_image()
	if _hud != null:
		_hud.photo_grab(false)
	_capturing = false
	var path := save_image(img)
	if path != "":
		if not UiSettings.s_reduce_motion and not UiSettings.s_reduce_flash:
			flash = 1.0
		say("PHOTO SAVED")
	else:
		say("PHOTO FAILED")
	captured.emit(path)


## Writes an image as the next photo file. Returns its path, "" when there is no usable image or the write failed.
func save_image(img: Image) -> String:
	if img == null or img.is_empty():
		shot_fails += 1
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
	var path := "%s/photo_%s_%03d.png" % [DIR, stamp, shots + shot_fails + 1]
	var n := 0
	while FileAccess.file_exists(path):
		n += 1
		path = "%s/photo_%s_%03d_%d.png" % [DIR, stamp, shots + shot_fails + 1, n]
	if img.save_png(path) != OK:
		shot_fails += 1
		return ""
	shots += 1
	last_path = path
	return path


## SHARE placeholder: nothing is sent anywhere. The hook (a later platform layer) gets the path of the last photo; without one the screen says sharing is not available yet.
func share() -> void:
	if not active:
		return
	if last_path == "":
		say("TAKE A PHOTO FIRST")
		return
	shares += 1
	share_requested.emit(last_path)
	if share_hook.is_valid():
		share_hook.call(last_path)
		say("SHARED")
	else:
		say("SHARING NOT AVAILABLE YET")


# ---------------------------------------------------------------------------------------------------------------------
# input: drags on the empty screen move the camera (buttons belong to the Hud)
# ---------------------------------------------------------------------------------------------------------------------

func _on_ui(pos: Vector2) -> bool:
	return _hud != null and _hud._button_at(pos) != &""


func _input(event: InputEvent) -> void:
	if not active or camera == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.device == InputEvent.DEVICE_ID_EMULATION:
			return                                                     # a finger already comes through the touch events
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(0.9)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(1.1)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_mouse_drag = 0 if _on_ui(mb.position) else (1 if mb.button_index == MOUSE_BUTTON_LEFT else 2)
			else:
				_mouse_drag = 0
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if _mouse_drag == 1:
			orbit(mm.relative)
		elif _mouse_drag == 2:
			pan(mm.relative)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed and not _on_ui(st.position):
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if not _touches.has(sd.index):
			return
		if _touches.size() == 1:
			orbit(sd.relative)
		elif _touches.size() == 2:
			var other: Vector2 = Vector2.ZERO
			for k: Variant in _touches:
				if k != sd.index:
					other = _touches[k]
			var before: Vector2 = _touches[sd.index]
			var d0 := before.distance_to(other)
			var d1 := sd.position.distance_to(other)
			if d0 > 8.0 and d1 > 8.0:
				zoom(clampf(d0 / d1, 0.8, 1.25))
			pan(sd.relative * 0.5)                                    # the midpoint moves half as far as the finger that moved
		_touches[sd.index] = sd.position
