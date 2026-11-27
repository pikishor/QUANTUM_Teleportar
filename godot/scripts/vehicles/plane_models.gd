class_name PlaneModels
extends AircraftModels
## WAVE 126 AEROPLANE ROSTER: the procedural bodies of the 28 aeroplanes of PlaneRoster (own-made, no texture, original designs). One parametric builder reads the kind's
## model parameters (PlaneRoster.DEFS[kind]["m"]) and makes the node contract of the craft models: "Body" (surfaces Body = paint / Glass / Trim / Chrome: fuselage, wings, tail,
## engine nacelles, floats), "Detail" (landing gear, struts, weapons, the small parts: hidden beyond DETAIL_FAR m), "Glow" (the emissive marks of the sci-fi craft: one draw),
## "Prop" + "PropB".."PropD" (the propellers, spin about Z; VehicleVisual adds the blur discs). Nose = -Z, the wheels rest on y = 0.
## SHARED MESHES: every mesh of a kind is built once and cached (`_cache`), so parked planes of a kind share one set of ArrayMeshes and materials.
##   build(kind, spec) -> Node3D           the model root (VehicleCraftModels.build calls it for every kind of PlaneRoster)
##   tri_count(kind) -> int                 triangles of the whole model
## Model parameters (all lengths in m; see tools/gen_plane_roster.py):
##   f [zn, zt, hw, hh, yc]  fuselage nose z, tail z, half width, half height, centre height      n  superellipse exponent (2 = round, more = boxier)
##   nose round / point / blunt / droop      cab bubble / cabin / airliner / glazed / open / slit / none
##   w [zle, hs, cr, ct, sw, dh, wy, th]  wing root leading edge z, half span, root chord, tip chord, sweep (tip LE z offset), dihedral (tip rise), root height (x hh from the axis), thickness
##   w2 [dy, dz]  the upper wing of a biplane      t conv / t / v / vcant / twin / fin / none      tp [fin height, fin chord, stabiliser half span, stabiliser chord]
##   e {type: nose / push / mast / wp (wing props) / wt (props on top of the wing) / wj (jet pods) / tj (rear fuselage pods) / int (buried jets: n nozzles), at: [share of the half span], r, l}
##   g trike / tail / heavy / mil / float / hull / skid      x extras      mark  the glow colour

const DETAIL_FAR := 70.0
const GLOW_FAR := 220.0
const PROP_NAMES: Array[String] = ["Prop", "PropB", "PropC", "PropD"]

static var _cache := {}
## w128-airlook: the believable build; W128_OLD=1 = the wave 126 build (tests/test_airlook_w128.gd fails on it).
static var old := OS.get_environment("W128_OLD") == "1"
static var _glow_mats := {}


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
			mi.visibility_range_end = HeliModels.LOD_AT
			mi.visibility_range_end_margin = 3.0
		elif part["name"] == "Body_LOD1":
			mi.visibility_range_begin = HeliModels.LOD_AT
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
	var P: Dictionary = params(kind)
	var body := PlaneModels.new()
	var det := PlaneModels.new()
	var glow := PlaneModels.new()
	var parts: Array[Dictionary] = []
	var hubs: Array = body._geom(P, det, glow, spec)
	parts.append({"name": "Body", "mesh": body._finish(), "pos": Vector3.ZERO})
	if not old:                                                                     # w128-airlook: the far body (LOD1) beyond LOD_AT m
		var b1 := PlaneModels.new()
		b1.far_lod = 1
		b1._geom(P, PlaneModels.new(), PlaneModels.new(), spec)
		parts.append({"name": "Body_LOD1", "mesh": b1._finish(), "pos": Vector3.ZERO})
	if not det._empty():
		parts.append({"name": "Detail", "mesh": det._finish(), "pos": Vector3.ZERO})
	if not glow._empty():
		var gm := glow._finish()
		gm.surface_set_material(0, _glow_material(Color(P.get("mark", Color(0.3, 0.9, 1.0)))))
		parts.append({"name": "Glow", "mesh": gm, "pos": Vector3.ZERO})
	var pr := float(spec.get("prop_r", 1.0))
	for i in mini(hubs.size(), PROP_NAMES.size()):
		var pm := PlaneModels.new()
		var blades := 3 if pr > 1.1 else 2
		if pr > 1.6:
			blades = 4
		for b in blades:
			var a := TAU * float(b) / float(blades) + 0.3
			pm._slab(S_TRIM, Vector3(cos(a), sin(a), 0.0) * 0.12, Vector3(cos(a), sin(a), 0.0) * pr, maxf(0.12, pr * 0.16), 0.05, Vector3.BACK)
		pm._cone(S_CHROME, Vector3(0.0, 0.0, 0.1), Vector3(0.0, 0.0, -0.45 - pr * 0.12), maxf(0.14, pr * 0.2), 8)
		parts.append({"name": PROP_NAMES[i], "mesh": pm._finish(), "pos": hubs[i]})
	return {"parts": parts}


