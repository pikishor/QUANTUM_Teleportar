class_name WorldBlasters
extends Node3D
## The WORLD BLASTERS of the blast table (wave 113): things in the city that go off when they are shot or blasted. The CAR BLAST is the real explosion of a real car (Vehicle.explode asks the table for `wb_car`);
## the others are props placed here: red BARRELS beside the sidewalk props, GAS TANKS and a FUEL TRUCK in the fuel yards of the harbour and the airport. A hit (a bullet, WorldBlasters.hit_at) takes health, at
## zero the prop goes off through BlastTable.apply(id) after a short fuse, and a blast next to it (Game.exploded) sets it off in a chain, so a row of barrels goes up one after the other.
## Budget: the props are streamed by distance (ACTIVE m around the hero), one pooled MultiMesh per kind (hidden, no draw call, while nothing of it is near), one pooled StaticBody3D per live prop so rays
## hit it; spots near the start of the game carry none (the first minutes stay as they were).
##   WorldBlasters.spawn(id, pos, yaw) -> bool       a prop at a place (cap per kind)   hit_at(pos, hits)   hit_collider(collider, pos, hits)   live_count(id)   detonations

const KINDS := {
	&"wb_barrel": {"cap": 16, "hp": 2.0, "fuse": 0.12, "box": Vector3(0.64, 0.95, 0.64)},
	&"wb_gas_tank": {"cap": 4, "hp": 6.0, "fuse": 0.3, "box": Vector3(3.2, 3.2, 7.0)},
	&"wb_fuel_truck": {"cap": 2, "hp": 10.0, "fuse": 0.45, "box": Vector3(2.6, 3.1, 9.0)},
}
const ACTIVE := 95.0
const KEEP := 130.0
const START_CLEAR := 120.0                    ## no barrel or tank within this of the hero's start
const RESPAWN_AFTER := 150.0
const CHAIN_FUSE := 0.18

static var current: WorldBlasters = null

var detonations := 0
var spawned := 0
var _live: Array[Dictionary] = []             ## {id, pos, yaw, hp, fuse, body, mi}
var _spots: Array[Dictionary] = []            ## {id, pos, yaw, live (bool), gone_at (seconds, -1 = never)}
var _mm: Dictionary = {}
var _node: Dictionary = {}
var _bodies: Dictionary = {}                  ## id -> Array of StaticBody3D
var _gen_done := false
var _acc := 0.0
var _hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0.0, -4000.0, 0.0))


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func _ready() -> void:
	name = &"WorldBlasters"
	top_level = true
	global_transform = Transform3D.IDENTITY
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.72
	mat.metallic = 0.25
	for id: StringName in KINDS:
		var k: Dictionary = KINDS[id]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _mesh_of(id)
		mm.instance_count = int(k["cap"])
		for i in int(k["cap"]):
			mm.set_instance_transform(i, _hidden)
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.material_override = mat
		node.custom_aabb = AABB(Vector3(-6000.0, -50.0, -6000.0), Vector3(12000.0, 200.0, 12000.0))
		node.visible = false
		add_child(node)
		_mm[id] = mm
		_node[id] = node
		var arr: Array[StaticBody3D] = []
		for i in int(k["cap"]):
			var body := StaticBody3D.new()
			body.collision_layer = 0
			body.collision_mask = 0
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = k["box"]
			cs.shape = bs
			cs.position = Vector3(0.0, (k["box"] as Vector3).y * 0.5, 0.0)
			body.add_child(cs)
			body.set_meta(&"wb_id", id)
			body.set_meta(&"wb_slot", i)
			add_child(body)
			arr.append(body)
		_bodies[id] = arr
	Game.exploded.connect(_on_exploded)
	Game.new_game.connect(reset)
	Game.respawn.connect(reset)


