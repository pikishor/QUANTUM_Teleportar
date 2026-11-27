class_name TankModels
extends VehicleCraftModels
## WAVE 127 TANKS AND MILITARY GROUND VEHICLES: the procedural bodies of the twenty new kinds of TankRoster (own-made, no texture, original designs). One parametric builder reads the
## kind's model parameters (TankRoster.DEFS[kind]["m"]) and makes the node contract of the wave 108 armour (VehicleCraftModels.build_tank), so VehicleCraft turns the turret and lifts the gun:
##   "Body"    the hull (surfaces Body = paint / Glass / Trim / Chrome), nose -Z, ground y = 0
##   "Turret"  on the turret axis (VehicleCraft rotates it about Y to the crosshair); its "Body" surface wears the hull paint (VehicleVisual._bind_craft)
##   "Gun"     child of Turret on the trunnion (VehicleCraft lifts it about X): cannon, autocannon, machine gun, rocket box, crane boom, rail
##   "Run"     MultiMeshInstance3D: the RUNNING GEAR that moves (track cleats on the top and bottom runs of both tracks / the tyres / the walker's legs), ONE draw call, hidden beyond RUN_FAR m
##   "Run2"    MultiMeshInstance3D: the road wheels, drive sprockets and idlers of a tracked hull (they turn with the track), ONE draw call
##   "Flail"   the mine clearer's chain drum (spins), "Glow" the emissive marks of the sci-fi kinds (unshaded, one draw)
## SHARED MESHES: every mesh of a kind is built once and cached (`_cache`); a parked vehicle only owns its two small MultiMesh transform buffers. animate() (called from VehicleCraft.sync)
## rolls the cleats along the runs, turns the wheels (each side by its own travel: the tracks counter-rotate in a pivot turn), steers the front axle, swings the legs, bobs the hover tank.
##   build(kind, spec) -> Node3D      the model root (VehicleCraftModels.build calls it for every kind of TankRoster)
##   animate(v, dt)                   per tick from VehicleCraft.sync (tank branch)
##   tri_count(kind) -> int           triangles of the shared meshes (the budget check of tests/test_tanks_w127.gd)

const RUN_FAR := 60.0                         ## m: the moving cleats / tyres / legs are hidden beyond this (the track band and the wheel arches carry the shape)
const ANIM_NEAR := 70.0                       ## m: animate() does nothing for a vehicle farther than this that nobody drives
const PITCH := 0.42                           ## m between two track cleats
const C_DARK := Color(0.07, 0.072, 0.078)
const C_STEEL := Color(0.42, 0.43, 0.45)

static var on := OS.get_environment("W127_TANKS_OLD") != "1"      ## false: the wave 126 state (nothing animates, VehicleCraft._tank steers every kind like a tank)
static var _cache := {}


static func build(kind: String, spec: Dictionary) -> Node3D:
	var k := StringName(kind)
	if not _cache.has(k):
		_cache[k] = _make(k, spec)
	var c: Dictionary = _cache[k]
	var root := Node3D.new()
	root.name = String(spec.get("model", kind))
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = c["body"]
	root.add_child(body)
	if c.has("turret"):
		var tur := MeshInstance3D.new()
		tur.name = "Turret"
		tur.mesh = c["turret"]
		tur.position = c["tpos"]
		root.add_child(tur)
		if c.has("gun"):
			var gm := MeshInstance3D.new()
			gm.name = "Gun"
			gm.mesh = c["gun"]
			gm.position = c["trun"]
			tur.add_child(gm)
	for rn: String in ["Run", "Run2"]:
		if not c.has(rn):
			continue
		var items: Array = c[rn]["items"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = c[rn]["mesh"]
		mm.instance_count = items.size()
		for i in items.size():
			mm.set_instance_transform(i, (items[i] as Dictionary)["xf"])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = rn
		mmi.multimesh = mm
		mmi.visibility_range_end = RUN_FAR
		mmi.visibility_range_end_margin = 5.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	if c.has("flail"):
		var fl := MeshInstance3D.new()
		fl.name = "Flail"
		fl.mesh = c["flail"]
		fl.position = c["fpos"]
		root.add_child(fl)
	if c.has("glow"):
		var g := MeshInstance3D.new()
		g.name = "Glow"
		g.mesh = c["glow"]
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(g)
	root.set_meta(&"t127", k)
	return root


static func tri_count(kind: StringName) -> int:
	if not _cache.has(kind):
		return 0
	var c: Dictionary = _cache[kind]
	var n := 0
	for key: String in ["body", "turret", "gun", "flail", "glow"]:
		if c.has(key):
			n += _tris(c[key])
	for rn: String in ["Run", "Run2"]:
		if c.has(rn):
			n += _tris(c[rn]["mesh"]) * (c[rn]["items"] as Array).size()
	return n


static func _tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		n += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


## The running-gear items of a kind (for the tests): [{side, kind (&"cleat", &"wheel", &"leg", &"road"), ...}].
static func run_items(kind: StringName, run := "Run") -> Array:
	if not _cache.has(kind) or not (_cache[kind] as Dictionary).has(run):
		return []
	return _cache[kind][run]["items"]


## The running gear's current transforms of a live vehicle's model (`run` "Run" / "Run2"), as animate() last wrote them: [] before it first moved.
static func pose_of(model: Node3D, run := "Run") -> Array:
	var mmi := model.get_node_or_null(run) as MultiMeshInstance3D if model != null else null
	return (mmi.get_meta(&"pose", []) as Array).duplicate() if mmi != null else []


# --- animation -------------------------------------------------------------------------------------------------------------------------

## Per tick (VehicleCraft.sync, tank branch, after the turret): roll the cleats, turn the wheels and the road wheels, steer the front axle, swing the legs, bob the hover tank.
static func animate(v: Vehicle, dt: float) -> void:
	var vis := v.visual
	if vis == null or vis.model == null or not vis.model.has_meta(&"t127"):
		return
	var kind: StringName = vis.model.get_meta(&"t127")
	if not v.driver_is_player and v._dist > ANIM_NEAR:
		return
	var c: Dictionary = _cache.get(kind, {})
	if c.is_empty():
		return
	var M: Dictionary = c["m"]
	var run := String(M.get("run", "track"))
	var hw := float(v.spec["wid"]) * 0.5
	var dl := (v.speed - v.yaw_rate * hw) * dt                                    # the travel of each side this tick (a pivot turn: the two sides run opposite ways)
	var dr := (v.speed + v.yaw_rate * hw) * dt
	var st: Dictionary = vis.model.get_meta(&"t127s", {"l": 0.0, "r": 0.0, "ph": 0.0, "t": 0.0})
	st["l"] = float(st["l"]) + dl
	st["r"] = float(st["r"]) + dr
	st["t"] = float(st["t"]) + dt
	if run == "hover":
		vis.model.position = Vector3(0.0, float(M.get("lift", 0.5)) + sin(float(st["t"]) * 2.2) * 0.06, 0.0)
		vis.model.rotation = Vector3(vis.model.rotation.x, 0.0, clampf(-v.yaw_rate * 0.08, -0.12, 0.12))
	var moved := absf(dl) + absf(dr) > 0.0001 or not st.has("done")
	st["done"] = true
	vis.model.set_meta(&"t127s", st)
	var fl := vis.model.get_node_or_null("Flail") as Node3D
	if fl != null:
		fl.rotation.x = fposmod(fl.rotation.x - (dl + dr) * 2.5 - dt * 9.0, TAU)       # the chains whirl even at a standstill
	if not moved:
		return
	var steer := clampf(v.steer_in, -1.0, 1.0) * 0.42
	for rn: String in ["Run", "Run2"]:
		var mmi := vis.model.get_node_or_null(rn) as MultiMeshInstance3D
		if mmi == null or not c.has(rn) or not mmi.is_visible_in_tree():
			continue
		var items: Array = c[rn]["items"]
		var mm := mmi.multimesh
		var pose: Array = mmi.get_meta(&"pose", [])                                 # the CPU copy of the transforms (pose_of: a headless test cannot read a MultiMesh back)
		if pose.size() != items.size():
			pose.resize(items.size())
			mmi.set_meta(&"pose", pose)
		for i in items.size():
			var it: Dictionary = items[i]
			var trav := float(st["l"]) if float(it["side"]) < 0.0 else float(st["r"])
			var xf: Transform3D = it["xf"]
			match it["kind"]:
				&"cleat":                                                      # the bottom run lies still on the ground (moves back along the hull), the top run comes forward
					var a := float(it["za"])
					var b := float(it["zb"])
					var z := a + fposmod(float(it["z0"]) - a + trav * float(it["dir"]), b - a)
					xf.origin.z = z
				&"wheel", &"road":
					var ang := -trav / float(it["r"])
					var yaw := steer * float(it.get("steer", 0.0))
					xf.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, ang) * xf.basis
				&"leg":
					var ph := (float(st["l"]) + float(st["r"])) * 0.5 / float(it["stride"]) * TAU + float(it["phase"])
					xf.basis = Basis(Vector3.RIGHT, sin(ph) * 0.42) * xf.basis
					xf.origin.y += maxf(cos(ph), 0.0) * 0.18
			mm.set_instance_transform(i, xf)
			pose[i] = xf


