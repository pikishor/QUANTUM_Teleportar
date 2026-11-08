extends Node
## Renders a picture (icon) of every weapon, throwable, gadget, vehicle and enemy type from its own 3D model: one transparent PNG each, written to <out>/<kind>_<id>.png.
## Kinds: w_ weapon (WeaponModels mesh, muzzle on the right), g_ gadget / throwable (small stand-in solids), v_ vehicle (the real Vehicle node), e_ enemy (the glb, tinted).
## Run through tools/icons/build_icons.sh (software Vulkan under xvfb; it then palettises the PNGs into assets/icons/). Args after `--`: out=DIR only=w_pistol,v_sedan
## The game never needs a renderer for them: ItemIcons loads the committed PNGs (res://assets/icons) and falls back to the flat silhouettes without them.

const SIZE_W := Vector2i(384, 192)          ## rendered 2x, the build script halves it
const SIZE_SQ := Vector2i(256, 256)
const SIZE_E := Vector2i(224, 256)

var _args := {}
var _vp: SubViewport
var _root: Node3D
var _cam: Camera3D
var _jobs: Array[Dictionary] = []
var _out := "/tmp/icons"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			_args[kv[0]] = kv[1]
	_out = String(_args.get("out", "/tmp/icons"))
	DirAccess.make_dir_recursive_absolute(_out)
	Game.quality = 1
	_build_stage()
	_collect_jobs()
	Engine.max_fps = 30
	_run.call_deferred()


func _build_stage() -> void:
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.size = SIZE_W
	add_child(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	var sky := Sky.new()                                            # a plain studio sky for reflections and ambient light; the background stays clear
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.55, 0.62, 0.8)
	psm.sky_horizon_color = Color(0.9, 0.9, 0.95)
	psm.ground_horizon_color = Color(0.5, 0.5, 0.55)
	psm.ground_bottom_color = Color(0.2, 0.22, 0.28)
	sky.sky_material = psm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.ambient_light_energy = 1.1
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.light_energy = 2.0
	key.light_color = Color(1.0, 0.96, 0.9)
	key.rotation_degrees = Vector3(-38.0, -32.0, 0.0)
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 1.1
	rim.light_color = Color(0.45, 0.75, 1.0)
	rim.rotation_degrees = Vector3(-15.0, 150.0, 0.0)
	_vp.add_child(rim)
	_root = Node3D.new()
	_vp.add_child(_root)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_vp.add_child(_cam)
	_cam.current = true


func _collect_jobs() -> void:
	var only := PackedStringArray()
	if _args.has("only"):
		only = String(_args["only"]).split(",", false)
	var all: Array[Dictionary] = []
	for id: StringName in WeaponDefs.IDS:
		all.append({"key": "w_%s" % id, "kind": "w", "id": id})
	for id: StringName in Gear.THROW_IDS:
		all.append({"key": "g_%s" % id, "kind": "g", "id": id})
	for id: StringName in Gear.GADGET_IDS:
		all.append({"key": "g_%s" % id, "kind": "g", "id": id})
	all.append({"key": "g_c4", "kind": "g", "id": &"c4"})                                   # the QUANTUM CHARGE (C4) and its detonator: not a Gear item, always carried
	for id: StringName in VehicleSpecs.ROSTER:
		all.append({"key": "v_%s" % id, "kind": "v", "id": id})
	for id: StringName in EnemyTypes.TYPES:
		all.append({"key": "e_%s" % id, "kind": "e", "id": id})
	for j in all:
		if only.is_empty() or only.has(String(j["key"])):
			_jobs.append(j)


func _run() -> void:
	for j in _jobs:
		await _make(j)
	print("ICONS done: ", _jobs.size(), " -> ", _out)
	get_tree().quit()


