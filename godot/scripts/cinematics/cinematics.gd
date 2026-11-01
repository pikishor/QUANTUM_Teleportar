class_name Cinematics
extends Node
## Cutscenes and screen presentation (composed by main.gd after the Stability watchdog; one instance, `Cinematics.instance`, group "cinematics").
##
##  * Scenes (scripts/cinematics/cine_plan.gd builds them as data): `intro` at the first DEPLOY (about 25 s: skyline fly-through, Vael drones, Kestrel on a rooftop,
##    the rift flash, title card), `chapter` (6.5 s orbit with the chapter title and objective after a sector win), `boss_in` (the Overseer is introduced when its
##    contract starts) and `boss_out` (its last moment in slow motion).
##  * A scene runs in the game state `cutscene` (STATE): every module already treats a non-play state as "frozen" (enemies, missions, player, timers), the HUD hides
##    both of its layers and the touch controls let go. The camera is the gameplay rig's own camera (so rain, grade and post stay), driven through CameraRig.cine_set();
##    the pose lapses by itself 0.25 s after the last call, so a scene that ends, errors or is freed can never leave the view stuck.
##  * Always restored: camera, input (the Stability watchdog releases it on every state change), time scale (Stability slow motion, ends with the state), the post grade
##    (saved values put back), the hero's position / look angles (the intro moves Kestrel to a roof and back), the state itself (Stability repairs a cutscene state with no
##    running scene). Any tap, click, Enter, Space, Tab or Esc skips (after MIN_SKIP_AGE); a settings toggle (UiSettings.cutscenes, "CINE" on the title and pause
##    screens) turns scenes off; tools, tests and bots (Game.autostart) never start one on their own unless `force` is set or play() is called.
##  * Presentation outside scenes: the title screen camera (slow parallax behind Kestrel, drones crossing the sky), letterbox bars + vignette on the dead and win screens, a
##    fade from black into play, and a hero close-up for the shop screen. Pooled props (drone models), no per-frame allocation, one canvas layer under the HUD.

signal started(id: StringName)
signal finished(id: StringName, skipped: bool)

const STATE := &"cutscene"
const MIN_SKIP_AGE := 0.45
const FADE_RATE := 2.0
const GRADE_KEYS: Array[StringName] = [&"vignette_amount", &"vignette_start", &"saturation", &"ca_amount", &"gain", &"contrast"]
const COLD_GAIN := Vector3(0.9, 1.02, 1.13)
const WARM_GAIN := Vector3(1.12, 1.0, 0.86)
const TITLE_DRONES := 2
const ENDING_SCENES: Array[String] = ["credits"]

static var instance: Cinematics

var enabled := true                  ## scenes may start by themselves (false under tools, tests and bots)
var force := false                   ## ignore the settings and the "seen" flag (tests, --cine)
var active := false
var active_id: StringName = &""
var plan: CinePlan
var t := 0.0                         ## real seconds into the running scene
var skipped := false
var plays := 0                       ## scenes finished (tests)

var _pending: StringName = &""       ## a scene waiting for the state to become play (set by new_game / next_sector)
var _last_state: StringName = &"menu"
var _overlay: Control
var _layer: CanvasLayer
var _vig_tex: GradientTexture2D
var _vig := 0.0
var _bars := 0.0
var _fade := 0.0
var _flash := 0.0
var _title_t := 0.0
var _closeup_t := 0.0
var _fov_out := PackedFloat32Array([70.0])
var _ev_i := 0
var _hud: Object
var _stab: Object
var _props_root: Node3D
var _pool := {}                      ## model name -> Array[Node3D]
var _used: Array[Node3D] = []        ## props of the running scene / title, index = drone index
var _title_props := false
var _grade_orig := {}
var _grade_on := false
var _hero_moved := false
var _saved := {}
var _boss: Overseer
var _boss_in_for := 0
var _boss_out_for := 0
var _ending_id: StringName = &""     ## the ending scene of the chapter that was just cleared (CampaignData "ending"), played after NEXT SECTOR
var _sub_key := ""
var _sub_lines := PackedStringArray()
var _wrap_key := ""
var _wrap_lines := PackedStringArray()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 50                           # before the camera rig (100): the pose set here is the one it applies this frame
	add_to_group(&"cinematics")
	instance = self
	enabled = not Game.autostart
	for a in OS.get_cmdline_user_args():
		if a == "--cine":
			force = true
			enabled = true
	Game.new_game.connect(_on_new_game)
	Game.next_sector.connect(_on_next_sector)
	Game.sector_cleared.connect(_on_cleared)
	Game.state_changed.connect(_on_state)
	_last_state = Game.state