# --- building --------------------------------------------------------------------------------------------------------------------------

static var _run_mats := {}


static func _vc_material() -> StandardMaterial3D:
	if not _run_mats.has("vc"):
		var m := StandardMaterial3D.new()
		m.resource_name = "Run"
		m.vertex_color_use_as_albedo = true
		m.metallic = 0.35
		m.roughness = 0.6
		_run_mats["vc"] = m
	return _run_mats["vc"]


static func _glow_material(col: Color) -> StandardMaterial3D:
	var key := col.to_html()
	if not _run_mats.has(key):
		var m := StandardMaterial3D.new()
		m.resource_name = "Glow"
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col
		_run_mats[key] = m
	return _run_mats[key]


## w127-critic: ONE surface for a hull / turret / gun / flail (was up to four: paint, glass, trim, chrome = four draw calls per part, 7 to 11 per vehicle; nine tanks in view put LOW
## at 149-161 draws against its budget of 100 and MED at 182-192 against 140). The paint keeps its name "Body" (VehicleVisual binds the vehicle's paint material to it and the turret and
## gun wear the same one); the other parts are vertex colours the paint colour multiplies (trim and glass stay near black, steel turns a darker shade of the paint).
static var merge_on := OS.get_environment("W127C_OLD") != "1"

func _finish_one() -> ArrayMesh:
	if not merge_on:
		return _finish()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	for s in 4:
		var vv: PackedVector3Array = _v[s]
		verts.append_array(vv)
		norms.append_array(_n[s])
		var col: Color = Color(1.0, 1.0, 1.0) if s == S_BODY else (C_STEEL * 1.25 if s == S_CHROME else (C_DARK if s == S_TRIM else Color(0.06, 0.08, 0.1)))
		for i in vv.size():
			cols.append(col)
	var m := ArrayMesh.new()
	if verts.is_empty():
		return m
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	mat.resource_name = NAMES[S_BODY]
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = COLS[S_BODY]
	mat.metallic = METAL[S_BODY]
	mat.roughness = ROUGH[S_BODY]
	m.surface_set_material(0, mat)
	return m


## One single-surface mesh with vertex colours from the Trim (dark) and Chrome (steel) surfaces of a builder: a MultiMesh part costs one draw call.
func _finish_vc() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	for s in 4:
		var vv: PackedVector3Array = _v[s]
		verts.append_array(vv)
		norms.append_array(_n[s])
		var col: Color = C_STEEL if s == S_CHROME else (C_DARK if s == S_TRIM else COLS[s])
		for i in vv.size():
			cols.append(col)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, _vc_material())
	return m


