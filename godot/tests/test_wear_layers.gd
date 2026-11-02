extends RefCounted
## Wear layers (headless): rain streaks, soot, edge wear, AO baked into the facade textures; tyre marks and puddle bodies in the road decal mask.
## Run: tools/test.sh tests/test_wear_layers.gd

func _img(path: String) -> Image:
	var t := load(path) as Texture2D
	if t == null:
		return null
	var im := t.get_image()
	if im != null and im.is_compressed():
		im.decompress()
	return im


func _lum_profile(im: Image, vertical: bool) -> float:
	# variance of the line means at 64 samples: streaks (vertical) give a high spread of COLUMN means and a low spread of ROW means
	var n := 64
	var w := im.get_width()
	var h := im.get_height()
	var means := PackedFloat32Array()
	for i in n:
		var acc := 0.0
		for j in n:
			var x := (i * w / n) if vertical else (j * w / n)
			var y := (j * h / n) if vertical else (i * h / n)
			acc += im.get_pixel(x, y).r
		means.append(acc / n)
	var mu := 0.0
	for m in means:
		mu += m
	mu /= n
	var v := 0.0
	for m in means:
		v += (m - mu) * (m - mu)
	return v / n


func run(_host: Node) -> void:
	for nm in ["brick", "concrete"]:
		var a := _img("res://assets/textures/surface_%s_albedo.png" % nm)
		var nrm := _img("res://assets/textures/surface_%s_normal.png" % nm)
		TestLib.check(a != null and nrm != null, "%s set loads" % nm)
		if a == null or nrm == null:
			continue
		var cols := _lum_profile(a, true)
		var rows := _lum_profile(a, false)
		TestLib.check(cols > 0.0 and rows > 0.0, "%s albedo has tonal variation" % nm)
		TestLib.check(nm != "brick" or rows > cols * 1.2, "%s carries vertical wear: row means vary more than column means (%.5f vs %.5f)" % [nm, rows, cols])
		var lo := 1.0
		for i in 256:
			lo = minf(lo, nrm.get_pixel((i * 37) % nrm.get_width(), (i * 91) % nrm.get_height()).b)
		TestLib.check(lo < 0.9, "%s cavity / AO channel darkens somewhere (min %.2f)" % [nm, lo])
	var d := _img("res://assets/textures/surface_decals.png")
	TestLib.check(d != null, "decal mask loads")
	if d != null:
		var oil := 0
		var pud := 0
		for i in 4096:
			var px := d.get_pixel((i * 53) % d.get_width(), (i * 29) % d.get_height())
			if px.r > 0.5:
				oil += 1
			if px.g > 0.45:
				pud += 1
		TestLib.check(oil > 20, "decal R holds oil and tyre marks (%d of 4096)" % oil)
		TestLib.check(pud > 20, "decal G holds puddle bodies and tide marks (%d of 4096)" % pud)
	for sh in ["ground_core", "building_core"]:
		TestLib.check(FileAccess.file_exists("res://assets/shaders/%s.gdshaderinc" % sh), "%s include present" % sh)