## The canvas layer, overlay and prop root are built on first use: a game that never shows a scene (tools, tests, bots) carries one node of ours.
func _ensure_nodes() -> void:
	if _overlay != null:
		return
	_layer = CanvasLayer.new()
	_layer.name = "CineLayer"
	_layer.layer = 9                                # under the HUD (10) and the story layer (11): the dead and win screens draw over the bars
	add_child(_layer)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	_overlay.draw.connect(_draw_overlay)
	_layer.add_child(_overlay)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.34, 1.0])
	g.colors = PackedColorArray([Color(0.0, 0.01, 0.03, 0.0), Color(0.0, 0.01, 0.03, 0.9)])
	_vig_tex = GradientTexture2D.new()
	_vig_tex.gradient = g
	_vig_tex.fill = GradientTexture2D.FILL_RADIAL
	_vig_tex.fill_from = Vector2(0.5, 0.5)
	_vig_tex.fill_to = Vector2(1.0, 0.5)
	_vig_tex.width = 96
	_vig_tex.height = 96
	_props_root = Node3D.new()
	_props_root.name = "Props"
	add_child(_props_root)


func _exit_tree() -> void:
	if active:
		_end(false, false)
	_clear_rig()
	_grade_restore()
	if instance == self:
		instance = null


# ---------------------------------------------------------------------------------------------------------------------
# collaborators
# ---------------------------------------------------------------------------------------------------------------------

func _player() -> Player:
	return Game.player as Player if is_instance_valid(Game.player) else null


func _rig() -> CameraRig:
	var p := _player()
	return p.camera_rig if p != null and is_instance_valid(p.camera_rig) else null


func _find_hud() -> Object:
	if is_instance_valid(_hud):
		return _hud
	var par := get_parent()
	if par != null:
		for c in par.get_children():
			if c is Hud:
				_hud = c
				return c
	return null


func _find_stab() -> Object:
	if is_instance_valid(_stab):
		return _stab
	var par := get_parent()
	if par != null:
		for c in par.get_children():
			if c is Stability:
				_stab = c
				return c
	return null


func _settings() -> UiSettings:
	var h := _find_hud()
	return h.get(&"settings") as UiSettings if h != null else null


func scenes_allowed() -> bool:
	var s := _settings()
	return force or (enabled and (s == null or s.cutscenes))


func _hero_pos() -> Vector3:
	var p := _player()
	return p.global_position if p != null else Vector3.ZERO


func _hero_yaw() -> float:
	var p := _player()
	if p != null:
		var y: Variant = p.get(&"yaw")
		if y is float:
			return y
	var r := _rig()
	return r.yaw if r != null else Player.SPAWN_YAW