## The meshes: boxes and cylinders in vertex colour (the builder of the weapon models), origin on the ground, front toward -Z.
static func _mesh_of(id: StringName) -> Mesh:
	var b := WeaponModels._Builder.new()
	var ax := Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0))
	match id:
		&"wb_barrel":
			b.cyl(Vector3(0.0, 0.47, 0.0), 0.31, 0.94, Color(0.72, 0.1, 0.07), 0.0, 12, ax)
			for y in [0.16, 0.47, 0.78]:
				b.cyl(Vector3(0.0, y, 0.0), 0.325, 0.045, Color(0.35, 0.05, 0.04), 0.0, 12, ax)
			b.cyl(Vector3(0.0, 0.955, 0.0), 0.27, 0.03, Color(0.15, 0.15, 0.17), 0.0, 12, ax)
			b.box(Vector3(0.0, 0.6, 0.315), Vector3(0.2, 0.2, 0.012), Color(1.0, 0.82, 0.1), 0.0)            # a warning plate
		&"wb_gas_tank":
			b.cyl(Vector3(0.0, 1.9, 0.0), 1.45, 6.2, Color(0.86, 0.87, 0.9), 0.0, 16)
			for z in [-2.4, 0.0, 2.4]:
				b.cyl(Vector3(0.0, 1.9, z), 1.5, 0.12, Color(0.45, 0.47, 0.5), 0.0, 16)
			b.cyl(Vector3(0.0, 1.9, 3.1), 1.3, 0.3, Color(0.62, 0.64, 0.68), 0.0, 16)
			b.cyl(Vector3(0.0, 1.9, -3.1), 1.3, 0.3, Color(0.62, 0.64, 0.68), 0.0, 16)
			for z in [-1.9, 1.9]:
				b.box(Vector3(0.0, 0.4, z), Vector3(2.6, 0.8, 0.5), Color(0.3, 0.32, 0.36))
			b.box(Vector3(0.0, 3.5, 0.0), Vector3(0.7, 0.18, 0.7), Color(0.2, 0.2, 0.22))
			b.box(Vector3(0.0, 1.9, 1.5 * 0.0), Vector3(2.92, 0.5, 6.22), Color(0.8, 0.12, 0.08))               # the red band round the middle
			b.box(Vector3(0.0, 2.0, 0.0), Vector3(2.96, 0.5, 1.2), Color(1.0, 0.82, 0.1))
		_:
			b.box(Vector3(0.0, 0.95, 0.0), Vector3(1.3, 0.3, 8.4), Color(0.18, 0.19, 0.22))                  # the chassis
			b.cyl(Vector3(0.0, 1.95, 1.2), 1.1, 6.2, Color(0.82, 0.8, 0.22), 0.0, 14)                           # the tank
			for z in [-0.6, 1.2, 3.0]:
				b.cyl(Vector3(0.0, 1.95, z), 1.15, 0.12, Color(0.45, 0.45, 0.4), 0.0, 14)
			b.box(Vector3(0.0, 2.1, -3.6), Vector3(2.5, 2.2, 1.9), Color(0.8, 0.12, 0.08))                       # the cab
			b.box(Vector3(0.0, 2.55, -4.5), Vector3(2.3, 1.0, 0.1), Color(0.45, 0.7, 0.8))                       # the windscreen
			b.box(Vector3(0.0, 1.2, -4.7), Vector3(2.4, 0.5, 0.5), Color(0.15, 0.15, 0.17))
			for z in [-3.5, 1.2, 3.4]:
				for x in [-1.15, 1.15]:
					b.cyl(Vector3(x, 0.55, z), 0.55, 0.4, Color(0.05, 0.05, 0.06), 0.0, 10, Basis.from_euler(Vector3(0.0, PI * 0.5, 0.0)))
			b.box(Vector3(0.0, 3.1, 1.2), Vector3(0.7, 0.2, 0.7), Color(0.2, 0.2, 0.22))
	return b.build()


func reset() -> void:
	for l in _live:
		_release(l)
	_live.clear()
	for s in _spots:
		s["live"] = false
		s["gone_at"] = -1.0
	_refresh_nodes()


func live_count(id: StringName = &"") -> int:
	if id == &"":
		return _live.size()
	var n := 0
	for l in _live:
		if l["id"] == id:
			n += 1
	return n


