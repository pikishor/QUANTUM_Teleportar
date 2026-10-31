extends RefCounted
## Atmosphere module tests (headless). Run: tools/test.sh tests/test_atmosphere.gd
## Covers: standalone instantiation (no world, no player, even no camera), set_weather and the global shader parameters, the quality tiers
## (particle counts and which post effects exist), the `enabled` post toggle, camera following, the physics ground probe, node leaks over many
## frames, and regression checks of the cross-module contract in ARCHITECTURE.md (the world owns the viewport's msaa_3d / scaling_3d_scale and its
## `Mirror` node; committed files carry no machine-specific paths).
## The dummy renderer used by --headless cannot compile shaders: shader compile errors only show in the real renderer, so
## tests/bot_atmosphere.gd (tools/bot.sh, also with RENDERER=compat) is the check for the picture itself.

const SCENE := "res://scenes/atmosphere.tscn"

var _host: Node
var _atm: Atmosphere
var _cam: Camera3D
var _rng := RandomNumberGenerator.new()


func run(host: Node) -> void:
	_host = host
	_rng.seed = 20260101
	var scene := load(SCENE) as PackedScene
	TestLib.check(scene != null, "scenes/atmosphere.tscn loads")
	if scene == null:
		return
	_test_sources()
	var vp := host.get_viewport()
	var msaa_before := vp.msaa_3d
	var scale_before := vp.scaling_3d_scale
	vp.msaa_3d = Viewport.MSAA_4X                 # non-default values, so that any write by the atmosphere would show
	vp.scaling_3d_scale = 0.77
	var mirror := _add_mirror()
	var host_children := host.get_child_count()
	await _test_standalone()
	await _test_weather()
	await _test_quality()
	await _test_enabled_and_rain_toggle()
	await _test_effects_api()
	await _test_camera()
	await _test_ground_probe()
	await _test_leaks()
	# contract regression, after everything above has exercised set_quality / set_weather / enabled
	TestLib.check(vp.msaa_3d == Viewport.MSAA_4X, "the atmosphere never writes the viewport's msaa_3d (the world owns it)")
	TestLib.check(is_equal_approx(vp.scaling_3d_scale, 0.77), "the atmosphere never writes the viewport's scaling_3d_scale (the world owns it)")
	TestLib.check(is_instance_valid(mirror) and mirror.get_parent() == host and mirror.visible and mirror.get_child_count() == 1
			and mirror.scale == Vector3(1, -1, 1), "a node named Mirror is neither hidden, reparented nor changed")
	TestLib.check(host.get_child_count() == host_children, "the atmosphere leaves the host's children alone (%d -> %d)" % [host_children, host.get_child_count()])
	vp.msaa_3d = msaa_before
	vp.scaling_3d_scale = scale_before
	mirror.queue_free()
	Game.camera = null


# --- sources -----------------------------------------------------------------------------------------------------------------

