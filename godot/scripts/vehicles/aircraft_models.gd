class_name AircraftModels
extends VehicleCraftModels
## Procedural bodies of the two helicopters that have no open-source model (wave 106): the GUNSHIP (tandem canopy, stub wings with rocket pods, chin gun, four-blade rotor) and the HAULER
## (the transport: a deep cabin with a rear ramp, wheels on sponsons, five-blade rotor). Same contract as VehicleCraftModels: one mesh "Body" with the surfaces Body (paint) / Glass / Trim (dark) /
## Chrome, the animated parts as their own nodes with the origin on the pivot: "Rotor" (spins about Y), "TailRotor" (about X). Nose = -Z, the skids / wheels rest on y = 0.
## Lofted fuselages (`_loft`: a stack of superellipse rings) keep them smooth; everything is a few hundred triangles, no texture.
## Also: `add_burner(model, spec)` adds the afterburner cone (node "Burner", hidden until the throttle is up) to a jet model.

const SEGS := 12


## The model root of "gunship" or "hauler" (called from VehicleCraftModels.build).
static func build_air(kind: String, spec: Dictionary) -> Node3D:
	var m := AircraftModels.new()
	var root := Node3D.new()
	root.name = String(spec["model"])
	var rr := float(spec.get("rotor_r", 6.0))
	if kind == "hauler":
		m._hauler()
		root.add_child(_mesh_instance(m))
		root.add_child(_rotor_node("Rotor", Vector3(0.0, 4.55, -0.9), rr, 5, 0.46))
		root.add_child(_tail_node(Vector3(0.28, 5.2, 9.2), 1.7))
	else:
		m._gunship()
		root.add_child(_mesh_instance(m))
		root.add_child(_rotor_node("Rotor", Vector3(0.0, 3.62, 0.3), rr, 4, 0.34))
		root.add_child(_tail_node(Vector3(0.36, 3.2, 8.7), 1.5))
	return root


## A superellipse ring stack: each station is [z, cx, cy, rx, ry] (centre and half sizes in the XY plane at depth z); `n` = 2 is an ellipse, more is boxier. The two ends are closed.
func _loft(surf: int, st: Array, n := 2.0, segs := SEGS) -> void:
	var rings: Array = []
	var centres: Array = []
	for s: Array in st:
		var ring: Array = []
		for i in segs:
			var a := TAU * float(i) / float(segs)
			var ca := cos(a)
			var sa := sin(a)
			var px := signf(ca) * pow(absf(ca), 2.0 / n) * float(s[3])
			var py := signf(sa) * pow(absf(sa), 2.0 / n) * float(s[4])
			ring.append(Vector3(float(s[1]) + px, float(s[2]) + py, float(s[0])))
		rings.append(ring)
		centres.append(Vector3(float(s[1]), float(s[2]), float(s[0])))
	for k in rings.size() - 1:
		var r0: Array = rings[k]
		var r1: Array = rings[k + 1]
		var mid: Vector3 = (centres[k] + centres[k + 1]) * 0.5
		for i in segs:
			var j := (i + 1) % segs
			_tri(surf, r0[i], r1[i], r1[j], mid)
			_tri(surf, r0[i], r1[j], r0[j], mid)
	for e in [0, rings.size() - 1]:
		var ring: Array = rings[e]
		var c: Vector3 = centres[e]
		var other: Vector3 = centres[rings.size() - 1 - e]
		for i in segs:
			_tri(surf, c, ring[i], ring[(i + 1) % segs], other)


## A slanted quad panel (four corners listed around it), double use for fins and stabilisers: two triangles, the normal away from `inside`.
func _quad_panel(surf: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3) -> void:
	_tri(surf, a, b, c, inside)
	_tri(surf, a, c, d, inside)


