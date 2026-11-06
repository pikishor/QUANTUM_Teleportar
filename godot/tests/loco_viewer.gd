extends RefCounted
## Locomotion look-dev: the REAL Player (game camera, input actions, physics) on a floor with a grid, driven through idle / walk / jog / run / sprint / strafe / back / turn / stop /
## jump / land. Every case saves a contact sheet of every 2nd frame of the first 2 s from the game camera and from a side camera that follows the hero (a SubViewport on the same world),
## and prints the LocoQA numbers of the case. Run through the test runner with a real renderer (fixed 30 fps, so every frame is 1/30 s):
##   tools/loco_view.sh OUT_DIR [WxH]        env LOCO_CASES=walk,run  LOCO_EVERY=2  LOCO_SECS=2
## The sheets are OUT_DIR/<case>_game.png and OUT_DIR/<case>_side.png.

const Fixture := preload("res://tests/player_fixture.gd")
const Env := preload("res://tests/player_env.gd")

## name, stick strength (0..1), sprint, strafe axis ("" forward, "r" right, "b" back), extra
const CASES: Array = [
	["idle", 0.0, false, "", ""],
	["walk", 0.3, false, "", ""],
	["jog", 0.6, false, "", ""],
	["run", 1.0, false, "", ""],
	["sprint", 1.0, true, "", ""],
	["strafe", 1.0, false, "r", ""],
	["back", 1.0, false, "b", ""],
	["turn", 0.0, false, "", "turn"],
	["stop", 1.0, false, "", "stop"],
	["jump", 1.0, false, "", "jump"],
	["standjump", 0.0, false, "", "jump"],
	["slope", 1.0, false, "", "slope"],
]

var e := Env.new()
var p: Player
var host: Node
var out := "user://loco_view"
var every := 2
var secs := 2.0
var tile := Vector2i(256, 256)
var cols := 10
var _side: SubViewport
var _side_cam: Camera3D
var _wedge: StaticBody3D


func run(h: Node) -> void:
	host = h
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1 and kv[0] == "out":
			out = kv[1]
	if OS.get_environment("LOCO_EVERY") != "":
		every = maxi(1, int(OS.get_environment("LOCO_EVERY")))
	if OS.get_environment("LOCO_TILE") != "":
		tile = Vector2i(int(OS.get_environment("LOCO_TILE")), int(OS.get_environment("LOCO_TILE")))
	if OS.get_environment("LOCO_COLS") != "":
		cols = int(OS.get_environment("LOCO_COLS"))
	if OS.get_environment("LOCO_SECS") != "":
		secs = float(OS.get_environment("LOCO_SECS"))
	DirAccess.make_dir_recursive_absolute(out)
	await e.setup(host)
	p = e.p
	_make_floor_grid()
	_side = SubViewport.new()
	_side.size = Vector2i(tile.x, tile.y)
	_side.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_side_cam = Camera3D.new()
	_side_cam.fov = 40.0
	_side.add_child(_side_cam)
	host.add_child(_side)
	_side_cam.make_current()
	var only := OS.get_environment("LOCO_CASES")
	for c in CASES:
		if only != "" and not (String(c[0]) in only.split(",", false)):
			continue
		await _case(c)
	await e.teardown()


func _make_floor_grid() -> void:
	var fl := e.root.get_node_or_null("Floor") as StaticBody3D
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var edge := x < 3 or y < 3
			var c := Color(0.55, 0.57, 0.6) if edge else (Color(0.22, 0.24, 0.27) if ((x / 32 + y / 32) % 2 == 0) else Color(0.3, 0.32, 0.36))
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.uv1_scale = Vector3(160.0, 160.0, 1.0)                  # one tile = 1 m, grid lines every metre; the dark / light squares are 0.5 m
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.roughness = 0.9
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160.0, 160.0)
	mi.mesh = pm
	mi.material_override = m
	mi.position = Vector3(0.0, 0.002, 0.0)
	fl.add_child(mi)
	var env := WorldEnvironment.new()
	var en := Environment.new()
	en.background_mode = Environment.BG_COLOR
	en.background_color = Color(0.1, 0.12, 0.16)
	en.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	en.ambient_light_color = Color(0.5, 0.52, 0.58)
	en.ambient_light_energy = 0.7
	env.environment = en
	e.root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.0
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	e.root.add_child(sun)