func _make(j: Dictionary) -> void:
	for c in _root.get_children():
		c.queue_free()
	await get_tree().process_frame
	var kind := String(j["kind"])
	var id: StringName = j["id"]
	var node: Node3D = null
	var view := Vector3(0.0, 0.0, 0.0)
	match kind:
		"w":
			node = _weapon_node(id)
			view = Vector3(deg_to_rad(-20.0), deg_to_rad(115.0), 0.0)         # seen from its right side, a little from the front and above: the muzzle points right
			_vp.size = SIZE_W
		"g":
			node = _gear_node(id)
			view = Vector3(deg_to_rad(-22.0), deg_to_rad(150.0), 0.0)
			_vp.size = SIZE_SQ
		"v":
			node = _vehicle_node(id)
			view = Vector3(deg_to_rad(-15.0), deg_to_rad(133.0), 0.0)             # front three-quarter, the car faces right
			_vp.size = SIZE_W
		"e":
			node = _enemy_node(id)
			view = Vector3(deg_to_rad(-6.0), deg_to_rad(158.0), 0.0)
			_vp.size = SIZE_E
	if node == null:
		push_error("no model for %s" % j["key"])
		return
	_root.add_child(node)
	for i in 6:
		await get_tree().process_frame
	_frame(node, kind, view)
	for i in 4:
		await get_tree().process_frame
	var img := _vp.get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, j["key"]])
	print("icon ", j["key"], " ", img.get_size())


## Aim the orthographic camera at the model's bounds from `view` (x pitch, y yaw about +Y, radians) and fit the picture with a small margin.
func _frame(node: Node3D, kind: String, view: Vector3) -> void:
	var bb := _bounds(node)
	if node.has_meta(&"bounds"):
		bb = node.get_meta(&"bounds")
	var c := bb.get_center()
	var basis := Basis.from_euler(Vector3(view.x, view.y, 0.0), EULER_ORDER_YXZ)
	_cam.global_transform = Transform3D(basis, c + basis.z * 20.0)
	var aspect := float(_vp.size.x) / float(_vp.size.y)
	# project the eight corners on the camera axes and fit
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for i in 8:
		var p := bb.get_endpoint(i) - c
		var q := Vector2(p.dot(basis.x), p.dot(basis.y))
		mn = mn.min(q)
		mx = mx.max(q)
	var ext := mx - mn
	var size := maxf(ext.y, ext.x / aspect) * 1.12
	_cam.size = size
	var mid := (mn + mx) * 0.5
	_cam.global_position += basis.x * mid.x + basis.y * mid.y


func _bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is MeshInstance3D and (x as MeshInstance3D).mesh != null and (x as MeshInstance3D).visible:
			var mi := x as MeshInstance3D
			var a: AABB = mi.global_transform * mi.get_aabb()
			if first:
				out = a
				first = false
			else:
				out = out.merge(a)
		for ch in x.get_children():
			stack.append(ch)
	return out


func _weapon_node(id: StringName) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = WeaponModels.mesh(id)
	mi.material_override = WeaponModels.material()
	return mi


func _vehicle_node(kind: StringName) -> Node3D:
	var car := Vehicle.new()
	_root.add_child(car)
	car.setup(kind, null)
	car.activate(Vector3.ZERO, 0.0)
	car.visual.set_paint(VehicleSpecs.COLORS[absi(String(kind).hash()) % VehicleSpecs.COLORS.size()])
	car.update_lod(0.0)
	car.visual.set_lights(0.9, 0.7, 0.0)
	car.visual.set_shadow(false)
	for nm in ["MirrorSource", "ShadowProxy", "UnderglowLight"]:                 # the wet-street reflection twin and the glow light are not part of a picture
		var x := car.find_child(nm, true, false)
		if x != null:
			x.queue_free()
	var none := StandardMaterial3D.new()
	none.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	none.albedo_color = Color(1, 1, 1, 0.0)
	for mi in car.find_children("*", "MeshInstance3D", true, false):       # the underglow plate and the light cones are surfaces of the body mesh: blank them
		var m3 := mi as MeshInstance3D
		if m3.mesh == null:
			continue
		for i in m3.mesh.get_surface_count():
			var nm := ""
			if m3.mesh is ArrayMesh:
				nm = (m3.mesh as ArrayMesh).surface_get_name(i)
			var om := m3.mesh.surface_get_material(i)
			if om != null:
				nm += om.resource_name
			if nm.contains("Lamps"):       # additive light cones: a black plate on a clear background
				m3.set_surface_override_material(i, none)
	_root.remove_child(car)
	var sp := car.spec
	car.set_meta(&"bounds", AABB(Vector3(-float(sp["wid"]) * 0.5, 0.0, -float(sp["len"]) * 0.5), Vector3(float(sp["wid"]), float(sp["hgt"]), float(sp["len"]))))
	return car