static func dir_of_yaw(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


# ---------------------------------------------------------------------------------------------------------------------
# triggers
# ---------------------------------------------------------------------------------------------------------------------

func _on_new_game() -> void:
	_pending = &""
	_ending_id = &""
	var prog := Game.progress
	var cont: bool = prog != null and prog.get(&"_continue_pending") == true     # CONTINUE re-uses start_new_game(): no intro
	if cont or not scenes_allowed():
		return
	var s := _settings()
	if force or s == null or not s.intro_seen:
		_pending = &"intro"


## The sector was cleared: when it was a chapter whose data names an ending scene (the last one: "credits"), remember it. The ending cards type over the win screen first
## (Story), the credits follow on NEXT SECTOR.
func _on_cleared() -> void:
	_ending_id = &""
	var st := Game.story
	if not is_instance_valid(st):
		return
	var cs: Variant = CampaignData.chapter(int(st.get(&"chapter"))).get("cutscenes", {})
	var id := str((cs as Dictionary).get("ending", "")) if cs is Dictionary else ""
	if id in ENDING_SCENES:
		_ending_id = StringName(id)


func _on_next_sector() -> void:
	var ending := _ending_id
	_ending_id = &""
	if not scenes_allowed():
		_pending = &""
	elif ending != &"":
		_pending = ending                            # the credits replace the chapter orbit; the aftermath sector's banner follows them
	else:
		_pending = &"chapter"


func _on_state(s: StringName) -> void:
	var from := _last_state
	_last_state = s
	if active:
		if s != STATE:
			_end(false, false)                       # someone else changed the state (pause, death, menu): stop at once, no state write
		return
	if s != &"menu" and _title_props:
		_set_title_props(false)
	if s == &"play":
		if _pending != &"":
			var id := _pending
			_pending = &""
			if play(id):
				return
		if from == &"dead" or from == &"win" or from == &"menu":
			_fade = 1.0                               # a clean cut from the screen into play: fade in from black
	if s != &"menu" and s != &"paused":
		_clear_rig()


# ---------------------------------------------------------------------------------------------------------------------
# scenes
# ---------------------------------------------------------------------------------------------------------------------

## Starts a scene now (from play or the title screen). Returns false when one is running or the state does not allow it.
func play(id: StringName, ctx := {}) -> bool:
	if active or _rig() == null:
		return false
	if Game.state != &"play" and Game.state != &"menu":
		return false
	var c := ctx.duplicate()
	var p := _player()
	var face := dir_of_yaw(_hero_yaw())
	match id:
		&"intro":
			_saved = {"pos": _hero_pos(), "yaw": _hero_yaw(), "view_yaw": _rig().yaw, "view_pitch": _rig().pitch}
			var roof := _find_roof(_hero_pos(), face)
			var rf := CinePlan.flat_dir(-Vector3(roof.x, 0.0, roof.z), Vector3.RIGHT)
			c = {"roof": roof, "roof_face": rf, "spawn": _hero_pos(), "spawn_face": face}
			plan = CinePlan.intro(c)
		&"chapter":
			var st := Game.story
			c = {"hero": _hero_pos(), "face": face, "label": "", "title": "", "sub": "", "obj": ""}
			if is_instance_valid(st):
				var d: Dictionary = st.call(&"chapter_data")
				c["label"] = str(st.call(&"chapter_label"))
				c["title"] = str(d.get("title", ""))
				c["sub"] = str(d.get("sub", ""))
				c["obj"] = str(st.call(&"objective_text"))
			plan = CinePlan.chapter(c)
		&"credits":
			c = {"hero": _hero_pos(), "face": face}
			plan = CinePlan.credits_scene(c)
		&"boss_in", &"boss_out":
			if not c.has("boss"):
				c["boss"] = _boss.global_position if is_instance_valid(_boss) else _hero_pos() + face * 30.0
			c["hero"] = _hero_pos()
			c["face"] = face
			plan = CinePlan.boss_in(c) if id == &"boss_in" else CinePlan.boss_out(c)
		_:
			return false
	active = true
	active_id = id
	t = 0.0
	skipped = false
	_ev_i = 0
	_fade = 1.0
	_flash = 0.0
	_sub_key = ""
	if id == &"intro":
		_move_hero_to_roof(plan)
	_set_props_for_plan()
	_grade_begin()
	Game.state = STATE                              # freezes gameplay; the HUD hides its layers (hud.gd)
	if plan.slowmo:
		var stab := _find_stab()
		if stab != null:
			stab.call(&"begin_slowmo", 0.25, 1.25, 0.8)
	_ensure_nodes()
	_overlay.visible = true
	if id != &"intro":
		Sfx.play(&"ui_confirm", -6.0, 0.6)
	started.emit(id)
	_apply_scene(0.0)
	return true


## A tap, Esc, Enter or Space during a scene.
func skip() -> void:
	if active and plan.skippable and t >= MIN_SKIP_AGE:
		skipped = true
		_end(true, true)


func _input(event: InputEvent) -> void:
	if not active:
		return
	var hit := false
	if event is InputEventScreenTouch:
		hit = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		hit = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventKey:
		var k := event as InputEventKey
		hit = k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER or k.keycode == KEY_SPACE or k.keycode == KEY_ESCAPE or k.keycode == KEY_TAB)
	if hit:
		if t >= MIN_SKIP_AGE:
			skip()
		get_viewport().set_input_as_handled()        # the tap never reaches the game, a card or a button


