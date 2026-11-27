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
const LOD_AT := 42.0                         ## m: w128-airlook, the full body (windows, seams, smooth skin) to this distance, the far body (Body_LOD1) beyond (VehicleVisual.LOD1_DIST)

static var _cache := {}
## w128-airlook: the believable build (smooth skin, framed windscreen, engine deck, swept fin with the tail rotor on its side at the BACK, real skids). W128_OLD=1 = the wave 125 build
## (tests/test_airlook_w128.gd fails on it).
static var old := OS.get_environment("W128_OLD") == "1"


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
		elif part["name"] == "Body" and c["parts"].size() > 1 and c["parts"][1]["name"] == "Body_LOD1":
			mi.visibility_range_end = LOD_AT
			mi.visibility_range_end_margin = 3.0
		elif part["name"] == "Body_LOD1":
			mi.visibility_range_begin = LOD_AT
			mi.visibility_range_begin_margin = 3.0
		elif part["name"] == "Glow":
			mi.visibility_range_end = GLOW_FAR
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


static func tri_count(kind: StringName, part_name := "") -> int:
	if not _cache.has(kind):
		return 0
	var n := 0
	for part: Dictionary in _cache[kind]["parts"]:
		if (part_name == "" and part["name"] == "Body_LOD1") or (part_name != "" and part["name"] != part_name):
			continue                                                            # the near look: the far body is never drawn with it
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


## w128-airlook: real proportions where the wave 125 table was off (the ultralight's boom put its tail rotor inside the main disc; same length as its spec).
const W128_FIX := {
	&"h_ultra": {"boom": [4.1, 1.35, 0.07]},
}


## w128-airlook: the classic helicopter ("heli", the first one the hero finds at the airport and on the pads) in the roster build: a light single-turbine utility type (glass nose,
## two-blade rotor, skids). Its old art model was an open frame with no glass.
const CLASSIC := {
	&"heli": {"cab": [-3.6, 1.3, 0.86, 0.9, 1.62], "n": 2.4, "nose": "glass", "boom": [7.0, 2.05, 0.2], "rotor": [3.05, -0.55, 2, 0.32], "gear": "skids", "x": ["steps"]},
}


static func has_classic(kind: StringName) -> bool:
	return not old and CLASSIC.has(kind)


## The model parameters of a kind (HeliRoster.DEFS m with the w128 corrections).
static func params(kind: StringName) -> Dictionary:
	if CLASSIC.has(kind):
		return CLASSIC[kind]
	var P: Dictionary = HeliRoster.DEFS[kind]["m"]
	if old or not W128_FIX.has(kind):
		return P
	var q := P.duplicate()
	q.merge(W128_FIX[kind], true)
	return q


static func _make(kind: StringName, spec: Dictionary) -> Dictionary:
	var P: Dictionary = params(kind)
	var body := HeliModels.new()
	var det := HeliModels.new()
	var glow := HeliModels.new()
	var parts: Array[Dictionary] = []
	var rr := float(spec.get("rotor_r", 5.0))
	var g := body._geom(P, det, glow, rr) if old else body._geom2(P, det, glow, rr, kind)
	parts.append({"name": "Body", "mesh": body._finish(), "pos": Vector3.ZERO})
	if not old:                                                                     # w128-airlook: the far body (LOD1, fewer segments, no windows / seams) beyond LOD_AT m
		var b1 := HeliModels.new()
		b1._geom2(P, HeliModels.new(), HeliModels.new(), rr, kind, 1)
		parts.append({"name": "Body_LOD1", "mesh": b1._finish(), "pos": Vector3.ZERO})
	parts.append({"name": "Detail", "mesh": det._finish(), "pos": Vector3.ZERO})
	if not glow._v[S_BODY].is_empty():
		var gm := glow._finish()
		gm.surface_set_material(0, _glow_material(Color(P.get("mark", Color(1.0, 0.2, 0.2)))))
		parts.append({"name": "Glow", "mesh": gm, "pos": Vector3.ZERO})
	var blades := int(P["rotor"][2])
	var chord := float(P["rotor"][3])
	var r1 := _rotor_node("Rotor", g["hub"], rr, blades, chord) if old else _rotor2("Rotor", g["hub"], rr, blades, chord)
	parts.append({"name": "Rotor", "mesh": r1.mesh, "pos": r1.position})
	r1.free()
	if g.has("hub2"):
		var r2 := _rotor_node("Rotor2", g["hub2"], rr, blades, chord) if old else _rotor2("Rotor2", g["hub2"], rr, blades, chord)
		parts.append({"name": "Rotor2", "mesh": r2.mesh, "pos": r2.position})
		r2.free()
	if g.has("tail"):
		var t := _tail_node(g["tail"], g["tail_r"]) if old else _tail2(g["tail"], g["tail_r"], int(g.get("tail_n", 2)))
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


# --- w128-airlook: the believable build ---------------------------------------------------------------------------------------------------
## Real layout of a helicopter, from the kind's parameters: a smooth pod (flat belly, the cabin roof rising into the engine deck), a framed windscreen with chin and door windows
## (no black shell over the whole nose), the engine cowling with intakes and exhausts on the roof behind the mast, a short mast with a hub, a tapered tail boom, a swept fin at the
## END of the boom with the tail rotor on its left side (or a fenestron in the fin, or no tail rotor for coaxial / tandem / tilt-rotor craft), the stabiliser ahead of the fin,
## a tail bumper, skids with upturned toes and bowed cross tubes or wheels with struts. The same parameters (HeliRoster.DEFS m) drive it, so every kind keeps its size and its
## seat / rotor numbers.