## A thin slab between two points: `width` across (along d x hint), `thick` the other way. The hint picks the side for near-vertical slabs.
func _slab(surf: int, p0: Vector3, p1: Vector3, width: float, thick: float, hint := Vector3.UP) -> void:
	var d := p1 - p0
	var side := d.cross(hint)
	if side.length() < 0.001:
		side = d.cross(Vector3.RIGHT)
	side = side.normalized() * width * 0.5
	var up := d.cross(side).normalized() * thick * 0.5
	var c := (p0 + p1) * 0.5
	var corners: Array[Vector3] = []
	for e in [p0, p1]:
		for sy in [-1.0, 1.0]:
			for sx in [-1.0, 1.0]:
				corners.append(e + side * sx + up * sy)
	# corners: index = end * 4 + sy * 2 + sx (each 0 or 1)
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	for f: Array in faces:
		_quad_panel(surf, corners[f[0]], corners[f[1]], corners[f[2]], corners[f[3]], c)


# --- gunship ----------------------------------------------------------------------------------------------------------------------------

func _gunship() -> void:
	# fuselage: a narrow tandem body, the tail boom runs on to the fin
	_loft(S_BODY, [[-5.7, 0.0, 1.32, 0.1, 0.1], [-5.0, 0.0, 1.3, 0.42, 0.42], [-3.8, 0.0, 1.38, 0.74, 0.8], [-2.0, 0.0, 1.62, 0.92, 1.0], [0.2, 0.0, 1.78, 0.98, 1.08], [2.2, 0.0, 1.86, 0.82, 0.9],
		[3.8, 0.0, 2.0, 0.5, 0.56], [6.2, 0.0, 2.15, 0.3, 0.38], [8.8, 0.0, 2.3, 0.2, 0.3]], 2.4)
	# two canopies (gunner in front, pilot behind) on the top of the nose section
	_prism(S_GLASS, [Vector2(-4.7, 1.55), Vector2(-3.7, 2.45), Vector2(-2.5, 2.62), Vector2(-2.4, 1.7)], -0.5, 0.5)
	_prism(S_GLASS, [Vector2(-2.2, 1.9), Vector2(-1.6, 2.72), Vector2(0.2, 2.82), Vector2(0.9, 1.95)], -0.52, 0.52)
	_box(S_TRIM, Vector3(0.0, 2.55, -2.35), Vector3(0.14, 0.34, 0.1))                           # the divider between the canopies
	# engines on the shoulders and the exhausts
	for sx in [-1.0, 1.0]:
		_cyl(S_TRIM, Vector3(sx * 0.82, 2.55, 1.5), 0.44, 3.0, 2, 8)
		_cyl(S_CHROME, Vector3(sx * 0.82, 2.55, 3.05), 0.3, 0.22, 2, 8)
		_cyl(S_TRIM, Vector3(sx * 0.82, 2.55, -0.25), 0.46, 0.5, 2, 8)                          # the intake lip
	# stub wings with pylons: rocket pods (outer) and a missile rail (inner)
	for sx in [-1.0, 1.0]:
		_slab(S_BODY, Vector3(sx * 1.0, 1.55, 0.35), Vector3(sx * 3.2, 1.62, 0.55), 1.5, 0.14)
		for px in [2.3, 3.0]:
			_cyl(S_TRIM, Vector3(sx * px, 1.18, 0.1), 0.26, 2.0, 2, 8)                        # rocket pod
			_cyl(S_CHROME, Vector3(sx * px, 1.18, -0.95), 0.2, 0.04, 2, 8)                      # the muzzle ring (its tip)
			_box(S_TRIM, Vector3(sx * px, 1.42, 0.1), Vector3(0.1, 0.26, 0.5))                  # the pylon
	# chin turret and the gun barrel
	_cyl(S_TRIM, Vector3(0.0, 0.72, -3.7), 0.36, 0.55, 1, 10)
	_cyl(S_CHROME, Vector3(0.0, 0.62, -4.6), 0.07, 1.5, 2, 6)
	# sensor ball on the nose
	_cyl(S_TRIM, Vector3(0.0, 1.55, -5.2), 0.3, 0.4, 2, 10)
	# tail: fin, tail plane, tail rotor boom end
	_quad_panel(S_BODY, Vector3(0.0, 2.3, 7.6), Vector3(0.0, 2.3, 9.2), Vector3(0.0, 4.0, 9.0), Vector3(0.0, 3.5, 8.0), Vector3(1.0, 2.5, 8.4))
	_quad_panel(S_BODY, Vector3(0.0, 2.3, 7.6), Vector3(0.0, 3.5, 8.0), Vector3(0.0, 4.0, 9.0), Vector3(0.0, 2.3, 9.2), Vector3(-1.0, 2.5, 8.4))
	_slab(S_BODY, Vector3(-1.5, 2.55, 8.2), Vector3(1.5, 2.55, 8.2), 1.0, 0.1)
	# the mast and the rotor head
	_cyl(S_TRIM, Vector3(0.0, 2.7, 0.3), 0.26, 0.9, 1, 8)
	_cyl(S_TRIM, Vector3(0.0, 3.4, 0.3), 0.34, 0.22, 1, 8)
	# skids with cross tubes
	for sx in [-1.0, 1.0]:
		_slab(S_TRIM, Vector3(sx * 1.15, 0.1, -2.6), Vector3(sx * 1.15, 0.1, 2.4), 0.14, 0.12)
		_slab(S_TRIM, Vector3(sx * 1.15, 0.1, -2.6), Vector3(sx * 0.9, 0.5, -3.1), 0.12, 0.1)
		_slab(S_TRIM, Vector3(sx * 1.15, 0.5, -1.3), Vector3(sx * 0.7, 1.12, -1.3), 0.12, 0.1)
		_slab(S_TRIM, Vector3(sx * 1.15, 0.5, 1.2), Vector3(sx * 0.7, 1.16, 1.2), 0.12, 0.1)