## w128-airlook: real proportions where the wave 126 table was off (wing area of the wide-bodies; same spans, so the PLANE LINE and the collision boxes stay).
const W128_FIX := {
	&"p_wide": {"w": [-6.5, 19.0, 10.5, 2.4, 9.5, 1.5, -0.65, 0.75]},
	&"p_jumbo": {"w": [-7.5, 19.0, 11.5, 2.6, 10.0, 1.6, -0.65, 0.8]},
	&"p_narrow": {"w": [-4.4, 17.0, 6.8, 1.7, 6.5, 1.2, -0.65, 0.52]},
}


## The model parameters of a kind (PlaneRoster.DEFS m with the w128 corrections).
static func params(kind: StringName) -> Dictionary:
	var P: Dictionary = PlaneRoster.DEFS[kind]["m"]
	if old or not W128_FIX.has(kind):
		return P
	var q := P.duplicate()
	q.merge(W128_FIX[kind], true)
	return q


## w128-airlook: the windows on the skin (patches that follow the fuselage): an airliner's cockpit band with its posts, the passenger window row each side, the doors;
## a light plane's sloping windscreen and its cabin side windows with the door seam.
func _glass2(cabk: String, st: Array, n: float, zn: float, zt: float, hw: float, hh: float, yc: float, L: float, det: PlaneModels) -> void:
	if cabk == "airliner":
		var z0 := zn + L * 0.032
		var z1 := zn + L * 0.058
		var band := [HeliModels._at(st, z0), HeliModels._at(st, (z0 + z1) * 0.5), HeliModels._at(st, z1)]
		for i in band.size():
			band[i] = (band[i] as Array).duplicate()
			band[i][2] = float(band[i][2]) + hh * 0.08
		_patch(S_GLASS, band, n, 0.42, PI - 0.42, 8 if far_lod == 0 else 4, 1.01)
		if far_lod > 0:
			for side in [[0.18, 0.3], [PI - 0.3, PI - 0.18]]:              # the window rows as one dark line far away
				_patch(S_GLASS, [HeliModels._at(st, zn + L * 0.11), HeliModels._at(st, zt - L * 0.3)], n, float(side[0]), float(side[1]), 1, 1.006)
			return
		for a: float in [0.9, 1.35, PI - 1.35, PI - 0.9]:                 # the window posts
			_patch(S_TRIM, band, n, a - 0.025, a + 0.025, 1, 1.016)
		var pitch := 0.55 if L > 20.0 else 0.6
		var wz := zn + L * 0.12
		var wl := minf(0.26, pitch * 0.48)
		while wz < zt - L * 0.31:
			for side in [[0.2, 0.3], [PI - 0.3, PI - 0.2]]:
				_patch(S_GLASS, [HeliModels._at(st, wz), HeliModels._at(st, wz + wl)], n, float(side[0]), float(side[1]), 1, 1.006)
			wz += pitch
		for dz: float in [zn + L * 0.085, zt - L * 0.27]:                 # the doors: front and rear, both sides
			for side in [[-0.15, 0.62], [PI - 0.62, PI + 0.15]]:
				for e: float in [0.0, 0.9]:
					_patch(S_TRIM, [HeliModels._at(st, dz + e), HeliModels._at(st, dz + e + 0.04)], n, float(side[0]), float(side[1]), 4, 1.005)
	else:
		var a0 := zn + L * 0.13
		var a1 := zn + L * 0.2
		_patch(S_GLASS, [HeliModels._at(st, a0), HeliModels._at(st, (a0 + a1) * 0.5), HeliModels._at(st, a1)], n, 0.5, PI - 0.5, 8 if far_lod == 0 else 4, 1.012)
		var s0 := zn + L * 0.205
		var s1 := zn + L * 0.36
		for side in [[0.12, 0.82], [PI - 0.82, PI - 0.12]]:
			_patch(S_GLASS, [HeliModels._at(st, s0), HeliModels._at(st, (s0 + s1) * 0.5), HeliModels._at(st, s1)], n, float(side[0]), float(side[1]), 3, 1.012)
		if far_lod == 0:
			_patch(S_TRIM, [HeliModels._at(st, a0), HeliModels._at(st, a1)], n, PI * 0.5 - 0.03, PI * 0.5 + 0.03, 1, 1.02)
			for zz: float in [s0 + (s1 - s0) * 0.48, s1 + 0.05]:
				for side in [[-0.6, 0.9], [PI - 0.9, PI + 0.6]]:
					_patch(S_TRIM, [HeliModels._at(st, zz), HeliModels._at(st, zz + 0.035)], n, float(side[0]), float(side[1]), 4, 1.006)


func _empty() -> bool:
	for s in 4:
		if not (_v[s] as PackedVector3Array).is_empty():
			return false
	return true