const W128_FIN := {
	## per kind: fin chord share, fin sweep, stabiliser on the boom (share of the boom from the cabin, 1 = at the fin), tail rotor blades
	&"h_scout": [1.0, 0.55, 0.85, 2], &"h_trainer": [0.9, 0.5, 0.9, 2], &"h_ultra": [0.8, 0.45, 0.9, 2], &"h_news": [1.0, 0.55, 0.78, 2], &"h_police": [1.0, 0.55, 0.78, 2],
	&"h_utility": [1.1, 0.6, 0.95, 4], &"h_heavy": [1.2, 0.5, 0.8, 5], &"h_attack": [1.0, 0.55, 0.95, 4], &"h_fire": [1.1, 0.6, 0.95, 4], &"h_naval": [1.1, 0.6, 0.95, 4],
	&"h_gull": [1.1, 0.55, 0.9, 4], &"h_crane": [1.1, 0.55, 0.85, 4],
}


## The fuselage stations of the pod: [z, cx, cy, rx, ry] from the nose to the boom root.
static func pod_stations(P: Dictionary) -> Array:
	var cab: Array = P["cab"]
	var zn := float(cab[0])
	var zr := float(cab[1])
	var hw := float(cab[2])
	var hh := float(cab[3])
	var yc := float(cab[4])
	var L := zr - zn
	var nose := String(P.get("nose", "glass"))
	var st: Array = []
	match nose:
		"point", "facet":
			st.append([zn, 0.0, yc - hh * 0.32, hw * 0.12, hh * 0.14])
			st.append([zn + L * 0.07, 0.0, yc - hh * 0.26, hw * 0.42, hh * 0.42])
			st.append([zn + L * 0.15, 0.0, yc - hh * 0.12, hw * 0.78, hh * 0.78])
			st.append([zn + L * 0.26, 0.0, yc - hh * 0.02, hw * 0.97, hh * 0.98])
		"tandem":
			st.append([zn, 0.0, yc - hh * 0.3, hw * 0.16, hh * 0.16])
			st.append([zn + L * 0.08, 0.0, yc - hh * 0.22, hw * 0.55, hh * 0.5])
			st.append([zn + L * 0.18, 0.0, yc - hh * 0.1, hw * 0.85, hh * 0.78])
			st.append([zn + L * 0.32, 0.0, yc, hw, hh * 0.95])
		"bubble":
			st.append([zn, 0.0, yc - hh * 0.08, hw * 0.3, hh * 0.36])
			st.append([zn + L * 0.06, 0.0, yc - hh * 0.03, hw * 0.72, hh * 0.78])
			st.append([zn + L * 0.16, 0.0, yc, hw * 0.93, hh * 0.96])
			st.append([zn + L * 0.32, 0.0, yc, hw, hh])
		_:
			st.append([zn, 0.0, yc - hh * 0.3, hw * 0.28, hh * 0.3])
			st.append([zn + L * 0.06, 0.0, yc - hh * 0.18, hw * 0.7, hh * 0.68])
			st.append([zn + L * 0.15, 0.0, yc - hh * 0.06, hw * 0.92, hh * 0.92])
			st.append([zn + L * 0.3, 0.0, yc, hw, hh])
	if nose == "bubble":
		st.append([zr - L * 0.22, 0.0, yc + hh * 0.04, hw * 0.92, hh * 0.94])
		st.append([zr, 0.0, yc + hh * 0.32, hw * 0.5, hh * 0.52])
	else:
		st.append([zr - L * 0.14, 0.0, yc + hh * 0.03, hw, hh * 0.98])
		st.append([zr, 0.0, yc + hh * 0.26, hw * 0.68, hh * 0.68])
	return st