static func _make(kind: StringName, spec: Dictionary) -> Dictionary:
	var M: Dictionary = TankRoster.DEFS[kind]["m"]
	var hull := TankModels.new()
	var tur := TankModels.new()
	var gun := TankModels.new()
	var glow := TankModels.new()
	var ln := float(spec["len"])
	var wid := float(spec["wid"])
	var out := {"m": M}
	var run := String(M.get("run", "track"))
	var tw := float(M.get("tw", 0.62))
	var wr := float(spec.get("wheel", 0.5))
	# --- the running gear
	match run:
		"track":
			_track_gear(out, hull, ln, wid, tw, float(M.get("tt", 0.9)), 0.0)
		"half":
			_track_gear(out, hull, ln * 0.55, wid, tw, float(M.get("tt", 0.8)), ln * 0.2)
			_wheels(out, M, ln, wid, wr, hull)
		"wheel":
			_wheels(out, M, ln, wid, wr, hull)
		"legs":
			_legs(out, M, ln, wid)
	# --- the hull
	hull._hull(String(M.get("hull", "tank")), M, ln, wid, glow)
	out["body"] = hull._finish_one()
	# --- the turret and its gun
	var T: Array = M.get("tur", ["none"])
	if String(T[0]) != "none":
		tur._turret(T, M, glow)
		out["turret"] = tur._finish_one()
		out["tpos"] = Vector3(0.0, float(M.get("ty", 1.5)), float(M.get("tz", 0.0)))
		var G: Array = M.get("gun", ["none"])
		if String(G[0]) != "none":
			gun._gun(G)
			out["gun"] = gun._finish_one()
			var tr: Array = M.get("tr", [0.3, -0.8])
			out["trun"] = Vector3(0.0, float(tr[0]), float(tr[1]))
	if (M.get("x", []) as Array).has("flail"):
		var f := TankModels.new()
		var fw := wid * 0.95
		f._cyl(S_TRIM, Vector3.ZERO, 0.22, fw, 0, 10)
		for k in 12:                                                                # chains with weights round the drum
			var a := TAU * float(k) / 12.0
			var x := lerpf(-fw * 0.45, fw * 0.45, float(k % 6) / 5.0)
			f._box(S_CHROME, Vector3(x, cos(a) * 0.45, sin(a) * 0.45), Vector3(0.06, 0.06 + absf(cos(a)) * 0.4, 0.06 + absf(sin(a)) * 0.4))
		out["flail"] = f._finish_one()
		out["fpos"] = Vector3(0.0, 0.62, -ln * 0.5 - 1.55)
	if not glow._v[S_BODY].is_empty():
		var gm := glow._finish()
		gm.surface_set_material(0, _glow_material(Color(M.get("mark", Color(0.25, 0.95, 1.0)))))
		out["glow"] = gm
	return out


## The tracks: a dark band on each side (in the hull mesh), the cleats of the top and bottom runs (Run) and the road wheels, sprocket and idler (Run2). `zc` shifts the gear back (half-track).
static func _track_gear(out: Dictionary, hull: TankModels, ln: float, wid: float, tw: float, tt: float, zc: float) -> void:
	var h := ln * 0.5
	var hw := wid * 0.5
	var cleat := TankModels.new()
	cleat._box(S_TRIM, Vector3.ZERO, Vector3(tw + 0.05, 0.07, 0.2))
	cleat._box(S_CHROME, Vector3(0.0, 0.0, 0.0), Vector3(0.1, 0.09, 0.12))
	var road := TankModels.new()
	road._cyl(S_TRIM, Vector3.ZERO, 1.0, 1.0, 0, 12)
	road._cyl(S_CHROME, Vector3.ZERO, 0.62, 1.08, 0, 10)
	road._box(S_TRIM, Vector3.ZERO, Vector3(1.12, 0.16, 1.1))                    # a spoke bar across the hub: the turning shows
	var cl: Array = []
	var rw: Array = []
	var rr := tt * 0.36
	for sx in [-1.0, 1.0]:
		var cx: float = sx * (hw - tw * 0.5)
		hull._box(S_TRIM, Vector3(cx, tt * 0.5, zc), Vector3(tw * 0.92, tt - 0.12, ln - rr * 1.6))       # the track band (seen through the gaps)
		for run_y: float in [0.05, tt - 0.03]:
			var za := -h + 0.35 + zc
			var zb := h - 0.35 + zc
			var n := int((zb - za) / PITCH)
			for i in n:
				var z0 := za + float(i) * PITCH
				cl.append({"kind": &"cleat", "side": sx, "z0": z0, "za": za, "zb": za + float(n) * PITCH, "dir": 1.0 if run_y < 0.5 else -1.0,
					"xf": Transform3D(Basis(), Vector3(cx, run_y, z0))})
		var nw := maxi(int(ln / 1.05), 4)
		for i in nw:
			var z := lerpf(-h + rr + 0.35, h - rr - 0.35, float(i) / float(nw - 1)) + zc
			var r := rr
			var y := r + 0.05
			if i == 0 or i == nw - 1:                                             # the sprocket (front) and the idler (rear) ride higher and smaller
				r = rr * 0.82
				y = tt * 0.52
			rw.append({"kind": &"road", "side": sx, "r": r, "xf": Transform3D(Basis().scaled(Vector3(tw * 0.8, r, r)), Vector3(cx, y, z))})
	out["Run"] = {"mesh": cleat._finish_vc(), "items": cl}
	out["Run2"] = {"mesh": road._finish_vc(), "items": rw}