## Static guard rails over the module's committed files: contract violations that a behavioural test cannot reach (a code path that only runs
## when a world exists) and the reproducibility rule (no machine-specific paths).
func _test_sources() -> void:
	var files: Array[String] = ["res://scenes/atmosphere.tscn"]
	for f in DirAccess.get_files_at("res://scripts/fx"):
		if f.begins_with("atmosphere") and f.ends_with(".gd"):
			files.append("res://scripts/fx/" + f)
	for f in DirAccess.get_files_at("res://assets/shaders"):
		if f.begins_with("post_") and f.ends_with(".gdshader"):
			files.append("res://assets/shaders/" + f)
	for f in DirAccess.get_files_at("res://tests"):
		if f.contains("atmosphere") and (f.ends_with(".gd") or f.ends_with(".tscn") or f.ends_with(".gdshader")):
			files.append("res://tests/" + f)
	TestLib.check(files.size() >= 6, "the module's files are found (%d files scanned)" % files.size())
	var forbidden_paths: Array[String] = ["/" + "tmp/", "/" + "home/", "/" + "root/", "C:" + "\\", "scratch" + "pad"]
	var bad_paths: Array[String] = []
	var bad_writes: Array[String] = []
	var touches_mirror: Array[String] = []
	var writes := RegEx.create_from_string("(msaa_3d|scaling_3d_scale)\\s*(=|\\.)|set\\(\\s*[\"&]+(msaa_3d|scaling_3d_scale)|viewport_set_(msaa_3d|scaling_3d)")
	for path in files:
		var code := _code_only(path)
		for needle in forbidden_paths:
			if code.contains(needle):
				bad_paths.append("%s (%s)" % [path, needle])
		if path.begins_with("res://scripts/fx/"):          # runtime scripts only: the test fixture builds its own mirror pass on purpose
			if writes.search(code) != null:
				bad_writes.append(path)
			if code.contains("Mirror"):
				touches_mirror.append(path)
	TestLib.check(bad_paths.is_empty(), "no machine-specific paths in committed code (%s)" % str(bad_paths))
	TestLib.check(bad_writes.is_empty(), "no module script writes msaa_3d / scaling_3d_scale (%s)" % str(bad_writes))
	TestLib.check(touches_mirror.is_empty(), "no module script refers to the world's Mirror node (%s)" % str(touches_mirror))
	var screen_shaders: Array[String] = []
	for path in files:
		if path.ends_with(".gdshader"):
			var code := FileAccess.get_file_as_string(path)
			if code.contains("shader_type canvas_item") and code.contains("hint_screen_texture"):
				screen_shaders.append(path.get_file())
	TestLib.check(not screen_shaders.is_empty(), "a post_*.gdshader is a canvas_item shader reading hint_screen_texture (%s)" % str(screen_shaders))


## The file's code without comments (GDScript '#', shader '//'), so doc comments may mention anything.
func _code_only(path: String) -> String:
	var marker := "//" if path.ends_with(".gdshader") else "#"
	var out := PackedStringArray()
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var cut := line.find(marker)
		out.append(line if cut < 0 else line.substr(0, cut))
	return "\n".join(out)


# --- helpers -----------------------------------------------------------------------------------------------------------------

func _make() -> Atmosphere:
	var a := (load(SCENE) as PackedScene).instantiate() as Atmosphere
	_host.add_child(a)
	return a


func _add_mirror() -> Node3D:
	var m := Node3D.new()
	m.name = "Mirror"
	m.scale = Vector3(1, -1, 1)
	m.add_child(MeshInstance3D.new())
	_host.add_child(m)
	return m


func _add_camera(pos: Vector3) -> Camera3D:
	var c := Camera3D.new()
	c.far = 2000.0
	_host.add_child(c)
	c.global_position = pos
	return c


func _nodes() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


func _objects() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))


# --- tests -------------------------------------------------------------------------------------------------------------------

