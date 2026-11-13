extends RefCounted
## Cars v2 (round 6, ART): the 20 glTF archetypes of tools/blender/build_cars_v2.py (procedural bodies built with bpy, shipped as glTF) and the CarV2 runtime that dresses them.
##  * every archetype loads with the node contract (Body, Body_LOD1, Body_LOD2, four empty wheel nodes at the axles: the wheels are vertices of the Details surface, so are the number plates;
##    plate / driver / engine anchors, doors), the nose at -Z, the size of its spec;
##  * triangle budgets per LOD (full detail with the four wheels, the middle LOD, the far LOD), three surfaces per body (Paint, Details, Glass) and a cabin that is really modelled;
##  * the glass is its own tinted, reflecting, see-through surface (never a flat black hole), the 12 paints with their finishes, decals (livery), dirt and wet;
##  * the damage states hooked into the vehicle scripts: GPU dents, cracked glass, torn-off bumpers / hood / trunk / doors, a swinging door, the burning stage, repair;
##  * wheels (tread normal map, rim, caliper, rolled and steered by the Details shader, shed), number plates, the near traffic meshes (HI and LO), the weight of the set on disk and in texture memory, the switch back to the older art.
## Run: tools/test.sh tests/test_cars_v2.gd   (after tools/import.sh; headless, nothing here waits on frames or timers)

const SET: Array[String] = ["sedan", "taxi", "patrol", "hatch", "coupe", "sports", "muscle", "suv", "pickup", "van", "boxtruck", "bus", "hover", "wagon", "limo", "ambulance", "armoured", "delivery",
		"garbage", "firetruck"]
## The game kinds that must wear the new set (traffic, parked cars, mission cars, police, the player's cars).
const KINDS: Array[StringName] = [&"sedan", &"sport", &"compact", &"suv", &"taxi", &"van", &"truck", &"bus", &"interceptor", &"ambulance", &"luxury", &"racer", &"pickup", &"muscle", &"hover",
		&"wagon", &"delivery", &"garbage", &"firetruck", &"armoured"]
const LOD0_TRIS := Vector2i(5500, 9500)         ## full detail with four wheels, drawn up to 26 m
const LOD1_TRIS := Vector2i(900, 2500)          ## about 1.5k - 2.2k with wheels
const LOD2_TRIS := Vector2i(180, 560)           ## the far car, about 400
const MAX_SET_BYTES := 30 * 1024 * 1024         ## the whole set of models on disk
const DETAIL_CLASS := {"fabric": 2, "leather": 3, "head": 4, "tail": 5, "indicator": 6, "reverse": 7, "plate": 12, "screen": 13, "skin": 18, "tyre": 20, "rim": 21, "brake": 22, "caliper": 23, "hub": 24}


func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	OS.set_environment("QT_CARS_V2", "")
	Game.quality = 1
	_archetypes()
	_budget_and_weight()
	_kinds_use_the_set(host)
	_glass(host)
	_paints_and_decals(host)
	_damage_states(host)
	_crash_drives_the_states(host)
	_wheels_and_lods(host)
	_near_mesh()
	_switch_back()


# --- helpers ------------------------------------------------------------------------------------------------------------------------------------------

static func _tris(mi: MeshInstance3D) -> int:
	if mi == null or mi.mesh == null:
		return 0
	var n := 0
	for s in mi.mesh.get_surface_count():
		var idx_len: int = mi.mesh.surface_get_array_index_len(s)
		n += (idx_len if idx_len > 0 else mi.mesh.surface_get_array_len(s)) / 3
	return n


static func _kind_of(archetype: String) -> StringName:
	for k: StringName in VehicleSpecs.SPECS:
		if String(VehicleSpecs.SPECS[k].get("cv2", "")) == archetype:
			return k
	return &""


## The wheel ids (1 .. 4) found in uv2.y of the wheel vertices (uv0.x >= 20) of the Details surface of a mesh, with the vertex count of each.
## Triangles of the surface called `surf_name` whose centre is on the left (x < -0.15) and on the right (x > 0.15): the shell is mirror symmetric, so are its windows.
static func _side_tris(mi: MeshInstance3D, surf_name: String) -> Vector2i:
	var l := 0
	var r := 0
	for sidx in mi.mesh.get_surface_count():
		if mi.mesh.surface_get_material(sidx).resource_name != surf_name:
			continue
		var arrs := mi.mesh.surface_get_arrays(sidx)
		var vv: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
		var ii: PackedInt32Array = arrs[Mesh.ARRAY_INDEX]
		for t in range(0, ii.size(), 3):
			var cx := (vv[ii[t]].x + vv[ii[t + 1]].x + vv[ii[t + 2]].x) / 3.0
			if cx < -0.15:
				l += 1
			elif cx > 0.15:
				r += 1
	return Vector2i(l, r)


static func _wheel_ids(mi: MeshInstance3D) -> Dictionary:
	var out := {}
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		if m == null or m.resource_name != "Details":
			continue
		var arr := mi.mesh.surface_get_arrays(s)
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
		for i in uv.size():
			if uv[i].x > 19.5:
				var k := int(roundf(uv2[i].y))
				out[k] = int(out.get(k, 0)) + 1
	return out


## The triangles of the Details surface whose vertices are wheel vertices (uv0.x >= 20).
static func _wheel_tris(mi: MeshInstance3D) -> int:
	var n := 0
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		if m == null or m.resource_name != "Details":
			continue
		var arr := mi.mesh.surface_get_arrays(s)
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for t in idx.size() / 3:
			if uv[idx[t * 3]].x > 19.5:
				n += 1
	return n


## Counts of the Details classes (uv0.x of the surface called Details), e.g. how many seat vertices the cabin has.
static func _detail_classes(mi: MeshInstance3D) -> Dictionary:
	var out := {}
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		if m == null or m.resource_name != "Details":
			continue
		var uv: PackedVector2Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV]
		for p in uv:
			var c := int(roundf(p.x))
			out[c] = int(out.get(c, 0)) + 1
	return out


static func _surface_names(mi: MeshInstance3D) -> Array[String]:
	var names: Array[String] = []
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		names.append(String(m.resource_name) if m != null else "")
	return names


# --- the models ---------------------------------------------------------------------------------------------------------------------------------------