## Ends the running scene and puts everything back. `set_state`: also return the game to play (false when somebody else already changed the state).
func _end(was_skipped: bool, set_state: bool) -> void:
	if not active:
		return
	var id := active_id
	active = false
	active_id = &""
	var stab := _find_stab()
	if stab != null:
		stab.call(&"end_slowmo")
	_clear_rig()
	_grade_restore()
	_restore_hero()
	_release_props()
	if id == &"intro":
		var s := _settings()
		if s != null and not s.intro_seen:
			s.intro_seen = true
			s.save()
		var st := Game.story
		if is_instance_valid(st) and st.has_method(&"skip_cards"):
			st.call(&"skip_cards")                    # the intro replaces the three prologue cards: chapter intro and tutorial go on from here
	elif id == &"chapter" and is_instance_valid(Game.story):
		Game.story.set(&"banner_t", -1.0)             # the scene showed the chapter title already
	if set_state and Game.state == STATE:
		Game.state = &"play"
	_fade = 0.7 if not was_skipped else 1.0
	_flash = 0.0
	plays += 1
	if id == &"boss_in":
		_boss_in_for = _boss.get_instance_id() if is_instance_valid(_boss) else 0
	finished.emit(id, was_skipped)


func _apply_scene(delta: float) -> void:
	var rig := _rig()
	if rig == null:
		_end(false, true)
		return
	while _ev_i < plan.events.size() and t >= float(plan.events[_ev_i]["t"]):
		_fire_event(str(plan.events[_ev_i]["name"]))
		_ev_i += 1
	plan.sample(t)
	rig.cine_set(plan.cam_transform(), plan.cam_fov)
	for i in _used.size():
		var n := _used[i]
		n.global_position = plan.drone_pos(i, t)
	_flash = plan.flash_at(t)
	_fade = maxf(_fade - delta * FADE_RATE, 0.0)
	_grade_apply(plan.grade_at(t), plan.warm_at(t), _flash)
	var bar_t := plan.bars * CinePlan.smooth(t / 0.9) * (1.0 - CinePlan.smooth((t - (plan.duration - 0.6)) / 0.6))
	_bars = bar_t


func _fire_event(ev: String) -> void:
	match ev:
		"teleport":
			_restore_hero()                           # Kestrel steps out of the rift in the street
			Sfx.play(&"blink")
			FX.shake(0.6)


# ---------------------------------------------------------------------------------------------------------------------
# the hero on the roof
# ---------------------------------------------------------------------------------------------------------------------

## The tallest flat roof 30-110 m from the spawn (a coarse scan, once per intro); a point above the spawn when the world cannot say.
func _find_roof(from: Vector3, face: Vector3) -> Vector3:
	var w: Object = Game.world if is_instance_valid(Game.world) else null
	if w == null or not w.has_method(&"ground_height"):
		return from + face * 6.0 + Vector3(0.0, 24.0, 0.0)
	var best := from + face * 6.0 + Vector3(0.0, 0.0, 0.0)
	var best_score := -1.0
	for ix in range(-11, 12):
		for iz in range(-11, 12):
			var x := from.x + ix * 10.0
			var z := from.z + iz * 10.0
			var d := Vector2(x - from.x, z - from.z).length()
			if d < 30.0 or d > 110.0:
				continue
			var h: float = w.call(&"ground_height", x, z)
			if h < 14.0:
				continue
			var flat := true
			for o: Vector2 in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3), Vector2(6, 6), Vector2(-6, -6)]:
				if absf(float(w.call(&"ground_height", x + o.x, z + o.y)) - h) > 0.4:
					flat = false
					break
			if flat and h - d * 0.05 > best_score:
				best_score = h - d * 0.05
				best = Vector3(x, h, z)
	if best_score < 0.0:
		return from + face * 6.0 + Vector3(0.0, 24.0, 0.0)
	return best