## A prop at `pos` (a test, a mission or a set piece). False when the cap of its kind is reached.
static func spawn(id: StringName, pos: Vector3, yaw := 0.0) -> bool:
	if current == null or not KINDS.has(id):
		return false
	return current._add(id, pos, yaw, -1)


func _add(id: StringName, pos: Vector3, yaw: float, spot: int) -> bool:
	var k: Dictionary = KINDS[id]
	if live_count(id) >= int(k["cap"]):
		return false
	var used := {}
	for l in _live:
		if l["id"] == id:
			used[int(l["slot"])] = true
	var slot := 0
	while used.has(slot):
		slot += 1
	var body: StaticBody3D = (_bodies[id] as Array)[slot]
	body.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	body.collision_layer = Game.L_WORLD
	var l := {"id": id, "pos": pos, "yaw": yaw, "hp": float(k["hp"]), "fuse": -1.0, "slot": slot, "spot": spot}
	_live.append(l)
	(_mm[id] as MultiMesh).set_instance_transform(slot, Transform3D(Basis(Vector3.UP, yaw), pos))
	spawned += 1
	_refresh_nodes()
	return true


func _release(l: Dictionary) -> void:
	var id: StringName = l["id"]
	var slot := int(l["slot"])
	var body: StaticBody3D = (_bodies[id] as Array)[slot]
	body.collision_layer = 0
	(_mm[id] as MultiMesh).set_instance_transform(slot, _hidden)


func _refresh_nodes() -> void:
	for id: StringName in KINDS:
		(_node[id] as MultiMeshInstance3D).visible = live_count(id) > 0


## A hit at a world position (hitscan, a test): the nearest live prop within 2.6 m (the big ones 5.5 m) takes `hits`.
func hit_at(pos: Vector3, hits: float) -> bool:
	var best := -1
	var best_d := 1.0e9
	for i in _live.size():
		var l: Dictionary = _live[i]
		var reach := 2.6 if StringName(l["id"]) == &"wb_barrel" else 5.5
		var d := (l["pos"] as Vector3).distance_to(pos)
		if d < reach and d < best_d:
			best_d = d
			best = i
	if best < 0:
		return false
	_damage(_live[best], hits)
	return true


## A bullet that hit a collider: ours carry the meta wb_id / wb_slot. Returns true when it was a blaster.
func hit_collider(collider: Object, pos: Vector3, hits: float) -> bool:
	if not (collider is Node) or not (collider as Node).has_meta(&"wb_id"):
		return false
	var id: StringName = (collider as Node).get_meta(&"wb_id")
	var slot := int((collider as Node).get_meta(&"wb_slot"))
	for l in _live:
		if l["id"] == id and int(l["slot"]) == slot:
			FX.burst(pos, Color(1.0, 0.8, 0.4), 4, 3.0, 0.25, 6.0, 0.7)
			_damage(l, hits)
			return true
	return false


func _damage(l: Dictionary, hits: float) -> void:
	l["hp"] = float(l["hp"]) - hits
	if float(l["hp"]) <= 0.0 and float(l["fuse"]) < 0.0:
		l["fuse"] = float((KINDS[l["id"]] as Dictionary)["fuse"])
		FX.burst((l["pos"] as Vector3) + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.55, 0.2), 6, 3.0, 0.4, 0.0, 1.0)


func _on_exploded(pos: Vector3, radius: float) -> void:
	for l in _live:
		if float(l["fuse"]) < 0.0 and (l["pos"] as Vector3).distance_to(pos) <= radius + 1.0 and (l["pos"] as Vector3).distance_to(pos) > 0.4:
			l["hp"] = 0.0
			l["fuse"] = CHAIN_FUSE


func _physics_process(dt: float) -> void:
	if not Game.is_playing():
		return
	var i := _live.size() - 1
	while i >= 0:
		var l: Dictionary = _live[i]
		if float(l["fuse"]) >= 0.0:
			l["fuse"] = float(l["fuse"]) - dt
			if float(l["fuse"]) < 0.0:
				_live.remove_at(i)
				_release(l)
				_refresh_nodes()
				if int(l["spot"]) >= 0 and int(l["spot"]) < _spots.size():
					_spots[int(l["spot"])]["live"] = false
					_spots[int(l["spot"])]["gone_at"] = PlayerUtil.now()
				_go(l)
		i -= 1
	_acc += dt
	if _acc >= 0.6:
		_acc = 0.0
		_stream()