func _archetypes() -> void:
	TestLib.check(SET.size() >= 12 and SET.size() == 20, "the set has %d archetypes (the brief asks for at least 12: hatchback, sedan, coupe, sports, muscle, SUV, pickup, van, box truck, bus, taxi, patrol, hover)" % SET.size())
	for must in ["hatch", "sedan", "coupe", "sports", "muscle", "suv", "pickup", "van", "boxtruck", "bus", "taxi", "patrol", "hover"]:
		TestLib.check(must in SET, "archetype %s is in the set" % must)
	for nm in SET:
		var model := Game.load_model("cv2_" + nm)
		TestLib.check(model != null, "%s: assets/models/cv2_%s.glb loads" % [nm, nm])
		if model == null:
			continue
		var body := model.get_node_or_null("Body") as MeshInstance3D
		var l1 := model.get_node_or_null("Body_LOD1") as MeshInstance3D
		var l2 := model.get_node_or_null("Body_LOD2") as MeshInstance3D
		TestLib.check(body != null and l1 != null and l2 != null, "%s: Body, Body_LOD1 and Body_LOD2 meshes" % nm)
		if body == null or l1 == null or l2 == null:
			model.free()
			continue
		var wheels_expected := 0 if nm == "hover" else 4                      # the quantum car floats on four thruster pods instead of wheels
		var ids := _wheel_ids(body)
		var ids1 := _wheel_ids(l1)
		TestLib.check(ids.size() == wheels_expected and ids1.size() == wheels_expected, "%s: %d wheels in the Details surface of Body and of Body_LOD1 (%s / %s)" % [nm, wheels_expected, ids.keys(), ids1.keys()])
		var kids := 0
		for wn: StringName in VehicleVisual.WHEEL_NAMES:
			var w := model.get_node_or_null(NodePath(wn)) as Node3D
			if w != null:
				kids += w.get_child_count()
		TestLib.check(kids == 0, "%s: the wheel nodes are empty (no tyre mesh of their own: no draw call per tyre)" % nm)
		TestLib.check(wheels_expected == 0 or (_wheel_tris(body) >= 3 * _wheel_tris(l1) / 2 and _wheel_tris(body) >= 4 * 250), "%s: the near wheels have real detail (%d triangles against %d at LOD1)" % [nm, _wheel_tris(body), _wheel_tris(l1)])
		# surfaces: the paint, the trim / lamps / interior, the glass; the far car is one surface
		var names := _surface_names(body)
		TestLib.check(",".join(names) == "Paint,Details,Glass", "%s: surfaces Paint, Details, Glass (%s)" % [nm, ",".join(names)])
		TestLib.check(",".join(_surface_names(l1)) == ",".join(names) and ",".join(_surface_names(l2)) == "Lod", "%s: LOD1 has the same three surfaces (one set of per-car materials), LOD2 one" % nm)
		var textured := false
		for mi: MeshInstance3D in [body, l1, l2]:
			for s in mi.mesh.get_surface_count():
				var bm := mi.mesh.surface_get_material(s) as BaseMaterial3D
				textured = textured or (bm != null and bm.albedo_texture != null)
		TestLib.check(not textured, "%s: no textures in the model (colours in the vertices, the shaders add the rest): no texture memory" % nm)
		# triangle budgets
		var t0 := _tris(body)
		var t1 := _tris(l1)
		var t2 := _tris(l2)
		print("   %-9s tris %5d / %5d / %4d" % [nm, t0, t1, t2])
		TestLib.check(t0 >= LOD0_TRIS.x and t0 <= LOD0_TRIS.y, "%s: LOD0 %d triangles with the wheels (%d - %d)" % [nm, t0, LOD0_TRIS.x, LOD0_TRIS.y])
		TestLib.check(t1 >= LOD1_TRIS.x and t1 <= LOD1_TRIS.y, "%s: LOD1 %d triangles (%d - %d)" % [nm, t1, LOD1_TRIS.x, LOD1_TRIS.y])
		TestLib.check(t2 >= LOD2_TRIS.x and t2 <= LOD2_TRIS.y, "%s: LOD2 %d triangles (%d - %d)" % [nm, t2, LOD2_TRIS.x, LOD2_TRIS.y])
		TestLib.check(t0 >= 3 * t1 and t1 >= 3 * t2, "%s: every LOD has at most a third of the one before (%d > %d > %d)" % [nm, t0, t1, t2])
		# the nose is -Z, the size is the spec's
		var kind := _kind_of(nm)
		TestLib.check(kind != &"", "%s: a game kind uses it (%s)" % [nm, kind])
		if kind != &"":
			var spec: Dictionary = VehicleSpecs.SPECS[kind]
			var box := body.get_aabb()
			var ln := float(spec["len"])
			var wd := float(spec["wid"])
			var hg := float(spec["hgt"])
			TestLib.check(absf(box.size.z - ln) <= 0.08 * ln, "%s: %.2f m long against the spec %.2f" % [nm, box.size.z, ln])
			TestLib.check(box.size.x >= 0.95 * wd and box.size.x <= 1.3 * wd, "%s: %.2f m wide (the mirrors stand out a quarter metre each side) against the spec %.2f" % [nm, box.size.x, wd])
			TestLib.check(box.size.y >= 0.8 * hg and box.size.y <= 1.25 * hg, "%s: %.2f m high against the spec %.2f" % [nm, box.size.y, hg])
		var fwd := model.get_node_or_null("PlateF") as Node3D
		var rear := model.get_node_or_null("PlateR") as Node3D
		TestLib.check(fwd != null and rear != null and fwd.position.z < -1.0 and rear.position.z > 1.0, "%s: plate anchors at the nose (-Z) and the tail" % nm)
		TestLib.check(model.get_node_or_null("Driver") != null and model.get_node_or_null("FxEngine") != null, "%s: Driver and FxEngine anchors" % nm)
		for side in ["L", "R"]:
			var dn := model.get_node_or_null("Door" + side)
			TestLib.check(dn == null or model.get_node_or_null("Door%s/Door%s_Mesh" % [side, side]) != null or model.get_node_or_null("Door%s_Mesh" % side) != null, "%s: door %s has its mesh" % [nm, side])
		# the cabin is modelled: seats, a dashboard, a screen, a driver; the lamps are separate emissive classes; the plates have recesses
		var cls := _detail_classes(body)
		var seats := int(cls.get(DETAIL_CLASS["fabric"], 0)) + int(cls.get(DETAIL_CLASS["leather"], 0))
		TestLib.check(seats >= 100, "%s: a seat / dashboard cabin is modelled (%d interior vertices)" % [nm, seats])
		TestLib.check(int(cls.get(DETAIL_CLASS["skin"], 0)) > 0, "%s: a driver sits in it" % nm)
		TestLib.check(int(cls.get(DETAIL_CLASS["head"], 0)) >= 8 and int(cls.get(DETAIL_CLASS["tail"], 0)) >= 8, "%s: headlight and tail light lenses are their own emissive classes (%d / %d vertices)" % [nm, int(cls.get(DETAIL_CLASS["head"], 0)), int(cls.get(DETAIL_CLASS["tail"], 0))])
		# glass triangles: a separate surface with real area (a windscreen, side lights)
		var glass_tris := 0
		for s in body.mesh.get_surface_count():
			if body.mesh.surface_get_material(s).resource_name == "Glass":
				glass_tris = body.mesh.surface_get_array_index_len(s) / 3
		TestLib.check(glass_tris >= 20, "%s: the glass is its own surface with %d triangles" % [nm, glass_tris])
		for lod_mi: MeshInstance3D in [body, l1]:                               # wave 112: the left half of the shell loft was one ring slot off, so the doors of the left side were glass at the coarse LODs
			var gs := _side_tris(lod_mi, "Glass")
			var ps := _side_tris(lod_mi, "Paint")
			TestLib.check(gs.x == gs.y and gs.x > 0, "%s %s: the windows are the same on both sides (%d left, %d right glass triangles)" % [nm, lod_mi.name, gs.x, gs.y])
			TestLib.check(absi(ps.x - ps.y) <= maxi(2, (ps.x + ps.y) / 40), "%s %s: the paint panels are the same on both sides (%d left, %d right triangles)" % [nm, lod_mi.name, ps.x, ps.y])
		model.free()


