extends RefCounted
## Deterministic animation bot of the hero (and a trooper) in the real city: run with a fixed frame step, so every rendered frame is exactly 1/30 game second:
##   tools/anim_check.sh OUT_PREFIX [WxH]            (godot --fixed-fps 30 ... -- --bot=res://tests/bot_animation.gd --out=PREFIX)     env RENDERER=compat, BOT_ONLY=walk,jump
## It prints
##   BOT tree ...     every visible MeshInstance3D under the hero and a trooper (exactly one body mesh plus the intended extras)
##   BOT slide ...    foot slide per stride: for every ground contact of a foot (from heel strike to toe-off) the largest horizontal distance the sole point moved in the
##                    world, in centimetres (mean, max, number of strides); the target is under 3 cm
##   BOT seq ...      pelvis height range, knee flexion, per sequence
## and writes at most SHOTS (12) pictures per sequence, PREFIX_<sequence>_<n>.png, taken by a side camera that follows the character.

const Fixture := preload("res://tests/player_fixture.gd")

const SHOTS := 8
## name, frames, kind
const SEQS: Array = [
	["walk", 66, "walk"],
	["sprint", 60, "sprint"],
	["strafe", 66, "strafe"],
	["back", 60, "back"],
	["turn", 54, "turn"],
	["idle", 60, "idle"],
	["jump", 54, "jump"],
	["aim", 54, "aim"],
	["hit", 30, "hit"],
	["death", 36, "death"],
	["trooper", 90, "trooper"],
	["trooper_death", 45, "trooper_death"],
]

var _out := "user://anim"
var _seqs: Array = []
var _idx := -1
var _f := 0
var _setup_done := false
var _p: Player
var _cam: Camera3D
var _cam_off := Vector3(3.4, 0.2, 0.0)             ## right of the character (x right, y up, z back), in the body frame
var _op: Operative
var _slide := {}                                    ## per foot: {start: Vector3, max: float, active: bool}
var _slides: Array[float] = []
var _pelvis_lo := 9.0
var _pelvis_hi := 0.0
var _knee_max := 0.0
var _shots_left := 0
var _shot_every := 6
var _pending_shot := ""
var _target_is_op := false
var _tree_done := false
var _pic_w := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1 and kv[0] == "out":
			_out = kv[1]
	_seqs = SEQS.duplicate()
	var only := OS.get_environment("BOT_ONLY")
	if only != "":
		var keep := only.split(",", false)
		_seqs = _seqs.filter(func(s: Array) -> bool: return String(s[0]) in keep)


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	_p.max_hp = 1.0e6
	Game.enemies.patrol_groups().clear()
	Game.enemies.clear()
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 400.0
	_p.get_tree().root.add_child(_cam)
	for n in _p.get_tree().root.find_children("*", "Stability", true, false):
		n.set_process(false)
	for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
		(n as AutoQuality).enabled = false
	Game.set_quality(2)


func _reset_player() -> void:
	Fixture.release_inputs()
	Game.state = &"play"
	_p.invuln = 0.0
	_p.hp = _p.max_hp
	_p.energy = _p.max_energy
	_p.weapon.reset()
	if _p.is_dead():
		Game.do_respawn()
	_p.teleport_to(Game.SPAWN)
	_p.camera_rig.reset_view(-PI * 0.5, -0.05)
	_p.yaw = -PI * 0.5
	_p.body.reset_pose()