# --- hauler -----------------------------------------------------------------------------------------------------------------------------

func _hauler() -> void:
	# the cabin: a deep boxy fuselage, a glazed nose, the tail ramp rises into the boom
	_loft(S_BODY, [[-6.4, 0.0, 1.9, 0.5, 0.5], [-5.5, 0.0, 1.95, 1.05, 1.0], [-3.8, 0.0, 2.15, 1.5, 1.45], [-1.0, 0.0, 2.3, 1.66, 1.6], [3.2, 0.0, 2.3, 1.66, 1.6], [5.4, 0.0, 2.55, 1.2, 1.12],
		[7.4, 0.0, 3.0, 0.62, 0.62], [9.4, 0.0, 3.5, 0.3, 0.4]], 2.9)
	# cockpit glass: the wide windscreen and the side windows
	_prism(S_GLASS, [Vector2(-5.9, 2.2), Vector2(-5.0, 3.1), Vector2(-3.9, 3.35), Vector2(-3.6, 2.35)], -1.12, 1.12)
	for sx in [-1.0, 1.0]:
		_box(S_GLASS, Vector3(sx * 1.52, 2.9, -4.1), Vector3(0.1, 0.62, 1.5))
		_box(S_TRIM, Vector3(sx * 1.68, 2.3, 0.9), Vector3(0.06, 1.3, 2.4))                    # the sliding cargo door
		_box(S_GLASS, Vector3(sx * 1.69, 2.85, -1.0), Vector3(0.05, 0.5, 0.9))
	# the tail ramp (dark) and the upswept boom with the fin
	_prism(S_TRIM, [Vector2(5.4, 1.5), Vector2(7.2, 2.35), Vector2(7.2, 2.7), Vector2(5.4, 2.0)], -0.9, 0.9)
	_quad_panel(S_BODY, Vector3(0.0, 3.0, 8.0), Vector3(0.0, 3.4, 9.6), Vector3(0.0, 5.6, 9.4), Vector3(0.0, 5.0, 8.2), Vector3(1.0, 3.5, 8.8))
	_quad_panel(S_BODY, Vector3(0.0, 3.0, 8.0), Vector3(0.0, 5.0, 8.2), Vector3(0.0, 5.6, 9.4), Vector3(0.0, 3.4, 9.6), Vector3(-1.0, 3.5, 8.8))
	_slab(S_BODY, Vector3(-1.7, 3.4, 8.9), Vector3(1.7, 3.4, 8.9), 1.2, 0.12)
	# engines above the cabin, exhausts to the rear
	for sx in [-1.0, 1.0]:
		_cyl(S_TRIM, Vector3(sx * 0.95, 4.3, 0.0), 0.5, 3.6, 2, 8)
		_cyl(S_CHROME, Vector3(sx * 0.95, 4.3, 1.9), 0.34, 0.2, 2, 8)
	# the mast and head
	_cyl(S_TRIM, Vector3(0.0, 4.0, -0.9), 0.34, 0.6, 1, 8)
	# sponsons with the wheels, a front nose wheel
	for sx in [-1.0, 1.0]:
		_box(S_BODY, Vector3(sx * 1.85, 1.0, 0.4), Vector3(0.7, 0.8, 3.0))
		_cyl(S_TRIM, Vector3(sx * 1.95, 0.42, 0.4), 0.42, 0.34, 0, 10)
		_box(S_TRIM, Vector3(sx * 1.85, 0.8, 0.4), Vector3(0.12, 0.7, 0.14))
	_cyl(S_TRIM, Vector3(0.0, 0.3, -4.4), 0.3, 0.26, 0, 10)
	_box(S_TRIM, Vector3(0.0, 0.8, -4.4), Vector3(0.1, 1.2, 0.1))
	# a door gun on the left side window frame
	_cyl(S_CHROME, Vector3(-1.9, 2.5, -1.9), 0.06, 1.0, 2, 6)


