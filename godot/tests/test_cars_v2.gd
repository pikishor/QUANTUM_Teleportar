extends RefCounted
## Cars v2 (round 6, ART): the 20 glTF archetypes of tools/blender/build_cars_v2.py (procedural bodies built with bpy, shipped as glTF) and the CarV2 runtime that dresses them.
##  * every archetype loads with the node contract (Body, Body_LOD1, Body_LOD2, four wheels with two tyre meshes, plate / driver / engine anchors, doors), the nose at -Z, the size of its spec;
##  * triangle budgets per LOD (full detail with the four wheels, the middle LOD, the far LOD), three surfaces per body (Paint, Details, Glass) and a cabin that is really modelled;
##  * the glass is its own tinted, reflecting, see-through surface (never a flat black hole), the 12 paints with their finishes, decals (livery), dirt and wet;
##  * the damage states hooked into the vehicle scripts: GPU dents, cracked glass, torn-off bumpers / hood / trunk / doors, a swinging door, the burning stage, repair;
##  * wheels (tread normal map, rim, caliper), the near traffic mesh, the weight of the set on disk and in texture memory, the switch back to the older art.
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
const DETAIL_CLASS := {"fabric": 2, "leather": 3, "head": 4, "tail": 5, "indicator": 6, "reverse": 7, "plate": 12, "screen": 13, "skin": 18}


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


## The wheel tyre meshes of a model: {"lod0": [MeshInstance3D x4], "lod1": [...]}.
static func _tyres(model: Node3D) -> Dictionary:
	var out := {"lod0": [], "lod1": []}
	for wn: StringName in VehicleVisual.WHEEL_NAMES:
		var w := model.get_node_or_null(NodePath(wn)) as Node3D
		if w == null:
			continue
		for c in w.get_children():
			var mi := c as MeshInstance3D
			if mi == null:
				continue
			(out["lod1"] if String(mi.name).contains("LOD1") else out["lod0"]).append(mi)
	return out


static func _wheel_tris(list: Array) -> int:
	var n := 0
	for mi: MeshInstance3D in list:
		n += _tris(mi)
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
		var tyres := _tyres(model)
		var wheels_expected := 0 if nm == "hover" else 4                      # the quantum car floats on four thruster pods instead of wheels
		TestLib.check(tyres["lod0"].size() == wheels_expected and tyres["lod1"].size() == wheels_expected, "%s: %d wheels with a full and a coarse tyre mesh (%d / %d)" % [nm, wheels_expected, tyres["lod0"].size(), tyres["lod1"].size()])
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
		var t0 := _tris(body) + _wheel_tris(tyres["lod0"])
		var t1 := _tris(l1) + _wheel_tris(tyres["lod1"])
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
	TestLib.check(count == SET.size() + 1, "the set is %d car models plus the near traffic car (found %d)" % [SET.size(), count])
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
			var mats := [vis.v2.paint_mat, vis.v2.details_mat, vis.v2.glass_mat, vis.v2.wheel_mat, vis.v2.lod_mat]
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
	TestLib.check(is_equal_approx(float(vis.v2.paint_mat.get_shader_parameter(&"dirt")), 0.9) and is_equal_approx(float(vis.v2.wheel_mat.get_shader_parameter(&"dirt")), 0.9), "dirt reaches the paint and the tyres")
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


# --- wheels and the LOD ranges --------------------------------------------------------------------------------------------------------------------------