func _enemy_node(type: StringName) -> Node3D:
	var cfg := EnemyTypes.get_cfg(type)
	var scn := load("res://assets/models/%s.glb" % String(cfg["model"])) as PackedScene
	if scn == null:
		return null
	var n := scn.instantiate() as Node3D
	var sc := float(cfg.get("scale", 1.0))
	n.scale = Vector3.ONE * sc
	var col: Color = cfg["color"]
	var tint := StandardMaterial3D.new()
	tint.albedo_color = Color(col, 0.28)
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint.emission_enabled = true
	tint.emission = col
	tint.emission_energy_multiplier = 0.35
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = tint
	if not bool(cfg.get("drone", false)):                          # a skinned humanoid: its mesh bounds include the rifle pose, frame the standing body instead
		n.set_meta(&"bounds", AABB(Vector3(-0.5, 0.0, -0.5) * sc, Vector3(1.0, 1.85, 1.0) * sc))
	return n


## Small solid stand-ins for the throwables and gadgets (they have no model of their own: the effect is the thing).
func _gear_node(id: StringName) -> Node3D:
	var d := Gear.def(id)
	var col: Color = d["color"] if d.has("color") else Charges.COLOR
	var root := Node3D.new()
	var glow := StandardMaterial3D.new()
	glow.albedo_color = col.darkened(0.45)
	glow.emission_enabled = true
	glow.emission = col
	glow.emission_energy_multiplier = 1.6
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.42, 0.46, 0.54)
	body.metallic = 0.5
	body.roughness = 0.4
	match id:
		&"singularity":
			_add(root, SphereMesh.new(), glow, Vector3.ZERO, Vector3(0.2, 0.2, 0.2))
			for k in 2:
				var t := TorusMesh.new()
				t.inner_radius = 0.15
				t.outer_radius = 0.185
				_add(root, t, body, Vector3.ZERO, Vector3.ONE, Vector3(70.0 - 140.0 * float(k), 0, 40.0 * float(k)))
		&"mine":
			var cy := CylinderMesh.new()
			cy.top_radius = 0.2
			cy.bottom_radius = 0.22
			cy.height = 0.08
			_add(root, cy, body, Vector3.ZERO, Vector3.ONE)
			var cy2 := CylinderMesh.new()
			cy2.top_radius = 0.07
			cy2.bottom_radius = 0.07
			cy2.height = 0.03
			_add(root, cy2, glow, Vector3(0, 0.055, 0), Vector3.ONE)
		&"decoy":
			var cap := CapsuleMesh.new()
			cap.radius = 0.1
			cap.height = 0.42
			_add(root, cap, glow, Vector3(0, 0.0, 0), Vector3.ONE)
			_add(root, SphereMesh.new(), glow, Vector3(0, 0.3, 0), Vector3(0.12, 0.12, 0.12))
		&"shroud":
			var cy3 := CylinderMesh.new()
			cy3.top_radius = 0.09
			cy3.bottom_radius = 0.09
			cy3.height = 0.3
			_add(root, cy3, body, Vector3.ZERO, Vector3.ONE)
			var cloud := SphereMesh.new()
			var cm := StandardMaterial3D.new()
			cm.albedo_color = Color(col, 0.45)
			cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			cm.emission_enabled = true
			cm.emission = col
			cm.emission_energy_multiplier = 0.5
			_add(root, cloud, cm, Vector3(0, 0.22, 0), Vector3(0.42, 0.3, 0.42))
		&"emp":
			var cy4 := CylinderMesh.new()
			cy4.top_radius = 0.1
			cy4.bottom_radius = 0.1
			cy4.height = 0.3
			_add(root, cy4, body, Vector3.ZERO, Vector3.ONE)
			for k in 2:
				var t2 := TorusMesh.new()
				t2.inner_radius = 0.12
				t2.outer_radius = 0.145
				_add(root, t2, glow, Vector3(0, -0.07 + 0.14 * float(k), 0), Vector3.ONE)
		&"flash":
			var cy6 := CylinderMesh.new()
			cy6.top_radius = 0.085
			cy6.bottom_radius = 0.085
			cy6.height = 0.3
			_add(root, cy6, body, Vector3.ZERO, Vector3.ONE)
			var cap2 := CylinderMesh.new()
			cap2.top_radius = 0.09
			cap2.bottom_radius = 0.09
			cap2.height = 0.05
			_add(root, cap2, glow, Vector3(0, 0.17, 0), Vector3.ONE)
			var t5 := TorusMesh.new()
			t5.inner_radius = 0.1
			t5.outer_radius = 0.12
			_add(root, t5, glow, Vector3(0, -0.12, 0), Vector3.ONE)
			var lever := BoxMesh.new()
			lever.size = Vector3(0.02, 0.2, 0.05)
			_add(root, lever, body, Vector3(0.1, 0.02, 0.0), Vector3.ONE)
		&"c4":
			var brick := BoxMesh.new()                                                       # a brick of charge with a glowing strip, a detonator beside it
			brick.size = Vector3(0.34, 0.12, 0.2)
			_add(root, brick, body, Vector3(-0.08, 0.0, 0.0), Vector3.ONE)
			var strip := BoxMesh.new()
			strip.size = Vector3(0.3, 0.02, 0.06)
			_add(root, strip, glow, Vector3(-0.08, 0.07, 0.0), Vector3.ONE)
			var det := BoxMesh.new()
			det.size = Vector3(0.12, 0.2, 0.07)
			_add(root, det, body, Vector3(0.22, 0.04, 0.0), Vector3.ONE)
			var btn := SphereMesh.new()
			_add(root, btn, glow, Vector3(0.22, 0.15, 0.0), Vector3(0.07, 0.07, 0.07))
		&"scanner":
			var t3 := TorusMesh.new()
			t3.inner_radius = 0.2
			t3.outer_radius = 0.25
			_add(root, t3, glow, Vector3.ZERO, Vector3.ONE, Vector3(80, 0, 0))
			_add(root, SphereMesh.new(), body, Vector3.ZERO, Vector3(0.16, 0.16, 0.16))
			_add(root, SphereMesh.new(), glow, Vector3(0, 0.0, 0.0), Vector3(0.07, 0.07, 0.07))
		&"drone":
			_add(root, SphereMesh.new(), body, Vector3.ZERO, Vector3(0.3, 0.16, 0.3))
			_add(root, SphereMesh.new(), glow, Vector3(0, 0.0, -0.14), Vector3(0.1, 0.1, 0.1))
			for k in 4:
				var a := float(k) * TAU / 4.0 + PI / 4.0
				var arm := BoxMesh.new()
				arm.size = Vector3(0.2, 0.025, 0.035)
				_add(root, arm, body, Vector3(cos(a) * 0.12, 0.0, sin(a) * 0.12), Vector3.ONE, Vector3(0, -rad_to_deg(a), 0))
				var t4 := TorusMesh.new()
				t4.inner_radius = 0.075
				t4.outer_radius = 0.1
				_add(root, t4, glow, Vector3(cos(a) * 0.24, 0.04, sin(a) * 0.24), Vector3.ONE)
		&"grapple":
			var cy5 := CylinderMesh.new()
			cy5.top_radius = 0.045
			cy5.bottom_radius = 0.045
			cy5.height = 0.3
			_add(root, cy5, body, Vector3.ZERO, Vector3.ONE, Vector3(0, 0, 90))
			var bx := BoxMesh.new()
			bx.size = Vector3(0.1, 0.16, 0.1)
			_add(root, bx, glow, Vector3(0.2, 0.0, 0.0), Vector3.ONE)
			for s in [-1.0, 1.0]:
				var h := BoxMesh.new()
				h.size = Vector3(0.14, 0.03, 0.03)
				_add(root, h, glow, Vector3(0.3, 0.1 * s, 0.0), Vector3.ONE, Vector3(0, 0, 25 * s))
	return root


func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	if scl.x < 0.5 and mesh is SphereMesh:
		(mesh as SphereMesh).radius = 0.5
		(mesh as SphereMesh).height = 1.0
	mi.scale = scl
	mi.rotation_degrees = rot
	parent.add_child(mi)