func _geom2(P: Dictionary, det: HeliModels, glow: HeliModels, rr: float, kind: StringName, lod := 0) -> Dictionary:
	smooth = true
	det.smooth = true
	var cab: Array = P["cab"]
	var zn := float(cab[0])
	var zr := float(cab[1])
	var hw := float(cab[2])
	var hh := float(cab[3])
	var yc := float(cab[4])
	var L := zr - zn
	var n := clampf(float(P.get("n", 2.4)), 2.0, 4.0)
	var nose := String(P.get("nose", "glass"))
	var x: Array = P.get("x", [])
	var lay := String(P.get("lay", "single"))
	var tail := String(P.get("tail", "rotor"))
	var segs := 18 if lod == 0 else 10
	var fin_p: Array = W128_FIN.get(kind, [1.0, 0.55, 0.85, 3 if rr > 5.0 else 2])
	var out := {}
	var bot := yc - hh
	var top := yc + hh
	# --- the pod and the boom
	var st := pod_stations(P)
	var boom: Array = P.get("boom", [])
	var truss := x.has("truss") or x.has("spine")
	var bz := 0.0
	var by := 0.0
	var br := 0.0
	var body_st := st.duplicate()
	if not boom.is_empty():
		bz = float(boom[0])
		by = float(boom[1])
		br = float(boom[2])
		if not truss:
			var s_last: Array = st[st.size() - 1]
			var y0 := float(s_last[2])
			body_st.append([lerpf(zr, bz, 0.2), 0.0, lerpf(y0, by, 0.25), maxf(br * 1.9, float(s_last[3]) * 0.55), maxf(br * 2.0, float(s_last[4]) * 0.55)])
			body_st.append([lerpf(zr, bz, 0.6), 0.0, lerpf(y0, by, 0.65), br * 1.35, br * 1.45])
			body_st.append([bz + 0.2, 0.0, by, br * 0.9, br])
	_loft(S_BODY, body_st, n, segs)
	# --- the glass: a framed windscreen over the upper front, chin windows, door windows; the roof and the chin stay paint
	var s0: Array = st[0]
	var s1: Array = st[1]
	var s2: Array = st[2]
	var s3: Array = st[3]
	var gs := 8 if lod == 0 else 4
	var front := [_mix(s0, s1, 0.35), s1, s2, _mix(s2, s3, 0.45)]
	match nose:
		"bubble":
			_patch(S_GLASS, [_mix(s0, s1, 0.15), s1, s2, _mix(s2, s3, 0.6)], n, -0.75, PI + 0.75, gs * 2, 1.012)
		"tandem":
			var cz := zn + L * 0.2
			for i in 2:
				var z0 := cz + float(i) * L * 0.17
				var yb := yc + hh * (0.55 + 0.18 * float(i))
				_patch(S_GLASS, [[z0 - L * 0.02, 0.0, yb, hw * 0.3, hh * 0.12], [z0 + L * 0.04, 0.0, yb + hh * 0.22, hw * 0.78, hh * 0.38], [z0 + L * 0.13, 0.0, yb + hh * 0.2, hw * 0.74, hh * 0.34], [z0 + L * 0.16, 0.0, yb + hh * 0.05, hw * 0.4, hh * 0.15]], 2.6, -0.1, PI + 0.1, 10 if lod == 0 else 6, 1.0)
				if lod == 0:
					det._slab(S_TRIM, Vector3(0.0, yb + hh * 0.58, z0 + L * 0.02), Vector3(0.0, yb + hh * 0.55, z0 + L * 0.14), 0.07, 0.05)
		"point", "facet":
			_patch(S_GLASS, [_mix(s1, s2, 0.2), s2, _mix(s2, s3, 0.7)], n, -0.05, PI + 0.05, gs * 2, 1.012)
		_:
			_patch(S_GLASS, front, n, -0.22, PI + 0.22, gs * 2, 1.012)
			if lod == 0:                                                                  # chin windows by the pedals
				for side in [[-0.95, -0.45], [PI + 0.45, PI + 0.95]]:
					_patch(S_GLASS, [_mix(s0, s1, 0.5), s1, _mix(s1, s2, 0.6)], n, float(side[0]), float(side[1]), 3, 1.012)
	if lod == 0 and nose != "tandem":
		var gz0 := float(front[0][0])
		var gz1 := float(front[front.size() - 1][0])
		if nose == "point" or nose == "facet":
			gz0 = float(_mix(s1, s2, 0.2)[0])
		# the frames: the centre post over the top and the corner posts between the windscreen and the doors
		_patch(S_TRIM, front if nose != "point" and nose != "facet" else [_mix(s1, s2, 0.2), s2, _mix(s2, s3, 0.7)], n, PI * 0.5 - 0.035, PI * 0.5 + 0.035, 1, 1.02)
		var zp := gz1
		var sp := _at(st, zp)
		var sq := _at(st, zp + 0.07)
		for side in [[-0.3, 1.25], [PI - 1.25, PI + 0.3]]:
			_patch(S_TRIM, [sp, sq], n, float(side[0]), float(side[1]), 6, 1.02)
		# the door windows (front doors) and the cabin windows behind them, flush with the skin
		var dz0 := zp + 0.12
		var dl := clampf(L * 0.2, 0.7, 1.6)
		var win: Array = [[dz0, dz0 + dl]]
		var nw := clampi(int((L * 0.62 - dl) / 1.5), 0, 4) if L > 4.6 else 0
		for i in nw:
			var wz := dz0 + dl + 0.35 + float(i) * 1.5
			win.append([wz, wz + 1.0])
		for wv: Array in win:
			var za := float(wv[0])
			var zb := float(wv[1])
			if zb > zr - L * 0.1:
				continue
			for side in [[0.12, 0.95], [PI - 0.95, PI - 0.12]]:
				_patch(S_GLASS, [_at(st, za), _at(st, (za + zb) * 0.5), _at(st, zb)], n, float(side[0]), float(side[1]), 4, 1.012)
		# the door seams: a dark line round each cabin door (front edge, rear edge), a handle
		for zs: float in [dz0 - 0.06, dz0 + dl + 0.12]:
			if zs < zr - L * 0.1:
				for side in [[-0.85, 1.0], [PI - 1.0, PI + 0.85]]:
					_patch(S_TRIM, [_at(st, zs), _at(st, zs + 0.035)], n, float(side[0]), float(side[1]), 6, 1.006)
		for sx: float in [-1.0, 1.0]:
			var hs := _at(st, dz0 + dl * 0.8)
			det._box(S_CHROME, Vector3(sx * float(hs[3]) * 1.01, float(hs[2]) - hh * 0.05, dz0 + dl * 0.8), Vector3(0.04, 0.05, 0.2))
	# --- the tail
	if not boom.is_empty():
		if truss:
			var a := Vector3(0.0, yc + hh * 0.4, zr - 0.2)
			var b := Vector3(0.0, by, bz)
			if x.has("spine"):
				_slab(S_BODY, a + Vector3(0.0, 0.0, zn - zr + L * 0.5), b, br * 2.4, br * 2.0)
				_slab(S_BODY, Vector3(0.0, yc + hh * 0.9, zr), Vector3(0.0, by + 0.6, zr + (bz - zr) * 0.35), 1.4, 0.9)
			else:
				for sx: float in [-1.0, 1.0]:
					_slab(S_TRIM, a + Vector3(sx * 0.32, 0.25, 0.0), b + Vector3(sx * 0.06, 0.1, 0.0), br, br)
				_slab(S_TRIM, a + Vector3(0.0, -0.3, 0.0), b - Vector3(0.0, 0.1, 0.0), br, br)
		var fh := float(P.get("fin", 0.7 + rr * 0.15))
		var rot0: Array = P["rotor"]
		if bz - float(rot0[1]) < rr + 0.6:                                         # a fin under the main disc stays clear of the blades' sweep
			fh = minf(fh, float(rot0[0]) - 0.5 - by)
		var fc := clampf(fh * 0.78 * float(fin_p[0]), 0.7, 3.4)
		var sweep := fc * float(fin_p[1])
		var fth := clampf(fc * 0.16, 0.1, 0.4)
		# the fin: from the END of the boom up and back (its trailing edge is the last part of the craft); a small ventral fin under it
		var rle := Vector3(0.0, by - br * 0.2, bz - fc)
		var rte := Vector3(0.0, by - br * 0.2, bz + 0.15)
		var tle := Vector3(0.0, by + fh, bz - fc * 0.45 + sweep)
		var tte := Vector3(0.0, by + fh, bz + 0.15 + sweep * 0.55)
		if tail == "fen":
			var fr := maxf(rr * 0.15, 0.55)
			var fcz := bz - fc * 0.35
			var fcy := by + fr * 0.55
			_panel(S_BODY, Vector3(0.0, by - fr * 0.9, fcz - fr * 1.6), Vector3(0.0, by - fr * 0.9, bz + 0.35), Vector3(0.0, fcy + fh * 0.95, fcz + sweep * 0.6), Vector3(0.0, fcy + fh * 0.95, bz + 0.35 + sweep * 0.55), fr * 0.75, fth, Vector3.RIGHT)
			_cyl(S_BODY, Vector3(0.0, fcy, fcz), fr * 1.18, fr * 0.78, 0, 16 if lod == 0 else 10)            # the shroud
			for sx: float in [-1.0, 1.0]:
				_cyl(S_TRIM, Vector3(sx * fr * 0.392, fcy, fcz), fr * 0.92, 0.02, 0, 16 if lod == 0 else 10)   # the dark duct faces
			if lod == 0:
				for i in 8:
					var a2 := TAU * float(i) / 8.0
					det._slab(S_TRIM, Vector3(0.0, fcy, fcz), Vector3(0.0, fcy + sin(a2) * fr * 0.85, fcz + cos(a2) * fr * 0.85), 0.16, 0.03, Vector3.RIGHT)
			out["fen"] = Vector3(0.0, fcy, fcz)
		else:
			_panel(S_BODY, rle, rte, tle, tte, fth, fth * 0.6, Vector3.RIGHT)
			if tail == "rotor" and (String(P.get("gear", "")) != "skids" or x.has("ventral")):
				_panel(S_BODY, Vector3(0.0, by - br * 0.5, bz - fc * 0.6), Vector3(0.0, by - br * 0.5, bz + 0.1), Vector3(0.0, by - br - fh * 0.3, bz - fc * 0.15 + sweep * 0.3), Vector3(0.0, by - br - fh * 0.3, bz + 0.1 + sweep * 0.2), fth, fth * 0.5, Vector3.RIGHT)
		# the horizontal stabiliser on the boom, ahead of the fin (a pair of end plates where the kind has them)
		var sspan := clampf(0.8 + rr * 0.13, 0.9, 2.6)
		var sc := clampf(fc * 0.55, 0.45, 1.6)
		var sz := lerpf(zr, bz - fc, float(fin_p[2])) if tail != "fen" else bz - fc * 0.2
		var sy := by - (bz - sz) * (by - (yc + hh * 0.3)) / maxf(bz - zr, 0.1) * 0.6
		if x.has("fins2") or tail == "none":
			sz = bz - fc * 0.5
			sy = by + br * 0.3
		for sx: float in [-1.0, 1.0]:
			_panel(S_BODY, Vector3(sx * br * 0.8, sy, sz - sc * 0.5), Vector3(sx * br * 0.8, sy, sz + sc * 0.5), Vector3(sx * sspan, sy + 0.05, sz - sc * 0.25), Vector3(sx * sspan, sy + 0.05, sz + sc * 0.45), clampf(sc * 0.14, 0.06, 0.2), 0.06, Vector3.UP)
			if x.has("fins2") or tail == "fen":
				var ph := fh * (0.75 if x.has("fins2") else 0.45)
				_panel(S_BODY, Vector3(sx * sspan, sy - ph * 0.3, sz - sc * 0.35), Vector3(sx * sspan, sy - ph * 0.3, sz + sc * 0.5), Vector3(sx * sspan, sy + ph * 0.7, sz - sc * 0.05), Vector3(sx * sspan, sy + ph * 0.7, sz + sc * 0.6), 0.08, 0.05, Vector3.RIGHT)
		# the tail rotor: on the LEFT side of the fin, high on it, behind the main rotor disc
		var tr := clampf(rr * 0.17, 0.6, 2.2)
		if tail == "rotor":
			var tz := bz - fc * 0.42 + sweep * 0.45
			var ty := maxf(by + fh * 0.55, tr + 0.45)
			out["tail"] = Vector3(-(fth * 0.5 + 0.22), ty, tz)
			out["tail_r"] = tr
			out["tail_n"] = int(fin_p[3])
			det._cyl(S_TRIM, Vector3(-(fth * 0.5 + 0.1), ty, tz), 0.12, 0.22, 0, 8)        # the gearbox stub
			det._slab(S_TRIM, Vector3(0.0, by + br * 0.6, zr + (bz - zr) * 0.2), Vector3(0.0, by + br * 0.9, bz - fc * 0.6), 0.1, 0.08)     # the drive shaft cover
		# the tail bumper under the boom (skid helicopters) keeps the fin off the ground
		if String(P.get("gear", "skids")) == "skids" and lod == 0:
			det._slab(S_CHROME, Vector3(0.0, by - br * 0.8, bz - fc * 0.9), Vector3(0.0, maxf(by - br - 0.6, 0.35), bz - fc * 0.6), 0.05, 0.05, Vector3.RIGHT)
			det._slab(S_CHROME, Vector3(0.0, maxf(by - br - 0.6, 0.35), bz - fc * 0.6), Vector3(0.0, by - br * 0.6, bz - fc * 0.2), 0.05, 0.05, Vector3.RIGHT)
	# --- the engine deck: the cowling on the roof behind the windscreen, intakes at its front, exhausts at its back, the mast and hub on top
	var rot: Array = P["rotor"]
	var ry := float(rot[0])
	var rz := float(rot[1])
	var eh := clampf(hh * 0.34, 0.22, 0.75)
	eh = maxf(minf(eh, (ry - 0.35 - top) / 1.07), 0.1)                          # the deck stays under the hub with room for the blades
	var ew := clampf(hw * 0.62, 0.3, 1.4)
	var ez0 := maxf(rz - L * 0.2, zn + L * 0.3)
	var ez1 := minf(rz + L * 0.34, zr + L * 0.06)
	var mast_base := top + eh * 0.9
	if lay == "single" or lay == "coax":
		if not truss or x.has("spine"):
			_loft(S_BODY, [[ez0, 0.0, top - eh * 0.2, ew * 0.4, eh * 0.3], [ez0 + (ez1 - ez0) * 0.15, 0.0, top + eh * 0.4, ew * 0.92, eh * 0.6], [ez0 + (ez1 - ez0) * 0.7, 0.0, top + eh * 0.45, ew, eh * 0.62],
				[ez1, 0.0, top + eh * 0.15, ew * 0.55, eh * 0.4]], 2.8, 12 if lod == 0 else 8)
			if lod == 0:
				for sx: float in [-1.0, 1.0]:
					det._box(S_TRIM, Vector3(sx * ew * 0.9, top + eh * 0.45, ez0 + (ez1 - ez0) * 0.22), Vector3(0.05, eh * 0.55, (ez1 - ez0) * 0.14))            # intake grille
					var ex := Vector3(sx * ew * 0.55, top + eh * 0.55, ez1 - (ez1 - ez0) * 0.08)
					det._cone_y(S_TRIM, ex, ex + Vector3(sx * 0.25, 0.08, 0.5), clampf(eh * 0.38, 0.1, 0.3), 8)            # exhaust stacks, angled out and back
					det._slab(S_TRIM, Vector3(sx * ew * 0.98, top + eh * 0.2, ez0 + (ez1 - ez0) * 0.45), Vector3(sx * ew * 0.98, top + eh * 0.2, ez0 + (ez1 - ez0) * 0.75), 0.03, 0.02)   # cowling seam
		else:
			_cyl(S_TRIM, Vector3(0.0, top + 0.08, rz + 0.3), hw * 0.55, 0.2, 1, 8)
	if x.has("engines"):
		for sx: float in [-1.0, 1.0]:
			_loft(S_BODY, [[ez0 - 0.4, sx * ew * 0.95, top + eh * 0.55, 0.3, 0.3], [ez0, sx * ew * 0.95, top + eh * 0.6, 0.62, 0.58], [ez1 - 0.2, sx * ew * 0.95, top + eh * 0.6, 0.6, 0.56], [ez1 + 0.6, sx * ew * 0.95, top + eh * 0.55, 0.38, 0.36]], 2.0, 12 if lod == 0 else 8)
			_cyl(S_TRIM, Vector3(sx * ew * 0.95, top + eh * 0.55, ez0 - 0.41), 0.26, 0.04, 2, 10)
	# --- the masts and hubs
	match lay:
		"tandem":
			var z1 := zn + L * 0.12
			var z2 := zr - L * 0.06
			var y2 := ry + 1.1
			# the front pylon over the cockpit (a hump) and the tall rear pylon at the tail (a tapered fairing, the CH-style back end)
			_loft(S_BODY, [[zn + L * 0.02, 0.0, top - hh * 0.1, hw * 0.3, hh * 0.15], [z1 - L * 0.04, 0.0, top + 0.15, hw * 0.6, 0.45], [z1 + L * 0.08, 0.0, top + 0.1, hw * 0.55, 0.4], [z1 + L * 0.16, 0.0, top - 0.05, hw * 0.3, 0.2]], 2.6, 12 if lod == 0 else 8)
			_loft(S_BODY, [[zr - L * 0.36, 0.0, top - 0.05, hw * 0.4, 0.2], [zr - L * 0.18, 0.0, top + (y2 - top) * 0.3, hw * 0.55, (y2 - top) * 0.32], [z2 - 0.4, 0.0, top + (y2 - top) * 0.45, hw * 0.5, (y2 - top) * 0.5],
				[zr + 0.3, 0.0, top + (y2 - top) * 0.45, hw * 0.3, (y2 - top) * 0.42]], 3.0, 12 if lod == 0 else 8)
			_cyl(S_TRIM, Vector3(0.0, (top + 0.4 + ry) * 0.5, z1), 0.3, maxf(ry - top - 0.3, 0.2), 1, 8)
			_cyl(S_TRIM, Vector3(0.0, y2 - 0.35, z2), 0.32, 0.6, 1, 8)
			out["hub"] = Vector3(0.0, ry, z1)
			out["hub2"] = Vector3(0.0, y2, z2)
		"coax":
			_cyl(S_TRIM, Vector3(0.0, (mast_base + ry + 0.9) * 0.5, rz), 0.2, ry + 0.9 - mast_base + 0.1, 1, 10)
			_cyl(S_TRIM, Vector3(0.0, ry + 0.45, rz), 0.34, 0.4, 1, 10)
			out["hub"] = Vector3(0.0, ry, rz)
			out["hub2"] = Vector3(0.0, ry + 0.9, rz)
		"tilt":
			var wy := top + 0.12
			var span2 := float(P.get("span", 6.4))
			var wc := 2.2
			# the high wing on a fairing over the cabin, a nacelle at each tip standing up (helicopter mode), the prop-rotor on top
			_loft(S_BODY, [[rz - wc * 0.9, 0.0, top - 0.1, hw * 0.4, 0.2], [rz - wc * 0.5, 0.0, wy, hw * 0.55, 0.3], [rz + wc * 0.7, 0.0, wy, hw * 0.55, 0.3], [rz + wc * 1.2, 0.0, top - 0.1, hw * 0.3, 0.15]], 2.4, 10)
			_wings_h(S_BODY, Vector3(0.0, wy + 0.1, rz - wc * 0.5), span2, wc, 0.32)
			for sx: float in [-1.0, 1.0]:
				_loft(S_BODY, [[rz - 0.7, sx * span2, wy - 0.35, 0.35, 0.35], [rz - 0.45, sx * span2, wy + 0.1, 0.6, 0.6], [rz + 0.6, sx * span2, wy + 0.1, 0.62, 0.62], [rz + 0.9, sx * span2, wy - 0.1, 0.4, 0.4]], 2.0, 12 if lod == 0 else 8)
				_cone_y(S_BODY, Vector3(sx * span2, wy + 0.2, rz), Vector3(sx * span2, ry - 0.35, rz), 0.6, 12 if lod == 0 else 8, 0.42)
				det._cone_y(S_CHROME, Vector3(sx * span2, ry - 0.3, rz), Vector3(sx * span2, ry + 0.4, rz), 0.36, 8)
			out["hub"] = Vector3(-span2, ry, rz)
			out["hub2"] = Vector3(span2, ry, rz)
		_:
			var mh := maxf(ry - mast_base, 0.25)
			_cyl(S_TRIM, Vector3(0.0, mast_base + mh * 0.5, rz), clampf(rr * 0.03, 0.11, 0.3), mh + 0.1, 1, 10)
			_cyl(S_TRIM, Vector3(0.0, mast_base + 0.12, rz), clampf(rr * 0.07, 0.25, 0.7), 0.24, 1, 10)            # the swashplate
			out["hub"] = Vector3(0.0, ry, rz)
	if x.has("ring"):
		var hubs: Array = [out["hub"]]
		if out.has("hub2"):
			hubs.append(out["hub2"])
		for hb: Vector3 in hubs:
			var rs := 20
			for i in rs:
				var a0 := TAU * float(i) / float(rs)
				var a1 := TAU * float(i + 1) / float(rs)
				glow._slab(S_BODY, hb + Vector3(cos(a0), 0.0, sin(a0)) * (rr + 0.25), hb + Vector3(cos(a1), 0.0, sin(a1)) * (rr + 0.25), 0.22, 0.12)
			for i in 4:
				var a2 := TAU * (float(i) + 0.5) / 4.0
				det._slab(S_TRIM, hb + Vector3(0.0, -0.35, 0.0) + Vector3(cos(a2), 0.0, sin(a2)) * 0.4, hb + Vector3(0.0, -0.15, 0.0) + Vector3(cos(a2), 0.0, sin(a2)) * (rr + 0.25), 0.1, 0.08)
	# --- the gear
	var gear := String(P.get("gear", "skids"))
	match gear:
		"skids":
			var gx := hw * 1.02 + 0.12
			var zf := zn + L * 0.14
			var zb := zr - L * 0.02
			for sx: float in [-1.0, 1.0]:
				det._slab(S_CHROME, Vector3(sx * gx, 0.06, zf + 0.3), Vector3(sx * gx, 0.06, zb), 0.09, 0.09)
				det._slab(S_CHROME, Vector3(sx * gx, 0.06, zf + 0.32), Vector3(sx * gx, 0.34, zf - 0.12), 0.09, 0.09)          # the upturned toe
				for fz: float in [0.3, 0.74]:
					var cz2 := zn + L * fz
					var knee := Vector3(sx * (gx - 0.02), minf(bot * 0.55, 0.75), cz2)
					det._slab(S_CHROME, Vector3(sx * gx, 0.06, cz2), knee, 0.08, 0.08)
					det._slab(S_CHROME, knee, Vector3(sx * hw * 0.55, bot + 0.08, cz2), 0.08, 0.08)                        # the bowed cross tube into the belly
		"wheels":
			var nz := zn + L * 0.1
			_strut(det, Vector3(0.0, bot + 0.1, nz), 0.28)
			var mz := zr - L * 0.26
			var mx := hw + 0.25
			for sx: float in [-1.0, 1.0]:
				_strut(det, Vector3(sx * mx, bot + 0.3, mz), 0.36)
				det._slab(S_TRIM, Vector3(sx * mx, 0.55, mz), Vector3(sx * hw * 0.8, bot + 0.35, mz - 0.2), 0.14, 0.12)
		"floats":
			for sx: float in [-1.0, 1.0]:
				_loft(S_BODY, [[zn + L * 0.02, sx * (hw + 0.35), 0.42, 0.1, 0.1], [zn + L * 0.12, sx * (hw + 0.35), 0.38, 0.34, 0.32], [zr - L * 0.1, sx * (hw + 0.35), 0.36, 0.34, 0.3], [zr + 0.2, sx * (hw + 0.35), 0.4, 0.12, 0.12]], 2.0, 10)
				for fz: float in [0.28, 0.72]:
					det._slab(S_TRIM, Vector3(sx * (hw + 0.35), 0.6, zn + L * fz), Vector3(sx * hw * 0.7, bot + 0.2, zn + L * fz), 0.12, 0.1)
		"legs":
			for sx: float in [-1.0, 1.0]:
				for fz: float in [0.15, 0.85]:
					var foot := Vector3(sx * (hw + 0.9), 0.06, zn + L * fz)
					det._slab(S_TRIM, foot + Vector3(0.0, 0.05, 0.0), Vector3(sx * hw * 0.7, bot + 0.3, zn + L * fz), 0.16, 0.16)
					det._cyl(S_TRIM, foot, 0.32, 0.1, 1, 8)
	# --- the extras (the same as the wave 125 build: role kit)
	_extras(P, det, glow, x, zn, zr, hw, hh, yc, L, bot)
	out["deck_top"] = top + eh * 0.85
	return out