## Tyres on the axles of M["axles"] (shares of the length from the middle); the first M["steer_n"] axles steer.
static func _wheels(out: Dictionary, M: Dictionary, ln: float, wid: float, wr: float, hull: TankModels) -> void:
	var tyre := TankModels.new()
	tyre._cyl(S_TRIM, Vector3.ZERO, 1.0, 1.0, 0, 14)
	tyre._cyl(S_CHROME, Vector3.ZERO, 0.55, 1.06, 0, 10)
	for k in 5:                                                                   # wheel nuts round the hub: the turning shows
		var a := TAU * float(k) / 5.0
		tyre._box(S_TRIM, Vector3(0.0, cos(a) * 0.36, sin(a) * 0.36), Vector3(1.1, 0.1, 0.1))
	var items: Array = []
	var ww := wr * 0.85
	var hw := wid * 0.5
	var ns := int(M.get("steer_n", 1))
	var ax: Array = M.get("axles", [-0.32, 0.32])
	for ai in ax.size():
		var z := float(ax[ai]) * ln
		for sx in [-1.0, 1.0]:
			items.append({"kind": &"wheel", "side": sx, "r": wr, "steer": 1.0 if ai < ns else 0.0,
				"xf": Transform3D(Basis().scaled(Vector3(ww, wr, wr)), Vector3(sx * (hw - ww * 0.5), wr, z))})
			hull._box(S_BODY, Vector3(sx * (hw - ww * 0.45), wr * 2.0 + 0.06, z), Vector3(ww * 1.15, 0.08, wr * 2.4))      # the mudguard over it
	if out.has("Run2"):                                                           # a half-track: the front tyres join the road wheels (Run2: one mesh, one draw call)
		(out["Run2"]["items"] as Array).append_array(items)
	else:
		out["Run"] = {"mesh": tyre._finish_vc(), "items": items}


## Four legs from the hips at the corners of the body (the quantum walker): each swings about its hip, diagonal pairs together.
static func _legs(out: Dictionary, M: Dictionary, ln: float, wid: float) -> void:
	var hip := float(M.get("hip", 2.2))
	var leg := TankModels.new()
	leg._box(S_TRIM, Vector3(0.0, -hip * 0.25, 0.0), Vector3(0.42, hip * 0.55, 0.5))                   # thigh
	leg._box(S_CHROME, Vector3(0.0, -hip * 0.52, 0.0), Vector3(0.5, 0.3, 0.5))                         # knee
	leg._box(S_TRIM, Vector3(0.0, -hip * 0.76, 0.1), Vector3(0.32, hip * 0.5, 0.36))                   # shin
	leg._box(S_CHROME, Vector3(0.0, -hip + 0.08, 0.05), Vector3(0.8, 0.16, 1.0))                       # foot pad
	var items: Array = []
	var i := 0
	for zs in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			var ph := 0.0 if (i == 0 or i == 3) else PI
			items.append({"kind": &"leg", "side": sx, "stride": 2.6, "phase": ph, "xf": Transform3D(Basis(), Vector3(sx * (wid * 0.5 - 0.1), hip, zs * ln * 0.33))})
			i += 1
	out["Run"] = {"mesh": leg._finish_vc(), "items": items}


