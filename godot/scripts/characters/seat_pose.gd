class_name SeatPose
extends RefCounted
## WAVE 128 (plan line 128, agent w128-anim): WHERE AND HOW THE HERO SITS IN A VEHICLE. Before this wave the hero was simply hidden in every vehicle (Player._apply_vehicle_state): a
## helicopter, a plane or a tank flew and drove with nobody at the controls (the wave 126 critic: "the glider's dark figure on top of the canopy" was its engine pylon; there was no pilot).
## Now PlayerBody keeps the body visible in a seat and CharacterRig poses it seated (CharacterRig.seat*): the pelvis ON the seat, the knees bent, the feet on the pedals or the floor, the
## hands ON the controls, the fingers curled round them, and the controls follow the stick of the player (the cyclic and the flight stick tilt, the yoke and the wheel turn).
##
## The seat is MEASURED on the built model (so it follows any redesign of a model, e.g. the wave 128 aircraft look pass), never typed per kind:
##   cockpit (helicopters, aeroplanes, legacy art aircraft): the cockpit glass of the "Body" mesh (the surfaces whose material is named "Glass"); its front cluster gives where the head
##            goes (under the canopy top, behind the windscreen; the left seat of a wide aeroplane cockpit, the right seat of a wide helicopter cockpit), the hull under it gives the floor; the
##            back reclines as far as the canopy needs (a glider pilot lies back, a helicopter pilot sits up).
##   hatch    (vehicles with a "Turret" node: tanks, carriers, flak): the commander stands in the hatch on the turret roof, chest and head out, both hands on the hatch rim; turns with the turret.
##   astride  (quad, scooter, jet ski): the rider on the saddle, feet on the pegs / the deck, hands on the handlebar grips.
##   none     cars and vans keep their painted driver (CarV2 "driver_on"), drones have nobody aboard, and a model without a cockpit glass keeps the hero hidden as before.
##
## The canopy of the hero's own aircraft is drawn see-through (one per-vehicle material override while he is aboard), so the pilot shows from the chase camera.
##   SeatPose.for_vehicle(v) -> Dictionary (cached per kind)   {style, hip, recline, feet [L, R], hands [L, R], node ("" = the model, "Turret"), top, controls}
##   all points in the frame of `node` (the model: nose -Z, y up from the ground). `controls`: &"cyclic" (heli), &"stick" (plane stick + throttle), &"yoke", &"bars", &"rim".
## W128_OLD=1 (env) or SeatPose.on = false: the old behaviour (hidden in every vehicle).

const HEAD_D := 0.74                       ## hero: pelvis to the centre of the head, sitting upright (rig: hips 0.95, head bone 1.60, head centre ~1.69)
const HEAD_CLEAR := 0.17                   ## head centre below the canopy top
const SHOULDER_D := 0.5                    ## pelvis to the shoulders
const LEG := 0.86                          ## thigh + shin
const MIN_RECLINE := 0.12
const MAX_RECLINE := 1.05
const NO_PILOT: Array[StringName] = [&"p_drone", &"p_ucav"]
const ASTRIDE: Array[StringName] = [&"quad", &"scooter", &"jetski"]

static var on := OS.get_environment("W128_OLD") != "1"
static var _cache := {}
static var _canopy_mat: StandardMaterial3D


## The seat of vehicle `v` (a Vehicle with a built visual), {} when the hero stays hidden in it.
static func for_vehicle(v: Node) -> Dictionary:
	if not on or v == null or not ("kind" in v):
		return {}
	var kind: StringName = v.get(&"kind")
	if _cache.has(kind):
		return _cache[kind]
	var vis = v.get(&"visual")
	var s := {}
	if vis != null and vis.get(&"model") != null and not NO_PILOT.has(kind):
		s = measure(kind, VehicleSpecs.cls_of(kind), vis.get(&"model") as Node3D)
	_cache[kind] = s
	return s


