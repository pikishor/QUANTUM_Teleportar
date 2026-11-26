class_name HeliModels
extends AircraftModels
## WAVE 125 HELICOPTER ROSTER: the procedural bodies of the twenty helicopters of HeliRoster (own-made, no texture, original designs). One parametric builder reads the kind's
## model parameters (HeliRoster.DEFS[kind]["m"]) and makes the same node contract as AircraftModels: "Body" (surfaces Body = paint / Glass / Trim / Chrome), "Detail" (gear, guns, winches,
## the small parts: hidden beyond DETAIL_FAR m, the cheap far look), "Glow" (the emissive marks: a medic cross, a police beacon, the quantum rings: one draw), "Rotor" (spins about Y),
## "Rotor2" (the second rotor of a tandem, coaxial or tilt-rotor craft, counter-rotating) and "TailRotor" (about X). Nose = -Z, the gear rests on y = 0.
## SHARED MESHES: every mesh of a kind is built once and cached (`_cache`), so ten parked helicopters of a kind share one set of ArrayMeshes and materials.
##   build(kind, spec) -> Node3D           the model root (VehicleCraftModels.build calls it for every kind of HeliRoster)
##   tri_count(kind) -> int                 triangles of the whole model (the budget check of tests/test_helis_w125.gd)

const DETAIL_FAR := 70.0                     ## m: the gear and small parts are hidden beyond this (the body and rotors carry the shape)
const GLOW_FAR := 160.0

static var _cache := {}


static func build(kind: String, spec: Dictionary) -> Node3D:
	var k := StringName(kind)
	if not _cache.has(k):
		_cache[k] = _make(k, spec)
	var c: Dictionary = _cache[k]
	var root := Node3D.new()
	root.name = String(spec.get("model", kind))
	for part: Dictionary in c["parts"]:
		var mi := MeshInstance3D.new()
		mi.name = part["name"]
		mi.mesh = part["mesh"]
		mi.position = part["pos"]
		if part["name"] == "Detail":
			mi.visibility_range_end = DETAIL_FAR
			mi.visibility_range_end_margin = 6.0
		elif part["name"] == "Glow":
			mi.visibility_range_end = GLOW_FAR
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


static func tri_count(kind: StringName) -> int:
	if not _cache.has(kind):
		return 0
	var n := 0
	for part: Dictionary in _cache[kind]["parts"]:
		var m: Mesh = part["mesh"]
		for s in m.get_surface_count():
			n += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


static var _glow_mats := {}

static func _glow_material(col: Color) -> StandardMaterial3D:
	var key := col.to_html()
	if not _glow_mats.has(key):
		var m := StandardMaterial3D.new()
		m.resource_name = "Glow"
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col
		_glow_mats[key] = m
	return _glow_mats[key]


static func _make(kind: StringName, spec: Dictionary) -> Dictionary:
	var P: Dictionary = HeliRoster.DEFS[kind]["m"]
	var body := HeliModels.new()
	var det := HeliModels.new()
	var glow := HeliModels.new()
	var parts: Array[Dictionary] = []
	var rr := float(spec.get("rotor_r", 5.0))
	var g := body._geom(P, det, glow, rr)
	parts.append({"name": "Body", "mesh": body._finish(), "pos": Vector3.ZERO})
	parts.append({"name": "Detail", "mesh": det._finish(), "pos": Vector3.ZERO})
	if not glow._v[S_BODY].is_empty():
		var gm := glow._finish()
		gm.surface_set_material(0, _glow_material(Color(P.get("mark", Color(1.0, 0.2, 0.2)))))
		parts.append({"name": "Glow", "mesh": gm, "pos": Vector3.ZERO})
	var blades := int(P["rotor"][2])
	var chord := float(P["rotor"][3])
	var r1 := _rotor_node("Rotor", g["hub"], rr, blades, chord)
	parts.append({"name": "Rotor", "mesh": r1.mesh, "pos": r1.position})
	r1.free()
	if g.has("hub2"):
		var r2 := _rotor_node("Rotor2", g["hub2"], rr, blades, chord)
		parts.append({"name": "Rotor2", "mesh": r2.mesh, "pos": r2.position})
		r2.free()
	if g.has("tail"):
		var t := _tail_node(g["tail"], g["tail_r"])
		parts.append({"name": "TailRotor", "mesh": t.mesh, "pos": t.position})
		t.free()
	return {"parts": parts}


