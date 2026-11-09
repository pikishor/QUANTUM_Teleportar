class_name OutskirtsWorld
extends Node3D
## The sites of the outskirts in the live world (wave 105; data OutskirtsSites, meshes OutskirtsKit, forests VegetationWorld, mountain air MountainWeather). Child `sites` of the City.
##
## A site is built when the hero comes within BUILD_R metres (one per tick, so the cost is spread) and freed beyond FREE_R: one MeshInstance3D (one draw call, distance culled), one
## StaticBody3D of boxes, moving parts (the farm's windmill), the ground dressing of the crash site. Free roam rewards each one: reaching it marks it DISCOVERED on the map and pays a quarter
## of its reward; the site's own activity (its USE spot: the radio console, the observatory's sky scan, the mine's stash, the crash site's core fragment, the cave's chest, a cabin's rest) pays
## the rest, once. Parked vehicles wait at the villages, farms and the end of the mountain roads (VehicleSpawns.all_points).
## The guard rails of the mountain roads are chunked meshes plus a pool of collision boxes that follows the hero.
## The HIDDEN CAVE is a teleport mouth: walk into the dark and you are in CaveSystem (a small cave system 300 m under the mountain), walk into the exit ring and you are back out.
##   OutskirtsWorld.instance          the node
##   settle(pos)                      build every site within BUILD_R of pos now (tests, captures)
##   site_node(id) / is_built(id)     the live nodes;  use_point(id) world position of the activity;  stats()
## `QT_NO_SITES=1` leaves the sites out (perf A/B runs).

const BUILD_R := 1000.0
const FREE_R := 1800.0
const SHOW_RANGE := 1100.0
const ARRIVE_EXTRA := 26.0                 ## a site is "reached" within r * 0.8 + this
const USE_R := 3.2
const RAIL_POOL := 26
const RAIL_CELL := 400.0

static var instance: OutskirtsWorld = null

var quality := 1
var built := {}                            ## id -> {root, mesh, body, rotors: [], tris}
var cave: CaveSystem
var found_count := 0
var used := {}                             ## id -> true once its activity was done this session
var arrivals := 0
var activities := 0
var rails_tris := 0
var rail_segments := 0
var _tick := 0.0
var _use_tick := 0.0
var _rail_chunks := {}
var _rail_bodies: Array[StaticBody3D] = []
var _rail_at := Vector2(1.0e9, 1.0e9)
var _rest_ready := {}                      ## id -> game seconds when the site's rest is ready again
var _clock := 0.0
var _lights: Array[OmniLight3D] = []


static func attach(parent: Node) -> OutskirtsWorld:
	var w := OutskirtsWorld.new()
	w.name = "Sites"
	parent.add_child(w)
	return w


func _ready() -> void:
	instance = self
	TerrainHeight.warm()
	OutskirtsSites.ensure()
	_build_rails()
	_make_rail_pool()
	_make_lights()
	set_quality(quality)
	set_process(true)
	set_physics_process(true)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)
	for i in _lights.size():
		_lights[i].visible = quality >= 1 and i < (1 if quality == 1 else 2)


func _make_lights() -> void:
	for i in 2:
		var l := OmniLight3D.new()
		l.name = "SiteLight%d" % i
		l.top_level = true
		l.omni_range = 14.0
		l.light_energy = 1.0
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append(l)


# --- building and freeing ---------------------------------------------------------------------------------------------------------------------

func is_built(id: StringName) -> bool:
	return built.has(id)


func site_node(id: StringName) -> Node3D:
	return (built[id]["root"] as Node3D) if built.has(id) else null


func use_point(id: StringName) -> Vector3:
	var s := OutskirtsSites.by_id(id)
	if s.is_empty():
		return Vector3.INF
	var local: Vector3 = built[id]["use"] if built.has(id) else Vector3(0.0, 0.0, -8.0)
	var w := OutskirtsSites.to_world(s, local)
	w.y = maxf(w.y, TerrainHeight.height_at(w.x, w.z)) if StringName(s["kind"]) != &"crash" else w.y
	return w


