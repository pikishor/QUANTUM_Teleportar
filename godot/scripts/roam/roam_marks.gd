class_name RoamMarks
extends Node3D
## A small pool of ground rings with a beam (the game's own ring shader and beam material, see ContractVisuals / MissionVisuals) for the free-roam world: pads, relics, photo
## spots, fishing places, ramps. A slot is a flat ring on the ground and a soft column; both are one draw call each and are hidden when the slot is not shown. The world shows only the
## slots near the hero (RoamWorld decides), so the draw cost is a few calls at most.

const BEAM_H := 120.0
const NEAR_FADE := 20.0

static var _beam_mats := {}

var slots: Array[Dictionary] = []
var host: Node                     ## when set, the pool joins the tree only when its first ring is shown (an idle pool of hidden meshes still cost the phone draw calls in the perf gate)
var _t := 0.0


## One shared column material per colour (MissionVisuals caches them by key too).
static func _beam_material(c: Color) -> Material:
	var key := c.to_html()
	if not _beam_mats.has(key):
		var b := MissionVisuals.make_beam(c, 1.1, BEAM_H, 1.5, 0.3)
		_beam_mats[key] = b.material_override
		b.free()
	return _beam_mats[key]


func _init(count := 10) -> void:
	name = "RoamMarks"
	top_level = true
	for i in count:
		slots.append(_build(i))


func _build(i: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Mark%d" % i
	root.visible = false
	var beam := MissionVisuals.make_beam(Color(0.3, 1.0, 0.8), 1.1, BEAM_H, 1.5, 0.3)
	beam.position.y = BEAM_H * 0.5
	root.add_child(beam)
	var mat := ShaderMaterial.new()
	mat.shader = ContractVisuals.ring_shader()
	var ring := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(2.0, 2.0)
	ring.mesh = quad
	ring.material_override = mat
	ring.position.y = 0.12
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	# a pad is also a plain alpha disc (the ring shader is additive: a light ring vanishes on pale concrete in the day, render loop 2)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.06
	cyl.radial_segments = 40
	cyl.rings = 1
	cyl.cap_bottom = false
	disc.mesh = cyl
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	dmat.disable_fog = true
	dmat.disable_receive_shadows = true
	dmat.albedo_color = Color(0.1, 0.8, 1.0, 0.5)
	disc.material_override = dmat
	disc.position.y = 0.08
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.visible = false
	root.add_child(disc)
	add_child(root)
	return {"node": root, "beam": beam, "ring": ring, "mat": mat, "disc": disc, "dmat": dmat, "on": false, "beam_on": true}


## Show slot `i` at `pos` (ground): ring radius `radius`, colour, with or without the column; `pad` draws the lit-pad style (a bright disc with a ripple).
func show_at(i: int, pos: Vector3, radius: float, color: Color, beam := true, pad := false, inner := 0.9) -> void:
	if i < 0 or i >= slots.size():
		return
	if host != null and not is_inside_tree():
		host.add_child(self)
	var s: Dictionary = slots[i]
	var node: Node3D = s["node"]
	node.position = Vector3(pos.x, pos.y, pos.z)
	node.visible = true
	s["on"] = true
	s["beam_on"] = beam
	(s["beam"] as MeshInstance3D).visible = beam
	var tint := Color(color.r, color.g, color.b, 1.0)
	(s["beam"] as MeshInstance3D).material_override = _beam_material(tint)
	(s["ring"] as MeshInstance3D).scale = Vector3(radius, 1.0, radius)
	(s["ring"] as MeshInstance3D).visible = not pad          # a pad is the alpha disc alone (one draw instead of two: the phone's draw budget)
	var mat: ShaderMaterial = s["mat"]
	mat.set_shader_parameter(&"tint", tint)
	mat.set_shader_parameter(&"progress", -1.0)
	mat.set_shader_parameter(&"inner", 0.78 if pad else inner)
	mat.set_shader_parameter(&"fill_a", 0.28 if pad else 0.035)
	mat.set_shader_parameter(&"ripple", 1.0 if pad else 0.0)
	var disc := s["disc"] as MeshInstance3D
	disc.visible = pad
	if pad:
		disc.scale = Vector3(radius * 0.96, 1.0, radius * 0.96)
		(s["dmat"] as StandardMaterial3D).albedo_color = Color(color.r * 0.55, color.g * 0.8, color.b * 0.9, 0.42)


func hide_slot(i: int) -> void:
	if i < 0 or i >= slots.size():
		return
	(slots[i]["node"] as Node3D).visible = false
	slots[i]["on"] = false


func hide_all() -> void:
	for i in slots.size():
		hide_slot(i)


func shown_count() -> int:
	var n := 0
	for s in slots:
		if bool(s["on"]):
			n += 1
	return n


func is_shown(i: int) -> bool:
	return i >= 0 and i < slots.size() and bool(slots[i]["on"])


## The columns turn slowly and thin out right next to the camera (an additive column at the lens only washes the view out).
func animate(delta: float) -> void:
	_t += delta
	var cam := Game.camera if is_instance_valid(Game.camera) else null
	for s in slots:
		if not bool(s["on"]):
			continue
		var beam := s["beam"] as Node3D
		beam.rotation.y += delta * 0.8
		if bool(s["beam_on"]) and cam != null:
			var np := (s["node"] as Node3D).global_position
			var cp := cam.global_position
			beam.visible = Vector2(np.x - cp.x, np.z - cp.z).length() > NEAR_FADE