func _enter(i: int) -> void:
	var s: Array = _seqs[i]
	var kind: String = s[2]
	Fixture.release_inputs()
	Game.enemies.clear()
	_op = null
	_target_is_op = false
	_reset_player()
	_slide = {}
	_slides.clear()
	_pelvis_lo = 9.0
	_pelvis_hi = 0.0
	_knee_max = 0.0
	_cam_off = Vector3(3.4, 0.2, 0.0)
	_shot_every = maxi(1, int(s[1]) / SHOTS)
	_shots_left = SHOTS
	match kind:
		"trooper", "trooper_death":
			_op = Game.enemies.spawn(&"operative", Game.SPAWN + Vector3(9.0, 0.0, 0.0), true) as Operative
			_target_is_op = true
			_cam_off = Vector3(3.6, 0.2, 0.0)
			_shots_left = SHOTS
		"death":
			_cam_off = Vector3(3.6, 0.6, 0.6)
		"turn", "idle", "aim", "hit":
			_cam_off = Vector3(2.6, 0.2, -0.8)
	print("BOT seq ", s[0], " start")


func _target() -> Node3D:
	return _op if _target_is_op and is_instance_valid(_op) else _p.body


func _loco() -> Locomotion:
	if _target_is_op and is_instance_valid(_op):
		return _op.loco
	return _p.body.loco


func _rig() -> CharacterRig:
	return _loco().rig if _loco() != null else null


func _place_cam() -> void:
	var t := _target()
	var yaw: float = _op.yaw if _target_is_op and is_instance_valid(_op) else _p.yaw
	var f := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var r := Vector3(cos(yaw), 0.0, -sin(yaw))
	var base := t.global_position + Vector3(0.0, 1.0, 0.0)
	_cam.global_position = base + r * _cam_off.x - f * _cam_off.z + Vector3(0.0, _cam_off.y, 0.0)
	_cam.look_at(base + Vector3(0.0, 0.0, 0.0), Vector3.UP)
	_cam.make_current()


func _sole_world(k: int) -> Vector3:
	var rg := _rig()
	var rest := rg.sole_rest(k)
	var mv := rg.bone_move(CharacterRig.FOOT_L if k == 0 else CharacterRig.FOOT_R)
	return rg.model.global_transform * (mv * rest)


## Slide bookkeeping: while a foot is planted, track how far its sole point moves from where it touched down.
func _measure() -> void:
	var lc := _loco()
	var rg := _rig()
	if lc == null or rg == null:
		return
	for k in 2:
		var prog := lc.stance_progress(k)
		var st: Dictionary = _slide.get(k, {"active": false, "start": Vector3.ZERO, "max": 0.0})
		var moving := lc.speed > 0.4 or absf(lc.yaw_rate) > 0.7
		if prog >= 0.0 and moving:
			var w := _sole_world(k)
			if not st["active"]:
				st["active"] = true
				st["start"] = w
				st["max"] = 0.0
			else:
				var dv: Vector3 = w - (st["start"] as Vector3)
				st["max"] = maxf(float(st["max"]), Vector2(dv.x, dv.z).length())
		elif st["active"]:
			st["active"] = false
			_slides.append(float(st["max"]) * 100.0)
		_slide[k] = st
	var hips := rg.model.global_transform * rg.bone_move(CharacterRig.HIPS) * Vector3(0.0, rg._hips_rest_y, 0.0)
	var gy := rg.model.global_position.y
	_pelvis_lo = minf(_pelvis_lo, hips.y - gy)
	_pelvis_hi = maxf(_pelvis_hi, hips.y - gy)
	_knee_max = maxf(_knee_max, absf(rg.skeleton.get_bone_pose(rg.skeleton.find_bone("ShinL")).basis.get_euler().x))


func _report(name: String) -> void:
	if _slides.is_empty():
		print("BOT seq %s: no stride measured; pelvis height %.2f..%.2f m, knee max %.2f rad" % [name, _pelvis_lo, _pelvis_hi, _knee_max])
		return
	var sum := 0.0
	var mx := 0.0
	for v in _slides:
		sum += v
		mx = maxf(mx, v)
	print("BOT slide %s: mean %.2f cm  max %.2f cm over %d strides (target < 3); pelvis %.2f..%.2f m, knee max %.2f rad" % [name, sum / _slides.size(), mx, _slides.size(), _pelvis_lo, _pelvis_hi, _knee_max])


