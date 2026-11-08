extends RefCounted
## Real scanned materials in the city (wave 99): Poly Haven CC0 sets packed into the city shaders' slot format (tools/materials/pack_world_materials.py), tier wiring on the ground,
## facades and interiors, the LOW single-tap path, memory estimates, sky probes, fallbacks and licence credits. Run: tools/test.sh tests/test_scanned_world.gd

const ORIGIN := Vector3(900.0, 600.0, 900.0)
const LUMA := Vector3(0.2126, 0.7152, 0.0722)
const SLOT_NAMES: Array[String] = ["road_market", "road_foundry", "road_slums", "road_towers", "walk_market", "walk_foundry", "walk_slums", "walk_towers", "brick", "wall", "metal", "corr"]
const FLAT_NAMES: Array[String] = ["i_plaster", "i_brick", "i_tile", "i_check", "i_concrete", "i_wood"]


func run(host: Node) -> void:
	_test_files()
	_test_pixels()
	_test_credits()
	_test_fallback_switch()
	await _test_city_tiers(host)
	await _test_interior(host)
	_test_sky()


func _test_files() -> void:
	var missing: Array[String] = []
	var packed := true
	for n in SLOT_NAMES:
		for sfx in ["a", "n"]:
			var p := "res://assets/textures/world_%s_%s.webp" % [n, sfx]
			if not ResourceLoader.exists(p):
				missing.append(p)
			else:
				var imp := FileAccess.get_file_as_string(p + ".import")
				packed = packed and imp.contains("compress/mode=2") and imp.contains("mipmaps/generate=true") and imp.contains("compress/normal_map=2")
	for n in FLAT_NAMES:
		var p := "res://assets/textures/world_%s_a.webp" % n
		if not ResourceLoader.exists(p):
			missing.append(p)
	TestLib.check(missing.is_empty(), "all 12 slot sets and 6 interior sets are imported (missing %s)" % str(missing))
	TestLib.check(packed, "scanned slot textures are VRAM compressed with mipmaps, packed normals stay colour textures")
	TestLib.check(SurfaceTextures.has_world(SurfaceTextures.ROAD_LAYERS) and SurfaceTextures.has_world(SurfaceTextures.WALK_SCAN_LAYERS), "road and sidewalk district layers are all present")
	for n in ["dusk", "night", "overcast"]:
		TestLib.check(ResourceLoader.exists("res://assets/textures/sky_probe_%s.png" % n), "sky probe %s is imported" % n)
	var ok_order := true
	for k in SurfaceTextures.WORLD_SLOTS:
		ok_order = ok_order and SurfaceTextures.scanned_slot(k)
	TestLib.check(ok_order, "brick, wall, metal and corrugated slots are served by scanned sets")


## The packed files are detail modulators: median luminance near 0.5 (the shader multiplies the world's palette by 2 x RGB), roughness in alpha, a packed normal that is mostly flat.
func _test_pixels() -> void:
	var bad: Array[String] = []
	for n in SLOT_NAMES + FLAT_NAMES:
		var p := "res://assets/textures/world_%s_a.webp" % n
		var img := Image.load_from_file(ProjectSettings.globalize_path(p))
		if img == null or img.is_empty() or img.get_width() != 1024 or img.get_height() != 1024:
			bad.append(n + ":size")
			continue
		var lums: Array[float] = []
		var amean := 0.0
		var cnt := 0
		for y in range(0, 1024, 16):
			for x in range(0, 1024, 16):
				var c := img.get_pixel(x, y)
				lums.append(Vector3(c.r, c.g, c.b).dot(LUMA))
				amean += c.a
				cnt += 1
		lums.sort()
		var med: float = lums[lums.size() / 2]
		amean /= float(cnt)
		var lo := 0.2 if n.begins_with("i_") else 0.36      # interior sets carry the cavity baked in: a little darker than the slot modulators
		if med < lo or med > 0.62 or amean < 0.12 or amean > 1.0:
			bad.append("%s median %.2f rough %.2f" % [n, med, amean])
	TestLib.check(bad.is_empty(), "modulators have median luminance about 0.5 and a roughness channel (%s)" % str(bad))
	var nbad: Array[String] = []
	for n in SLOT_NAMES:
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/textures/world_%s_n.webp" % n))
		if img == null or img.is_empty():
			nbad.append(n)
			continue
		var rx := 0.0
		var ry := 0.0
		var cav := 0.0
		var cnt := 0
		for y in range(0, 1024, 32):
			for x in range(0, 1024, 32):
				var c := img.get_pixel(x, y)
				rx += c.r
				ry += c.g
				cav += c.b
				cnt += 1
		rx /= cnt
		ry /= cnt
		cav /= cnt
		if absf(rx - 0.5) > 0.08 or absf(ry - 0.5) > 0.08 or cav < 0.5:
			nbad.append("%s %.2f %.2f %.2f" % [n, rx, ry, cav])
	TestLib.check(nbad.is_empty(), "packed normals are flat on average (RG about 0.5) with the cavity in B (%s)" % str(nbad))