func _move_hero_to_roof(p: CinePlan) -> void:
	var pl := _player()
	var rig := _rig()
	if pl == null or rig == null:
		return
	var roof: Vector3 = p.shots[2].center
	var rf: Vector3 = p.shots[2].face
	var yaw := PlayerUtil.yaw_of(rf)
	pl.teleport_to(roof + Vector3(0.0, 0.05, 0.0))
	pl.yaw = yaw
	pl.rotation.y = yaw
	rig.reset_view(yaw, -0.08)
	_hero_moved = true


func _restore_hero() -> void:
	if not _hero_moved:
		return
	_hero_moved = false
	var pl := _player()
	var rig := _rig()
	if pl == null or rig == null or _saved.is_empty():
		return
	pl.teleport_to(_saved["pos"])
	pl.yaw = _saved["yaw"]
	pl.rotation.y = _saved["yaw"]
	rig.reset_view(_saved["view_yaw"], _saved["view_pitch"])


func _clear_rig() -> void:
	var rig := _rig()
	if rig != null:
		rig.cine_clear()


# ---------------------------------------------------------------------------------------------------------------------
# props (pooled drone models)
# ---------------------------------------------------------------------------------------------------------------------

func _acquire(model: String, scale: float) -> Node3D:
	var arr: Array = _pool.get(model, [])
	_pool[model] = arr
	for n: Node3D in arr:
		if not n.visible:
			n.visible = true
			n.scale = Vector3.ONE * scale
			return n
	_ensure_nodes()
	var node := Game.load_model(model)
	if node == null:
		var mi := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.6
		sph.height = 0.7
		mi.mesh = sph
		node = mi
	node.name = "Prop_" + model
	_props_root.add_child(node)
	node.scale = Vector3.ONE * scale
	arr.append(node)
	return node


func _set_props_for_plan() -> void:
	_release_props()
	for i in plan.drones.size():
		var d := plan.drones[i]
		var n := _acquire(str(d["model"]), float(d["scale"]))
		var v: Vector3 = d["v"]
		var dir := v.normalized() if v.length() > 0.01 else Vector3.FORWARD
		n.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP).scaled(n.scale), plan.drone_pos(i, 0.0))
		_used.append(n)


func _release_props() -> void:
	for n in _used:
		if is_instance_valid(n):
			n.visible = false
	_used.clear()
	_title_props = false


func _set_title_props(on: bool) -> void:
	if on == _title_props:
		return
	if not on:
		_release_props()
		return
	_release_props()
	for i in TITLE_DRONES:
		_used.append(_acquire("drone_sentinel" if i == 0 else "drone_heavy", 3.0 + float(i)))
	_title_props = true


func prop_count() -> int:
	var n := 0
	for k: String in _pool:
		n += (_pool[k] as Array).size()
	return n


# ---------------------------------------------------------------------------------------------------------------------
# grade (the real post-process: vignette, saturation, colour shift)
# ---------------------------------------------------------------------------------------------------------------------

func _post() -> Object:
	var a: Object = Game.atmosphere if is_instance_valid(Game.atmosphere) else null
	return a.get(&"post") if a != null else null


func _grade_begin() -> void:
	var post := _post()
	if post == null or _grade_on:
		return
	for k in GRADE_KEYS:
		_grade_orig[k] = post.call(&"get_param", k)
	_grade_on = true