func _hull(kind: String, M: Dictionary, ln: float, wid: float, glow: TankModels) -> void:
	var h := ln * 0.5
	var hw := wid * 0.5
	var top := float(M.get("top", 1.5))
	var tw := float(M.get("tw", 0.62))
	var X: Array = M.get("x", [])
	match kind:
		"tank":                                                                   # a tracked hull between the tracks with a sloped glacis, fenders over the tracks
			var inner := hw - tw
			var sl := float(M.get("slope", 0.8))
			_prism(S_BODY, [Vector2(-h + 0.05, 0.5), Vector2(-h + 0.05 + sl, top), Vector2(h - 0.5, top), Vector2(h - 0.05, top - 0.35), Vector2(h - 0.05, 0.5)], -inner, inner)
			_box(S_BODY, Vector3(0.0, top - 0.42, 0.0), Vector3(wid + 0.06, 0.08, ln * 0.9))                      # the fenders over the tracks
			_box(S_TRIM, Vector3(0.0, top - 0.01, h * 0.55), Vector3(inner * 1.5, 0.04, h * 0.5))                # engine grille
			_box(S_GLASS, Vector3(-inner * 0.45, top - 0.02, -h + sl + 0.25), Vector3(0.32, 0.07, 0.16))          # driver's vision block
			_box(S_TRIM, Vector3(0.0, top - 0.25, h - 0.02), Vector3(inner * 1.6, 0.16, 0.1))                    # exhaust bar
			if X.has("skirts"):
				for sx in [-1.0, 1.0]:
					_box(S_BODY, Vector3(sx * (hw + 0.04), top - 0.66, 0.0), Vector3(0.07, 0.46, ln * 0.82))
		"box":                                                                    # a tall tracked box: carriers, engineering vehicles
			var inner2 := hw - tw
			_prism(S_BODY, [Vector2(-h + 0.05, 0.5), Vector2(-h + 0.9, top), Vector2(h - 0.1, top), Vector2(h - 0.05, 0.5)], -inner2 - 0.12, inner2 + 0.12)
			_box(S_BODY, Vector3(0.0, top * 0.62, 0.0), Vector3(wid + 0.06, 0.08, ln * 0.9))
			_box(S_TRIM, Vector3(0.0, top * 0.55, h + 0.0), Vector3(inner2 * 1.4, top * 0.6, 0.05))              # the rear door / ramp
			_box(S_GLASS, Vector3(-inner2 * 0.4, top - 0.2, -h + 0.75), Vector3(0.36, 0.12, 0.06))
			_box(S_TRIM, Vector3(inner2 * 0.4, top + 0.02, h * 0.4), Vector3(0.6, 0.05, 0.6))                    # roof hatch
		"wheeled":                                                                # an armoured car hull over the wheels: sloped nose, flat sides
			var wr := float(M.get("wr", 0.55))
			var y0 := wr * 0.9
			_prism(S_BODY, [Vector2(-h, y0 + 0.2), Vector2(-h + 0.4, y0 - 0.05), Vector2(h - 0.2, y0 - 0.05), Vector2(h, y0 + 0.3), Vector2(h, top - 0.15), Vector2(h - 0.15, top),
				Vector2(-h + 1.2, top), Vector2(-h + 0.1, y0 + 0.75)], -hw + 0.22, hw - 0.22)
			for sx in [-1.0, 1.0]:
				_box(S_GLASS, Vector3(sx * (hw - 0.23), top - 0.45, -h + 1.6), Vector3(0.04, 0.16, 0.6))
			_box(S_GLASS, Vector3(0.0, top - 0.25, -h + 1.0), Vector3(1.1, 0.18, 0.05))
			_box(S_TRIM, Vector3(0.0, y0 + 0.1, -h - 0.04), Vector3(wid * 0.7, 0.14, 0.1))
		"truck":                                                                  # a cab over the front axle, a load behind (canvas / fuel / launcher / crane)
			var wr2 := float(M.get("wr", 0.55))
			var y1 := wr2 * 1.25
			var cab := float(M.get("cab", 2.2))
			_box(S_TRIM, Vector3(0.0, y1 - 0.15, 0.0), Vector3(1.1, 0.3, ln * 0.94))                              # the chassis rails
			_prism(S_BODY, [Vector2(-h, y1), Vector2(-h, top - 0.55), Vector2(-h + 0.45, top), Vector2(-h + cab, top), Vector2(-h + cab, y1)], -hw + 0.1, hw - 0.1)
			_box(S_GLASS, Vector3(0.0, top - 0.45, -h + 0.22), Vector3(wid - 0.5, 0.5, 0.06))
			for sx in [-1.0, 1.0]:
				_box(S_GLASS, Vector3(sx * (hw - 0.09), top - 0.5, -h + cab * 0.55), Vector3(0.04, 0.45, cab * 0.45))
			_box(S_TRIM, Vector3(0.0, y1 + 0.2, -h - 0.05), Vector3(wid * 0.8, 0.3, 0.12))                       # bumper / grille
			var bz0 := -h + cab + 0.15
			var bl := ln - cab - 0.2
			var bc := bz0 + bl * 0.5
			if X.has("canvas"):
				_box(S_BODY, Vector3(0.0, y1 + 0.3, bc), Vector3(wid, 0.5, bl))
				_prism(S_BODY, [Vector2(bz0, y1 + 0.55), Vector2(bz0, top + 0.1), Vector2(bz0 + 0.3, top + 0.35), Vector2(bz0 + bl - 0.3, top + 0.35), Vector2(bz0 + bl, top + 0.1),
					Vector2(bz0 + bl, y1 + 0.55)], -hw, hw)
				for k in 4:
					_box(S_TRIM, Vector3(0.0, top + 0.37, bz0 + 0.4 + float(k) * (bl - 0.8) / 3.0), Vector3(wid + 0.02, 0.04, 0.08))       # the hoops
			elif X.has("fuel"):
				_box(S_TRIM, Vector3(0.0, y1 + 0.1, bc), Vector3(wid * 0.9, 0.2, bl))
				_cyl(S_BODY, Vector3(0.0, y1 + 0.95, bc), wid * 0.45, bl - 0.3, 2, 16)
				for zz in [bz0 + 0.12, bz0 + bl - 0.12, bc]:                              # dark end caps and a middle band: the tank reads as a round tank
					_cyl(S_TRIM, Vector3(0.0, y1 + 0.95, zz), wid * 0.47, 0.14, 2, 16)
				_box(S_CHROME, Vector3(0.0, y1 + 0.98 + wid * 0.45, bc), Vector3(0.5, 0.05, bl - 0.6))                 # the walkway on top
				for sx in [-1.0, 1.0]:
					_box(S_TRIM, Vector3(sx * (hw - 0.05), y1 + 0.3, bc), Vector3(0.1, 0.25, bl * 0.8))                 # side lockers
				_cyl(S_CHROME, Vector3(0.0, y1 + 0.95 + wid * 0.45, bc), 0.3, 0.12, 1, 10)                           # filler hatch
				_box(S_CHROME, Vector3(0.0, y1 + 0.35, bz0 + bl + 0.02), Vector3(0.9, 0.3, 0.1))                    # hose reel
			else:                                                                 # a flat bed (the launcher or the crane stands on it)
				_box(S_BODY, Vector3(0.0, y1 + 0.15, bc), Vector3(wid, 0.3, bl))
				if X.has("stab"):
					for sx in [-1.0, 1.0]:
						_box(S_TRIM, Vector3(sx * (hw + 0.1), y1 * 0.6, bz0 + bl * 0.85), Vector3(0.18, y1 * 1.2, 0.18))         # stabiliser legs
		"jeep":                                                                   # a light four-by-four: bonnet, open cab with a windscreen frame, a roll bar, a ring mount
			var wr3 := float(M.get("wr", 0.45))
			var y2 := wr3 * 1.1
			_prism(S_BODY, [Vector2(-h, y2), Vector2(-h, y2 + 0.55), Vector2(-h + 1.5, y2 + 0.7), Vector2(h, y2 + 0.7), Vector2(h, y2)], -hw + 0.12, hw - 0.12)
			_box(S_BODY, Vector3(0.0, y2 + 1.0, 0.2), Vector3(wid - 0.25, 0.08, 1.8))                            # hard top
			for sx in [-1.0, 1.0]:
				_box(S_TRIM, Vector3(sx * (hw - 0.2), y2 + 0.85, -0.65), Vector3(0.08, 0.3, 0.08))
				_box(S_TRIM, Vector3(sx * (hw - 0.2), y2 + 0.85, 1.05), Vector3(0.08, 0.3, 0.08))
			_box(S_GLASS, Vector3(0.0, y2 + 0.85, -0.7), Vector3(wid - 0.4, 0.28, 0.05))
			_box(S_TRIM, Vector3(0.0, y2 + 0.3, -h - 0.06), Vector3(wid * 0.8, 0.3, 0.1))                        # grille guard
			_box(S_TRIM, Vector3(0.0, y2 + 0.85, h - 0.1), Vector3(0.5, 0.35, 0.3))                               # jerry cans
		"mrap":                                                                   # a tall V-hulled truck: bonnet, high armoured cab with thick glass
			var wr4 := float(M.get("wr", 0.6))
			var y3 := wr4 * 1.05
			_prism(S_TRIM, [Vector2(-h + 1.4, y3), Vector2(-h + 1.6, y3 - 0.45), Vector2(h - 0.3, y3 - 0.45), Vector2(h, y3)], -hw + 0.6, hw - 0.6)    # the V under the cab
			_prism(S_BODY, [Vector2(-h, y3 + 0.1), Vector2(-h, y3 + 0.85), Vector2(-h + 1.6, y3 + 1.05), Vector2(-h + 2.1, top), Vector2(h, top), Vector2(h, y3)], -hw + 0.15, hw - 0.15)
			_box(S_GLASS, Vector3(0.0, top - 0.45, -h + 1.88), Vector3(wid - 0.6, 0.55, 0.06))
			for sx in [-1.0, 1.0]:
				_box(S_GLASS, Vector3(sx * (hw - 0.14), top - 0.5, -h + 2.8), Vector3(0.04, 0.4, 0.7))
				_box(S_TRIM, Vector3(sx * (hw - 0.05), y3 + 0.2, -h + 2.6), Vector3(0.1, 0.3, 0.5))                   # step
			_box(S_TRIM, Vector3(0.0, y3 + 0.4, -h - 0.06), Vector3(wid * 0.85, 0.5, 0.12))
			_box(S_TRIM, Vector3(0.0, top * 0.5, h + 0.02), Vector3(1.0, top * 0.6, 0.06))                       # rear door
		"boat":                                                                   # the amphibious carrier: a boat bow, a trim vane folded on the nose, water jets at the stern
			var inner3 := hw - tw
			_prism(S_BODY, [Vector2(-h - 0.3, top * 0.75), Vector2(-h + 0.5, 0.45), Vector2(h - 0.2, 0.45), Vector2(h, top * 0.6), Vector2(h - 0.1, top), Vector2(-h + 1.6, top)], -inner3 - 0.2, inner3 + 0.2)
			_box(S_BODY, Vector3(0.0, top * 0.66, 0.2), Vector3(wid + 0.08, 0.08, ln * 0.84))
			_box(S_TRIM, Vector3(0.0, top * 0.72, -h - 0.15), Vector3(wid * 0.8, 0.06, 0.6))                     # trim vane
			for sx in [-1.0, 1.0]:
				_cyl(S_CHROME, Vector3(sx * inner3 * 0.6, 0.75, h + 0.02), 0.22, 0.2, 2, 10)                      # water jets
			_box(S_GLASS, Vector3(0.0, top - 0.12, -h + 1.75), Vector3(1.2, 0.12, 0.06))
		"hover":                                                                  # the sci-fi hover tank: a flat wedge on four glowing thruster pods
			_prism(S_BODY, [Vector2(-h, 0.55), Vector2(-h + 1.8, top), Vector2(h - 0.4, top), Vector2(h, top - 0.3), Vector2(h, 0.45), Vector2(-h + 1.0, 0.3)], -hw + 0.3, hw - 0.3)
			for zs in [-1.0, 1.0]:
				for sx in [-1.0, 1.0]:
					var p := Vector3(sx * (hw - 0.45), 0.35, zs * h * 0.6)
					_box(S_TRIM, p, Vector3(0.9, 0.5, 1.6))
					glow._box(S_BODY, p - Vector3(0.0, 0.27, 0.0), Vector3(0.7, 0.04, 1.3))
			glow._box(S_BODY, Vector3(0.0, top * 0.6, -h - 0.01), Vector3(wid * 0.5, 0.06, 0.03))                # the nose light bar
			for sx in [-1.0, 1.0]:
				glow._box(S_BODY, Vector3(sx * (hw - 0.29), top * 0.7, 0.0), Vector3(0.03, 0.05, ln * 0.7))
		"walker":                                                                 # the quantum walker: a hull on four legs, a glowing core under it
			var hip := float(M.get("hip", 2.2))
			_prism(S_BODY, [Vector2(-h, hip + 0.2), Vector2(-h + 0.8, hip + 1.1), Vector2(h - 0.5, hip + 1.1), Vector2(h, hip + 0.5), Vector2(h - 0.3, hip - 0.2), Vector2(-h + 0.6, hip - 0.25)], -hw + 0.35, hw - 0.35)
			for zs in [-1.0, 1.0]:
				for sx in [-1.0, 1.0]:
					_cyl(S_CHROME, Vector3(sx * (hw - 0.1), hip, zs * ln * 0.33), 0.32, 0.4, 0, 10)            # hip joints
			glow._cyl(S_BODY, Vector3(0.0, hip - 0.3, 0.0), 0.55, 0.12, 1, 14)
			glow._box(S_BODY, Vector3(0.0, hip + 0.7, -h - 0.01), Vector3(1.0, 0.08, 0.03))
		"half":                                                                   # the half-track: a truck cab and bonnet over the front wheels, an open armoured box over the tracks
			var wr5 := float(M.get("wr", 0.5))
			var y4 := wr5 * 1.2
			_prism(S_BODY, [Vector2(-h, y4), Vector2(-h, y4 + 0.6), Vector2(-h + 1.6, y4 + 0.85), Vector2(-h + 1.8, top), Vector2(h, top), Vector2(h, 0.55), Vector2(-h + 2.0, 0.55)], -hw + 0.1, hw - 0.1)
			_box(S_TRIM, Vector3(0.0, top - 0.02, 0.6), Vector3(wid - 0.4, 0.04, ln * 0.45))                     # the open troop bay (dark floor seen from above)
			_box(S_GLASS, Vector3(0.0, top - 0.35, -h + 1.75), Vector3(wid - 0.5, 0.35, 0.05))
			_box(S_TRIM, Vector3(0.0, y4 + 0.25, -h - 0.06), Vector3(wid * 0.7, 0.4, 0.1))
	# --- extras on any hull
	if X.has("bridge"):                                                           # the folded scissor bridge on the roof
		_box(S_CHROME, Vector3(0.0, top + 0.25, 0.0), Vector3(wid + 0.3, 0.3, ln * 0.98))
		_box(S_CHROME, Vector3(0.0, top + 0.58, 0.0), Vector3(wid + 0.3, 0.3, ln * 0.98))
		for sx in [-1.0, 1.0]:
			for k in 6:
				_box(S_TRIM, Vector3(sx * (hw + 0.16), top + 0.42, -h + 0.6 + float(k) * (ln - 1.2) / 5.0), Vector3(0.04, 0.66, 0.08))
		_box(S_TRIM, Vector3(0.0, top * 0.6, -h - 0.3), Vector3(wid * 0.9, 0.2, 0.5))                           # the launch blade
	if X.has("plough"):                                                           # the mine plough at the nose
		_prism(S_TRIM, [Vector2(-h - 1.1, 0.05), Vector2(-h - 0.6, 0.85), Vector2(-h - 0.1, 0.85), Vector2(-h - 0.1, 0.4)], -hw, hw)
	if X.has("flail"):
		for sx in [-1.0, 1.0]:
			_box(S_TRIM, Vector3(sx * (hw - 0.1), 0.85, -h - 0.8), Vector3(0.14, 0.14, 1.7))                      # the flail arms
	if X.has("spade"):
		_box(S_TRIM, Vector3(0.0, 0.5, h + 0.25), Vector3(wid * 0.85, 0.7, 0.14))                                 # rear spade / blade
	if X.has("dozer"):
		_prism(S_TRIM, [Vector2(-h - 0.6, 0.05), Vector2(-h - 0.75, 0.95), Vector2(-h - 0.35, 1.0), Vector2(-h - 0.25, 0.1)], -hw - 0.1, hw + 0.1)
	if X.has("smoke"):
		for sx in [-1.0, 1.0]:
			for k in 3:
				_cyl(S_TRIM, Vector3(sx * (hw - 0.35 - float(k) * 0.18), top + 0.1, -h * 0.55), 0.07, 0.3, 2, 6)
	if X.has("stow"):
		for sx in [-1.0, 1.0]:
			_box(S_TRIM, Vector3(sx * (hw - 0.3), top + 0.12, h * 0.6), Vector3(0.5, 0.25, h * 0.5))
	if X.has("lights"):
		for sx in [-1.0, 1.0]:
			_box(S_CHROME, Vector3(sx * (hw - 0.3), top * 0.55, -h - 0.04), Vector3(0.2, 0.14, 0.05))