func _test_credits() -> void:
	var root := ProjectSettings.globalize_path("res://").path_join("..")
	var src := FileAccess.get_file_as_string(root.path_join("art_sources/polyhaven_pbr/SOURCE.md"))
	var lic := FileAccess.get_file_as_string(root.path_join("art_sources/polyhaven_pbr/LICENSE.txt"))
	var third := FileAccess.get_file_as_string(root.path_join("docs/THIRD_PARTY.md"))
	if src == "":
		TestLib.check(true, "(licence files not shipped with this checkout: credits check skipped)")
		return
	var manifest := JSON.parse_string(FileAccess.get_file_as_string("res://tools/materials/world_materials.json")) as Dictionary
	var sets: Dictionary = manifest["sets"]
	var undocumented: Array[String] = []
	for k in sets:
		var slug: String = sets[k]["slug"]
		if not src.contains(slug) or not third.contains(slug):
			undocumented.append(slug)
	TestLib.check(undocumented.is_empty(), "every scanned set is credited in SOURCE.md and docs/THIRD_PARTY.md (%s)" % str(undocumented))
	TestLib.check(lic.contains("CC0") and third.contains("Poly Haven"), "the CC0 licence text is kept with the pack and Poly Haven is credited")


## QT_SCANNED=0 (before / after captures, and the safety valve) puts every procedural set back without touching anything else.
func _test_fallback_switch() -> void:
	OS.set_environment("QT_SCANNED", "0")
	var off := not SurfaceTextures.scanned_roads() and not SurfaceTextures.scanned_slot("brick") and not SurfaceTextures.scanned_interiors() and SurfaceTextures.estimate_low_bytes() == 0
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/interior_surface.gdshader")
	var bound := SurfaceTextures.apply_interior(m, 1)
	OS.unset_environment("QT_SCANNED")
	TestLib.check(off and not bound and is_equal_approx(float(m.get_shader_parameter(&"scan_k")), 0.0), "QT_SCANNED=0 disables every scanned set (procedural fallback)")
	var back := SurfaceTextures.scanned_roads() and SurfaceTextures.scanned_interiors()
	TestLib.check(back, "and the scanned sets come back with it unset")


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


