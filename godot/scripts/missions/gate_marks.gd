class_name GateMarks
extends Node3D
## The gates of a course (air race, flight school, jet-ski laps, off-road trial) as light in the world: the CURRENT gate is a big glowing ring that stands across the way through it (a torus,
## unshaded and additive, scaled to the gate radius) with a tall beam so it can be found from far away; the NEXT gate is a dimmer ring and a thin beam. Two rings and two beams in all, built
## once and only moved afterwards (four draw calls while a course runs, none otherwise). The ring faces the direction of travel (the line from the previous gate to the next one).

const TORUS_TUBE := 0.06                ## tube thickness as a share of the radius
const BEAM_H := 220.0

var _ring: Array[MeshInstance3D] = []
var _beam: Array[MeshInstance3D] = []
var _mats: Array[StandardMaterial3D] = []
var shown := 0                            ## gates drawn (0, 1 or 2)
var _flat: ContractVisuals                ## ground and water gates use the game's own ring markers (flat band with a polar shader, plus a beam): the same look as every other objective ring


func _init() -> void:
	name = "GateMarks"
	var tor := TorusMesh.new()
	tor.inner_radius = 1.0 - TORUS_TUBE * 2.0
	tor.outer_radius = 1.0
	tor.rings = 28
	tor.ring_segments = 6
	for i in 2:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA                   # plain alpha, not additive: a gold ring must show against a bright hazy sky too (render loop 1)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.disable_receive_shadows = true
		m.disable_fog = true                                                     # the haze of the outskirts swallowed a ring 400 m away (render loop 2)
		m.albedo_color = Color(1.0, 0.7, 0.08, 0.95 if i == 0 else 0.55) if i == 0 else Color(0.3, 0.85, 1.0, 0.6)
		_mats.append(m)
		var r := MeshInstance3D.new()
		r.mesh = tor
		r.material_override = m
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		r.visible = false
		r.extra_cull_margin = 64.0
		add_child(r)
		_ring.append(r)
		var b := MissionVisuals.make_beam(Color(1.0, 0.78, 0.25) if i == 0 else Color(0.45, 0.85, 1.0), 2.4 if i == 0 else 1.3, BEAM_H, 1.3 if i == 0 else 0.7, 0.3)
		b.visible = false
		add_child(b)
		_beam.append(b)
	top_level = true


func _place(i: int, c: Vector3, radius: float, dir: Vector3, flat: bool) -> void:
	var up := Vector3.UP if flat else (dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD)
	var q := Quaternion(Vector3.UP, up) if not flat else Quaternion.IDENTITY
	var b := Basis(q).scaled(Vector3(radius, radius * (0.12 if flat else 1.0), radius))             # a ring on the ground / water lies flat (it looked like a slab when it was as thick as a standing one)
	_ring[i].transform = Transform3D(b, c + (Vector3(0.0, 0.25, 0.0) if flat else Vector3.ZERO))
	_ring[i].visible = true
	_beam[i].global_position = Vector3(c.x, c.y + BEAM_H * 0.5 - 40.0, c.z)
	_beam[i].visible = true


## Show gate `i` of `gates` (and the one after it dimmer). `flat` = ground and water courses (rings lie on the surface, the beam marks them); air courses stand the ring up across the way.
func show_gate(gates: Array[Vector3], i: int, radius: float, flat := false) -> void:
	if i < 0 or i >= gates.size():
		hide_all()
		return
	if flat:
		_show_flat(gates, i, radius)
		return
	if _flat != null:
		_flat.hide_all()
	var prev := gates[i - 1] if i > 0 else gates[i] - Vector3(0.0, 0.0, 1.0)
	var nxt := gates[i + 1] if i + 1 < gates.size() else gates[i] + (gates[i] - prev)
	var dir := nxt - prev
	_place(0, gates[i], radius, dir, false)
	shown = 1
	if i + 1 < gates.size():
		var d2 := (gates[i + 1 + (1 if i + 2 < gates.size() else 0)] - gates[i]) if i + 2 < gates.size() else (gates[i + 1] - gates[i])
		_place(1, gates[i + 1], radius * 0.8, d2, false)
		shown = 2
	else:
		_ring[1].visible = false
		_beam[1].visible = false
	visible = true


func _show_flat(gates: Array[Vector3], i: int, radius: float) -> void:
	for k in 2:
		_ring[k].visible = false
		_beam[k].visible = false
	if _flat == null:
		_flat = ContractVisuals.new()
		add_child(_flat)
	_flat.show_marker(0, gates[i], radius, ContractTypes.AMBER, -1.0, true)
	shown = 1
	if i + 1 < gates.size():
		_flat.show_marker(1, gates[i + 1], radius * 0.8, ContractTypes.CYAN, -1.0, false)
		shown = 2
	else:
		_flat.hide_marker(1)
	visible = true


func hide_all() -> void:
	for i in 2:
		_ring[i].visible = false
		_beam[i].visible = false
	if _flat != null:
		_flat.hide_all()
	shown = 0
	visible = false