## The measurement (static: tests call it on any built model). `cls` heli / plane / tank / bike / boat / car ...
static func measure(kind: StringName, cls: StringName, model: Node3D) -> Dictionary:
	if model == null:
		return {}
	if ASTRIDE.has(kind):
		return _astride(kind)
	var tur := model.get_node_or_null("Turret") as MeshInstance3D
	if tur != null and tur.mesh != null:
		return _hatch(tur)
	if cls != &"heli" and cls != &"plane":
		return {}
	var body := model.get_node_or_null("Body") as MeshInstance3D
	if body == null or body.mesh == null:
		body = _find_body(model)
	if body == null:
		return {}
	var glass := PackedVector3Array()
	var hull := PackedVector3Array()
	var xf := CharacterRig.chain_to(body, model)
	for si in body.mesh.get_surface_count():
		var m := body.mesh.surface_get_material(si)
		var nm := m.resource_name.to_lower() if m != null else ""
		var verts: PackedVector3Array = body.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		if nm.contains("glass") or nm.contains("canopy") or nm.contains("window"):
			for p in verts:
				glass.append(xf * p)
		else:
			for i in range(0, verts.size(), 3 if verts.size() > 30000 else 1):
				hull.append(xf * verts[i])
	if glass.size() < 3:
		return {}
	return _cockpit(cls, glass, hull)


static func _find_body(model: Node3D) -> MeshInstance3D:
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if m != null and m.resource_name.to_lower().contains("glass"):
				return mi
	return null


## A cockpit under glass. `glass` and `hull`: model-space points.
static func _cockpit(cls: StringName, glass: PackedVector3Array, hull: PackedVector3Array) -> Dictionary:
	var zmin := INF
	for p in glass:
		zmin = minf(zmin, p.z)
	var zmax_all := -INF
	for p in glass:
		zmax_all = maxf(zmax_all, p.z)
	var span := clampf((zmax_all - zmin) * 0.55, 1.1, 2.6)               # the front cluster: the windscreen and the canopy, not the cabin windows of an airliner
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p in glass:
		if p.z <= zmin + span:
			lo = lo.min(p)
			hi = hi.max(p)
	var width := hi.x - lo.x
	var depth := hi.z - lo.z
	var x := 0.0
	if width > 1.3:
		x = clampf(width * 0.22, 0.3, 0.55) * (1.0 if cls == &"heli" else -1.0)     # a helicopter's captain sits right, an aeroplane's left
	var head := Vector3(x, hi.y - HEAD_CLEAR, lerpf(lo.z, hi.z, 0.62))
	if depth < 0.35:                                                         # an open cockpit with a small windscreen: the head is behind it and above it
		head = Vector3(x, hi.y + 0.02, hi.z + 0.5)
	else:
		if cls == &"heli" and depth > 1.6:
			head.z = lerpf(lo.z, hi.z, 0.7)
		var roof := -INF                                                     # the canopy right over the head (a bubble is lower toward its ends than at its peak)
		for p in glass:
			if absf(p.z - head.z) < 0.3 and absf(p.x - x) < 0.45 and p.z <= zmin + span:
				roof = maxf(roof, p.y)
		if roof > -INF:
			head.y = minf(head.y, roof - HEAD_CLEAR - 0.05)
	# the hull under the seat: the lowest hull point near the seat line
	var floor_y := _floor_at(hull, Vector3(x, lo.y, head.z - 0.25), 0.5, 1.4)
	var hip_min := floor_y + 0.16
	var hip_y := head.y - HEAD_D * cos(MIN_RECLINE)
	var r := MIN_RECLINE
	if hip_y < hip_min:                                                   # no room to sit up: lie back like a glider pilot
		hip_y = hip_min
		r = acos(clampf((head.y - hip_y) / HEAD_D, cos(MAX_RECLINE), 1.0))
	var hip := Vector3(x, hip_y, head.z - HEAD_D * sin(r))
	if OS.get_environment("W128_DBG") == "1":
		print("SEATDBG lo %s hi %s head %s floor %.2f r %.2f" % [lo, hi, head, floor_y, r])
	# feet forward on the pedals: as low as the hull allows, the knees a little bent
	var foot_floor := maxf(_floor_at(hull, Vector3(x, hip.y, hip.z - 0.55), 0.5, 0.9), floor_y)
	var dy := clampf(hip.y - (foot_floor + 0.06), 0.05, 0.62)
	var reach := sqrt(maxf(LEG * LEG - dy * dy, 0.04)) * 0.72                 # knees bent: the feet on the pedals stay inside the nose
	var fz := maxf(hip.z - reach, lo.z + 0.3) if cls == &"heli" else hip.z - reach
	var fl := Vector3(x - 0.13, hip.y - dy, fz)
	var fr := Vector3(x + 0.13, hip.y - dy, fz)
	var sh := hip + Vector3(0.0, SHOULDER_D * cos(r), SHOULDER_D * sin(r))
	var controls: StringName = &"cyclic" if cls == &"heli" else (&"yoke" if width > 1.3 else &"stick")
	var hl: Vector3
	var hr: Vector3
	match controls:
		&"cyclic":
			hr = Vector3(x + 0.05, hip.y + 0.3, hip.z - 0.26)                   # the cyclic between the knees
			hl = Vector3(x - 0.27, hip.y + 0.1, hip.z - 0.1)                    # the collective lever beside the seat
		&"stick":
			hr = Vector3(x + 0.05, hip.y + 0.3, hip.z - 0.26)                   # the stick between the knees
			hl = Vector3(x - 0.22, hip.y + 0.22, hip.z - 0.12)                  # the throttle on the left wall
		_:
			hl = Vector3(x - 0.17, sh.y - 0.12, sh.z - 0.38)                     # both hands on the yoke horns
			hr = Vector3(x + 0.17, sh.y - 0.12, sh.z - 0.38)
	return {"style": &"cockpit", "hip": hip, "recline": r, "feet": [fl, fr], "hands": [hl, hr], "node": "", "top": hi.y, "head": head, "controls": controls,
		"glass_lo": lo, "glass_hi": hi}