## A cone (or a truncated cone with r1 > 0) from `a` (radius r) to `b` (radius r1), closed at both ends.
func _cone(surf: int, a: Vector3, b: Vector3, r: float, segs: int, r1 := 0.0) -> void:
	var ax := (b - a).normalized()
	var u := Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT
	var a1 := ax.cross(u).normalized()
	var a2 := ax.cross(a1).normalized()
	var mid := (a + b) * 0.5
	for i in segs:
		var t0 := TAU * float(i) / float(segs)
		var t1 := TAU * float(i + 1) / float(segs)
		var d0 := a1 * cos(t0) + a2 * sin(t0)
		var d1 := a1 * cos(t1) + a2 * sin(t1)
		_tri(surf, a + d0 * r, a + d1 * r, b + d0 * r1, mid)
		if r1 > 0.0:
			_tri(surf, a + d1 * r, b + d1 * r1, b + d0 * r1, mid)
			_tri(surf, b, b + d0 * r1, b + d1 * r1, mid)
		_tri(surf, a, a + d0 * r, a + d1 * r, mid)


## Both wings of the planform [zle, hs, cr, ct, sw, dh] at height y, from x0 out.
func _wings(surf: int, w: Array, y: float, x0: float, dz := 0.0) -> void:
	var zle := float(w[0]) + dz
	var hs := float(w[1])
	var cr := float(w[2])
	var ct := float(w[3])
	var sw := float(w[4])
	var dh := float(w[5])
	var th := float(w[7])
	for sx in [-1.0, 1.0]:
		_panel(surf, Vector3(sx * x0, y, zle), Vector3(sx * x0, y, zle + cr), Vector3(sx * hs, y + dh, zle + sw), Vector3(sx * hs, y + dh, zle + sw + ct), th, th * 0.4, Vector3.UP)


## Where the wing's leading edge and chord are at a share `t` of the half span (0 = root, 1 = tip): [z of the LE, chord, y].
static func wing_at(w: Array, y: float, t: float) -> Array:
	return [float(w[0]) + float(w[4]) * t, lerpf(float(w[2]), float(w[3]), t), y + float(w[5]) * t]


