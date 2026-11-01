extends "res://tests/assets_showcase.gd"
## Look-dev line-up of the crowd's citizen archetypes with the real crowd shader (prop_crowd.gdshader), one MultiMesh per state row.
## Environment (shot.sh passes it through):
##   QT_VIEW=all                every state as a row, archetype 0..12 left to right (default)
##   QT_VIEW=<state>            one row close up; state = walk, idle, talk, flee, cower, far (the cut-down far mesh walking)
##   QT_VIEW=arch<N>            archetype N in every state, seen from the front
##   QT_HALF=0|1               with a state: only archetypes 0..6 or 7..12, closer
##   QT_ANGLE=<deg>             camera yaw around the row (0 = front, 90 = from the side)
## Example: QT_VIEW=talk tools/shot.sh /tmp/talk.png res://tests/citizen_lineup.tscn 40
## ARCH_SEED maps an archetype to a seed the crowd shader decodes to it (group = floor(seed * 6), the fraction picks inside the group; see ARCH_OPT / ARCH_CUT there).

const SHADER := preload("res://assets/shaders/prop_crowd.gdshader")
const MODEL := "res://assets/models/citizen.glb"
const STATES: Array[String] = ["walk", "idle", "talk", "flee", "cower"]
const GROUP_R := {0: [0, 0.25], 9: [0, 0.7], 11: [0, 0.92], 1: [1, 0.25], 12: [1, 0.8], 2: [2, 0.25], 8: [2, 0.9], 3: [3, 0.25], 6: [3, 0.8], 4: [4, 0.25], 10: [4, 0.8], 5: [5, 0.25], 7: [5, 0.8]}
const SPACING := 1.45

var _near: Mesh
var _far: Mesh


## A seed the crowd shader decodes to archetype `a`; `variant` (0..1) moves the palette digits without changing the archetype.
static func arch_seed(a: int, variant: float = 0.0) -> float:
	var gr: Array = GROUP_R[a]
	var r: float = float(gr[1]) + 0.04 * variant
	return (float(gr[0]) + r) / 6.0


## INSTANCE_CUSTOM (seed, phase, state, flags) of one person: state = walk / idle / talk / flee / cower / far (walking).
static func custom_of(state: String, seed: float, k: int) -> Color:
	var phase := 0.9 * float(k)
	match state:
		"idle":
			return Color(seed, phase, 0.0, 0.0)
		"talk":
			return Color(seed, phase, 0.0, 2.0)
		"flee":
			return Color(seed, phase, 2.17, 0.0)
		"cower":
			return Color(seed, phase, -1.0, 0.0)
	return Color(seed, phase, 0.9, 0.0)


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_lights()
	var ps := load(MODEL) as PackedScene
	var root := ps.instantiate()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if String(mi.name).begins_with("CitizenFar"):
			_far = mi.mesh
		elif String(mi.name).begins_with("Citizen"):
			_near = mi.mesh
	root.free()
	var view := OS.get_environment("QT_VIEW")
	var yaw := deg_to_rad(float(OS.get_environment("QT_ANGLE")) if OS.get_environment("QT_ANGLE") != "" else 0.0)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.far = 300.0
	add_child(cam)
	cam.make_current()
	var centre := Vector3.ZERO
	var dist := 12.0
	var pitch := 0.10
	if view.begins_with("arch"):
		var a := int(view.substr(4))
		for si in STATES.size():
			_row(STATES[si], [a], Vector3(0, 0, 0), float(si) - 2.0, false)
		centre = Vector3(0, 1.0, 0)
		dist = 7.5
		cam.fov = 40.0
	elif view == "all" or view == "":
		for si in STATES.size():
			_row(STATES[si], range(13), Vector3(0, 0, -2.4 * float(si)), 0.0, false)
		_row("walk", range(13), Vector3(0, 0, -2.4 * float(STATES.size())), 0.0, true)
		centre = Vector3(0, 0.8, -6.0)
		dist = 24.0
		pitch = 0.75                                              # looking down so the rows do not hide each other
	else:
		var half := OS.get_environment("QT_HALF")                 # "0": archetypes 0..6, "1": 7..12 (closer)
		var archs: Array = range(13) if half == "" else (range(7) if half == "0" else range(7, 13))
		_row("walk" if view == "far" else view, archs, Vector3.ZERO, 0.0, view == "far")
		centre = Vector3(0, 1.0, 0)
		dist = 14.5 if half == "" else 9.0
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	cam.position = centre + dir * dist
	cam.look_at(centre, Vector3.UP)


## One row of people (MultiMesh): archetypes `archs` at `origin`, spaced SPACING along x; for the single archetype view `dx` offsets the whole row.
func _row(state: String, archs: Array, origin: Vector3, dx: float, far: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _far if far else _near
	mm.instance_count = archs.size()
	var x0 := float(archs.size() - 1) * SPACING * 0.5            # the camera looks along +Z: archetype 0 is at the left of the picture
	for k in archs.size():
		var a: int = archs[k]
		var seed := arch_seed(a, 0.3 * float(k % 3))
		mm.set_instance_transform(k, Transform3D(Basis(), origin + Vector3(x0 - float(k) * SPACING + dx * 1.6, 0.0, 0.0)))
		mm.set_instance_color(k, Color.WHITE)
		mm.set_instance_custom_data(k, custom_of(state, seed, k))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mi.material_override = mat
	mi.custom_aabb = AABB(Vector3(-40, -1, -40), Vector3(80, 6, 80))
	add_child(mi)