func ensure_site(id: StringName) -> bool:
	if built.has(id):
		return true
	var s := OutskirtsSites.by_id(id)
	if s.is_empty():
		return false
	var kit := OutskirtsKit.build(s)
	if kit.is_empty():
		return false
	var root := Node3D.new()
	root.name = String(id)
	var sp: Vector3 = s["pos"]
	root.position = sp
	root.rotation.y = float(s["yaw"])
	add_child(root)
	var mi := MeshInstance3D.new()
	mi.name = "Kit"
	mi.mesh = kit["mesh"]
	mi.material_override = OutskirtsKit.material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality >= 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_end = SHOW_RANGE
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	for bx: Dictionary in kit["boxes"]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bx["size"]
		cs.shape = bs
		cs.position = bx["pos"]
		cs.rotation.y = float(bx["yaw"])
		body.add_child(cs)
	root.add_child(body)
	var rotors: Array = []
	for r: Dictionary in kit["rotors"]:
		var rm := MeshInstance3D.new()
		rm.name = "Rotor"
		rm.mesh = r["mesh"]
		rm.material_override = OutskirtsKit.material()
		rm.position = r["pos"]
		rm.visibility_range_end = 300.0
		rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(rm)
		rotors.append({"node": rm, "axis": r["axis"], "speed": r["speed"]})
	var extra := 0
	if StringName(s["kind"]) == &"crash":
		var sc := MeshInstance3D.new()
		sc.name = "Scorch"
		sc.mesh = _scorch(s)
		sc.material_override = OutskirtsKit.material()
		sc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sc.visibility_range_end = SHOW_RANGE
		root.add_child(sc)
		extra += 1
		var smoke := _smoke(Vector3(3.0, float(kit.get("crater_floor", -5.6)) + 6.0, 4.0))
		root.add_child(smoke)
	if StringName(s["kind"]) == &"cave":
		cave = CaveSystem.attach(self, s)
		var portal := MeshInstance3D.new()                    # a faint cold glow in the mouth, the hint that this dark is a way in
		var qm := QuadMesh.new()
		qm.size = Vector2(5.6, 4.0)
		portal.mesh = qm
		var pmat := StandardMaterial3D.new()
		pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pmat.albedo_color = Color(0.2, 0.7, 0.9, 0.18)
		pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		pmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		portal.material_override = pmat
		portal.position = Vector3(0.0, 2.0, 9.6)
		portal.visibility_range_end = 220.0
		root.add_child(portal)
	built[id] = {"root": root, "mesh": mi, "body": body, "rotors": rotors, "tris": int(kit["tris"]) + extra, "use": kit["use"], "lamps": kit["lamps"]}
	return true


func _smoke(at: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Smoke"
	p.position = at
	p.amount = 26 if quality >= 1 else 12
	p.lifetime = 7.0
	p.direction = Vector3.UP
	p.spread = 14.0
	p.gravity = Vector3(0.6, 0.5, 0.2)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 3.6
	p.scale_amount_min = 3.0
	p.scale_amount_max = 7.0
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	p.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.16, 0.17, 0.19, 0.34)
	mat.vertex_color_use_as_albedo = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	p.material_override = mat
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.3, 0.35, 0.4, 0.45))
	ramp.set_color(1, Color(0.2, 0.2, 0.22, 0.0))
	p.color_ramp = ramp
	p.visibility_aabb = AABB(Vector3(-30.0, -10.0, -30.0), Vector3(60.0, 90.0, 60.0))
	return p