## The role kit of the kind (cameras, searchlights, winches, weapons, tanks...): the same pieces as the wave 125 build.
func _extras(P: Dictionary, det: HeliModels, glow: HeliModels, x: Array, zn: float, zr: float, hw: float, hh: float, yc: float, L: float, bot: float) -> void:
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
					glow._box(S_BODY, Vector3(sx * hw * 1.0, yc - hh * 0.25, zn + L * 0.55), Vector3(0.03, 0.08, L * 0.5))
			"cross":
				for sx: float in [-1.0, 1.0]:
					var cc := Vector3(sx * hw * 1.0, yc + hh * 0.05, zr - L * 0.3)
					glow._box(S_BODY, cc, Vector3(0.04, 0.24, 0.8))
					glow._box(S_BODY, cc, Vector3(0.04, 0.8, 0.24))
			"stripe":
				for sx: float in [-1.0, 1.0]:
					glow._box(S_BODY, Vector3(sx * hw * 0.99, yc - hh * 0.35, zn + L * 0.5), Vector3(0.03, 0.07, L * 0.75))
			"winch":
				det._box(S_TRIM, Vector3(hw * 1.05, yc + hh * 0.8, zn + L * 0.5), Vector3(0.5, 0.3, 0.5))
				det._slab(S_CHROME, Vector3(hw * 0.9, yc + hh * 0.8, zn + L * 0.5), Vector3(hw * 1.5, yc + hh * 0.8, zn + L * 0.5), 0.1, 0.1)
			"wings":
				for sx: float in [-1.0, 1.0]:
					_panel(S_BODY, Vector3(sx * hw * 0.85, yc - hh * 0.15, zn + L * 0.62), Vector3(sx * hw * 0.85, yc - hh * 0.15, zn + L * 0.8), Vector3(sx * (hw + 1.9), yc - hh * 0.25, zn + L * 0.66), Vector3(sx * (hw + 1.9), yc - hh * 0.25, zn + L * 0.78), 0.16, 0.1, Vector3.UP)
			"pods":
				for sx: float in [-1.0, 1.0]:
					for px: float in [hw + 0.9, hw + 1.7]:
						det._cyl(S_TRIM, Vector3(sx * px, yc - hh * 0.5, zn + L * 0.7), 0.22, 1.7, 2, 8)
						det._slab(S_TRIM, Vector3(sx * px, yc - hh * 0.5 + 0.2, zn + L * 0.7), Vector3(sx * px, yc - hh * 0.22, zn + L * 0.71), 0.3, 0.06, Vector3.RIGHT)
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
					_loft(S_BODY, [[zn + L * 0.45, sx * (hw + 0.1), bot + 0.6, 0.3, 0.3], [zn + L * 0.5, sx * (hw + 0.1), bot + 0.6, 0.55, 0.5], [zn + L * 0.75, sx * (hw + 0.1), bot + 0.6, 0.55, 0.5], [zn + L * 0.8, sx * (hw + 0.1), bot + 0.6, 0.3, 0.3]], 2.6, 10)
			"hook":
				det._slab(S_CHROME, Vector3(0.0, bot + 0.4, zn + L * 1.6), Vector3(0.0, 1.1, zn + L * 1.6), 0.06, 0.06)
				det._box(S_TRIM, Vector3(0.0, 0.95, zn + L * 1.6), Vector3(0.5, 0.3, 0.3))
			"tank":
				det._box(S_TRIM, Vector3(0.0, bot + 0.05, zn + L * 0.55), Vector3(hw * 1.5, 0.35, L * 0.42))
				det._slab(S_TRIM, Vector3(0.0, bot - 0.05, zn + L * 0.4), Vector3(0.0, 0.25, zn + L * 0.2), 0.14, 0.14)
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