func _grade_apply(w: float, warm: float, flash: float) -> void:
	if not _grade_on:
		return
	var a: Object = Game.atmosphere
	if not is_instance_valid(a):
		return
	var o := _grade_orig
	a.call(&"set_effect", &"vignette_amount", lerpf(float(o[&"vignette_amount"]), 0.92, w))
	a.call(&"set_effect", &"vignette_start", lerpf(float(o[&"vignette_start"]), 0.24, w))
	a.call(&"set_effect", &"saturation", lerpf(float(o[&"saturation"]), float(o[&"saturation"]) * lerpf(0.8, 1.08, warm), w))
	a.call(&"set_effect", &"ca_amount", lerpf(float(o[&"ca_amount"]), 0.0028 + flash * 0.006, w))
	a.call(&"set_effect", &"gain", (o[&"gain"] as Vector3).lerp(COLD_GAIN.lerp(WARM_GAIN, warm), w * 0.7))
	a.call(&"set_effect", &"contrast", lerpf(float(o[&"contrast"]), minf(float(o[&"contrast"]) + 0.2, 1.0), w))


func _grade_restore() -> void:
	if not _grade_on:
		return
	_grade_on = false
	var a: Object = Game.atmosphere if is_instance_valid(Game.atmosphere) else null
	if a == null:
		return
	for k in GRADE_KEYS:
		a.call(&"set_effect", k, _grade_orig[k])


# ---------------------------------------------------------------------------------------------------------------------
# per frame
# ---------------------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var real := minf(delta / maxf(Engine.time_scale, 0.05), 0.1)
	if active:
		t += real
		if Game.state != STATE or t > plan.duration + 1.5:
			_end(false, Game.state == STATE)
		elif t >= plan.duration:
			_end(false, true)
		else:
			_apply_scene(real)
		_vig = plan.grade_at(t) * 0.8 if active else _vig
	else:
		_idle(real)
	var show := active or _bars > 0.002 or _vig > 0.01 or _fade > 0.01 or _flash > 0.01
	if show:
		_ensure_nodes()
	if _overlay != null:
		_overlay.visible = show
		if show:
			_overlay.queue_redraw()


func _idle(real: float) -> void:
	var st := Game.state
	var bar_goal := 0.0
	var vig_goal := 0.0
	var rig := _rig()
	_fade = maxf(_fade - real * FADE_RATE, 0.0)
	_flash = maxf(_flash - real * 2.0, 0.0)
	if rig != null and Game.state != STATE:
		if st == &"menu":
			bar_goal = 0.075
			vig_goal = 0.55
			_title_t += real
			_set_title_props(true)
			var hero := _hero_pos()
			var face := dir_of_yaw(_hero_yaw())
			rig.cine_set(CinePlan.title_pose(_title_t, hero, face, _fov_out), _fov_out[0])
			for i in _used.size():
				_used[i].global_position = CinePlan.title_drone(i, _title_t, hero, face)
		elif st == &"paused":
			var h := _find_hud()
			if h != null and h.has_method(&"shop_open") and bool(h.call(&"shop_open")):
				_closeup_t += real
				rig.cine_set(CinePlan.closeup_pose(_closeup_t, _hero_pos(), dir_of_yaw(_hero_yaw()), _fov_out), _fov_out[0])
			else:
				_closeup_t = 0.0
		elif st == &"dead" or st == &"win":
			bar_goal = 0.055
			vig_goal = 0.4
		elif st == &"play" and enabled:
			_poll_boss()
	_bars = move_toward(_bars, bar_goal, real * 0.2)
	_vig = move_toward(_vig, vig_goal, real * 0.8)


## The Overseer of a boss contract: remember it, introduce it once, and give its fall a beat.
func _poll_boss() -> void:
	if _boss != null and not is_instance_valid(_boss):
		_boss = null
	if _boss == null:
		var m: Object = Game.missions if is_instance_valid(Game.missions) else null
		var cs: Object = m.get(&"contracts") if m != null else null
		var tgt: Overseer = null
		if cs != null and cs.get(&"state") == &"active" and cs.get(&"kind") == &"boss":
			tgt = cs.get(&"target") as Overseer
		else:
			var cr: Object = m.get(&"campaign") if m != null else null     # a scripted campaign step that hunts an Overseer
			if cr != null and cr.get(&"state") == &"active" and cr.get(&"kind") == &"kill_target":
				tgt = cr.get(&"target") as Overseer
		if tgt == null or not is_instance_valid(tgt):
			return
		_boss = tgt
		if scenes_allowed() and _boss_in_for != _boss.get_instance_id():
			play(&"boss_in")
		return
	if (_boss.dead or _boss.hp <= 0.0) and _boss_out_for != _boss.get_instance_id():
		_boss_out_for = _boss.get_instance_id()
		if scenes_allowed():
			play(&"boss_out", {"boss": _boss.global_position})
		_boss = null


