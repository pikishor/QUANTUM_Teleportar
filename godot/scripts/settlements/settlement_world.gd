class_name SettlementWorld
extends Node3D
## The towns in the live world (wave 112). Child `settlements` of the City. Data: SettlementData / SettlementPlan (kind &"town" entries of OutskirtsSites), meshes: SettlementKit.
##
## A town is a root Node3D at its pad (OutskirtsSites.to_world frame) with a few kinds of children:
##   near chunks   80 m squares of the town frame, built when the hero is within BUILD_R (one chunk per tick, nearest first, the mesh of the chunk is relative to its own centre so the visibility range
##                 is measured from the chunk), freed beyond BUILD_R + FREE_EXTRA: one MeshInstance3D (ONE draw call: assets/shaders/settlement.gdshader), one StaticBody3D of boxes and cylinders, the
##                 rotating parts (windmill sails, tower crane)
##   far mesh      ONE cut-down mesh of the whole town (boxes and roofs), built when the hero is within FAR_BUILD_R, drawn beyond the near range with a dither cross-fade
## Door glows (one MultiMesh for every town) follow the hero. `QT_NO_TOWNS=1` leaves the node out (perf A/B). `settle(pos)` builds everything near a point now (tests, captures).
##   SettlementWorld.instance / stats() / settle(pos) / is_built(id) / chunk_count(id) / set_quality(level)

const MB := preload("res://scripts/world/mesh_builder.gd")

const CH := 80.0
const BUILD_R: Array[float] = [230.0, 290.0, 350.0]
const FREE_EXTRA := 90.0
const NEAR_END: Array[float] = [250.0, 310.0, 370.0]
const FAR_END: Array[float] = [1500.0, 2100.0, 2800.0]
const FAR_BUILD_R := 3000.0
const FADE := 40.0
const TICK := 0.1
const MARKERS := 64
const MARKER_R := 70.0

static var instance: SettlementWorld = null

var quality := 1
var towns := {}                                  ## id -> {site, plan, root, chunks: {key: record}, far: MeshInstance3D, origin: Vector2, dims: Vector2i}
var rotors: Array[Dictionary] = []               ## {node (the spinning Node3D), axis (part frame), speed, pos (world)}
var built_total := 0                             ## chunks built so far (tests)
var freed_total := 0
var _tick := 0.0
var _markers: MultiMeshInstance3D
var _marker_doors: Array[Dictionary] = []
var _marker_t := 0.0
var _hero := Vector3.INF
var folk := SettlementFolk.new()                 ## the people standing at their posts (pinned slots of the city crowd)
var _folk_crowd: RefCounted = null


static func attach(parent: Node) -> SettlementWorld:
	var w := SettlementWorld.new()
	w.name = "Towns"
	parent.add_child(w)
	return w


func _ready() -> void:
	instance = self
	TerrainHeight.warm()
	OutskirtsSites.ensure()
	for s in SettlementData.towns():
		_make_town(s)
	_make_markers()
	set_quality(quality)
	set_process(true)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)
	folk.set_tier(quality)
	for id in towns.keys():
		var t: Dictionary = towns[id]
		for key in (t["chunks"] as Dictionary).keys():
			_style_chunk(t["chunks"][key])
		if t["far"] != null:
			_style_far(t["far"])


func _make_town(s: Dictionary) -> void:
	var plan := SettlementData.plan_of(s)
	var root := Node3D.new()
	root.name = String(s["id"])
	var sp: Vector3 = s["pos"]
	root.transform = Transform3D(Basis(Vector3.UP, float(s["yaw"])), Vector3(sp.x, float(s["pad_y"]), sp.z))
	add_child(root)
	var origin := Vector2(-plan.r - 12.0, -plan.ln - 12.0)
	var dims := Vector2i(int(ceil((2.0 * plan.r + 24.0) / CH)), int(ceil((2.0 * plan.ln + 24.0) / CH)))
	towns[s["id"]] = {"site": s, "plan": plan, "root": root, "chunks": {}, "far": null, "origin": origin, "dims": dims}


# --- queries ------------------------------------------------------------------------------------------------------------------------------

func is_built(id: StringName) -> bool:
	return towns.has(id) and not (towns[id]["chunks"] as Dictionary).is_empty()


func chunk_count(id: StringName) -> int:
	return (towns[id]["chunks"] as Dictionary).size() if towns.has(id) else 0


func has_far(id: StringName) -> bool:
	return towns.has(id) and towns[id]["far"] != null


func town_root(id: StringName) -> Node3D:
	return towns[id]["root"] if towns.has(id) else null


func stats() -> Dictionary:
	var chunks := 0
	var tris := 0
	var bodies := 0
	var far := 0
	for id in towns.keys():
		var t: Dictionary = towns[id]
		for key in (t["chunks"] as Dictionary).keys():
			var rec: Dictionary = t["chunks"][key]
			if rec.get("root") != null:
				chunks += 1
				tris += int(rec["tris"])
				bodies += int(rec["shapes"])
		if t["far"] != null:
			far += 1
			tris += int(t["far_tris"]) if t.has("far_tris") else 0
	return {"towns": towns.size(), "chunks": chunks, "tris": tris, "colliders": bodies, "far": far, "built_total": built_total, "freed_total": freed_total, "rotors": rotors.size(), "markers": _marker_doors.size()}


