extends Node
func _ready() -> void:
	var img := Image.load_from_file("res://assets/textures/hero_suit_albedo.jpg")
	HeroSuit.part_count()
	for pn in ["boot_r", "sole_r", "pack", "thigh_r"]:
		var parts := HeroSuit._parts
		for p: Dictionary in parts:
			if p["name"] == pn:
				var uv: PackedVector2Array = p["uv"]
				var idx: PackedInt32Array = p["idx"]
				var acc := Color(0, 0, 0)
				var n := 0
				for t in idx.size() / 3:
					var c := (uv[idx[t * 3]] + uv[idx[t * 3 + 1]] + uv[idx[t * 3 + 2]]) / 3.0
					var px := img.get_pixel(clampi(int(c.x * img.get_width()), 0, img.get_width() - 1), clampi(int(c.y * img.get_height()), 0, img.get_height() - 1))
					acc += px.srgb_to_linear()
					n += 1
				print("PROBE ", pn, " tris ", n, " mean linear ", Color(acc.r / n, acc.g / n, acc.b / n), " uv range ", uv[0], uv[uv.size() - 1])
	get_tree().quit()