## The lowest hull point within `rx` (x) and `rz` (z) of `at` and below it (the belly under the seat: a loft has vertices only at its stations, so the z window is wide); at.y - 0.6
## when the hull has nothing there.
static func _floor_at(hull: PackedVector3Array, at: Vector3, rx: float, rz: float) -> float:
	var best := INF
	for p in hull:
		if absf(p.x - at.x) < rx and absf(p.z - at.z) < rz and p.y < at.y:
			best = minf(best, p.y)
	return best if best < INF else at.y - 0.6


## The commander in the hatch of the turret: legs inside, chest and head out, hands on the hatch rim.
static func _hatch(tur: MeshInstance3D) -> Dictionary:
	var ab := tur.mesh.get_aabb()
	var top := _roof(tur.mesh, ab)
	var hx := clampf(ab.position.x + ab.size.x * 0.3, -0.6, 0.0)               # the left half of the roof, a little behind the middle
	var hz := clampf(ab.get_center().z + ab.size.z * 0.12, ab.position.z + 0.4, ab.position.z + ab.size.z - 0.4)
	var hip := Vector3(hx, top - 0.3, hz)                                      # the waist at the roof: chest, arms and head out
	var fl := Vector3(hx - 0.12, hip.y - 0.86, hz + 0.05)
	var fr := Vector3(hx + 0.12, hip.y - 0.86, hz + 0.05)
	var hl := Vector3(hx - 0.34, top + 0.05, hz - 0.16)
	var hr := Vector3(hx + 0.34, top + 0.05, hz - 0.16)
	return {"style": &"hatch", "hip": hip, "recline": 0.0, "feet": [fl, fr], "hands": [hl, hr], "node": "Turret", "top": top, "head": hip + Vector3(0.0, HEAD_D, 0.0), "controls": &"rim"}


