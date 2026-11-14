extends Node
## Renders the PICTURE of every weapon (wave 114, weapons-ui builder): the weapon's own model (WeaponModels.mesh(id, 0) with its own material) seen from a 3/4 angle in a small studio, a warm key
## light, a cool fill, a soft-box reflection sky for the metal, and a RIM light in the colour of the weapon's class (UiKit.class_tint) from behind, on a transparent background. The picture is
## rendered at 1024 x 512 (2x of the card size) and halved by tools/icons/weapon_atlas.py, which packs the pictures of a class into atlas pages (assets/icons/wp/, scripts/ui/weapon_pics.gd).
## The class-coloured BACKDROP is not baked in: every weapon of a class shares it, so the UI draws it (WeaponPics.draw_backdrop) and the pictures stay usable on the wheel, the HUD plate and the kill
## feed. Run through tools/icons/weapon_pics.sh (software Vulkan under xvfb). Args after `--`: out=DIR only=a_pillar,m_arcsabre class=rifle,melee view=yaw,pitch size=1024x512
## The renderer version (VERSION) goes into the manifest: a change of the lights or the view makes every picture stale.

const VERSION := 3
const DEFAULT_SIZE := Vector2i(1024, 512)
const VIEW_YAW := 122.0                                       ## degrees about +Y: 90 = the weapon's right side, 180 = from the front; 122 is a 3/4 view from the front right
const VIEW_PITCH := -22.0
const VIEW_BY_ID := {&"m_shield": Vector2(20.0, -14.0)}       ## a weapon that is a flat plate shows its face: at the 3/4 view the riot shield was an edge-on sliver (wave 114 critic); an explicit view= argument wins
const FILL := 0.90                                            ## share of the frame the weapon's projected bounds take (the rest is the margin a rim glow and the backdrop need)
const ROLL_FROM := 3.6                                        ## a weapon longer than this (width / height of its projection) is rolled a little so that it uses more of the frame
const ROLL_MAX := 15.0

var _args := {}
var _vp: SubViewport
var _root: Node3D
var _cam: Camera3D
var _rim: DirectionalLight3D
var _rim2: DirectionalLight3D
var _env: Environment
var _ids: Array[StringName] = []
var _out := "/tmp/wpics"
var _yaw := VIEW_YAW
var _pitch := VIEW_PITCH


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			_args[kv[0]] = kv[1]
	_out = String(_args.get("out", "/tmp/wpics"))
	DirAccess.make_dir_recursive_absolute(_out)
	Game.quality = 1
	if _args.has("view"):
		var v := String(_args["view"]).split(",")
		_yaw = float(v[0])
		_pitch = float(v[1]) if v.size() > 1 else VIEW_PITCH
	var size := DEFAULT_SIZE
	if _args.has("size"):
		var sp := String(_args["size"]).split("x")
		size = Vector2i(int(sp[0]), int(sp[1]))
	_build_stage(size)
	_collect()
	Engine.max_fps = 30
	_run.call_deferred()


func _collect() -> void:
	var only := PackedStringArray()
	if _args.has("only"):
		only = String(_args["only"]).split(",", false)
	var cls := PackedStringArray()
	if _args.has("class"):
		cls = String(_args["class"]).split(",", false)
	for id: StringName in WeaponDefs.all_ids():
		if not only.is_empty() and not only.has(String(id)):
			continue
		if not cls.is_empty() and not cls.has(String(WeaponDefs.class_of(id))):
			continue
		_ids.append(id)


## An equirectangular studio sky made in code: a dark gradient with a big soft box top left, a thin strip right and a low warm card, so that polished metal shows real reflections
## (a plain procedural sky reflects as a flat grey).
static func studio_sky() -> Sky:
	var w := 512
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBAF)
	for y in h:
		var v := float(y) / float(h - 1)
		var base := Color(0.10, 0.12, 0.17).lerp(Color(0.03, 0.035, 0.05), clampf(v * 1.4, 0.0, 1.0)) if v < 0.5 else Color(0.03, 0.035, 0.05).lerp(Color(0.015, 0.015, 0.02), (v - 0.5) * 2.0)
		for x in w:
			img.set_pixel(x, y, base)
	_box(img, 0.18, 0.10, 0.20, 0.30, Color(2.6, 2.5, 2.3))                  # the big soft box, upper left
	_box(img, 0.62, 0.22, 0.04, 0.34, Color(1.5, 1.8, 2.2))                  # a cool strip on the right
	_box(img, 0.40, 0.06, 0.12, 0.08, Color(1.8, 1.8, 1.8))                  # a top light
	_box(img, 0.88, 0.40, 0.07, 0.16, Color(1.0, 0.8, 0.6))                  # a warm card low right
	var sky := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = ImageTexture.create_from_image(img)
	pm.filter = true
	sky.sky_material = pm
	return sky


