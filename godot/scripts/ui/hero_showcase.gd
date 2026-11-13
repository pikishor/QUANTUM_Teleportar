class_name HeroShowcase
extends SubViewport
## The live 3D picture of the hero in the SUIT screen (wave 112): the real hero model (HeroCharacter.build, the very kit and material the game uses) standing on a lit pedestal in a small
## studio of its own, on a turntable: it turns slowly by itself, a finger drag turns it by hand (Hud routes the drag, `rotate_by`) and a tap swings it back to the front. It follows the look
## in hand: a changed body, skin, hair, beard or armour SET rebuilds the model, a changed suit, scheme or accent only rewrites the material (HeroLook.apply_material).
## The preview has its OWN HeroGlow (never the live hero's `HeroGlow.primary`): the circuits breathe and run a wave every few seconds so the glow reads in the picture.
## It renders only while a screen asks for it (`want()` each draw; two idle seconds stop the viewport, twelve free the model) and one instance serves every screen (`of(host)`).
## `capture()` renders the hero from a framing (full / waist / bust) into an Image for the portraits (HeroPortrait, tools/hero/bake_portraits.sh). Under the headless renderer the texture
## is empty and the API still works (yaw, rebuilds, counters).

const SIZE := Vector2i(456, 720)
const IDLE_SPIN := 0.55                  ## radians a second while nobody touches it
const HOLD_TIME := 2.5                   ## seconds the turntable waits after a drag
const REST_YAW := 0.42                   ## the resting view: the hero turned a little toward the viewer's left (a three quarter view from the front)
const FREE_AFTER := 12.0                 ## idle seconds after which the model is freed (the next request builds it again)
const CROP_H := 570.0                    ## capture window height in viewport px (the width is the full 456: a 4:5 portrait)
## camera framings: centre height (m), height of the subject (m), distance (m)
const FRAMES := {&"full": [0.93, 2.2, 5.6], &"waist": [1.40, 0.98, 3.4], &"bust": [1.52, 0.78, 2.5]}

var yaw := REST_YAW
var drag_hold := 0.0
var hero: Node3D
var rig: CharacterRig
var mat: ShaderMaterial
var glow: HeroGlow
var info := {}                           ## HeroCharacter.build info of the shown model (tris, lods, ...)
var builds := 0                          ## how many models this preview built (tests: a palette change must not rebuild)
var frame_kind: StringName = &"full"
var accent := Color(0.2, 0.95, 1.0)
var _geo_key := ""
var _pal_key := ""
var _pivot: Node3D
var _cam: Camera3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _idle := 0.0
var _t := 0.0
var _wave := 1.5                         ## seconds until the next circuit wave
var _built := false
var _capturing := false

static var _inst: HeroShowcase
static var freeze := false               ## tests and the screenshot bots: no idle spin, no waves (a still, repeatable picture)


## The one showcase of this host (made on first use).
static func of(host: Node) -> HeroShowcase:
	if is_instance_valid(_inst) and _inst.is_inside_tree():
		return _inst
	_inst = HeroShowcase.new()
	_inst.name = "HeroShowcase"
	host.add_child(_inst)
	return _inst


static func alive() -> bool:
	return is_instance_valid(_inst) and _inst.is_inside_tree()


func _init() -> void:
	own_world_3d = true
	transparent_bg = true
	size = SIZE
	msaa_3d = Viewport.MSAA_2X
	screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build_stage()