# ---------------------------------------------------------------------------------------------------------------------
# drawing
# ---------------------------------------------------------------------------------------------------------------------

func _shadow(c: Control, font: Font, x: float, y: float, w: float, text: String, size: int, col: Color, sh: float) -> void:
	c.draw_string(font, Vector2(x + sh, y + sh), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, Color(0.0, 0.0, 0.0, col.a * 0.85))
	c.draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, col)


func _draw_overlay() -> void:
	var c := _overlay
	var vp := c.size
	if vp.x < 2.0:
		return
	var s := UiUtil.ui_scale(vp)
	var font := UiUtil.font()
	if _vig > 0.01:
		c.draw_texture_rect(_vig_tex, Rect2(Vector2.ZERO, vp), false, Color(1, 1, 1, clampf(_vig, 0.0, 1.0)))
	var bh := vp.y * _bars
	if bh > 0.5:
		c.draw_rect(Rect2(0.0, 0.0, vp.x, bh), Color.BLACK)
		c.draw_rect(Rect2(0.0, vp.y - bh, vp.x, bh), Color.BLACK)
	if active and font != null:
		_draw_title(c, vp, s, font)
		_draw_credits(c, vp, s, font)
		_draw_subtitle(c, vp, s, font, bh)
		if plan.skippable and t > 1.0 and t < plan.duration - 1.0:
			var a := 0.45 + 0.2 * sin(t * 3.0)
			c.draw_string(font, Vector2(vp.x - 190.0 * s, vp.y - maxf(bh * 0.3, 14.0 * s)), "TAP TO SKIP", HORIZONTAL_ALIGNMENT_RIGHT, 170.0 * s, int(16.0 * s), Color(1, 1, 1, a))
	if _flash > 0.005:
		c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.86, 0.96, 1.0, clampf(_flash, 0.0, 1.0)))
	if _fade > 0.005:
		c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, clampf(_fade, 0.0, 1.0)))


func _draw_title(c: Control, vp: Vector2, s: float, font: Font) -> void:
	var a := plan.title_alpha(t)
	if a <= 0.01 or plan.head == "":
		return
	var y := vp.y * 0.30                           # above the hero's head: the orbit keeps Kestrel in the middle of the picture
	var w := vp.x
	if plan.id == &"intro":
		_shadow(c, font, 0.0, y, w, plan.head, int(76.0 * s), Color(1, 1, 1, a), 3.0 * s)
		c.draw_line(Vector2(vp.x * 0.5 - 240.0 * s, y + 26.0 * s), Vector2(vp.x * 0.5 + 240.0 * s, y + 26.0 * s), Color(UiUtil.MAGENTA, 0.85 * a), 2.0 * s)
		_shadow(c, font, 0.0, y + 62.0 * s, w, plan.tag_line, int(UiUtil.TEXT_MIN * s), Color(UiUtil.CYAN, 0.95 * a), 1.0 * s)
		return
	if plan.tag_line != "":
		_shadow(c, font, 0.0, y - 62.0 * s, w, plan.tag_line, int(UiUtil.TEXT_MIN * s), Color(UiUtil.CYAN, 0.95 * a), 1.0 * s)
	var big := Color(UiUtil.RED, a) if plan.id == &"boss_in" else Color(1, 1, 1, a)
	_shadow(c, font, 0.0, y, w, plan.head, int(64.0 * s), big, 3.0 * s)
	c.draw_line(Vector2(vp.x * 0.5 - 200.0 * s, y + 22.0 * s), Vector2(vp.x * 0.5 + 200.0 * s, y + 22.0 * s), Color(UiUtil.MAGENTA, 0.85 * a), 2.0 * s)
	if plan.sub_line != "":
		_shadow(c, font, 0.0, y + 58.0 * s, w, plan.sub_line, int(UiUtil.TEXT_MIN * s), Color(1, 1, 1, 0.9 * a), 1.0 * s)
	if plan.obj_line != "":
		var size := int(UiUtil.TEXT_MIN * s)
		var width := minf(vp.x * 0.8, 760.0 * s)
		var key := "%s|%d|%d" % [plan.obj_line, int(width), size]
		if key != _wrap_key:
			_wrap_key = key
			_wrap_lines = StoryView.wrap_text(font, "%s  %s" % [CineData.CHAPTER_HEAD, plan.obj_line], width, size)
		var yy := vp.y * (1.0 - plan.bars) - 150.0 * s
		var x0 := (vp.x - width) * 0.5
		for ln in _wrap_lines:
			_shadow(c, font, x0, yy, width, ln, size, Color(UiUtil.AMBER, 0.95 * a), 1.0 * s)
			yy += size * 1.3