func _budget_and_weight() -> void:
	var total := 0
	var count := 0
	for f in DirAccess.get_files_at("res://assets/models"):
		if f.begins_with("cv2_") and f.ends_with(".glb"):
			var fa := FileAccess.open("res://assets/models/" + f, FileAccess.READ)
			if fa != null:
				total += int(fa.get_length())
				count += 1
	print("   cv2 models: %d files, %.1f MB" % [count, total / 1048576.0])
	TestLib.check(count == SET.size() + 2, "the set is %d car models plus the two near traffic cars, HI and far (found %d)" % [SET.size(), count])
	TestLib.check(total < MAX_SET_BYTES, "the whole set weighs %.1f MB (limit %.0f MB)" % [total / 1048576.0, MAX_SET_BYTES / 1048576.0])
	var tex_bytes := 0
	for path in [CarV2.FLAKE_TEX, CarV2.TREAD_TEX]:
		var t := load(path) as Texture2D
		TestLib.check(t != null and t.get_width() <= 512 and t.get_height() <= 512, "%s is a small shared map (%s)" % [path.get_file(), "%dx%d" % [t.get_width(), t.get_height()] if t != null else "missing"])
		if t != null:
			tex_bytes += int(t.get_width() * t.get_height() * 4 * 4 / 3)
	TestLib.check(tex_bytes <= 4 * 1048576, "the two shared textures take %.2f MB of texture memory at most (the tier budgets are 200 / 260 / 360 MB)" % [tex_bytes / 1048576.0])
	# (the tier limits LOW 200 / MED 260 / HIGH 360 MB themselves are held by tests/test_perf_budget.gd and tests/test_texture_tiers2.gd, which run with this set in the game)


func _kinds_use_the_set(host: Node) -> void:
	for kind in KINDS:
		TestLib.check(VehicleSpecs.SPECS.has(kind), "%s is a vehicle kind" % kind)
		var mname := CarV2.model_of(kind)
		TestLib.check(mname != "", "%s: has a Cars v2 model (%s)" % [kind, mname])
		TestLib.check(VehicleSpecs.model_names(kind)[0] == mname, "%s: tries the Cars v2 model before every older art" % kind)
	# a built car is the new art: shader materials, no CarParts generated wheels
	var holder := Node3D.new()
	host.add_child(holder)
	for kind in KINDS:
		var vis := VehicleVisual.new()
		var root := vis.build(kind, Color(0.2, 0.9, 1.0))
		holder.add_child(root)
		TestLib.check(vis.v2 != null and vis.model_name.begins_with("cv2_"), "%s: built with the Cars v2 runtime (%s)" % [kind, vis.model_name])
		if vis.v2 != null:
			var mats := [vis.v2.paint_mat, vis.v2.details_mat, vis.v2.glass_mat, vis.v2.lod_mat]
			var shaders_ok := true
			for m: ShaderMaterial in mats:
				shaders_ok = shaders_ok and m != null and m.shader != null
			TestLib.check(shaders_ok, "%s: five shader materials (paint, trim, glass, wheel, far LOD)" % kind)
			if vis.plates.size() > 0:
				TestLib.check(vis.plates.size() == 2, "%s: a plate at each end" % kind)
		root.queue_free()
	holder.queue_free()


# --- glass --------------------------------------------------------------------------------------------------------------------------------------------

func _shader_default(code: String, name: String) -> Variant:
	var re := RegEx.new()
	re.compile("uniform\\s+(?:float|vec4)\\s+" + name + "\\s*(?::\\s*\\w+\\s*)?=\\s*(?:vec4\\()?([-0-9.,\\s]+)\\)?\\s*;")
	var m := re.search(code)
	if m == null:
		return null
	var parts := m.get_string(1).split(",", false)
	if parts.size() == 1:
		return parts[0].to_float()
	var v: Array[float] = []
	for p in parts:
		v.append(p.to_float())
	return v


func _glass(host: Node) -> void:
	var vis := VehicleVisual.new()
	var root := vis.build(&"sedan", Color(0.2, 0.9, 1.0))
	host.add_child(root)
	var glass := vis.v2.glass_mat
	var code := glass.shader.code
	var opacity := float(_shader_default(code, "opacity"))
	var reflect_k := float(_shader_default(code, "reflect_k"))
	var tint: Array = _shader_default(code, "tint")
	print("   glass: opacity %.2f reflect %.2f tint %s" % [opacity, reflect_k, tint])
	TestLib.check(code.contains("blend_mix") and code.contains("ALPHA"), "the glass blends over what is behind it (the cabin shows through)")
	TestLib.check(opacity > 0.2 and opacity < 0.85, "the pane is see-through: opacity %.2f" % opacity)
	TestLib.check(tint.size() >= 3 and float(tint[2]) > float(tint[0]) and float(tint[0]) + float(tint[1]) + float(tint[2]) > 0.12, "the tint is blue-grey and not black (%.2f %.2f %.2f)" % [tint[0], tint[1], tint[2]])
	TestLib.check(reflect_k >= 0.4 and code.contains("street_env") and code.contains("EMISSION"), "the glass reflects the street (reflection strength %.2f), so it is never a flat black hole" % reflect_k)
	TestLib.check(code.contains("crack"), "the glass cracks (shader uniform)")
	# the dark liner behind the pane shows the cabin: there are seats and a dashboard in the Details surface, and the cabin light at night shows through it
	vis.v2.set_interior_glow(1.0)
	TestLib.check(is_equal_approx(float(glass.get_shader_parameter(&"interior")), 1.0), "the cabin glow at night reaches the glass")
	vis.v2.set_interior_glow(1.8)
	TestLib.check(float(glass.get_shader_parameter(&"interior")) <= 1.0, "a big cabin glow is clamped (a bus window is not a lamp)")
	# a cracked pane is lighter than a clean one (the shader mixes the crack web in)
	vis.v2.crack_glass(0.9, Vector3(1.0, 1.0, 0.0), Vector3(1.85, 1.46, 4.75))
	TestLib.check(is_equal_approx(float(glass.get_shader_parameter(&"crack")), 0.9) and (glass.get_shader_parameter(&"crack_at") as Vector4).w > 0.5, "cracking the glass drives the shader")
	root.queue_free()