## Everything but the propellers. Returns the propeller hubs (Prop first).
func _geom(P: Dictionary, det: PlaneModels, glow: PlaneModels, spec: Dictionary) -> Array:
	var f: Array = P["f"]
	var zn := float(f[0])
	var zt := float(f[1])
	var hw := float(f[2])
	var hh := float(f[3])
	var yc := float(f[4])
	var L := zt - zn
	var n := float(P.get("n", 2.2))
	var nose := String(P.get("nose", "round"))
	var x: Array = P.get("x", [])
	var tail := String(P.get("t", "conv"))
	var hubs: Array = []
	smooth = not old
	# --- the fuselage
	var st: Array = []
	match nose:
		"point":
			st.append([zn, 0.0, yc - hh * 0.05, hw * 0.06, hh * 0.06])
			st.append([zn + L * 0.13, 0.0, yc, hw * 0.6, hh * 0.62])
		"droop":
			st.append([zn, 0.0, yc - hh * 0.3, hw * 0.05, hh * 0.05])
			st.append([zn + L * 0.09, 0.0, yc - hh * 0.05, hw * 0.55, hh * 0.55])
		"blunt":
			st.append([zn, 0.0, yc, hw * 0.6, hh * 0.6])
			st.append([zn + L * 0.07, 0.0, yc, hw * 0.88, hh * 0.9])
		_:
			st.append([zn, 0.0, yc - hh * 0.12, hw * 0.22, hh * 0.22])
			st.append([zn + L * 0.05, 0.0, yc - hh * 0.04, hw * 0.78, hh * 0.8])
	st.append([zn + L * 0.2, 0.0, yc, hw, hh])
	if tail == "none":
		st.append([zt - L * 0.25, 0.0, yc, hw * 0.92, hh * 0.85])
		st.append([zt, 0.0, yc, hw * 0.55, hh * 0.35])
	else:
		st.append([zt - L * 0.36, 0.0, yc, hw, hh])
		st.append([zt - L * 0.1, 0.0, yc + hh * 0.35, hw * 0.36, hh * 0.46])
		st.append([zt, 0.0, yc + hh * 0.52, hw * 0.12, hh * 0.2])
	_loft(S_BODY, st, n, 12 if L < 30.0 else 14)
	var top_tail := yc + hh * 0.52                                   # the height of the tail cone (fins grow from here)
	if x.has("hump"):
		_loft(S_BODY, [[zn + L * 0.06, 0.0, yc + hh * 0.55, hw * 0.3, hh * 0.25], [zn + L * 0.14, 0.0, yc + hh * 0.78, hw * 0.72, hh * 0.45],
			[zn + L * 0.32, 0.0, yc + hh * 0.78, hw * 0.72, hh * 0.45], [zn + L * 0.42, 0.0, yc + hh * 0.6, hw * 0.4, hh * 0.25]], 2.0, 10)
	if x.has("dome"):
		_loft(S_BODY, [[zn + L * 0.05, 0.0, yc + hh * 0.4, hw * 0.3, hh * 0.3], [zn + L * 0.14, 0.0, yc + hh * 0.65, hw * 0.85, hh * 0.55], [zn + L * 0.35, 0.0, yc + hh * 0.5, hw * 0.6, hh * 0.4]], 2.0, 10)
	if x.has("hopper"):
		_box(S_BODY, Vector3(0.0, yc + hh * 0.85, zn + L * 0.3), Vector3(hw * 1.5, hh * 0.5, L * 0.16))
	# --- the cockpit glass
	var cabk := String(P.get("cab", "none"))
	if not old and (cabk == "airliner" or cabk == "cabin"):
		_glass2(cabk, st, n, zn, zt, hw, hh, yc, L, det)
		cabk = "done"
	match cabk:
		"bubble":
			var z0 := zn + L * (0.16 if L > 9.0 else 0.26)
			var ln := clampf(L * 0.2, 1.4, 3.6)
			var bub := [[z0, 0.0, yc + hh * 0.7, hw * 0.12, hh * 0.1], [z0 + ln * 0.35, 0.0, yc + hh * 0.86, hw * 0.55, hh * 0.42],
				[z0 + ln * 0.75, 0.0, yc + hh * 0.86, hw * 0.52, hh * 0.4], [z0 + ln, 0.0, yc + hh * 0.75, hw * 0.25, hh * 0.15]]
			if old:
				_loft(S_GLASS, bub, 2.0, 10)
			else:                                                           # w128-airlook: the canopy is the top half (its belly would sit inside the fuselage), with a frame bow
				_patch(S_GLASS, bub, 2.0, -0.15, PI + 0.15, 10 if far_lod == 0 else 5, 1.0)
				if far_lod == 0:
					_patch(S_TRIM, [HeliModels._mix(bub[1], bub[2], 0.1), HeliModels._mix(bub[1], bub[2], 0.16)], 2.0, -0.1, PI + 0.1, 8, 1.02)
		"cabin":
			var z1 := zn + L * 0.2
			for sx in [-1.0, 1.0]:
				_box(S_GLASS, Vector3(sx * hw * 0.98, yc + hh * 0.38, z1 + L * 0.12), Vector3(0.06, hh * 0.5, L * 0.22))
			_quad_panel(S_GLASS, Vector3(-hw * 0.82, yc + hh * 0.15, z1 - L * 0.02), Vector3(hw * 0.82, yc + hh * 0.15, z1 - L * 0.02),
				Vector3(hw * 0.75, yc + hh * 0.86, z1 + L * 0.05), Vector3(-hw * 0.75, yc + hh * 0.86, z1 + L * 0.05), Vector3(0.0, yc, z1 + 2.0))
		"airliner":
			for sx in [-1.0, 1.0]:
				_box(S_GLASS, Vector3(sx * hw * 0.72, yc + hh * 0.42, zn + L * 0.045), Vector3(hw * 0.5, hh * 0.16, L * 0.025))
				_box(S_GLASS, Vector3(sx * hw * 0.995, yc + hh * 0.3, zn + L * 0.42), Vector3(0.05, hh * 0.13, L * 0.5))
		"glazed":
			if old:
				_loft(S_GLASS, [[zn - 0.02, 0.0, (st[0] as Array)[2], hw * 0.3, hh * 0.3], [zn + L * 0.07, 0.0, yc + hh * 0.05, hw * 0.82, hh * 0.84]], 2.0, 10)
			else:                                                           # w128-airlook: the glazed nose with chin windows, not a glass ring round the belly
				_patch(S_GLASS, [HeliModels._mix(st[0], st[1], 0.15), st[1], HeliModels._mix(st[1], st[2], 0.12)], n, -0.6, PI + 0.6, 10 if far_lod == 0 else 5, 1.012)
			for sx in [-1.0, 1.0]:
				_box(S_GLASS, Vector3(sx * hw * 0.7, yc + hh * 0.55, zn + L * 0.1), Vector3(hw * 0.45, hh * 0.22, L * 0.03))
		"open":
			_quad_panel(S_GLASS, Vector3(-hw * 0.4, yc + hh * 0.95, zn + L * 0.42), Vector3(hw * 0.4, yc + hh * 0.95, zn + L * 0.42),
				Vector3(hw * 0.3, yc + hh * 1.3, zn + L * 0.46), Vector3(-hw * 0.3, yc + hh * 1.3, zn + L * 0.46), Vector3(0.0, yc, zn + L))
			_cyl(S_TRIM, Vector3(0.0, yc + hh * 0.98, zn + L * 0.5), hw * 0.45, 0.2, 1, 8)
		"slit":
			_box(S_GLASS, Vector3(0.0, yc + hh * 0.9, zn + L * 0.18), Vector3(hw * 0.6, hh * 0.18, L * 0.08))
	# --- the wings
	var w: Array = P["w"]
	var wy := yc + float(w[6]) * hh
	_wings(S_BODY, w, wy, hw * 0.6)
	if P.has("w2"):
		var w2: Array = P["w2"]
		_wings(S_BODY, w, wy + float(w2[0]), 0.0, float(w2[1]))
		var cz := float(w[0]) + float(w2[1]) * 0.5 + float(w[2]) * 0.4
		for sx in [-1.0, 1.0]:
			det._slab(S_TRIM, Vector3(sx * hw * 0.5, yc + hh * 0.7, cz), Vector3(sx * hw * 0.8, wy + float(w2[0]), cz), 0.08, 0.05, Vector3.BACK)
			var a := wing_at(w, wy, 0.75)
			det._slab(S_TRIM, Vector3(sx * float(w[1]) * 0.75, float(a[2]), float(a[0]) + float(a[1]) * 0.35), Vector3(sx * float(w[1]) * 0.75, float(a[2]) + float(w2[0]), float(a[0]) + float(a[1]) * 0.35 + float(w2[1])), 0.12, 0.06, Vector3.BACK)
	if x.has("winglet"):
		var a2 := wing_at(w, wy, 1.0)
		for sx in [-1.0, 1.0]:
			_panel(S_BODY, Vector3(sx * float(w[1]), float(a2[2]), float(a2[0])), Vector3(sx * float(w[1]), float(a2[2]), float(a2[0]) + float(a2[1])),
				Vector3(sx * float(w[1]), float(a2[2]) + float(w[1]) * 0.12, float(a2[0]) + float(a2[1]) * 0.7), Vector3(sx * float(w[1]), float(a2[2]) + float(w[1]) * 0.12, float(a2[0]) + float(a2[1]) * 1.0),
				0.12, 0.06, Vector3.RIGHT)
	if x.has("canard"):
		_wings(S_BODY, [zn + L * 0.22, hw + L * 0.12, L * 0.09, L * 0.04, L * 0.05, 0.0, 0.0, 0.12], yc + hh * 0.2, hw * 0.6)
	# --- the tail
	var tp: Array = P.get("tp", [0.0, 0.0, 0.0, 0.0])
	var fh := float(tp[0])
	var fc := float(tp[1])
	var sh := float(tp[2])
	var sc := float(tp[3])
	match tail:
		"conv", "t", "twin", "fin":
			if tail != "twin":
				_panel(S_BODY, Vector3(0.0, top_tail - hh * 0.1, zt - fc * 1.05), Vector3(0.0, top_tail - hh * 0.1, zt), Vector3(0.0, top_tail + fh, zt - fc * 0.35), Vector3(0.0, top_tail + fh, zt + fc * 0.05),
					fc * 0.12, fc * 0.07, Vector3.RIGHT)
			if tail != "fin":
				var sy := top_tail + (fh * 0.95 if tail == "t" else -hh * 0.05)
				var sz := zt - sc * (0.9 if tail == "t" else 1.05)
				_wings(S_BODY, [sz, sh, sc, sc * 0.55, sc * 0.4, 0.0, 0.0, sc * 0.12], sy, 0.0)
				if tail == "twin":
					for sx in [-1.0, 1.0]:
						_panel(S_BODY, Vector3(sx * sh, sy - fh * 0.25, sz), Vector3(sx * sh, sy - fh * 0.25, sz + sc * 0.8), Vector3(sx * sh, sy + fh * 0.75, sz + sc * 0.25), Vector3(sx * sh, sy + fh * 0.75, sz + sc * 0.85),
							sc * 0.12, sc * 0.08, Vector3.RIGHT)
		"v", "vcant":
			var cant := 0.62 if tail == "v" else 0.42
			var bx := 0.0 if tail == "v" else hw * 0.55
			var by := top_tail if tail == "v" else yc + hh * 0.4
			for sx in [-1.0, 1.0]:
				var tip := Vector3(sx * (bx + fh * sin(cant)), by + fh * cos(cant), 0.0)
				_panel(S_BODY, Vector3(sx * bx, by, zt - fc * 1.1), Vector3(sx * bx, by, zt), Vector3(tip.x, tip.y, zt - fc * 0.4), Vector3(tip.x, tip.y, zt + fc * 0.05),
					fc * 0.12, fc * 0.07, Vector3(cos(cant), -sx * sin(cant), 0.0) * sx)
			if tail == "vcant" and sh > 0.0:
				_wings(S_BODY, [zt - sc * 0.95, sh, sc, sc * 0.5, sc * 0.5, 0.0, 0.0, sc * 0.1], yc, hw * 0.5)
	# --- the engines
	var e: Dictionary = P.get("e", {})
	var er := float(e.get("r", 0.5))
	var el := float(e.get("l", 2.0))
	match String(e.get("type", "")):
		"nose":
			_cone(S_TRIM, Vector3(0.0, yc, zn + 0.02), Vector3(0.0, yc, zn + el), er * 1.05, 10, er * 1.15)
			hubs.append(Vector3(0.0, yc, zn - 0.05))
		"push":
			hubs.append(Vector3(0.0, top_tail - hh * 0.1, zt + 0.12))
		"mast":
			var mz := zn + L * 0.45
			det._slab(S_TRIM, Vector3(0.0, yc + hh * 0.8, mz), Vector3(0.0, yc + hh + 0.75, mz), 0.3, 0.06, Vector3.BACK)
			_cyl(S_TRIM, Vector3(0.0, yc + hh + 0.8, mz), er, 0.7, 2, 8)
			hubs.append(Vector3(0.0, yc + hh + 0.8, mz - 0.42))
		"wp", "wt":
			for t: float in e.get("at", [0.3]):
				var a3 := wing_at(w, wy, t)
				var ny := float(a3[2]) + (er * 1.0 if e["type"] == "wt" else (-er * 0.25 if float(w[6]) < 0.0 else er * 0.1))
				var nz := float(a3[0]) - el * 0.25
				for sx in [-1.0, 1.0]:
					var nx: float = sx * float(w[1]) * t
					_loft(S_BODY, [[nz - el * 0.5, nx, ny, er * 0.55, er * 0.55], [nz - el * 0.35, nx, ny, er, er], [nz + el * 0.25, nx, ny, er * 0.95, er * 0.9], [nz + el * 0.5, nx, ny, er * 0.35, er * 0.35]], 2.0, 10)
					if hubs.size() < 4:
						hubs.append(Vector3(nx, ny, nz - el * 0.55))
		"wj":
			for t: float in e.get("at", [0.33]):
				var a4 := wing_at(w, wy, t)
				var jy := float(a4[2]) - er * 1.25
				if not old:
					jy = maxf(jy, er + 0.55)                                    # w128-airlook: the fan clears the ground (a short pylon under a low wing)
				var jz := float(a4[0]) - el * 0.2
				for sx in [-1.0, 1.0]:
					var jx: float = sx * float(w[1]) * t
					_loft(S_BODY, [[jz - el * 0.5, jx, jy, er * 0.95, er * 0.95], [jz - el * 0.3, jx, jy, er, er], [jz + el * 0.3, jx, jy, er * 0.85, er * 0.85], [jz + el * 0.5, jx, jy, er * 0.55, er * 0.55]], 2.0, 12)
					_cyl(S_TRIM, Vector3(jx, jy, jz - el * 0.5 + 0.02), er * 0.82, 0.08, 2, 10)                    # the intake face
					_slab(S_BODY, Vector3(jx, jy + er * 0.7, jz - el * 0.05), Vector3(jx, float(a4[2]), jz + el * 0.15), el * 0.5, 0.25, Vector3.RIGHT)          # the pylon
		"tj":
			for sx in [-1.0, 1.0]:
				var px: float = sx * (hw + er * 1.1)
				var py := yc + hh * 0.55
				var pz := zt - L * 0.3
				_loft(S_BODY, [[pz - el * 0.5, px, py, er * 0.95, er * 0.95], [pz - el * 0.3, px, py, er, er], [pz + el * 0.5, px, py, er * 0.6, er * 0.6]], 2.0, 10)
				_cyl(S_TRIM, Vector3(px, py, pz - el * 0.5 + 0.02), er * 0.8, 0.08, 2, 10)
				_slab(S_BODY, Vector3(px - sx * er * 0.6, py, pz), Vector3(sx * hw * 0.5, py - hh * 0.2, pz), el * 0.45, 0.2, Vector3.BACK)
		"int":
			var nn := int(e.get("n", 1))
			for i in nn:
				var ox := (float(i) - float(nn - 1) * 0.5) * er * 2.3
				var oy := yc if tail == "none" else yc + hh * 0.05
				var oz := zt - (0.4 if tail == "none" else L * 0.08)
				_cone(S_TRIM, Vector3(ox, oy, oz - 0.6), Vector3(ox, oy, oz + 0.5), er, 10, er * 0.82)
				if x.has("glow"):
					glow._cyl(S_BODY, Vector3(ox, oy, oz + 0.52), er * 0.7, 0.05, 2, 10)
	# --- extras on the body
	if x.has("intake"):
		for sx in [-1.0, 1.0]:
			_box(S_TRIM, Vector3(sx * hw * 1.02, yc - hh * 0.15, zn + L * 0.36), Vector3(hw * 0.5, hh * 0.9, L * 0.16))
	if x.has("intake_top"):
		_box(S_TRIM, Vector3(0.0, yc + hh * 0.85, zn + L * 0.35), Vector3(hw * 0.7, hh * 0.35, L * 0.14))
	if x.has("rotodome"):
		var rz := zt - L * 0.34
		var ry := yc + hh + 2.4
		_cyl(S_BODY, Vector3(0.0, ry, rz), 4.6, 0.95, 1, 18)
		_cyl(S_TRIM, Vector3(0.0, ry, rz), 4.65, 0.25, 1, 18)
		for dz in [-1.2, 1.2]:
			_slab(S_BODY, Vector3(0.0, yc + hh * 0.9, rz + dz), Vector3(0.0, ry - 0.4, rz + dz * 0.6), 0.9, 0.3, Vector3.BACK)
	if x.has("boom"):
		_slab(S_BODY, Vector3(0.0, yc - hh * 0.75, zt - L * 0.12), Vector3(0.0, yc - hh * 1.35, zt + L * 0.04), 0.5, 0.4, Vector3.RIGHT)
		_wings(S_BODY, [zt - 0.6, 1.4, 0.8, 0.5, 0.3, 0.0, 0.0, 0.1], yc - hh * 1.25, 0.0, L * 0.04 - 0.4)
	if x.has("drogue"):
		var ad := wing_at(w, wy, 0.85)
		for sx in [-1.0, 1.0]:
			_cyl(S_BODY, Vector3(sx * float(w[1]) * 0.85, float(ad[2]) - 0.5, float(ad[0]) + 0.6), 0.35, 2.6, 2, 8)
	if x.has("ramp"):
		_box(S_TRIM, Vector3(0.0, yc - hh * 0.72, zt - L * 0.2), Vector3(hw * 1.4, 0.08, L * 0.18))
	if x.has("sponson"):
		for sx in [-1.0, 1.0]:
			_loft(S_BODY, [[zn + L * 0.36, sx * hw * 0.95, yc - hh * 0.62, hw * 0.25, hh * 0.25], [zn + L * 0.42, sx * hw * 0.95, yc - hh * 0.62, hw * 0.42, hh * 0.38],
				[zn + L * 0.6, sx * hw * 0.95, yc - hh * 0.62, hw * 0.42, hh * 0.38], [zn + L * 0.66, sx * hw * 0.95, yc - hh * 0.62, hw * 0.25, hh * 0.25]], 2.4, 8)
	if x.has("bays"):
		_box(S_TRIM, Vector3(0.0, yc - hh * 0.98, zn + L * 0.5), Vector3(hw * 0.9, 0.06, L * 0.22))
	if x.has("floats_tip"):
		var af := wing_at(w, wy, 0.92)
		for sx in [-1.0, 1.0]:
			var fx: float = sx * float(w[1]) * 0.92
			_loft(S_BODY, [[float(af[0]) - 0.6, fx, float(af[2]) - 1.6, 0.2, 0.18], [float(af[0]), fx, float(af[2]) - 1.6, 0.42, 0.36], [float(af[0]) + 1.6, fx, float(af[2]) - 1.5, 0.2, 0.18]], 2.0, 8)
			det._slab(S_TRIM, Vector3(fx, float(af[2]) - 1.3, float(af[0]) + 0.3), Vector3(fx, float(af[2]), float(af[0]) + 0.6), 0.1, 0.08, Vector3.BACK)
	if x.has("glow"):
		var ag := wing_at(w, wy, 0.0)
		for sx in [-1.0, 1.0]:
			glow._slab(S_BODY, Vector3(sx * hw, wy + 0.06, float(ag[0]) + 0.2), Vector3(sx * float(w[1]) * 0.96, wy + float(w[5]) + 0.06, float(w[0]) + float(w[4]) + 0.15), 0.12, 0.05)
	if x.has("ring") or x.has("ring2"):
		var centres: Array = [Vector3(0.0, yc, zt - L * 0.25)]
		var rad := hh * 1.9
		if x.has("ring2"):
			var ar := wing_at(w, wy, 0.92)
			centres = [Vector3(-float(w[1]) * 0.9, float(ar[2]), float(ar[0]) + float(ar[1]) * 0.5), Vector3(float(w[1]) * 0.9, float(ar[2]), float(ar[0]) + float(ar[1]) * 0.5)]
			rad = 1.0
		for cc: Vector3 in centres:
			for i in 14:
				var a5 := TAU * float(i) / 14.0
				var a6 := TAU * float(i + 1) / 14.0
				glow._slab(S_BODY, cc + Vector3(cos(a5), sin(a5), 0.0) * rad, cc + Vector3(cos(a6), sin(a6), 0.0) * rad, 0.14, 0.14, Vector3.BACK)
	# --- detail: struts, sprays, weapons, sensors
	if x.has("strut"):
		var as_ := wing_at(w, wy, 0.55)
		for sx in [-1.0, 1.0]:
			det._slab(S_TRIM, Vector3(sx * hw * 0.9, yc - hh * 0.6, float(w[0]) + float(w[2]) * 0.4), Vector3(sx * float(w[1]) * 0.55, float(as_[2]) - 0.05, float(as_[0]) + float(as_[1]) * 0.4), 0.16, 0.07, Vector3.BACK)
	if x.has("spray"):
		var ap := wing_at(w, wy, 0.5)
		det._cyl(S_CHROME, Vector3(0.0, wy - 0.35, float(ap[0]) + float(ap[1]) + 0.15), 0.05, float(w[1]) * 1.7, 0, 6)
	if x.has("pods"):
		for t2: float in [0.45, 0.75]:
			var aw := wing_at(w, wy, t2)
			for sx in [-1.0, 1.0]:
				var mx: float = sx * float(w[1]) * t2
				det._slab(S_TRIM, Vector3(mx, float(aw[2]) - 0.05, float(aw[0]) + float(aw[1]) * 0.3), Vector3(mx, float(aw[2]) - 0.35, float(aw[0]) + float(aw[1]) * 0.35), float(aw[1]) * 0.35, 0.1, Vector3.RIGHT)
				det._cone(S_CHROME, Vector3(mx, float(aw[2]) - 0.5, float(aw[0]) + float(aw[1]) * 0.7), Vector3(mx, float(aw[2]) - 0.5, float(aw[0]) - 0.9), 0.14, 6)
	if x.has("gun"):
		det._cyl(S_CHROME, Vector3(0.0, yc - hh * 0.35, zn - 0.6), 0.1, 1.4, 2, 6)
	if x.has("sensor"):
		det._cyl(S_TRIM, Vector3(0.0, yc - hh * 1.05, zn + L * 0.22), 0.28, 0.4, 1, 8)
	# --- the landing gear (detail), floats and the hull (body)
	var r := float(spec.get("wheel", 0.4))
	var g := String(P.get("g", "trike"))
	var bottom := yc - hh
	var mz2 := float(w[0]) + float(w[2]) * 0.65                       # the main gear sits under the wing, behind the centre of lift
	if tail == "none":
		mz2 = zn + L * 0.62
	match g:
		"trike", "mil", "heavy":
			var gx := maxf(hw * 1.15, minf(float(w[1]) * 0.22, hw * 3.0))
			if g == "heavy":
				gx = hw * 0.95
			det._strut_wheel(Vector3(0.0, bottom + 0.1, zn + L * 0.13), r * 0.8, g == "heavy")
			for sx in [-1.0, 1.0]:
				det._strut_wheel(Vector3(sx * gx, bottom + 0.1, mz2), r, g == "heavy")
		"tail":
			for sx in [-1.0, 1.0]:
				det._strut_wheel(Vector3(sx * hw * 1.6, bottom + 0.1, zn + L * 0.24), r, false)
			det._strut_wheel(Vector3(0.0, top_tail - hh * 0.6, zt - L * 0.05), r * 0.4, false)
		"skid":
			det._strut_wheel(Vector3(0.0, bottom + 0.05, zn + L * 0.42), r, false)
			det._strut_wheel(Vector3(0.0, bottom + 0.05, zt - L * 0.15), r * 0.6, false)
		"float":
			var fy := 0.42
			for sx in [-1.0, 1.0]:
				var fx2: float = sx * hw * 1.9
				_loft(S_BODY, [[zn + L * 0.02, fx2, fy + 0.08, 0.08, 0.06], [zn + L * 0.12, fx2, fy, 0.34, 0.38], [zn + L * 0.6, fx2, fy, 0.36, 0.4], [zn + L * 0.85, fx2, fy + 0.12, 0.1, 0.08]], 2.4, 8)
				for zz in [zn + L * 0.25, zn + L * 0.5]:
					det._slab(S_TRIM, Vector3(fx2, fy + 0.35, zz), Vector3(sx * hw * 0.7, bottom + 0.2, zz), 0.12, 0.08, Vector3.BACK)
		"hull":
			_box(S_TRIM, Vector3(0.0, bottom + 0.05, zn + L * 0.45), Vector3(hw * 1.2, 0.1, 0.4))              # the hull step
			for sx in [-1.0, 1.0]:
				det._strut_wheel(Vector3(sx * hw * 1.05, bottom + 0.6, zn + L * 0.4), r, false)
			det._strut_wheel(Vector3(0.0, bottom + 0.4, zn + L * 0.12), r * 0.8, false)
	return hubs


## A strut from `top` straight down to a wheel (or a pair of wheels for heavy gear) that touches y = 0.
func _strut_wheel(top: Vector3, r: float, pair: bool) -> void:
	var hub := Vector3(top.x, r, top.z)
	_slab(S_CHROME, Vector3(top.x, maxf(top.y, r + 0.05), top.z), hub + Vector3(0.0, r * 0.3, 0.0), maxf(0.1, r * 0.3), maxf(0.08, r * 0.25), Vector3.BACK)
	if pair:
		for dz in [-r * 1.1, r * 1.1]:
			_cyl(S_TRIM, hub + Vector3(0.0, 0.0, dz), r, r * 0.7, 0, 10)
	else:
		_cyl(S_TRIM, hub, r, r * 0.55, 0, 10)