## The credits block of the moment: a head line with a rule under it and its lines, in the same band as the chapter title (above Kestrel's head).
func _draw_credits(c: Control, vp: Vector2, s: float, font: Font) -> void:
	var i := plan.credit_index(t)
	if i < 0:
		return
	var a := plan.credit_alpha(t)
	if a <= 0.01:
		return
	var blk: Dictionary = plan.credits[i]
	var y := vp.y * 0.26
	var big := i == 0 or i == plan.credits.size() - 1
	_shadow(c, font, 0.0, y, vp.x, str(blk["head"]), int((72.0 if big else 56.0) * s), Color(1, 1, 1, a), 3.0 * s)
	c.draw_line(Vector2(vp.x * 0.5 - 200.0 * s, y + 22.0 * s), Vector2(vp.x * 0.5 + 200.0 * s, y + 22.0 * s), Color(UiUtil.MAGENTA, 0.85 * a), 2.0 * s)
	var yy := y + 62.0 * s
	for ln: Variant in blk["lines"]:
		_shadow(c, font, 0.0, yy, vp.x, str(ln), int(UiUtil.TEXT_MIN * s), Color(UiUtil.CYAN, 0.95 * a), 1.0 * s)
		yy += UiUtil.TEXT_MIN * s * 1.4


func _draw_subtitle(c: Control, vp: Vector2, s: float, font: Font, bh: float) -> void:
	var sub := plan.subtitle_at(t)
	if sub.is_empty():
		return
	var fade_out := clampf((float(sub["t1"]) - t) / 0.35, 0.0, 1.0)
	var a := minf(clampf((t - float(sub["t0"])) / 0.3, 0.0, 1.0), fade_out)
	var size := int(UiUtil.TEXT_MIN * s)
	var width := minf(vp.x * 0.74, 900.0 * s)
	var key := "%s|%d|%d" % [sub["t"], int(width), size]
	if key != _sub_key:
		_sub_key = key
		_sub_lines = StoryView.wrap_text(font, str(sub["t"]), width, size)
	var h := size * 1.3 * _sub_lines.size() + size * 1.5
	var y0 := vp.y - bh - 18.0 * s - h
	var x0 := (vp.x - width) * 0.5
	c.draw_rect(Rect2(x0 - 14.0 * s, y0 - 4.0 * s, width + 28.0 * s, h + 8.0 * s), Color(0.0, 0.03, 0.05, 0.55 * a))
	var sp := str(sub["s"])
	_shadow(c, font, x0, y0 + size * 0.95, width, sp, int(size * 0.8), Color(StoryView.speaker_color(sp), a), 1.0 * s)
	var yy := y0 + size * 0.95 + size * 1.45
	for ln in _sub_lines:
		_shadow(c, font, x0, yy - size * 0.5, width, ln, size, Color(1, 1, 1, a), 1.0 * s)
		yy += size * 1.3