func _turret(T: Array, M: Dictionary, _glow: TankModels) -> void:
	match String(T[0]):
		"round":                                                                  # [round, r, h, cupola]
			_turret_round(float(T[1]), float(T[2]), float(T[3]))
		"wedge":                                                                  # [wedge, w, h, l]: a modern flat turret with a pointed front and a rear bustle
			var w := float(T[1]) * 0.5
			var th := float(T[2])
			var tl := float(T[3]) * 0.5
			_prism(S_BODY, [Vector2(-tl, th * 0.15), Vector2(-tl - 0.4, th * 0.6), Vector2(-tl + 0.3, th), Vector2(tl, th), Vector2(tl + 0.5, th * 0.8), Vector2(tl + 0.5, th * 0.15)], -w, w)
			_box(S_TRIM, Vector3(0.0, th * 0.55, -tl - 0.35), Vector3(w * 0.6, th * 0.6, 0.2))
			_cyl(S_BODY, Vector3(w * 0.45, th + 0.12, tl * 0.2), 0.3, 0.24, 1, 10)
			_cyl(S_GLASS, Vector3(w * 0.45, th + 0.25, tl * 0.2), 0.24, 0.04, 1, 10)
			_box(S_TRIM, Vector3(-w * 0.5, th + 0.15, -tl * 0.3), Vector3(0.35, 0.3, 0.45))                      # gunner's sight
			_box(S_TRIM, Vector3(0.0, th * 0.5, tl + 0.52), Vector3(w * 1.6, th * 0.5, 0.06))                     # bustle rack
		"box":                                                                    # [box, w, h, l]: the big SPG / launcher housing
			var w2 := float(T[1]) * 0.5
			var th2 := float(T[2])
			var tl2 := float(T[3]) * 0.5
			_prism(S_BODY, [Vector2(-tl2, 0.0), Vector2(-tl2 - 0.3, th2 * 0.7), Vector2(-tl2 + 0.2, th2), Vector2(tl2, th2), Vector2(tl2, 0.0)], -w2, w2)
			_box(S_TRIM, Vector3(0.0, th2 * 0.5, -tl2 - 0.32), Vector3(0.8, 0.6, 0.15))
			_cyl(S_BODY, Vector3(w2 * 0.5, th2 + 0.1, tl2 * 0.4), 0.28, 0.2, 1, 10)
			_box(S_TRIM, Vector3(-w2 * 0.5, th2 + 0.05, tl2 * 0.4), Vector3(0.5, 0.08, 0.5))
			for sx in [-1.0, 1.0]:
				_box(S_TRIM, Vector3(sx * (w2 + 0.04), th2 * 0.5, tl2 * 0.3), Vector3(0.06, th2 * 0.5, tl2))
		"open":                                                                   # [open, r, h]: an open-topped turret (tank destroyer): thin walls, a dark inside
			var r := float(T[1])
			var th3 := float(T[2])
			_prism(S_BODY, [Vector2(-r, 0.0), Vector2(-r - 0.35, th3 * 0.7), Vector2(-r, th3), Vector2(r * 0.8, th3), Vector2(r * 0.8, 0.0)], -r * 0.9, r * 0.9)
			_box(S_TRIM, Vector3(0.0, th3 + 0.005, 0.0), Vector3(r * 1.5, 0.02, r * 1.4))
			_box(S_TRIM, Vector3(0.0, th3 * 0.5, -r - 0.25), Vector3(0.7, 0.55, 0.2))
		"rws", "ring":                                                            # [rws]: a remote weapon station / [ring]: a gunner's ring with a shield
			if String(T[0]) == "rws":
				_box(S_BODY, Vector3(0.0, 0.25, 0.0), Vector3(0.75, 0.5, 0.85))
				_box(S_GLASS, Vector3(0.3, 0.42, -0.44), Vector3(0.18, 0.14, 0.04))
				_box(S_TRIM, Vector3(-0.3, 0.42, -0.3), Vector3(0.2, 0.2, 0.3))
			else:
				_cyl(S_TRIM, Vector3(0.0, 0.06, 0.0), 0.6, 0.12, 1, 14)
				_box(S_BODY, Vector3(0.0, 0.42, -0.5), Vector3(0.9, 0.6, 0.06))
				_box(S_TRIM, Vector3(0.0, 0.3, 0.0), Vector3(0.1, 0.5, 0.1))
		"cupola":                                                                 # [cupola, r]: a small MG cupola
			var r2 := float(T[1])
			_cyl(S_BODY, Vector3(0.0, 0.2, 0.0), r2, 0.4, 1, 12)
			_cyl(S_GLASS, Vector3(0.0, 0.42, 0.0), r2 * 0.8, 0.05, 1, 12)
			_box(S_TRIM, Vector3(0.0, 0.25, -r2), Vector3(0.25, 0.2, 0.15))
		"rack":                                                                   # [rack, w, h, l, rows, cols]: a rocket launcher box on a turntable
			_cyl(S_TRIM, Vector3(0.0, 0.1, 0.0), 0.8, 0.2, 1, 12)
			_box(S_TRIM, Vector3(0.0, 0.45, 0.4), Vector3(0.5, 0.6, 0.5))
		"crane":                                                                  # [crane]: the recovery crane's turntable and cab
			_cyl(S_TRIM, Vector3(0.0, 0.12, 0.0), 0.9, 0.24, 1, 14)
			_box(S_BODY, Vector3(0.55, 0.65, 0.3), Vector3(0.75, 0.9, 1.0))
			_box(S_GLASS, Vector3(0.55, 0.8, -0.21), Vector3(0.6, 0.4, 0.04))
			_box(S_TRIM, Vector3(-0.3, 0.45, 0.6), Vector3(0.7, 0.5, 0.6))                                      # the winch
		"aa":                                                                     # [aa]: a missile launcher turret with a radar
			_prism(S_BODY, [Vector2(-0.8, 0.0), Vector2(-0.6, 0.6), Vector2(0.8, 0.65), Vector2(0.9, 0.0)], -0.7, 0.7)
			_cyl(S_TRIM, Vector3(0.0, 0.95, 0.55), 0.06, 0.6, 1, 8)
			_cyl(S_CHROME, Vector3(0.0, 1.3, 0.55), 0.55, 0.05, 2, 14)
		"sci":                                                                    # [sci, r, h]: a smooth sci-fi turret with glow seams
			var r3 := float(T[1])
			var th4 := float(T[2])
			_prism(S_BODY, [Vector2(-r3 * 1.3, th4 * 0.2), Vector2(-r3 * 0.6, th4), Vector2(r3, th4), Vector2(r3 * 1.15, th4 * 0.4), Vector2(r3 * 0.6, 0.0), Vector2(-r3 * 0.8, 0.0)], -r3, r3)
			_box(S_CHROME, Vector3(0.0, th4 * 0.55, -r3 * 1.05), Vector3(r3 * 1.4, 0.05, 0.04))                  # the sensor strip
	if T.size() > 0 and String(T[0]) in ["round", "wedge", "box"] and (M.get("x", []) as Array).has("atgm"):
		_box(S_TRIM, Vector3(-float(T[1]) * 0.5 - 0.25, float(T[2]) * 0.65, 0.1), Vector3(0.35, 0.35, 1.1))   # the guided missile box on the turret side