func _test_city_tiers(host: Node) -> void:
	var scene := load("res://scenes/world.tscn") as PackedScene
	var city := scene.instantiate() as City
	host.add_child(city)
	await TestLib.frames(host, 4)
	var ground: ShaderMaterial = city._ground.material
	var lite: ShaderMaterial = city._ground.material_lite
	var bmat: ShaderMaterial = city._building_mat
	for level in [2, 1, 0]:
		city.set_quality(level)
		await TestLib.frames(host, 2)
		var brick = bmat.get_shader_parameter(&"srf_brick_a")
		var wall = bmat.get_shader_parameter(&"srf_wall_a")
		TestLib.check(brick is Texture2D and (brick as Texture2D).resource_path.contains("world_brick_a") == (level > 0) and wall != null, "quality %d: facade brick / wall taps are %s" % [level, "the scanned 1K sets" if level > 0 else "the half-size scanned albedo (LOW)"])
		var lo := float(bmat.get_shader_parameter(&"srf_lo"))
		TestLib.check(is_equal_approx(lo, 1.0 if level == 0 else 0.0), "quality %d: facade LOW single-tap flag is %s" % [level, "on" if level == 0 else "off"])
		if level > 0:
			var arr = ground.get_shader_parameter(&"srf_roadv_a")
			var flag := float(ground.get_shader_parameter(&"srf_roadv"))
			var single = ground.get_shader_parameter(&"srf_road_a")
			TestLib.check((arr != null and is_equal_approx(flag, 1.0)) or (arr == null and is_equal_approx(flag, 0.0) and single != null), "quality %d: road is the district array, or the single procedural set when the data cannot be read" % level)
			TestLib.check(is_equal_approx(float(lite.get_shader_parameter(&"srf_lo")), 0.0) and lite.get_shader_parameter(&"srf_roadv_a") == null, "quality %d: the lite ground holds nothing" % level)
		else:
			var lflag := float(lite.get_shader_parameter(&"srf_lo"))
			TestLib.check(_is_headless() or is_equal_approx(lflag, 1.0), "LOW: the lite ground taps the scanned asphalt and pavement albedo once")
			TestLib.check(ground.get_shader_parameter(&"srf_roadv_n") == null and bmat.get_shader_parameter(&"srf_brick_n") == null, "LOW: no scanned normal map is resident")
	var e1 := SurfaceTextures.estimate_bytes(1)
	var e2 := SurfaceTextures.estimate_bytes(2)
	var e0 := SurfaceTextures.estimate_low_bytes()
	TestLib.check(e0 > 0 and e0 < 8_000_000 and e1 > e0 and e1 < 40_000_000 and e2 > e1 and e2 < 90_000_000,
			"scanned texture memory estimate: LOW %.1f MB (limit 8), MED %.1f MB (limit 40), HIGH %.1f MB (limit 90); the tier limits 200 / 260 / 360 MB stay with the perf gate" % [e0 / 1e6, e1 / 1e6, e2 / 1e6])
	city.set_quality(1)
	city.queue_free()
	await TestLib.frames(host, 2)


## An interior built in the real pipeline binds the scanned floors and walls to its ONE surface material.
func _test_interior(host: Node) -> void:
	InteriorGen.clear_cache()
	var it := InteriorGen.build(&"bar", 3, ORIGIN, 1) as Interior
	host.add_child(it)
	await TestLib.frames(host, 2)
	var m := it.actor_material()
	var good := is_equal_approx(float(m.get_shader_parameter(&"scan_k")), 1.0)
	for u in SurfaceTextures.INTERIOR:
		good = good and m.get_shader_parameter(StringName(u)) != null
	TestLib.check(good, "an interior binds the six scanned surface samplers (scan_k 1)")
	var names := []
	for d in m.shader.get_shader_uniform_list():
		names.append(String(d["name"]))
	TestLib.check(names.has("scan_brick") and names.has("scan_wood") and names.has("scan_plaster") and names.has("scan_tile") and names.has("scan_check") and names.has("scan_concrete"), "interior_surface.gdshader declares the six scan samplers")
	it.queue_free()
	await TestLib.frames(host, 1)


func _test_sky() -> void:
	var dusk := DayNight.probe_weights(18.5, 0.0)
	var night := DayNight.probe_weights(1.0, 0.0)
	var noon_over := DayNight.probe_weights(12.0, 0.9)
	var noon_clear := DayNight.probe_weights(12.0, 0.0)
	TestLib.check(dusk.x > 0.9 and night.y > 0.9 and night.x < 0.01 and noon_over.z > 0.3 and noon_clear.length() < 0.01, "probe weights: dusk at sunset, night after dark, overcast under cloud, none at a clear noon")
	var look := DayNight.sky_look(1.0, &"clear", 0)
	TestLib.check(look.has("probe_w") and float(look["probe_amount"]) > 0.0 and float(look["probe_amount"]) <= 0.6, "sky look carries the probe weights and a restrained amount on every tier")
	var sh := load("res://assets/shaders/sky.gdshader") as Shader
	var names := []
	for d in sh.get_shader_uniform_list():
		names.append(String(d["name"]))
	TestLib.check(names.has("probe_dusk") and names.has("probe_night") and names.has("probe_over") and names.has("probe_w"), "sky shader declares the probe samplers")
