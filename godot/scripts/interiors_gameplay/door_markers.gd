class_name DoorMarkers
extends Node3D
## The glowing doors of the city: ONE MultiMesh (one draw call) with a door-frame sheet on the facade and a pulsing pad on the sidewalk in front, per door of `Game.world.doors`
## (scripts/world/city_doors.gd). Colour = interior type (InteriorData.COLORS). A door whose mission is still open glows brighter; a door a rumour pointed at brighter still.
## Built once from the door list; hidden while the player is inside an interior (the city is hidden then anyway). Costs nothing per frame.

const MB := preload("res://scripts/world/mesh_builder.gd")
const SHADER := preload("res://scripts/interiors_gameplay/door_glow.gdshader")

var mmi: MultiMeshInstance3D
var count := 0
var doors: Array[Dictionary] = []


static func quad_mesh() -> ArrayMesh:
	var b := MB.new()
	var w := 1.2
	var h := 3.2
	b.quad(Vector3(-w, 0.0, 0.04), Vector3(w, 0.0, 0.04), Vector3(w, h, 0.04), Vector3(-w, h, 0.04), Vector3.BACK, Color.WHITE, Vector2.ZERO, Vector2.ZERO,
			PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]))
	var pw := 1.5
	var pd := 2.2
	b.quad(Vector3(-pw, 0.06, 0.0), Vector3(pw, 0.06, 0.0), Vector3(pw, 0.06, pd), Vector3(-pw, 0.06, pd), Vector3.UP, Color.WHITE, Vector2.ZERO, Vector2.ZERO,
			PackedVector2Array([Vector2(2, 0), Vector2(3, 0), Vector2(3, 1), Vector2(2, 1)]))
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.render_priority = 10
	return b.build(m, false, true)


func build(list: Array[Dictionary]) -> void:
	doors = list
	count = list.size()
	if mmi != null:
		mmi.queue_free()
		mmi = null
	if count == 0:
		return
	var mm := MB.new_multimesh(quad_mesh(), count, true, true)
	var buf := MB.new_buffer(count, true, true)
	for i in count:
		var d: Dictionary = list[i]
		var xf := Transform3D(Basis(Vector3.UP, float(d["yaw"])), d["wall"] as Vector3)
		var c := InteriorData.color(d["type"])
		MB.write_instance(buf, i, xf, true, Color(c.r, c.g, c.b, 0.0), true, Color(fposmod(float(int(d["id"])) * 0.61803, 1.0), 0.0, 0.0, 0.0))
	mm.buffer = buf
	mmi = MultiMeshInstance3D.new()
	mmi.name = "DoorGlow"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-400, -2, -400), Vector3(800, 12, 800))
	add_child(mmi)


## Brighter glow for doors whose mission is open (`open`: door id -> true) and rumour-hinted doors (`hinted`).
func refresh(open: Dictionary, hinted: Dictionary) -> void:
	if mmi == null:
		return
	for i in count:
		var d: Dictionary = doors[i]
		var id := int(d["id"])
		var c := InteriorData.color(d["type"])
		var a := 0.0
		if hinted.has(id):
			a = 1.0
		elif open.has(id):
			a = 0.4
		mmi.multimesh.set_instance_color(i, Color(c.r, c.g, c.b, a))
