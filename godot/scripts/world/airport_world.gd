class_name AirportWorld
extends Node3D
## EASTFIELD AIRPORT in the live world (data: Airport, meshes: AirportKit). Child of the City (AirportWorld.attach). THREE draw calls for the whole field (ground with all its paint and the pads, kit, detail),
## one small mesh per remote helipad (roof, mountain, mountain sites: each its own draw within 700 m), one StaticBody3D with the collision boxes of the buildings, the tank cylinders and the roof pad, the
## scenery airliners parked at the gates, and the AIR TRAFFIC (AirTraffic: planes taking off and landing, helicopters on patrol, all within 2.4 km of the player and nowhere else). `QT_NO_AIRPORT=1`
## leaves the field out. Nothing here is within 540 m of the start of the game, and everything is distance culled: the perf gate's staged views see none of it.
##   AirportWorld.instance      the node
##   traffic                    the AirTraffic child
##   stats()                    {tris, boxes, pads, parked}

const SHOW_RANGE := 1000.0                          ## the field is drawn up to this distance (Godot measures to the nearest point of the mesh's box: the start of the city is 1.2 km from the apron's corner and never draws it)
const SHOW_DETAIL := 450.0
const SHOW_PAD := 450.0
const SCENERY_RANGE := 950.0                        ## the parked airliners are shown within this of the apron
const CENTRE := Vector3(1170.0, 0.0, -560.0)       ## the middle of the apron (local frame)

static var instance: AirportWorld = null

var tris := 0
var boxes := 0
var pad_nodes: Array[MeshInstance3D] = []
var parked: Array[Node3D] = []
var traffic: AirTraffic
var field: Node3D                                   ## the field's own frame (Airport.FRAME): the meshes, the colliders and the parked scenery are children of it
var _tick := 0.0


static func attach(parent: Node) -> AirportWorld:
	var w := AirportWorld.new()
	w.name = "AirportWorld"
	parent.add_child(w)
	return w


func _ready() -> void:
	instance = self
	Airport.ensure()
	field = Node3D.new()
	field.name = "Field"
	field.transform = Airport.FRAME
	add_child(field)
	_mesh(field, "Ground", AirportKit.ground(), SHOW_RANGE, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_mesh(field, "Kit", AirportKit.kit(), SHOW_RANGE, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	_mesh(field, "Detail", AirportKit.detail(), SHOW_DETAIL, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	for p in Airport.pads():
		if p["kind"] == &"apron":
			continue
		var mi := _mesh(self, "Pad_" + String(p["id"]), AirportKit.pad_mesh(p), SHOW_PAD, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		mi.position = p["pos"]
		pad_nodes.append(mi)
	_collision()
	_scenery()
	traffic = AirTraffic.new()
	traffic.name = "AirTraffic"
	add_child(traffic)
	set_process(true)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _mesh(parent: Node3D, nm: String, m: ArrayMesh, vis_end: float, shadow: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = m
	mi.cast_shadow = shadow as GeometryInstance3D.ShadowCastingSetting
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_end = vis_end
	tris += BridgeWorld._tri_count(m)
	parent.add_child(mi)
	return mi


func _collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	for b: Dictionary in Airport.BUILDINGS:
		var p: Vector2 = b["pos"]
		var sz: Vector3 = b["size"]
		_add_box(body, Vector3(p.x, sz.y * 0.5, p.y), sz if b["kind"] != &"tower" else Vector3(8.0, sz.y, 8.0))
	for t: Dictionary in Airport.TANKS:
		var tp: Vector2 = t["pos"]
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = float(t["r"])
		cyl.height = float(t["h"])
		cs.shape = cyl
		cs.position = Vector3(tp.x, float(t["h"]) * 0.5, tp.y)
		body.add_child(cs)
		boxes += 1
	field.add_child(body)
	var rf := Airport.roof()
	if not rf.is_empty():                                                    # the elevated roof pad is a slab in the air (world coordinates): a helicopter lands on it whatever the roof under it holds
		var rbody := StaticBody3D.new()
		rbody.name = "RoofPadCollision"
		rbody.collision_layer = Game.L_WORLD
		rbody.collision_mask = 0
		var rp: Vector3 = rf["pos"]
		for sx in [-1.0, 1.0]:                                               # two halves with a 1 m gap down the middle: a straight ray through the pad's centre still finds the roof (tests/test_world.gd), a helicopter stands on either half
			var cs2 := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(8.0, 0.6, 17.0)
			cs2.shape = bx
			cs2.position = Vector3(rp.x + float(sx) * 4.5, rp.y - 0.3, rp.z)
			rbody.add_child(cs2)
		add_child(rbody)
		boxes += 1


func _add_box(body: StaticBody3D, pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	body.add_child(cs)
	boxes += 1


## The parked scenery: the models of Airport.PARKED, one draw per surface each (3 airliners = 9 draws, shown only within SCENERY_RANGE).
func _scenery() -> void:
	for e: Dictionary in Airport.PARKED:
		var n := AircraftScenery.make(StringName(e["kind"]), int(e["paint"]))
		if n == null:
			continue
		var p: Vector2 = e["pos"]
		n.name = String(e["id"])
		n.position = Vector3(p.x, 0.0, p.y)
		n.rotation.y = float(e["h"])
		n.visible = false
		field.add_child(n)
		parked.append(n)


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.5:
		return
	_tick = 0.0
	var p := Game.player as Node3D
	if not is_instance_valid(p):
		return
	var c := Airport.to_world(CENTRE)
	var d := Vector2(p.global_position.x - c.x, p.global_position.z - c.z).length()
	for n in parked:
		n.visible = d < SCENERY_RANGE


func stats() -> Dictionary:
	return {"tris": tris, "boxes": boxes, "pads": pad_nodes.size(), "parked": parked.size()}