# --- paints, decals, dirt and wet ------------------------------------------------------------------------------------------------------------------------

func _paints_and_decals(host: Node) -> void:
	TestLib.check(VehicleSpecs.COLORS.size() == 12, "12 paint colours (%d)" % VehicleSpecs.COLORS.size())
	TestLib.check(CarV2.FINISH.size() == VehicleSpecs.COLORS.size(), "every paint has its finish (flake, metal, gloss, pearl)")
	var distinct := true
	for i in VehicleSpecs.COLORS.size():
		for j in range(i + 1, VehicleSpecs.COLORS.size()):
			var a: Color = VehicleSpecs.COLORS[i]
			var b: Color = VehicleSpecs.COLORS[j]
			if Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length() < 0.08:
				distinct = false
	TestLib.check(distinct, "the 12 paints are told apart")
	var metal_ok := true
	for f: Dictionary in CarV2.FINISH:
		metal_ok = metal_ok and float(f["metal"]) <= 0.45 and float(f["flake"]) > 0.0 and float(f["rough"]) < 0.5
	TestLib.check(metal_ok, "every finish is a lacquer with flake and a clear gloss, metal stays at or under 0.45 (no mirror paint)")
	var vis := VehicleVisual.new()
	var root := vis.build(&"sport", Color(0.2, 0.9, 1.0))
	host.add_child(root)
	var seen := {}
	for i in VehicleSpecs.COLORS.size():
		var c: Color = VehicleSpecs.COLORS[i]
		vis.set_paint(c)
		var p := vis.v2.paint_mat.get_shader_parameter(&"paint") as Color
		TestLib.check(p.r > 0.0 or p.g > 0.0 or p.b > 0.0, "paint %d reaches the shader" % i)
		TestLib.check(vis.get_paint() == c and float(vis.v2.paint_mat.get_shader_parameter(&"flake")) > 0.0, "paint %d: colour and metallic flake" % i)
		var st := vis.paint_state()
		TestLib.check(float(st["clearcoat"]) > 0.9 and float(st["metallic"]) <= 0.45, "paint %d: clear coat on, metal %.2f" % [i, float(st["metallic"])])
		seen["%d,%d,%d" % [int(p.r * 60.0), int(p.g * 60.0), int(p.b * 60.0)]] = true
	TestLib.check(seen.size() >= 11, "the shader gets %d different colours for 12 paints" % seen.size())
	# decals: the shader's livery modes with their colour
	for mode in [0, 1, 2, 3, 4, 5, 6]:
		vis.v2.set_livery(mode, Color(0.9, 0.1, 0.1))
		TestLib.check(int(vis.v2.paint_mat.get_shader_parameter(&"livery")) == mode, "livery decal %d" % mode)
	vis.v2.set_livery(0)
	# dirt and wet: dirt dulls, rain glosses (the numbers the paint shader reads)
	var dull := float(vis.paint_state()["roughness"])
	vis.v2.set_dirt(0.9)
	TestLib.check(is_equal_approx(float(vis.v2.paint_mat.get_shader_parameter(&"dirt")), 0.9) and is_equal_approx(float(vis.v2.details_mat.get_shader_parameter(&"wheel_dirt")), 0.9), "dirt reaches the paint and the tyres")
	vis.v2.set_dirt(0.0)
	vis.set_wet(1.0)
	TestLib.check(float(vis.paint_state()["roughness"]) < dull, "a wet car is glossier (%.2f < %.2f)" % [float(vis.paint_state()["roughness"]), dull])
	vis.set_wet(0.0)
	# randomised look: some cars are dirty, a few wear stripes
	var dirty := 0
	var striped := 0
	for i in 60:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + i
		vis.v2.set_livery(0)
		vis.v2.set_dirt(0.0)
		vis.v2.randomize_look(rng)
		dirty += 1 if vis.v2.dirt > 0.3 else 0
		striped += 1 if int(vis.v2.paint_mat.get_shader_parameter(&"livery")) > 0 else 0
	TestLib.check(dirty > 0 and dirty < 40, "some cars are filthy, most are clean (%d of 60)" % dirty)
	TestLib.check(striped > 0 and striped < 60, "a sports car wears racing stripes now and then (%d of 60)" % striped)
	# the taxi and the patrol car come with their liveries
	var taxi := VehicleVisual.new()
	host.add_child(taxi.build(&"taxi", Color(0.2, 0.9, 1.0)))
	TestLib.check(taxi.v2 != null and int(taxi.v2.paint_mat.get_shader_parameter(&"livery")) == int(VehicleSpecs.SPECS[&"taxi"]["livery"]), "a taxi has the checker band")
	var cop := VehicleVisual.new()
	host.add_child(cop.build(&"interceptor", Color(0.2, 0.9, 1.0)))
	TestLib.check(cop.v2 != null and int(cop.v2.paint_mat.get_shader_parameter(&"livery")) == int(VehicleSpecs.SPECS[&"interceptor"]["livery"]), "a patrol car has the emergency band")
	root.queue_free()
	taxi.model.get_parent().queue_free()
	cop.model.get_parent().queue_free()


# --- damage states --------------------------------------------------------------------------------------------------------------------------------------