## Dark scorched ground around the crater: rings of the real terrain heights (+4 cm), the alien material (dark, with faint glowing veins).
func _scorch(s: Dictionary) -> ArrayMesh:
	var mb := OutskirtsKit.MB.new()
	var sp: Vector3 = s["pos"]
	var yaw: float = s["yaw"]
	var basis := Basis(Vector3.UP, yaw)
	var rings := [6.0, 18.0, 30.0, 42.0, 54.0, 66.0, 78.0, 90.0]
	var seg := 44
	var grid: Array = []
	for ri in rings.size():
		var row: Array[int] = []
		for k in seg:
			var a := TAU * float(k) / float(seg)
			var jit := 1.0 + 0.05 * sin(float(k) * 1.9 + float(ri)) + 0.03 * sin(float(k) * 5.3 + float(ri) * 2.0)
			var lx := cos(a) * float(rings[ri]) * jit
			var lz := sin(a) * float(rings[ri]) * jit
			var w := sp + basis * Vector3(lx, 0.0, lz)
			var fade := 1.0 - clampf((float(rings[ri]) - 30.0) / 70.0, 0.0, 1.0)
			var ash := clampf((float(rings[ri]) - 20.0) / 70.0, 0.0, 1.0)                 # the blast mark fades into the sand at its rim
			var col := Color(lerpf(0.035, 0.28, ash), lerpf(0.032, 0.19, ash), lerpf(0.03, 0.11, ash), OutskirtsKit.ALIEN if ri < 2 else OutskirtsKit.SOIL)
			row.append(mb.vertex(Vector3(lx, TerrainHeight.height_at(w.x, w.z) - sp.y + 0.05 + 0.0 * fade, lz), Vector3.UP, col))
		grid.append(row)
	for ri in rings.size() - 1:
		for k in seg:
			var k2 := (k + 1) % seg
			var a: Array = grid[ri]
			var b: Array = grid[ri + 1]
			mb.tri(a[k], b[k], a[k2])
			mb.tri(a[k2], b[k], b[k2])
	return mb.build(OutskirtsKit.material())


func _free_site(id: StringName) -> void:
	if not built.has(id):
		return
	(built[id]["root"] as Node3D).queue_free()
	if id == &"cave" and cave != null and not cave.inside():
		cave.queue_free()
		cave = null
	built.erase(id)


## Build every site within BUILD_R of `p` now.
func settle(p: Vector3) -> void:
	for s in OutskirtsSites.list:
		var sp: Vector3 = s["pos"]
		if Vector2(sp.x - p.x, sp.z - p.z).length() <= BUILD_R:
			ensure_site(s["id"])


# --- guard rails ------------------------------------------------------------------------------------------------------------------------------

func _build_rails() -> void:
	var segs := GuardRails.segments()
	rail_segments = segs.size()
	var groups := {}
	for s: Dictionary in segs:
		var a: Vector3 = s["a"]
		var key := Vector2i(int(floor(a.x / RAIL_CELL)), int(floor(a.z / RAIL_CELL)))
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(s)
	for key: Vector2i in groups.keys():
		var centre := Vector3((float(key.x) + 0.5) * RAIL_CELL, 0.0, (float(key.y) + 0.5) * RAIL_CELL)
		var m := GuardRails.mesh(groups[key], centre)
		var mi := MeshInstance3D.new()
		mi.name = "Rails_%d_%d" % [key.x, key.y]
		mi.position = centre
		mi.mesh = m
		mi.material_override = OutskirtsKit.material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.visibility_range_end = 520.0
		add_child(mi)
		rails_tris += OutskirtsWorld.tri_count(m)
		_rail_chunks[key] = mi


static func tri_count(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		n += (idx as PackedInt32Array).size() / 3 if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _make_rail_pool() -> void:
	for i in RAIL_POOL:
		var b := StaticBody3D.new()
		b.name = "RailBody%d" % i
		b.collision_layer = Game.L_WORLD
		b.collision_mask = 0
		b.top_level = true
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.35, 1.1, 4.4)
		cs.shape = bs
		b.add_child(cs)
		b.position = Vector3(0.0, -3000.0, 0.0)
		add_child(b)
		_rail_bodies.append(b)


