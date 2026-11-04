extends RefCounted
## Per-tier texture loading (TextureBudget.upgrade_high): 2K ORM / emission twins (`*_2k`) for the hero and the starter car load only on HIGH; everything else stays 1K.
## Run: tools/test.sh tests/test_texture_tiers2.gd

const TEX := "res://assets/textures/"
const TWINS := ["player_orm.jpg", "player_emit.png", "car_sedan_orm.jpg", "car_sedan_paint_orm.jpg"]


func run(_h: Node) -> void:
	for f: String in TWINS:
		var twin: String = TEX + f.get_basename() + "_2k." + f.get_extension()
		TestLib.check(ResourceLoader.exists(twin), "2K twin exists: %s" % twin.get_file())
		TestLib.check(TextureBudget.high_path(TEX + f) == twin, "high_path maps %s to its twin" % f)
		var base := FileAccess.get_file_as_string(TEX + f + ".import")
		var hi := FileAccess.get_file_as_string(twin + ".import")
		TestLib.check(base.contains("process/size_limit=1024"), "%s stays a 1K import (LOW and MED memory unchanged)" % f)
		TestLib.check(hi.contains("process/size_limit=2048"), "%s twin imports at 2K" % f)
		var t := load(twin) as Texture2D
		TestLib.check(t != null and t.get_width() >= 2048, "twin loads at 2048 px (%d)" % (t.get_width() if t != null else 0))
	TestLib.check(TextureBudget.high_path(TEX + "player_albedo.jpg") == "" and TextureBudget.high_path(TEX + "drone_heavy_orm.jpg") == "", "no twin for other maps or models")
	var before := TextureBudget.high_count
	var n := TextureBudget.upgrade_high()
	TestLib.check(n >= 2, "upgrade_high replaced textures of the hero and cars (%d)" % n)
	TestLib.check(TextureBudget.high_count == before + n and TextureBudget.high_active, "counters updated")
	var inst := (load("res://assets/models/player.glb") as PackedScene).instantiate()
	var seen_2k := 0
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as BaseMaterial3D
			var o := mat.get_texture(BaseMaterial3D.TEXTURE_ROUGHNESS) if mat != null else null
			if o != null and o.get_width() >= 2048:
				seen_2k += 1
	inst.free()
	TestLib.check(seen_2k > 0, "the hero model now uses a 2K ORM map")
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	TestLib.check(src.contains("TextureBudget.upgrade_high()") and src.contains("quality >= 2"), "main.gd calls upgrade_high on the HIGH tier only")