## A station between two stations (t 0..1).
static func _mix(a: Array, b: Array, t: float) -> Array:
	var r: Array = []
	for i in 5:
		r.append(lerpf(float(a[i]), float(b[i]), t))
	return r


## The pod's station at depth z (interpolated; clamped to the first / last station).
static func _at(st: Array, z: float) -> Array:
	if z <= float(st[0][0]):
		return st[0]
	for i in st.size() - 1:
		var a: Array = st[i]
		var b: Array = st[i + 1]
		if z <= float(b[0]):
			return _mix(a, b, (z - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001))
	var l: Array = st[st.size() - 1]
	return [z, l[1], l[2], l[3], l[4]]


## A tapered cylinder from a (radius r) to b (radius r1; 0 = a point), any direction, with smooth sides.
func _cone_y(surf: int, a: Vector3, b: Vector3, r: float, segs: int, r1 := -1.0) -> void:
	if r1 < 0.0:
		r1 = r * 0.85
	var ax := (b - a).normalized()
	var u := Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT
	var a1 := ax.cross(u).normalized()
	var a2 := ax.cross(a1).normalized()
	for i in segs:
		var t0 := TAU * float(i) / float(segs)
		var t1 := TAU * float(i + 1) / float(segs)
		var d0 := a1 * cos(t0) + a2 * sin(t0)
		var d1 := a1 * cos(t1) + a2 * sin(t1)
		_tri_n(surf, a + d0 * r, b + d0 * r1, b + d1 * r1, d0, d0, d1)
		_tri_n(surf, a + d0 * r, b + d1 * r1, a + d1 * r, d0, d1, d1)
		_tri(surf, a, a + d1 * r, a + d0 * r, b)
		if r1 > 0.0:
			_tri(surf, b, b + d0 * r1, b + d1 * r1, a)