func _gun(G: Array) -> void:
	match String(G[0]):
		"barrel":                                                                 # [barrel, length, r_tip, r, brake]
			_barrel(float(G[1]), float(G[2]), float(G[3]), bool(G[4]))
		"twin":
			_twin_barrel(float(G[1]), float(G[2]), float(G[3]))
		"mg":                                                                     # [mg, length]
			_box(S_TRIM, Vector3(0.0, 0.0, 0.1), Vector3(0.14, 0.16, 0.5))
			_cyl(S_TRIM, Vector3(0.0, 0.0, -float(G[1]) * 0.5), 0.035, float(G[1]), 2, 6)
			_box(S_TRIM, Vector3(0.12, -0.05, 0.05), Vector3(0.1, 0.14, 0.2))                                    # the ammo box
		"pods":                                                                   # [pods, n per side]: missile tubes either side of the radar mount
			for sx in [-1.0, 1.0]:
				_box(S_BODY, Vector3(sx * 0.95, 0.0, -0.2), Vector3(0.5, 0.55, 1.6))
				for k in int(G[1]):
					_cyl(S_CHROME, Vector3(sx * 0.95 + (float(k % 2) - 0.5) * 0.22, (floorf(float(k) / 2.0) - 0.5) * 0.22, -1.01), 0.09, 0.03, 2, 8)
		"rack":                                                                   # [rack, w, h, l, rows, cols]: the rocket box (the launcher's "gun")
			var w := float(G[1])
			var h := float(G[2])
			var l := float(G[3])
			_box(S_BODY, Vector3(0.0, 0.0, -l * 0.35), Vector3(w, h, l))
			for i in int(G[4]):
				for j in int(G[5]):
					_cyl(S_TRIM, Vector3(lerpf(-w * 0.38, w * 0.38, float(j) / maxf(float(G[5]) - 1.0, 1.0)), lerpf(-h * 0.35, h * 0.35, float(i) / maxf(float(G[4]) - 1.0, 1.0)), -l * 0.85 - 0.01), 0.11, 0.04, 2, 8)
		"boom":                                                                   # [boom, length]: the crane jib with its hook
			var L := float(G[1])
			_box(S_BODY, Vector3(0.0, 0.0, -L * 0.5), Vector3(0.35, 0.4, L))
			_box(S_TRIM, Vector3(0.0, -0.6, -L + 0.1), Vector3(0.04, 1.0, 0.04))
			_box(S_CHROME, Vector3(0.0, -1.15, -L + 0.1), Vector3(0.22, 0.2, 0.14))
		"rail":                                                                   # [rail, length]: the twin-rail energy gun
			var L2 := float(G[1])
			for sx in [-1.0, 1.0]:
				_box(S_TRIM, Vector3(sx * 0.16, 0.0, -L2 * 0.5), Vector3(0.1, 0.22, L2))
			_box(S_CHROME, Vector3(0.0, 0.0, 0.1), Vector3(0.5, 0.36, 0.7))
			for k in 4:
				_box(S_CHROME, Vector3(0.0, 0.0, -L2 * (0.25 + 0.2 * float(k))), Vector3(0.46, 0.28, 0.08))