func _damage_states(host: Node) -> void:
	var car := Vehicle.new()
	host.add_child(car)
	car.setup(&"sedan", null)
	car.activate(Vector3(0, 0, 0), 0.0)
	var v2 := car.visual.v2
	TestLib.check(v2 != null, "a sedan in play is a Cars v2 car")
	if v2 == null:
		car.queue_free()
		return
	TestLib.check(v2.dents.is_empty() and v2.cracks == 0.0 and v2.parts_lost == 0 and not v2.burning, "a fresh car is whole")
	# dents: vertex displacement on the GPU, at most six, nearby hits merge
	car.visual.add_dent(Vector3(0.3, 0.7, -2.3), Vector3(0.0, 0.0, 1.0), 0.6)
	TestLib.check(v2.dents.size() == 1 and int(v2.paint_mat.get_shader_parameter(&"dent_n")) == 1, "a hit makes a dent that the paint shader receives")
	car.visual.add_dent(Vector3(0.35, 0.7, -2.3), Vector3(0.0, 0.0, 1.0), 0.5)
	TestLib.check(v2.dents.size() == 1, "a second hit on the same spot deepens the dent instead of adding one")
	for i in 9:
		car.visual.add_dent(Vector3(0.9 if i % 2 == 0 else -0.9, 0.5 + 0.1 * i, -2.0 + 0.5 * i), Vector3(-1.0 if i % 2 == 0 else 1.0, 0.0, 0.0), 0.4)
	TestLib.check(v2.dents.size() == CarV2.MAX_DENTS and int(v2.paint_mat.get_shader_parameter(&"dent_n")) == CarV2.MAX_DENTS, "dents are capped at %d (the oldest goes)" % CarV2.MAX_DENTS)
	var dent_a := v2.paint_mat.get_shader_parameter(&"dent_a") as PackedVector4Array
	TestLib.check(dent_a.size() == CarV2.MAX_DENTS and dent_a[0].w > 0.3, "the dent radius and place are uniforms of the shader")
	# cracked glass
	car.visual.crack_glass(0.5, Vector3(0.0, 1.0, 0.0))
	var c1 := v2.cracks
	car.visual.crack_glass(0.95, Vector3(1.0, 1.0, 0.0))
	TestLib.check(c1 > 0.0 and v2.cracks > c1 and float(v2.glass_mat.get_shader_parameter(&"crack")) > c1, "the glass cracks further with the damage (%.2f, then %.2f)" % [c1, v2.cracks])
	# parts: bumpers, hood, trunk, doors come off by where the hit landed
	var dims := Vector3(1.85, 1.46, 4.75)
	var p1 := v2.tear_part_at(Vector3(0.0, 0.4, -2.3), dims)
	TestLib.check(p1 in [&"bumper_f", &"hood"] and v2.part_gone(p1), "a hit on the nose takes the front bumper or the hood (%s)" % p1)
	var p2 := v2.tear_part_at(Vector3(0.0, 0.4, -2.3), dims)
	TestLib.check(p2 != p1 and p2 in [&"bumper_f", &"hood"], "the next one takes the other (%s)" % p2)
	var p3 := v2.tear_part_at(Vector3(0.9, 0.7, 0.0), dims)
	TestLib.check(p3 in [&"door_fr", &"door_rr"], "a hit on the right flank takes a right door (%s)" % p3)
	var p4 := v2.tear_part_at(Vector3(0.0, 0.5, 2.3), dims)
	TestLib.check(p4 in [&"bumper_r", &"trunk"], "a hit on the tail takes the rear bumper or the trunk lid (%s)" % p4)
	var mask := int(float(v2.paint_mat.get_shader_parameter(&"part_lost")))
	TestLib.check(mask == (v2.parts_lost | v2.parts_open) and v2.parts_lost != 0, "the torn-off parts are a bit mask the shader collapses (%d)" % mask)
	TestLib.check(not v2.lose_part(p1) and not v2.lose_part(&"no_such_part"), "a part can only be lost once, an unknown part is refused")
	# the burning stage of the vehicle script reaches the model
	car.debug_damage(0.3)
	TestLib.check(car.dmg_state == Vehicle.state_for(car.hp, car.max_hp) and not v2.burning, "a hurt car smokes at most (stage %d) and its engine bay does not glow" % car.dmg_state)
	car.debug_damage(0.97)
	TestLib.check(car.dmg_state == 2 and v2.burning and float(v2.details_mat.get_shader_parameter(&"fire")) > 0.5, "a nearly dead car burns: the dark engine bay glows (stage %d)" % car.dmg_state)
	TestLib.check(v2.scuff > 0.0 and float(v2.paint_mat.get_shader_parameter(&"scuff")) > 0.0, "the paint is scuffed and sooty with the damage")
	# repair puts everything back
	car.visual.repair()
	TestLib.check(v2.dents.is_empty() and v2.cracks == 0.0 and v2.parts_lost == 0 and v2.parts_open == 0 and int(v2.paint_mat.get_shader_parameter(&"dent_n")) == 0, "a repair puts the body, the glass and the parts back")
	TestLib.check(not v2.burning and float(v2.details_mat.get_shader_parameter(&"fire")) == 0.0 and v2.scuff == 0.0, "...puts the fire out and wipes the soot off the paint")
	TestLib.check(float(v2.glass_mat.get_shader_parameter(&"crack")) == 0.0, "the glass is clean again")
	# a door swings: the shell's own door is hidden meanwhile, the door node shows
	var dn := v2.set_door_open(1.0, true)
	TestLib.check(dn != null and v2.parts_open != 0, "the right door can swing open (a hinged panel node)")
	var swing_mask := int(float(v2.paint_mat.get_shader_parameter(&"part_lost")))
	TestLib.check(swing_mask != 0, "the shell door is hidden while the door node swings")
	v2.set_door_open(1.0, false)
	TestLib.check(v2.parts_open == 0 and int(float(v2.paint_mat.get_shader_parameter(&"part_lost"))) == 0, "the door closes again")
	# every archetype with doors has door nodes; a lost door cannot swing
	v2.lose_part(&"door_fr")
	TestLib.check(v2.set_door_open(1.0, true) == null, "a door that was torn off cannot swing")
	car.queue_free()


## The closing speed (m/s) whose Vehicle.crash_fraction is at least `frac`.
static func _speed_for(frac: float) -> float:
	var v := 5.0
	while v < 60.0 and Vehicle.crash_fraction(v) < frac:
		v += 0.5
	return v