static func _box(img: Image, cx: float, cy: float, hw: float, hh: float, col: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(int((cy - hh) * h), int((cy + hh) * h)):
		for x in range(int((cx - hw) * w), int((cx + hw) * w)):
			var u := absf((float(x) / float(w) - cx) / hw)
			var v := absf((float(y) / float(h) - cy) / hh)
			var k := clampf(1.0 - maxf(u, v), 0.0, 1.0)
			k = clampf(k * 2.2, 0.0, 1.0)                                      # a soft edge
			if y >= 0 and y < h and x >= 0 and x < w:
				var old := img.get_pixel(x, y)
				img.set_pixel(x, y, old.lerp(col, k))


func _build_stage(size: Vector2i) -> void:
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.size = size
	add_child(_vp)
	var env := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_CLEAR_COLOR
	_env.sky = studio_sky()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.ambient_light_energy = 0.7
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.05
	env.environment = _env
	_vp.add_child(env)
	_root = Node3D.new()
	_vp.add_child(_root)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_vp.add_child(_cam)
	_cam.current = true
	# the lights live in the camera's frame (the camera turns about the weapon, the light stays where the viewer expects it)
	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.light_energy = 2.9
	key.light_color = Color(1.0, 0.96, 0.9)
	_cam.add_child(key)
	key.transform = Transform3D(Basis.looking_at(Vector3(0.55, -0.62, -0.58), Vector3.UP), Vector3.ZERO)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_energy = 0.75
	fill.light_color = Color(0.62, 0.76, 1.0)
	_cam.add_child(fill)
	fill.transform = Transform3D(Basis.looking_at(Vector3(-0.75, -0.2, -0.62), Vector3.UP), Vector3.ZERO)
	_rim = DirectionalLight3D.new()
	_rim.name = "Rim"
	_rim.light_energy = 7.0
	_cam.add_child(_rim)
	_rim.transform = Transform3D(Basis.looking_at(Vector3(-0.6, -0.2, 0.78), Vector3.UP), Vector3.ZERO)
	_rim2 = DirectionalLight3D.new()
	_rim2.name = "Rim2"
	_rim2.light_energy = 3.5
	_rim2.light_color = Color(0.9, 0.95, 1.0)
	_cam.add_child(_rim2)
	_rim2.transform = Transform3D(Basis.looking_at(Vector3(0.55, 0.5, 0.67), Vector3.UP), Vector3.ZERO)


func _run() -> void:
	for id in _ids:
		await _make(id)
	print("WEAPON PICS done: ", _ids.size(), " -> ", _out)
	get_tree().quit()


func _make(id: StringName) -> void:
	for c in _root.get_children():
		c.queue_free()
	await get_tree().process_frame
	var mesh := WeaponModels.mesh(id, 0)
	if mesh == null:
		push_error("no model for %s" % id)
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = WeaponModels.material_for(id)
	_root.add_child(mi)
	var tint := UiKit.class_tint(WeaponDefs.class_of(id))
	_rim.light_color = tint.lerp(Color.WHITE, 0.25)
	var yaw_was := _yaw
	var pitch_was := _pitch
	if VIEW_BY_ID.has(id) and not _args.has("view"):
		_yaw = (VIEW_BY_ID[id] as Vector2).x
		_pitch = (VIEW_BY_ID[id] as Vector2).y
	_frame(mesh)
	_yaw = yaw_was
	_pitch = pitch_was
	for i in 6:
		await get_tree().process_frame
	var img := _vp.get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, id])
	print("pic ", id, " ", img.get_size())


## Aim the orthographic camera at the model from the 3/4 view and fit the projected vertex bounds into the frame (FILL of the width or the height, whichever binds). A long weapon is rolled.
func _frame(mesh: Mesh) -> void:
	var faces := mesh.get_faces()
	var bb := mesh.get_aabb()
	var c := bb.get_center()
	var basis := Basis.from_euler(Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), 0.0), EULER_ORDER_YXZ)
	var aspect := float(_vp.size.x) / float(_vp.size.y)
	var roll := 0.0
	for pass_i in 2:                                                     # the second pass fits again after the roll
		var cb := basis
		if roll != 0.0:
			cb = Basis(basis.z, roll) * basis
		var mn := Vector2(1e9, 1e9)
		var mx := Vector2(-1e9, -1e9)
		for p in faces:
			var q := Vector2((p - c).dot(cb.x), (p - c).dot(cb.y))
			mn = mn.min(q)
			mx = mx.max(q)
		var ext := mx - mn
		if pass_i == 0:
			var ar := ext.x / maxf(ext.y, 0.001)
			if ar > ROLL_FROM:
				roll = deg_to_rad(-minf((ar - ROLL_FROM) * 4.0 + 5.0, ROLL_MAX))
				continue
		var size := maxf(ext.y, ext.x / aspect) / FILL
		_cam.size = maxf(size, 0.05)
		var mid := (mn + mx) * 0.5
		_cam.global_transform = Transform3D(cb, c + cb.z * 20.0 + cb.x * mid.x + cb.y * mid.y)
		return