func _refresh_rails(c: Vector2) -> void:
	_rail_at = c
	var near: Array = []
	for s: Dictionary in GuardRails.segments():
		var a: Vector3 = s["a"]
		var d := Vector2(a.x - c.x, a.z - c.y).length()
		if d < 90.0:
			near.append([d, s])
	near.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	for i in _rail_bodies.size():
		var b := _rail_bodies[i]
		if i < near.size():
			var s2: Dictionary = (near[i] as Array)[1]
			var a2: Vector3 = s2["a"]
			var b2: Vector3 = s2["b"]
			var mid := (a2 + b2) * 0.5
			b.global_transform = Transform3D(Basis.looking_at((b2 - a2).normalized() if a2.distance_to(b2) > 0.1 else Vector3.FORWARD, Vector3.UP), mid + Vector3(0.0, 0.55, 0.0))
			(b.get_child(0) as CollisionShape3D).shape.set(&"size", Vector3(0.35, 1.1, maxf(a2.distance_to(b2) + 0.3, 1.0)))
		else:
			b.global_position = Vector3(0.0, -3000.0, 0.0)


# --- the live tick ----------------------------------------------------------------------------------------------------------------------------

func _hero() -> Player:
	var p := Game.player as Player
	return p if is_instance_valid(p) else null


func _process(delta: float) -> void:
	_clock += delta
	var p := _hero()
	if p == null:
		return
	var pp := p.global_position
	for id in built.keys():
		for r: Dictionary in built[id]["rotors"]:
			if Vector2(((built[id]["root"] as Node3D).global_position.x - pp.x), ((built[id]["root"] as Node3D).global_position.z - pp.z)).length() < 320.0:
				(r["node"] as Node3D).rotate(r["axis"], float(r["speed"]) * delta)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.25
	var made := 0
	for s in OutskirtsSites.list:
		var sp: Vector3 = s["pos"]
		var d := Vector2(sp.x - pp.x, sp.z - pp.z).length()
		var id: StringName = s["id"]
		if d <= BUILD_R and not built.has(id) and made < 1:
			ensure_site(id)
			made += 1
		elif d > FREE_R and built.has(id) and not (id == &"cave" and cave != null and cave.inside()):
			_free_site(id)
		if d <= float(s["r"]) * 0.8 + ARRIVE_EXTRA + (30.0 if bool(s.get("hidden", false)) else 0.0) and not OutskirtsSites.is_found(id) and absf(pp.y - sp.y) < 60.0:
			_arrive(s)
	if Vector2(pp.x, pp.z).distance_to(_rail_at) > 12.0:
		_refresh_rails(Vector2(pp.x, pp.z))
	_assign_lights(pp)


func _assign_lights(pp: Vector3) -> void:
	var cands: Array = []
	for id in built.keys():
		var root := built[id]["root"] as Node3D
		for lp: Dictionary in built[id]["lamps"]:
			var w := root.global_transform * (lp["pos"] as Vector3)
			var d := pp.distance_to(w)
			if d < 70.0:
				cands.append([d, w, lp])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in _lights.size():
		if i < cands.size() and quality >= 1:
			var lp2: Dictionary = (cands[i] as Array)[2]
			_lights[i].global_position = (cands[i] as Array)[1]
			_lights[i].light_color = lp2["color"]
			_lights[i].light_energy = float(lp2["energy"])
			_lights[i].omni_range = float(lp2["range"])
			_lights[i].visible = true
		else:
			_lights[i].visible = false


func _arrive(s: Dictionary) -> void:
	var id: StringName = s["id"]
	OutskirtsSites.mark_found(id)
	found_count += 1
	arrivals += 1
	var q := int(float(s["reward"]) * 0.25)
	_pay(q)
	Game.say("DISCOVERED  %s   +%d" % [String(s["name"]), q], 3.2)
	Sfx.play(&"pickup")