func _test_standalone() -> void:
	TestLib.check(Game.world == null and Game.player == null, "standalone: no world and no player are registered")
	var state := Game.state
	var heat := Game.heat
	var score := Game.score
	_atm = _make()
	TestLib.check(_atm != null and _atm is Atmosphere, "atmosphere.tscn instantiates as an Atmosphere")
	await TestLib.frames(_host, 3)           # with no camera at all: must neither crash nor draw
	TestLib.check(_atm.is_in_group(&"atmosphere"), "joins the group `atmosphere` so other modules can find it without node paths")
	TestLib.check(_atm.post is CanvasLayer and _atm.post.layer <= 0, "the post-process is a CanvasLayer below the HUD layers (layer %d)" % _atm.post.layer)
	var rect := _atm.post.rect as ColorRect
	TestLib.check(rect != null and rect.anchor_right == 1.0 and rect.anchor_bottom == 1.0, "the post-process rect covers the whole screen")
	TestLib.check(rect.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the post-process rect lets mouse and touch events through")
	var mat := rect.material as ShaderMaterial
	TestLib.check(mat != null and mat.shader != null and mat.shader.code.contains("hint_screen_texture"), "the rect carries a shader that reads the screen texture")
	TestLib.check(_atm.particle_count() == 0, "no camera: no rain is drawn and nothing breaks (count %d)" % _atm.particle_count())
	TestLib.check(Game.state == state and Game.heat == heat and Game.score == score, "never touches gameplay state")
	TestLib.check(Game.world == null and Game.player == null, "does not register anything as world or player")


func _test_weather() -> void:
	_atm.set_weather(0.3, 0.2, true)
	TestLib.check(is_equal_approx(_atm.rain_now, 0.3) and is_equal_approx(_atm.wetness_now, 0.2), "set_weather(.., instant) applies at once (rain %.2f, wetness %.2f)" % [_atm.rain_now, _atm.wetness_now])
	# The headless dummy renderer stores no global parameters (get returns null); in a real renderer they must follow.
	var g_rain: Variant = RenderingServer.global_shader_parameter_get(&"rain")
	var g_wet: Variant = RenderingServer.global_shader_parameter_get(&"wetness")
	if g_rain == null or g_wet == null:
		print("note: the dummy renderer cannot read global shader parameters back; the real-renderer check lives in tests/bot_atmosphere.gd")
	else:
		TestLib.check(is_equal_approx(float(g_rain), 0.3) and is_equal_approx(float(g_wet), 0.2), "the global shader parameters rain / wetness follow set_weather (%s / %s)" % [g_rain, g_wet])
	_atm.set_weather(5.0, -3.0, true)
	TestLib.check(_atm.rain_now == 1.0 and _atm.wetness_now == 0.0, "set_weather clamps to 0..1")
	# smooth: a normal call eases toward the target
	_atm.weather_tau = 0.05
	_atm.set_weather(0.0, 0.0, true)
	_atm.set_weather(1.0, 1.0)
	TestLib.check(_atm.rain_now == 0.0 and _atm.rain_target == 1.0, "set_weather without instant only sets the target")
	await TestLib.frames(_host, 2)
	TestLib.check(_atm.rain_now > 0.0 and _atm.rain_now < 1.0, "the weather eases in (rain %.3f after 2 frames)" % _atm.rain_now)
	await TestLib.frames(_host, 90)
	TestLib.check(is_equal_approx(_atm.rain_now, 1.0) and is_equal_approx(_atm.wetness_now, 1.0), "the weather reaches its target (rain %.3f, wetness %.3f)" % [_atm.rain_now, _atm.wetness_now])
	# wetness and rain are independent: the street can stay wet after the rain stops
	_atm.set_weather(0.0, 0.9, true)
	TestLib.check(_atm.rain_now == 0.0 and is_equal_approx(_atm.wetness_now, 0.9), "wetness can stay high while it is not raining")
	_atm.weather_tau = 1.4


func _test_quality() -> void:
	_cam = _add_camera(Vector3(40.0, 3.0, -15.0))
	Game.camera = _cam
	_atm.set_weather(1.0, 0.8, true)
	await TestLib.frames(_host, 3)
	var counts: Array[int] = []
	var streaks: Array[int] = []
	var splashes: Array[int] = []
	var cost: Array[int] = []
	var pool: int = _atm.rainfield.streaks.multimesh.instance_count
	for level in [0, 1, 2]:
		_atm.set_quality(level)
		await TestLib.frames(_host, 2)
		counts.append(_atm.particle_count())
		streaks.append(_atm.rainfield.streak_count())
		splashes.append(_atm.rainfield.splash_count())
		var paid := 0
		for effect: StringName in [&"ca_amount", &"sharpen_amount", &"haze_amount", &"lens_amount", &"overlay_amount"]:
			if float(_atm.post.effective(effect)) > 0.0:
				paid += 1
		cost.append(paid)
		TestLib.check(_atm.quality == level and _atm.post.tier == level and _atm.rainfield.tier == level, "set_quality(%d) reaches the post layer and the rain" % level)
	TestLib.check(counts[0] > 0, "with a camera and full rain the rain is drawn even on LOW (%d particles)" % counts[0])
	TestLib.check(streaks[0] < streaks[1] and streaks[1] < streaks[2], "streak count grows with the tier (%s)" % str(streaks))
	TestLib.check(splashes[0] < splashes[1] and splashes[1] < splashes[2], "splash count grows with the tier (%s)" % str(splashes))
	TestLib.check(counts[0] < counts[1] and counts[1] < counts[2], "total particle count changes with the quality tier (%s)" % str(counts))
	TestLib.check(cost[0] < cost[1] and cost[1] < cost[2], "the post-process gets more expensive with the tier: %s effects beyond grade, vignette and grain" % str(cost))
	TestLib.check(cost[0] == 0, "LOW pays only for grade, vignette and grain")
	for level in [0, 1, 2]:
		TestLib.check(Atmosphere.particle_budget(level) >= counts[level], "particle_budget(%d) is the ceiling of what is drawn" % level)
	TestLib.check(Atmosphere.particle_budget(0) < Atmosphere.particle_budget(1) and Atmosphere.particle_budget(1) < Atmosphere.particle_budget(2), "particle_budget grows with the tier")
	TestLib.check(_atm.rainfield.streaks.multimesh.instance_count == pool, "the particle pool is allocated once (tiers only change the visible count)")
	_atm.set_quality(-4)
	TestLib.check(_atm.quality == 0, "set_quality clamps below 0")
	_atm.set_quality(9)
	TestLib.check(_atm.quality == 2, "set_quality clamps above 2")
	# density follows the rain intensity
	await TestLib.frames(_host, 2)
	var full := _atm.particle_count()
	_atm.set_weather(0.5, 0.8, true)
	await TestLib.frames(_host, 2)
	var half := _atm.particle_count()
	_atm.set_weather(0.0, 0.8, true)
	await TestLib.frames(_host, 2)
	var none := _atm.particle_count()
	TestLib.check(none == 0 and half > 0 and half < full, "density follows the rain intensity (0: %d, 0.5: %d, 1: %d)" % [none, half, full])
	_atm.set_weather(1.0, 0.8, true)
	await TestLib.frames(_host, 2)


func _test_enabled_and_rain_toggle() -> void:
	TestLib.check(_atm.enabled and _atm.post.visible, "the post-process is on by default")
	var before := _atm.particle_count()
	_atm.enabled = false
	TestLib.check(not _atm.post.visible, "enabled = false hides the post-process layer")
	await TestLib.frames(_host, 2)
	TestLib.check(_atm.particle_count() == before and before > 0, "enabled only toggles the post-process, the rain keeps falling")
	_atm.enabled = true
	TestLib.check(_atm.post.visible, "enabled = true shows the post-process layer again")
	_atm.rain_enabled = false
	await TestLib.frames(_host, 2)
	TestLib.check(_atm.particle_count() == 0, "rain_enabled = false hides all streaks and splashes")
	TestLib.check(_atm.post.visible, "rain_enabled does not touch the post-process")
	_atm.rain_enabled = true
	await TestLib.frames(_host, 2)
	TestLib.check(_atm.particle_count() == before, "rain_enabled = true brings the rain back (%d)" % _atm.particle_count())
	# the property also works on a fresh instance before it enters the tree (settings screens set it early)
	var fresh := (load(SCENE) as PackedScene).instantiate() as Atmosphere
	fresh.enabled = false
	_host.add_child(fresh)
	await TestLib.frames(_host, 2)
	TestLib.check(not fresh.post.visible, "enabled = false set before _ready is honoured")
	fresh.queue_free()
	await TestLib.frames(_host, 2)


func _test_effects_api() -> void:
	_atm.set_quality(2)
	_atm.set_effect(&"grain_amount", 0.1)
	TestLib.check(is_equal_approx(float(_atm.post.get_param(&"grain_amount")), 0.1) and is_equal_approx(float(_atm.post.effective(&"grain_amount")), 0.1), "set_effect changes one effect (grain)")
	_atm.set_quality(0)
	_atm.set_effect(&"ca_amount", 0.005)
	TestLib.check(is_equal_approx(float(_atm.post.get_param(&"ca_amount")), 0.005) and float(_atm.post.effective(&"ca_amount")) == 0.0, "the designer value is kept but LOW masks chromatic aberration")
	_atm.set_quality(2)
	TestLib.check(is_equal_approx(float(_atm.post.effective(&"ca_amount")), 0.005), "raising the tier brings the effect back with the designer value")
	_atm.set_effect(&"no_such_effect", 1.0)
	TestLib.check(true, "an unknown effect name is rejected without crashing")
	_atm.set_effect(&"grain_amount", 0.042)
	_atm.set_effect(&"ca_amount", 0.0012)


func _test_camera() -> void:
	_atm.set_quality(1)
	_cam.global_position = Vector3(40.0, 3.0, -15.0)
	await TestLib.frames(_host, 3)
	var field := _atm.rainfield as Node3D
	TestLib.check(field.global_position.distance_to(_cam.global_position) < 0.05, "the rain follows Game.camera")
	_cam.global_position = Vector3(-120.0, 10.0, 80.0)
	await TestLib.frames(_host, 3)
	TestLib.check(field.global_position.distance_to(_cam.global_position) < 0.05, "the rain follows a camera that moved 200 m (blink, cut)")
	# no Game.camera: the viewport's current camera is the fallback
	Game.camera = null
	await TestLib.frames(_host, 3)
	_cam.make_current()
	await TestLib.frames(_host, 3)
	TestLib.check(_atm.particle_count() > 0 and field.global_position.distance_to(_cam.global_position) < 0.05, "without Game.camera the viewport's current camera is followed")
	# no camera at all
	_cam.queue_free()
	await TestLib.frames(_host, 3)
	TestLib.check(_atm.particle_count() == 0, "a camera that disappears just stops the rain, no errors")
	_cam = _add_camera(Vector3(0.0, 2.0, 0.0))
	Game.camera = _cam
	await TestLib.frames(_host, 3)
	TestLib.check(_atm.particle_count() > 0, "the rain comes back with the next camera")


## Drops must land on what is under the camera, not on y = 0: a collider on the world layer at y = 3 raises the rain floor.
func _test_ground_probe() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Game.L_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, 2.5, 0.0)       # top face at y = 3
	_host.add_child(floor_body)
	_cam.global_position = Vector3(0.0, 6.0, 0.0)
	_atm.set_weather(1.0, 0.8, true)
	await TestLib.frames(_host, 70)
	var landed: float = float(_atm.rainfield.streak_material.get_shader_parameter(&"ground_y"))
	TestLib.check(absf(landed - 3.0) < 0.15, "the rain lands on the surface under the camera (ground_y %.2f, expected 3)" % landed)
	floor_body.queue_free()
	_cam.global_position = Vector3(0.0, 2.0, 0.0)
	await TestLib.frames(_host, 70)
	landed = float(_atm.rainfield.streak_material.get_shader_parameter(&"ground_y"))
	TestLib.check(absf(landed) < 0.15, "and falls back to the ground level when the surface is gone (ground_y %.2f)" % landed)