func _dump_tree() -> void:
	_tree_done = true
	var op := Game.enemies.spawn(&"operative", Game.SPAWN + Vector3(9.0, 0.0, 0.0), true) as Operative
	var roots: Array = [["hero", _p], ["trooper", op]]
	for r in roots:
		var vis := 0
		for n in (r[1] as Node).find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var shown := mi.is_visible_in_tree() and mi.layers != 0 and mi.mesh != null
			print("BOT tree %s: %s visible=%s layers=%d skinned=%s shadow=%d mesh=%s" % [r[0], (_p.get_path_to(mi) if r[1] == _p else op.get_path_to(mi)), str(mi.is_visible_in_tree()), mi.layers,
					str(mi.skin != null or mi.skeleton != NodePath("")), mi.cast_shadow, mi.mesh.get_class() if mi.mesh != null else "none"])
			if shown:
				vis += 1
		print("BOT tree %s: %d MeshInstance3D drawn at rest (flash cards hidden until a shot)" % [r[0], vis])
	Game.enemies.clear()


func _run(kind: String, k: int) -> void:
	var f := _f
	match kind:
		"walk":
			if k == 4:
				Input.action_press(&"move_forward")
		"sprint":
			if k == 4:
				Input.action_press(&"move_forward")
				Input.action_press(&"sprint")
		"strafe":
			if k == 4:
				Input.action_press(&"move_right")
			if k == 26:
				Input.action_release(&"move_right")
				Input.action_press(&"move_left")
			if k == 48:
				Input.action_release(&"move_left")
		"back":
			if k == 4:
				Input.action_press(&"move_back")
		"turn":
			if k >= 8 and k < 40:
				_p.camera_rig.add_look(0.07, 0.0)
		"jump":
			if k == 4:
				Input.action_press(&"move_forward")
			if k == 22:
				Input.action_press(&"jump")
			if k == 24:
				Input.action_release(&"jump")
			if k == 46:
				Input.action_release(&"move_forward")
		"aim":
			if k == 6:
				Input.action_press(&"aim")
			if k == 30:
				Input.action_press(&"move_right")
		"hit":
			if k == 8:
				_p.damage(20.0, _p.global_position + Vector3(0.0, 1.0, -3.0).rotated(Vector3.UP, _p.yaw) * 1.0)
			if k == 20:
				_p.damage(20.0, _p.global_position + Vector3(3.0, 1.0, 0.0).rotated(Vector3.UP, _p.yaw))
		"death":
			if k == 6:
				_p.damage(1.0e7, _p.global_position + Vector3(2.0, 1.0, -3.0))
		"trooper":
			pass
		"trooper_death":
			if k == 3 and is_instance_valid(_op):
				_op.damage(500.0, true)
				_op._death_kind = int(f / 45) % 3 if false else _op._death_kind
	_place_cam()


func step(_t: float, _delta: float) -> bool:
	if Game.player == null or Game.enemies == null:
		return false
	if not _setup_done:
		_setup()
	if not _tree_done and Engine.get_process_frames() > 8:
		_dump_tree()
	if not _tree_done:
		return false
	if _idx < 0 or _f >= int((_seqs[_idx] as Array)[1]):
		if _idx >= 0:
			_report(String((_seqs[_idx] as Array)[0]))
		_idx += 1
		_f = 0
		if _idx >= _seqs.size():
			Fixture.release_inputs()
			return true
		_enter(_idx)
	_f += 1
	var s: Array = _seqs[_idx]
	_run(String(s[2]), _f)
	_measure()
	if _f % _shot_every == 0 and _shots_left > 0 and _out != "":
		_shots_left -= 1
		_snap("%s_%s_%02d.png" % [_out, s[0], SHOTS - _shots_left - 1])
	return false


func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _p.get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("bot_animation: no image (needs a real renderer, not --headless)")
		return
	img.save_png(path)