func _go(l: Dictionary) -> void:
	detonations += 1
	var id: StringName = l["id"]
	var e := BlastTable.entry(id)
	var pos: Vector3 = (l["pos"] as Vector3) + Vector3(0.0, 0.9 if id != &"wb_barrel" else 0.5, 0.0)
	if e.is_empty():
		return
	BlastTable.apply(id, pos, null, {"by_hero": false})


# --- streaming of the standing spots --------------------------------------------------------------------------------------

func _stream() -> void:
	var hero := Game.player as Node3D
	if not is_instance_valid(hero):
		return
	if not _gen_done:
		_gen_spots()
	var hp := hero.global_position
	var now := PlayerUtil.now()
	for si in _spots.size():
		var s: Dictionary = _spots[si]
		var d := Vector2((s["pos"] as Vector3).x - hp.x, (s["pos"] as Vector3).z - hp.z).length()
		if bool(s["live"]):
			if d > KEEP:
				for l in _live:
					if int(l["spot"]) == si:
						_live.erase(l)
						_release(l)
						break
				s["live"] = false
		elif d < ACTIVE and (float(s["gone_at"]) < 0.0 or (now - float(s["gone_at"]) > RESPAWN_AFTER and d > 40.0)):
			if _add(s["id"], s["pos"], float(s["yaw"]), si):
				s["live"] = true
				s["gone_at"] = -1.0
	_refresh_nodes()


func _gen_spots() -> void:
	var br := Breakables.current
	if br == null or not is_instance_valid(Game.world):
		return
	_gen_done = true
	_spots.clear()
	var start := Game.SPAWN
	var n := 0
	for i in Breakables.COUNT:
		if i % 7 != 3:
			continue
		var kind: String = Breakables.KINDS[br.kind_of[i]]["name"]
		if kind in ["window", "pole", "fence", "barrier"]:
			continue
		var p := br.positions[i] + Vector3(1.25 if i % 2 == 0 else 0.0, 0.0, 0.0 if i % 2 == 0 else 1.25)
		p.y = 0.0
		if Vector2(p.x - start.x, p.z - start.z).length() < START_CLEAR:
			continue
		_spots.append({"id": &"wb_barrel", "pos": p, "yaw": float(i) * 0.7, "live": false, "gone_at": -1.0})
		n += 1
	# the fuel yards: the harbour's tank farm and the airport's
	var h := Harbour.layout()
	if not h.is_empty() and (h.get("tanks", []) as Array).size() > 0:
		var t0: Vector3 = ((h["tanks"] as Array)[0] as Dictionary)["pos"]
		_yard(t0 + Vector3(-6.0, 0.0, -34.0))
	var tank0: Dictionary = Airport.TANKS[0]
	var ap := Airport.to_world(Vector3((tank0["pos"] as Vector2).x, 0.0, (tank0["pos"] as Vector2).y))
	_yard(ap + Vector3(-8.0, 0.0, 34.0))


func _yard(c: Vector3) -> void:
	for k in 3:
		_spots.append({"id": &"wb_barrel", "pos": c + Vector3(float(k) * 1.4, 0.0, 6.0), "yaw": float(k), "live": false, "gone_at": -1.0})
	_spots.append({"id": &"wb_gas_tank", "pos": c + Vector3(-9.0, 0.0, 0.0), "yaw": 0.0, "live": false, "gone_at": -1.0})
	_spots.append({"id": &"wb_gas_tank", "pos": c + Vector3(-9.0, 0.0, -11.0), "yaw": 0.0, "live": false, "gone_at": -1.0})
	_spots.append({"id": &"wb_fuel_truck", "pos": c + Vector3(9.0, 0.0, -2.0), "yaw": PI * 0.5, "live": false, "gone_at": -1.0})