func _pay(n: int) -> void:
	var pg := Game.progress as Progress
	if pg != null and n > 0:
		pg.add_credits(n)


func _physics_process(delta: float) -> void:
	_use_tick -= delta
	if _use_tick > 0.0 or not Game.is_playing():
		return
	_use_tick = 0.1
	var p := _hero()
	if p == null or p.is_dead():
		return
	var pp := p.global_position
	if cave != null and cave.inside():
		_cave_tick(p)
		return
	for id in built.keys():
		var s := OutskirtsSites.by_id(id)
		var up := use_point(id)
		if not up.is_finite():
			continue
		var near := Vector2(up.x - pp.x, up.z - pp.z).length() <= (USE_R if StringName(s["kind"]) != &"cave" else 3.4) and absf(pp.y - up.y) < 5.0
		if not near or p.vehicle != null:
			continue
		_use(s, p)


func _use(s: Dictionary, p: Player) -> void:
	var id: StringName = s["id"]
	var kind: StringName = s["kind"]
	if kind == &"cave":
		if cave != null:
			cave.enter(p)
		return
	var first := not used.has(id)
	match kind:
		&"cabins", &"village", &"farm":
			if _clock < float(_rest_ready.get(id, 0.0)):
				return
			_rest_ready[id] = _clock + 45.0
			if p.weapon != null:
				p.weapon.restock(WeaponLadder.AMMO_RESTOCK)
			p.hp = p.max_hp
			Game.say("%s: REST AND RESTOCK" % String(s["name"]) if first else "HEALTH AND AMMO RESTORED", 2.6)
		&"tower":
			if not first:
				return
			Game.say("SIGNAL RESTORED  RADIO TOWER ONLINE", 3.0)
		&"observatory":
			if not first:
				return
			for o in OutskirtsSites.list:
				OutskirtsSites.mark_found(o["id"])
			Game.say("SKY SCAN COMPLETE  EVERY SITE IS ON THE MAP", 3.4)
		&"mine":
			if not first:
				return
			if p.weapon != null:
				p.weapon.restock(WeaponLadder.AMMO_RESTOCK)
			Game.say("MINE STASH  AMMO AND CREDITS", 3.0)
		&"crash":
			if not first:
				return
			Game.say("CORE FRAGMENT RECOVERED", 3.0)
	if first:
		used[id] = true
		activities += 1
		var rest := int(float(s["reward"]) * 0.75)
		_pay(rest)
		Game.say("%s   +%d" % [String(s["tag"]), rest], 2.4)
		FX.burst(use_point(id) + Vector3(0.0, 1.0, 0.0), Color(0.3, 0.95, 1.0), 22, 5.0, 0.7, 4.0, 1.0)
		Sfx.play(&"pickup")


func _cave_tick(p: Player) -> void:
	var pp := p.global_position
	if Vector2(pp.x - cave.exit_ring().x, pp.z - cave.exit_ring().z).length() < 2.2 and absf(pp.y - cave.exit_ring().y) < 4.0 and p.velocity.length() > 0.2:
		cave.leave(p)
		return
	if cave.take_stash(p):
		var s := OutskirtsSites.by_id(&"cave")
		used[&"cave"] = true
		activities += 1
		var rest := int(float(s["reward"]) * 0.75)
		_pay(rest)
		if p.weapon != null:
			p.weapon.restock(WeaponLadder.AMMO_RESTOCK)
		Game.say("THE STASH   +%d" % rest, 3.0)
		Sfx.play(&"pickup")
		FX.burst(cave.stash_point() + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.8, 0.3), 22, 5.0, 0.7, 4.0, 1.0)


func stats() -> Dictionary:
	var tris := 0
	for id in built.keys():
		tris += int(built[id]["tris"])
	return {"sites": OutskirtsSites.list.size(), "built": built.size(), "tris": tris, "rail_segments": rail_segments, "rail_tris": rails_tris, "arrivals": arrivals, "activities": activities, "found": found_count}