func _wheels_and_lods(host: Node) -> void:
	var vis := VehicleVisual.new()
	var root := vis.build(&"muscle", Color(0.2, 0.9, 1.0))
	host.add_child(root)
	var v2 := vis.v2
	TestLib.check(v2.wheel_meshes.size() == 8, "four wheels with a full and a coarse tyre mesh each (%d meshes)" % v2.wheel_meshes.size())
	var wm := v2.wheel_mat
	var tread := wm.get_shader_parameter(&"tread") as Texture2D
	TestLib.check(tread != null and tread.get_width() >= 64, "the tyres share the tread normal map (%s)" % ("%dx%d" % [tread.get_width(), tread.get_height()] if tread != null else "missing"))
	TestLib.check(wm.shader.code.contains("tread") and wm.shader.code.contains("caliper_color") and wm.shader.code.contains("rim_tint"), "the wheel shader has tread, rim, caliper and hub classes")
	var full := v2.wheel_meshes[0]
	var arrays := full.mesh.surface_get_arrays(0)
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var classes := {}
	for p in uv2:
		classes[int(roundf(p.x))] = true
	TestLib.check(uv.size() > 100 and classes.has(0) and classes.has(1) and classes.has(2) and classes.has(3) and classes.has(4), "a full wheel is a tyre with tread uvs, a rim, a brake disc, a caliper and a hub (classes %s)" % [classes.keys()])
	TestLib.check(_tris(full) > 3 * _tris(v2.wheel_meshes[1]) / 2 and _tris(full) >= 250, "the near wheel has real detail (%d triangles against %d for the coarse one)" % [_tris(full), _tris(v2.wheel_meshes[1])])
	# the tyres turn with the car
	var before := vis.wheels[0].rotation.x
	vis.spin(2.0, 0.3)
	TestLib.check(vis.wheels.size() == 4 and not is_equal_approx(vis.wheels[0].rotation.x, before), "the wheels spin")
	# LOD ranges: Body to 26 m, Body_LOD1 to 64 m, Body_LOD2 beyond, the tyres swap at 22 m
	TestLib.check(is_equal_approx(v2.body.visibility_range_end, CarV2.LOD1_DIST) and is_equal_approx(v2.lod1.visibility_range_begin, CarV2.LOD1_DIST), "the near body hands over to the middle LOD at %.0f m with no gap" % CarV2.LOD1_DIST)
	TestLib.check(is_equal_approx(v2.lod1.visibility_range_end, CarV2.LOD2_DIST) and is_equal_approx(v2.lod2.visibility_range_begin, CarV2.LOD2_DIST), "the middle LOD hands over to the far car at %.0f m" % CarV2.LOD2_DIST)
	TestLib.check(CarV2.LOD1_DIST >= 24.0 and CarV2.LOD1_DIST <= 30.0, "the full detail car shows up to about 25 m")
	TestLib.check(is_equal_approx(v2.wheel_meshes[0].visibility_range_end, CarV2.WHEEL_LOD1) and is_equal_approx(v2.wheel_meshes[1].visibility_range_begin, CarV2.WHEEL_LOD1), "the tyre mesh swaps to the coarse one at %.0f m" % CarV2.WHEEL_LOD1)
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


# --- the near traffic car ----------------------------------------------------------------------------------------------------------------------------------

func _near_mesh() -> void:
	var root := Game.load_model("cv2_near")
	TestLib.check(root != null, "assets/models/cv2_near.glb loads (the car of the near traffic MultiMesh)")
	if root == null:
		return
	var mi: MeshInstance3D = null
	for n in root.find_children("*", "MeshInstance3D", true, false):
		mi = n as MeshInstance3D
		break
	TestLib.check(mi != null and mi.mesh.get_surface_count() == 1, "one surface: the whole near traffic fleet is one draw call")
	if mi != null:
		var tris := _tris(mi)
		TestLib.check(tris >= 300 and tris <= 700, "%d triangles (about 430)" % tris)
		var arr := mi.mesh.surface_get_arrays(0)
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var tags := {}
		var wheel_ok := true
		for p in uv:
			tags[snappedf(p.x, 0.05)] = tags.get(snappedf(p.x, 0.05), 0) + 1
			if p.x > 0.4 and p.x < 0.5 and absf(p.y) < 0.05:
				wheel_ok = false
		var allowed := [0.0, 0.25, 0.45, 0.5, 0.55, 0.65, 0.8, 1.0]
		var tags_ok := true
		for t: float in tags.keys():
			var known := false
			for a: float in allowed:
				known = known or is_equal_approx(t, a)
			tags_ok = tags_ok and known
		TestLib.check(tags.has(0.0) and tags.has(0.25) and tags.has(1.0) and tags_ok, "the surface tags of prop_nearcar.gdshader (paint, glass, tail lamps; tags %s)" % [tags.keys()])
		TestLib.check(wheel_ok, "every tyre vertex carries the wheel centre height in uv.y (the wheels keep their size when the body is stretched)")
		var shared := NearTraffic.car_mesh()
		TestLib.check(shared != null and shared.get_surface_count() == 1, "NearTraffic.car_mesh() gives the MultiMesh a one surface car")
		TestLib.check(_tris_of_mesh(shared) == tris, "...and it is this one (%d triangles)" % _tris_of_mesh(shared))
	root.free()


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