# --- animated parts ---------------------------------------------------------------------------------------------------------------------

## The main rotor: `blades` slabs around the hub, a hub cap, everything dark (the surface Trim). Its origin is the hub, so it spins about Y.
static func _rotor_node(nm: String, hub: Vector3, radius: float, blades: int, chord: float) -> MeshInstance3D:
	var m := AircraftModels.new()
	for i in blades:
		var a := TAU * float(i) / float(blades)
		m._slab(S_TRIM, Vector3(cos(a) * 0.3, 0.0, sin(a) * 0.3), Vector3(cos(a) * radius, 0.0, sin(a) * radius), chord, 0.07)
	m._cyl(S_TRIM, Vector3(0.0, -0.1, 0.0), 0.32, 0.26, 1, 8)
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = m._finish()
	mi.position = hub
	return mi


## The tail rotor: two crossed blades in the YZ plane (it spins about X), origin on the hub at the tail.
static func _tail_node(hub: Vector3, radius: float) -> MeshInstance3D:
	var m := AircraftModels.new()
	m._slab(S_TRIM, Vector3(0.0, -radius, 0.0), Vector3(0.0, radius, 0.0), 0.2, 0.04, Vector3.BACK)
	m._slab(S_TRIM, Vector3(0.0, 0.0, -radius), Vector3(0.0, 0.0, radius), 0.2, 0.04)
	m._cyl(S_TRIM, Vector3.ZERO, 0.12, 0.2, 0, 8)
	var mi := MeshInstance3D.new()
	mi.name = "TailRotor"
	mi.mesh = m._finish()
	mi.position = hub
	return mi


## The afterburner of a jet: a long soft cone behind the tail, additive and unshaded, hidden until the throttle is up (VehicleCraft.sync scales it with the thrust).
static func add_burner(model: Node3D, spec: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Burner"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.42
	cm.height = 1.0
	cm.radial_segments = 8
	cm.rings = 1
	var mat := StandardMaterial3D.new()
	mat.resource_name = "Burner"
	mat.albedo_color = Color(1.0, 0.62, 0.22, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.15)
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cm.material = mat
	mi.mesh = cm
	mi.rotation = Vector3(PI * 0.5, 0.0, 0.0)                    # the cone's axis along Z, its wide end towards the tail
	mi.position = Vector3(0.0, float(spec["hgt"]) * 0.34, float(spec["len"]) * 0.5 + 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	model.add_child(mi)