func _build_stage() -> void:
	if _built:
		return
	_built = true
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	var sky := Sky.new()
	sky.process_mode = Sky.PROCESS_MODE_REALTIME               # the radiance map is complete in one frame (the default builds it over many)
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.1, 0.13, 0.22)
	psm.sky_horizon_color = Color(0.3, 0.34, 0.44)
	psm.ground_horizon_color = Color(0.2, 0.21, 0.27)
	psm.ground_bottom_color = Color(0.05, 0.055, 0.08)
	sky.sky_material = psm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.7
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = e
	add_child(we)
	var key := DirectionalLight3D.new()                           # a warm key from the front left above, the same weight the hero has in the street
	key.light_energy = 2.3
	key.light_color = Color(1.0, 0.95, 0.88)
	key.rotation_degrees = Vector3(-34.0, 148.0, 0.0)
	add_child(key)
	var rim := DirectionalLight3D.new()                           # a cool rim from behind right: the silhouette separates from the dark
	rim.light_energy = 1.5
	rim.light_color = Color(0.55, 0.8, 1.0)
	rim.rotation_degrees = Vector3(-18.0, -30.0, 0.0)
	add_child(rim)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.45
	fill.light_color = Color(0.8, 0.85, 1.0)
	fill.rotation_degrees = Vector3(-5.0, 235.0, 0.0)
	add_child(fill)
	var disc := MeshInstance3D.new()                               # the pedestal: a dark glossy disc with an accent ring
	var cm := CylinderMesh.new()
	cm.top_radius = 0.72
	cm.bottom_radius = 0.76
	cm.height = 0.05
	cm.radial_segments = 40
	cm.rings = 1
	disc.mesh = cm
	disc.position = Vector3(0.0, -0.025, 0.0)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.045, 0.055, 0.075)
	dm.metallic = 0.7
	dm.roughness = 0.32
	disc.material_override = dm
	add_child(disc)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.66
	tm.outer_radius = 0.71
	tm.rings = 40
	tm.ring_segments = 6
	_ring.mesh = tm
	_ring.position = Vector3(0.0, 0.004, 0.0)
	_ring.scale = Vector3(1.0, 0.12, 1.0)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = accent
	_ring.material_override = _ring_mat
	add_child(_ring)
	var blob := MeshInstance3D.new()                               # a soft contact shadow under the feet
	var qm := QuadMesh.new()
	qm.size = Vector2(1.3, 1.3)
	qm.orientation = PlaneMesh.FACE_Y
	blob.mesh = qm
	blob.position = Vector3(0.0, 0.012, 0.0)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(0.0, 0.0, 0.0, 0.62))
	gr.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	bm.albedo_texture = gt
	blob.material_override = bm
	add_child(blob)
	_pivot = Node3D.new()
	_pivot.rotation.y = yaw
	add_child(_pivot)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	set_frame(&"full")


## The camera framing: `kind` is a key of FRAMES. The portrait kinds are framed so that the centre CROP_H rows of the picture hold the subject (a 4:5 window).
func set_frame(kind: StringName) -> void:
	_build_stage()
	var f: Array = FRAMES.get(kind, FRAMES[&"full"])
	frame_kind = kind if FRAMES.has(kind) else &"full"
	var cy := float(f[0])
	var h := float(f[1])
	var d := float(f[2])
	var vis := h if frame_kind == &"full" else h * float(SIZE.y) / CROP_H
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.fov = rad_to_deg(2.0 * atan(vis * 0.5 / d))
	_cam.near = 0.1
	_cam.far = 30.0
	_cam.position = Vector3(0.0, cy, -d)
	_cam.look_at(Vector3(0.0, cy, 0.0), Vector3.UP)


## The geometry key of a look: the options that make a different model (the armour set, the body, the skin, the hair, the beard).
static func geo_opts(look: HeroLook) -> Dictionary:
	if look == null:
		return HeroCharacter.sanitize({})
	return HeroCharacter.sanitize({"body": look.body, "skin": look.skin_tone, "hair": look.hair, "beard": look.beard, "suit": look.kit_set()})


## Show `look`: a different model when the geometry key changed, else only the material. False when the hero kit is not available.
func show_look(look: HeroLook) -> bool:
	_build_stage()
	var opts := geo_opts(look)
	var key := "%s|%s|%s|%s|%s" % [opts["body"], opts["skin"], opts["hair"], opts["beard"], opts["suit"]]
	if hero == null or key != _geo_key:
		if not _rebuild(opts):
			return false
		_geo_key = key
		_pal_key = ""
	var pk := HeroPortrait.signature(look)
	if pk != _pal_key and look != null:
		_pal_key = pk
		accent = look.apply_material(mat, glow, 1, false)
		_ring_mat.albedo_color = accent
		glow.update(0.0)
		glow.apply_to(mat)
	return true


