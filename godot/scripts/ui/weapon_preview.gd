class_name WeaponPreview
extends SubViewport
## The large 3D weapon preview of the LOADOUT and the weapon catalogue (owner round 5: "a large 3D-rendered weapon preview that can rotate"). One SubViewport with its own little world (a studio
## sky for the reflections, a key and a rim light, an orthographic camera) holds the weapon's own mesh (WeaponModels.mesh, the very one the hero carries) on a turntable: it turns slowly by
## itself, a finger drag turns it by hand (Hud routes the drag, `rotate_by`), and a tap on the picture swings it back to the side view. The texture is drawn into the screen canvas by `draw`.
## It renders only while a screen asks for it (`want()` each draw; two seconds without a request and it stops: no GPU cost in play) and one instance serves every screen (`of(hud)`).
## Tests under the headless renderer get an empty texture and a working API (yaw, mesh, framing).

const SIZE := Vector2i(640, 320)
const IDLE_SPIN := 0.45                  ## radians a second while nobody touches it
const HOLD_TIME := 2.5                   ## seconds the turntable waits after a drag before it spins again
const SIDE_YAW := -1.9                   ## the resting view: the weapon seen from its right side, a little from the front (muzzle to the right)
const PITCH := -0.30
const CROP := 0.82                       ## the middle part of the rendered picture that is shown (the rest is the margin the turntable needs)

var weapon: StringName = &""
var yaw := SIDE_YAW
var drag_hold := 0.0
var _pivot: Node3D
var _mesh: MeshInstance3D
var _cam: Camera3D
var _mat: ShaderMaterial
var _idle := 0.0                          ## seconds since the last request
var _built := false
var framed_size := 0.0                    ## the camera's orthographic size after the last `show_weapon` (tests)

static var _inst: WeaponPreview
static var freeze := false               ## tests and the screenshot bots: no idle spin (a still, repeatable picture)


## The one preview of this Hud (made on first use).
static func of(hud: Node) -> WeaponPreview:
	if is_instance_valid(_inst) and _inst.is_inside_tree():
		return _inst
	_inst = WeaponPreview.new()
	_inst.name = "WeaponPreview"
	hud.add_child(_inst)
	return _inst


func _init() -> void:
	own_world_3d = true
	transparent_bg = true
	size = SIZE
	msaa_3d = Viewport.MSAA_2X
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.45, 0.55, 0.8)
	psm.sky_horizon_color = Color(0.85, 0.88, 0.95)
	psm.ground_horizon_color = Color(0.45, 0.47, 0.55)
	psm.ground_bottom_color = Color(0.16, 0.18, 0.26)
	sky.sky_material = psm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.ambient_light_energy = 1.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.light_energy = 2.6
	key.light_color = Color(1.0, 0.96, 0.9)
	key.rotation_degrees = Vector3(-38.0, -32.0, 0.0)
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 1.2
	rim.light_color = Color(0.45, 0.75, 1.0)
	rim.rotation_degrees = Vector3(-15.0, 150.0, 0.0)
	add_child(rim)
	_pivot = Node3D.new()
	add_child(_pivot)
	_mesh = MeshInstance3D.new()
	_pivot.add_child(_mesh)
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://assets/shaders/weapon_look.gdshader")
	_mat.set_shader_parameter(&"glow", 1.3)
	_mesh.material_override = _mat
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.transform = Transform3D(Basis.from_euler(Vector3(PITCH, 0.0, 0.0)), Vector3(0.0, 0.0, 0.0))
	add_child(_cam)
	_cam.current = true


## Show weapon `id` (its own mesh, framed so that no turn of the turntable clips). False for an id without a model (a throwable or a gadget: the screen draws its picture instead).
func show_weapon(id: StringName) -> bool:
	_build()
	var m := WeaponModels.mesh(id)
	if m == null:
		weapon = &""
		_mesh.mesh = null
		return false
	if id == weapon and _mesh.mesh == m:
		return true
	weapon = id
	_mesh.mesh = m
	var bb := m.get_aabb()
	var cen := bb.get_center()
	_mesh.position = -cen                                          # the pivot turns about the middle of the weapon
	var radius := Vector2(bb.size.x, bb.size.z).length() * 0.5     # the turn sweeps a circle in the ground plane
	var aspect := float(SIZE.x) / float(SIZE.y)
	var vert := bb.size.y * 0.5 + radius * absf(sin(PITCH))        # half the height after the pitch
	var horiz := radius * absf(cos(PITCH)) + 0.02
	framed_size = maxf(vert * 2.0, horiz * 2.0 / aspect) * 1.08
	_cam.size = maxf(framed_size, 0.2)
	_cam.transform = Transform3D(Basis.from_euler(Vector3(PITCH, 0.0, 0.0)), Basis.from_euler(Vector3(PITCH, 0.0, 0.0)).z * 6.0)
	yaw = SIDE_YAW
	drag_hold = 0.0
	_pivot.rotation.y = yaw
	return true


## A finger moved dx px across the picture: turn the weapon by hand (the turntable then waits HOLD_TIME).
func rotate_by(dx: float) -> void:
	yaw = wrapf(yaw + dx * 0.012, -PI, PI)
	drag_hold = HOLD_TIME
	if _pivot != null:
		_pivot.rotation.y = yaw


## A tap on the picture: back to the side view.
func reset_view() -> void:
	yaw = SIDE_YAW
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
	if _idle > 2.0 and render_target_update_mode != SubViewport.UPDATE_DISABLED:
		render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if render_target_update_mode == SubViewport.UPDATE_DISABLED:
		return
	drag_hold = maxf(drag_hold - delta, 0.0)
	if drag_hold <= 0.0 and not freeze:
		yaw = wrapf(yaw + IDLE_SPIN * delta, -PI, PI)
		if _pivot != null:
			_pivot.rotation.y = yaw


## Draw the preview into `r` of canvas `c` (aspect kept, centred). Returns the covered rect.
func draw(c: CanvasItem, r: Rect2) -> Rect2:
	want()
	var ts := Vector2(SIZE)
	var k := minf(r.size.x / ts.x, r.size.y / ts.y)
	var box := Rect2(r.get_center() - ts * k * 0.5, ts * k)
	var src := Rect2(ts * (0.5 - CROP * 0.5), ts * CROP)           # the picture is framed with room for every turn: show its middle so the weapon fills the plate
	c.draw_texture_rect_region(get_texture(), box, src)
	return box