# --- streaming ------------------------------------------------------------------------------------------------------------------------------

func _hero_pos() -> Vector3:
	var p := Game.player as Node3D
	if is_instance_valid(p):
		return p.global_position
	if is_instance_valid(Game.camera):
		return Game.camera.global_position
	return Vector3.INF


func _process(delta: float) -> void:
	_tick -= delta
	_spin_rotors(delta)
	if _tick > 0.0:
		return
	_tick = TICK
	_hero = _hero_pos()
	if not _hero.is_finite():
		return
	_stream(_hero, 1)
	_step_folk(TICK)
	_marker_t -= TICK
	if _marker_t <= 0.0:
		_marker_t = 0.4
		_refresh_markers()


## One round of streaming around `p`: builds at most `budget` chunks (and one far mesh), frees what is out of range.
func _stream(p: Vector3, budget: int) -> void:
	var br := BUILD_R[quality]
	for id in towns.keys():
		var t: Dictionary = towns[id]
		var site: Dictionary = t["site"]
		var sp: Vector3 = site["pos"]
		var d := Vector2(sp.x - p.x, sp.z - p.z).length()
		var plan: SettlementPlan = t["plan"]
		var reach := maxf(plan.r, plan.ln) + br
		if d < FAR_BUILD_R and t["far"] == null:
			_build_far(t)
		elif d > FAR_BUILD_R + 600.0 and t["far"] != null:
			(t["far"] as Node).queue_free()
			t["far"] = null
		if d > reach + FREE_EXTRA + 200.0:
			if not (t["chunks"] as Dictionary).is_empty():
				_free_chunks(t, -1.0)
			continue
		var loc := _to_local(t, p)
		var built := 0
		var want: Array = []
		var dims: Vector2i = t["dims"]
		var org: Vector2 = t["origin"]
		for cj in dims.y:
			for ci in dims.x:
				var key := cj * 100 + ci
				var centre := Vector2(org.x + (float(ci) + 0.5) * CH, org.y + (float(cj) + 0.5) * CH)
				var dc := centre.distance_to(Vector2(loc.x, loc.z))
				if dc < br + CH * 0.5 and not (t["chunks"] as Dictionary).has(key):
					want.append([dc, ci, cj])
		want.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		for w in want:
			if built >= budget:
				break
			_build_chunk(t, int(w[1]), int(w[2]))
			built += 1
		_free_chunks(t, br + FREE_EXTRA + CH, Vector2(loc.x, loc.z))


func _to_local(t: Dictionary, p: Vector3) -> Vector3:
	return (t["root"] as Node3D).global_transform.affine_inverse() * p


func _free_chunks(t: Dictionary, beyond: float, loc := Vector2.ZERO) -> void:
	var org: Vector2 = t["origin"]
	var gone: Array = []
	for key in (t["chunks"] as Dictionary).keys():
		var ci: int = int(key) % 100
		var cj: int = int(key) / 100
		var centre := Vector2(org.x + (float(ci) + 0.5) * CH, org.y + (float(cj) + 0.5) * CH)
		if beyond < 0.0 or centre.distance_to(loc) > beyond:
			gone.append(key)
	for key in gone:
		var rec: Dictionary = t["chunks"][key]
		if rec.get("root") != null:
			(rec["root"] as Node).queue_free()
		for rt in rec.get("rotors", []):
			rotors.erase(rt)
		(t["chunks"] as Dictionary).erase(key)
		freed_total += 1


## Build every chunk within the build radius of `p` now, and the far meshes (tests, captures, teleports).
func settle(p: Vector3) -> void:
	_hero = p
	for pass_i in 400:
		var before := built_total
		_stream(p, 6)
		if built_total == before:
			break