## Vehicle.crash() is where VehicleManager.collide_cars, the near traffic and the road traffic all end: a crash must reach every damage state of the new art (dents, cracks, torn parts, a lost
## wheel, the burning engine bay) without anything calling the visual by hand.
func _crash_drives_the_states(host: Node) -> void:
	var car := Vehicle.new()
	host.add_child(car)
	car.setup(&"sedan", null)
	car.activate(Vector3(0, 0, 0), 0.0)
	var v2 := car.visual.v2
	if v2 == null:
		TestLib.check(false, "crash states: the sedan is a Cars v2 car")
		car.queue_free()
		return
	var nose := Vector3(0.0, 0.7, -2.3)
	var v_dent := _speed_for(maxf(VehicleSpecs.DENT_MIN, 0.05) + 0.02)                  # the closing speed that makes a dent, cracks the glass (frac > 0.28), tears a panel (frac > 0.38)
	var v_glass := _speed_for(0.34)
	var v_part := _speed_for(0.46)
	car._dist = 4.0                                                        # a car near the camera shows its damage (far ones skip the dents)
	var lost0 := car.crash(car.max_hp * 0.0 + 3.0, car.to_global(nose), Vector3(0.0, 0.0, 1.0), INF)
	TestLib.check(lost0 == 0.0 and v2.dents.is_empty() and v2.cracks == 0.0, "a bump at walking pace leaves the car whole")
	car.impact_t = 9.0
	car.last_impact = 0.0
	var hp0 := car.hp
	var lost1 := car.crash(v_dent, car.to_global(nose), Vector3(0.0, 0.0, 1.0), INF)
	TestLib.check(lost1 > 0.0 and car.hp < hp0 and v2.dents.size() >= 1 and int(v2.paint_mat.get_shader_parameter(&"dent_n")) >= 1, "a hard hit dents the panel the shader draws (%.0f hp lost, %d dents)" % [lost1, v2.dents.size()])
	car.impact_t = 9.0
	car.last_impact = 0.0
	car.crash(v_glass, car.to_global(nose), Vector3(0.0, 0.0, 1.0), INF)
	TestLib.check(v2.cracks > 0.0 and float(v2.glass_mat.get_shader_parameter(&"crack")) > 0.0, "a harder one cracks the glass (%.2f)" % v2.cracks)
	car.impact_t = 9.0
	car.last_impact = 0.0
	var parts_before := v2.parts_lost
	car.crash(v_part, car.to_global(nose), Vector3(0.0, 0.0, 1.0), INF)
	TestLib.check(v2.parts_lost != parts_before or car.dead, "a violent one tears a part off (mask %d), the Details / Paint / Glass shaders collapse it" % v2.parts_lost)
	TestLib.check(car.hp <= car.max_hp * 0.8 and car.dmg_state >= 0, "the hull took the damage (%.0f of %.0f hp, state %d)" % [car.hp, car.max_hp, car.dmg_state])
	# the engine bay burns once the hull is nearly gone
	car.repair()
	TestLib.check(v2.dents.is_empty() and v2.cracks == 0.0 and v2.parts_lost == 0 and v2.wheels_lost == 0, "a repair puts the car back together (dents, glass, parts, wheels)")
	car.hp = car.max_hp * 0.12
	car._hurt(1.0)
	TestLib.check(car.dmg_state == 2 and v2.burning and float(v2.details_mat.get_shader_parameter(&"fire")) > 0.5, "a hull below 15 percent burns: the engine bay glows (state %d)" % car.dmg_state)
	car.queue_free()
	# two cars in a head-on crash through the manager's own collision response: both are dented
	var a := Vehicle.new()
	var b := Vehicle.new()
	host.add_child(a)
	host.add_child(b)
	a.setup(&"sedan", null)
	b.setup(&"suv", null)
	a.activate(Vector3(300.0, 0.0, 300.0), 0.0)
	b.activate(Vector3(300.0, 0.0, 296.0), PI)
	var mgr := VehicleManager.new()
	host.add_child(mgr)
	a._dist = 4.0
	b._dist = 4.0
	a.impact_t = 9.0
	b.impact_t = 9.0
	a.crash(v_glass, Vector3(300.0, 0.7, 298.0), Vector3(0.0, 0.0, 1.0), VehicleSpecs.mass_of(&"suv"))
	b.crash(v_glass, Vector3(300.0, 0.7, 298.0), Vector3(0.0, 0.0, -1.0), VehicleSpecs.mass_of(&"sedan"))
	TestLib.check(a.visual.v2.dents.size() >= 1 and b.visual.v2.dents.size() >= 1, "a car-to-car crash dents both (%d / %d dents)" % [a.visual.v2.dents.size(), b.visual.v2.dents.size()])
	mgr.queue_free()
	a.queue_free()
	b.queue_free()


# --- wheels and the LOD ranges --------------------------------------------------------------------------------------------------------------------------