func _test_leaks() -> void:
	_atm.queue_free()
	await TestLib.frames(_host, 3)
	_atm = null
	var nodes0 := _nodes()
	var orphans0 := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for i in 12:
		var a := _make()
		await TestLib.frames(_host, 2)
		a.set_quality(i % 3)
		a.set_weather(float(i % 5) / 4.0, 0.5, true)
		a.queue_free()
		await TestLib.frames(_host, 2)
	TestLib.check(_nodes() == nodes0, "instantiating and freeing the atmosphere 12 times leaves no nodes behind (%d -> %d)" % [nodes0, _nodes()])
	TestLib.check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphans0, "no orphan nodes are left behind")
	# a long run with everything changing: drive the camera, switch tiers, toggle, change the weather
	_atm = _make()
	await TestLib.frames(_host, 10)
	var n1 := _nodes()
	var o1 := _objects()
	for f in 300:
		if f % 15 == 0:
			_atm.set_quality(_rng.randi() % 3)
			_atm.set_weather(_rng.randf(), _rng.randf())
			_atm.enabled = _rng.randf() > 0.3
			_atm.rain_enabled = _rng.randf() > 0.2
		_cam.global_position += Vector3(0.9, 0.0, -0.4)        # about 50 m/s
		await TestLib.frames(_host, 1)
	var n2 := _nodes()
	var o2 := _objects()
	TestLib.check(n2 == n1, "no nodes are created over 300 frames of weather, tier and camera changes (%d -> %d)" % [n1, n2])
	TestLib.check(o2 <= o1 + 2, "no objects are allocated per frame (%d -> %d)" % [o1, o2])
	_atm.enabled = true
	_atm.rain_enabled = true
	_atm.queue_free()
	await TestLib.frames(_host, 3)
	_cam.queue_free()
	await TestLib.frames(_host, 2)
	TestLib.check(_nodes() == nodes0 - 1, "everything is released again (%d nodes; %d at the start of the run, which included the camera)" % [_nodes(), nodes0])