## The height of the turret ROOF: the level that carries the most upward-facing area (the AABB top is a cupola, a sight or a gun mantle above the roof).
static func _roof(mesh: Mesh, ab: AABB) -> float:
	var bins := {}
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		var n := (idx as PackedInt32Array).size() if idx != null else v.size()
		for t in range(0, n - 2, 3):
			var a := v[(idx as PackedInt32Array)[t]] if idx != null else v[t]
			var b := v[(idx as PackedInt32Array)[t + 1]] if idx != null else v[t + 1]
			var c := v[(idx as PackedInt32Array)[t + 2]] if idx != null else v[t + 2]
			var cr := (b - a).cross(c - a)
			var area := cr.length() * 0.5
			if area < 0.0001 or cr.normalized().y < 0.85:                         # facing up only
				continue
			var key := int(round((a.y + b.y + c.y) / 3.0 / 0.05))
			bins[key] = float(bins.get(key, 0.0)) + area
	var best := -1
	var top := ab.position.y + ab.size.y
	var best_a := 0.0
	for key: int in bins:
		if float(bins[key]) > best_a and float(key) * 0.05 > ab.position.y + ab.size.y * 0.3:
			best_a = float(bins[key])
			best = key
	for key: int in bins:                                                   # the highest level that still carries a good share of it (a lower glacis or a bustle shelf is not the roof)
		if key > best and float(bins[key]) >= best_a * 0.35:
			best = key
	return float(best) * 0.05 if best_a > 0.0 else top


## The riders of the procedural two- and four-wheelers and the jet ski (VehicleCraftModels: saddle and grips in model space).
static func _astride(kind: StringName) -> Dictionary:
	var hip: Vector3
	var grip_x := 0.42
	var grip := Vector3.ZERO
	var peg_y := 0.42
	var peg_z := -0.05
	var lean := -0.42
	match kind:
		&"scooter":
			hip = Vector3(0.0, 0.84, 0.08)
			grip = Vector3(0.0, 1.12, -0.52)
			grip_x = 0.31
			peg_y = 0.31
			peg_z = -0.2
			lean = -0.5
		&"jetski":
			hip = Vector3(0.0, 0.95, 0.15)
			grip = Vector3(0.0, 1.06, -0.45)
			grip_x = 0.36
			peg_y = 0.55
			peg_z = 0.15
			lean = -0.65
		_:
			hip = Vector3(0.0, 0.92, 0.2)
			grip = Vector3(0.0, 1.26, -0.4)
	var fl := Vector3(-0.26, peg_y, peg_z)
	var fr := Vector3(0.26, peg_y, peg_z)
	return {"style": &"astride", "hip": hip, "recline": lean, "feet": [fl, fr], "hands": [grip + Vector3(-grip_x, 0.0, 0.0), grip + Vector3(grip_x, 0.0, 0.0)], "node": "",
		"top": hip.y + HEAD_D, "head": hip + Vector3(0.0, HEAD_D, 0.0), "controls": &"bars"}


## The see-through canopy of the hero's own aircraft (one shared material; the parked ones keep the dark glass).
static func canopy_material() -> StandardMaterial3D:
	if _canopy_mat == null:
		_canopy_mat = StandardMaterial3D.new()
		_canopy_mat.resource_name = "Glass"
		_canopy_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_canopy_mat.albedo_color = Color(0.12, 0.18, 0.26, 0.42)               # tinted glass that still reads as a canopy (a lighter one vanished and left a bare head over the hull)
		_canopy_mat.metallic = 0.0
		_canopy_mat.metallic_specular = 0.8
		_canopy_mat.roughness = 0.06
		_canopy_mat.rim_enabled = true
		_canopy_mat.rim = 0.6
		_canopy_mat.rim_tint = 0.3
		_canopy_mat.cull_mode = BaseMaterial3D.CULL_DISABLED                    # both faces: the shell reads as glass from outside and from the cockpit view
	return _canopy_mat


## Swap the glass of `body` (the vehicle's Body mesh) to the see-through canopy (on) or back to what it wore (off).
static func set_canopy(body: MeshInstance3D, see_through: bool) -> void:
	if body == null or body.mesh == null:
		return
	for si in body.mesh.get_surface_count():
		var m := body.mesh.surface_get_material(si)
		if m == null or not m.resource_name.to_lower().contains("glass"):
			continue
		if see_through:
			if not body.has_meta("w128_glass_%d" % si):
				body.set_meta("w128_glass_%d" % si, [body.get_surface_override_material(si)])      # (an Array: a null meta value would erase the key)
			body.set_surface_override_material(si, canopy_material())
		elif body.has_meta("w128_glass_%d" % si):
			body.set_surface_override_material(si, (body.get_meta("w128_glass_%d" % si) as Array)[0] as Material)
			body.remove_meta("w128_glass_%d" % si)