## A straight wing through the centre (the tilt-rotor's): root leading edge at `le`, half span, chord, thickness.
func _wings_h(surf: int, le: Vector3, half: float, chord: float, th: float) -> void:
	for sx: float in [-1.0, 1.0]:
		_panel(surf, le, le + Vector3(0.0, 0.0, chord), le + Vector3(sx * half, 0.0, 0.0), le + Vector3(sx * half, 0.0, chord), th, th * 0.8, Vector3.UP)


## An oleo strut from `top` down to a wheel resting on y = 0.
static func _strut(m: HeliModels, top: Vector3, r: float) -> void:
	m._slab(S_CHROME, top, Vector3(top.x, r, top.z), 0.1, 0.1)
	m._cyl(S_TRIM, Vector3(top.x, r, top.z), r, r * 0.6, 0, 12)
	m._cyl(S_CHROME, Vector3(top.x, r, top.z), r * 0.5, r * 0.62, 0, 8)


## The main rotor: tapered blades with a slight droop, a hub with its blade grips and a cap.
static func _rotor2(nm: String, hub: Vector3, radius: float, blades: int, chord: float) -> MeshInstance3D:
	var m := HeliModels.new()
	for i in blades:
		var a := TAU * float(i) / float(blades)
		var d := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-d.z, 0.0, d.x)
		var r0 := 0.45
		m._panel(S_TRIM, d * r0 + side * chord * 0.5, d * r0 - side * chord * 0.5, d * radius + side * chord * 0.42 + Vector3(0.0, -radius * 0.012, 0.0), d * radius - side * chord * 0.42 + Vector3(0.0, -radius * 0.012, 0.0), 0.08, 0.04, Vector3.UP)
		m._slab(S_CHROME, d * 0.12, d * (r0 + 0.12), 0.16, 0.12)                             # the grip
		m._box(S_CHROME, d * (radius - 0.18) + Vector3(0.0, -radius * 0.012, 0.0), Vector3(0.06, 0.09, 0.06) + d.abs() * 0.3)        # the tip cap
	m._cyl(S_TRIM, Vector3(0.0, -0.06, 0.0), 0.3, 0.24, 1, 10)
	m._cyl(S_CHROME, Vector3(0.0, 0.12, 0.0), 0.16, 0.16, 1, 8)
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = m._finish()
	mi.position = hub
	return mi


## The tail rotor: `blades` blades in the YZ plane about its hub (it spins about X), with a hub cap.
static func _tail2(hub: Vector3, radius: float, blades: int) -> MeshInstance3D:
	var m := HeliModels.new()
	var ch := clampf(radius * 0.22, 0.14, 0.36)
	for i in blades:
		var a := TAU * float(i) / float(blades) + 0.4
		var d := Vector3(0.0, sin(a), cos(a))
		m._slab(S_TRIM, d * 0.1, d * radius, ch, 0.04, Vector3.RIGHT)
	m._cyl(S_CHROME, Vector3.ZERO, 0.13, 0.22, 0, 8)
	var mi := MeshInstance3D.new()
	mi.name = "TailRotor"
	mi.mesh = m._finish()
	mi.position = hub
	return mi
