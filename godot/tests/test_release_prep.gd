extends RefCounted
## Release prep: the procedural app icon and adaptive layers exist and are wired into project settings and every export preset; the export presets keep build-only
## content out of the pack; the size-tuned imports (ORM / emission masks at 1K) are in place; docs/RELEASE.md documents the size plan.
## Reads files only (no export, no network). Run: tools/test.sh tests/test_release_prep.gd

const ICON_DIR := "res://assets/icon/"


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _png(name: String) -> Image:
	var img := Image.new()
	var bytes := FileAccess.get_file_as_bytes(ICON_DIR + name)
	if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK:
		return null
	return img


func _opt(presets: String, preset: String, key: String) -> String:
	var at := presets.find('name="%s"' % preset)
	if at < 0:
		return ""
	var end := presets.find("\nname=\"", at + 10)
	var sect := presets.substr(at, (end if end > 0 else presets.length()) - at)
	var rx := RegEx.create_from_string("(?m)^%s=\"?([^\"\\n]*)\"?" % key)
	var m := rx.search(sect)
	return m.get_string(1) if m != null else ""


func run(_host: Node) -> void:
	# icon files
	var full := _png("icon_1024.png")
	TestLib.check(full != null and full.get_width() == 1024 and full.get_height() == 1024, "icon_1024.png is a 1024 x 1024 PNG")
	if full != null:
		var opaque := true
		for p in [Vector2i(0, 0), Vector2i(1023, 0), Vector2i(512, 512), Vector2i(10, 900), Vector2i(1023, 1023)]:
			opaque = opaque and full.get_pixelv(p).a > 0.999
		TestLib.check(opaque, "the store icon has no transparency (App Store rule)")
		var core := full.get_pixel(512, 512)
		var corner := full.get_pixel(4, 4)
		TestLib.check(core.get_luminance() > corner.get_luminance() + 0.3, "the icon has a bright core on a dark field")
	for n in ["icon_fg_432.png", "icon_bg_432.png", "icon_mono_432.png"]:
		var im := _png(n)
		TestLib.check(im != null and im.get_width() == 432 and im.get_height() == 432, "%s is 432 x 432 (adaptive layer)" % n)
	var fg := _png("icon_fg_432.png")
	if fg != null:
		TestLib.check(fg.get_pixel(0, 0).a < 0.01 and fg.get_pixel(216, 216).a > 0.9, "the foreground layer is transparent at the edge and solid at the core")
		# adaptive safe zone: the outer 17 percent ring on every side holds no symbol
		var clear := true
		for i in range(0, 432, 12):
			for edge in [0, 40, 391, 431]:
				clear = clear and fg.get_pixel(i, edge).a < 0.05 and fg.get_pixel(edge, i).a < 0.05
		TestLib.check(clear, "the symbol stays inside the adaptive safe zone")
	var mono := _png("icon_mono_432.png")
	if mono != null:
		var c := mono.get_pixel(216, 216)
		TestLib.check(c.a > 0.9 and c.r > 0.95 and c.g > 0.95 and c.b > 0.95, "the monochrome layer is a white silhouette")

	# wiring
	TestLib.check(str(ProjectSettings.get_setting("application/config/icon")) == ICON_DIR + "icon_1024.png", "project icon is the 1024 PNG")
	var presets := _read("res://export_presets.cfg")
	for pr in ["Android", "Android AAB"]:
		for pair in [["launcher_icons/main_192x192", "icon_192.png"], ["launcher_icons/adaptive_foreground_432x432", "icon_fg_432.png"],
				["launcher_icons/adaptive_background_432x432", "icon_bg_432.png"], ["launcher_icons/adaptive_monochrome_432x432", "icon_mono_432.png"]]:
			var v := _opt(presets, pr, pair[0])
			TestLib.check(v == ICON_DIR + pair[1] and FileAccess.file_exists(v), "%s preset: %s -> %s" % [pr, pair[0], pair[1]])
	var ios := _opt(presets, "iOS", "application/icon_1024x1024")
	TestLib.check(ios == ICON_DIR + "icon_1024.png", "iOS preset uses the 1024 icon")
	for pr in ["Android", "Android AAB", "iOS"]:
		TestLib.check(_opt(presets, pr, "exclude_filter").contains("assets/generated/*"), "%s preset leaves the unreferenced build-time textures (assets/generated) out of the pack" % pr)

	# size tuning
	var tuned := 0
	var untuned := 0
	var d := DirAccess.open("res://assets/textures")
	if d != null:
		for f in d.get_files():
			if f.ends_with("_orm.jpg.import") or f.ends_with("_orm.png.import") or f.ends_with("_emit.png.import"):
				if _read("res://assets/textures/" + f).contains("process/size_limit=1024"):
					tuned += 1
				else:
					untuned += 1
	TestLib.check(tuned > 0 and untuned == 0, "ORM and emission masks import at 1K (%d tuned, %d not)" % [tuned, untuned])
	TestLib.check(_read("res://assets/textures/player_albedo.jpg.import").contains("compress/high_quality=true"), "hero albedo atlases stay 2K high quality")

	# tools and docs
	for rel in ["tools/release/make_icon.py", "tools/release/tune_imports.py", "tools/release/size_plan.py", "tools/pck_list.py"]:
		TestLib.check(FileAccess.file_exists("res://" + rel), "%s exists" % rel)
	var doc := _read(ProjectSettings.globalize_path("res://").path_join("../docs/RELEASE.md").simplify_path())
	TestLib.check(doc.contains("Asset Delivery") and doc.contains("size_plan.py") and doc.contains("200 MB"), "docs/RELEASE.md documents the size plan and Play Asset Delivery")