func _wheels_and_lods(host: Node) -> void:
	var vis := VehicleVisual.new()
	var root := vis.build(&"muscle", Color(0.2, 0.9, 1.0))
	host.add_child(root)
	var v2 := vis.v2
	var dm := v2.details_mat
	var tread := dm.get_shader_parameter(&"tread") as Texture2D
	TestLib.check(tread != null and tread.get_width() >= 64, "the tyres share the tread normal map (%s)" % ("%dx%d" % [tread.get_width(), tread.get_height()] if tread != null else "missing"))
	TestLib.check(dm.shader.code.contains("tread") and dm.shader.code.contains("caliper_color") and dm.shader.code.contains("rim_tint") and dm.shader.code.contains("wheel_roll"), "the Details shader has the tread, rim, caliper and hub classes and rolls the wheels")
	var cls := _detail_classes(v2.body)
	TestLib.check(cls.has(DETAIL_CLASS["tyre"]) and cls.has(DETAIL_CLASS["rim"]) and cls.has(DETAIL_CLASS["brake"]) and cls.has(DETAIL_CLASS["caliper"]) and cls.has(DETAIL_CLASS["hub"]),
			"a full wheel is a tyre with tread uvs, a rim, a brake disc, a caliper and a hub (classes %s)" % [cls.keys()])
	var pivots: PackedVector3Array = dm.get_shader_parameter(&"wheel_c")
	TestLib.check(pivots.size() == 4 and pivots[0].x < 0.0 and pivots[1].x > 0.0 and pivots[0].z < pivots[2].z, "the four wheel pivots are the wheel nodes: left and right, front before rear (%s)" % [pivots])
	# the tyres turn with the car: the wheel nodes (their rotation is what the effects and the tests read) and the shader uniforms
	var before := vis.wheels[0].rotation.x
	vis.spin(2.0, 0.3)
	TestLib.check(vis.wheels.size() == 4 and not is_equal_approx(vis.wheels[0].rotation.x, before), "the wheels spin")
	TestLib.check(not is_equal_approx(float(dm.get_shader_parameter(&"wheel_roll")), 0.0) and is_equal_approx(float(dm.get_shader_parameter(&"wheel_steer")), 0.3), "...and the Details shader rolls and steers the tyre vertices")
	# a wheel that flies off collapses into its hub, a repair puts it back
	vis.shed_wheel(2)
	TestLib.check(vis.wheel_shed(2) and (int(float(dm.get_shader_parameter(&"wheel_lost"))) & 4) != 0 and v2.wheels_lost == 4, "a wheel that flew off is hidden in the shader")
	vis.restore_wheels()
	TestLib.check(vis.wheels_lost() == 0 and int(float(dm.get_shader_parameter(&"wheel_lost"))) == 0, "...and a repair puts it back")
	var plate_cls := cls.get(DETAIL_CLASS["plate"], 0) as int
	TestLib.check(plate_cls >= 8 and dm.get_shader_parameter(&"plate_seed") != null and dm.shader.code.contains("GLYPH"), "the number plates are patches of the Details surface that print QT and five digits (%d plate vertices)" % plate_cls)
	# LOD ranges: Body to 26 m, Body_LOD1 to 64 m, Body_LOD2 beyond, the tyres swap at 22 m
	TestLib.check(is_equal_approx(v2.body.visibility_range_end, CarV2.LOD1_DIST) and is_equal_approx(v2.lod1.visibility_range_begin, CarV2.LOD1_DIST), "the near body hands over to the middle LOD at %.0f m with no gap" % CarV2.LOD1_DIST)
	TestLib.check(is_equal_approx(v2.lod1.visibility_range_end, CarV2.LOD2_DIST) and is_equal_approx(v2.lod2.visibility_range_begin, CarV2.LOD2_DIST), "the middle LOD hands over to the far car at %.0f m" % CarV2.LOD2_DIST)
	TestLib.check(CarV2.LOD1_DIST >= 24.0 and CarV2.LOD1_DIST <= 30.0, "the full detail car shows up to about 25 m")
	TestLib.check(_wheel_ids(v2.lod1).size() == 4 and _wheel_ids(v2.lod2).is_empty(), "the middle LOD has coarse wheels of its own, the far car has them baked into its one surface")
	# the far car casts the shadow (the near mesh does not: one cheap proxy), and a twin without a render layer is what the wet street reflects
	var shadow := v2.body.get_node_or_null(NodePath(ShadowProxy.PROXY_NAME)) as MeshInstance3D
	TestLib.check(shadow != null and shadow.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and v2.body.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the 400 triangle mesh is the shadow caster")
	TestLib.check(vis.mirror_meshes.size() == 1 and vis.mirror_meshes[0].layers == 0, "the street reflection gets the small mesh on no render layer")
	# lights: the headlamp cones at night and the brake light push
	vis.set_lights(0.9, 0.7, 1.0)
	var beams := root.get_node_or_null("Beams") as MeshInstance3D
	TestLib.check(beams != null and beams.mesh != null and beams.mesh.get_surface_count() > 0 and beams.visibility_range_end >= 60.0, "the headlights have light cones that show from far away at night")
	TestLib.check(is_equal_approx(float(v2.details_mat.get_shader_parameter(&"head")), 0.9) and is_equal_approx(float(v2.details_mat.get_shader_parameter(&"tail")), 0.7), "the lamp lenses glow with the lights (emissive classes in the trim shader)")
	v2.set_indicator(true)
	v2.set_reverse(true)
	v2.set_siren(0.2, true)
	TestLib.check(v2.details_mat.get_shader_parameter(&"ind") != null and v2.details_mat.get_shader_parameter(&"reverse_lamp") != null, "indicators and the reverse lamp are driven")
	root.queue_free()
	# the patrol car: its siren lights flash
	var cop := VehicleVisual.new()
	var croot := cop.build(&"interceptor", Color(0.2, 0.9, 1.0))
	host.add_child(croot)
	cop.v2.set_siren(0.2, true)
	var s_on := float(cop.v2.details_mat.get_shader_parameter(&"siren_on"))
	cop.v2.set_siren(0.2, false)
	TestLib.check(s_on > 0.5 and float(cop.v2.details_mat.get_shader_parameter(&"siren_on")) < 0.5, "a patrol car's roof bar flashes only with the siren on")
	croot.queue_free()


# --- the near traffic cars -----------------------------------------------------------------------------------------------------------------------------------

## Both near meshes are ONE surface each (one draw call per MultiMesh): the far car (LO, the sedan shell and four octagonal wheels, about 360 triangles) and the HI car (the sedan shell, the box
## truck shell, four wheels and a few extras, about 1.2k triangles, drawn by a handful of instances within about 20 m). Tags in uv0.x, region / wheel id in uv0.y, ao and part in uv2.
const NEAR_TAGS := [0.0, 0.25, 0.3, 0.45, 0.52, 0.55, 0.65, 0.72, 0.78, 0.84, 0.9, 0.95, 1.0]


func _near_mesh_of(model_name: String) -> MeshInstance3D:
	var root := Game.load_model(model_name)
	TestLib.check(root != null, "assets/models/%s.glb loads" % model_name)
	if root == null:
		return null
	var mi: MeshInstance3D = null
	for n in root.find_children("*", "MeshInstance3D", true, false):
		mi = n as MeshInstance3D
		break
	if mi != null:
		root.remove_child(mi)
		mi.owner = null
		root.free()
	return mi


func _near_mesh() -> void:
	for name_hi: Array in [["cv2_near", false], ["cv2_near_hi", true]]:
		var model_name: String = name_hi[0]
		var hi: bool = name_hi[1]
		var mi := _near_mesh_of(model_name)
		TestLib.check(mi != null and mi.mesh.get_surface_count() == 1, "%s: one surface, so the whole fleet of this mesh is one draw call" % model_name)
		if mi == null:
			continue
		var tris := _tris(mi)
		if hi:
			TestLib.check(tris >= 900 and tris <= 1500, "%s: %d triangles (about 1.2k: two bodies, four wheels, extras)" % [model_name, tris])
		else:
			TestLib.check(tris >= 250 and tris <= 520, "%s: %d triangles (about 360: it carries the many far cars)" % [model_name, tris])
		var arr := mi.mesh.surface_get_arrays(0)
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
		TestLib.check(uv.size() == uv2.size() and uv2.size() > 100, "%s: both uv sets (tag / wheel id, occlusion / part)" % model_name)
		var tags := {}
		var parts := {}
		var wheel_ids := {}
		var bad_tag := 0
		for i in uv.size():
			var t := snappedf(uv[i].x, 0.01)
			tags[t] = int(tags.get(t, 0)) + 1
			var known := false
			for a: float in NEAR_TAGS:
				known = known or is_equal_approx(t, a)
			if not known:
				bad_tag += 1
			var part := int(roundf(uv2[i].y))
			parts[part] = int(parts.get(part, 0)) + 1
			if part == 6:
				wheel_ids[int(roundf(uv[i].y))] = true
		TestLib.check(bad_tag == 0 and tags.has(0.0) and tags.has(0.25) and tags.has(1.0) and tags.has(0.45) and tags.has(0.65), "%s: the surface tags of the near shaders (paint, glass, tyre, wheel face, tail lamp; tags %s)" % [model_name, tags.keys()])
		TestLib.check(wheel_ids.size() == 4 and wheel_ids.has(1) and wheel_ids.has(4), "%s: every wheel vertex carries its wheel id 1 .. 4 in uv0.y (the shader places the wheels by the table of the kind: %s)" % [model_name, wheel_ids.keys()])
		var vtx: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var gl := Vector2i.ZERO
		var pa := Vector2i.ZERO
		for t in range(0, idx.size(), 3):
			if int(roundf(uv2[idx[t]].y)) != 0:
				continue
			var cx := (vtx[idx[t]].x + vtx[idx[t + 1]].x + vtx[idx[t + 2]].x) / 3.0
			if absf(cx) < 0.3:
				continue
			var tg := snappedf(uv[idx[t]].x, 0.01)
			if is_equal_approx(tg, 0.25):
				gl += Vector2i(1, 0) if cx < 0.0 else Vector2i(0, 1)
			elif is_equal_approx(tg, 0.0):
				pa += Vector2i(1, 0) if cx < 0.0 else Vector2i(0, 1)
		TestLib.check(gl.x == gl.y and gl.x > 0 and pa.x == pa.y, "%s: the sedan shell is the same on both sides (glass %d / %d, paint %d / %d triangles: the left doors were glass once)" % [model_name, gl.x, gl.y, pa.x, pa.y])
		if hi:
			TestLib.check(parts.has(0) and parts.has(1) and parts.has(2) and parts.has(3) and parts.has(4) and parts.has(5) and parts.has(6), "%s: sedan shell, box truck shell, taxi sign, patrol light bar, spoiler, ambulance bar and wheels (parts %s)" % [model_name, parts.keys()])
		else:
			TestLib.check(parts.has(0) and parts.has(6) and not parts.has(1), "%s: the sedan shell and the wheels only (parts %s)" % [model_name, parts.keys()])
		mi.free()
	var shared := NearTraffic.car_mesh()
	var shared_hi := NearTraffic.car_mesh_hi()
	TestLib.check(shared != null and shared.get_surface_count() == 1 and shared_hi != null and shared_hi.get_surface_count() == 1, "NearTraffic gives each MultiMesh a one surface car")
	TestLib.check(_tris_of_mesh(shared_hi) > 2 * _tris_of_mesh(shared), "the HI car (%d triangles) has the detail the far car (%d) has not" % [_tris_of_mesh(shared_hi), _tris_of_mesh(shared)])
	# the anchors of the kinds (written by tools/blender/carv2/near.py into the shader include): twelve kinds, the box kinds on the box truck body
	var inc := FileAccess.get_file_as_string("res://assets/shaders/prop_nearcar_tables.gdshaderinc")
	TestLib.check(inc.contains("C_TAB[108]") and inc.contains("B_TAB[132]") and inc.contains("WHEEL_BASE"), "the near shaders have an anchor table row for each of the twelve kinds")
	var mask_ok := inc.contains("FAMILY_B_MASK = %d" % _box_mask())
	TestLib.check(mask_ok, "the box kinds of the shader (van, truck, bus, ambulance, delivery) are the box kinds of NearTraffic (mask %d)" % _box_mask())
	var hi_sh := FileAccess.get_file_as_string("res://assets/shaders/prop_nearcar_hi.gdshader")
	var lo_sh := FileAccess.get_file_as_string("res://assets/shaders/prop_nearcar.gdshader")
	TestLib.check(hi_sh.contains("near_wheel") and hi_sh.contains("near_b(") and lo_sh.contains("near_wheel") and not lo_sh.contains("near_b("), "the HI shader places two bodies, the far shader one; both place the wheels")
	TestLib.check(HiRoute.new().ok(), "NearTraffic routes the cars within the HI range to the HI MultiMesh and the rest to the far one")


func _box_mask() -> int:
	var m := 0
	for k: int in NearTraffic.BOX_KINDS:
		m |= 1 << k
	return m


## The routing of NearTraffic (the HI MultiMesh holds the nearest cars, the far one the rest; an empty HI node is hidden): checked on a bare NearTraffic, no scene.
class HiRoute:
	func ok() -> bool:
		var nt := NearTraffic.new()
		nt.build(null)
		nt._cam_ok = true
		nt._cam_pos = Vector2(0.0, 0.0)
		nt.quality = 1
		nt._nw_hi = 0
		var near_ok := nt._wants_hi(3.0, 4.0, 0) and not nt._wants_hi(40.0, 0.0, 0)
		var box_far := nt._wants_hi(NearTraffic.HI_R[1] + 4.0, 0.0, 7) and not nt._wants_hi(NearTraffic.HI_R[1] + 4.0, 0.0, 0)      # a box kind keeps the HI mesh a little farther
		nt._nw_hi = NearTraffic.HI_CAP[1]
		var capped := not nt._wants_hi(3.0, 4.0, 0)
		# nearest first: with more cars in range than slots, the next step gives the HI mesh to the nearest ones whatever the order they are written in
		nt._hi_cand.clear()
		nt._hi_thr2 = INF
		nt._nw_hi = 0
		var dists: Array[float] = [14.0, 3.0, 11.0, 6.0, 9.0, 4.0]                 # metres, 6 cars in range of MED (15 m), 4 slots
		for d in dists:
			nt._wants_hi(d, 0.0, 0)
		nt._update_hi_threshold()                                                  # (the step does this when it starts)
		var picks := 0
		var nearest_ok := true
		nt._nw_hi = 0
		for d in dists:
			var hi := nt._wants_hi(d, 0.0, 0)
			picks += 1 if hi else 0
			nearest_ok = nearest_ok and (hi == (d <= 9.0))                          # 3, 4, 6 and 9 m are the four nearest
		nt._nw_hi = 0
		var order_free := nt._wants_hi(3.0, 0.0, 0) and not nt._wants_hi(14.0, 0.0, 0) and not nt._wants_hi(11.0, 0.0, 0)
		return near_ok and box_far and capped and nt.mm_hi.instance_count == NearTraffic.HI_MAX and picks == NearTraffic.HI_CAP[1] and nearest_ok and order_free


static func _tris_of_mesh(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var idx_len: int = m.surface_get_array_index_len(s)
		n += (idx_len if idx_len > 0 else m.surface_get_array_len(s)) / 3
	return n


# --- the older art stays a fallback ---------------------------------------------------------------------------------------------------------------------------

func _switch_back() -> void:
	OS.set_environment("QT_CARS_V2", "0")
	TestLib.check(not CarV2.enabled() and CarV2.model_of(&"sedan") == "", "QT_CARS_V2=0 brings the older art back (for before / after captures and the legacy tests)")
	var vis := VehicleVisual.new()
	var root := vis.build(&"sedan", Color(0.2, 0.9, 1.0))
	TestLib.check(vis.v2 == null and not vis.model_name.begins_with("cv2_"), "...and a built sedan is not a Cars v2 car then (%s)" % vis.model_name)
	root.free()
	OS.set_environment("QT_CARS_V2", "")
	TestLib.check(CarV2.enabled() and CarV2.model_of(&"sedan") == "cv2_sedan", "switched on again")