## Everything but the rotors. Returns the hub positions: hub, hub2 (optional), tail + tail_r (optional).
func _geom(P: Dictionary, det: HeliModels, glow: HeliModels, rr: float) -> Dictionary:
	var cab: Array = P["cab"]
	var zn := float(cab[0])
	var zr := float(cab[1])
	var hw := float(cab[2])
	var hh := float(cab[3])
	var yc := float(cab[4])
	var L := zr - zn
	var n := float(P.get("n", 2.4))
	var nose := String(P.get("nose", "glass"))
	var x: Array = P.get("x", [])
	var lay := String(P.get("lay", "single"))
	var out := {}
	# --- the fuselage: the cabin, then the boom (a loft), or a truss
	var st: Array = []
	if nose == "point" or nose == "tandem" or nose == "facet":
		st.append([zn, 0.0, yc - hh * 0.15, hw * 0.16, hh * 0.22])
		st.append([zn + L * 0.16, 0.0, yc - hh * 0.05, hw * 0.62, hh * 0.72])
	else:
		st.append([zn, 0.0, yc, hw * 0.3, hh * 0.32])
		st.append([zn + L * 0.09, 0.0, yc, hw * 0.78, hh * 0.84])
	st.append([zn + L * 0.3, 0.0, yc + hh * 0.03, hw, hh])
	st.append([zr - L * 0.12, 0.0, yc + hh * 0.05, hw, hh])
	st.append([zr, 0.0, yc + hh * 0.22, hw * 0.62, hh * 0.68])
	var boom: Array = P.get("boom", [])
	var truss := x.has("truss") or x.has("spine")
	if not boom.is_empty() and not truss:
		var bz := float(boom[0])
		var by := float(boom[1])
		var br := float(boom[2])
		st.append([lerpf(zr, bz, 0.35), 0.0, lerpf(yc + hh * 0.3, by, 0.35), br * 1.7, br * 1.8])
		st.append([bz, 0.0, by, br, br * 1.1])
	_loft(S_BODY, st, n)
	# --- the glass: a shell over the front of the cabin, raised so the belly stays paint (a bubble: glass to the chin)
	var gl: Array = []
	var lift := 0.0 if nose == "bubble" else hh * 0.16
	var k := 1.035
	for i in 3:
		var s: Array = st[i]
		gl.append([float(s[0]) - (0.03 if i == 0 else 0.0), 0.0, float(s[2]) + lift, float(s[3]) * k, float(s[4]) * k])
	if nose == "bubble":
		gl.append([zn + L * 0.42, 0.0, yc + hh * 0.04, hw * 1.02, hh * 1.02])
	if nose == "tandem":                                                             # two canopies one behind the other over a slim body
		_loft(S_GLASS, [[zn + L * 0.14, 0.0, yc + hh * 0.7, hw * 0.25, hh * 0.15], [zn + L * 0.24, 0.0, yc + hh * 0.95, hw * 0.7, hh * 0.35], [zn + L * 0.34, 0.0, yc + hh * 0.9, hw * 0.7, hh * 0.3]], 2.0, 10)
		_loft(S_GLASS, [[zn + L * 0.38, 0.0, yc + hh * 0.95, hw * 0.3, hh * 0.2], [zn + L * 0.5, 0.0, yc + hh * 1.15, hw * 0.75, hh * 0.38], [zn + L * 0.62, 0.0, yc + hh * 1.05, hw * 0.72, hh * 0.32]], 2.0, 10)
	else:
		_loft(S_GLASS, gl, n)
	# side windows on long cabins
	if L > 4.5 and nose != "tandem":
		var nw := clampi(int(L / 2.4), 1, 4)
		for sx: float in [-1.0, 1.0]:
			for i in nw:
				var wz := lerpf(zn + L * 0.42, zr - L * 0.16, (float(i) + 0.5) / float(nw))
				_box(S_GLASS, Vector3(sx * hw * 0.985, yc + hh * 0.32, wz), Vector3(0.06, hh * 0.45, minf(L * 0.6 / float(nw), 1.3)))
	# --- the truss / spine boom
	if truss and not boom.is_empty():
		var bz2 := float(boom[0])
		var by2 := float(boom[1])
		var br2 := float(boom[2])
		var a := Vector3(0.0, yc + hh * 0.4, zr - 0.2)
		var b := Vector3(0.0, by2, bz2)
		if x.has("spine"):
			_slab(S_BODY, a + Vector3(0.0, 0.0, zn - zr + L * 0.5), b, br2 * 2.4, br2 * 2.0)            # the crane's backbone runs from the cockpit to the tail
			_slab(S_BODY, Vector3(0.0, yc + hh * 0.9, zr), Vector3(0.0, by2 + 0.6, zr + (bz2 - zr) * 0.35), 1.4, 0.9)
		else:
			for sx: float in [-1.0, 1.0]:
				_slab(S_TRIM, a + Vector3(sx * 0.32, 0.25, 0.0), b + Vector3(sx * 0.06, 0.1, 0.0), br2, br2)
			_slab(S_TRIM, a + Vector3(0.0, -0.3, 0.0), b - Vector3(0.0, 0.1, 0.0), br2, br2)
	# --- the tail
	var tail := String(P.get("tail", "rotor"))
	if not boom.is_empty():
		var bz3 := float(boom[0])
		var by3 := float(boom[1])
		var fh := float(P.get("fin", 1.3 + rr * 0.12))
		_quad_panel(S_BODY, Vector3(0.0, by3, bz3 - 1.4), Vector3(0.0, by3, bz3 + 0.25), Vector3(0.0, by3 + fh, bz3 + 0.1), Vector3(0.0, by3 + fh * 0.7, bz3 - 0.7), Vector3(1.0, by3, bz3))
		_quad_panel(S_BODY, Vector3(0.0, by3, bz3 - 1.4), Vector3(0.0, by3 + fh * 0.7, bz3 - 0.7), Vector3(0.0, by3 + fh, bz3 + 0.1), Vector3(0.0, by3, bz3 + 0.25), Vector3(-1.0, by3, bz3))
		var span := 0.9 + rr * 0.12
		_slab(S_BODY, Vector3(-span, by3 + 0.1, bz3 - 1.0), Vector3(span, by3 + 0.1, bz3 - 1.0), 0.8, 0.1)
		if x.has("fins2"):
			for sx: float in [-1.0, 1.0]:
				_quad_panel(S_BODY, Vector3(sx * span, by3 - 0.4, bz3 - 1.5), Vector3(sx * span, by3 - 0.4, bz3 - 0.4), Vector3(sx * span, by3 + 0.9, bz3 - 0.3), Vector3(sx * span, by3 + 0.9, bz3 - 1.1), Vector3(0.0, by3, bz3 - 1.0))
		var tr := maxf(rr * 0.17, 0.7)
		if tail == "rotor":
			out["tail"] = Vector3(0.3 + float(boom[2]), by3 + fh * 0.45, bz3 - 0.2)
			out["tail_r"] = tr
		elif tail == "fen":                                                          # a shrouded fan in the fin: a disc of paint with a dark face each side
			_cyl(S_BODY, Vector3(0.0, by3 + fh * 0.4, bz3 - 0.35), tr * 0.95, 0.42, 0, 12)
			for sx: float in [-1.0, 1.0]:
				det._cyl(S_TRIM, Vector3(sx * 0.215, by3 + fh * 0.4, bz3 - 0.35), tr * 0.72, 0.02, 0, 12)
	# --- the rotor masts and hubs
	var rot: Array = P["rotor"]
	var ry := float(rot[0])
	var rz := float(rot[1])
	var top := yc + hh * 0.9
	match lay:
		"tandem":
			var z1 := zn + L * 0.12
			var z2 := zr - L * 0.06
			var y2 := ry + 1.1
			_cyl(S_TRIM, Vector3(0.0, (top + ry) * 0.5, z1), 0.3, ry - top + 0.2, 1, 8)
			_box(S_BODY, Vector3(0.0, (top + y2) * 0.5 - 0.2, z2 - 0.6), Vector3(hw * 0.9, y2 - top + 0.4, 2.6))         # the rear pylon
			out["hub"] = Vector3(0.0, ry, z1)
			out["hub2"] = Vector3(0.0, y2, z2)
		"coax":
			_cyl(S_TRIM, Vector3(0.0, (top + ry + 0.9) * 0.5, rz), 0.28, ry + 0.9 - top + 0.2, 1, 8)
			out["hub"] = Vector3(0.0, ry, rz)
			out["hub2"] = Vector3(0.0, ry + 0.9, rz)
		"tilt":
			var wy := yc + hh * 0.95
			var span2 := float(P.get("span", 6.4))
			_slab(S_BODY, Vector3(-span2, wy, rz), Vector3(span2, wy, rz), 2.0, 0.24)
			for sx: float in [-1.0, 1.0]:
				_cyl(S_BODY, Vector3(sx * span2, wy + 0.4, rz), 0.55, 2.6, 1, 10)                  # the nacelles stand up (helicopter mode)
				det._cyl(S_CHROME, Vector3(sx * span2, wy + 1.75, rz), 0.3, 0.2, 1, 8)
			out["hub"] = Vector3(-span2, ry, rz)
			out["hub2"] = Vector3(span2, ry, rz)
		_:
			_cyl(S_TRIM, Vector3(0.0, (top + ry) * 0.5, rz), 0.26, ry - top + 0.2, 1, 8)
			_cyl(S_TRIM, Vector3(0.0, top + 0.12, rz + 0.3), hw * 0.55, 0.36, 1, 8)            # the engine fairing under the mast
			out["hub"] = Vector3(0.0, ry, rz)
	if x.has("ring"):                                                                   # the quantum ring: a glowing hoop around each rotor disc on four thin struts
		var hubs: Array = [out["hub"]]
		if out.has("hub2"):
			hubs.append(out["hub2"])
		for hb: Vector3 in hubs:
			var segs := 20
			for i in segs:
				var a0 := TAU * float(i) / float(segs)
				var a1 := TAU * float(i + 1) / float(segs)
				glow._slab(S_BODY, hb + Vector3(cos(a0), 0.0, sin(a0)) * (rr + 0.25), hb + Vector3(cos(a1), 0.0, sin(a1)) * (rr + 0.25), 0.22, 0.12)
			for i in 4:
				var a2 := TAU * (float(i) + 0.5) / 4.0
				det._slab(S_TRIM, hb + Vector3(0.0, -0.35, 0.0) + Vector3(cos(a2), 0.0, sin(a2)) * 0.4, hb + Vector3(0.0, -0.15, 0.0) + Vector3(cos(a2), 0.0, sin(a2)) * (rr + 0.25), 0.1, 0.08)
	# --- the gear
	var gear := String(P.get("gear", "skids"))
	var bot := yc - hh
	match gear:
		"skids":
			for sx: float in [-1.0, 1.0]:
				var gx := sx * (hw + 0.12)
				det._slab(S_TRIM, Vector3(gx, 0.08, zn + L * 0.18), Vector3(gx, 0.08, zr - L * 0.05), 0.12, 0.1)
				det._slab(S_TRIM, Vector3(gx, 0.08, zn + L * 0.18), Vector3(gx * 0.95, 0.4, zn + L * 0.1), 0.1, 0.1)
				for fz: float in [0.3, 0.75]:
					det._slab(S_TRIM, Vector3(gx, 0.08, zn + L * fz), Vector3(sx * hw * 0.6, bot + 0.15, zn + L * fz), 0.1, 0.09)
		"wheels":
			det._cyl(S_TRIM, Vector3(0.0, 0.3, zn + L * 0.14), 0.3, 0.22, 0, 10)
			det._box(S_TRIM, Vector3(0.0, (0.3 + bot) * 0.5 + 0.1, zn + L * 0.14), Vector3(0.1, maxf(bot - 0.2, 0.2), 0.1))
			for sx: float in [-1.0, 1.0]:
				det._cyl(S_TRIM, Vector3(sx * (hw + 0.15), 0.36, zr - L * 0.28), 0.36, 0.28, 0, 10)
				det._slab(S_TRIM, Vector3(sx * (hw + 0.1), 0.4, zr - L * 0.28), Vector3(sx * hw * 0.7, bot + 0.2, zr - L * 0.28), 0.12, 0.12)
		"floats":
			for sx: float in [-1.0, 1.0]:
				_loft(S_BODY, [[zn + L * 0.02, sx * (hw + 0.35), 0.4, 0.1, 0.1], [zn + L * 0.12, sx * (hw + 0.35), 0.38, 0.34, 0.32], [zr - L * 0.1, sx * (hw + 0.35), 0.36, 0.34, 0.3], [zr + 0.2, sx * (hw + 0.35), 0.4, 0.12, 0.12]], 2.0, 8)
				for fz: float in [0.28, 0.72]:
					det._slab(S_TRIM, Vector3(sx * (hw + 0.35), 0.6, zn + L * fz), Vector3(sx * hw * 0.7, bot + 0.2, zn + L * fz), 0.12, 0.1)
		"legs":
			for sx: float in [-1.0, 1.0]:
				for fz: float in [0.15, 0.85]:
					var foot := Vector3(sx * (hw + 0.9), 0.06, zn + L * fz)
					det._slab(S_TRIM, foot + Vector3(0.0, 0.05, 0.0), Vector3(sx * hw * 0.7, bot + 0.3, zn + L * fz), 0.16, 0.16)
					det._cyl(S_TRIM, foot, 0.32, 0.1, 1, 8)
	# --- the extras
	for e: String in x:
		match e:
			"camera":
				det._cyl(S_TRIM, Vector3(0.0, bot + 0.05, zn + L * 0.12), 0.32, 0.5, 1, 10)
				det._cyl(S_GLASS, Vector3(0.0, bot - 0.15, zn + L * 0.08), 0.16, 0.06, 2, 8)
			"mast":
				det._slab(S_TRIM, Vector3(0.0, yc + hh, zr - L * 0.2), Vector3(0.0, yc + hh + 0.9, zr - L * 0.1), 0.05, 0.05)
				det._box(S_CHROME, Vector3(0.0, yc + hh + 0.95, zr - L * 0.1), Vector3(0.6, 0.06, 0.3))
			"light":
				det._cyl(S_CHROME, Vector3(hw * 0.5, bot - 0.05, zn + L * 0.28), 0.22, 0.34, 2, 8)
				glow._cyl(S_BODY, Vector3(hw * 0.5, bot - 0.05, zn + L * 0.28 - 0.18), 0.16, 0.03, 2, 8)
			"bar":
				glow._box(S_BODY, Vector3(0.0, yc + hh * 0.98, zr - L * 0.25), Vector3(0.9, 0.12, 0.22))
				for sx: float in [-1.0, 1.0]:
					glow._box(S_BODY, Vector3(sx * hw * 1.0, yc + hh * 0.05, zn + L * 0.55), Vector3(0.03, 0.12, L * 0.5))
			"cross":
				for sx: float in [-1.0, 1.0]:
					var cc := Vector3(sx * hw * 1.0, yc + hh * 0.05, zr - L * 0.3)
					glow._box(S_BODY, cc, Vector3(0.04, 0.24, 0.8))
					glow._box(S_BODY, cc, Vector3(0.04, 0.8, 0.24))
			"stripe":
				for sx: float in [-1.0, 1.0]:
					glow._box(S_BODY, Vector3(sx * hw * 0.99, yc - hh * 0.2, zn + L * 0.5), Vector3(0.03, 0.1, L * 0.75))
			"winch":
				det._box(S_TRIM, Vector3(hw * 1.05, yc + hh * 0.8, zn + L * 0.5), Vector3(0.5, 0.3, 0.5))
				det._slab(S_CHROME, Vector3(hw * 0.9, yc + hh * 0.8, zn + L * 0.5), Vector3(hw * 1.5, yc + hh * 0.8, zn + L * 0.5), 0.1, 0.1)
			"wings":
				for sx: float in [-1.0, 1.0]:
					_slab(S_BODY, Vector3(sx * hw * 0.9, yc - hh * 0.2, zn + L * 0.7), Vector3(sx * (hw + 2.0), yc - hh * 0.12, zn + L * 0.74), 1.3, 0.12)
			"pods":
				for sx: float in [-1.0, 1.0]:
					for px: float in [hw + 1.1, hw + 1.8]:
						det._cyl(S_TRIM, Vector3(sx * px, yc - hh * 0.5, zn + L * 0.7), 0.22, 1.7, 2, 8)
			"chin":
				det._cyl(S_TRIM, Vector3(0.0, bot + 0.05, zn + L * 0.1), 0.3, 0.4, 1, 10)
				det._cyl(S_CHROME, Vector3(0.0, bot - 0.05, zn - 0.5), 0.06, 1.4, 2, 6)
			"bays":
				for sx: float in [-1.0, 1.0]:
					_quad_panel(S_BODY, Vector3(sx * hw * 0.8, yc - hh * 0.3, zn + L * 0.55), Vector3(sx * (hw + 1.2), yc - hh * 0.35, zn + L * 0.7), Vector3(sx * (hw + 1.2), yc - hh * 0.35, zn + L * 0.85), Vector3(sx * hw * 0.8, yc - hh * 0.3, zn + L * 0.95), Vector3(0.0, yc + 1.0, zn + L * 0.75))
			"steps":
				for sx: float in [-1.0, 1.0]:
					det._box(S_TRIM, Vector3(sx * (hw + 0.1), bot + 0.25, zn + L * 0.5), Vector3(0.3, 0.06, 1.6))
			"ramp":
				_prism(S_TRIM, [Vector2(zr - L * 0.12, bot + 0.1), Vector2(zr + 0.2, bot + hh * 0.5), Vector2(zr + 0.2, bot + hh * 0.8), Vector2(zr - L * 0.12, bot + 0.5)], -hw * 0.75, hw * 0.75)
			"sponson":
				for sx: float in [-1.0, 1.0]:
					_box(S_BODY, Vector3(sx * (hw + 0.3), bot + 0.6, zn + L * 0.62), Vector3(0.8, 0.9, L * 0.3))
			"engines":
				for sx: float in [-1.0, 1.0]:
					_cyl(S_TRIM, Vector3(sx * hw * 0.55, yc + hh + 0.35, zn + L * 0.55), 0.55, L * 0.32, 2, 10)
					det._cyl(S_CHROME, Vector3(sx * hw * 0.55, yc + hh + 0.35, zn + L * 0.72), 0.36, 0.2, 2, 8)
			"hook":
				det._slab(S_CHROME, Vector3(0.0, bot + 0.4, zn + L * 1.6), Vector3(0.0, 1.1, zn + L * 1.6), 0.06, 0.06)
				det._box(S_TRIM, Vector3(0.0, 0.95, zn + L * 1.6), Vector3(0.5, 0.3, 0.3))
			"tank":
				det._box(S_TRIM, Vector3(0.0, bot + 0.05, zn + L * 0.55), Vector3(hw * 1.5, 0.35, L * 0.42))
				det._slab(S_TRIM, Vector3(0.0, bot - 0.05, zn + L * 0.4), Vector3(0.0, 0.25, zn + L * 0.2), 0.14, 0.14)       # the snorkel hose
				glow._box(S_BODY, Vector3(0.0, bot - 0.13, zn + L * 0.55), Vector3(hw * 1.52, 0.03, L * 0.1))
			"engine_open":
				det._cyl(S_CHROME, Vector3(0.0, yc + hh * 0.3, zr + 0.3), 0.32, 0.9, 2, 8)
			"sonar":
				det._cyl(S_TRIM, Vector3(0.0, bot + 0.05, zr - L * 0.3), 0.36, 0.5, 1, 10)
			"glow":
				for sx: float in [-1.0, 1.0]:
					glow._box(S_BODY, Vector3(sx * hw * 0.99, yc, zn + L * 0.5), Vector3(0.03, 0.06, L * 0.8))
				glow._box(S_BODY, Vector3(0.0, bot + 0.02, zn + L * 0.5), Vector3(hw * 1.2, 0.03, 0.18))
			"doorgun":
				det._cyl(S_CHROME, Vector3(-hw - 0.25, yc + hh * 0.1, zn + L * 0.45), 0.06, 1.0, 2, 6)
	return out