func _rebuild(opts: Dictionary) -> bool:
	if hero != null and is_instance_valid(hero):
		_pivot.remove_child(hero)
		hero.free()
	hero = null
	rig = null
	mat = null
	if not HeroCharacter.available(opts["body"]):
		return false
	var o := opts.duplicate()
	o["gear"] = true
	o["armed"] = false
	var r := HeroCharacter.build(o)
	if r["root"] == null:
		return false
	if not bool(r["ok"]):
		(r["root"] as Node).free()
		return false
	hero = r["root"]
	mat = r["material"]
	info = r["info"]
	_pivot.add_child(hero)
	rig = CharacterRig.find(hero)                                  # reads the wrist empties: they go only after it
	for n: String in ["Fill", "Rim", "Muzzle", "WristL", "WristR", "MagWell", "MagPouch"]:
		var x := hero.get_node_or_null(n)
		if x != null:
			hero.remove_child(x)
			x.free()
	if rig != null:
		HumanoidAnim.relax_arms(rig)
		rig.ik = false
		rig.ready = 0.0
	if glow == null:
		glow = HeroGlow.new()
	builds += 1
	_pose(0.0)
	return true


func _pose(dt: float) -> void:
	if rig == null:
		return
	rig.clock += dt
	rig.apply()


## A finger moved dx px across the picture: turn the hero by hand (the turntable then waits HOLD_TIME).
func rotate_by(dx: float) -> void:
	yaw = wrapf(yaw + dx * 0.012, -PI, PI)
	drag_hold = HOLD_TIME
	if _pivot != null:
		_pivot.rotation.y = yaw


## A tap on the picture: back to the front view.
func reset_view() -> void:
	yaw = REST_YAW
	drag_hold = HOLD_TIME
	if _pivot != null:
		_pivot.rotation.y = yaw


## A screen draws the preview this frame: keep rendering.
func want() -> void:
	_idle = 0.0
	if render_target_update_mode != SubViewport.UPDATE_ALWAYS:
		render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _process(delta: float) -> void:
	_idle += delta
	if not _capturing:
		if _idle > FREE_AFTER:
			queue_free()
			return
		if _idle > 2.0 and render_target_update_mode != SubViewport.UPDATE_DISABLED:
			render_target_update_mode = SubViewport.UPDATE_DISABLED
			return
		if render_target_update_mode == SubViewport.UPDATE_DISABLED:
			return
	_t += delta
	drag_hold = maxf(drag_hold - delta, 0.0)
	if drag_hold <= 0.0 and not freeze and not _capturing:
		yaw = wrapf(yaw + IDLE_SPIN * delta, -PI, PI)
		if _pivot != null:
			_pivot.rotation.y = yaw
	if glow != null and mat != null:
		_wave -= delta
		if _wave <= 0.0 and not freeze and not _capturing:
			_wave = 5.0
			glow.pulse(accent, 1.5, 1.1)                        # a wave of light through the circuits now and then
		glow.update(delta)
		glow.apply_to(mat)
	_pose(delta)


## Draw the preview into `r` of canvas `c` (aspect kept, centred). Returns the covered rect.
func draw(c: CanvasItem, r: Rect2) -> Rect2:
	want()
	var ts := Vector2(SIZE)
	var k := minf(r.size.x / ts.x, r.size.y / ts.y)
	var box := Rect2(r.get_center() - ts * k * 0.5, ts * k)
	c.draw_texture_rect(get_texture(), box, false)
	return box


## Renders `look` from the framing `kind` at `view_yaw` and returns the picture as an Image (null under the headless renderer or when the kit is missing). `kind` full returns the whole
## viewport (transparent background); waist and bust return the 4:5 window (456 x 570 px). Waits for the frames itself: call it with await.
func capture(look: HeroLook, kind: StringName = &"bust", view_yaw := REST_YAW, settle_frames := 5) -> Image:
	if not show_look(look):
		return null
	_capturing = true
	var saved := [yaw, frame_kind, drag_hold]
	set_frame(kind)
	yaw = view_yaw
	_pivot.rotation.y = yaw
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_idle = 0.0
	for i in settle_frames:
		await get_tree().process_frame
		_idle = 0.0
	await RenderingServer.frame_post_draw
	var img := get_texture().get_image()
	yaw = saved[0]
	_pivot.rotation.y = yaw
	drag_hold = saved[2]
	set_frame(saved[1])
	_capturing = false
	_idle = 0.0
	if img == null or img.is_empty():
		return null
	if kind != &"full":
		var top := int((float(SIZE.y) - CROP_H) * 0.5)
		img = img.get_region(Rect2i(0, top, SIZE.x, int(CROP_H)))
	return img