func _build_chunk(t: Dictionary, ci: int, cj: int) -> void:
	var plan: SettlementPlan = t["plan"]
	var org: Vector2 = t["origin"]
	var rect := Rect2(org.x + float(ci) * CH, org.y + float(cj) * CH, CH, CH)
	var key := cj * 100 + ci
	var out := SettlementKit.build(plan, rect, false)
	var m: SettlementMesh = out["mesh"]
	var rec := {"root": null, "tris": 0, "shapes": 0, "rotors": [], "mi": null}
	(t["chunks"] as Dictionary)[key] = rec
	built_total += 1
	if m.is_empty() and (out["boxes"] as Array).is_empty() and (out["cyls"] as Array).is_empty():
		return
	var centre := rect.get_center()
	var c3 := Vector3(centre.x, 0.0, centre.y)
	var cr := Node3D.new()
	cr.name = "C%d_%d" % [ci, cj]
	cr.position = c3
	(t["root"] as Node3D).add_child(cr)
	rec["root"] = cr
	if not m.is_empty():
		m.transform_from(0, Transform3D(Basis.IDENTITY, -c3))
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = m.to_mesh(SettlementKit.material())
		mi.material_override = SettlementKit.material()
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		cr.add_child(mi)
		rec["mi"] = mi
		rec["tris"] = m.tris()
		_style_chunk(rec)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	var n := 0
	for bx: Dictionary in out["boxes"]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bx["size"]
		cs.shape = bs
		cs.position = (bx["pos"] as Vector3) - c3
		cs.rotation.y = float(bx["yaw"])
		body.add_child(cs)
		n += 1
	for cy: Dictionary in out["cyls"]:
		var cs2 := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = float(cy["r"])
		cyl.height = float(cy["h"])
		cs2.shape = cyl
		var cp: Vector3 = cy["pos"]
		cs2.position = Vector3(cp.x, cp.y + float(cy["h"]) * 0.5, cp.z) - c3
		body.add_child(cs2)
		n += 1
	cr.add_child(body)
	rec["shapes"] = n
	for rt: Dictionary in out["rotors"]:
		var holder := Node3D.new()
		holder.position = (rt["pos"] as Vector3) - c3
		holder.rotation.y = float(rt["yaw"])
		cr.add_child(holder)
		var spin := MeshInstance3D.new()
		spin.mesh = (rt["mesh"] as SettlementMesh).to_mesh(SettlementKit.material())
		spin.material_override = SettlementKit.material()
		spin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(spin)
		var rr := {"node": spin, "axis": rt["axis"], "speed": float(rt["speed"])}
		(rec["rotors"] as Array).append(rr)
		rotors.append(rr)


func _style_chunk(rec: Dictionary) -> void:
	var mi := rec.get("mi") as MeshInstance3D
	if mi == null or not is_instance_valid(mi):
		return
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality >= 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = NEAR_END[quality]
	mi.visibility_range_end_margin = FADE
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _build_far(t: Dictionary) -> void:
	var plan: SettlementPlan = t["plan"]
	var out := SettlementKit.build(plan, Rect2(), true)
	var m: SettlementMesh = out["mesh"]
	var mi := MeshInstance3D.new()
	mi.name = "Far"
	mi.mesh = m.to_mesh(SettlementKit.material())
	mi.material_override = SettlementKit.material()
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(t["root"] as Node3D).add_child(mi)
	t["far"] = mi
	t["far_tris"] = m.tris()
	_style_far(mi)


func _style_far(mi: MeshInstance3D) -> void:
	mi.visibility_range_begin = NEAR_END[quality] - FADE
	mi.visibility_range_begin_margin = FADE
	mi.visibility_range_end = FAR_END[quality]
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _spin_rotors(delta: float) -> void:
	if rotors.is_empty() or not _hero.is_finite():
		return
	for rr in rotors:
		var n := rr["node"] as Node3D
		if is_instance_valid(n) and n.global_position.distance_squared_to(_hero) < 360000.0:
			n.rotate_object_local(rr["axis"], float(rr["speed"]) * delta)


# --- the folk ---------------------------------------------------------------------------------------------------------------------------------------

func _step_folk(delta: float) -> void:
	var city := get_parent() as City
	if city == null or city.ambient == null:
		return
	var crowd: Variant = city.ambient.get("crowd")
	if crowd == null:
		return
	if crowd != _folk_crowd:
		_folk_crowd = crowd
		folk.setup(crowd)
		folk.set_tier(quality)
	folk.step(delta, _hero)


# --- door glows --------------------------------------------------------------------------------------------------------------------------------

func _make_markers() -> void:
	var mm := MB.new_multimesh(DoorMarkers.quad_mesh(), MARKERS, true, true)
	_markers = MultiMeshInstance3D.new()
	_markers.name = "DoorGlow"
	_markers.multimesh = mm
	_markers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_markers.custom_aabb = AABB(Vector3(-4600, -50, -4600), Vector3(9200, 600, 9200))
	mm.visible_instance_count = 0
	add_child(_markers)
	_markers.visible = false


func _refresh_markers() -> void:
	_marker_doors.clear()
	var cands: Array = []
	for d in SettlementData.doors():
		var wp: Vector3 = d["wall"]
		var dd := Vector2(wp.x - _hero.x, wp.z - _hero.z).length()
		if dd < MARKER_R:
			cands.append([dd, d])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var mm := _markers.multimesh
	var n := mini(cands.size(), MARKERS)
	var buf := MB.new_buffer(MARKERS, true, true)
	for i in n:
		var d: Dictionary = (cands[i] as Array)[1]
		_marker_doors.append(d)
		var xf := Transform3D(Basis(Vector3.UP, float(d["yaw"])), d["wall"] as Vector3)
		var c := InteriorData.color(d["type"])
		MB.write_instance(buf, i, xf, true, Color(c.r, c.g, c.b, 0.0), true, Color(fposmod(float(int(d["id"])) * 0.61803, 1.0), 0.0, 0.0, 0.0))
	mm.buffer = buf
	mm.visible_instance_count = n
	_markers.visible = n > 0