func _case(c: Array) -> void:
	var name: String = c[0]
	var stick: float = c[1]
	var sprint: bool = c[2]
	var dir: String = c[3]
	var extra: String = c[4]
	Fixture.release_inputs()
	if is_instance_valid(_wedge):
		_wedge.queue_free()
	await e.prep(Vector3(0.0, 0.0, -30.0), -PI * 0.5, -0.1, 30)
	if extra == "slope":                                         # a 14 degree ramp, 3 m after the start, 12 m long
		_wedge = _ramp()
	var lc := p.body.loco
	var q := LocoQA.new(p.body.rig, lc)
	if extra == "slope":
		q.ground = func(w: Vector3) -> float: return clampf(tan(deg_to_rad(10.0)) * (w.x - 3.0), 0.0, 5.0)
	var frames: Array[Image] = []
	var sides: Array[Image] = []
	var total := int(secs * 30.0)
	var settle_at := 0
	var t := 0.0
	var f := 0
	var jumped := false
	var stopped_at := -1.0
	var recording_from := -1.0
	var began := false
	while f < total + 45:
		var dt := host.get_process_delta_time()
		# input script
		var act := ""
		var strength := stick
		if extra == "stop":
			if t >= 1.4:
				strength = 0.0
		if extra == "turn":
			p.camera_rig.add_look((3.4 if t > 0.3 else 0.0) / 60.0 * 2.0, 0.0)
		if strength > 0.0:
			match dir:
				"": Input.action_press(&"move_forward", strength)
				"r": Input.action_press(&"move_right", strength)
				"b": Input.action_press(&"move_back", strength)
		else:
			Fixture.release_inputs()
		if sprint:
			Input.action_press(&"sprint")
		if extra == "jump":
			if t >= 0.9 and not jumped:
				jumped = true
				Input.action_press(&"jump")
			elif jumped and t >= 1.0:
				Input.action_release(&"jump")
		await RenderingServer.frame_post_draw
		t += dt
		f += 1
		if f == 30:
			q.begin()
			began = true
		if began:
			q.sample(dt, lc.speed > 0.45 or absf(lc.yaw_rate) > 0.7, 0.0)
		if f >= 30 and (f - 30) % every == 0 and (f - 30) / every < int(secs * 30.0 / every):
			frames.append(_grab_game())
			sides.append(await _grab_side())
		if f - 30 >= int(secs * 30.0):
			break
	Fixture.release_inputs()
	print("LOCO ", name, " speed %.2f " % lc.speed, q.summary())
	_sheet(frames, "%s/%s_game.png" % [out, name], cols)
	_sheet(sides, "%s/%s_side.png" % [out, name], cols)


func _ramp() -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = Game.L_WORLD
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 0.4, 8.0)
	cs.shape = box
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mi.mesh = bm
	b.add_child(mi)
	e.root.add_child(b)
	var a := deg_to_rad(10.0)                                   # a 10 degree ramp from x = 3 m, 30 m long, the low end flush with the floor
	b.global_position = Vector3(3.0 + 15.0 * cos(a) + 0.2 * sin(a), 15.0 * sin(a) - 0.2 * cos(a), -30.0)
	b.rotation.z = a
	return b


func _grab_game() -> Image:
	var img := host.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var cw := mini(img.get_width(), int(img.get_height() * 0.9))        # the middle of the frame, where the hero is
	var crop := img.get_region(Rect2i((img.get_width() - cw) / 2, 0, cw, img.get_height()))
	crop.resize(tile.x, tile.y, Image.INTERPOLATE_BILINEAR)
	return crop


func _grab_side() -> Image:
	var b := p.body
	var right := Vector3(cos(p.yaw), 0.0, -sin(p.yaw))          # the hero's right in the world
	_side_cam.global_position = b.global_position + right * 3.6 + Vector3(0.0, 1.0, 0.0)
	_side_cam.look_at(b.global_position + Vector3(0.0, 0.95, 0.0), Vector3.UP)
	await RenderingServer.frame_post_draw
	var img := _side.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _sheet(imgs: Array[Image], path: String, cols: int) -> void:
	if imgs.is_empty():
		return
	var w := imgs[0].get_width()
	var h := imgs[0].get_height()
	var rows := int(ceil(float(imgs.size()) / cols))
	var sheet := Image.create(w * mini(cols, imgs.size()), h * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.BLACK)
	for i in imgs.size():
		sheet.blit_rect(imgs[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(path)
